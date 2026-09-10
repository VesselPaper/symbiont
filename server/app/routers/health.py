"""系统探针路由。"""
from fastapi import APIRouter

router = APIRouter(tags=["system"])


@router.get("/health")
def health() -> dict:
    """存活探针（docker-compose healthcheck 使用）。"""
    return {"status": "ok", "service": "symbiont-server", "version": "0.1.0"}
