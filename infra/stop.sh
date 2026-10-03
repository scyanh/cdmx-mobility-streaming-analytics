#!/usr/bin/env bash
# Stops everything that costs money while running. The Pub/Sub subscription keeps 7 days of
# events, so with the poller still scheduled (PAUSE_POLLER=0) a later job catches up.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh

JOB_ID="$(gcloud dataflow jobs list --project "$PROJECT" --region "$REGION" --status active \
  --filter "name=$DATAFLOW_JOB" --format 'value(id)' | head -1)"
if [ -n "$JOB_ID" ]; then
  # Drain, not cancel: finishes writing what was already read from Pub/Sub.
  gcloud dataflow jobs drain "$JOB_ID" --project "$PROJECT" --region "$REGION"
  echo "draining $JOB_ID"
fi
if [ "${PAUSE_POLLER:-0}" = "1" ]; then
  gcloud scheduler jobs pause "$SCHEDULER_JOB" --project "$PROJECT" --location "$REGION"
  echo "poller paused"
fi
