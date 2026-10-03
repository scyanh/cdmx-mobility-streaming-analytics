#!/usr/bin/env bash
# Loads ECOBICI's open trip history (one CSV per month, Portal de Datos Abiertos ECOBICI) into
# BigQuery unchanged, as strings. Dataform parses it (silver.trips): the live stream only starts
# on deploy, and the history gives the dashboard a year of real trips to tell patterns from.
set -euo pipefail
cd "$(dirname "$0")"
source ../infra/config.sh

TRIPS_TABLE="${TRIPS_TABLE:-trips_raw}"
BASE="https://ecobici.cdmx.gob.mx/wp-content/uploads"
# The site names files inconsistently; these are the published names for Oct 2025 - Sep 2026.
FILES=(
  2025/11/2025-10-1.csv
  2025/12/2025-11.csv
  2026/01/2025-12.csv
  2026/02/2026-01.csv
  2026/03/2026-02.csv
  2026/04/2026-03.csv
  2026/05/2026-04.csv
  2026/06/2026-05.csv
  2026/07/public_data_web_2026-06.csv
  2026/08/public_data_web_2026-07.csv
  2026/09/public_data_web_2026-08_2.csv
  2026/10/public_data_web_2026-09.csv
)
WORK="${WORK:-$(mktemp -d)}"

# The server is slow per connection, so files download in parallel; a file only gets its final
# name once complete, so a rerun skips finished files and retries partial ones.
printf '%s\n' "${FILES[@]}" | xargs -P 6 -I{} sh -c '
  out="$1/$(basename "$2")"
  [ -s "$out" ] || { curl -sSfL --retry 3 -o "$out.part" "$3/$2" && mv "$out.part" "$out"; }
' _ "$WORK" {} "$BASE"
[ "$(ls "$WORK"/*.csv | wc -l)" -eq "${#FILES[@]}" ] || { echo "missing downloads in $WORK" >&2; exit 1; }
gcloud storage cp "$WORK"/*.csv "gs://$BUCKET/ecobici_trips/" --project "$PROJECT"

# Column names differ by a character between files of different years; position is what matters.
bq --project_id "$PROJECT" load --replace --source_format CSV --skip_leading_rows 1 \
  --allow_quoted_newlines --max_bad_records 100 \
  "$PROJECT:$REF_DATASET.$TRIPS_TABLE" "gs://$BUCKET/ecobici_trips/*.csv" \
  gender:STRING,age:STRING,bike:STRING,start_station:STRING,start_date:STRING,start_time:STRING,end_station:STRING,end_date:STRING,end_time:STRING

bq --project_id "$PROJECT" query --nouse_legacy_sql \
  "SELECT COUNT(*) AS trips FROM \`$PROJECT.$REF_DATASET.$TRIPS_TABLE\`"
