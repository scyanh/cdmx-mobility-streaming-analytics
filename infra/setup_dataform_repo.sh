#!/usr/bin/env bash
# Runs the Dataform project (workflow_settings.yaml and definitions/ at the repo root) on
# BigQuery's managed Dataform: a repository linked to GitHub, a release compiled from main every
# hour and a workflow that runs it five minutes later as the ecobici-dataform service account.
#
# Before running: add a GitHub token (fine-grained, this repository, Contents read and write)
# as a version of the secret this script creates:
#   gcloud secrets versions add dataform-github-token --data-file=- --project <project>
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh

DATAFORM_REGION="${DATAFORM_REGION:-$REGION}"
REPOSITORY="${DATAFORM_REPOSITORY:-cdmx-mobility}"
GIT_URL="${GIT_URL:-https://github.com/scyanh/cdmx-mobility-streaming-analytics.git}"
SECRET="dataform-github-token"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format 'value(projectNumber)')"
AGENT="service-$PROJECT_NUMBER@gcp-sa-dataform.iam.gserviceaccount.com"
API="https://dataform.googleapis.com/v1/projects/$PROJECT/locations/$DATAFORM_REGION"

call() {  # method, path, json body
  local out
  out="$(curl -sS -X "$1" -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "Content-Type: application/json" "$API/$2" ${3:+-d "$3"})"
  if echo "$out" | grep -q '"error"'; then
    echo "$out" >&2
    return 1
  fi
  echo "$out"
}

gcloud services enable dataform.googleapis.com secretmanager.googleapis.com --project "$PROJECT"
gcloud beta services identity create --service dataform.googleapis.com --project "$PROJECT" >/dev/null

gcloud secrets describe "$SECRET" --project "$PROJECT" >/dev/null 2>&1 \
  || gcloud secrets create "$SECRET" --project "$PROJECT" --replication-policy automatic
gcloud secrets add-iam-policy-binding "$SECRET" --project "$PROJECT" \
  --member "serviceAccount:$AGENT" --role roles/secretmanager.secretAccessor >/dev/null
# Dataform's service agent runs workflows by impersonating our service account.
for role in roles/iam.serviceAccountTokenCreator roles/iam.serviceAccountUser; do
  gcloud iam service-accounts add-iam-policy-binding "$DATAFORM_SA" --project "$PROJECT" \
    --member "serviceAccount:$AGENT" --role "$role" >/dev/null
done

if ! gcloud secrets versions list "$SECRET" --project "$PROJECT" --filter state=enabled --format 'value(name)' | grep -q .; then
  echo "secret $SECRET has no token yet; add one (see the top of this script) and re-run" >&2
  exit 1
fi

idparam() {  # repositories -> repositoryId, releaseConfigs -> releaseConfigId, ...
  case "${1##*/}" in
    repositories) echo repositoryId ;;
    *) local c="${1##*/}"; echo "${c%s}Id" ;;
  esac
}
upsert() {
  if call GET "$1/$2" >/dev/null 2>&1; then
    call PATCH "$1/$2" "$3"
  else
    call POST "$1?$(idparam "$1")=$2" "$3"
  fi
}

REPO_PATH="projects/$PROJECT/locations/$DATAFORM_REGION/repositories/$REPOSITORY"
GIT_SETTINGS="{\"url\":\"$GIT_URL\",\"defaultBranch\":\"main\",\"authenticationTokenSecretVersion\":\"projects/$PROJECT/secrets/$SECRET/versions/latest\"}"
upsert repositories "$REPOSITORY" "{\"gitRemoteSettings\":$GIT_SETTINGS,\"serviceAccount\":\"$DATAFORM_SA\"}" >/dev/null

upsert "repositories/$REPOSITORY/releaseConfigs" production \
  '{"gitCommitish":"main","cronSchedule":"0 * * * *","timeZone":"America/Mexico_City"}' >/dev/null
# Compile now and make it the release's current compilation, so the workflow can run before
# the next scheduled release.
COMPILATION="$(call POST "repositories/$REPOSITORY/compilationResults" \
  "{\"releaseConfig\":\"$REPO_PATH/releaseConfigs/production\"}" | python3 -c 'import json,sys; d=json.load(sys.stdin); errs=d.get("compilationErrors", []); [print("compilation error:", e, file=sys.stderr) for e in errs]; print(d["name"]); sys.exit(1 if errs else 0)')"
call PATCH "repositories/$REPOSITORY/releaseConfigs/production?updateMask=releaseCompilationResult" \
  "{\"gitCommitish\":\"main\",\"releaseCompilationResult\":\"$COMPILATION\"}" >/dev/null

upsert "repositories/$REPOSITORY/workflowConfigs" hourly \
  "{\"releaseConfig\":\"$REPO_PATH/releaseConfigs/production\",\"cronSchedule\":\"5 * * * *\",\"timeZone\":\"America/Mexico_City\",\"invocationConfig\":{\"serviceAccount\":\"$DATAFORM_SA\"}}" >/dev/null

echo "Dataform repository $REPOSITORY linked to $GIT_URL, compiled as $COMPILATION"
echo "release hourly at :00, workflow hourly at :05"
