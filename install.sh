#!/usr/bin/env bash
set -euo pipefail

# Camcookie Games single-file installer.
# This script creates the full project tree and all runtime files.

INSTALL_USER="${SUDO_USER:-${USER}}"
[[ "$INSTALL_USER" == "root" ]] && INSTALL_USER="camcookieg"
HOME_DIR="$(getent passwd "$INSTALL_USER" | cut -d: -f6 || true)"
[[ -z "$HOME_DIR" ]] && HOME_DIR="/home/$INSTALL_USER"

TARGET_DIR="$HOME_DIR/camcookie-games"
VENV_DIR="$TARGET_DIR/.venv"
DESKTOP_FILE="$HOME_DIR/.local/share/applications/camcookie-games.desktop"
SERVICE_FILE="$HOME_DIR/.config/systemd/user/camcookie-lan.service"

log(){ printf '\n[Camcookie Installer] %s\n' "$1"; }
run_as_user(){ sudo -u "$INSTALL_USER" "$@"; }

require(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }

clean_old(){
  log "Removing old install"
  rm -rf "$TARGET_DIR"
  rm -f "$DESKTOP_FILE" "$SERVICE_FILE" "$HOME_DIR/Desktop/Camcookie Games.desktop"
}

install_packages(){
  log "Installing system dependencies"
  sudo apt-get update
  sudo apt-get install -y \
    python3 python3-venv python3-pip python3-full \
    python3-pygame python3-flask python3-psutil \
    chromium-browser vlc ffmpeg rsync joystick jstest-gtk
}

