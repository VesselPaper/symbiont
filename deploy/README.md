# 部署 deploy/（docker）

对应课程交付 **4. 系统安装部署文档（包括 docker 镜像文件）**。

## 一键全栈

```powershell
# 前置：Docker Desktop
docker compose -f deploy/docker-compose.yml up -d
```

| 服务 | 地址 | 说明 |
|---|---|---|
| game-web | http://localhost:8080 | 游戏 Web 版（Godot HTML5 导出，nginx 托管） |
| server | http://localhost:8000/docs | FastAPI 后端 + OpenAPI 文档 |
| mysql | 127.0.0.1:3306 | MySQL 8，首次启动自动执行 schema.sql + seed.sql |

## 镜像说明

- `Dockerfile.server`：后端镜像（python:3.12-slim + uvicorn）。
- `Dockerfile.game-web`：游戏 Web 版镜像（nginx:alpine + `client/build/web`）。

⚠️ `game-web` 依赖 Godot Web 导出产物 `client/build/web/`，M2 起先运行
`scripts/export_web.ps1`（需安装 Godot 导出模板），M0 阶段该镜像暂不构建。

## 目录

- `docker-compose.yml`：编排（mysql8 + server + game-web；Redis 可选项在 `03-系统详细设计.md` 说明）
- `nginx.conf`：Web 托管 + /api 反代
- `Dockerfile.*`：镜像构建文件
