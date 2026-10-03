import json
from datetime import datetime, timezone

import apache_beam as beam
from apache_beam.io.gcp.pubsub import PubsubMessage
from apache_beam.testing.test_pipeline import TestPipeline as BeamTestPipeline
from apache_beam.testing.util import assert_that, equal_to
from apache_beam.transforms.window import TimestampedValue

from mobility_pipeline.pipeline import ERRORS, ValidateEvents, insert_failure_to_error
from tests.conftest import make_event

NOW = datetime(2026, 10, 3, 16, 32, 5, tzinfo=timezone.utc)
PUBLISHED = datetime(2026, 10, 3, 16, 32, 1, tzinfo=timezone.utc)


def message(data: bytes, attributes=None, publish_time=None):
    return PubsubMessage(data, attributes or {}, publish_time=publish_time)


def test_valid_and_invalid_events_are_split():
    good = make_event()
    other = make_event(station_id="5", event_id="MEX-5-1791045083")
    with BeamTestPipeline() as p:
        out = (
            p
            | beam.Create([
                message(json.dumps(good).encode(), {"event_id": good["event_id"]}, PUBLISHED),
                message(json.dumps(other).encode()),
                message(b"{broken"),
                message(json.dumps(make_event(num_bikes_available=-2)).encode()),
            ])
            | beam.Map(lambda m: TimestampedValue(m, PUBLISHED.timestamp()))
            | ValidateEvents(now=lambda: NOW)
        )
        assert_that(out.valid | "ValidIds" >> beam.Map(lambda r: (r["event_id"], r["publish_ts"], r["ingest_ts"])),
                    equal_to([
                        ("MEX-1-1791045083", "2026-10-03T16:32:01+00:00", "2026-10-03T16:32:05+00:00"),
                        ("MEX-5-1791045083", "2026-10-03T16:32:01+00:00", "2026-10-03T16:32:05+00:00"),
                    ]), label="valid")
        assert_that(out[ERRORS] | "ErrorTypes" >> beam.Map(lambda r: (r["stage"], r["error_type"])),
                    equal_to([("validate", "parse_error"), ("validate", "negative_count")]), label="errors")


def test_insert_failure_becomes_error_row():
    row = {"event_id": "MEX-1-1", "station_id": "1", "publish_ts": "2026-10-03T16:32:01+00:00"}
    err = insert_failure_to_error(("p:d.t", row, [{"reason": "invalid", "message": "no such field: foo"}]),
                                  now=lambda: NOW)
    assert err["stage"] == "bigquery_insert" and err["error_type"] == "insert_rejected"
    assert err["event_id"] == "MEX-1-1" and "no such field" in err["error_message"]
    assert json.loads(err["payload"]) == row
