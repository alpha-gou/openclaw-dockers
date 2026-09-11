# 通过 Caddy 为 OpenClaw 网关提供 HTTPS 访问

## 背景

OpenClaw 网关（`openclaw-gateway`）默认监听 `OPENCLAW_GATEWAY_PORT`（默认 `18789`）端口，对外提供的是**明文 HTTP** 页面和服务。无论是公网还是内网，HTTP 流量都可能被中间人工具（Wireshark、tcpdump 等）窃听——网关鉴权用的 `OPENCLAW_GATEWAY_TOKEN`、控制台会话、对话内容都会以明文暴露，尤其对**公网服务器（如阿里云 ECS）**，暴露在公网上的明文接口风险更高。

本方案在同一个 `docker-compose.yml` 中增加一个 **Caddy** 反向代理容器：

- Caddy 对外只暴露 **HTTPS 443**，用**手动生成的自签证书**终止 TLS；
- 加密后的请求由 Caddy 转发给 OpenClaw 的明文 HTTP（网关端口，仅存在于 Docker 内部网络）；
- **OpenClaw 侧零改动**，依然监听明文 HTTP，只是不再对网络层可达。

这样访问者只能看到加密流量，无法再直接抓取明文网关端口。

## 架构

```
客户端 ──HTTPS:443（自签证书）──►  Caddy  ──HTTP:网关端口（Docker 内部网络）──► openclaw-gateway
                                  │ reverse_proxy openclaw-gateway:{$OPENCLAW_GATEWAY_PORT:18789}
                                  └ 对外仅开放 443，80 不映射
```

| 端口 | 宿主绑定 | 说明 |
| --- | --- | --- |
| `443` | `0.0.0.0` | Caddy HTTPS 入口，对外加密访问（公网场景需在云安全组放行） |
| `80` | 不映射 | 强制只走 HTTPS，避免明文入口 |
| `OPENCLAW_GATEWAY_PORT`（默认 18789） | `127.0.0.1` | OpenClaw 明文网关，仅宿主机 loopback 可达 |

## 为什么是手动自签证书 + `:443`

两个坑决定了当前方案（避免再踩）：

1. **不能用 Caddy 内置的 `tls internal`**：它只为内网/本地地址（localhost、私有 IP 段）签发，**公网 IP 不在白名单**，握手会报 `tlsv1 alert internal error`。所以公网 IP 必须用 `caddy/generate-cert.sh` 手动生成自签证书（SAN 含该 IP）。
2. **Caddyfile 用 `:443` 而非 `https://<IP>:443`**：按 IP 限定 host 时，curl/浏览器对 IP 的 SNI 行为与 `openssl s_client` 不同，握手时 SNI 匹配不上会报 `ERR_SSL_PROTOCOL_ERROR` / `internal error`。`:443` 不限定 host，Caddy 对任意 SNI 都用同一张证书，单服务场景最稳。

## 公网 IP 与内网 IP：`CADDY_IP` 填哪个

`CADDY_IP` 用于 `caddy/generate-cert.sh` 生成证书时的 SAN，**必须等于客户端浏览器地址栏实际输入的地址**：

- **公网服务器（阿里云 ECS 等）→ 填公网 IP**。无论公网 IP 是直接绑 ECS，还是由云端 SLB/NAT 做 DNAT 转发到内网 IP，证书 SAN 填公网 IP 即可对应 `https://公网IP` 的访问。
- **仅内网部署 → 填内网 IP**。

## 涉及的文件

| 文件 | 改动 |
| --- | --- |
| [`caddy/Caddyfile`](../cloud_server/caddy/Caddyfile) | `:443` + `tls` 指定手动证书 + 反代到 `openclaw-gateway:{$OPENCLAW_GATEWAY_PORT:18789}` |
| [`caddy/generate-cert.sh`](../cloud_server/caddy/generate-cert.sh) | 新增：按 `CADDY_IP` 生成自签证书（SAN 含 IP），输出 `caddy.crt` / `caddy.key` |
| [`docker-compose.yml`](../cloud_server/docker-compose.yml) | 明文网关端口改为绑 `127.0.0.1`；新增 `caddy` service（只暴露 443，挂载证书） |
| [`.env.example`](../cloud_server/.env.example) | 新增 `CADDY_IP` / `CADDY_PORT`；`OPENCLAW_GATEWAY_ALLOWED_ORIGINS` 补充 `https://$CADDY_IP` |
| [`.gitignore`](../.gitignore) | 忽略 `caddy_data/`、`caddy_config/`、`caddy/caddy.crt`、`caddy/caddy.key` |

## 首次部署

### 1. 配置环境变量

在项目根目录 `cp .env.example .env` 后，确认以下配置：

