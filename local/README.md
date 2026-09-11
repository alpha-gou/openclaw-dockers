# OpenClaw 本地环境 Docker 部署 (alpha-gou 维护版)

本项目是 [`openclaw-dockers`](..) 仓库的**本地单机部署**方案，与 [`cloud_server/`](../cloud_server) 并列，面向在自己机器上运行 OpenClaw 的用户。

## 项目简介

将命令行 AI 助手 OpenClaw 打包为可直接运行的 Docker 服务，提供 Web 控制台与多种 IM 渠道机器人（Telegram / 飞书 / 钉钉 / 企业微信 / QQ / NapCat）。

- **本地单机定位**：明文网关端口只绑 `127.0.0.1`，直接 `http://localhost:18789` 访问，无需 HTTPS、无需自签证书。
- **macOS 友好**：Apple Silicon Mac 用 [Colima](../docs/macos-colima-setup.md) 即可从零搭建 Docker 环境，arm64 原生运行，virtiofs 挂载性能接近原生。
- **复用共享镜像**：运行时镜像 `alpha-gou/openclaw-dockers`（**尚未发布到 Docker Hub，需自行构建，见下**）由 [`Dockerfile`](../Dockerfile) 构建，`local/` 与 `cloud_server/` 共用同一套软件，本目录只做编排与文档适配，不重复 Dockerfile / init.sh。
- **与 cloud_server 的差异**：去掉了 Caddy HTTPS 反向代理（那是公网服务器暴露明文端口才需要的）；其余模型、渠道、沙箱、Agent Reach 等能力完全一致。

## 前置条件

本机已安装 Docker 与 Docker Compose。

- **macOS（Apple Silicon）**：若尚未安装 Docker，推荐用 Colima 搭建"服务器般"的 Docker 环境（轻量 VM，无 Docker Desktop 的 GUI 负担与商业授权问题），完整从零步骤见 [macOS Colima 环境准备](../docs/macos-colima-setup.md)。搭好后回到本文继续。
- **Linux / 其它平台**：自行安装 Docker 与 Docker Compose。

> Colima 用 `vz` + virtiofs，宿主 `~/.openclaw` 挂载性能接近原生；OpenClaw 镜像是多架构（arm64 原生），Apple Silicon 无需 Rosetta。

## 使用方式

> macOS 用户：如果还没装 Docker，先按 [macOS Colima 环境准备](../docs/macos-colima-setup.md) 装好 Colima 并 `colima start`，再回到这里。

### 1. 获取代码

```bash
git clone <本仓库地址>
cd openclaw-dockers/local
```

### 2. 准备镜像

> ⚠️ **镜像尚未发布到 Docker Hub，`docker compose pull` 暂不可用（未实现），请先用下方「自行构建」方式构建本地镜像。**

**A. 使用预构建镜像（未实现，待镜像发布后可用）**

```bash
docker compose pull   # ⚠️ 未实现：镜像尚未发布
```

**B. 自行构建镜像（当前可用方式）**

镜像定义在仓库根的 `Dockerfile`，在仓库根目录执行：

```bash
# 默认最新版
docker build -t alpha-gou/openclaw-dockers:latest .

# 指定 OpenClaw 版本
docker build --build-arg OPENCLAW_VERSION=2026.6.1 -t alpha-gou/openclaw-dockers:latest .

# 可选：带 clawhub 登录 token 以拉取私有扩展
docker build --build-arg CLAWHUB_TOKEN=你的token -t alpha-gou/openclaw-dockers:latest .
```

> 自行构建时镜像 tag 必须与 `.env` 中 `OPENCLAW_IMAGE` 一致，否则 compose 会去拉取远端镜像而非使用本地构建结果。

### 3. 配置环境变量

```bash
cp .env.minimal .env   # 精简版，最快起步
# 或
cp .env.example .env   # 完整版，含所有可选项与注释
```

