"""Turns one poll of the GBFS feeds into one event per station."""

from __future__ import annotations

from datetime import datetime, timezone

SCHEMA_VERSION = 1


def event_id(system_id: str, station_id: str, last_reported) -> str:
    """Identifies a station state, not a poll: a station that has not reported since the last
    poll produces the same ID, so Dataflow and the silver layer can drop the repeat."""
    if last_reported is None:
        return f"{system_id}-{station_id}-unknown"
    return f"{system_id}-{station_id}-{last_reported}"


def _rfc3339(ts: datetime) -> str:
    return ts.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _unix_to_rfc3339(sec) -> str | None:
    if isinstance(sec, bool) or not isinstance(sec, int):
        return None
    return _rfc3339(datetime.fromtimestamp(sec, tz=timezone.utc))


def _gbfs_bool(value):
    # GBFS v1/v2 send 0/1 and v3 true/false. Anything else passes through unchanged so the
    # pipeline rejects it, instead of the poller guessing.
    if value in (0, 1) and not isinstance(value, float):
        return bool(value)
    return value


def build_events(system_id: str, status: dict, information: dict, polled_at: datetime, poll_id: str) -> list[dict]:
    """Missing fields stay None: a count absent from the feed reaches the pipeline as null and
    is rejected there, instead of silently becoming zero bikes."""
    info_by_id = {str(s.get("station_id")): s for s in information["data"]["stations"]}
    feed_last_updated = _unix_to_rfc3339(status.get("last_updated"))
    events = []
    for s in status["data"]["stations"]:
        station_id = str(s.get("station_id"))  # some publishers send it as a number
        last_reported = s.get("last_reported")
        info = info_by_id.get(station_id, {})
        events.append({
            "schema_version": SCHEMA_VERSION,
            "event_id": event_id(system_id, station_id, last_reported),
            "system_id": system_id,
            "station_id": station_id,
            "last_reported": last_reported,
            "event_ts": _unix_to_rfc3339(last_reported),
            "num_bikes_available": s.get("num_bikes_available"),
            "num_bikes_disabled": s.get("num_bikes_disabled"),
            "num_docks_available": s.get("num_docks_available"),
            "num_docks_disabled": s.get("num_docks_disabled"),
            "is_installed": _gbfs_bool(s.get("is_installed")),
            "is_renting": _gbfs_bool(s.get("is_renting")),
            "is_returning": _gbfs_bool(s.get("is_returning")),
            "station_name": info.get("name"),
            "station_short_name": info.get("short_name"),
            "lat": info.get("lat"),
            "lon": info.get("lon"),
            "capacity": info.get("capacity"),
            "feed_last_updated": feed_last_updated,
            "polled_at": _rfc3339(polled_at),
            "poll_id": poll_id,
        })
    return events
