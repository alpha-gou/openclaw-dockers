# 快速开始

本文适合第一次部署 OpenClaw Docker 的用户，覆盖预构建镜像部署、自行构建镜像、升级、日志查看与进入容器等常用操作。仓库提供两套并行编排，部署流程按环境二选一：

- **公网服务器**：[`cloud_server/`](../cloud_server) — Caddy HTTPS 反向代理，对外只暴露加密 443。
- **本地单机**：[`local/`](../local) — 明文 `http://localhost:18789` 直连，无需 HTTPS。

两者共享同一套 OpenClaw 运行时镜像 `alpha-gou/openclaw-dockers`（多架构，arm64/amd64），仅编排与访问方式不同。

## 部署方式概览

### 方式一：使用预构建镜像（未实现）

> ⚠️ 镜像尚未发布到 Docker Hub，`docker compose pull` 暂不可用。请改用下方「方式二：自行构建镜像」。

（待镜像发布后）直接用各环境的 `docker-compose.yml` 与 `.env.example` 启动。

### 方式二：自行构建镜像

适合需要自定义镜像、调试构建过程或验证本地修改的用户，构建定义见 [`Dockerfile`](../Dockerfile)。

---

## 公网服务器部署 (cloud_server)

面向有公网 IP 的服务器（如阿里云 ECS），核心特征是 Caddy HTTPS 反向代理 + 明文网关端口仅绑 loopback。

### 1. 获取配置文件

可以直接下载：

```bash
wget https://raw.githubusercontent.com/<你的仓库>/main/cloud_server/docker-compose.yml
wget https://raw.githubusercontent.com/<你的仓库>/main/cloud_server/.env.example
```

也可以直接克隆仓库，便于后续升级维护：

```bash
git clone <本仓库地址>
cd openclaw-dockers/cloud_server
```

### 2. 初始化环境变量

```bash
cp .env.example .env
```

至少配置以下几项：

| 变量 | 说明 |
| --- | --- |
| `MODEL_ID` / `BASE_URL` / `API_KEY` | 默认模型 ID、模型服务地址、模型密钥 |
| `OPENCLAW_GATEWAY_TOKEN` | Web 控制台登录 token |
| `CADDY_IP` | 客户端实际访问的 IP（公网服务器填公网 IP，且与访问地址一致）；未配置会导致 `caddy` 容器启动失败 |

> 完整可选项见 [`cloud_server/.env.example`](../cloud_server/.env.example)，IM 渠道按需填写。

### 3. 生成 HTTPS 自签证书（首次部署）

Caddy 默认启用 HTTPS，需先为访问 IP 生成自签证书。**公网 IP 必须手动生成**——Caddy 内置的 `tls internal` 只支持内网/本地地址，无法为公网 IP 签发。

```bash
sh caddy/generate-cert.sh <你的CADDY_IP>
# 例如：sh caddy/generate-cert.sh 123.57.245.84
```

生成 `caddy/caddy.crt` 与 `caddy/caddy.key`（已加入 `.gitignore`，勿提交）。详见 [HTTPS 反向代理](caddy-https.md)。

### 4. 启动容器

```bash
docker compose up -d
```

### 5. 访问服务

```text
https://<CADDY_IP>
```

- 浏览器首次访问会有自签证书警告，点「高级 → 继续前往」可临时放行；把 `caddy/caddy.crt` 装到客户端「受信任的根证书颁发机构」可永久消除警告（详见 [HTTPS 反向代理](caddy-https.md)）。
- 明文网关端口已绑 `127.0.0.1`，仅本机可达；需要明文兜底时走 SSH 隧道：`ssh -L <OPENCLAW_GATEWAY_PORT>:127.0.0.1:<OPENCLAW_GATEWAY_PORT> user@host`。

---

## 本地部署 (local)

面向本机单机，核心特征是明文 `http://localhost:18789` 直连、无 HTTPS。

