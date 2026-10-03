-- Bronze tables the Dataflow job streams into. Created up front (CREATE_NEVER in the job) so
-- partitioning, clustering and descriptions are owned here, not by the pipeline.
CREATE SCHEMA IF NOT EXISTS `${PROJECT}.${BRONZE_DATASET}`
OPTIONS (location = '${BQ_LOCATION}', description = 'Raw ECOBICI station events as received from Pub/Sub');

CREATE TABLE IF NOT EXISTS `${PROJECT}.${BRONZE_DATASET}.station_status_raw` (
  event_id STRING NOT NULL OPTIONS (description = 'system-station-last_reported: identifies a station state, repeats across polls'),
  system_id STRING NOT NULL,
  station_id STRING NOT NULL,
  event_ts TIMESTAMP NOT NULL OPTIONS (description = 'When the station reported this state (GBFS last_reported)'),
  last_reported INT64 NOT NULL,
  num_bikes_available INT64 NOT NULL,
  num_bikes_disabled INT64,
  num_docks_available INT64 NOT NULL,
  num_docks_disabled INT64,
  is_installed BOOL,
  is_renting BOOL,
  is_returning BOOL,
  station_name STRING,
  station_short_name STRING,
  lat FLOAT64,
  lon FLOAT64,
  capacity INT64,
  feed_last_updated TIMESTAMP NOT NULL,
  polled_at TIMESTAMP NOT NULL OPTIONS (description = 'When the poller read the feed'),
  poll_id STRING,
  schema_version INT64 NOT NULL,
  publish_ts TIMESTAMP NOT NULL OPTIONS (description = 'Pub/Sub publish time'),
  ingest_ts TIMESTAMP NOT NULL OPTIONS (description = 'When Dataflow processed the message'),
  report_age_seconds INT64 NOT NULL OPTIONS (description = 'polled_at - event_ts'),
  is_stale BOOL NOT NULL OPTIONS (description = 'Report older than one hour when polled'),
  warnings ARRAY<STRING> OPTIONS (description = 'Soft validation problems; the row is still usable')
)
PARTITION BY DATE(ingest_ts)
CLUSTER BY station_id
OPTIONS (description = 'One row per message that passed validation. Contains repeats of the same event_id; silver deduplicates.');

CREATE TABLE IF NOT EXISTS `${PROJECT}.${BRONZE_DATASET}.station_status_errors` (
  ingest_ts TIMESTAMP NOT NULL,
  publish_ts TIMESTAMP,
  stage STRING NOT NULL OPTIONS (description = 'validate or bigquery_insert'),
  error_type STRING NOT NULL,
  error_message STRING,
  event_id STRING,
  station_id STRING,
  payload STRING OPTIONS (description = 'Original message body, for replay'),
  attributes STRING OPTIONS (description = 'Pub/Sub attributes as JSON')
)
PARTITION BY DATE(ingest_ts)
CLUSTER BY error_type
OPTIONS (description = 'Dead-letter table: messages rejected by validation or by BigQuery', partition_expiration_days = 90);
