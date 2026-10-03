#!/usr/bin/env bash
# One-time setup: Pub/Sub, bucket, BigQuery datasets and bronze tables, service accounts.
# Safe to re-run; every step checks before creating.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh

gcloud services enable pubsub.googleapis.com run.googleapis.com cloudscheduler.googleapis.com \
  dataflow.googleapis.com bigquery.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  --project "$PROJECT"

# --- Pub/Sub ---------------------------------------------------------------------------------
gcloud pubsub topics describe "$TOPIC" --project "$PROJECT" >/dev/null 2>&1 \
  || gcloud pubsub topics create "$TOPIC" --project "$PROJECT"
# Seven days of retention: the poller keeps publishing while the Dataflow job is stopped, and
# a new job catches up from the backlog.
gcloud pubsub subscriptions describe "$SUBSCRIPTION" --project "$PROJECT" >/dev/null 2>&1 \
  || gcloud pubsub subscriptions create "$SUBSCRIPTION" --project "$PROJECT" --topic "$TOPIC" \
       --ack-deadline 60 --message-retention-duration 7d --expiration-period never

# --- Storage for Dataflow staging ----------------------------------------------------------
gcloud storage buckets describe "gs://$BUCKET" >/dev/null 2>&1 \
  || gcloud storage buckets create "gs://$BUCKET" --project "$PROJECT" --location "$REGION" \
       --uniform-bucket-level-access

# --- BigQuery ----------------------------------------------------------------------------------
export PROJECT BRONZE_DATASET BQ_LOCATION
envsubst < bronze.sql | bq --project_id "$PROJECT" query --nouse_legacy_sql >/dev/null
for ds in "$REF_DATASET" "$SILVER_DATASET" "$GOLD_DATASET" "$ASSERTIONS_DATASET"; do
  bq --project_id "$PROJECT" show "$PROJECT:$ds" >/dev/null 2>&1 \
    || bq --project_id "$PROJECT" mk --location "$BQ_LOCATION" --dataset "$PROJECT:$ds" >/dev/null
done

# --- Service accounts (least privilege) ----------------------------------------------------
for sa in ecobici-poller ecobici-scheduler ecobici-dataflow ecobici-dataform; do
  gcloud iam service-accounts describe "$sa@$PROJECT.iam.gserviceaccount.com" --project "$PROJECT" >/dev/null 2>&1 \
    || gcloud iam service-accounts create "$sa" --project "$PROJECT" --display-name "$sa"
done

# Poller: publish to its topic only.
gcloud pubsub topics add-iam-policy-binding "$TOPIC" --project "$PROJECT" \
  --member "serviceAccount:$POLLER_SA" --role roles/pubsub.publisher >/dev/null

# Dataflow workers: run the job, read the subscription, write bronze, use the staging bucket.
gcloud projects add-iam-policy-binding "$PROJECT" --member "serviceAccount:$DATAFLOW_SA" \
  --role roles/dataflow.worker --condition None >/dev/null
gcloud pubsub subscriptions add-iam-policy-binding "$SUBSCRIPTION" --project "$PROJECT" \
  --member "serviceAccount:$DATAFLOW_SA" --role roles/pubsub.subscriber >/dev/null
gcloud pubsub subscriptions add-iam-policy-binding "$SUBSCRIPTION" --project "$PROJECT" \
  --member "serviceAccount:$DATAFLOW_SA" --role roles/pubsub.viewer >/dev/null
gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" \
  --member "serviceAccount:$DATAFLOW_SA" --role roles/storage.objectAdmin >/dev/null
bq_grant() {  # dataset, member, role (dataset-level access entry)
  local ds="$1" member="$2" role="$3"
  bq --project_id "$PROJECT" show --format=prettyjson "$PROJECT:$ds" > /tmp/ds_$$.json
  python3 - "$member" "$role" /tmp/ds_$$.json <<'PY'
import json, sys
member, role, path = sys.argv[1:]
ds = json.load(open(path))
entry = {"role": role, "userByEmail": member}
if entry not in ds["access"]:
    ds["access"].append(entry)
json.dump({"access": ds["access"]}, open(path, "w"))
PY
  bq --project_id "$PROJECT" update --source /tmp/ds_$$.json "$PROJECT:$ds" >/dev/null
  rm -f /tmp/ds_$$.json
}
bq_grant "$BRONZE_DATASET" "$DATAFLOW_SA" WRITER

# Dataform: read bronze and ref, own silver, gold and assertions, run query jobs.
bq_grant "$BRONZE_DATASET" "$DATAFORM_SA" READER
bq_grant "$REF_DATASET" "$DATAFORM_SA" READER
for ds in "$SILVER_DATASET" "$GOLD_DATASET" "$ASSERTIONS_DATASET"; do
  bq_grant "$ds" "$DATAFORM_SA" WRITER
done
gcloud projects add-iam-policy-binding "$PROJECT" --member "serviceAccount:$DATAFORM_SA" \
  --role roles/bigquery.jobUser --condition None >/dev/null

echo "setup done: topic $TOPIC, subscription $SUBSCRIPTION, bucket gs://$BUCKET, datasets mobility_*"