### 前置：安装 Docker（仅首次）

部署 OpenClaw 需要本机有 Docker 与 Docker Compose。

- **macOS（Apple Silicon）**：按 [macOS Colima 环境准备](macos-colima-setup.md) 装好 Colima 并启动 VM：
  ```bash
  colima start --cpu 4 --memory 8 --disk 100 --vm-type vz
  ```
  完成后回到本节继续。OpenClaw 镜像是 arm64 原生，无需 Rosetta。
- **Linux / 其它平台**：自行安装 Docker 与 Docker Compose。

装好后用以下命令确认（看到 "Hello from Docker!" 即可）：

```bash
docker run --rm hello-world
docker compose version
```

### 1. 获取代码

```bash
git clone <本仓库地址>
cd openclaw-dockers/local
```

### 2. 初始化环境变量

```bash
cp .env.minimal .env   # 精简版，最快起步
# 或
cp .env.example .env   # 完整版，含所有可选项与注释
```

至少配置：

| 变量 | 说明 | 示例 |
| --- | --- | --- |
| `MODEL_ID` | 默认模型 ID | `gpt-4` |
| `BASE_URL` | 模型服务地址 | `https://api.openai.com/v1` |
| `API_KEY` | 模型服务密钥 | `sk-xxx` |
| `OPENCLAW_GATEWAY_TOKEN` | 网关登录 Token | `123456` |

一个最小示例：

```bash
MODEL_ID=gemini-3-flash-preview
BASE_URL=http://localhost:3000/v1
API_KEY=your-api-key
API_PROTOCOL=openai-completions
CONTEXT_WINDOW=1000000
MAX_TOKENS=8192
OPENCLAW_GATEWAY_TOKEN=123456
```

> IM 平台配置可以暂时留空，后续再按需启用。

### 3. 启动服务

```bash
docker compose up -d
```

### 4. 访问服务

```text
http://localhost:18789
```

