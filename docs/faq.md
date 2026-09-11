# 常见问题

本文汇总 OpenClaw Docker 当前版本的高频问题与排查建议，内容以两套环境的 `docker-compose.yml`、[`.env.example`](../cloud_server/.env.example) / [`local/.env.example`](../local/.env.example)、[`init.sh`](../init.sh) 与仓库内现有说明为准。两套环境（[`cloud_server/`](../cloud_server) 公网服务器、[`local/`](../local) 本地单机）共享同一运行时镜像，运行时排查逻辑通用，访问/本地环境相关项已按环境标注。

---

## 配置与同步

### 修改了环境变量，但配置没有按预期生效

容器启动时会执行 [`init.sh`](../init.sh)，并根据当前环境变量同步模型、渠道、插件、Gateway 等配置到 `openclaw.json`。但以下情况仍会让你感觉"没有生效"：

- 实际启动的不是你刚修改的那份 [`.env`](../cloud_server/.env.example)
- 容器没有重建或重启
- 你手动维护的 `openclaw.json` 中存在与环境变量冲突的旧字段
- 相关渠道缺少必要环境变量，结果被启动脚本自动禁用

**建议排查顺序：**

1. 确认当前目录下的 `.env` 已保存。
2. 重建或重启容器：
   ```bash
   docker compose up -d --force-recreate
   ```
3. 查看启动日志是否出现"同步完成""渠道同步""已禁用渠道"等：
   ```bash
   docker compose logs -f openclaw-gateway
   ```
4. 进入容器检查实际配置：
   ```bash
   docker compose exec openclaw-gateway /bin/bash
   su node
   cat ~/.openclaw/openclaw.json
   ```

**彻底回到"从环境变量重新生成"**：删配置文件后重启：

```bash
rm ~/.openclaw/openclaw.json
docker compose restart
```

或连历史数据一起清空：

```bash
rm -rf ~/.openclaw
docker compose up -d
```

> 若你手动维护 `openclaw.json`，可把 `SYNC_OPENCLAW_CONFIG=false`，避免启动同步覆盖你的修改。

### 启动后看不到某个平台生效

[`init.sh`](../init.sh) 会根据是否提供了"必需环境变量"来启用或禁用渠道：

- 飞书需要 `FEISHU_APP_ID` 和 `FEISHU_APP_SECRET`，或 `FEISHU_ACCOUNTS_JSON`
- 钉钉需要 `DINGTALK_CLIENT_ID` 和 `DINGTALK_CLIENT_SECRET`，或 `DINGTALK_ACCOUNTS_JSON`
- QQ 机器人需要 `QQBOT_APP_ID` 和 `QQBOT_CLIENT_SECRET`，或 `QQBOT_BOTS_JSON`
- 企业微信需要 `WECOM_BOT_ID` 和 `WECOM_SECRET`，或 `WECOM_ACCOUNTS_JSON`
- NapCat 需要 `NAPCAT_REVERSE_WS_PORT`

缺字段时，启动脚本会把对应插件或渠道设为禁用。排查：

```bash
docker compose logs -f openclaw-gateway
```

重点看关键词：`渠道同步`、`已禁用渠道`、`未提供环境变量`、`已根据 ... 多账号环境变量启用插件`。详细变量说明见 [`configuration.md`](configuration.md)。

### `OPENCLAW_GATEWAY_BIND` 该填什么？为什么不是 `localhost`？

