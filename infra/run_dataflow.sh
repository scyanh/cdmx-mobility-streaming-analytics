#!/usr/bin/env bash
# Launches the streaming job: Pub/Sub subscription -> validation -> bronze + errors tables.
# Credentials: Beam uses Application Default Credentials, not the gcloud account.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
cd ../pipeline

# One small worker is enough: the feed produces ~11 messages per second.
.venv/bin/python main.py \
  --runner DataflowRunner \
  --project "$PROJECT" \
  --region "$REGION" \
  --job_name "$DATAFLOW_JOB" \
  --service_account_email "$DATAFLOW_SA" \
  --temp_location "gs://$BUCKET/temp" \
  --staging_location "gs://$BUCKET/staging" \
  --setup_file ./setup.py \
  --streaming \
  --enable_streaming_engine \
  --machine_type "${MACHINE_TYPE:-n1-standard-1}" \
  --num_workers 1 --max_num_workers 1 \
  --input_subscription "projects/$PROJECT/subscriptions/$SUBSCRIPTION" \
  --bronze_table "$PROJECT:$BRONZE_DATASET.station_status_raw" \
  --errors_table "$PROJECT:$BRONZE_DATASET.station_status_errors" \
  "$@" &
LAUNCH_PID=$!
# The launcher blocks while the streaming job runs; it can be stopped once the job is running.
for _ in $(seq 1 60); do
  sleep 10
  STATE="$(gcloud dataflow jobs list --project "$PROJECT" --region "$REGION" --status active \
    --filter "name=$DATAFLOW_JOB" --format 'value(state)' | head -1)"
  if [ "$STATE" = "Running" ]; then
    kill "$LAUNCH_PID" 2>/dev/null || true
    echo "dataflow job $DATAFLOW_JOB is running"
    exit 0
  fi
done
echo "job did not reach Running in 10 minutes; check the Dataflow console" >&2
exit 1
