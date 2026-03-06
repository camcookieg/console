from __future__ import annotations

import json
from pathlib import Path
from typing import Any


class ConfigManager:
    """Loads and stores global Camcookie configuration."""

    def __init__(self, base_dir: Path):
        self.base_dir = base_dir
        self.config_path = base_dir / "profiles" / "system_config.json"
        self.default_config: dict[str, Any] = {
            "language": "en-US",
            "region": "US",
            "theme": "ocean",
            "wifi_name": "",
            "device_connect_id": "",
            "setup_complete": False,
            "last_user": "",
            "boot_sound": True,
            "notifications_enabled": True,
        }

    def load(self) -> dict[str, Any]:
        if not self.config_path.exists():
            return dict(self.default_config)
        with self.config_path.open("r", encoding="utf-8") as fp:
            return {**self.default_config, **json.load(fp)}

    def save(self, config: dict[str, Any]) -> None:
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        with self.config_path.open("w", encoding="utf-8") as fp:
            json.dump(config, fp, indent=2)

    def update(self, **kwargs: Any) -> dict[str, Any]:
        config = self.load()
        config.update(kwargs)
        self.save(config)
        return config
