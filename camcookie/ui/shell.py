from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pygame

from camcookie.apps.registry import APPS
from camcookie.core.accounts import AccountStore
from camcookie.core.config import ConfigManager
from camcookie.core.notifications import NotificationCenter
from camcookie.games.registry import GAMES

TABS = ["Games", "Apps", "Settings"]


def run_setup_if_needed(base_dir: Path, cfg: ConfigManager, notes: NotificationCenter) -> None:
    config = cfg.load()
    if config.get("setup_complete"):
        return
    config["setup_complete"] = True
    if not config.get("device_connect_id"):
        config["device_connect_id"] = "CAMCOOKIE-PI4B"
    cfg.save(config)
    notes.push("Setup complete", "First boot wizard defaults were applied.")


def launch_lan_server(base_dir: Path) -> subprocess.Popen[str]:
    return subprocess.Popen(
        [sys.executable, "-m", "camcookie.lan.server"],
        cwd=str(base_dir),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        text=True,
    )


def draw_text(screen, font, text, pos, color=(255, 255, 255)):
    screen.blit(font.render(text, True, color), pos)


def main() -> None:
    base_dir = Path(__file__).resolve().parents[2]
    cfg = ConfigManager(base_dir)
    accounts = AccountStore(base_dir / "profiles")
    notes = NotificationCenter()
    accounts.ensure_default_admin()
    run_setup_if_needed(base_dir, cfg, notes)
    notes.push("LAN", "LAN server available on port 8088")

    lan_process = launch_lan_server(base_dir)

    pygame.init()
    pygame.joystick.init()
    screen = pygame.display.set_mode((1280, 720), pygame.FULLSCREEN)
    pygame.display.set_caption("Camcookie Games")
    clock = pygame.time.Clock()
    font = pygame.font.SysFont("Arial", 30)
    small = pygame.font.SysFont("Arial", 24)

    tab_index = 0
    selected = 0

    running = True
    while running:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            if event.type == pygame.KEYDOWN:
                if event.key == pygame.K_ESCAPE:
                    running = False
                elif event.key in (pygame.K_RIGHT, pygame.K_d):
                    tab_index = (tab_index + 1) % len(TABS)
                    selected = 0
                elif event.key in (pygame.K_LEFT, pygame.K_a):
                    tab_index = (tab_index - 1) % len(TABS)
                    selected = 0
                elif event.key in (pygame.K_DOWN, pygame.K_s):
                    selected += 1
                elif event.key in (pygame.K_UP, pygame.K_w):
                    selected = max(0, selected - 1)

        screen.fill((16, 25, 48))
        draw_text(screen, font, "Camcookie Games", (40, 30), (90, 210, 255))

        for idx, tab in enumerate(TABS):
            color = (255, 255, 255) if idx == tab_index else (130, 130, 130)
            draw_text(screen, small, tab, (40 + idx * 170, 100), color)

        panel_items = []
        if TABS[tab_index] == "Games":
            panel_items = [f"{game['name']} ({game['status']})" for game in GAMES]
        elif TABS[tab_index] == "Apps":
            panel_items = [app["name"] for app in APPS]
        else:
            config = cfg.load()
            panel_items = [
                f"Language: {config['language']}",
                f"Region: {config['region']}",
                f"Theme: {config['theme']}",
                f"Device Connect ID: {config['device_connect_id']}",
                "Press ESC to exit to Raspberry Pi OS",
            ]

        if panel_items:
            selected = min(selected, len(panel_items) - 1)

        for idx, item in enumerate(panel_items):
            color = (255, 206, 84) if idx == selected else (235, 235, 235)
            draw_text(screen, small, f"• {item}", (80, 180 + idx * 38), color)

        draw_text(screen, small, "Notifications", (880, 40), (90, 210, 255))
        for idx, note in enumerate(notes.latest()):
            draw_text(screen, small, f"{note.title}: {note.body}", (740, 80 + idx * 36), (230, 230, 230))

        pygame.display.flip()
        clock.tick(60)

    lan_process.terminate()
    pygame.quit()


if __name__ == "__main__":
    main()
