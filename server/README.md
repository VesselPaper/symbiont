# 后端 server/（FastAPI）

远程存档 / 统计埋点 REST API。账号与排行榜只有设计和表结构，没有实现（方案 B 范围；如改为方案 A 可整体移除本目录）。

## 本地运行

```powershell
python -m venv server/.venv
server\.venv\Scripts\pip install -r server\requirements.txt
server\.venv\Scripts\python -m uvicorn app.main:app --reload --port 8000 --app-dir server
# 或: scripts/run_server.ps1
```

接口文档（OpenAPI）：http://127.0.0.1:8000/docs

## 测试

```powershell
server\.venv\Scripts\python -m pytest server -v
```

## 结构

```
server/
├── app/
│   ├── main.py        入口（挂载路由、OpenAPI 元信息）
│   ├── config.py      配置（SYMBIONT_ 环境变量覆盖）
│   ├── db.py          引擎/会话/依赖
│   ├── models.py      SQLAlchemy 模型（对齐 database/schema.sql）
│   └── routers/       路由：health、saves、events 三个；auth 与 leaderboard 未实现
├── tests/             pytest
├── requirements.txt
└── pytest.ini
```

## 里程碑

- **M0（本阶段）**：骨架 + /health + OpenAPI + 冒烟测试。
- **M2**：saves（远程存档 GET/PUT）、events（批量埋点）、MySQL 联调、docker-compose 全栈已做；auth（注册/登录/token）与 leaderboard 只有设计，没做。
- WebSocket：**明确不做**，理由见 `doc/03-系统详细设计.md`（单机无实时需求）。
