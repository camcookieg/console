from __future__ import annotations

import json
from pathlib import Path

from flask import Flask, jsonify, request
from werkzeug.utils import secure_filename


def build_app(base_dir: Path) -> Flask:
    app = Flask(__name__)
    uploads = base_dir / "profiles" / "uploads"
    uploads.mkdir(parents=True, exist_ok=True)

    @app.get("/health")
    def health():
        return jsonify({"status": "ok", "service": "camcookie-lan"})

    @app.post("/upload/background")
    def upload_background():
        file = request.files.get("file")
        if not file:
            return jsonify({"error": "file required"}), 400
        filename = secure_filename(file.filename)
        file.save(uploads / f"background_{filename}")
        return jsonify({"message": "background uploaded"})

    @app.post("/upload/profile-image")
    def upload_profile_image():
        file = request.files.get("file")
        username = request.form.get("username", "default")
        if not file:
            return jsonify({"error": "file required"}), 400
        filename = secure_filename(file.filename)
        file.save(uploads / f"avatar_{username}_{filename}")
        return jsonify({"message": "profile image uploaded"})

    @app.post("/device-connect")
    def device_connect():
        payload = request.get_json(silent=True) or {}
        connect_id = payload.get("device_connect_id", "")
        config_path = base_dir / "profiles" / "system_config.json"
        if config_path.exists():
            config = json.loads(config_path.read_text(encoding="utf-8"))
        else:
            config = {}
        config["device_connect_id"] = connect_id
        config_path.write_text(json.dumps(config, indent=2), encoding="utf-8")
        return jsonify({"message": "device connect id saved", "device_connect_id": connect_id})

    return app


def main() -> None:
    base_dir = Path(__file__).resolve().parents[2]
    app = build_app(base_dir)
    app.run(host="0.0.0.0", port=8088)


if __name__ == "__main__":
    main()
