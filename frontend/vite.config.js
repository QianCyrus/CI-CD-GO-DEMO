import { defineConfig } from "vite";

// 本地开发时把 /api 与 /healthz 代理到 Go 后端（:8080）
export default defineConfig({
  // 适配 GitHub Pages（仓库子路径部署）；用相对 base 避免资源 404
  base: "./",
  server: {
    proxy: {
      "/api": "http://localhost:8080",
      "/healthz": "http://localhost:8080",
    },
  },
});

