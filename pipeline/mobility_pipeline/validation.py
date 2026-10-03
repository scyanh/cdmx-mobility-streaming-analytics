"""Validation of station events published by the poller.

Hard errors send the message to the errors table (DLQ); soft problems keep the row in bronze
with a warning, because the station state is still usable.
"""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone

SCHEMA_VERSION = 1
# ECOBICI's current system started on this date (system_information.start_date).
SYSTEM_START = datetime(2022, 6, 19, tzinfo=timezone.utc)
MAX_CLOCK_SKEW = timedelta(minutes=5)
# A station keeps last_reported unchanged while it is quiet; older than this it is probably offline.
STALE_AFTER = timedelta(hours=1)
# Generous box around Mexico City; ECOBICI stations sit well inside it.
CDMX_BBOX = {"lat": (19.0, 19.7), "lon": (-99.40, -98.90)}

COUNT_FIELDS = ("num_bikes_available", "num_bikes_disabled", "num_docks_available", "num_docks_disabled")
REQUIRED_COUNTS = ("num_bikes_available", "num_docks_available")
BOOL_FIELDS = ("is_installed", "is_renting", "is_returning")
STRING_FIELDS = ("station_name", "station_short_name", "poll_id")


class ValidationError(Exception):
    def __init__(self, error_type: str, message: str, event: dict | None = None):
        super().__init__(message)
        self.error_type = error_type
        self.message = message
        self.event = event or {}


def _parse_ts(value, field: str, event: dict) -> datetime:
    if not isinstance(value, str):
        raise ValidationError("invalid_type", f"{field} must be an RFC 3339 string", event)
    try:
        ts = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        raise ValidationError("invalid_timestamp", f"{field} is not a timestamp: {value!r}", event) from None
    if ts.tzinfo is None:
        raise ValidationError("invalid_timestamp", f"{field} has no timezone: {value!r}", event)
    return ts.astimezone(timezone.utc)


