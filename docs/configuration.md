# 配置指南

本文聚焦 OpenClaw Docker 的核心配置项，包括模型、Gateway、工作空间、环境变量组织方式，以及与 [`openclaw.json.example`](../cloud_server/openclaw.json.example) 的对应关系。两套环境（[`cloud_server/`](../cloud_server) 公网服务器、[`local/`](../local) 本地单机）共享同一套 OpenClaw 运行时与配置语义，仅编排与访问方式不同。

## 配置文件关系

两套环境各自的配置入口：

| 文件 | 作用 |
| --- | --- |
| [`cloud_server/.env.example`](../cloud_server/.env.example) / [`local/.env.example`](../local/.env.example) | 完整环境变量模板，包含所有可选配置及详细注释 |
| [`cloud_server/.env.minimal`](../cloud_server/.env.minimal) / [`local/.env.minimal`](../local/.env.minimal) | 精简环境变量模板，仅包含运行必需的核心参数 |
| 各环境的 `docker-compose.yml` | 把环境变量注入容器并定义卷、端口、服务 |
| [`openclaw.json.example`](../cloud_server/openclaw.json.example) | OpenClaw 配置结构示例，用于理解最终生成结果 |
| [`init.sh`](../init.sh) | 启动时读取环境变量并生成 / 修正实际配置（已内置于共享镜像） |

默认情况下，容器首次启动时会根据环境变量自动生成 `openclaw.json`。如果你已经手动维护该文件，建议同时关注 `SYNC_MODEL_CONFIG` 的行为。

---

## AI 模型配置

项目支持以下协议：

- `openai-completions`
- `openai-responses`
- `google-generative-ai`
- `anthropic-messages`

推荐先完成这一部分，再接入 IM 平台。

### 基础参数

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `MODEL_ID` | 模型名称，支持多个值，逗号分隔 | `model id` |
| `PRIMARY_MODEL` | 显式指定 `agents.defaults.model.primary` | 留空 |
| `IMAGE_MODEL_ID` | 图片模型名称，可单独指定 | 留空 |
| `BASE_URL` | Provider Base URL | `http://xxxxx/v1` |
| `API_KEY` | Provider API Key | `123456` |
| `API_PROTOCOL` | API 协议类型 | `openai-completions` |
| `CONTEXT_WINDOW` | 上下文窗口大小 | `200000` |
| `MAX_TOKENS` | 最大输出 token 数 | `8192` |

### 协议说明

| 协议类型 | 适用模型 | Base URL 习惯 | 说明 |
| --- | --- | --- | --- |
| `openai-completions` | OpenAI、Gemini 等 | 通常需要 `/v1` | 最常见接入方式 |
| `openai-responses` | OpenAI (Beta) | 通常需要 `/v1` | 适合 OpenAI 新版协议 |
| `google-generative-ai` | Gemini (Native) | 通常不需要 `/v1` | 适合 Google 原生协议 |
| `anthropic-messages` | Claude | 通常不需要 `/v1` | 适合 Claude 原生协议 |

### OpenAI 协议示例

```bash
MODEL_ID=gemini-3-flash-preview
BASE_URL=http://localhost:3000/v1
API_KEY=your-api-key
API_PROTOCOL=openai-completions
CONTEXT_WINDOW=1000000
MAX_TOKENS=8192
```

### Claude 协议示例

```bash
MODEL_ID=claude-sonnet-4-5
BASE_URL=http://localhost:3000
API_KEY=your-api-key
API_PROTOCOL=anthropic-messages
CONTEXT_WINDOW=200000
MAX_TOKENS=8192
```

### 默认 Provider 的名称

当你只配置第一组模型环境变量（`MODEL_ID`、`BASE_URL`、`API_KEY`、`API_PROTOCOL`）时，生成到 `openclaw.json` 里的默认 Provider 名称固定为 `default`。

- 第一组模型配置落到 `models.providers.default`
- 未设 `PRIMARY_MODEL` 时，默认主模型引用 `default/<MODEL_ID 的第一个值>`
- 未设 `IMAGE_MODEL_ID` 时，默认图片模型回退到 `default/<MODEL_ID 的第一个值>`

