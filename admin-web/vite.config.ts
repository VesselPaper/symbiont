import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// 骨架配置，随开发补全（代理 / 构建产物路径等）
export default defineConfig({
  plugins: [vue()],
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://localhost:8000',
        changeOrigin: true,
      },
    },
  },
})
