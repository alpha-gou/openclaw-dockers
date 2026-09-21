# openclaw-dockers

> alpha-gou 维护版

集成多种环境下 OpenClaw 命令行 AI 助手的 Docker 部署方案：把 OpenClaw 打包为可直接运行的 Docker 服务，提供 Web 控制台与多种 IM 渠道机器人（Telegram / 飞书 / 钉钉 / 企业微信 / QQ / NapCat）。

## 两套部署环境

仓库按「每种环境一个子目录」组织，共享同一套 OpenClaw 运行时镜像，仅编排与访问方式不同：

| 环境 | 目录 | 定位 | 访问方式 |
| --- | --- | --- | --- |
| 公网服务器 | [`cloud_server/`](cloud_server/README.md) | 有公网 IP 的服务器（如阿里云 ECS） | Caddy HTTPS 443，明文端口仅绑 loopback |
| 本地单机 | [`local/`](local/README.md) | 本机 / 单机 | 明文 `http://localhost:18789` 直连，无 HTTPS |

- 公网服务器部署见 [`cloud_server/README.md`](cloud_server/README.md)。
- 本地部署见 [`local/README.md`](local/README.md)；macOS（Apple Silicon）从零装 Docker 见 [`docs/macos-colima-setup.md`](docs/macos-colima-setup.md)。

## 运行时镜像

两环境共用镜像 `alpha-gou/openclaw-dockers`，由 [`Dockerfile`](Dockerfile) 构建。

> ⚠️ **镜像尚未发布到 Docker Hub**，`docker compose pull` 暂不可用（未实现）。请先自行构建：

```bash
# 在仓库根目录执行
docker build -t alpha-gou/openclaw-dockers:latest .

# 指定 OpenClaw 版本
docker build --build-arg OPENCLAW_VERSION=2026.6.1 -t alpha-gou/openclaw-dockers:latest .
```

> 自行构建时镜像 tag 必须与各环境 `.env` 中 `OPENCLAW_IMAGE` 一致，否则 compose 会去拉取远端镜像而非使用本地构建结果。

## openclaw doctor 操作指南

OpenClaw 更新频繁（状态库/配置 schema 迁移时有发生），`openclaw doctor` 是升级与修复的**常规操作**：负责健康检查、配置迁移、状态修复与插件兼容性探测。**建议每次升级镜像后都跑一次 `doctor --fix`。**

### 何时需要跑

- 升级镜像 / OpenClaw 版本后（必做）
- gateway 日志出现下列任一告警：
  - `[state-migrations] Startup migration warnings; continuing with degraded state`
  - `agent database ... uses schema version N ... run openclaw doctor --fix`
  - `Sessions remain unavailable`
- CLI 报错末尾提示 `Try: openclaw doctor`
- 渠道 / 插件 / 配置行为异常且原因不明

### 标准操作流程（两环境通用）

在 `cloud_server/` 或 `local/` 目录下执行。项目提供 `openclaw-installer` 工具容器（`tools` profile，见各环境 docker-compose.yml），与 gateway 共享同一状态卷，保证 doctor 操作的是同一份 state/config：

```bash
# 0. 停 gateway（修复期间不能有活跃写入者）
docker compose stop openclaw-gateway

# 1. 备份状态目录（宿主机路径 = 各环境 .env 中 OPENCLAW_DATA_DIR 指向的目录）
cp -a <OPENCLAW_DATA_DIR> <OPENCLAW_DATA_DIR>-backup-$(date +%Y%m%d)

# 2. 修复式迁移（升级后的主命令）
docker compose --profile tools run --rm --entrypoint "" openclaw-installer \
  openclaw doctor --fix --non-interactive

# 3. 重启并验证
docker compose up -d openclaw-gateway
docker compose logs -f openclaw-gateway
#    确认：无 state-migrations 告警、出现 [gateway] ready
```

也可以先 `docker compose --profile tools up -d openclaw-installer` 再 `docker compose exec openclaw-installer openclaw doctor ...`（exec 不经过 entrypoint，无参数解析问题），修完 `stop` 掉即可。

### 常用命令速查

| 目的 | 命令 | 说明 |
| --- | --- | --- |
| 修复 + 迁移（升级主命令） | `openclaw doctor --fix --non-interactive` | 无提示地应用全部受支持的迁移与修复 |
| 只读诊断（绝不写盘） | `openclaw doctor --lint --json` | 人工检查或 CI 门禁；退出码按严重度阈值 |
| 升级后插件兼容性探测 | `openclaw doctor --post-upgrade` | 存在 error 级发现时退出码 1 |
| 深度扫描 | `openclaw doctor --deep` | 额外扫描系统里的其他 gateway 安装 |
| 共享状态库压缩 | `openclaw doctor --state-sqlite compact` | checkpoint + compact + 校验 |
| 会话库维护 | `openclaw doctor --session-sqlite <inspect\|dry-run\|import\|validate\|compact\|recover\|restore>` | 会话历史检查、导入与恢复 |

