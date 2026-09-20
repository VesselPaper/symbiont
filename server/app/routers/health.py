"""系统探针路由。"""
from fastapi import APIRouter

router = APIRouter(tags=["system"])


@router.get("/health")
@router.get("/healthz")
def health() -> dict:
    """存活探针（docker-compose / k8s / nginx 入口统一命名）。"""
    return {"status": "ok", "service": "symbiont-server", "version": "0.1.0"}