```bash
# —— Caddy HTTPS 反向代理 ——
# 对外固定 IP：公网服务器填公网 IP，仅内网访问则填内网 IP。
# 用于生成自签证书的 SAN，必须与客户端实际访问时输入的地址一致。
CADDY_IP=1.2.3.4
# 宿主机 HTTPS 端口（默认 443，一般不用改）
CADDY_PORT=443
```

同时确认网关的 Origin 白名单里**包含你的 HTTPS 访问地址**，否则浏览器控制台请求可能被网关拦截：

```bash
OPENCLAW_GATEWAY_ALLOWED_ORIGINS=http://localhost:18789,https://1.2.3.4
```

### 2. 生成自签证书

**公网 IP 必须手动生成**（`tls internal` 不支持公网 IP）：

```bash
sh caddy/generate-cert.sh 1.2.3.4
```

生成 `caddy/caddy.crt` 与 `caddy/caddy.key`（已加入 `.gitignore`，勿提交）。

> 若报错 `Is a directory`：Docker 之前已把同名路径建成了空目录，先删掉再生成：
> ```bash
> rm -rf caddy/caddy.crt caddy/caddy.key
> sh caddy/generate-cert.sh 1.2.3.4
> ```

### 3. 放行端口（公网服务器必做）

在云厂商安全组（如阿里云）放行入方向 TCP `443`；确认网关端口未对外开放。

### 4. 启动服务

```bash
docker compose up -d
```

## 安装证书（消除浏览器警告）

### 为什么必须装证书

浏览器**永远不会主动信任一段未知的自签证书**——这是 TLS 安全模型的基本设计（否则任何人都能伪造证书冒充你的服务器）。

- 不安装时：每次访问 `https://IP` 都会弹「您的连接不是私密连接 / `NET::ERR_CERT_AUTHORITY_INVALID`」，需要手动点「高级 → 继续前往」。
- 安装后：信任这张证书，警告**彻底消失**，一劳永逸。

### 各平台安装 `caddy.crt`

把项目里的 `caddy/caddy.crt` 装到客户端的「**受信任的根证书颁发机构**」（自签证书作为信任锚）：

- **macOS**：双击 `caddy.crt` 或用「钥匙串访问」打开 → 选「系统」钥匙串 → 双击该证书 →「信任」展开 →「使用此证书时」选「始终信任」→ 输入密码确认。
- **Windows**：双击 `caddy.crt` →「安装证书」→ 存储位置选「本地计算机」→「将所有证书都放入下列存储」→「浏览」选「**受信任的根证书颁发机构**」→ 完成。
- **Linux**：
  - Chrome/Chromium：设置 → 隐私和安全 → 安全 → 管理证书 → 证书颁发机构 → 导入。
  - Firefox：设置 → 隐私与安全 → 证书 → 查看证书 → 证书颁发机构 → 导入 → 勾选「信任由此证书颁发机构来标识网站」。
  - 系统级（Ubuntu/Debian）：`sudo cp caddy/caddy.crt /usr/local/share/ca-certificates/openclaw.crt && sudo update-ca-certificates`。
- **iOS**：将 `caddy.crt` 发送到设备打开 → 安装描述文件 → 设置 → 通用 → 关于本机 → 证书信任设置 → 打开该证书的「完全信任」开关。
- **Android**：设置 → 安全 → 加密与凭据 → 安装证书 → CA 证书 → 选择 `caddy.crt`。

> ⚠️ **证书文件 = 信任你服务器的钥匙，要像私钥一样保管**。只应把它安装到**你亲自管控、愿意信任的客户端**；**不要**把它作为公开文件分发给陌生公网用户，也不要提交到公开仓库。一旦怀疑泄露，重新生成证书并让受影响客户端重新安装。

## 使用方法

### 正常 HTTPS 访问

```text
https://<CADDY_IP>
```

- 浏览器地址栏**必须带 `https://`**；如果访问 `http://<CADDY_IP>`，因为 80 端口不映射，会直接无法连接（有意为之，关闭了明文入口）。
- 首次访问弹自签证书警告 → 点「高级 → 继续前往」临时放行，或装 `caddy.crt` 永久消除。
- 输入正确的 `OPENCLAW_GATEWAY_TOKEN` 即可正常使用网关控制台。

### SSH 隧道明文兜底（可选）

明文网关端口已绑到宿主机 `127.0.0.1`，仅本机进程可达。若某工具需要走原始明文接口，可在宿主机上建立隧道：

```bash
ssh -L <OPENCLAW_GATEWAY_PORT>:127.0.0.1:<OPENCLAW_GATEWAY_PORT> user@<宿主>
# 然后通过本机 http://127.0.0.1:<OPENCLAW_GATEWAY_PORT> 访问明文网关
```

## 验证

