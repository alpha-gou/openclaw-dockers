# macOS (Apple Silicon) Colima 环境准备

本文面向 Apple Silicon Mac（M1/M2/M3/M4）用户，从零搭一套"服务器般"的 Docker 环境，作为 [OpenClaw 本地部署](../local/README.md) 的**前置依赖**。完成本文后，回到 [快速开始](quick-start.md) 用 `docker compose` 部署 OpenClaw 即可。

## 为什么选 Colima

- 轻量 Linux VM 替代 Docker Desktop，无 GUI 负担、无商业授权问题；`docker` 命令随时可用，体验与 Linux 服务器一致。
- Apple Silicon 上用 `vz`（Virtualization.Framework）+ virtiofs，宿主目录挂载性能接近原生——OpenClaw 会把宿主 `~/.openclaw` 挂进容器作为数据目录，挂载性能直接影响读写体验。
- OpenClaw 镜像是多架构（`linux/arm64` + `linux/amd64`），Apple Silicon 原生跑 arm64，**无需 Rosetta**。

整个流程分四步：安装 → 启动 VM → 验证 → 配置自动启停。

## 系统要求核对

- Apple Silicon Mac（M1/M2/M3/M4）
- macOS 13 (Ventura) 或更新版本
- 已安装 Homebrew

如果 Homebrew 还没装：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

> 💡 如果需要跑 x86/amd64 镜像（OpenClaw 主镜像不需要，但某些沙箱/工具镜像可能只有 amd64 版本），建议先装 Rosetta 2：`softwareupdate --install-rosetta`

## 第一步：安装 Colima 和 Docker CLI

Colima 只负责跑 Linux VM，Docker 命令行工具需要单独装：

```bash
brew install colima docker docker-compose docker-buildx
```

然后建立 Compose 和 Buildx 插件软链，让 `docker compose` 和 `docker buildx` 子命令可用：

```bash
mkdir -p ~/.docker/cli-plugins
ln -sfn $(brew --prefix)/opt/docker-compose/bin/docker-compose ~/.docker/cli-plugins/docker-compose
ln -sfn $(brew --prefix)/opt/docker-buildx/bin/docker-buildx ~/.docker/cli-plugins/docker-buildx
```

验证安装：

```bash
colima version
docker --version
```

能看到版本号就说明装好了。

## 第二步：启动 Colima（关键步骤）

### 推荐配置（大多数开发者）

```bash
colima start --cpu 4 --memory 8 --disk 100 --vm-type vz --mount-type virtiofs --runtime docker
```

参数含义：

- `--cpu 4 --memory 8 --disk 100`：分配 4 核 CPU、8GB 内存、100GB 磁盘
- `--vm-type vz`：使用 Apple 的 Virtualization.Framework，macOS 13+ 且 Apple Silicon 专用，性能明显优于默认 QEMU，自动启用 virtiofs 挂载，文件读写接近原生速度

> **为什么不直接 `colima start`？** 默认 `colima start` 用 QEMU + SSHFS/9p 挂载宿主目录。OpenClaw 的状态库（`~/.openclaw/state/openclaw.sqlite`）是 SQLite，SSHFS 无法安全协调跨挂载的 SQLite 写入，openclaw 会报 `is on SSHFS ... refusing to open the database` 拒绝打开状态库（日志里会出现这行，导致 state 无法持久化）。`--vm-type vz` 用 Apple Virtualization.Framework，自动启用 **virtiofs**——支持正确的文件锁，SQLite 可安全写入；同时性能也明显优于 QEMU。所以务必带 `--vm-type vz`。

### 需要跑 x86/amd64 镜像的场景

OpenClaw 主镜像本身是 arm64 原生，不需要 Rosetta。但若你启用了沙箱、或某些工具镜像只有 amd64 版本，加 `--vz-rosetta`：

```bash
colima start --cpu 4 --memory 8 --disk 100 --vm-type vz --vz-rosetta
```

Rosetta 2 转译能让 amd64 容器在 Apple Silicon 上接近原生速度运行。

### 想要一个独立的 x86_64 环境

```bash
colima start x86-env --arch x86_64 --cpu 4 --memory 8 --disk 100 --vm-type vz --vz-rosetta
```

这会创建一个名为 `x86-env` 的独立实例，与默认的 arm64 实例并存，用 `colima start x86-env` / `colima stop x86-env` 切换。

