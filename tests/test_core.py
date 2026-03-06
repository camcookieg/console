from pathlib import Path

from camcookie.core.accounts import AccountStore
from camcookie.core.config import ConfigManager


def test_account_create_and_auth(tmp_path: Path):
    store = AccountStore(tmp_path)
    store.create_account("TestUser", "9876", theme="sunset")
    assert store.authenticate("TestUser", "9876") is not None
    assert store.authenticate("TestUser", "bad") is None


def test_config_update(tmp_path: Path):
    cfg = ConfigManager(tmp_path)
    updated = cfg.update(theme="forest", setup_complete=True)
    assert updated["theme"] == "forest"
    assert cfg.load()["setup_complete"] is True
