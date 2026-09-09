# Godot WebGL 客户端镜像（骨架：托管导出产物，随构建补全导出流程）
# 构建前先用 Godot 导出 WebGL 到本目录下 build/（或 CI 自动导出）
FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY build/ /usr/share/nginx/html/