### 资源分配建议

| 你的 Mac 内存 | 推荐 `--memory` | 推荐 `--cpu` |
| --- | --- | --- |
| 16 GB | 4-6 GB | 4 |
| 32 GB | 8-12 GB | 4-6 |
| 64 GB+ | 12-16 GB | 6-8 |

> ⚠️ 内存不要超过物理内存的 70%，留足 macOS 自身开销。OpenClaw 跑浏览器自动化（内置 Chromium）与多 Agent 并发时较吃内存，建议至少 8GB。

首次启动会花 20-60 秒创建 VM，日志类似：

```text
INFO[0000] starting colima
INFO[0000] runtime: docker
INFO[0000] preparing network ... context=vm
INFO[0002] starting ... context=vm
INFO[0035] provisioning ... context=docker
INFO[0037] done
```

## 第三步：验证 Docker 是否可用

```bash
docker run --rm hello-world
```

看到 "Hello from Docker!" 就成功了。再确认 context 已切到 colima：

```bash
docker context list
```

输出中 `colima` 前面有 `*` 号，说明当前 docker 命令已经指向 Colima 的守护进程，Colima 会自动完成这个切换。

跑个实际例子验证挂载和端口映射（OpenClaw 也依赖这两项）：

```bash
docker run -d --name nginx-test -p 8080:80 nginx
curl http://localhost:8080
docker stop nginx-test && docker rm nginx-test
```

> ✅ 验证通过后，回到 [快速开始](quick-start.md) 部署 OpenClaw：本质就是把上例换成 `docker compose up -d`，网关端口 `18789` 同样以 `127.0.0.1` 暴露到本机。

## 第四步：配置"开终端即用"（核心诉求）

光是 `colima start` 一次还不够"像服务器"。把下面这个函数加到 `~/.zshrc`（Apple Silicon Mac 默认 shell 是 zsh）：

```bash
docker() {
  if ! command -v colima &> /dev/null; then
    command docker "$@"
    return
  fi
  if ! colima status &> /dev/null; then
    echo "🚀 Colima 未运行，正在启动..."
    colima start --cpu 4 --memory 8 --disk 100 --vm-type vz
  fi
  command docker "$@"
}
```

重新加载配置：

```bash
source ~/.zshrc
```

从此以后，任何时候在终端敲 `docker` 命令，如果 Colima 没运行就会自动拉起 VM，完全不需要打开任何 GUI 客户端，体验上和 Linux 服务器一模一样。

> 📌 如果想让 Colima 在 Mac 登录时自动启动（进一步接近服务器体验），可以把 `colima start --vm-type vz` 加到「系统设置 → 用户与群组 → 登录项」，或者用 launchd 做一个 plist。但对大多数人来说，上面的 shell 函数已经够用。

## 日常使用命令速查

```bash
colima start                    # 启动（默认实例）
colima stop                     # 停止
colima restart                  # 重启
colima status                   # 查看运行状态
colima list                     # 列出所有实例
colima ssh                      # SSH 进 VM 内部排查问题
colima delete                   # 删除 VM（慎用，会清掉所有容器和数据）
colima start --edit             # 交互式编辑配置文件
```

查看详细日志（排查启动失败时很有用）：

```bash
colima logs --follow
```

## 进阶：持久化配置

如果不想每次 `colima start` 都带一长串参数，可以编辑配置文件 `~/.colima/default/colima.yaml`：

```yaml
cpu: 4
memory: 8
disk: 100
vmType: vz
rosetta: true        # 需要 Rosetta 转译时开启
runtime: docker
docker:
  features:
    buildkit: true
```

改完配置需要重启生效：

```bash
colima stop && colima start
```

> 💡 配置文件中 `vmType` 和 `arch` 在 VM 创建后不可更改，要换必须 `colima delete` 后重建。

## 常见问题处理

**1. `docker` 命令报 `Cannot connect to the Docker daemon`**
VM 没起来，执行 `colima start`，或检查 `colima status`。

**2. 拉取镜像时报架构不匹配**
镜像是 amd64 但 VM 是 arm64，两种解法：

- 单次运行指定平台：`docker run --platform linux/amd64 <image>`
- 或者重建 VM 时加 `--vz-rosetta`（推荐）

