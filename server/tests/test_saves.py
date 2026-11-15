"""远程存档接口：设备归属、覆盖写、槽位与设备号校验。"""
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db import Base, get_db
from app.main import app
from app.models import SaveData, User

DEVICE = "abcdef0123456789"
OTHER = "fedcba9876543210"


@pytest.fixture()
def api():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine, autoflush=False, autocommit=False)

    def override():
        db = Session()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override
    with TestClient(app) as client:
        yield client, Session
    app.dependency_overrides.clear()


def test_missing_device_id_is_rejected(api):
    client, _ = api
    assert client.get("/api/v1/saves/0").status_code == 400
    assert client.put("/api/v1/saves/0", json={"save_data": {}}).status_code == 400


def test_short_device_id_is_rejected(api):
    client, _ = api
    r = client.get("/api/v1/saves/0", headers={"X-Device-Id": "short"})
    assert r.status_code == 400


def test_slot_out_of_range(api):
    client, _ = api
    r = client.put("/api/v1/saves/9", json={"save_data": {}}, headers={"X-Device-Id": DEVICE})
    assert r.status_code == 422


def test_get_without_save_returns_404(api):
    client, _ = api
    r = client.get("/api/v1/saves/1", headers={"X-Device-Id": DEVICE})
    assert r.status_code == 404


def test_put_then_get_roundtrip(api):
    client, _ = api
    body = {"save_data": {"version": 1, "game_progress": {"current_floor": "start"}}}
    put = client.put("/api/v1/saves/1", json=body, headers={"X-Device-Id": DEVICE})
    assert put.status_code == 200

    got = client.get("/api/v1/saves/1", headers={"X-Device-Id": DEVICE})
    assert got.status_code == 200
    assert got.json()["save_data"]["game_progress"]["current_floor"] == "start"


def test_put_overwrites_same_slot(api):
    client, Session = api
    client.put("/api/v1/saves/1", json={"save_data": {"hp": 4}}, headers={"X-Device-Id": DEVICE})
    client.put("/api/v1/saves/1", json={"save_data": {"hp": 2}}, headers={"X-Device-Id": DEVICE})
    with Session() as db:
        rows = db.query(SaveData).all()
    assert len(rows) == 1, "同一设备同一槽位应该覆盖，而不是堆版本"
    assert rows[0].save_data["hp"] == 2


def test_devices_are_isolated(api):
    client, _ = api
    client.put("/api/v1/saves/0", json={"save_data": {"owner": "A"}}, headers={"X-Device-Id": DEVICE})
    r = client.get("/api/v1/saves/0", headers={"X-Device-Id": OTHER})
    assert r.status_code == 404


def test_first_put_creates_anonymous_user(api):
    client, Session = api
    client.put("/api/v1/saves/0", json={"save_data": {}}, headers={"X-Device-Id": DEVICE})
    with Session() as db:
        user = db.query(User).filter(User.username == "device:" + DEVICE).one()
    assert user.password_hash == "!", "匿名设备账号不该有可登录的密码"
