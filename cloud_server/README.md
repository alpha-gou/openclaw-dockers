# OpenClaw-Dockers · 公网服务器部署 (alpha-gou 维护版)

## 新特性

- openclaw 升级为最新正式版（2026.6.1）
- 镜像构建时支持国内环境，在阿里云服务器上运行良好。（对于window、linux可能不支持）
- 新增 Caddy HTTPS 反向代理（默认启用）：对外只暴露加密 443，默认关闭明文 18789，公网/内网访问更安全。**注意**：需要在 `.env` 配置 `CADDY_IP`（公网服务器填公网 IP，且要与客户端实际访问地址一致），未配置会导致 `caddy` 容器启动失败。用不到 HTTPS 时可注释掉 `docker-compose.yml` 中的 `caddy` service 并还原网关明文端口。详见 [HTTPS 反向代理](../docs/caddy-https.md)。

## 项目简介

OpenClaw 的国内环境 Docker 一键部署方案（alpha-gou 维护版）。

- 将命令行 AI 助手 OpenClaw 打包为可直接运行的 Docker 服务，提供 Web 控制台与多种 IM 渠道机器人（Telegram / 飞书 / 钉钉 / 企业微信 / QQ / NapCat）。
- 面向中国大陆环境优化：使用国内 Debian / 阿里云 / npmmirror 镜像源，在阿里云 ECS 上开箱即用。
- 内置 Caddy HTTPS 反向代理，对外仅暴露加密 443、默认关闭明文 18789，保护网关鉴权与对话流量不被抓包。

## 使用方式

前置条件：已安装 Docker 与 Docker Compose。

### 1. 获取代码

```bash
git clone <本仓库地址>
cd openclaw-dockers/cloud_server
```

### 2. 准备镜像

> ⚠️ **镜像尚未发布到 Docker Hub，`docker compose pull` 暂不可用（未实现），请先用下方「自行构建」方式构建本地镜像。**

**A. 使用预构建镜像（未实现，待镜像发布后可用）**

```bash
docker compose pull   # ⚠️ 未实现：镜像尚未发布
```

**B. 自行构建镜像（当前可用方式）**

需在仓库根目录执行（从 cloud_server 目录先 `cd ..`）：

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
cp .env.example .env
```

至少配置以下几项：

| 变量 | 说明 |
| --- | --- |
| `MODEL_ID` / `BASE_URL` / `API_KEY` | 默认模型 ID、模型服务地址、模型密钥 |
| `OPENCLAW_GATEWAY_TOKEN` | Web 控制台登录 token |
| `CADDY_IP` | 客户端实际访问的 IP（公网服务器填公网 IP，且与访问地址一致）；未配置会导致 `caddy` 容器启动失败 |

> 完整可选项见 [`.env.example`](.env.example)，IM 渠道（飞书/钉钉/企微/QQ/Telegram/NapCat）按需填写。

### 4. 生成 HTTPS 自签证书（首次部署）

Caddy 默认启用 HTTPS 反向代理，需先为你的访问 IP 生成一张自签证书。**公网 IP 必须手动生成**——Caddy 内置的 `tls internal` 只支持内网/本地地址，无法为公网 IP 签发，会报 `tlsv1 alert internal error`。

```bash
sh caddy/generate-cert.sh <你的CADDY_IP>
# 例如：sh caddy/generate-cert.sh 123.57.245.84
```

生成 `caddy/caddy.crt` 与 `caddy/caddy.key`（已加入 `.gitignore`，勿提交）。

> 若报错 `Is a directory`：说明 Docker 之前已把同名路径建成了空目录，先删掉再生成：
> ```bash
> rm -rf caddy/caddy.crt caddy/caddy.key
> sh caddy/generate-cert.sh <你的CADDY_IP>
> ```

### 5. 启动容器

```bash
docker compose up -d
```

查看日志 / 停止：

```bash
docker compose logs -f
docker compose down
```

### 6. 访问服务

```text
https://<CADDY_IP>
```

- 浏览器首次访问会有自签证书警告，点「高级 → 继续前往」可临时放行；把 `caddy/caddy.crt` 装到客户端「受信任的根证书颁发机构」可永久消除警告（详见 [HTTPS 反向代理](../docs/caddy-https.md)）。
- 明文网关端口已绑 `127.0.0.1`，仅本机可达；需要明文兜底时走 SSH 隧道：`ssh -L <OPENCLAW_GATEWAY_PORT>:127.0.0.1:<OPENCLAW_GATEWAY_PORT> user@host`。

更多细节见 [快速开始](../docs/quick-start.md) 与 [配置指南](../docs/configuration.md)。

## 升级与运行 openclaw doctor

当 openclaw 升级（尤其是大版本重构）后，可能需要运行 `openclaw doctor` 修复配置/插件。本项目提供了 `openclaw-installer` 工具容器（`tools` profile，见 [docker-compose.yml](docker-compose.yml)）来执行。你有两种选择：

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



