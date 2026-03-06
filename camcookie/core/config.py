from __future__ import annotations

import json
from pathlib import Path


class ConfigManager:
    """Loads and stores global Camcookie configuration."""

    def __init__(self, base_dir: Path):
        self.base_dir = base_dir
        self.config_path = base_dir / "profiles" / "system_config.json"
        self.default_config = {
            "language": "en-US",
            "region": "US",
            "theme": "ocean",
            "wifi_name": "",
            "device_connect_id": "",
            "setup_complete": False,
        }

    def load(self) -> dict:
        if not self.config_path.exists():
            return dict(self.default_config)
        with self.config_path.open("r", encoding="utf-8") as fp:
            return {**self.default_config, **json.load(fp)}

    def save(self, config: dict) -> None:
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        with self.config_path.open("w", encoding="utf-8") as fp:
            json.dump(config, fp, indent=2)
