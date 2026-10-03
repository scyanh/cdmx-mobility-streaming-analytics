"""HTTP service for Cloud Run: Cloud Scheduler calls POST /poll every minute."""

from __future__ import annotations

import json
import os
import secrets
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

from flask import Flask, Response, jsonify

from ecobici_poller.events import build_events
from ecobici_poller.gbfs import FeedError, GBFSClient
from ecobici_poller.publisher import PublishError



def log(severity: str, message: str, **fields):
    # Cloud Run turns a JSON line on stdout into a structured entry with this severity.
    print(json.dumps({"severity": severity, "message": message, **fields}), flush=True)


def create_app(source, publisher, system_id: str = "MEX", now=lambda: datetime.now(timezone.utc)) -> Flask:
    app = Flask(__name__)
    fetcher = ThreadPoolExecutor(max_workers=2)

    @app.post("/poll")
    def poll():
        started = time.monotonic()
        polled_at = now()
        poll_id = secrets.token_hex(8)
        try:
            status_f = fetcher.submit(source.station_status)
            info_f = fetcher.submit(source.station_information)
            status, information = status_f.result(), info_f.result()
        except FeedError as exc:
            log("ERROR", "poll failed", poll_id=poll_id, error=str(exc))
            return Response(str(exc), status=502)

        events = build_events(system_id, status, information, polled_at, poll_id)
        result = {
            "poll_id": poll_id,
            "stations": len(events),
            "stations_without_information": sum(1 for e in events if e["lat"] is None),
            "feed_last_updated": events[0]["feed_last_updated"] if events else None,
        }
        try:
            result["published"] = publisher.publish(events)
        except PublishError as exc:
            log("ERROR", "poll failed", **{**result, "published": exc.published}, error=str(exc))
            return Response(str(exc), status=502)
        result["duration_ms"] = int((time.monotonic() - started) * 1000)
        log("INFO", "poll ok", **result)
        return jsonify(result)

    @app.get("/healthz")
    def healthz():
        return "", 204

    return app


def create_app_from_env() -> Flask:
    """Entry point for gunicorn; reads configuration from the environment."""
    from ecobici_poller.publisher import PubSubPublisher

    project = os.environ["GOOGLE_CLOUD_PROJECT"]
    return create_app(
        source=GBFSClient(os.environ.get("GBFS_BASE_URL", "https://gbfs.mex.lyftbikes.com/gbfs/es")),
        publisher=PubSubPublisher(project, os.environ.get("PUBSUB_TOPIC", "ecobici-station-status")),
        system_id=os.environ.get("SYSTEM_ID", "MEX"),
    )
