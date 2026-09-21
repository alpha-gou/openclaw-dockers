# 开发者说明

本文面向需要理解镜像构建与启动流程的维护者。

## 仓库关键文件

| 文件 | 说明 |
| --- | --- |
| [`Dockerfile`](../Dockerfile) | Docker 镜像构建定义 |
| [`init.sh`](../init.sh) | 容器初始化与启动脚本 |
| [`docker-compose.yml`](../cloud_server/docker-compose.yml) | 默认部署编排 |
| [`.env.example`](../cloud_server/.env.example) | 环境变量模板 |
| [`openclaw.json.example`](../cloud_server/openclaw.json.example) | 默认配置结构示例 |
| [`README.md`](../cloud_server/README.md) | 项目入口文档 |

## 构建镜像

```bash
docker build -t alpha-gou/openclaw-dockers:latest .
```

## `init.sh` 启动阶段主要职责

[`init.sh`](../init.sh) 在容器启动时主要负责：

1. 创建必要目录
2. 根据环境变量动态生成配置文件（若不存在）
3. 修复或校验挂载目录权限
4. 启动 OpenClaw Gateway

## `openclaw.json` 的生成逻辑

首次启动时，如果 `/home/node/.openclaw/openclaw.json` 不存在，初始化脚本会基于环境变量生成配置，主要包括：

- 模型配置
- 通道配置
- Gateway 配置
- 插件启用配置
- 工具配置

如果宿主机已经挂载了自己的 `openclaw.json`，则通常会跳过自动生成过程。

## 镜像中安装的主要组件

当前镜像内主要包含以下几类组件（2026-09 精简后）：

- 全局 Node.js 工具：`openclaw`、`clawhub`
- 浏览器与系统依赖：`chromium`（`openclaw.json` 中 `browser.executablePath` 指向）、`ffmpeg`（agent-reach 的 yt-dlp 需要）、`jq`、`gosu`、`python3` 等
- Linuxbrew 环境：默认注释未安装（见 Dockerfile 内说明）
- 预装 / 预拉取的 IM 相关扩展与插件：
  - `qqbot`（默认安装并固化为 seed）
  - `napcat` / `dingtalk` / `wecom`：默认注释，按需启用
- 飞书相关能力以镜像内预置配置和后续安装步骤为主，并不是直接全局安装 `@openclaw/feishu`
- 已移除的历史组件：`opencode-ai`、`playwright`、`playwright-extra`、`puppeteer-extra-plugin-stealth`、`@steipete/bird`（上游已弃用）、`@tobilu/qmd`、`bun`、`uv`、`websockify`、`socat`、`tini`、`build-essential`、`docker.io`（均无实际引用，详见 Dockerfile 注释）

更准确的安装来源、安装方式与版本，以 [`Dockerfile`](../Dockerfile) 为准。

## 默认启动命令

容器最终通过以下方式启动：

```bash
openclaw gateway --verbose
```

入口点由 [`Dockerfile`](../Dockerfile) 中的 `ENTRYPOINT` 配合 [`init.sh`](../init.sh) 完成。

## 文档维护建议

当你修改以下文件时，建议同步检查文档是否需要更新：

- [`.env.example`](../cloud_server/.env.example)
- [`docker-compose.yml`](../cloud_server/docker-compose.yml)
- [`Dockerfile`](../Dockerfile)
- [`openclaw.json.example`](../cloud_server/openclaw.json.example)
- [`init.sh`](../init.sh)