至少配置以下几项：

| 变量 | 说明 |
| --- | --- |
| `MODEL_ID` / `BASE_URL` / `API_KEY` | 默认模型 ID、模型服务地址、模型密钥 |
| `OPENCLAW_GATEWAY_TOKEN` | Web 控制台登录 token |

> 完整可选项见 [`.env.example`](.env.example)，IM 渠道（飞书/钉钉/企微/QQ/Telegram/NapCat）按需填写。

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

### 4. 启动容器

```bash
docker compose up -d
```

查看日志 / 停止：

```bash
docker compose logs -f
docker compose down
```

### 5. 访问服务

```text
http://localhost:18789
```

- 浏览器直接打开上述地址，输入 `OPENCLAW_GATEWAY_TOKEN` 登录即可使用网关控制台。
- 明文网关端口已绑 `127.0.0.1`，仅本机可达。如需局域网内其它机器访问，把 [`docker-compose.yml`](docker-compose.yml) 中 `openclaw-gateway` 的 `ports` 前缀由 `127.0.0.1:` 改为 `0.0.0.0:`，并自行评估明文暴露风险（公网请改用 `cloud_server/` 的 Caddy HTTPS 方案）。

更多细节见 [快速开始](../docs/quick-start.md) 与 [配置指南](../docs/configuration.md)。

## 升级与运行 openclaw doctor

当 openclaw 升级（尤其是大版本重构）后，可能需要运行 `openclaw doctor` 修复配置/插件。本项目提供 `openclaw-installer` 工具容器（`tools` profile，见 [docker-compose.yml](docker-compose.yml)）来执行。你有两种选择：

### 方法一：`run` 命令显式清空 entrypoint

```bash
docker compose --profile tools run --rm --entrypoint "" openclaw-installer \
  openclaw doctor --fix --non-interactive
```

`--entrypoint ""` 会将 entrypoint 置空，此时 `openclaw doctor --fix --non-interactive` 才会被当作容器启动命令正确执行。

### 方法二：先启动 installer，再用 `exec` 进入执行（更直观）

```bash
# 1. 启动 installer 容器（后台运行，entrypoint 仍是 tail -f，不会退出）
docker compose --profile tools up -d openclaw-installer

# 2. 进入容器执行 doctor 命令
docker compose exec openclaw-installer openclaw doctor --fix --non-interactive

# 3. 修完后停掉 installer（可选）
docker compose --profile tools stop openclaw-installer

# 4. 启动 gateway
docker compose up -d openclaw-gateway
```

`exec` 不会经过 entrypoint，直接在已有容器内执行命令，不会有参数解析问题。

## 与 cloud_server 的关系

| 维度 | `local/`（本目录） | `cloud_server/` |
| --- | --- | --- |
| 定位 | 本机单机 | 公网服务器（如阿里云 ECS） |
| HTTPS | 无，明文 `http://localhost` | Caddy 自签证书 HTTPS 443 |
| 网关端口 | 绑 `127.0.0.1`，仅本机可达 | 绑 `127.0.0.1`，对外只走 Caddy 443 |
| 运行时镜像 | **共享** `alpha-gou/openclaw-dockers` | 同左（且 Dockerfile/init.sh 源在此） |
| 部署步骤 | 配 .env → `up -d` → 访问 | 额外需生成自签证书、放行 443 |

环境无关的进阶文档不在本目录重复，直接参考 [`docs/`](../docs/)：

- [AIClient-2-API 对接](../docs/aiclient-2-api.md)
- [高级运行方式](../docs/advanced.md)
- [开发者说明](../docs/developer-notes.md)
- [微信相关](../docs/wechat.md)

## 相关文档

- macOS 从零装 Docker：[Colima 环境准备](../docs/macos-colima-setup.md)
- [快速开始](../docs/quick-start.md)
- [配置指南](../docs/configuration.md)
- [故障排查](../docs/faq.md)
