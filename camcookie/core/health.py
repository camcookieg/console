from __future__ import annotations

import platform
import shutil
from pathlib import Path

import psutil


def system_health(base_dir: Path) -> dict:
    usage = shutil.disk_usage(base_dir)
    return {
        "platform": platform.platform(),
        "cpu_percent": psutil.cpu_percent(interval=0.1),
        "memory_percent": psutil.virtual_memory().percent,
        "disk_percent": round((usage.used / usage.total) * 100, 2),
        "disk_free_gb": round(usage.free / (1024**3), 2),
    }
