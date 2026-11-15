"""埋点接口：批量写入、批量大小限制、时间戳处理。"""
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db import Base, get_db
from app.main import app
from app.models import GameEvent


@pytest.fixture()
def api():
    """用内存 SQLite 顶替 MySQL：埋点逻辑与库无关，测试不该依赖 docker。"""
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine, autoflush=False, autocommit=False)

    def override() -> Session:
        db = Session()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override
    with TestClient(app) as client:
        yield client, Session
    app.dependency_overrides.clear()


def test_accepts_batch(api):
    client, _ = api
    r = client.post(
        "/api/v1/events",
        json={"events": [
            {"event": "level_start", "data": {"floor": "start"}, "ts": 1700000000},
            {"event": "player_death", "data": {"by": "slime"}},
        ]},
    )
    assert r.status_code == 200
    assert r.json()["accepted"] == 2


def test_rows_are_persisted(api):
    client, Session = api
    client.post(
        "/api/v1/events",
        json={"events": [{"event": "level_start", "data": {"floor": "start"}, "ts": 1700000000}]},
    )
    with Session() as db:
        rows = db.query(GameEvent).all()
    assert len(rows) == 1
    assert rows[0].event == "level_start"
    assert rows[0].payload["floor"] == "start"
    # 客户端时间戳既进 payload 也进 created_at
    assert rows[0].payload["client_ts"] == 1700000000
    assert rows[0].created_at.year == 2023


def test_empty_batch_is_noop(api):
    client, Session = api
    r = client.post("/api/v1/events", json={"events": []})
    assert r.status_code == 200
    assert r.json()["accepted"] == 0
    with Session() as db:
        assert db.query(GameEvent).count() == 0


def test_batch_size_limit(api):
    client, _ = api
    too_many = [{"event": "x"} for _ in range(51)]
    r = client.post("/api/v1/events", json={"events": too_many})
    assert r.status_code == 422
    assert "50" in r.text


def test_batch_size_at_limit_ok(api):
    client, _ = api
    exact = [{"event": "x"} for _ in range(50)]
    r = client.post("/api/v1/events", json={"events": exact})
    assert r.status_code == 200
    assert r.json()["accepted"] == 50


def test_event_name_length_limit(api):
    client, _ = api
    r = client.post("/api/v1/events", json={"events": [{"event": "y" * 65}]})
    assert r.status_code == 422


def test_bad_timestamp_falls_back_to_now(api):
    """时间戳越界不能让整批失败：写库用当前时间，payload 里保留原值。"""
    client, Session = api
    client.post("/api/v1/events", json={"events": [{"event": "x", "ts": 1e30}]})
    with Session() as db:
        row = db.query(GameEvent).one()
    assert row.payload["client_ts"] == 1e30
    assert row.created_at is not None
