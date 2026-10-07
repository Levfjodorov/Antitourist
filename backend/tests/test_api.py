from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_health():
    assert client.get("/health").json()["status"] == "ok"


def test_surprise_route():
    response = client.post(
        "/api/v1/routes/surprise",
        json={
            "lat": 59.437,
            "lon": 24.7536,
            "duration_minutes": 120,
            "mode": "walking",
            "interests": ["weird", "history", "views"],
            "wildness": 70,
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["city"] == "Tallinn"
    assert 3 <= len(data["places"]) <= 7
    assert all(p["legal_access"] for p in data["places"])
