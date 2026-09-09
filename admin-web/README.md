# Symbiont 管理后台（Vue3）

面向管理员（教师 / 组员）的 Web 管理端：关卡配置、玩家管理、公告管理、数据统计看板。

## 技术栈

Vue3 · Vite · TypeScript · Element Plus · ECharts · Pinia · Axios · Vue Router

## 目录结构（规划）

```
admin-web/
├── src/
│   ├── main.ts            # 入口
│   ├── App.vue
│   ├── router/            # 路由（登录鉴权守卫）
│   ├── stores/            # Pinia（用户 / 看板）
│   ├── api/               # Axios 封装 + 接口
│   └── views/
│       ├── login/         # 登录
│       ├── dashboard/     # 数据看板（ECharts）
│       ├── levels/        # 关卡配置管理
│       ├── players/       # 玩家管理
│       ├── announcements/ # 公告管理
│       └── stats/         # 数据统计
├── package.json
└── vite.config.ts
```

## 本地运行（随开发补全）

```bash
npm install
npm run dev
```

详见 `../doc/03-系统详细设计.md`。