def _is_int(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _bq_ts(ts: datetime) -> str:
    return ts.astimezone(timezone.utc).isoformat()


def validate_event(payload: bytes, attributes: dict | None, publish_ts: datetime, ingest_ts: datetime) -> dict:
    """Returns the bronze row for a valid event or raises ValidationError."""
    try:
        event = json.loads(payload)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValidationError("parse_error", f"payload is not JSON: {exc}") from None
    if not isinstance(event, dict):
        raise ValidationError("parse_error", "payload is not a JSON object")

    if event.get("schema_version") != SCHEMA_VERSION:
        raise ValidationError("unsupported_schema", f"schema_version {event.get('schema_version')!r}", event)

    for field in ("event_id", "system_id", "station_id"):
        if not isinstance(event.get(field), str) or not event[field]:
            raise ValidationError("missing_field", f"{field} is missing or empty", event)
    if not _is_int(event.get("last_reported")):
        raise ValidationError("missing_field", "last_reported is missing or not an integer", event)

    expected_id = f"{event['system_id']}-{event['station_id']}-{event['last_reported']}"
    if event["event_id"] != expected_id:
        raise ValidationError("event_id_mismatch", f"event_id {event['event_id']!r}, expected {expected_id!r}", event)
    if attributes and attributes.get("event_id") not in (None, event["event_id"]):
        raise ValidationError("event_id_mismatch", "event_id attribute differs from the payload", event)

    for field in COUNT_FIELDS:
        value = event.get(field)
        if value is None:
            if field in REQUIRED_COUNTS:
                raise ValidationError("missing_field", f"{field} is missing", event)
            continue
        if not _is_int(value):
            raise ValidationError("invalid_type", f"{field} must be an integer, got {value!r}", event)
        if value < 0:
            raise ValidationError("negative_count", f"{field} is {value}", event)
    for field in BOOL_FIELDS:
        if event.get(field) is not None and not isinstance(event[field], bool):
            raise ValidationError("invalid_type", f"{field} must be a boolean", event)

    event_ts = datetime.fromtimestamp(event["last_reported"], tz=timezone.utc)
    if event.get("event_ts") is not None and _parse_ts(event["event_ts"], "event_ts", event) != event_ts:
        raise ValidationError("invalid_timestamp", "event_ts does not match last_reported", event)
    polled_at = _parse_ts(event.get("polled_at"), "polled_at", event)
    feed_last_updated = _parse_ts(event.get("feed_last_updated"), "feed_last_updated", event)
    if event_ts > polled_at + MAX_CLOCK_SKEW:
        raise ValidationError("future_timestamp", f"event_ts {event_ts.isoformat()} is after polled_at", event)
    if event_ts < SYSTEM_START:
        raise ValidationError("timestamp_out_of_range", f"event_ts {event_ts.isoformat()} is before the system start", event)

    warnings = []
    lat, lon, capacity = event.get("lat"), event.get("lon"), event.get("capacity")
    if lat is None or lon is None:
        warnings.append("missing_station_information")
        lat = lon = None
    elif not all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in (lat, lon)):
        raise ValidationError("invalid_type", "lat and lon must be numbers", event)
    elif not (CDMX_BBOX["lat"][0] <= lat <= CDMX_BBOX["lat"][1] and CDMX_BBOX["lon"][0] <= lon <= CDMX_BBOX["lon"][1]):
        warnings.append("location_outside_cdmx")
    if capacity is not None and not _is_int(capacity):
        raise ValidationError("invalid_type", "capacity must be an integer", event)
    total_slots = sum(event.get(f) or 0 for f in COUNT_FIELDS)
    if capacity is not None and total_slots > capacity:
        warnings.append("counts_exceed_capacity")
    lag = polled_at - event_ts
    if lag > STALE_AFTER:
        warnings.append("stale_report")
    for field in STRING_FIELDS:
        if event.get(field) is not None and not isinstance(event[field], str):
            raise ValidationError("invalid_type", f"{field} must be a string", event)

    return {
        "event_id": event["event_id"],
        "system_id": event["system_id"],
        "station_id": event["station_id"],
        "event_ts": _bq_ts(event_ts),
        "last_reported": event["last_reported"],
        **{f: event.get(f) for f in COUNT_FIELDS},
        **{f: event.get(f) for f in BOOL_FIELDS},
        "station_name": event.get("station_name"),
        "station_short_name": event.get("station_short_name"),
        "lat": float(lat) if lat is not None else None,
        "lon": float(lon) if lon is not None else None,
        "capacity": capacity,
        "feed_last_updated": _bq_ts(feed_last_updated),
        "polled_at": _bq_ts(polled_at),
        "poll_id": event.get("poll_id"),
        "schema_version": event["schema_version"],
        "publish_ts": _bq_ts(publish_ts),
        "ingest_ts": _bq_ts(ingest_ts),
        "report_age_seconds": int(lag.total_seconds()),
        "is_stale": lag > STALE_AFTER,
        "warnings": warnings,
    }


def error_row(stage: str, error_type: str, message: str, payload: bytes | str | None, attributes: dict | None,
              event: dict | None, publish_ts: datetime | None, ingest_ts: datetime) -> dict:
    if isinstance(payload, bytes):
        payload = payload.decode("utf-8", errors="replace")
    event = event if isinstance(event, dict) else {}
    station_id = event.get("station_id")
    return {
        "ingest_ts": _bq_ts(ingest_ts),
        "publish_ts": _bq_ts(publish_ts) if publish_ts else None,
        "stage": stage,
        "error_type": error_type,
        "error_message": message[:2000],
        "event_id": event.get("event_id") if isinstance(event.get("event_id"), str) else (attributes or {}).get("event_id"),
        "station_id": station_id if isinstance(station_id, str) else (attributes or {}).get("station_id"),
        "payload": payload,
        "attributes": json.dumps(attributes or {}, sort_keys=True),
    }
