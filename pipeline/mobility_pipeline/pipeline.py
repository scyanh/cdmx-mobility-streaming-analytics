"""Streaming pipeline: Pub/Sub station events -> validation -> BigQuery bronze, errors -> DLQ table."""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone

import apache_beam as beam
from apache_beam.io.gcp.bigquery import BigQueryDisposition, RetryStrategy, WriteToBigQuery
from apache_beam.metrics import Metrics
from apache_beam.options.pipeline_options import PipelineOptions, SetupOptions, StandardOptions

from mobility_pipeline.validation import ValidationError, error_row, validate_event

ERRORS = "errors"


class MobilityOptions(PipelineOptions):
    # Not argparse-required: Beam parses every registered options class, tests included.
    REQUIRED = ("input_subscription", "bronze_table", "errors_table")

    @classmethod
    def _add_argparse_args(cls, parser):
        parser.add_argument("--input_subscription", help="projects/<project>/subscriptions/<subscription>")
        parser.add_argument("--bronze_table", help="project:dataset.table for valid events")
        parser.add_argument("--errors_table", help="project:dataset.table for rejected events")
        parser.add_argument("--id_label", default="event_id",
                            help="Pub/Sub attribute Dataflow deduplicates on; empty to disable (DirectRunner)")


def _utc(ts) -> datetime:
    """Pub/Sub publish times arrive as datetimes; Beam element timestamps as Timestamp."""
    if isinstance(ts, datetime):
        return ts.astimezone(timezone.utc)
    return datetime.fromtimestamp(ts.micros / 1_000_000, tz=timezone.utc)


class ParseAndValidate(beam.DoFn):
    """Emits bronze rows on the main output and DLQ rows on the 'errors' output."""

    def __init__(self, now=None):
        self._now = now
        self.valid = Metrics.counter("mobility", "valid_events")
        self.stale = Metrics.counter("mobility", "stale_events")

    def process(self, msg, element_ts=beam.DoFn.TimestampParam):
        # Without timestamp_attribute the element timestamp is the Pub/Sub publish time.
        publish_ts = _utc(msg.publish_time) if getattr(msg, "publish_time", None) else _utc(element_ts)
        ingest_ts = self._now() if self._now else datetime.now(timezone.utc)
        try:
            row = validate_event(msg.data, msg.attributes, publish_ts, ingest_ts)
        except ValidationError as exc:
            Metrics.counter("mobility", f"rejected_{exc.error_type}").inc()
            yield beam.pvalue.TaggedOutput(ERRORS, error_row(
                "validate", exc.error_type, exc.message, msg.data, msg.attributes, exc.event, publish_ts, ingest_ts))
            return
        except Exception as exc:  # a bug in validation must not stall the stream
            logging.exception("unexpected validation failure")
            Metrics.counter("mobility", "rejected_internal_error").inc()
            yield beam.pvalue.TaggedOutput(ERRORS, error_row(
                "validate", "internal_error", repr(exc), msg.data, msg.attributes, None, publish_ts, ingest_ts))
            return
        self.valid.inc()
        if row["is_stale"]:
            self.stale.inc()
        yield row


class ValidateEvents(beam.PTransform):
    def __init__(self, now=None):
        super().__init__()
        self._now = now

    def expand(self, messages):
        return messages | "ParseAndValidate" >> beam.ParDo(ParseAndValidate(self._now)).with_outputs(ERRORS, main="valid")


def insert_failure_to_error(failure, now=None) -> dict:
    """Maps a (table, row, errors) tuple from a failed streaming insert to a DLQ row."""
    _, row, errors = failure
    ingest_ts = now() if now else datetime.now(timezone.utc)
    return {
        "ingest_ts": ingest_ts.isoformat(),
        "publish_ts": row.get("publish_ts"),
        "stage": "bigquery_insert",
        "error_type": "insert_rejected",
        "error_message": json.dumps(errors, default=str)[:2000],
        "event_id": row.get("event_id"),
        "station_id": row.get("station_id"),
        "payload": json.dumps(row, default=str),
        "attributes": "{}",
    }


def build(p: beam.Pipeline, opts: MobilityOptions):
    missing = [f"--{name}" for name in MobilityOptions.REQUIRED if not getattr(opts, name)]
    if missing:
        raise ValueError(f"missing required options: {', '.join(missing)}")
    messages = p | "ReadPubSub" >> beam.io.ReadFromPubSub(
        subscription=opts.input_subscription,
        with_attributes=True,
        id_label=opts.id_label or None,
    )
    validated = messages | "Validate" >> ValidateEvents()

    bronze = validated.valid | "WriteBronze" >> WriteToBigQuery(
        opts.bronze_table,
        method=WriteToBigQuery.Method.STREAMING_INSERTS,
        create_disposition=BigQueryDisposition.CREATE_NEVER,
        write_disposition=BigQueryDisposition.WRITE_APPEND,
        insert_retry_strategy=RetryStrategy.RETRY_ON_TRANSIENT_ERROR,
    )
    insert_failures = bronze.failed_rows_with_errors | "InsertFailuresToErrors" >> beam.Map(insert_failure_to_error)

    (
        (validated[ERRORS], insert_failures)
        | "MergeErrors" >> beam.Flatten()
        | "WriteErrors" >> WriteToBigQuery(
            opts.errors_table,
            method=WriteToBigQuery.Method.STREAMING_INSERTS,
            create_disposition=BigQueryDisposition.CREATE_NEVER,
            write_disposition=BigQueryDisposition.WRITE_APPEND,
            insert_retry_strategy=RetryStrategy.RETRY_ALWAYS,
        )
    )


def run(argv=None):
    options = PipelineOptions(argv)
    options.view_as(StandardOptions).streaming = True
    options.view_as(SetupOptions).save_main_session = False
    with beam.Pipeline(options=options) as p:
        build(p, options.view_as(MobilityOptions))
