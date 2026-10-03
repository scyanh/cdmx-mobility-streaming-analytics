"""Reads ECOBICI's GBFS feeds."""

from __future__ import annotations

import requests


class FeedError(Exception):
    pass


class GBFSClient:
    def __init__(self, base_url: str, session: requests.Session | None = None, timeout: float = 20):
        self.base_url = base_url.rstrip("/")
        self.session = session or requests.Session()
        self.timeout = timeout

    def station_status(self) -> dict:
        return self._fetch("station_status.json")

    def station_information(self) -> dict:
        return self._fetch("station_information.json")

    def _fetch(self, name: str) -> dict:
        try:
            resp = self.session.get(f"{self.base_url}/{name}", timeout=self.timeout,
                                    headers={"Accept": "application/json"})
        except requests.RequestException as exc:
            raise FeedError(f"fetch {name}: {exc}") from exc
        if resp.status_code != 200:
            raise FeedError(f"fetch {name}: HTTP {resp.status_code}: {resp.text[:200]}")
        try:
            feed = resp.json()
            stations = feed["data"]["stations"]
        except (ValueError, KeyError, TypeError) as exc:
            raise FeedError(f"decode {name}: {exc!r}") from exc
        if not isinstance(stations, list) or not stations:
            raise FeedError(f"{name} has no stations")
        return feed
