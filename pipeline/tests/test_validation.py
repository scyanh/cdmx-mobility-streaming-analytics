from datetime import datetime, timezone

import pytest

from mobility_pipeline.validation import ValidationError, error_row, validate_event

PUBLISH = datetime(2026, 10, 3, 16, 32, 1, tzinfo=timezone.utc)
INGEST = datetime(2026, 10, 3, 16, 32, 3, tzinfo=timezone.utc)


def validate(data, attributes=None):
    return validate_event(data, attributes if attributes is not None else {"event_id": "MEX-1-1791045083"}, PUBLISH, INGEST)


def rejected(data, attributes=None) -> str:
    with pytest.raises(ValidationError) as exc:
        validate(data, attributes)
    return exc.value.error_type


def test_valid_event_becomes_a_bronze_row(payload):
    row = validate(payload())
    assert row["event_id"] == "MEX-1-1791045083"
    assert row["event_ts"] == "2026-10-03T16:31:23+00:00"
    assert row["polled_at"] == "2026-10-03T16:32:00.123456+00:00"
    assert row["publish_ts"] == "2026-10-03T16:32:01+00:00"
    assert row["ingest_ts"] == "2026-10-03T16:32:03+00:00"
    assert row["report_age_seconds"] == 37
    assert row["is_stale"] is False
    assert row["warnings"] == []
    assert (row["num_bikes_available"], row["capacity"], row["lat"]) == (18, 39, 19.416795)


def test_old_report_is_kept_but_flagged_stale(payload):
    two_hours_earlier = 1791045083 - 7200
    row = validate(payload(last_reported=two_hours_earlier, event_id=f"MEX-1-{two_hours_earlier}",
                           event_ts="2026-10-03T14:31:23Z"), attributes={})
    assert row["is_stale"] is True
    assert row["report_age_seconds"] == 7237
    assert row["warnings"] == ["stale_report"]


def test_station_without_information_is_kept(payload):
    row = validate(payload(lat=None, lon=None, capacity=None, station_name=None))
    assert row["warnings"] == ["missing_station_information"]
    assert row["lat"] is None and row["capacity"] is None


@pytest.mark.parametrize("overrides, warning", [
    ({"num_docks_available": 30}, "counts_exceed_capacity"),
    ({"lat": 20.67, "lon": -103.35}, "location_outside_cdmx"),
])
def test_soft_problems_become_warnings(payload, overrides, warning):
    assert validate(payload(**overrides))["warnings"] == [warning]


def test_optional_counts_may_be_missing(payload):
    row = validate(payload(num_bikes_disabled=None, num_docks_disabled=None))
    assert row["num_bikes_disabled"] is None and row["warnings"] == []


@pytest.mark.parametrize("data, error_type", [
    (b"not json", "parse_error"),
    (b"\xff\xfe", "parse_error"),
    (b"[1, 2]", "parse_error"),
])
def test_unparseable_payloads(data, error_type):
    assert rejected(data) == error_type


@pytest.mark.parametrize("overrides, error_type", [
    ({"schema_version": 2}, "unsupported_schema"),
    ({"station_id": ""}, "missing_field"),
    ({"last_reported": None, "event_id": "MEX-1-unknown", "event_ts": None}, "missing_field"),
    ({"num_bikes_available": None}, "missing_field"),
    ({"event_id": "MEX-1-123"}, "event_id_mismatch"),
    ({"num_bikes_available": -1}, "negative_count"),
    ({"num_docks_available": True}, "invalid_type"),
    ({"num_docks_available": "20"}, "invalid_type"),
    ({"is_renting": 1}, "invalid_type"),
    ({"lat": "19.4"}, "invalid_type"),
    ({"capacity": 39.5}, "invalid_type"),
    ({"station_name": 710}, "invalid_type"),
    ({"event_ts": "2026-10-03T16:00:00Z"}, "invalid_timestamp"),
    ({"polled_at": "yesterday"}, "invalid_timestamp"),
    ({"polled_at": "2026-10-03T16:32:00"}, "invalid_timestamp"),
    ({"feed_last_updated": None}, "invalid_type"),
    ({"polled_at": "2026-10-03T16:20:00Z"}, "future_timestamp"),
    ({"last_reported": 1600000000, "event_id": "MEX-1-1600000000", "event_ts": "2020-09-13T12:26:40Z"},
     "timestamp_out_of_range"),
])
def test_hard_errors_are_rejected(payload, overrides, error_type):
    assert rejected(payload(**overrides), attributes={}) == error_type


def test_attribute_must_match_payload(payload):
    assert rejected(payload(), attributes={"event_id": "MEX-2-1791045083"}) == "event_id_mismatch"


def test_error_row_keeps_payload_for_replay(payload):
    data = payload(num_bikes_available=-3)
    with pytest.raises(ValidationError) as exc:
        validate(data)
    row = error_row("validate", exc.value.error_type, exc.value.message, data, {"event_id": "MEX-1-1791045083"},
                    exc.value.event, PUBLISH, INGEST)
    assert row["error_type"] == "negative_count"
    assert row["event_id"] == "MEX-1-1791045083" and row["station_id"] == "1"
    assert row["payload"] == data.decode()
    assert row["attributes"] == '{"event_id": "MEX-1-1791045083"}'


def test_error_row_falls_back_to_attributes_when_payload_is_garbage():
    row = error_row("validate", "parse_error", "boom", b"\xff", {"event_id": "MEX-9-1", "station_id": "9"},
                    None, None, INGEST)
    assert (row["event_id"], row["station_id"], row["publish_ts"]) == ("MEX-9-1", "9", None)
    assert row["payload"] == "�"
