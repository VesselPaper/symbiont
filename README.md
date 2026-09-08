# CodeCompass 🧭

> AI 开源项目导学平台（代码仓库智能导读系统）

导入任意开源项目 / 课程代码仓库，AI 自动解析并生成**项目地图 + 源码导读 + 学习路线 + 上手任务**，让"读别人的代码"从无从下手变成有路径可循。

本项目为《软件工程》课程设计自主选题，AI 原生设计：大模型 + 检索增强（RAG）是系统的核心体验，所有问答均引用仓库内具体文件与代码位置，可溯源、可验证。

## ✨ 核心特性

- **项目接入**：支持 Git 仓库拉取 / 本地 zip 上传 / 内置示例仓库三种方式，自动解析目录结构、识别技术栈
- **AI 项目解读**：一句话定位、功能清单、架构概览；逐模块职责与依赖讲解；核心文件逐文件导读
- **学习路线生成**：按基础到进阶生成阅读顺序、知识前置清单、按周学习计划，可视化路线图
- **RAG 智能问答**：针对仓库提问，AI 结合代码内容回答，并定位到具体文件与代码行
- **学习管理**：项目收藏、学习打卡、笔记关联、进度追踪
- **实战任务**（进阶）：AI 基于项目生成改造任务，提交代码后 AI 点评
- **教师 / 后台**：课程与导学任务布置、班级学习数据、示例项目库、AI 参数配置

## 🛠 技术栈

| 层 | 技术 |
|---|---|
| 前端 | Vue3 + Element Plus + Monaco 代码展示 + ECharts |
| 后端 | Python FastAPI + Git 集成 + 异步任务 |
| AI | 大模型 API（DeepSeek 等）+ 检索增强 RAG（Embedding + Chroma） |
| 存储 | MySQL（业务数据）+ Redis（缓存 / 队列）+ Chroma（向量库） |
| 部署 | Docker Compose 一键部署 |

## 🚀 快速开始（开发中，随项目推进完善）

```bash
# 1. 克隆仓库
git clone https://github.com/<your-org>/codecompass.git && cd codecompass

# 2. 配置环境变量（.env）
#    DEEPSEEK_API_KEY=sk-xxx
#    MYSQL_HOST=localhost ...

# 3. 启动（Docker Compose 一键部署）
docker compose up -d

# 4. 访问
#    前端: http://localhost:8080
#    后端: http://localhost:8000/docs
```

## 📁 目录结构（规划）

```
codecompass/
├── backend/          # FastAPI 后端
│   ├── app/
│   │   ├── api/      # 接口路由
│   │   ├── core/     # 配置、安全
│   │   ├── models/   # ORM 模型
│   │   ├── services/ # 业务服务（解析 / RAG / AI 解读）
│   │   └── tasks/    # 异步任务
│   └── tests/        # 测试
├── frontend/         # Vue3 前端
│   └── src/
├── docker/           # Dockerfile / compose
├── docs/             # 课程交付文档
└── scripts/          # 数据库脚本等
```

## 📅 项目进度

- [x] 选题与项目计划
- [ ] 需求分析（进行中）
- [ ] 系统设计（接口 / 详细设计 / 数据库）
- [ ] 后端开发（解析 / RAG / AI 解读 / 学习管理）
- [ ] 前端开发与联调
- [ ] 测试 / 部署 / 文档交付

## 📄 License

[MIT](LICENSE)
