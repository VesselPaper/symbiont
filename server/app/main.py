"""共生之缚 后端入口。

启动: uvicorn app.main:app --reload --port 8000
文档: http://127.0.0.1:8000/docs（OpenAPI，随实现自动生成，即接口设计文档素材）
"""
from fastapi import FastAPI, Request

from .config import settings
from .routers import health

app = FastAPI(
    title=settings.app_name,
    version="0.1.0",
    description=(
        "账号 / 远程存档 / 统计埋点 / 排行榜 REST API。\n"
        "完整接口定义以 /openapi.json 为准，将整理进 docs/02-系统接口设计文档.md。"
    ),
)

app.include_router(health.router, prefix=settings.api_prefix)


@app.get("/healthz", include_in_schema=False)
def healthz(request: Request) -> dict:
    """基础设施探针路径（不带 /api/v1 前缀，给 compose healthcheck 和 k8s 用）。

    必须复用 routers/health.py 那一份实现：两处各写一个，字段早晚会漂，
    之前就是这样——根路径少了 instance 和 client_ip。
    """
    return health.health(request)


@app.get("/")
def root() -> dict:
    return {
        "service": "symbiont-server",
        "docs": "/docs",
        "health": f"{settings.api_prefix}/health",
        "healthz": "/healthz",
    }
