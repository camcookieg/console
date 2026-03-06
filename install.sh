#!/usr/bin/env bash
set -euo pipefail

# Camcookie Games one-shot installer for Raspberry Pi 4B
# Safe model: installs into user-space, no kernel or login replacement.

DEFAULT_USER="camcookieg"
INSTALL_USER="${SUDO_USER:-${USER}}"
if [[ "$INSTALL_USER" == "root" ]]; then
  INSTALL_USER="$DEFAULT_USER"
fi

HOME_DIR="$(getent passwd "$INSTALL_USER" | cut -d: -f6 || true)"
if [[ -z "$HOME_DIR" ]]; then
  HOME_DIR="/home/$INSTALL_USER"
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME_DIR/camcookie-games"
VENV_DIR="$TARGET_DIR/.venv"
DESKTOP_FILE="$HOME_DIR/.local/share/applications/camcookie-games.desktop"
LAN_SERVICE_FILE="$HOME_DIR/.config/systemd/user/camcookie-lan.service"
LAUNCH_SCRIPT="$TARGET_DIR/camcookie/scripts/run_camcookie.sh"
ICON_FILE="$TARGET_DIR/assets/camcookie-icon.svg"

log() { printf '\n[Camcookie Installer] %s\n' "$1"; }

ensure_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command '$1' is missing. Install it and rerun." >&2
    exit 1
  fi
}

as_user() {
  sudo -u "$INSTALL_USER" "$@"
}

cleanup_old_install() {
  log "Removing old Camcookie files before reinstall"

  # Remove old install dir entirely so stale files never survive upgrades.
  if [[ -d "$TARGET_DIR" ]]; then
    rm -rf "$TARGET_DIR"
  fi

  # Remove prior launcher/service entries if they exist.
  rm -f "$DESKTOP_FILE" "$LAN_SERVICE_FILE"

  # Remove known legacy paths from earlier versions.
  rm -rf "$HOME_DIR/.camcookie-games"
  rm -f "$HOME_DIR/Desktop/Camcookie Games.desktop"
}

install_system_packages() {
  log "Installing required Raspberry Pi packages"
  sudo apt-get update
  sudo apt-get install -y \
    python3 python3-venv python3-pip python3-full \
    python3-pygame python3-flask python3-psutil python3-pytest \
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
  chown -R "$INSTALL_USER":"$INSTALL_USER" "$TARGET_DIR"
}

build_venv() {
  log "Creating Python virtual environment"
  as_user python3 -m venv "$VENV_DIR"
  as_user "$VENV_DIR/bin/pip" install --upgrade pip
  as_user "$VENV_DIR/bin/pip" install -r "$TARGET_DIR/requirements.txt"
}

write_default_data() {
  log "Preparing profile/config defaults"
  as_user mkdir -p "$TARGET_DIR/profiles" "$TARGET_DIR/assets"

  cat > "$TARGET_DIR/profiles/accounts.json" <<'JSON'
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

  cat > "$TARGET_DIR/profiles/system_config.json" <<'JSON'
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

  echo "[]" > "$TARGET_DIR/profiles/notifications.json"
  chown -R "$INSTALL_USER":"$INSTALL_USER" "$TARGET_DIR/profiles"
}

create_icon() {
  log "Creating Camcookie icon"
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
  chown "$INSTALL_USER":"$INSTALL_USER" "$ICON_FILE"
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
  chown "$INSTALL_USER":"$INSTALL_USER" "$LAN_SERVICE_FILE"

  as_user systemctl --user daemon-reload || true
  as_user systemctl --user enable --now camcookie-lan.service || true
}

create_desktop_entry() {
  log "Creating Raspberry Pi menu launcher"
  mkdir -p "$(dirname "$DESKTOP_FILE")"
  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=Camcookie Games
Comment=Launch Camcookie console environment
Exec=$LAUNCH_SCRIPT
Icon=$ICON_FILE
Terminal=false
Type=Application
Categories=Game;System;
EOF
  chmod +x "$DESKTOP_FILE"
  chown "$INSTALL_USER":"$INSTALL_USER" "$DESKTOP_FILE"
  as_user update-desktop-database "$HOME_DIR/.local/share/applications" >/dev/null 2>&1 || true
}

run_self_checks() {
  log "Running local validation checks"
  as_user "$VENV_DIR/bin/python" -m py_compile $(cd "$TARGET_DIR" && rg --files -g '*.py')
}

final_message() {
  cat <<EOF

Camcookie Games full version installed successfully.

Install user: $INSTALL_USER
Install path: $TARGET_DIR

Launch from Raspberry Pi menu: Camcookie Games
or run: $LAUNCH_SCRIPT

Inside Camcookie Games:
- Controller and keyboard navigation are active.
- Press ESC to return to Raspberry Pi OS.
- LAN service is available at http://<pi-ip>:8088

No GitHub password is required for installation when cloning from a public repo.
EOF
}

main() {
  ensure_command python3
  ensure_command sudo
  ensure_command rsync

  cleanup_old_install
  install_system_packages
  sync_repo
  build_venv
  write_default_data
  create_icon
  create_lan_service
  create_desktop_entry
  run_self_checks
  final_message
}

main "$@"
