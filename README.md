# cicd-go-demo (monorepo)

这是一个**尽量小**、但把 CI/CD 关键点都串起来的 Go Demo（同时模拟 monorepo：`backend/` + `frontend/`）。

## 目录结构

- `backend/`: Go 后端（分层：transport/http -> service），自带单元测试/HTTP 测试
- `deploy/`: 用于“零宕机”部署的蓝绿脚本（在服务器上执行）
- `.github/workflows/`: GitHub Actions 的 CI/CD（安全/缓存/多环境/paths 过滤）

## 本地运行与测试

在仓库根目录：

```bash
cd backend
go test ./...
go run ./cmd/server
```

启动后访问：

- `GET http://localhost:8080/healthz`
- `GET http://localhost:8080/api/v1/hello?name=world`

前端（可选，用于演示 monorepo + npm 缓存）：

```bash
cd frontend
npm ci
npm run dev
```

然后在浏览器打开 `http://localhost:5173`（Vite 会把 `/api` 代理到后端 `:8080`）。

## CI/CD 设计（按你的 5 个挑战点逐一落地）

### 挑战一：安全（最重要）

**原则：任何服务器 IP/账号/密码/SSH Key/注册表 Token 都不写进代码仓库。**

本 demo 的做法：

- **用 GitHub Environments + Secrets** 管理不同环境的机密（推荐）
  - `Settings -> Environments -> dev / production`
  - 在每个 environment 里配置 secrets（见下方清单）
- workflow 里只用 `${{ secrets.xxx }}` 引用
- SSH 连接启用 `known_hosts`（避免新手常见的 `StrictHostKeyChecking=no` 造成 MITM 风险）

**需要在 GitHub 里创建的 secrets（建议放在 Environment 级别）**

用于 `dev` 和 `production` 两套环境分别配置（值不同）：

- `SERVER_HOST`: 服务器域名或 IP
- `SERVER_USER`: SSH 用户名
- `SERVER_PORT`: SSH 端口（可选；不配默认 22）
- `SERVER_SSH_KEY`: 私钥（建议用单独创建的部署 key，权限最小化）
- `SERVER_KNOWN_HOSTS`: `ssh-keyscan -H <host>` 的输出（至少包含服务器主机指纹）
- `GHCR_USERNAME`: 用于服务器 `docker login ghcr.io` 的用户名
- `GHCR_TOKEN`: PAT（至少 `read:packages`），用于服务器拉取 GHCR 镜像

> 进阶：大公司常用 **OIDC**（短期凭证，用完即焚）替代长期密钥；这个 demo 在 README 里讲清思路，但不强依赖云厂商账号，避免把学习门槛拉高。

### 挑战二：速度优化（Caching）

我们做了两层缓存：

- **Go 依赖/编译缓存**：`actions/setup-go` 开启 `cache: true`
- **Docker 分层缓存**：`docker/build-push-action` 使用 `cache-to/cache-from: type=gha`

目标是：大部分提交只改业务代码时，不用每次重新下载依赖/重建基础层，把构建时间压到 1~2 分钟量级。

### 挑战三：部署策略（零宕机 + 回滚）

这里用的是**蓝绿部署（Blue/Green）**：

- 服务器上同时存在 `app-blue`/`app-green` 两个容器名
- 新版本先部署到“空闲色”，通过 `/healthz` 健康检查
- 再让 Nginx reload，把流量切到新色
- 最后删除旧色容器

回滚：

- 服务器会记录 `current_image` / `previous_image`
- workflow 提供 `workflow_dispatch` 的 **rollback**，一键切回上一个镜像

对应脚本：`deploy/scripts/bluegreen.sh`

对应 workflow：

- `deploy-dev`: `.github/workflows/deploy-dev.yml`
- `deploy-production`: `.github/workflows/deploy-production.yml`
- `rollback`: `.github/workflows/rollback.yml`

### 挑战四：多环境（Dev/Test/Prod）

- `push` 到 `dev` 分支：部署到 **dev 环境服务器**
- `push` 到 `main` 分支或打 `v*` tag：部署到 **production**
- 生产环境 job 使用 `environment: production`，你可以在 GitHub 里给 production 配置 **Required reviewers**，实现“上线必须审批”

### 挑战五：Monorepo 触发控制（paths 过滤）

workflow 在 `on.push.paths`/`on.pull_request.paths` 上做了过滤：

- 只改 `frontend/**` 不会触发后端 CI/CD
- 只改 `backend/**` 不会触发前端 CI

对应 workflow：

- 后端 CI：`.github/workflows/backend-ci.yml`
- 前端 CI：`.github/workflows/frontend-ci.yml`

## 你需要做的事（把 demo 真跑起来）

1) 把本目录推到你自己的 GitHub 仓库（public/private 均可）

### 推到 GitHub（最短命令）

先在 GitHub 网页新建一个空仓库（不要勾选 “Add a README”）。

然后在本地仓库根目录执行（把 `<REPO_URL>` 替换成你的仓库地址，SSH/HTTPS 都行）：

```bash
git remote add origin <REPO_URL>
git push -u origin main
git push -u origin dev
```
2) 在仓库 `Settings -> Environments` 创建 `dev` 与 `production`
3) 为两个 environment 分别添加上面的 secrets
4) 服务器准备：
   - 安装 Docker
   - 允许 SSH 登录
   - 开放 80 端口（Nginx 对外监听）
5) 推送到 `dev` 分支观察自动部署；再合并到 `main`（或打 `v*` tag）观察 production 审批与部署

> 小抄：`SERVER_KNOWN_HOSTS` 可以在本地执行 `ssh-keyscan -H <host>` 获取（把输出整段复制到 secret）。

## 怎么“展示我会 CI/CD”（面试/汇报用最短剧本）

1) **展示 monorepo paths 触发**
   - 只改 `frontend/src/style.css`，提 PR：只会跑 `frontend-ci`
   - 只改 `backend/internal/service/greeter.go`，提 PR：只会跑 `backend-ci`

2) **展示缓存（速度优化）**
   - 连续 push 两次很小的改动，去 Actions 看日志：第二次会出现 cache hit（npm/go/docker layer cache）

3) **展示 CD（不用服务器也能演示）**
   - 合并到 `main` 且只改 `frontend/**`：会自动跑 `deploy-frontend-pages` 发布到 GitHub Pages（纯 GitHub 资源）

4) **展示“真部署 + 零宕机 + 审批 + 回滚”（需要你准备服务器并配置 secrets）**
   - push 到 `dev`：跑 `deploy-dev`（蓝绿切流量）
   - 合并到 `main`：跑 `deploy-production`（production environment 可配置 Required reviewers，需网页点 Approve）
   - 出问题时：手动触发 `rollback`，一键回滚到上一个镜像