例如 `MODEL_ID=gemini-3-flash-preview` 最终引用 `default/gemini-3-flash-preview`。这也是 `PRIMARY_MODEL` / `IMAGE_MODEL_ID` 常写 `default/...` 的原因。

---

## 多 Provider 配置

如需同时接多个模型提供商，继续配置 `MODEL2_*`、`MODEL3_*` 等扩展项，具体见各环境 `.env.example`。

### 示例：第二个 Provider 作为默认主模型

```bash
MODEL_ID=dashscope/qwen3.5-plus
MODEL2_NAME=aliyun
MODEL2_MODEL_ID=qwen-max,qwen3.5-plus,qwen-vl-max
PRIMARY_MODEL=aliyun/qwen3.5-plus
IMAGE_MODEL_ID=aliyun/qwen-vl-max
```

### 优先级

- 主模型：`PRIMARY_MODEL` → `MODEL_ID`
- 图片模型：`IMAGE_MODEL_ID` → `MODEL_ID`

两者都可写完整引用，例如 `default/dashscope/qwen3.5-plus`、`aliyun/qwen3.5-plus`、`model2/claude-sonnet-4-5`。

---

## Gateway 配置

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `OPENCLAW_GATEWAY_TOKEN` | Gateway 访问令牌 | `123456` |
| `OPENCLAW_GATEWAY_BIND` | 容器内绑定地址 | `lan` |
| `OPENCLAW_GATEWAY_PORT` | Gateway 端口 | `18789` |
| `OPENCLAW_GATEWAY_MODE` | 运行模式 | `local` |
| `OPENCLAW_GATEWAY_ALLOWED_ORIGINS` | 允许的来源域 | 见下两节 |
| `OPENCLAW_GATEWAY_ALLOW_INSECURE_AUTH` | 是否允许不安全认证 | `true` |
| `OPENCLAW_GATEWAY_DANGEROUSLY_DISABLE_DEVICE_AUTH` | 是否禁用设备认证 | `false` |
| `OPENCLAW_GATEWAY_AUTH_MODE` | 认证模式 | `token` |

这些配置最终映射到 [`openclaw.json.example`](../cloud_server/openclaw.json.example) 的 `gateway` 节点。

### 公网服务器 (cloud_server)

- 明文网关端口在 `docker-compose.yml` 中绑 `127.0.0.1`，仅本机可达；对外只走 Caddy 的 HTTPS 443。
- `OPENCLAW_GATEWAY_ALLOWED_ORIGINS` 含 `http://localhost:$OPENCLAW_GATEWAY_PORT` 与 `https://$CADDY_IP`（必须包含浏览器实际访问的 HTTPS 地址，否则跨源请求被网关拦截）。
- 容器内 `OPENCLAW_GATEWAY_BIND=lan`，网关绑到容器内可达接口，Caddy 在 Docker 内部网络反代明文流量。安全由宿主侧 `127.0.0.1:` 映射 + Caddy 443 对外保证。
- 需要明文兜底时走 SSH 隧道：`ssh -L <OPENCLAW_GATEWAY_PORT>:127.0.0.1:<OPENCLAW_GATEWAY_PORT> user@host`。HTTPS 详见 [`caddy-https.md`](caddy-https.md)。

### 本地 (local)

- 明文网关端口绑 `127.0.0.1`，直接 `http://localhost:18789` 访问，无 HTTPS。
- `OPENCLAW_GATEWAY_ALLOWED_ORIGINS` 默认只含 `http://localhost:$OPENCLAW_GATEWAY_PORT`。
- 容器内 `OPENCLAW_GATEWAY_BIND=lan`：网关需绑到容器内可达接口，宿主端口转发才能把流量送进来。安全由宿主侧 `127.0.0.1:` 映射保证，与 `bind` 无关。
- **如需局域网访问**：把 [`local/docker-compose.yml`](../local/docker-compose.yml) 的 `ports` 前缀由 `127.0.0.1:` 改为 `0.0.0.0:`，并在 `OPENCLAW_GATEWAY_ALLOWED_ORIGINS` 补上 `http://<局域网IP>:18789`。明文暴露到网络有被抓包风险，公网请改用 [`cloud_server`](../cloud_server) 的 Caddy HTTPS 方案。

