"""Checks the LookML project without a Looker instance.

1. Parses the model, views and dashboards.
2. Checks every ${TABLE}.column exists in BigQuery and every ${field} reference resolves.
3. Checks every dashboard element and filter points at an existing explore and fields.
4. Builds the SQL Looker would run for each element (dimensions, measures, filtered measures)
   and dry-runs it in BigQuery, so a broken expression fails here instead of in a dashboard.

Usage: python validate_lookml.py [--project flow-eed16]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import lkml
import yaml
from google.cloud import bigquery

ROOT = Path(__file__).parent
TIMEFRAMES_DATETIME = {
    "raw": "{x}", "time": "{x}", "minute": "DATETIME_TRUNC({x}, MINUTE)", "hour": "DATETIME_TRUNC({x}, HOUR)",
    "date": "DATE({x})", "week": "DATE_TRUNC(DATE({x}), WEEK(MONDAY))", "day_of_week": "FORMAT_DATETIME('%A', {x})",
    "hour_of_day": "EXTRACT(HOUR FROM {x})",
}
TIMEFRAMES_TIMESTAMP = {
    **TIMEFRAMES_DATETIME,
    "minute": "TIMESTAMP_TRUNC({x}, MINUTE)", "hour": "TIMESTAMP_TRUNC({x}, HOUR)",
    "date": "DATE({x}, 'America/Mexico_City')", "day_of_week": "FORMAT_TIMESTAMP('%A', {x})",
}

errors: list[str] = []


def fail(msg: str):
    errors.append(msg)


class View:
    def __init__(self, raw: dict, constants: dict):
        self.name = raw["name"]
        self.table = raw["sql_table_name"].strip().rstrip(";").strip()
        for k, v in constants.items():
            self.table = self.table.replace("@{" + k + "}", v)
        self.fields: dict[str, dict] = {}
        for d in raw.get("dimensions", []):
            self.fields[d["name"]] = {**d, "kind": "dimension"}
        for g in raw.get("dimension_groups", []):
            frames = TIMEFRAMES_DATETIME if g.get("datatype") == "datetime" else TIMEFRAMES_TIMESTAMP
            for tf in g.get("timeframes", []):
                if tf not in frames:
                    fail(f"{self.name}.{g['name']}: timeframe {tf} not handled by the validator")
                    continue
                self.fields[f"{g['name']}_{tf}"] = {
                    "name": f"{g['name']}_{tf}", "kind": "dimension",
                    "sql": frames[tf].format(x=f"({g['sql'].strip().rstrip(';')})"),
                }
        for m in raw.get("measures", []):
            self.fields[m["name"]] = {**m, "kind": "measure"}

    def expr(self, name: str, alias: str, seen=()) -> str:
        if name in seen:
            raise ValueError(f"{self.name}.{name}: circular reference")
        f = self.fields.get(name)
        if f is None:
            raise KeyError(f"{self.name}: unknown field {name}")
        if f.get("type") == "location":
            return f"CONCAT(CAST({self._sub(f['sql_latitude'], alias, seen + (name,))} AS STRING), ',', " \
                   f"CAST({self._sub(f['sql_longitude'], alias, seen + (name,))} AS STRING))"
        if f["kind"] == "measure":
            return self._measure(f, alias, seen + (name,))
        return self._sub(f["sql"], alias, seen + (name,))

    def _sub(self, sql: str, alias: str, seen) -> str:
        sql = sql.strip().rstrip(";").strip()
        sql = sql.replace("${TABLE}", alias)
        return re.sub(r"\$\{(\w+)\}", lambda m: f"({self.expr(m.group(1), alias, seen)})", sql)

    def _measure(self, m: dict, alias: str, seen) -> str:
        t = m.get("type")
        cond = " AND ".join(self._filter(k, v, alias, seen) for flt in m.get("filters", []) for k, v in flt.items()) \
            if m.get("filters") else None
        if t == "count":
            return f"COUNTIF({cond})" if cond else "COUNT(*)"
        inner = self._sub(m["sql"], alias, seen)
        if t in ("number", "date_time"):
            return inner
        agg = {"sum": "SUM", "average": "AVG", "max": "MAX", "min": "MIN", "count_distinct": "COUNT(DISTINCT"}[t]
        value = f"IF({cond}, {inner}, NULL)" if cond else inner
        return f"{agg}({value}))" if agg.endswith("DISTINCT") else f"{agg}({value})"

    def _filter(self, field: str, value: str, alias: str, seen) -> str:
        col = self.expr(field, alias, seen)
        negate = value.startswith("-")
        literal = value[1:] if negate else value
        return f"({col} {'!=' if negate else '='} '{literal}')"


def load():
    constants = {c["name"]: c["value"] for c in lkml.load((ROOT / "manifest.lkml").read_text()).get("constants", [])}
    views = {}
    for p in sorted((ROOT / "views").glob("*.view.lkml")):
        for raw in lkml.load(p.read_text()).get("views", []):
            views[raw["name"]] = View(raw, constants)
    model = lkml.load((ROOT / "cdmx_mobility.model.lkml").read_text())
    explores = {e["name"]: e.get("from", e["name"]) for e in model.get("explores", [])}
    dashboards = []
    for p in sorted((ROOT / "dashboards").glob("*.dashboard.lookml")):
        dashboards.extend(yaml.safe_load(p.read_text()))
    return constants, views, explores, dashboards


def check_columns(client: bigquery.Client, views: dict[str, View]):
    for v in views.values():
        try:
            cols = {f.name for f in client.get_table(v.table.strip("`")).schema}
        except Exception as exc:  # noqa: BLE001
            fail(f"view {v.name}: table {v.table} not readable: {exc}")
            continue
        for f in v.fields.values():
            for key in ("sql", "sql_latitude", "sql_longitude"):
                for col in re.findall(r"\$\{TABLE\}\.(\w+)", f.get(key, "")):
                    if col not in cols:
                        fail(f"view {v.name}.{f['name']}: column {col} not in {v.table}")
        print(f"view {v.name}: {len(v.fields)} fields against {len(cols)} columns")


def field_of(ref: str, explores: dict, views: dict):
    view_name, _, field = ref.partition(".")
    if view_name not in views:
        raise KeyError(f"unknown view {view_name} in {ref}")
    if field not in views[view_name].fields:
        raise KeyError(f"unknown field {ref}")
    return views[view_name], field


def element_sql(el: dict, explores: dict, views: dict) -> str:
    view = views[explores[el["explore"]]]
    dims, measures = [], []
    for ref in el["fields"]:
        v, name = field_of(ref, explores, views)
        if v is not view:
            raise KeyError(f"{ref} is not in explore {el['explore']}")
        sql = v.expr(name, "t")
        (measures if v.fields[name]["kind"] == "measure" else dims).append(f"{sql} AS {name}")
    select = ",\n  ".join(dims + measures)
    group = f"\nGROUP BY {', '.join(str(i + 1) for i in range(len(dims)))}" if dims and measures else ""
    return f"SELECT\n  {select}\nFROM {view.table} AS t{group}\nLIMIT {el.get('limit', 500)}"


def check_dashboards(client, dashboards, explores, views):
    for dash in dashboards:
        filters = {f["name"]: f for f in dash.get("filters", [])}
        for f in filters.values():
            try:
                field_of(f["field"], explores, views)
            except KeyError as exc:
                fail(f"dashboard {dash['dashboard']} filter {f['name']}: {exc}")
        for el in dash["elements"]:
            where = f"dashboard {dash['dashboard']} element {el['name']}"
            if el.get("model") != "cdmx_mobility" or el.get("explore") not in explores:
                fail(f"{where}: unknown model/explore {el.get('model')}/{el.get('explore')}")
                continue
            for ref in el.get("sorts", []):
                if ref.split(" ")[0] not in el["fields"]:
                    fail(f"{where}: sort {ref} not in fields")
            for ref in el.get("pivots", []):
                if ref not in el["fields"]:
                    fail(f"{where}: pivot {ref} not in fields")
            for flt, ref in (el.get("listen") or {}).items():
                if flt not in filters:
                    fail(f"{where}: listens to unknown filter {flt}")
                try:
                    field_of(ref, explores, views)
                except KeyError as exc:
                    fail(f"{where}: listen {flt}: {exc}")
            try:
                sql = element_sql(el, explores, views)
                job = client.query(sql, job_config=bigquery.QueryJobConfig(dry_run=True, use_query_cache=False))
                print(f"ok  {dash['dashboard']}.{el['name']}: dry run {job.total_bytes_processed:,} bytes")
            except Exception as exc:  # noqa: BLE001
                fail(f"{where}: {exc}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default="flow-eed16")
    args = parser.parse_args()
    client = bigquery.Client(project=args.project)
    _, views, explores, dashboards = load()
    for name, view_name in explores.items():
        if view_name not in views:
            fail(f"explore {name}: no view {view_name}")
    check_columns(client, views)
    check_dashboards(client, dashboards, explores, views)
    elements = sum(len(d["elements"]) for d in dashboards)
    if errors:
        print(f"\n{len(errors)} problem(s):", *errors, sep="\n  ")
        sys.exit(1)
    print(f"\nLookML OK: {len(views)} views, {len(explores)} explores, {len(dashboards)} dashboards, {elements} elements")


if __name__ == "__main__":
    main()