> OpenClaw 主镜像 `alpha-gou/openclaw-dockers` 是多架构，arm64 Mac 会自动拉 arm64 版，不会遇到此问题；只有当你额外跑 amd64-only 的沙箱/工具镜像时才需要关注。

**3. 挂载目录性能慢**
确保用了 `--vm-type vz`（自动启用 virtiofs）。如果是 QEMU 实例，挂载性能会差很多，建议删掉重建为 vz 类型。OpenClaw 把 `~/.openclaw`（含工作空间、配置、向量内存）挂进容器，vz + virtiofs 下读写接近原生。

**4. 升级 Colima**

```bash
brew upgrade colima
colima stop && colima start
```

**5. 之前装过 Docker Desktop 导致 credential helper 报错**
编辑 `~/.docker/config.json`，把 `"credsStore": "desktop"` 改成 `"credsStore": "osxkeychain"`，或者安装 docker-credential-helper：`brew install docker-credential-helper`。

**6. OpenClaw 沙箱在 Colima 里报找不到 Docker？**
沙箱功能需要把宿主 docker.sock 挂进 OpenClaw 容器。Colima 的 docker.sock 路径对 `docker compose` 是透明的——在 [`docker-compose.yml`](../local/docker-compose.yml) 里取消 `- /var/run/docker.sock:/var/run/docker.sock` 的注释即可，Colima 会把 VM 内的 socket 正确映射进来。详见 [配置指南 · 沙箱配置](configuration.md#沙箱配置-sandbox)。

**7. 合盖 / 系统睡眠后容器会被挂起吗？如何保持常驻？**

先分清三种状态：**锁屏**与**屏幕关闭**不会影响容器（系统仍在运行，VM 照跑）；只有**系统睡眠 / 待机**会挂起 Colima 的 Linux VM，所有容器随之暂停（不是崩溃，而是冻结）。此时网络监听中断、在途请求 / IM webhook 丢失；唤醒后 VM 与容器自动恢复（`restart: unless-stopped` 已设）。睡眠期间 OpenClaw 收不到 IM 消息、长任务可能超时，但不会损坏数据。

让 Mac 像 server 一样不睡（**均建议接电源**，电池模式 macOS 会强制省电，`caffeinate -s` 也只在 AC 电源下生效）：

```bash
# 最简：阻止系统睡眠，Ctrl-C 释放
caffeinate -s

# 或挂到 colima 进程：容器在跑就不睡
caffeinate -s -w $(pgrep -f colima)

# 永久：接电源时空闲不睡
sudo pmset -c sleep 0
pmset -g          # 查看当前设置
```

- GUI：系统设置 → 显示器 → 高级 → 打开「电源适配器下，显示器关闭时阻止自动进入睡眠」。
- **合盖也不睡**：默认合盖即睡。用 `sudo pmset -a disablesleep 1`（完全禁止睡眠，含合盖，注意散热），或装 Amphetamine（App Store 免费）开启「合盖保持唤醒」。
- 保持接电源：电池模式上面设置可能被 macOS 覆盖进入低功耗。

## 总结：完整的最小操作序列

如果你只想复制粘贴一条龙跑完，按顺序执行：

```bash
# 1. 安装
brew install colima docker docker-compose docker-buildx
mkdir -p ~/.docker/cli-plugins
ln -sfn $(brew --prefix)/opt/docker-compose/bin/docker-compose ~/.docker/cli-plugins/docker-compose
ln -sfn $(brew --prefix)/opt/docker-buildx/bin/docker-buildx ~/.docker/cli-plugins/docker-buildx

# 2. 启动（按需加 --vz-rosetta）
colima start --cpu 4 --memory 8 --disk 100 --vm-type vz

# 3. 验证
docker run --rm hello-world

# 4. 把自动启动函数加到 ~/.zshrc（见第四步）
```

完成这四步后，你的 MacBook 上的 Docker 使用体验就和基本版 Linux 服务器一致了——`docker` 命令随时可用，背后由 Colima 管理的轻量 Linux VM 支撑，没有 Docker Desktop 的 GUI 负担，也没有商业授权问题。

## 下一步

- 部署 OpenClaw：[`docs/quick-start.md`](quick-start.md)
- 配置说明：[`docs/configuration.md`](configuration.md)
- 故障排查：[`docs/faq.md`](faq.md)