---

## 工作空间与数据目录

### 工作空间

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `OPENCLAW_WORKSPACE_ROOT` | 工作空间根目录，最终路径自动拼接为 `${OPENCLAW_WORKSPACE_ROOT}/workspace`；与 `/home/node/.openclaw` 不一致时启动会创建指向它的软链接 | `/home/node/.openclaw` |

### 数据目录挂载

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `OPENCLAW_DATA_DIR` | 宿主机挂载目录 | `~/.openclaw` |
| `DOCKER_BIND` | 文档参考用，实际端口绑定见各环境 `docker-compose.yml` | cloud `0.0.0.0` / local `127.0.0.1` |
| `OPENCLAW_RUN_USER` | 容器运行用户 UID:GID | `0:0` |

默认设计：

1. 容器先以 root 启动
2. [`init.sh`](../init.sh) 尝试修复挂载目录权限
3. 再以更合适的用户运行 OpenClaw

> 本地 macOS（Colima）下 `OPENCLAW_DATA_DIR=~/.openclaw` 会由 Compose 展开为宿主家目录（如 `/Users/<user>/.openclaw`），Colima virtiofs 把它挂进容器，无需改默认值。

### 权限建议

- 公网服务器默认 `DOCKER_BIND=0.0.0.0`（监听所有网卡，含公网 IP）；配合 Caddy 反代时建议设 `DOCKER_BIND=127.0.0.1` 只在本地访问网关。
- 本地默认 `DOCKER_BIND=127.0.0.1`，仅本机可达。
- 若明确知道宿主机目录 UID/GID，可把 `OPENCLAW_RUN_USER` 改为 `1000:1000`，或设 `TARGET_UID` / `TARGET_GID` 与宿主机用户对齐。SELinux 环境在挂载卷后加 `:z` 或 `:Z`。

---

## IM 渠道多账号 / 多机器人配置

通过环境变量直接支持以下多账号结构：

- 飞书：`FEISHU_ACCOUNTS_JSON`
- 钉钉：`DINGTALK_ACCOUNTS_JSON`
- QQ 机器人：`QQBOT_BOTS_JSON`
- 企业微信：`WECOM_ACCOUNTS_JSON`

这些环境变量把各平台账号信息同步到各自 `channels.*` 节点（飞书→`channels.feishu.accounts`、钉钉→`channels.dingtalk.accounts`、QQ→`channels.qqbot.accounts`、企业微信→`channels.wecom`）。

如需把不同账号路由到不同 OpenClaw Agent，建议直接手动维护宿主机上的 [`openclaw.json`](../cloud_server/openclaw.json.example)，并组合使用：

- `agents.list`：定义多个 OpenClaw Agent
- `bindings`：定义 `channel + accountId -> agentId` 路由规则
- 对应平台下的多账号配置

`bindings` 的典型写法：

```jsonc
"bindings": [
  {
    "type": "route",
    "agentId": "main",
    "match": { "channel": "your-channel", "accountId": "bot_1" }
  },
  {
    "type": "route",
    "agentId": "growth-agent",
    "match": { "channel": "your-channel", "accountId": "bot_2" }
  }
],
```

使用这类路由配置时，建议将 `SYNC_OPENCLAW_CONFIG=false`，避免启动时被环境变量同步覆盖手动维护的其它节点。

---

## 插件与工具配置

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `OPENCLAW_PLUGINS_ENABLED` | 是否启用插件系统 | `true` |
| `OPENCLAW_SANDBOX_MODE` | 沙箱模式，可选 `off`, `non-main`, `all` | `off` |
| `OPENCLAW_SANDBOX_SCOPE` | 沙箱范围，可选 `session`, `agent`, `shared` | `agent` |
| `OPENCLAW_SANDBOX_DOCKER_IMAGE` | 沙箱使用的 Docker 镜像 | `openclaw-sandbox:bookworm-slim` |
| `OPENCLAW_SANDBOX_WORKSPACE_ACCESS` | 工作区访问权限，可选 `none`, `ro`, `rw` | `none` |
| `OPENCLAW_SANDBOX_JOIN_NETWORK` | 是否让沙箱加入主容器网络（解决无外网问题） | `false` |
| `OPENCLAW_SANDBOX_JSON` | 自定义沙箱配置 JSON（全量覆盖/合并） | 留空 |
| `OPENCLAW_TOOLS_JSON` | 自定义工具配置 JSON | 留空 |

