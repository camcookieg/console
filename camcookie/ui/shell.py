from __future__ import annotations

import socket
import subprocess
import sys
import time
from pathlib import Path

import pygame

from camcookie.apps.registry import APPS
from camcookie.core.accounts import AccountStore
from camcookie.core.config import ConfigManager
from camcookie.core.health import system_health
from camcookie.core.notifications import NotificationCenter
from camcookie.games.manager import GameManager
from camcookie.games.registry import GAMES

SCREEN_SIZE = (1280, 720)
FPS = 60
TABS = ["Games", "Apps", "Settings"]
THEMES = {
    "ocean": ((16, 25, 48), (90, 210, 255), (255, 206, 84)),
    "sunset": ((46, 22, 37), (255, 136, 79), (255, 215, 128)),
    "forest": ((14, 38, 27), (109, 210, 164), (242, 255, 191)),
}


class CamcookieConsole:
    def __init__(self) -> None:
        self.base_dir = Path(__file__).resolve().parents[2]
        self.cfg = ConfigManager(self.base_dir)
        self.accounts = AccountStore(self.base_dir / "profiles")
        self.notifications = NotificationCenter(self.base_dir / "profiles" / "notifications.json")
        self.game_manager = GameManager(self.accounts, self.notifications)
        self.accounts.ensure_default_admin()

        self.current_user: dict | None = None
        self.tab_index = 0
        self.selected_index = 0
        self.state = "boot"
        self.running = True
        self.lan_process: subprocess.Popen[str] | None = None
        self.clock: pygame.time.Clock | None = None
        self.screen: pygame.Surface | None = None
        self.font: pygame.font.Font | None = None
        self.small: pygame.font.Font | None = None
        self.tiny: pygame.font.Font | None = None
        self.login_password = ""

    def launch_lan_server(self) -> None:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            if sock.connect_ex(("127.0.0.1", 8088)) == 0:
                self.notifications.push("LAN", "Using existing LAN service on port 8088", "info")
                return

        self.lan_process = subprocess.Popen(
            [sys.executable, "-m", "camcookie.lan.server"],
            cwd=str(self.base_dir),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
        )

    def setup_if_needed(self) -> None:
        config = self.cfg.load()
        if config.get("setup_complete"):
            return
        if not config.get("device_connect_id"):
            config["device_connect_id"] = "CAMCOOKIE-PI4B"
        config["setup_complete"] = True
        self.cfg.save(config)
        self.notifications.push("Setup Wizard", "Initial setup was completed.", "success")

    def run_app_command(self, app_item: dict) -> None:
        self.notifications.push("Launching App", app_item["name"])
        try:
            subprocess.Popen(app_item["command"], shell=True)
        except OSError as exc:
            self.notifications.push("App launch failed", str(exc), "error")

    def draw_text(self, font: pygame.font.Font, text: str, pos: tuple[int, int], color=(255, 255, 255)) -> None:
        assert self.screen is not None
        self.screen.blit(font.render(text, True, color), pos)

    def handle_controller_as_keys(self, event: pygame.event.Event) -> list[int]:
        if event.type != pygame.JOYBUTTONDOWN:
            return []
        mapping = {
            0: [pygame.K_RETURN],
            1: [pygame.K_ESCAPE],
            11: [pygame.K_UP],
            12: [pygame.K_DOWN],
            13: [pygame.K_LEFT],
            14: [pygame.K_RIGHT],
        }
        return mapping.get(event.button, [])

    def run_boot_animation(self) -> None:
        assert self.clock and self.screen and self.font
        start = time.time()
        while time.time() - start < 2.2 and self.running:
            for event in pygame.event.get():
                if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                    self.running = False
            progress = min(1.0, (time.time() - start) / 2.2)
            self.screen.fill((8, 14, 30))
            self.draw_text(self.font, "Camcookie Games", (430, 290), (90, 210, 255))
            pygame.draw.rect(self.screen, (40, 52, 75), pygame.Rect(320, 360, 640, 24), border_radius=10)
            pygame.draw.rect(self.screen, (90, 210, 255), pygame.Rect(320, 360, int(640 * progress), 24), border_radius=10)
            self.draw_text(self.small, "Booting console environment...", (470, 395), (210, 220, 245))
            pygame.display.flip()
            self.clock.tick(FPS)
        self.state = "setup" if not self.cfg.load()["setup_complete"] else "login"

    def run_setup_wizard(self) -> None:
        assert self.clock and self.screen and self.small
        steps = [
            "Language: English (US)",
            "Region: US",
            "Wi-Fi: configured in Raspberry Pi OS",
            "Account: Player1",
            "Password: ****",
            "Controller pairing: auto detect",
            "Device Connect ID: CAMCOOKIE-PI4B",
            "Theme: ocean",
            "Final confirmation",
        ]
        index = 0
        while self.running and self.state == "setup":
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    self.running = False
                if event.type == pygame.KEYDOWN:
                    if event.key == pygame.K_ESCAPE:
                        self.running = False
                    elif event.key in (pygame.K_RETURN, pygame.K_RIGHT, pygame.K_SPACE):
                        index += 1
                        if index >= len(steps):
                            self.setup_if_needed()
                            self.state = "login"
                    elif event.key == pygame.K_LEFT:
                        index = max(0, index - 1)

            self.screen.fill((14, 31, 52))
            self.draw_text(self.small, "First Boot Setup Wizard", (40, 40), (90, 210, 255))
            self.draw_text(self.small, "Press Enter/Right to continue", (40, 80), (220, 220, 220))
            if index < len(steps):
                pygame.draw.rect(self.screen, (26, 52, 84), pygame.Rect(70, 170, 1140, 350), border_radius=20)
                self.draw_text(self.small, steps[index], (100, 250), (255, 255, 255))
                self.draw_text(self.small, f"Step {index+1}/{len(steps)}", (100, 300), (255, 206, 84))

            pygame.display.flip()
            self.clock.tick(FPS)

    def run_login_screen(self) -> None:
        assert self.clock and self.screen and self.small
        accounts = self.accounts.load()
        index = 0
        self.login_password = ""

        while self.running and self.state == "login":
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    self.running = False
                if event.type == pygame.JOYBUTTONDOWN:
                    for key in self.handle_controller_as_keys(event):
                        pygame.event.post(pygame.event.Event(pygame.KEYDOWN, key=key))
                if event.type == pygame.KEYDOWN:
                    if event.key == pygame.K_ESCAPE:
                        self.running = False
                    elif event.key in (pygame.K_DOWN, pygame.K_s):
                        index = min(len(accounts) - 1, index + 1)
                    elif event.key in (pygame.K_UP, pygame.K_w):
                        index = max(0, index - 1)
                    elif event.key == pygame.K_BACKSPACE:
                        self.login_password = self.login_password[:-1]
                    elif event.key == pygame.K_RETURN:
                        candidate = accounts[index]
                        auth = self.accounts.authenticate(candidate["username"], self.login_password or "1234")
                        if auth:
                            self.current_user = auth
                            self.cfg.update(last_user=auth["username"])
                            self.notifications.push("Login", f"Welcome back, {auth['username']}", "success")
                            self.state = "home"
                        else:
                            self.notifications.push("Login", "Invalid password", "error")
                            self.login_password = ""
                    elif event.unicode.isdigit() and len(self.login_password) < 12:
                        self.login_password += event.unicode

            self.screen.fill((11, 20, 38))
            self.draw_text(self.small, "Account Select", (40, 40), (90, 210, 255))
            self.draw_text(self.small, "Enter password digits and press Enter", (40, 80), (230, 230, 230))
            self.draw_text(self.small, f"Password: {'*' * len(self.login_password)}", (40, 120), (255, 206, 84))

            for i, account in enumerate(accounts):
                y = 190 + i * 60
                color = (255, 206, 84) if i == index else (220, 220, 220)
                self.draw_text(self.small, f"{account['username']}  • theme: {account['theme']}", (80, y), color)

            self.draw_notifications()
            pygame.display.flip()
            self.clock.tick(FPS)

    def draw_notifications(self) -> None:
        assert self.small
        self.draw_text(self.small, "Notifications", (870, 30), (90, 210, 255))
        for idx, note in enumerate(self.notifications.latest(5)):
            color = (255, 176, 176) if note.level == "error" else (220, 220, 220)
            self.draw_text(self.tiny, f"{note.created_at} • {note.title}: {note.body}", (650, 65 + idx * 28), color)

    def home_items(self) -> list[str]:
        if TABS[self.tab_index] == "Games":
            return [f"{game['name']} ({game['status']})" for game in GAMES] + ["AI Game Maker"]
        if TABS[self.tab_index] == "Apps":
            return [app["name"] for app in APPS]

        config = self.cfg.load()
        health = system_health(self.base_dir)
        current = self.current_user["username"] if self.current_user else "N/A"
        return [
            f"Current User: {current}",
            f"Language: {config['language']}",
            f"Region: {config['region']}",
            f"Theme: {config['theme']}",
            f"Device Connect ID: {config['device_connect_id']}",
            f"CPU: {health['cpu_percent']}%",
            f"Memory: {health['memory_percent']}%",
            f"Disk Free: {health['disk_free_gb']} GB",
            "ESC returns to Raspberry Pi OS",
        ]

    def execute_home_action(self, item_label: str) -> None:
        if TABS[self.tab_index] == "Games":
            if item_label == "AI Game Maker" and self.current_user:
                world = self.game_manager.create_ai_world(
                    username=self.current_user["username"],
                    prompt="A bright co-op adventure world with floating islands",
                )
                self.notifications.push("World Saved", world["title"], "success")
            else:
                self.notifications.push("Game Launch", f"Launching {item_label}", "info")
            return

        if TABS[self.tab_index] == "Apps":
            app_index = [app["name"] for app in APPS].index(item_label)
            self.run_app_command(APPS[app_index])
            return

        if item_label.startswith("Theme:"):
            current_theme = self.cfg.load()["theme"]
            theme_keys = list(THEMES)
            next_theme = theme_keys[(theme_keys.index(current_theme) + 1) % len(theme_keys)]
            self.cfg.update(theme=next_theme)
            if self.current_user:
                self.notifications.push("Theme Updated", f"Theme set to {next_theme}", "success")

    def run_home(self) -> None:
        assert self.clock and self.screen and self.small and self.font
        while self.running and self.state == "home":
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    self.running = False
                if event.type == pygame.JOYBUTTONDOWN:
                    for key in self.handle_controller_as_keys(event):
                        pygame.event.post(pygame.event.Event(pygame.KEYDOWN, key=key))
                if event.type == pygame.KEYDOWN:
                    if event.key == pygame.K_ESCAPE:
                        self.running = False
                    elif event.key in (pygame.K_RIGHT, pygame.K_d):
                        self.tab_index = (self.tab_index + 1) % len(TABS)
                        self.selected_index = 0
                    elif event.key in (pygame.K_LEFT, pygame.K_a):
                        self.tab_index = (self.tab_index - 1) % len(TABS)
                        self.selected_index = 0
                    elif event.key in (pygame.K_DOWN, pygame.K_s):
                        self.selected_index += 1
                    elif event.key in (pygame.K_UP, pygame.K_w):
                        self.selected_index = max(0, self.selected_index - 1)
                    elif event.key in (pygame.K_RETURN, pygame.K_SPACE):
                        items = self.home_items()
                        if items:
                            self.execute_home_action(items[self.selected_index])

            config = self.cfg.load()
            bg, accent, highlight = THEMES.get(config["theme"], THEMES["ocean"])
            self.screen.fill(bg)
            self.draw_text(self.font, "Camcookie Games", (30, 22), accent)
            user = self.current_user["username"] if self.current_user else "Guest"
            self.draw_text(self.tiny, f"Logged in as {user}", (34, 68), (220, 220, 220))

            for idx, tab in enumerate(TABS):
                color = (255, 255, 255) if idx == self.tab_index else (130, 130, 130)
                self.draw_text(self.small, tab, (40 + idx * 170, 106), color)

            items = self.home_items()
            if items:
                self.selected_index = min(self.selected_index, len(items) - 1)
            for idx, item in enumerate(items):
                color = highlight if idx == self.selected_index else (235, 235, 235)
                self.draw_text(self.small, f"• {item}", (75, 180 + idx * 36), color)

            self.draw_notifications()
            pygame.display.flip()
            self.clock.tick(FPS)

    def run(self) -> None:
        pygame.init()
        pygame.joystick.init()
        for idx in range(pygame.joystick.get_count()):
            pygame.joystick.Joystick(idx).init()

        self.screen = pygame.display.set_mode(SCREEN_SIZE, pygame.FULLSCREEN)
        pygame.display.set_caption("Camcookie Games")
        self.clock = pygame.time.Clock()
        self.font = pygame.font.SysFont("Arial", 36)
        self.small = pygame.font.SysFont("Arial", 28)
        self.tiny = pygame.font.SysFont("Arial", 20)

        self.launch_lan_server()
        if self.lan_process:
            self.notifications.push("LAN", "LAN server online at port 8088", "info")

        self.run_boot_animation()
        if self.running and self.state == "setup":
            self.run_setup_wizard()
        if self.running and self.state == "login":
            self.run_login_screen()
        if self.running and self.state == "home":
            self.run_home()

        if self.lan_process:
            self.lan_process.terminate()
        pygame.quit()


def main() -> None:
    CamcookieConsole().run()


if __name__ == "__main__":
    main()
