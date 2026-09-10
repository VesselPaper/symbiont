# webadmin/ —— 管理看板（stretch）

可选加分项（方案 C）：基于后端 REST API 的轻量管理看板（玩家数 / 事件统计 / 结局分布 / 排行榜）。
**决策**：核心（M0–M4）完成且有余力才做；不阻塞主线。当前为空占位。
若启动：技术选型建议 Vue3 + Vite 或原生 HTML+JS（复用 OpenAPI 生成的客户端），通过 deploy/nginx.conf 的 /api 反代同源访问。
