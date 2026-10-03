#!/usr/bin/env bash
# Runs the Dataform project (bronze -> silver -> gold + assertions) every hour as a Cloud Run job.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
JOB="${DATAFORM_JOB:-mobility-dataform}"

gcloud run jobs deploy "$JOB" --project "$PROJECT" --region "$REGION" \
  --source ../dataform \
  --service-account "$DATAFORM_SA" \
  --set-env-vars "PROJECT=$PROJECT,BQ_LOCATION=$BQ_LOCATION" \
  --cpu 1 --memory 1Gi --task-timeout 20m --max-retries 1 \
  --quiet

gcloud run jobs add-iam-policy-binding "$JOB" --project "$PROJECT" --region "$REGION" \
  --member "serviceAccount:$SCHEDULER_SA" --role roles/run.invoker >/dev/null

# Five minutes past every hour, after the previous hour has closed.
URI="https://run.googleapis.com/v2/projects/$PROJECT/locations/$REGION/jobs/$JOB:run"
ARGS=(--project "$PROJECT" --location "$REGION" --schedule "5 * * * *" --time-zone "America/Mexico_City"
  --uri "$URI" --http-method POST --oauth-service-account-email "$SCHEDULER_SA")
if gcloud scheduler jobs describe "$JOB" --project "$PROJECT" --location "$REGION" >/dev/null 2>&1; then
  gcloud scheduler jobs update http "$JOB" "${ARGS[@]}" >/dev/null
else
  gcloud scheduler jobs create http "$JOB" "${ARGS[@]}" >/dev/null
fi
echo "dataform job $JOB scheduled hourly"
