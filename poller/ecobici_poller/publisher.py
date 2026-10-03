"""Publishes station events to Pub/Sub."""

from __future__ import annotations

import json
from concurrent import futures

from google.cloud import pubsub_v1


class PublishError(Exception):
    def __init__(self, message: str, published: int):
        super().__init__(message)
        self.published = published


class PubSubPublisher:
    def __init__(self, project: str, topic: str, client: pubsub_v1.PublisherClient | None = None):
        self.client = client or pubsub_v1.PublisherClient(
            batch_settings=pubsub_v1.types.BatchSettings(max_messages=500, max_latency=0.05))
        self.topic_path = self.client.topic_path(project, topic)

    def publish(self, events: list[dict], timeout: float = 30) -> int:
        """Sends every event and waits for all acknowledgements, so a 200 from /poll means the
        whole poll is in Pub/Sub. A partial failure raises and Cloud Scheduler retries; the
        repeated events carry the same IDs and are dropped downstream."""
        pending = [
            self.client.publish(
                self.topic_path,
                json.dumps(ev, separators=(",", ":")).encode(),
                event_id=ev["event_id"],
                station_id=ev["station_id"],
                schema_version=str(ev["schema_version"]),
            )
            for ev in events
        ]
        done, not_done = futures.wait(pending, timeout=timeout)
        errors = [f.exception() for f in done if f.exception() is not None]
        published = len(done) - len(errors)
        if errors or not_done:
            first = errors[0] if errors else "timeout"
            raise PublishError(f"{len(events) - published} of {len(events)} publishes failed, first: {first}", published)
        return published
