from __future__ import annotations

import json
from pathlib import Path

from flask import Flask, jsonify, render_template_string, request
from werkzeug.utils import secure_filename

INDEX_HTML = """
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>Camcookie Device Connect</title>
  <style>
    body { font-family: sans-serif; background: #0f1f3a; color: #e9f3ff; margin: 0; padding: 2rem; }
    .card { background: #1b3158; border-radius: 12px; padding: 1rem 1.2rem; margin-bottom: 1rem; }
    input, button { padding: .6rem; border-radius: 8px; border: none; margin-top: .4rem; }
    button { background: #4aa8ff; color: white; cursor: pointer; }
    .row { display: grid; gap: .8rem; }
  </style>
</head>
<body>
  <h1>🎮 Camcookie Device Connect</h1>
  <div class="card">
    <h3>Upload Background</h3>
    <form action="/upload/background" method="post" enctype="multipart/form-data">
      <input type="file" name="file" required>
      <button type="submit">Upload</button>
    </form>
  </div>
  <div class="card">
    <h3>Upload Profile Image</h3>
    <form action="/upload/profile-image" method="post" enctype="multipart/form-data" class="row">
      <input type="text" name="username" placeholder="Username" required>
      <input type="file" name="file" required>
      <button type="submit">Upload</button>
    </form>
  </div>
  <div class="card">
    <h3>Set Device Connect ID</h3>
    <form id="connect-form" class="row">
      <input type="text" id="device_id" placeholder="CAMCOOKIE-XXXX" required>
      <button type="submit">Save</button>
    </form>
    <pre id="result"></pre>
  </div>
  <script>
    document.getElementById('connect-form').addEventListener('submit', async (e) => {
      e.preventDefault();
      const device_connect_id = document.getElementById('device_id').value;
      const res = await fetch('/device-connect', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ device_connect_id })
      });
      document.getElementById('result').textContent = JSON.stringify(await res.json(), null, 2);
    });
  </script>
</body>
</html>
"""


def build_app(base_dir: Path) -> Flask:
    app = Flask(__name__)
    uploads = base_dir / "profiles" / "uploads"
    uploads.mkdir(parents=True, exist_ok=True)
    config_path = base_dir / "profiles" / "system_config.json"

    def load_config() -> dict:
        if config_path.exists():
            return json.loads(config_path.read_text(encoding="utf-8"))
        return {}

    def save_config(config: dict) -> None:
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text(json.dumps(config, indent=2), encoding="utf-8")

    @app.get("/")
    def index():
        return render_template_string(INDEX_HTML)

    @app.get("/health")
    def health():
        return jsonify({"status": "ok", "service": "camcookie-lan"})

    @app.get("/uploads")
    def list_uploads():
        files = sorted(path.name for path in uploads.glob("*"))
        return jsonify({"files": files})

    @app.post("/upload/background")
    def upload_background():
        file = request.files.get("file")
        if not file:
            return jsonify({"error": "file required"}), 400
        filename = secure_filename(file.filename)
        file.save(uploads / f"background_{filename}")
        return jsonify({"message": "background uploaded", "file": f"background_{filename}"})

    @app.post("/upload/profile-image")
    def upload_profile_image():
        file = request.files.get("file")
        username = request.form.get("username", "default")
        if not file:
            return jsonify({"error": "file required"}), 400
        filename = secure_filename(file.filename)
        stored = f"avatar_{secure_filename(username)}_{filename}"
        file.save(uploads / stored)
        return jsonify({"message": "profile image uploaded", "file": stored})

    @app.post("/device-connect")
    def device_connect():
        payload = request.get_json(silent=True) or {}
        connect_id = payload.get("device_connect_id", "")
        config = load_config()
        config["device_connect_id"] = connect_id
        save_config(config)
        return jsonify({"message": "device connect id saved", "device_connect_id": connect_id})

    return app


def main() -> None:
    base_dir = Path(__file__).resolve().parents[2]
    app = build_app(base_dir)
    app.run(host="0.0.0.0", port=8088)


if __name__ == "__main__":
    main()
