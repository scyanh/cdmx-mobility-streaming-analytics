"""The fixtures are the first three stations of the live feed plus station 999, written by hand
the way other GBFS publishers send it: numeric ID, true/false booleans, no disabled counts,
null last_reported and no entry in station_information."""

import functools
import http.server
import threading
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

from ecobici_poller.app import create_app
from ecobici_poller.events import build_events
from ecobici_poller.gbfs import FeedError, GBFSClient
from ecobici_poller.publisher import PublishError

TESTDATA = Path(__file__).parent.parent / "testdata"
NOW = datetime(2026, 10, 3, 16, 32, tzinfo=timezone.utc)


@pytest.fixture
def feed_url():
    class Quiet(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass

    handler = functools.partial(Quiet, directory=str(TESTDATA))
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{srv.server_address[1]}"
    srv.shutdown()


class FakePublisher:
    def __init__(self, error=None):
        self.events, self.error = [], error

    def publish(self, events):
        self.events.extend(events)
        if self.error:
            raise self.error
        return len(events)


def client_for(source, publisher, now=lambda: NOW):
    return create_app(source, publisher, now=now).test_client()


def by_station(events):
    return {e["station_id"]: e for e in events}


def test_poll_publishes_one_event_per_station(feed_url):
    pub = FakePublisher()
    resp = client_for(GBFSClient(feed_url), pub).post("/poll")
    assert resp.status_code == 200, resp.data
    body = resp.get_json()
    assert (body["stations"], body["published"], body["stations_without_information"]) == (4, 4, 1)
    assert body["feed_last_updated"] == "2026-10-03T16:32:08Z"
    assert len(pub.events) == 4


def test_events_carry_station_attributes(feed_url):
    pub = FakePublisher()
    client_for(GBFSClient(feed_url), pub).post("/poll")
    ev = by_station(pub.events)["1"]
    assert ev["event_id"] == "MEX-1-1791045083"
    assert ev["event_ts"] == "2026-10-03T16:31:23Z"
    assert ev["station_name"] == "CE-710 Molino del Rey - Glorieta de la Lealtad"
    assert (ev["capacity"], ev["lat"], ev["lon"]) == (39, 19.416795, -99.192508)
    assert ev["is_renting"] is True and ev["num_bikes_available"] == 18
    assert ev["polled_at"] == "2026-10-03T16:32:00Z" and ev["schema_version"] == 1


def test_missing_fields_stay_null(feed_url):
    pub = FakePublisher()
    client_for(GBFSClient(feed_url), pub).post("/poll")
    ev = by_station(pub.events)["999"]  # numeric station_id in the feed
    assert ev["event_id"] == "MEX-999-unknown"
    assert ev["event_ts"] is None and ev["last_reported"] is None
    assert ev["num_bikes_disabled"] is None and ev["num_docks_disabled"] is None
    assert ev["is_returning"] is False
    assert ev["station_name"] is None and ev["lat"] is None


def test_event_id_is_stable_across_polls(feed_url):
    pub = FakePublisher()
    times = iter([NOW, NOW + timedelta(minutes=1)])
    client = client_for(GBFSClient(feed_url), pub, now=lambda: next(times))
    first, second = client.post("/poll").get_json(), client.post("/poll").get_json()
    assert first["poll_id"] != second["poll_id"]
    assert [e["event_id"] for e in pub.events[:4]] == [e["event_id"] for e in pub.events[4:]]
    assert pub.events[0]["polled_at"] != pub.events[4]["polled_at"]


def test_upstream_error_returns_502(feed_url):
    pub = FakePublisher()
    resp = client_for(GBFSClient(feed_url + "/missing"), pub).post("/poll")
    assert resp.status_code == 502 and b"HTTP 404" in resp.data
    assert pub.events == []


def test_publish_error_returns_502_so_scheduler_retries(feed_url):
    resp = client_for(GBFSClient(feed_url), FakePublisher(PublishError("pubsub down", 1))).post("/poll")
    assert resp.status_code == 502


def test_poll_rejects_get(feed_url):
    assert client_for(GBFSClient(feed_url), FakePublisher()).get("/poll").status_code == 405


def test_empty_feed_is_an_error():
    class Empty:
        def get(self, *args, **kwargs):
            class R:
                status_code = 200
                text = ""

                def json(self):
                    return {"data": {"stations": []}}
            return R()

    with pytest.raises(FeedError, match="no stations"):
        GBFSClient("http://x", session=Empty()).station_status()


@pytest.mark.parametrize("raw, want", [(1, True), (0, False), (True, True), (False, False), ("1", "1"), (0.0, 0.0)])
def test_gbfs_booleans(raw, want):
    status = {"last_updated": 1, "data": {"stations": [{"station_id": "1", "is_renting": raw}]}}
    ev = build_events("MEX", status, {"data": {"stations": []}}, NOW, "p")[0]
    assert ev["is_renting"] == want and type(ev["is_renting"]) is type(want)
