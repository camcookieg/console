from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from datetime import datetime


@dataclass
class Notification:
    title: str
    body: str
    level: str = "info"
    created_at: str = ""

    def __post_init__(self) -> None:
        if not self.created_at:
            self.created_at = datetime.now().isoformat(timespec="seconds")


class NotificationCenter:
    def __init__(self, max_items: int = 50):
        self._items: deque[Notification] = deque(maxlen=max_items)

    def push(self, title: str, body: str, level: str = "info") -> None:
        self._items.appendleft(Notification(title=title, body=body, level=level))

    def latest(self, limit: int = 3) -> list[Notification]:
        return list(self._items)[:limit]
