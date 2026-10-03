#!/usr/bin/env bash
# Loads Mexico City's colonias (IECM 2019, Portal de Datos Abiertos CDMX) into BigQuery as
# GEOGRAPHY polygons. Stations are assigned to a colonia, the "zone" of the gold layer.
set -euo pipefail
cd "$(dirname "$0")"
source ../infra/config.sh

URL="https://datos.cdmx.gob.mx/dataset/04a1900a-0c2f-41ed-94dc-3d2d5bad4065/resource/8070ee81-9111-437e-a3dd-0c3cc6dce9f4/download/8070ee81-9111-437e-a3dd-0c3cc6dce9f4.json"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -sSfL --retry 3 -o "$WORK/colonias.geojson" "$URL"
python3 - "$WORK/colonias.geojson" "$WORK/colonias.ndjson" <<'PY'
import json, sys
src, dst = sys.argv[1:]
features = json.load(open(src))["features"]
with open(dst, "w") as out:
    for f in features:
        p = f["properties"]
        out.write(json.dumps({
            "colonia_id": p["CVEUT"],
            "colonia": p["NOMUT"],
            "alcaldia": p["NOMDT"],
            "geometry": json.dumps(f["geometry"]),
        }) + "\n")
print(f"{len(features)} colonias", file=sys.stderr)
PY

bq --project_id "$PROJECT" load --replace --source_format NEWLINE_DELIMITED_JSON \
  "$PROJECT:$REF_DATASET.colonias_geojson" "$WORK/colonias.ndjson" \
  colonia_id:STRING,colonia:STRING,alcaldia:STRING,geometry:STRING

# make_valid repairs the few self-intersecting rings in the source polygons.
bq --project_id "$PROJECT" query --nouse_legacy_sql "
CREATE OR REPLACE TABLE \`$PROJECT.$REF_DATASET.colonias\`
CLUSTER BY geog
OPTIONS (description = 'Colonias of Mexico City (IECM 2019), source: datos.cdmx.gob.mx dataset coloniascdmx')
AS
SELECT
  colonia_id,
  INITCAP(colonia) AS colonia,
  INITCAP(alcaldia) AS alcaldia,
  ST_GEOGFROMGEOJSON(geometry, make_valid => TRUE) AS geog
FROM \`$PROJECT.$REF_DATASET.colonias_geojson\`"
bq --project_id "$PROJECT" rm -f -t "$PROJECT:$REF_DATASET.colonias_geojson"
