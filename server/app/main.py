"""共生之缚 后端入口。

启动: uvicorn app.main:app --reload --port 8000
文档: http://127.0.0.1:8000/docs（OpenAPI，随实现自动生成，即接口设计文档素材）
"""
from fastapi import FastAPI

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


@app.get("/")
def root() -> dict:
    return {
        "service": "symbiont-server",
        "docs": "/docs",
        "health": f"{settings.api_prefix}/health",
    }
