# Shared settings for the infra scripts. Override any of them from the environment.
PROJECT="${PROJECT:-flow-eed16}"
REGION="${REGION:-us-central1}"
BQ_LOCATION="${BQ_LOCATION:-US}"

TOPIC="${TOPIC:-ecobici-station-status}"
SUBSCRIPTION="${SUBSCRIPTION:-ecobici-station-status-dataflow}"
BUCKET="${BUCKET:-${PROJECT}-mobility-dataflow}"

BRONZE_DATASET="${BRONZE_DATASET:-mobility_bronze}"
REF_DATASET="${REF_DATASET:-mobility_ref}"
SILVER_DATASET="${SILVER_DATASET:-mobility_silver}"
GOLD_DATASET="${GOLD_DATASET:-mobility_gold}"
ASSERTIONS_DATASET="${ASSERTIONS_DATASET:-mobility_assertions}"

POLLER_SERVICE="${POLLER_SERVICE:-ecobici-poller}"
SCHEDULER_JOB="${SCHEDULER_JOB:-ecobici-poll}"
DATAFLOW_JOB="${DATAFLOW_JOB:-ecobici-bronze}"

POLLER_SA="ecobici-poller@${PROJECT}.iam.gserviceaccount.com"
SCHEDULER_SA="ecobici-scheduler@${PROJECT}.iam.gserviceaccount.com"
DATAFLOW_SA="ecobici-dataflow@${PROJECT}.iam.gserviceaccount.com"
DATAFORM_SA="ecobici-dataform@${PROJECT}.iam.gserviceaccount.com"