write_files(){
  log "Creating Camcookie project files"
  mkdir -p "$TARGET_DIR"/{camcookie/{core,ui,lan,games,apps,scripts},profiles,assets}

  cat > "$TARGET_DIR/requirements.txt" <<'TXT'
flask>=3.0.0
pygame>=2.5.0
psutil>=5.9.0
TXT

  for pkg in camcookie camcookie/core camcookie/ui camcookie/lan camcookie/games camcookie/apps; do
    echo > "$TARGET_DIR/$pkg/__init__.py"
  done

  cat > "$TARGET_DIR/camcookie/core/config.py" <<'PY'
from __future__ import annotations
import json
from pathlib import Path

class ConfigManager:
    def __init__(self, base_dir: Path):
        self.path = base_dir / "profiles" / "system_config.json"
        self.default = {
            "language": "en-US", "region": "US", "theme": "ocean", "wifi_name": "",
            "device_connect_id": "CAMCOOKIE-PI4B", "setup_complete": False,
            "last_user": "", "boot_sound": True, "notifications_enabled": True,
        }

    def load(self) -> dict:
        if not self.path.exists():
            return dict(self.default)
        with self.path.open("r", encoding="utf-8") as f:
            return {**self.default, **json.load(f)}

    def save(self, data: dict) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.path.open("w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)

    def update(self, **kwargs) -> dict:
        c = self.load(); c.update(kwargs); self.save(c); return c
PY

  cat > "$TARGET_DIR/camcookie/core/accounts.py" <<'PY'
from __future__ import annotations
import hashlib, json, secrets
from pathlib import Path

class AccountStore:
    def __init__(self, profiles_dir: Path):
        self.path = profiles_dir / "accounts.json"

    @staticmethod
    def _h(password: str, salt: str) -> str:
        return hashlib.sha256(f"{salt}:{password}".encode()).hexdigest()

    def load(self) -> list[dict]:
        if not self.path.exists(): return []
        data = json.loads(self.path.read_text(encoding="utf-8"))
        changed = False
        for a in data:
            if "password" in a and "password_hash" not in a:
                salt = secrets.token_hex(8)
                a["password_hash"] = self._h(a.pop("password"), salt)
                a["salt"] = salt
                changed = True
            a.setdefault("theme", "ocean"); a.setdefault("avatar", "default")
            a.setdefault("achievements", []); a.setdefault("rewards", []); a.setdefault("worlds", [])
        if changed: self.save(data)
        return data

    def save(self, accounts: list[dict]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(accounts, indent=2), encoding="utf-8")

    def create_account(self, username: str, password: str, theme: str = "ocean") -> dict:
        accounts = self.load()
        if any(a["username"].lower() == username.lower() for a in accounts):
            raise ValueError("username already exists")
        salt = secrets.token_hex(8)
        user = {"username": username, "password_hash": self._h(password, salt), "salt": salt,
                "theme": theme, "avatar": "default", "achievements": [], "rewards": [], "worlds": []}
        accounts.append(user); self.save(accounts); return user

    def authenticate(self, username: str, password: str) -> dict | None:
        for a in self.load():
            if a["username"].lower() == username.lower() and secrets.compare_digest(self._h(password, a["salt"]), a["password_hash"]):
                return a
        return None

    def ensure_default_admin(self) -> None:
        if not self.load(): self.create_account("Player1", "1234", "ocean")

    def add_world(self, username: str, world: dict) -> None:
        data = self.load()
        for a in data:
            if a["username"].lower() == username.lower():
                a["worlds"].append(world)
                if "World Architect" not in a["achievements"]: a["achievements"].append("World Architect")
                if "AI Creator Badge" not in a["rewards"]: a["rewards"].append("AI Creator Badge")
                self.save(data)
                return
PY

  cat > "$TARGET_DIR/camcookie/core/notifications.py" <<'PY'
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
    def __post_init__(self):
        if not self.created_at: self.created_at = datetime.now().isoformat(timespec="seconds")

class NotificationCenter:
    def __init__(self, path: Path, max_items: int = 100):
        self.path = path
        self.items: deque[Notification] = deque(maxlen=max_items)
        if path.exists():
            for i in json.loads(path.read_text(encoding="utf-8")): self.items.append(Notification(**i))

    def push(self, title: str, body: str, level: str = "info") -> None:
        self.items.appendleft(Notification(title=title, body=body, level=level))
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps([asdict(n) for n in self.items], indent=2), encoding="utf-8")

    def latest(self, n: int = 5) -> list[Notification]:
        return list(self.items)[:n]
PY

  cat > "$TARGET_DIR/camcookie/core/health.py" <<'PY'
from __future__ import annotations
import platform, shutil, psutil
from pathlib import Path

def system_health(base_dir: Path) -> dict:
    d = shutil.disk_usage(base_dir)
    return {
        "platform": platform.platform(),
        "cpu_percent": psutil.cpu_percent(interval=0.1),
        "memory_percent": psutil.virtual_memory().percent,
        "disk_free_gb": round(d.free / (1024 ** 3), 2),
    }
PY

  cat > "$TARGET_DIR/camcookie/apps/registry.py" <<'PY'
APPS = [
    {"id": "browser", "name": "Browser (Chromium Kiosk)", "command": "chromium-browser --kiosk"},
    {"id": "file_editor", "name": "File Editor", "command": "nano"},
    {"id": "media_player", "name": "Media Player", "command": "vlc"},
    {"id": "system_monitor", "name": "System Monitor", "command": "htop"},
    {"id": "device_connect", "name": "Device Connect", "command": "xdg-open http://127.0.0.1:8088"},
]
PY

  cat > "$TARGET_DIR/camcookie/games/registry.py" <<'PY'
GAMES = [
    {"id": "retro2d", "name": "Retro 2D Engine", "status": "ready"},
    {"id": "early2000s", "name": "Early 2000s 2D Engine", "status": "ready"},
    {"id": "hybrid360", "name": "360° Hybrid Engine", "status": "ready"},
    {"id": "infinite_worlds", "name": "Infinite Worlds", "status": "beta"},
    {"id": "guided_worlds", "name": "Guided Worlds", "status": "beta"},
]
PY

  cat > "$TARGET_DIR/camcookie/games/ai_maker.py" <<'PY'
from __future__ import annotations
import random
from datetime import datetime

def generate_world_spec(prompt: str) -> dict:
    engines = ["retro2d", "early2000s", "hybrid360", "infinite_worlds", "guided_worlds"]
    biomes = ["forest", "city", "desert", "space", "ocean", "volcanic"]
    return {
        "title": f"AI World: {prompt[:40]}",
        "prompt": prompt,
        "engine": random.choice(engines),
        "biome": random.choice(biomes),
        "difficulty": random.choice(["easy", "normal", "hard"]),
        "seed": random.randint(1000, 999999),
        "created_at": datetime.utcnow().isoformat(timespec="seconds") + "Z",
    }
PY

  cat > "$TARGET_DIR/camcookie/games/manager.py" <<'PY'
from __future__ import annotations
from camcookie.games.ai_maker import generate_world_spec

class GameManager:
    def __init__(self, accounts, notifications):
        self.accounts = accounts
        self.notifications = notifications

    def create_ai_world(self, username: str, prompt: str) -> dict:
        world = generate_world_spec(prompt)
        self.accounts.add_world(username, world)
        self.notifications.push("AI Game Maker", f"World generated for {username}", "success")
        return world
PY

  cat > "$TARGET_DIR/camcookie/lan/server.py" <<'PY'
from __future__ import annotations
import json
from pathlib import Path
from flask import Flask, jsonify, render_template_string, request
from werkzeug.utils import secure_filename

INDEX = """
<!doctype html><html><head><meta charset='utf-8'><title>Camcookie Device Connect</title>
<style>body{font-family:sans-serif;background:#0f1f3a;color:#e9f3ff;padding:2rem}.card{background:#1b3158;border-radius:12px;padding:1rem;margin-bottom:1rem}button{padding:.6rem;border-radius:8px;border:none;background:#4aa8ff;color:#fff}</style>
</head><body><h1>🎮 Camcookie Device Connect</h1>
<div class='card'><h3>Upload Background</h3><form action='/upload/background' method='post' enctype='multipart/form-data'><input type='file' name='file' required><button>Upload</button></form></div>
<div class='card'><h3>Upload Profile Image</h3><form action='/upload/profile-image' method='post' enctype='multipart/form-data'><input name='username' placeholder='Username' required><input type='file' name='file' required><button>Upload</button></form></div>
<div class='card'><h3>Set Device Connect ID</h3><form id='f'><input id='i' placeholder='CAMCOOKIE-XXXX' required><button>Save</button></form><pre id='r'></pre></div>
<script>document.getElementById('f').onsubmit=async(e)=>{e.preventDefault();const id=document.getElementById('i').value;const res=await fetch('/device-connect',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({device_connect_id:id})});document.getElementById('r').textContent=JSON.stringify(await res.json(),null,2)};</script>
</body></html>
"""

def build_app(base_dir: Path) -> Flask:
    app = Flask(__name__)
    uploads = base_dir / "profiles" / "uploads"; uploads.mkdir(parents=True, exist_ok=True)
    cfg = base_dir / "profiles" / "system_config.json"

    def load_cfg():
        return json.loads(cfg.read_text(encoding="utf-8")) if cfg.exists() else {}

    def save_cfg(data):
        cfg.parent.mkdir(parents=True, exist_ok=True)
        cfg.write_text(json.dumps(data, indent=2), encoding="utf-8")

    @app.get("/")
    def index(): return render_template_string(INDEX)

    @app.get("/health")
    def health(): return jsonify({"status": "ok", "service": "camcookie-lan"})

    @app.get("/uploads")
    def files(): return jsonify({"files": sorted(p.name for p in uploads.glob("*"))})

    @app.post("/upload/background")
    def up_bg():
        f = request.files.get("file")
        if not f: return jsonify({"error": "file required"}), 400
        n = f"background_{secure_filename(f.filename)}"; f.save(uploads / n)
        return jsonify({"message": "background uploaded", "file": n})

    @app.post("/upload/profile-image")
    def up_pf():
        f = request.files.get("file"); u = secure_filename(request.form.get("username", "default"))
        if not f: return jsonify({"error": "file required"}), 400
        n = f"avatar_{u}_{secure_filename(f.filename)}"; f.save(uploads / n)
        return jsonify({"message": "profile image uploaded", "file": n})

    @app.post("/device-connect")
    def connect():
        payload = request.get_json(silent=True) or {}
        c = load_cfg(); c["device_connect_id"] = payload.get("device_connect_id", "")
        save_cfg(c)
        return jsonify({"message": "device connect id saved", "device_connect_id": c["device_connect_id"]})

    return app

if __name__ == "__main__":
    base = Path(__file__).resolve().parents[2]
    build_app(base).run(host="0.0.0.0", port=8088)
PY

  cat > "$TARGET_DIR/camcookie/ui/shell.py" <<'PY'
from __future__ import annotations
import socket, subprocess, sys, time
from pathlib import Path
import pygame
from camcookie.apps.registry import APPS
from camcookie.core.accounts import AccountStore
from camcookie.core.config import ConfigManager
from camcookie.core.health import system_health
from camcookie.core.notifications import NotificationCenter
from camcookie.games.manager import GameManager
from camcookie.games.registry import GAMES

TABS=["Games","Apps","Settings"]
THEMES={"ocean":((16,25,48),(90,210,255),(255,206,84)),"sunset":((46,22,37),(255,136,79),(255,215,128)),"forest":((14,38,27),(109,210,164),(242,255,191))}

class Console:
    def __init__(self):
        self.base=Path(__file__).resolve().parents[2]
        self.cfg=ConfigManager(self.base)
        self.acc=AccountStore(self.base/"profiles")
        self.notes=NotificationCenter(self.base/"profiles"/"notifications.json")
        self.games=GameManager(self.acc,self.notes)
        self.acc.ensure_default_admin()
        self.user=None; self.tab=0; self.sel=0; self.state="boot"; self.running=True; self.lan=None; self.password=""

    def draw(self, font, text, pos, color=(255,255,255)): self.screen.blit(font.render(text,True,color),pos)

    def start_lan(self):
        with socket.socket(socket.AF_INET,socket.SOCK_STREAM) as s:
            if s.connect_ex(("127.0.0.1",8088))==0: return
        self.lan=subprocess.Popen([sys.executable,"-m","camcookie.lan.server"],cwd=str(self.base),stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

    def boot(self):
        st=time.time()
        while self.running and time.time()-st<2.0:
            for e in pygame.event.get():
                if e.type==pygame.KEYDOWN and e.key==pygame.K_ESCAPE: self.running=False
            p=min(1.0,(time.time()-st)/2.0)
            self.screen.fill((8,14,30)); self.draw(self.font,"Camcookie Games",(430,290),(90,210,255))
            pygame.draw.rect(self.screen,(40,52,75),pygame.Rect(320,360,640,24),border_radius=10)
            pygame.draw.rect(self.screen,(90,210,255),pygame.Rect(320,360,int(640*p),24),border_radius=10)
            pygame.display.flip(); self.clock.tick(60)
        self.state="setup" if not self.cfg.load()["setup_complete"] else "login"

    def setup(self):
        steps=["Language","Region","Wi-Fi","Account","Password","Controller","Device Connect ID","Theme","Finish"]; i=0
        while self.running and self.state=="setup":
            for e in pygame.event.get():
                if e.type==pygame.KEYDOWN:
                    if e.key==pygame.K_ESCAPE: self.running=False
                    elif e.key in (pygame.K_RETURN,pygame.K_RIGHT,pygame.K_SPACE): i+=1
                    elif e.key==pygame.K_LEFT: i=max(0,i-1)
            if i>=len(steps):
                c=self.cfg.load(); c["setup_complete"]=True; self.cfg.save(c); self.notes.push("Setup","Completed","success"); self.state="login"; break
            self.screen.fill((14,31,52)); self.draw(self.small,"First Boot Setup Wizard",(40,40),(90,210,255))
            self.draw(self.small,f"Step {i+1}/{len(steps)}: {steps[i]}",(80,220)); pygame.display.flip(); self.clock.tick(60)

    def login(self):
        accounts=self.acc.load(); idx=0; self.password=""
        while self.running and self.state=="login":
            for e in pygame.event.get():
                if e.type==pygame.KEYDOWN:
                    if e.key==pygame.K_ESCAPE: self.running=False
                    elif e.key in (pygame.K_DOWN,): idx=min(len(accounts)-1,idx+1)
                    elif e.key in (pygame.K_UP,): idx=max(0,idx-1)
                    elif e.key==pygame.K_BACKSPACE: self.password=self.password[:-1]
                    elif e.key==pygame.K_RETURN:
                        a=accounts[idx]; auth=self.acc.authenticate(a["username"],self.password or "1234")
                        if auth: self.user=auth; self.cfg.update(last_user=auth["username"]); self.notes.push("Login",f"Welcome {auth['username']}","success"); self.state="home"
                        else: self.notes.push("Login","Invalid password","error"); self.password=""
                    elif e.unicode.isdigit() and len(self.password)<12: self.password+=e.unicode
            self.screen.fill((11,20,38)); self.draw(self.small,"Account Select",(40,40),(90,210,255)); self.draw(self.small,f"Password: {'*'*len(self.password)}",(40,90),(255,206,84))
            for i,a in enumerate(accounts): self.draw(self.small,f"{a['username']} • {a['theme']}",(80,180+i*50),(255,206,84) if i==idx else (220,220,220))
            self.draw_notes(); pygame.display.flip(); self.clock.tick(60)

    def draw_notes(self):
        self.draw(self.small,"Notifications",(850,30),(90,210,255))
        for i,n in enumerate(self.notes.latest(5)): self.draw(self.tiny,f"{n.created_at} {n.title}: {n.body}",(620,65+i*26),(255,176,176) if n.level=="error" else (220,220,220))

    def items(self):
        if TABS[self.tab]=="Games": return [f"{g['name']} ({g['status']})" for g in GAMES]+["AI Game Maker"]
        if TABS[self.tab]=="Apps": return [a["name"] for a in APPS]
        c=self.cfg.load(); h=system_health(self.base); u=self.user["username"] if self.user else "Guest"
        return [f"Current User: {u}",f"Language: {c['language']}",f"Region: {c['region']}",f"Theme: {c['theme']}",f"Device Connect ID: {c['device_connect_id']}",f"CPU: {h['cpu_percent']}%",f"Memory: {h['memory_percent']}%",f"Disk Free: {h['disk_free_gb']} GB","ESC returns to Raspberry Pi OS"]

    def act(self,item):
        if TABS[self.tab]=="Games":
            if item=="AI Game Maker" and self.user:
                w=self.games.create_ai_world(self.user["username"],"A bright co-op adventure with floating islands"); self.notes.push("World Saved",w["title"],"success")
            else: self.notes.push("Game Launch",f"Launching {item}")
            return
        if TABS[self.tab]=="Apps":
            app=next(a for a in APPS if a["name"]==item); subprocess.Popen(app["command"],shell=True); self.notes.push("App",f"Launched {item}"); return
        if item.startswith("Theme:"):
            ks=list(THEMES); cur=self.cfg.load()["theme"]; nx=ks[(ks.index(cur)+1)%len(ks)]; self.cfg.update(theme=nx); self.notes.push("Theme",f"Set to {nx}","success")

    def home(self):
        while self.running and self.state=="home":
            for e in pygame.event.get():
                if e.type==pygame.KEYDOWN:
                    if e.key==pygame.K_ESCAPE: self.running=False
                    elif e.key in (pygame.K_RIGHT,): self.tab=(self.tab+1)%len(TABS); self.sel=0
                    elif e.key in (pygame.K_LEFT,): self.tab=(self.tab-1)%len(TABS); self.sel=0
                    elif e.key in (pygame.K_DOWN,): self.sel+=1
                    elif e.key in (pygame.K_UP,): self.sel=max(0,self.sel-1)
                    elif e.key in (pygame.K_RETURN,pygame.K_SPACE):
                        it=self.items(); self.sel=min(self.sel,len(it)-1); self.act(it[self.sel])
            c=self.cfg.load(); bg,accent,hi=THEMES.get(c["theme"],THEMES["ocean"])
            self.screen.fill(bg); self.draw(self.font,"Camcookie Games",(30,20),accent); self.draw(self.tiny,f"Logged in as {(self.user or {'username':'Guest'})['username']}",(35,65),(220,220,220))
            for i,t in enumerate(TABS): self.draw(self.small,t,(40+i*170,100),(255,255,255) if i==self.tab else (130,130,130))
            it=self.items(); self.sel=min(self.sel,max(0,len(it)-1))
            for i,v in enumerate(it): self.draw(self.small,f"• {v}",(75,170+i*34),hi if i==self.sel else (235,235,235))
            self.draw_notes(); pygame.display.flip(); self.clock.tick(60)

    def run(self):
        pygame.init(); pygame.joystick.init(); [pygame.joystick.Joystick(i).init() for i in range(pygame.joystick.get_count())]
        self.screen=pygame.display.set_mode((1280,720),pygame.FULLSCREEN); pygame.display.set_caption("Camcookie Games")
        self.clock=pygame.time.Clock(); self.font=pygame.font.SysFont("Arial",36); self.small=pygame.font.SysFont("Arial",28); self.tiny=pygame.font.SysFont("Arial",20)
        self.start_lan(); self.notes.push("LAN","LAN server at port 8088")
        self.boot();
        if self.running and self.state=="setup": self.setup()
        if self.running and self.state=="login": self.login()
        if self.running and self.state=="home": self.home()
        if self.lan: self.lan.terminate()
        pygame.quit()

if __name__=="__main__":
    Console().run()
PY

  cat > "$TARGET_DIR/camcookie/scripts/run_camcookie.sh" <<'SH2'
#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BASE_DIR/.venv/bin/activate"
cd "$BASE_DIR"
python -m camcookie.ui.shell
SH2
  chmod +x "$TARGET_DIR/camcookie/scripts/run_camcookie.sh"

  cat > "$TARGET_DIR/profiles/accounts.json" <<'JSON'
[
  {"username":"Player1","password":"1234","theme":"ocean","avatar":"default","achievements":[],"rewards":[],"worlds":[]}
]
JSON
  cat > "$TARGET_DIR/profiles/system_config.json" <<'JSON'
{"language":"en-US","region":"US","theme":"ocean","wifi_name":"","device_connect_id":"CAMCOOKIE-PI4B","setup_complete":false,"last_user":"","boot_sound":true,"notifications_enabled":true}
JSON
  echo "[]" > "$TARGET_DIR/profiles/notifications.json"

  cat > "$TARGET_DIR/assets/camcookie-icon.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256"><defs><linearGradient id="g" x1="0" x2="1" y1="0" y2="1"><stop offset="0" stop-color="#0f2746"/><stop offset="1" stop-color="#1e88e5"/></linearGradient></defs><rect width="256" height="256" fill="url(#g)" rx="40"/><circle cx="128" cy="128" r="84" fill="#4ab0ff"/><text x="128" y="146" font-size="68" text-anchor="middle" fill="#ffffff" font-family="sans-serif">CG</text></svg>
SVG

  chown -R "$INSTALL_USER":"$INSTALL_USER" "$TARGET_DIR"
}

create_venv(){
  log "Creating virtual environment"
  run_as_user python3 -m venv "$VENV_DIR"
  run_as_user "$VENV_DIR/bin/pip" install --upgrade pip
  run_as_user "$VENV_DIR/bin/pip" install -r "$TARGET_DIR/requirements.txt"
}

configure_services(){
  log "Creating launcher and LAN service"
  mkdir -p "$(dirname "$DESKTOP_FILE")" "$(dirname "$SERVICE_FILE")"

  cat > "$SERVICE_FILE" <<EOF
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

  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=Camcookie Games
Comment=Launch Camcookie console environment
Exec=$TARGET_DIR/camcookie/scripts/run_camcookie.sh
Icon=$TARGET_DIR/assets/camcookie-icon.svg
Terminal=false
Type=Application
Categories=Game;System;
EOF

  chmod +x "$DESKTOP_FILE"
  chown "$INSTALL_USER":"$INSTALL_USER" "$DESKTOP_FILE" "$SERVICE_FILE"

  run_as_user systemctl --user daemon-reload || true
  run_as_user systemctl --user enable --now camcookie-lan.service || true
  run_as_user update-desktop-database "$HOME_DIR/.local/share/applications" >/dev/null 2>&1 || true
}

verify_install(){
  log "Running validation"
  run_as_user "$VENV_DIR/bin/python" -m py_compile $(cd "$TARGET_DIR" && find camcookie -name '*.py' -type f)
}

finish(){
  cat <<EOF

Camcookie Games installed.
User: $INSTALL_USER
Path: $TARGET_DIR
Launch: $TARGET_DIR/camcookie/scripts/run_camcookie.sh
LAN dashboard: http://<pi-ip>:8088

This installer is self-contained and creates all runtime files itself.
No GitHub password is needed to run this installer.
EOF
}

main(){
  require sudo; require python3
  clean_old
  install_packages
  write_files
  create_venv
  configure_services
  verify_install
  finish
}

main "$@"
