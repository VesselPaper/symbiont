# Symbiont 后端（FastAPI）

账号 / 云存档 / 排行榜 / 数据统计 / 管理后台 / AI（可选）服务。

## 技术栈

Python 3.13 · FastAPI · SQLAlchemy 2 · Alembic · Pydantic v2 · MySQL 8 · Redis

## 目录结构（规划）

```
backend/
├── app/
│   ├── main.py            # 应用入口（CORS / 路由注册 / 启动钩子）
│   ├── core/              # 配置、安全（JWT）、RBAC 依赖
│   ├── models/            # SQLAlchemy ORM 模型
│   ├── schemas/           # Pydantic 请求/响应模型
│   ├── api/               # 路由：auth / saves / leaderboard / stats / admin / ai
│   ├── services/          # 业务逻辑层
│   └── ai/                # AI 关卡生成、卡关提示（可选）
├── alembic/               # 数据库迁移
├── tests/                 # 单元/接口测试
└── requirements.txt
```

## 本地运行（随开发补全）

```bash
python -m venv .venv && .venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

详见 `../doc/03-系统详细设计.md`。
