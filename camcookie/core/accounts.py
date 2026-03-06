from __future__ import annotations

import hashlib
import json
import secrets
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class Account:
    username: str
    password_hash: str
    salt: str
    theme: str = "ocean"
    avatar: str = "default"
    achievements: list[str] = field(default_factory=list)
    rewards: list[str] = field(default_factory=list)
    worlds: list[dict[str, Any]] = field(default_factory=list)

    def as_dict(self) -> dict[str, Any]:
        return {
            "username": self.username,
            "password_hash": self.password_hash,
            "salt": self.salt,
            "theme": self.theme,
            "avatar": self.avatar,
            "achievements": self.achievements,
            "rewards": self.rewards,
            "worlds": self.worlds,
        }


class AccountStore:
    def __init__(self, profiles_dir: Path):
        self.path = profiles_dir / "accounts.json"

    @staticmethod
    def _hash_password(password: str, salt: str) -> str:
        return hashlib.sha256(f"{salt}:{password}".encode("utf-8")).hexdigest()

    def load(self) -> list[dict[str, Any]]:
        if not self.path.exists():
            return []
        with self.path.open("r", encoding="utf-8") as fp:
            records: list[dict[str, Any]] = json.load(fp)

        upgraded = []
        for record in records:
            if "password" in record and "password_hash" not in record:
                salt = secrets.token_hex(8)
                password_hash = self._hash_password(record["password"], salt)
                record.pop("password", None)
                record["password_hash"] = password_hash
                record["salt"] = salt
            record.setdefault("theme", "ocean")
            record.setdefault("avatar", "default")
            record.setdefault("achievements", [])
            record.setdefault("rewards", [])
            record.setdefault("worlds", [])
            upgraded.append(record)

        if upgraded != records:
            self.save(upgraded)
        return upgraded

    def save(self, accounts: list[dict[str, Any]]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.path.open("w", encoding="utf-8") as fp:
            json.dump(accounts, fp, indent=2)

    def create_account(self, username: str, password: str, theme: str = "ocean") -> dict[str, Any]:
        accounts = self.load()
        if any(a["username"].lower() == username.lower() for a in accounts):
            raise ValueError("username already exists")
        salt = secrets.token_hex(8)
        account = Account(
            username=username,
            password_hash=self._hash_password(password, salt),
            salt=salt,
            theme=theme,
        )
        accounts.append(account.as_dict())
        self.save(accounts)
        return account.as_dict()

    def authenticate(self, username: str, password: str) -> dict[str, Any] | None:
        for account in self.load():
            if account["username"].lower() != username.lower():
                continue
            expected = self._hash_password(password, account["salt"])
            if secrets.compare_digest(expected, account["password_hash"]):
                return account
        return None

    def ensure_default_admin(self) -> list[dict[str, Any]]:
        accounts = self.load()
        if accounts:
            return accounts
        self.create_account(username="Player1", password="1234", theme="ocean")
        return self.load()

    def add_achievement(self, username: str, achievement: str, reward: str | None = None) -> None:
        accounts = self.load()
        for account in accounts:
            if account["username"].lower() != username.lower():
                continue
            if achievement not in account["achievements"]:
                account["achievements"].append(achievement)
            if reward and reward not in account["rewards"]:
                account["rewards"].append(reward)
            self.save(accounts)
            return

    def add_world(self, username: str, world_spec: dict[str, Any]) -> None:
        accounts = self.load()
        for account in accounts:
            if account["username"].lower() == username.lower():
                account["worlds"].append(world_spec)
                self.save(accounts)
                return