保持默认 `lan`。网关在**容器内**绑定，需绑到容器内可达接口，宿主的端口转发才能把流量送进来。安全由各环境 `docker-compose.yml` 里宿主侧 `127.0.0.1:` 端口映射保证（公网再叠加 Caddy 443），与 `bind` 无关。详见 [配置指南 · Gateway 配置](configuration.md#gateway-配置)。

---

## 渠道与插件

### 飞书机器人能发消息，但收不到消息

优先检查飞书开放平台后台的"事件与回调"配置：

- 是否选择"使用长连接接收事件"
- 是否订阅 `im.message.receive_v1`
- 相关权限是否已申请并通过审核
- 机器人是否确实安装到了目标聊天或群组

如果你启用的是飞书官方团队插件，还要确认交互式安装已经完成，而不是只设置了环境变量。

### 飞书官方插件为什么没有自动安装

飞书官方团队插件安装命令 `npx -y @larksuite/openclaw-lark-tools install` 是交互式流程，无法在 [`Dockerfile`](../Dockerfile) 构建阶段自动完成，所以项目只在镜像里准备运行环境，不会直接帮你走完安装向导。

**正确做法**：使用 `openclaw-installer` 工具容器：

```bash
docker compose up -d openclaw-gateway
docker compose --profile tools up -d openclaw-installer
docker exec -it openclaw-installer bash
su node
npx -y @larksuite/openclaw-lark-tools install
```

安装完成后，再按需在 `.env` 中设置 `FEISHU_OFFICIAL_PLUGIN_ENABLED=true`。完整流程见 [`quick-start.md`](quick-start.md) 的工具容器说明。

### 出现 `plugin not found: openclaw-lark`

通常说明飞书官方团队插件尚未完成交互式安装，或安装发生在错误的容器里。重新按工具容器流程执行：

```bash
docker compose --profile tools up -d openclaw-installer
docker exec -it openclaw-installer bash
su node
npx -y @larksuite/openclaw-lark-tools install
# 版本不匹配时：npx -y @larksuite/openclaw-lark-tools update
```

### NapCat 应该怎么启用

NapCat 相关扩展已在镜像中预装，但是否启用取决于环境变量。至少需要：

```bash
NAPCAT_REVERSE_WS_PORT=3001
```

常用可选项还有 `NAPCAT_HTTP_URL`、`NAPCAT_ACCESS_TOKEN`、`NAPCAT_ADMINS`、`NAPCAT_DM_POLICY`、`NAPCAT_GROUP_POLICY`。启动后通过日志确认是否出现 NapCat 渠道同步信息。

---

## 模型与 Provider

### 连接 AI / Provider 失败

按以下顺序排查：

- 检查 `BASE_URL` 是否正确
- 如果是 OpenAI 兼容接口，通常需要带 `/v1`
- 检查 `API_KEY` 是否正确
- 检查 `API_PROTOCOL` 是否与服务实际协议一致
- 如果配置了多个 Provider，检查 `MODEL2_*`、`MODEL3_*` 等是否填完整
- 如果显式设置了 `PRIMARY_MODEL` 或 `IMAGE_MODEL_ID`，检查引用格式是否正确（如 `default/gpt-4o`、`aliyun/qwen3.5-plus`）

模型与 Provider 规则见 [`configuration.md`](configuration.md) 与 [`aiclient-2-api.md`](aiclient-2-api.md)。

### 出现 401 / 403 错误

常见原因：`API_KEY` 填错；Provider 后端本身拒绝当前模型或账号；代理层改写或丢失了认证头；使用了不匹配的 `BASE_URL` / `API_PROTOCOL`。建议先用最小配置只保留一组模型参数验证，再逐步叠加复杂配置。

### `PRIMARY_MODEL` 或 `IMAGE_MODEL_ID` 写了以后模型还是不对

项目会对模型引用做归一化处理：

- 不带 `/` 时，自动视为 `default/<模型名>`
- 带 `/` 且前缀是已知 Provider 名称时，视为完整引用
- 带 `/` 但前缀不是已知 Provider 名称时，视为 `default/...`

例如：

```bash
MODEL_ID=qwen3.5-plus
MODEL2_NAME=aliyun
MODEL2_MODEL_ID=qwen-max,qwen3.5-plus
PRIMARY_MODEL=aliyun/qwen3.5-plus
IMAGE_MODEL_ID=default/qwen3.5-plus
```

相关规则见 [`configuration.md`](configuration.md) 与 [`init.sh`](../init.sh)。

---

## 访问与端口

### 本地：浏览器打不开 `http://localhost:18789`

依次确认：

1. 容器在运行：`docker compose ps`，`openclaw-gateway` 应为 Up。
2. 端口在监听：`lsof -iTCP:18789 -sTCP:LISTEN`，应看到 `127.0.0.1:18789`。
   - 无输出：容器未起或端口未映射，`docker compose logs openclaw-gateway` 看报错。
   - 端口被占用：改 `.env` 的 `OPENCLAW_GATEWAY_PORT` 换空闲端口，重建容器。
3. `OPENCLAW_GATEWAY_TOKEN` 已配置。

### 本地：本机能访问，但局域网内其它机器访问不了

默认 `ports` 绑 `127.0.0.1`，仅本机可达。如需局域网访问：

1. 修改 [`local/docker-compose.yml`](../local/docker-compose.yml) 的 `ports` 行，前缀改为 `0.0.0.0`：
   ```yaml
   ports:
     - "0.0.0.0:${OPENCLAW_GATEWAY_PORT}:${OPENCLAW_GATEWAY_PORT}"
   ```
2. `OPENCLAW_GATEWAY_ALLOWED_ORIGINS` 补上 `http://<本机局域网IP>:${OPENCLAW_GATEWAY_PORT}`。
3. `docker compose up -d --force-recreate`。

> ⚠️ 明文暴露到局域网/公网有被中间人抓包风险（网关 Token、对话内容均明文）。公网场景请改用 [`cloud_server/`](../cloud_server) 的 Caddy HTTPS 方案，详见 [`caddy-https.md`](caddy-https.md)。

### 控制台能进但部分请求失败 / 跨源报错

检查 `OPENCLAW_GATEWAY_ALLOWED_ORIGINS` 是否包含浏览器地址栏实际使用的地址（含端口）。本地默认是 `http://localhost:18789`；用 `http://127.0.0.1:18789` 或局域网 IP 访问时需补上对应地址。

### 公网：浏览器报 `ERR_SSL_PROTOCOL_ERROR` / curl 报 `tlsv1 alert internal error`

确认 [`caddy-https.md`](caddy-https.md) 的 Caddyfile 用 `:443`（不是 `https://<IP>:443`），且证书是 `generate-cert.sh` 生成的手动证书（不是 `tls internal`）。公网 IP 用 `tls internal` 或按 IP 限定 host 都会触发此错。改完后 `docker compose up -d --force-recreate caddy`。完整排障见 [`caddy-https.md`](caddy-https.md#常见问题与排障)。

---

## 镜像与权限

### 镜像找不到 / 拉取未实现

镜像**尚未发布到 Docker Hub**，`docker compose pull` 不可用。请直接自行构建：

```bash
docker build -t alpha-gou/openclaw-dockers:latest .
```

> 镜像发布后，国内网络拉取慢可加镜像前缀，例如把 `.env` 的 `OPENCLAW_IMAGE` 改为 `docker.m.daocloud.io/alpha-gou/openclaw-dockers:latest`。

### 出现 `Permission denied` / 容器内 node 用户无法写挂载目录

宿主机目录所有者与容器内 node 用户 UID/GID 不一致。当前项目默认允许容器先以 root 启动，[`init.sh`](../init.sh) 会尝试修复 `/home/node/.openclaw` 权限，再降权为 node 启动。

常见原因：宿主机目录由 root 或其他 UID 创建；目录可读但不可写；SELinux 对挂载卷额外限制。

修法（任选）：

- `.env` 设 `TARGET_UID` / `TARGET_GID` 为宿主机 `id -u` / `id -g`，让 init.sh 自动对齐 node 用户。
- 或直接指定运行用户：`OPENCLAW_RUN_USER=$(id -u):$(id -g)`。
- 或宿主机手动修正：`sudo chown -R 1000:1000 ~/.openclaw`（按实际 UID:GID）。
- SELinux 环境在挂载卷后加 `:z` 或 `:Z`。

### 进入容器后某些命令报权限错

默认以 root 进入，需切到 node 用户：

```bash
docker compose exec openclaw-gateway /bin/bash
su node
```

尤其是插件安装、配对审批、查看用户目录配置时，使用 `node` 用户更符合实际运行环境。

---

## 沙箱

### 启用沙箱后报找不到 Docker / 无法创建沙箱容器

Docker 沙箱需要把宿主机 docker.sock 挂进容器，并在 `.env` 设 `OPENCLAW_SANDBOX_MODE` 非 `off`：

1. 在对应环境的 `docker-compose.yml` 取消 `- /var/run/docker.sock:/var/run/docker.sock` 的注释。
2. `.env` 设 `OPENCLAW_SANDBOX_MODE=non-main`（或 `all`）。
3. `docker compose up -d --force-recreate`。

> macOS/Colima 下 docker.sock 对 `docker compose` 透明，取消注释即可正常工作。详见 [配置指南 · 沙箱配置](configuration.md#沙箱配置-sandbox)。

---

## macOS / Colima

> 完整的 Colima 安装与排障见 [`macos-colima-setup.md`](macos-colima-setup.md#常见问题处理)。

### `docker` 命令报 `Cannot connect to the Docker daemon`

Colima VM 没起。执行 `colima start`（或配好 [`~/.zshrc` 自动启停函数](macos-colima-setup.md#第四步配置开终端即用核心诉求)后，再敲 `docker` 会自动拉起 VM），`colima status` 确认运行中。

### `http://localhost:18789` 能访问，但 `~/.openclaw` 挂载读写很慢

确认 Colima 用的是 `vz` 类型（`colima start --vm-type vz`），它会自动启用 virtiofs，挂载性能接近原生。若当前是 QEMU 实例，`colima delete` 后用 `--vm-type vz` 重建。详见 [`macos-colima-setup.md`](macos-colima-setup.md#常见问题处理)。

### 之前装过 Docker Desktop，拉镜像 / 登录报 credential helper 错

编辑 `~/.docker/config.json`，把 `"credsStore": "desktop"` 改成 `"credsStore": "osxkeychain"`，或 `brew install docker-credential-helper`。

---

## 日志里提示 JSON 非法或配置冲突

当前版本的 [`init.sh`](../init.sh) 会对部分历史格式做兼容迁移，也会自动校验多账号冲突。常见报错包括：

- `FEISHU_ACCOUNTS_JSON 不是合法 JSON`
- `DINGTALK_ACCOUNTS_JSON 不是合法 JSON`
- `WECOM_ACCOUNTS_JSON 不是合法 JSON`
- `QQBOT_BOTS_JSON 不是合法 JSON`
- 飞书 App ID 冲突 / 钉钉 clientId / robotCode / Agent ID 冲突 / 企业微信 botId / Agent ID 冲突 / QQ 机器人 AppID 冲突

遇到这类问题时，优先检查对应 JSON 是否为合法对象，以及账号标识是否重复。

---

## 通用排查命令

```bash
# 服务状态
docker compose ps

# 跟踪日志
docker compose logs -f
docker compose logs -f openclaw-gateway

# 进入容器
docker compose exec openclaw-gateway /bin/bash
su node

# 容器内查看版本 / 配置
openclaw --version
cat ~/.openclaw/openclaw.json
```

## 下一步

- 快速开始：[`quick-start.md`](quick-start.md)
- 配置指南：[`configuration.md`](configuration.md)
- macOS 装 Docker：[`macos-colima-setup.md`](macos-colima-setup.md)
- 公网 HTTPS 详解：[`caddy-https.md`](caddy-https.md)
- AIClient-2-API：[`aiclient-2-api.md`](aiclient-2-api.md)
- 开发者说明：[`developer-notes.md`](developer-notes.md)
- 项目总览：[`cloud_server/README.md`](../cloud_server/README.md) / [`local/README.md`](../local/README.md)
