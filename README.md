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
