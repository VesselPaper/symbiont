"""M0 冒烟测试：健康检查 + OpenAPI 存在性。"""
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    r = client.get("/api/v1/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert body["service"] == "symbiont-server"


def test_root_meta():
    r = client.get("/")
    assert r.status_code == 200
    assert r.json()["docs"] == "/docs"


def test_openapi_registers_routes():
    r = client.get("/openapi.json")
    assert r.status_code == 200
    paths = r.json()["paths"]
    assert "/api/v1/health" in paths


def test_health_reports_instance(monkeypatch):
    """多副本部署时探针要能报出"我是谁"，否则看不出请求落到了哪台。"""
    monkeypatch.setenv("SYMBIONT_INSTANCE", "node-2")
    r = client.get("/api/v1/health")
    assert r.json()["instance"] == "node-2"


def test_health_instance_empty_when_unset(monkeypatch):
    """单机运行时没有实例号，不能凭空编一个。"""
    monkeypatch.delenv("SYMBIONT_INSTANCE", raising=False)
    r = client.get("/api/v1/health")
    assert r.json()["instance"] == ""


def test_health_prefers_forwarded_for():
    """经代理后取 X-Forwarded-For 最左边那个，也就是原始客户端。"""
    r = client.get("/api/v1/health", headers={"X-Forwarded-For": "203.0.113.7, 10.0.0.2"})
    assert r.json()["client_ip"] == "203.0.113.7"


def test_health_falls_back_to_real_ip():
    """只有 X-Real-IP 时也能取到。"""
    r = client.get("/api/v1/health", headers={"X-Real-IP": "203.0.113.9"})
    assert r.json()["client_ip"] == "203.0.113.9"


def test_health_empty_forwarded_header_falls_back():
    """转发头为空时回退到连接对端地址，不能返回空字符串。"""
    r = client.get("/api/v1/health", headers={"X-Forwarded-For": ""})
    assert r.json()["client_ip"] == "testclient"


def test_root_healthz_matches_api_health():
    """根路径 /healthz 和 /api/v1/health 必须返回同一份字段。

    这两个路径以前是各写各的，根路径少了 instance / client_ip，
    容器 healthcheck 和接口文档就对不上了。
    """
    root = client.get("/healthz").json()
    api = client.get("/api/v1/health").json()
    assert root == api
