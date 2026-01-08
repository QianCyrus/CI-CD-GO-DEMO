import { defineConfig } from "vite";

// 本地开发时把 /api 与 /healthz 代理到 Go 后端（:8080）
export default defineConfig({
  server: {
    proxy: {
      "/api": "http://localhost:8080",
      "/healthz": "http://localhost:8080",
    },
  },
});

