from __future__ import annotations

import json
from collections import deque
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


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
    def __init__(self, storage_path: Path, max_items: int = 100):
        self.storage_path = storage_path
        self._items: deque[Notification] = deque(maxlen=max_items)
        self._load()

    def _load(self) -> None:
        if not self.storage_path.exists():
            return
        data = json.loads(self.storage_path.read_text(encoding="utf-8"))
        for item in data:
            self._items.append(Notification(**item))

    def _save(self) -> None:
        self.storage_path.parent.mkdir(parents=True, exist_ok=True)
        data = [asdict(item) for item in self._items]
        self.storage_path.write_text(json.dumps(data, indent=2), encoding="utf-8")

    def push(self, title: str, body: str, level: str = "info") -> None:
        self._items.appendleft(Notification(title=title, body=body, level=level))
        self._save()

    def latest(self, limit: int = 3) -> list[Notification]:
        return list(self._items)[:limit]

    def all(self) -> list[Notification]:
        return list(self._items)