### 沙箱配置 (Sandbox)

沙箱用于隔离工具执行（如 Python 代码运行、Shell 执行）。当开启 `non-main` 或 `all` 模式时，Agent 会在隔离的 Docker 容器中运行相关工具。

**网络配置**：`OPENCLAW_SANDBOX_JOIN_NETWORK=true` 时，沙箱自动使用 `docker.network: "container:<gateway-id>"` 加入网关容器网络，并自动开启 `dangerouslyAllowContainerNamespaceJoin: true`，解决部分环境沙箱无法访问外网或主服务的问题。

**工作区访问 (Workspace Access)**：

- `none` (默认): 工具会在 `~/.openclaw/sandboxes` 下看到沙箱工作区。
- `ro`: 在 `/agent` 处挂载只读代理工作区（禁用 write / edit / apply_patch）。
- `rw`: 在 `/workspace` 处挂载代理工作区读写器。

**网络共享 (Network Sharing)**：当沙箱配置使用 `docker.network: "container:<id>"` 时，底层引擎通常要求开启 `dangerouslyAllowContainerNamespaceJoin`：

```bash
OPENCLAW_SANDBOX_JSON='{"docker":{"dangerouslyAllowContainerNamespaceJoin":true}}'
```

**注意**：本镜像运行在 Docker 中，使用 Docker 沙箱需将宿主机 `/var/run/docker.sock` 挂载到容器内，并取消各环境 `docker-compose.yml` 内沙箱挂载的注释。macOS/Colima 下 docker.sock 对 `docker compose` 透明，取消注释即可。

示例配置 (`.env`)：

```bash
OPENCLAW_SANDBOX_MODE=non-main
OPENCLAW_SANDBOX_SCOPE=agent
OPENCLAW_SANDBOX_WORKSPACE_ACCESS=none
OPENCLAW_SANDBOX_DOCKER_IMAGE=openclaw-sandbox:bookworm-slim
```

---

## 与 `openclaw.json` 的关系

运行后生成的实际配置通常包含：`models.providers`、`agents.defaults`、`channels`、`gateway`、`plugins`、`tools`。建议把 [`openclaw.json.example`](../cloud_server/openclaw.json.example) 当作"结构参考"，把各环境 `.env.example` 当作"操作入口"。

---

## 修改环境变量后为什么不生效

容器启动时执行 [`init.sh`](../init.sh)，根据当前环境变量同步模型、渠道、插件、Gateway 等配置到 `openclaw.json`。但以下情况会让你感觉"没生效"：

- 实际启动的不是你刚修改的那份 `.env`
- 容器没有重建或重启
- 你手动维护的 `openclaw.json` 中存在与环境变量冲突的旧字段
- 相关渠道缺少必要环境变量，被启动脚本自动禁用

### 建议排查顺序

1. 确认当前目录 `.env` 已保存。
2. 重建或重启：`docker compose up -d --force-recreate`。
3. 看日志是否出现"同步完成""渠道同步""已禁用渠道"等：`docker compose logs -f openclaw-gateway`。
4. 进容器检查实际配置：
   ```bash
   docker compose exec openclaw-gateway /bin/bash
   su node
   cat ~/.openclaw/openclaw.json
   ```

### 彻底回到"从环境变量重新生成"

删配置文件后重启：

```bash
rm ~/.openclaw/openclaw.json
docker compose restart
```

或删整个数据目录重新生成：

```bash
rm -rf ~/.openclaw
docker compose up -d
```

更完整的故障排查见 [`faq.md`](faq.md)。

## 下一步

- 快速部署与升级：[`quick-start.md`](quick-start.md)
- 故障排查：[`faq.md`](faq.md)
- 公网 HTTPS 详解：[`caddy-https.md`](caddy-https.md)
- AIClient-2-API：[`aiclient-2-api.md`](aiclient-2-api.md)
- 项目总览：[`cloud_server/README.md`](../cloud_server/README.md) / [`local/README.md`](../local/README.md)