```bash
# 1. 服务都在运行
docker compose ps

# 2. HTTPS 可达（-k 临时忽略本地未装证书的警告）
curl -vk https://<CADDY_IP>/

# 3. 用 openssl 握手 + 发 HTTP 请求，确认能拿到控制台页面（最可靠）
printf 'GET / HTTP/1.1\r\nHost: <CADDY_IP>\r\nConnection: close\r\n\r\n' \
  | openssl s_client -connect <CADDY_IP>:443 -servername <CADDY_IP> -quiet 2>/dev/null | head -5

# 4. 证书文件存在
ls -l caddy/caddy.crt caddy/caddy.key

# 5. 明文网关端口仅绑 loopback
lsof -iTCP:<OPENCLAW_GATEWAY_PORT> -sTCP:LISTEN   # 宿主上应显示 127.0.0.1
```

## 常见问题与排障

**Q1：浏览器报 `ERR_SSL_PROTOCOL_ERROR` / curl 报 `tlsv1 alert internal error`？**
确认 Caddyfile 用的是 `:443`（不是 `https://<IP>:443`），且证书是 `caddy/generate-cert.sh` 生成的手动证书（不是 `tls internal`）。公网 IP 用 `tls internal` 或按 IP 限定 host 都会触发此错。改完后 `docker compose up -d --force-recreate caddy`。

**Q2：原来 `http://IP:网关端口` 的网络访问连不上了？**
这是预期行为——明文端口已不再对网络暴露。请改用 `https://IP`。需要明文时走上面的 SSH 隧道。

**Q3：换了 IP 后证书还匹配吗？**
需要重新生成证书：`sh caddy/generate-cert.sh <新IP>`，再 `docker compose restart caddy`。同时更新 `OPENCLAW_GATEWAY_ALLOWED_ORIGINS`。客户端已安装的旧 `caddy.crt` 需替换为新证书（因为新证书 SAN 变了）。

**Q4：浏览器反复弹警告？**
本机没装 `caddy.crt`，或装的不是当前这张证书。重新安装 `caddy/caddy.crt` 到「受信任的根证书颁发机构」。

**Q5：国内网络拉取 `caddy:2-alpine` 镜像超时？**
将服务镜像改为国内镜像前缀，例如 `docker.m.daocloud.io/library/caddy:2-alpine`。

**Q6：控制台能进但部分请求失败？**
检查 `OPENCLAW_GATEWAY_ALLOWED_ORIGINS` 是否包含当前的 `https://<CADDY_IP>` Origin，缺少会导致网关拒绝跨源请求。

**Q7：Caddy 和网关重启后证书会变吗？**
不会。证书是 `caddy/caddy.crt` 文件（手动生成，独立于容器），重启/重建容器都不影响；只有重新跑 `generate-cert.sh` 才会换。

**Q8：这个方案适合推向公网陌生用户吗？**
自签证书适合**你自己或团队成员**访问。向陌生公网用户开放时，自签证书无法也不应公开分发。理想做法是给这台服务器配一个**域名**，改用 Let's Encrypt 自动申请浏览器原生信任的证书——用户无需安装任何证书。见下文。

## 升级到域名 + 公开证书（推荐做公网）

如果你能拿到一个域名（例如 `claw.example.com`，甚至 `*.example.com` 泛解析到本机），Caddy 可改为自动申请受信任证书：

```caddyfile
# caddy/Caddyfile
{
  email 你的邮箱   # 用于 Let's Encrypt 通知
}

https://claw.example.com {
  tls {
    dns <提供商> { token ... }   # 可选：用 DNS 挑战以支持裸 IP/无公网回连
  }
  reverse_proxy openclaw-gateway:{$OPENCLAW_GATEWAY_PORT:18789}
}
```

> 域名场景可以用 `https://域名` 限定 host（域名 SNI 匹配正常，不像 IP 有 SNI 问题）。

改用域名后：浏览器原生信任证书，客户端**不再需要安装任何证书**，同时可把 `OPENCLAW_GATEWAY_ALLOWED_ORIGINS` 设为 `https://claw.example.com`。这是公网开放的推荐形态。

> 说明：Let's Encrypt 的 HTTP-01/TLS-ALPN 挑战需要 80/443 能对外回连；若不想开放 80，或需要裸 IP/内网续期，建议给域名配 DNS 挑战（如阿里云 DNS 插件）。

## 卸载 / 回退

```bash
docker compose stop caddy
docker compose rm caddy
```

如需彻底恢复明文可达，还原 `docker-compose.yml` 中 `openclaw-gateway` 的 `ports` 行（去掉 `127.0.0.1:` 前缀），并可删除 `caddy/` 与 `caddy_data/`、`caddy_config/`。

## 相关文档

- [快速开始](quick-start.md)
- [配置指南](configuration.md)
- [故障排查](faq.md)