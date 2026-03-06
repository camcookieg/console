#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/camcookie-games"
VENV_DIR="$TARGET_DIR/.venv"
DESKTOP_FILE="$HOME/.local/share/applications/camcookie-games.desktop"
ICON_FILE="$TARGET_DIR/assets/camcookie-icon.svg"
LAN_SERVICE_FILE="$HOME/.config/systemd/user/camcookie-lan.service"

log() { printf '\n[Camcookie Installer] %s\n' "$1"; }

ensure_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command '$1' is missing. Install it and rerun." >&2
    exit 1
  fi
}

install_system_packages() {
  log "Installing required Raspberry Pi packages"
  sudo apt-get update
  sudo apt-get install -y \
    python3 python3-venv python3-pip python3-full \
    python3-pygame python3-flask python3-psutil \
    joystick jstest-gtk \
    ffmpeg vlc chromium-browser rsync
}

sync_repo() {
  log "Copying project files into $TARGET_DIR"
  mkdir -p "$TARGET_DIR"
  rsync -a --delete \
    --exclude '.git' \
    --exclude '.venv' \
    --exclude '__pycache__' \
    "$REPO_DIR/" "$TARGET_DIR/"
}

build_venv() {
  log "Creating Python virtual environment"
  python3 -m venv "$VENV_DIR"
  # shellcheck disable=SC1091
  source "$VENV_DIR/bin/activate"
  pip install --upgrade pip
  pip install -r "$TARGET_DIR/requirements.txt"
}

write_default_data() {
  log "Preparing profile/config defaults"
  mkdir -p "$TARGET_DIR/profiles" "$TARGET_DIR/assets"

  [[ -f "$TARGET_DIR/profiles/accounts.json" ]] || cat > "$TARGET_DIR/profiles/accounts.json" <<'JSON'
[
  {
    "username": "Player1",
    "password": "1234",
    "theme": "ocean",
    "avatar": "default",
    "achievements": [],
    "rewards": [],
    "worlds": []
  }
]
JSON

  [[ -f "$TARGET_DIR/profiles/system_config.json" ]] || cat > "$TARGET_DIR/profiles/system_config.json" <<'JSON'
{
  "language": "en-US",
  "region": "US",
  "wifi_name": "",
  "theme": "ocean",
  "device_connect_id": "CAMCOOKIE-PI4B",
  "setup_complete": false,
  "last_user": "",
  "boot_sound": true,
  "notifications_enabled": true
}
JSON

  [[ -f "$TARGET_DIR/profiles/notifications.json" ]] || echo "[]" > "$TARGET_DIR/profiles/notifications.json"
}

create_icon() {
  if [[ -f "$ICON_FILE" ]]; then
    return
  fi

  log "Creating placeholder icon"
  cat > "$ICON_FILE" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <defs>
    <linearGradient id="g" x1="0" x2="1" y1="0" y2="1">
      <stop offset="0" stop-color="#0f2746"/>
      <stop offset="1" stop-color="#1e88e5"/>
    </linearGradient>
  </defs>
  <rect width="256" height="256" fill="url(#g)" rx="40"/>
  <circle cx="128" cy="128" r="84" fill="#4ab0ff"/>
  <text x="128" y="146" font-size="68" text-anchor="middle" fill="#ffffff" font-family="sans-serif">CG</text>
</svg>
SVG
}

create_lan_service() {
  log "Installing user service for Camcookie LAN"
  mkdir -p "$(dirname "$LAN_SERVICE_FILE")"
  cat > "$LAN_SERVICE_FILE" <<EOF
[Unit]
Description=Camcookie LAN Service
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$TARGET_DIR
ExecStart=$VENV_DIR/bin/python -m camcookie.lan.server
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload || true
  systemctl --user enable --now camcookie-lan.service || true
}

create_desktop_entry() {
  log "Creating Raspberry Pi menu launcher"
  mkdir -p "$(dirname "$DESKTOP_FILE")"
  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=Camcookie Games
Comment=Launch Camcookie console environment
Exec=bash -lc 'pkill -f lxterminal || true; $TARGET_DIR/camcookie/scripts/run_camcookie.sh'
Icon=$ICON_FILE
Terminal=false
Type=Application
Categories=Game;System;
EOF
  chmod +x "$DESKTOP_FILE"
  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
}

final_message() {
  cat <<EOF

Camcookie Games installed successfully.

Launch from Raspberry Pi menu: Camcookie Games
or run: $TARGET_DIR/camcookie/scripts/run_camcookie.sh

Inside Camcookie Games:
- Controller and keyboard navigation are active.
- Press ESC to return to Raspberry Pi OS.
- LAN service is available at http://<pi-ip>:8088
EOF
}

main() {
  ensure_command python3
  ensure_command sudo

  install_system_packages
  sync_repo
  build_venv
  write_default_data
  create_icon
  create_lan_service
  create_desktop_entry
  final_message
}

main "$@"
