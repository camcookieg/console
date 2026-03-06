#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BASE_DIR/.venv/bin/activate"
cd "$BASE_DIR"
python -m camcookie.ui.shell
