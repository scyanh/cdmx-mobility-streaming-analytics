"""Runs the poller's event builder on its fixtures and checks the pipeline accepts the output."""

import importlib.util
import json
from datetime import datetime, timezone
from pathlib import Path

from mobility_pipeline.validation import ValidationError, validate_event

POLLER = Path(__file__).resolve().parents[2] / "poller"
spec = importlib.util.spec_from_file_location("poller_events", POLLER / "ecobici_poller" / "events.py")
poller_events = importlib.util.module_from_spec(spec)
spec.loader.exec_module(poller_events)


def test_poller_events_pass_validation():
    status = json.loads((POLLER / "testdata" / "station_status.json").read_text())
    info = json.loads((POLLER / "testdata" / "station_information.json").read_text())
    now = datetime(2026, 10, 3, 16, 33, tzinfo=timezone.utc)
    outcome = {}
    for ev in poller_events.build_events("MEX", status, info, now, "p1"):
        try:
            validate_event(json.dumps(ev).encode(), {"event_id": ev["event_id"]}, now, now)
            outcome[ev["station_id"]] = "valid"
        except ValidationError as exc:
            outcome[ev["station_id"]] = exc.error_type
    # Station 999 has no last_reported, so it has no event time and goes to the DLQ.
    assert outcome == {"1": "valid", "5": "valid", "6": "valid", "999": "missing_field"}