- 浏览器直接打开，输入 `OPENCLAW_GATEWAY_TOKEN` 登录即可。
- 默认端口绑 `127.0.0.1`，仅本机可达。如需局域网内其它机器访问，把 [`local/docker-compose.yml`](../local/docker-compose.yml) 中 `openclaw-gateway` 的 `ports` 前缀由 `127.0.0.1:` 改为 `0.0.0.0:`，并在 `OPENCLAW_GATEWAY_ALLOWED_ORIGINS` 补上 `http://<局域网IP>:18789`。明文暴露到网络有被抓包风险，公网请改用 [cloud_server](#公网服务器部署-cloud_server) 方案。

---

## 自行构建镜像（两环境通用）

镜像定义在 [`Dockerfile`](../Dockerfile)，在仓库根目录构建：

```bash
# 默认最新版
docker build -t alpha-gou/openclaw-dockers:latest .

# 指定 OpenClaw 版本
docker build --build-arg OPENCLAW_VERSION=2026.6.1 -t alpha-gou/openclaw-dockers:latest .

# 可选：带 clawhub 登录 token 以拉取私有扩展
docker build --build-arg CLAWHUB_TOKEN=你的token -t alpha-gou/openclaw-dockers:latest .
```

> 自行构建时镜像 tag 必须与 `.env` 中 `OPENCLAW_IMAGE` 一致，否则 compose 会去拉取远端镜像而非使用本地构建结果。

---

## 查看日志与停止

```bash
docker compose logs -f      # 跟踪日志
docker compose down          # 停止
```

---

## 启用沙箱支持 (可选)

沙箱功能用于隔离 AI 执行 Python 代码与 Shell 脚本的环境，防止对主容器造成潜在安全威胁。两环境的 `docker-compose.yml` 都已预留 docker.sock 挂载注释。

1. 修改 `.env`，启用沙箱模式：
   ```bash
   OPENCLAW_SANDBOX_MODE=all
   ```
2. 修改对应环境的 `docker-compose.yml`（`openclaw-gateway` 下），取消 `/var/run/docker.sock` 挂载的注释：
   ```yaml
   volumes:
     - ${OPENCLAW_DATA_DIR}:/home/node/.openclaw
     - openclaw-extensions:/home/node/.openclaw/extensions
     # 取消下面这一行的注释
     - /var/run/docker.sock:/var/run/docker.sock
   ```
3. 重新启动：
   ```bash
   docker compose up -d --force-recreate
   ```

> macOS/Colima 环境下 docker.sock 对 `docker compose` 透明，取消注释即可正常工作。详见 [配置指南 · 沙箱配置](configuration.md#沙箱配置-sandbox)。

详细配置说明请参考 [配置指南](configuration.md#沙箱配置-sandbox)。

---

## 升级建议

推荐直接克隆仓库进行维护。升级时，先同步项目文件，再拉取镜像并重建容器，避免遗漏新增的环境变量、Compose 编排或文档变更。

```bash
# 首次使用
git clone <本仓库地址>
cd openclaw-dockers/<cloud_server|local>

# 后续升级时同步仓库
git pull

# 根据最新模板检查本地 .env
# 必要时对照 .env.example 补充新增配置

# 拉取镜像并重建
docker compose pull   # ⚠️ 未实现：镜像尚未发布，跳过此步，确保已自行构建
docker compose up -d --force-recreate
```

## 升级后运行 openclaw doctor

当 openclaw 升级（尤其是大版本重构）后，可能需要运行 `openclaw doctor` 修复配置/插件。两环境均提供 `openclaw-installer` 工具容器（`tools` profile）。

### 方法一：`run` 显式清空 entrypoint

```bash
docker compose --profile tools run --rm --entrypoint "" openclaw-installer \
  openclaw doctor --fix --non-interactive
```

### 方法二：先启动 installer，再用 `exec` 进入执行

```bash
docker compose --profile tools up -d openclaw-installer
docker compose exec openclaw-installer openclaw doctor --fix --non-interactive
docker compose --profile tools stop openclaw-installer
docker compose up -d openclaw-gateway
```

`exec` 不经过 entrypoint，直接在已有容器内执行命令，不会有参数解析问题。

---

## 进入容器

```bash
docker compose exec openclaw-gateway /bin/bash
su node     # 推荐切到 node 用户，避免权限上下文不一致
```

容器内常用命令：

```bash
openclaw --version
cat ~/.openclaw/openclaw.json
ls -la ~/.openclaw/workspace
openclaw pairing approve telegram {token}     # 手动配对审批
npx -y @larksuite/openclaw-lark-tools install # 手动安装飞书官方插件
```

## 独立工具容器

`openclaw-installer`（`tools` profile）用于一次性的交互式安装或维护（如飞书官方团队插件）：

```bash
docker compose --profile tools up -d openclaw-installer
docker exec -it openclaw-installer bash
su node
```

## 部署后的建议检查项

- 公网服务器：确认 `443` 监听、云安全组放行 443、网关端口未对外开放。
- 本地：确认 `18789` 监听在 `127.0.0.1`（`lsof -iTCP:18789 -sTCP:LISTEN`）。
- 确认 `.env` 中至少完成模型与 Gateway Token 配置。
- 确认宿主机数据目录对容器可写。
- 如需接入 IM 平台，按 [配置指南](configuration.md) 补充对应环境变量。

## 下一步

- 配置指南：[`configuration.md`](configuration.md)
- 故障排查：[`faq.md`](faq.md)
- macOS 装 Docker：[`macos-colima-setup.md`](macos-colima-setup.md)
- 公网 HTTPS 详解：[`caddy-https.md`](caddy-https.md)
- AIClient-2-API 对接：[`aiclient-2-api.md`](aiclient-2-api.md)
- 高级运行方式：[`advanced.md`](advanced.md)
