#!/usr/bin/env bash
# Builds and deploys the poller to Cloud Run (private) and schedules POST /poll every minute.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh

gcloud run deploy "$POLLER_SERVICE" --project "$PROJECT" --region "$REGION" \
  --source ../poller \
  --service-account "$POLLER_SA" \
  --no-allow-unauthenticated \
  --set-env-vars "GOOGLE_CLOUD_PROJECT=$PROJECT,PUBSUB_TOPIC=$TOPIC" \
  --cpu 1 --memory 512Mi --concurrency 4 --min-instances 0 --max-instances 2 --timeout 60 \
  --quiet

URL="$(gcloud run services describe "$POLLER_SERVICE" --project "$PROJECT" --region "$REGION" --format 'value(status.url)')"
gcloud run services add-iam-policy-binding "$POLLER_SERVICE" --project "$PROJECT" --region "$REGION" \
  --member "serviceAccount:$SCHEDULER_SA" --role roles/run.invoker >/dev/null

# Every minute. One retry: a failed poll is replaced by the next one a minute later anyway,
# and repeats are harmless because event IDs are deterministic.
SCHEDULE_ARGS=(--project "$PROJECT" --location "$REGION" --schedule "* * * * *" --time-zone "America/Mexico_City"
  --uri "$URL/poll" --http-method POST --oidc-service-account-email "$SCHEDULER_SA" --oidc-token-audience "$URL"
  --attempt-deadline 60s --max-retry-attempts 1 --min-backoff 10s)
if gcloud scheduler jobs describe "$SCHEDULER_JOB" --project "$PROJECT" --location "$REGION" >/dev/null 2>&1; then
  gcloud scheduler jobs update http "$SCHEDULER_JOB" "${SCHEDULE_ARGS[@]}" >/dev/null
  gcloud scheduler jobs resume "$SCHEDULER_JOB" --project "$PROJECT" --location "$REGION" >/dev/null
else
  gcloud scheduler jobs create http "$SCHEDULER_JOB" "${SCHEDULE_ARGS[@]}" >/dev/null
fi
echo "poller at $URL, scheduled every minute as $SCHEDULER_JOB"
