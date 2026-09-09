# docker/ — 镜像与部署配置

| 文件 | 说明 |
|---|---|
| `backend.Dockerfile` | FastAPI 后端镜像 |
| `client.Dockerfile` | Godot WebGL 客户端（Nginx 托管导出产物） |
| `admin-web.Dockerfile` | Vue3 管理后台（构建后 Nginx 托管） |
| `nginx.conf` | 客户端静态服务器配置（含 WebGL 所需 COOP/COEP 头） |

编排见根目录 `docker-compose.yml`。
