from pathlib import Path

from camcookie.lan.server import build_app


def test_health_endpoint(tmp_path: Path):
    app = build_app(tmp_path)
    client = app.test_client()
    response = client.get('/health')
    assert response.status_code == 200
    assert response.get_json()['status'] == 'ok'