**注意事项**（来自官方文档，容易踩坑）：

- **`--non-interactive` 只是不弹提示，不是只读**——裸 `openclaw doctor` 也可能自动拷贝 legacy 配置、迁移状态。纯诊断一律用 `--lint` 或 `--json`。
- `--fix` 会停止受管的 gateway 再修复、重启、验证；Docker 部署下先手动 `stop` 容器最干净。
- 运行 doctor 的 openclaw 版本不能旧于写入状态的版本，否则会拒绝处理更新的 schema（本项目 installer 与 gateway 同镜像，天然满足）。
- doctor 会跟随配置里显式写死的 workspace/store 路径；在状态副本上演练修复时，注意它可能改到原始目录。

### 实战案例：2026.9.5 升级失败修复（2026-09 实录）

**症状**：升级后 gateway 报两个 agent 数据库停在 `schema version 19`、sessions 不可用；且 doctor 在预检阶段崩溃：`Error: Skill name must contain at least one letter or number`，反复重跑 `--fix` 均崩在同一处。

**根因**：旧版 Skill Workshop 把技能的**纯中文显示名**（如 `文风学习`）直接写进了提案记录的 `target.skillKey`。新版迁移会把 skillKey 规范化为 ASCII slug（只保留 `a-z0-9-`），纯中文名规范化后为空串 → 抛错并卡死整条迁移链。**不清掉畸形记录，doctor 永远跑不完。**

**修复步骤**（状态目录已挂载到宿主机，可直接操作；下列路径中 `<state>` = `OPENCLAW_DATA_DIR`，对应容器内 `/home/node/.openclaw`）：

```bash
# 1. 停 gateway + 备份（同上"标准操作流程"第 0/1 步）

# 2. 找出畸形提案（skillKey 不含任何字母/数字即肇事者）
python3 - <<'EOF'
import sqlite3, json, re
norm = lambda s: re.sub(r'[^a-z0-9-]+','',re.sub(r'[\s_/]+','-',(s or '').strip().lower())).strip('-')
db = sqlite3.connect('<state>/state/openclaw.sqlite')
for (rj, owner) in db.execute("SELECT record_json, owner_agent_id FROM skill_workshop_proposals"):
    r = json.loads(rj); k = r.get('target', {}).get('skillKey', '')
    print(('BAD:' if not norm(k) else 'ok :'), r['id'], repr(k), 'owner=', owner)
EOF

# 3. 把 BAD 记录的 target.skillKey 改成真实技能目录名（如 workspace 下 skills/ 里
#    对应的 style-learning），用 UPDATE skill_workshop_proposals SET record_json=... 写回；
#    若不需要这些历史提案，直接 DELETE 对应行即可（技能本体在 workspace，不受影响）。

# 4. 重跑 doctor --fix --non-interactive，
#    确认输出 "Upgraded agent database schema ... v19 -> v21"，再重启 gateway。
```

> 偷懒方案：整个移走 `<state>/skill-workshop` 目录并清空 `skill_workshop_proposals` 表，doctor 会直接跳过这一步迁移（提案仅是"待审核的技能更新建议"，全部丢弃不影响已有技能）。

### 官方文档

- Doctor CLI 总览（含 7 个专题子页）：<https://docs.openclaw.ai/cli/doctor>
- 运行方式、姿态与完整参数表：<https://docs.openclaw.ai/cli/doctor/running>
- 检查项明细（gateway 视角）：<https://docs.openclaw.ai/gateway/doctor>

## 目录结构

```
openclaw-dockers/
├── Dockerfile           # 共享运行时镜像构建定义（两环境共用）
├── init.sh              # 共享运行时启动脚本（内置于镜像）
├── cloud_server/        # 公网服务器编排
│   ├── docker-compose.yml
│   ├── .env.example / .env.minimal
│   ├── caddy/           # HTTPS 自签证书工具
│   └── README.md
├── local/              # 本地单机编排（复用同一镜像）
│   ├── docker-compose.yml
│   ├── .env.example / .env.minimal
│   └── README.md
└── docs/               # 统一文档
    ├── quick-start.md
    ├── configuration.md
    ├── faq.md
    ├── macos-colima-setup.md
    ├── caddy-https.md
    ├── aiclient-2-api.md
    ├── advanced.md
    ├── developer-notes.md
    └── wechat.md
```

## 文档

- [快速开始](docs/quick-start.md) — 两环境的部署、构建、升级、进入容器
- [配置指南](docs/configuration.md) — 模型、Gateway、渠道、沙箱
- [故障排查](docs/faq.md)
- [macOS Colima 环境准备](docs/macos-colima-setup.md) — Apple Silicon 从零装 Docker
- [公网 HTTPS 详解](docs/caddy-https.md)
- [AIClient-2-API 对接](docs/aiclient-2-api.md)
- [高级运行方式](docs/advanced.md)
- [开发者说明](docs/developer-notes.md)
- [微信相关](docs/wechat.md)

## License

见 [LICENSE](LICENSE)。
