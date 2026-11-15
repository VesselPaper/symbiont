# 共生之缚 后端镜像
#
# 构建上下文就是这个目录（server/），不是整个仓库：
# 把 client/、.git、doc/ 传给 daemon 只会拖慢构建，还可能把开发垃圾带进镜像。
#
# 两段构建：builder 装依赖到 /opt/venv，runtime 只带 venv 与 app；运行身份是非 root。
# 健康检查写在镜像里，compose 不必重复。

FROM python:3.12-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# 依赖源。默认走国内镜像：直连 pypi.org 装全套依赖实测要 4 分钟以上，镜像约 30 秒。
# 换网络环境（CI、海外机器）时用 --build-arg PIP_INDEX_URL=https://pypi.org/simple/ 覆盖。
ARG PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/
ENV PIP_INDEX_URL=${PIP_INDEX_URL}

WORKDIR /build
COPY requirements.txt ./
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install -r requirements.txt


FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

WORKDIR /srv/app
COPY --from=builder /opt/venv /opt/venv
COPY app ./app

RUN useradd --uid 10001 --create-home --shell /usr/sbin/nologin app \
 && chown -R app:app /srv
USER app

EXPOSE 8000

# 探针用 python 标准库：slim 镜像里没有 curl / wget
HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=5 \
    CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2).status == 200 else 1)"]

# --no-server-header：连 uvicorn 的指纹也不报
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-server-header"]
