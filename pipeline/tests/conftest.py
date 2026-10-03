import json
from datetime import datetime, timezone

import pytest

POLLED_AT = datetime(2026, 10, 3, 16, 32, tzinfo=timezone.utc)
LAST_REPORTED = 1791045083  # 2026-10-03T16:31:23Z


def make_event(**overrides):
    """An event as the Go poller publishes it (station 1 of the live feed)."""
    event = {
        "schema_version": 1,
        "event_id": f"MEX-1-{LAST_REPORTED}",
        "system_id": "MEX",
        "station_id": "1",
        "last_reported": LAST_REPORTED,
        "event_ts": "2026-10-03T16:31:23Z",
        "num_bikes_available": 18,
        "num_bikes_disabled": 1,
        "num_docks_available": 20,
        "num_docks_disabled": 0,
        "is_installed": True,
        "is_renting": True,
        "is_returning": True,
        "station_name": "CE-710 Molino del Rey - Glorieta de la Lealtad",
        "station_short_name": "710",
        "lat": 19.416795,
        "lon": -99.192508,
        "capacity": 39,
        "feed_last_updated": "2026-10-03T16:31:30Z",
        "polled_at": "2026-10-03T16:32:00.123456Z",
        "poll_id": "a1b2c3d4e5f60718",
    }
    event.update(overrides)
    return event


@pytest.fixture
def payload():
    return lambda **overrides: json.dumps(make_event(**overrides)).encode()
