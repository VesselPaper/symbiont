"""系统探针路由。"""
import os

from fastapi import APIRouter, Request

router = APIRouter(tags=["system"])


def client_ip(request: Request) -> str:
    """取客户端地址。

    经反向代理之后，后端看到的 peer 是代理自己，真实来源在 X-Forwarded-For /
    X-Real-IP 里。这里优先读头部，取第一个值（最左边是原始客户端）。
    头部本身可以伪造，只有"代理是自己部署的、并且会覆盖这两个头"时才可信；
    deploy/nginx.conf 里的 proxy_set_header 就是在做这个覆盖。
    """
    forwarded = request.headers.get("x-forwarded-for", "")
    if forwarded:
        return forwarded.split(",")[0].strip()

    real_ip = request.headers.get("x-real-ip", "")
    if real_ip:
        return real_ip.strip()

    return request.client.host if request.client else ""


@router.get("/health")
@router.get("/healthz")
def health(request: Request) -> dict:
    """存活探针（docker-compose 健康检查、nginx upstream 摘除、监控统一入口）。

    instance 在负载均衡下用来看清这一次是哪台后端接的；单机运行时为空。
    """
    return {
        "status": "ok",
        "service": "symbiont-server",
        "version": "0.1.0",
        "instance": os.environ.get("SYMBIONT_INSTANCE", ""),
        "client_ip": client_ip(request),
    }
