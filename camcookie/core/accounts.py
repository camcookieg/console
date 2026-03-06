from __future__ import annotations

import json
from pathlib import Path
from typing import Any


class AccountStore:
    def __init__(self, profiles_dir: Path):
        self.path = profiles_dir / "accounts.json"

    def load(self) -> list[dict[str, Any]]:
        if not self.path.exists():
            return []
        with self.path.open("r", encoding="utf-8") as fp:
            return json.load(fp)

    def save(self, accounts: list[dict[str, Any]]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.path.open("w", encoding="utf-8") as fp:
            json.dump(accounts, fp, indent=2)

    def ensure_default_admin(self) -> list[dict[str, Any]]:
        accounts = self.load()
        if accounts:
            return accounts
        accounts = [
            {
                "username": "Player1",
                "password": "1234",
                "theme": "ocean",
                "avatar": "default",
                "achievements": [],
            }
        ]
        self.save(accounts)
        return accounts
