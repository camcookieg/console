from __future__ import annotations

from camcookie.core.accounts import AccountStore
from camcookie.core.notifications import NotificationCenter
from camcookie.games.ai_maker import generate_world_spec


class GameManager:
    def __init__(self, accounts: AccountStore, notifications: NotificationCenter):
        self.accounts = accounts
        self.notifications = notifications

    def create_ai_world(self, username: str, prompt: str, engine: str | None = None) -> dict:
        world = generate_world_spec(prompt=prompt, engine=engine)
        self.accounts.add_world(username=username, world_spec=world)
        self.accounts.add_achievement(
            username=username,
            achievement="World Architect",
            reward="AI Creator Badge",
        )
        self.notifications.push(
            "AI Game Maker",
            f"World generated for {username} using {world['engine']}",
            "success",
        )
        return world
