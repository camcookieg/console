# Camcookie Games

Camcookie Games is a **console-style operating environment layer** for Raspberry Pi 4B running on top of Raspberry Pi OS.

## Features

- Fullscreen console UI flow: boot animation → setup wizard → login → home menu
- Home menu tabs: Games / Apps / Settings
- Notification bubbles with persistent history
- LAN Device Connect server on port `8088` with upload dashboard
- Accounts, profiles, achievements, rewards, and AI-generated world specs
- Controller-first navigation with keyboard fallback

## Install (Raspberry Pi)

```bash
git clone https://github.com/<you>/camcookie-games.git
cd camcookie-games
chmod +x install.sh
./install.sh
```

### Installer behavior

- Targets user **`camcookieg`** automatically when run as root, otherwise current user.
- Deletes old Camcookie install files before reinstalling.
- Recreates launcher/service/config as fresh files each install.
- Uses public GitHub clone flow (no GitHub password required for public repos).

## Launch

Use the Raspberry Pi menu shortcut **Camcookie Games** or run:

```bash
/home/camcookieg/camcookie-games/camcookie/scripts/run_camcookie.sh
```

## Controls

- `←` / `→`: switch tabs
- `↑` / `↓`: change selected item
- `Enter`: select / launch
- `Esc`: exit back to Raspberry Pi OS

## LAN Dashboard

Open on your local network:

```text
http://<pi-ip>:8088
```

From there you can upload:
- Backgrounds
- Profile images
- Device Connect ID
