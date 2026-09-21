# OpenClaw Docker 镜像（精简版）
# 基础镜像：openclaw >= 2026.9 要求 Node >=24.16 <25 || >=26.1（Node 22 已不被官方支持），
# 与官方 Dockerfile 的 node:24-bookworm-slim 运行时基准保持一致。
FROM docker.m.daocloud.io/node:24-bookworm-slim

# 从 国内镜像源 拷贝 Python 3.12 (确保使用与 node 镜像一致的 Debian Bookworm 版本)
COPY --from=docker.m.daocloud.io/python:3.12-slim-bookworm /usr/local /usr/local

# 设置工作目录
WORKDIR /app

# 设置环境变量
ENV PATH="/usr/local/bin:$PATH" \
    DEBIAN_FRONTEND=noninteractive

# Openclaw版本
# 默认使用最新版，指定版本命令：
#     docker build --build-arg OPENCLAW_VERSION=2026.9.5 -t myclawimage .
ARG OPENCLAW_VERSION=latest

# 1. 系统依赖与环境安装
## 1.1：换源和基础更新
RUN rm -f /etc/apt/sources.list.d/* && \
    echo "deb http://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list && \
    echo "deb http://mirrors.ustc.edu.cn/debian-security/ bookworm-security main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    apt-get update

## 1.2：安装基础工具（已精简）
# 已移除且仓库内零引用：
#   - socat / tini：init.sh 与 compose 均未使用（compose 用 `init: true`，自带 init）
#   - build-essential：qqbot 等插件为纯 JS，无需编译；官方运行时镜像也不含构建工具
#   - docker.io：openclaw.json 中 sandbox.mode=off；如日后启用 docker 沙箱，
#     需重新加回 docker.io（或官方推荐的 docker-ce-cli）并在 compose 中挂载 /var/run/docker.sock
RUN apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    locales \
    openssh-client \
    procps \
    unzip \
    jq \
    gosu \
    ffmpeg \
    fonts-liberation \
    fonts-noto-cjk \
    fonts-noto-color-emoji \
    chromium

## 1.3：Locale 配置、Git 和 NPM 配置
RUN sed -i 's/^# *en_US.UTF-8 UTF-8$/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen && \
    printf 'LANG=en_US.UTF-8\nLANGUAGE=en_US:en\nLC_ALL=en_US.UTF-8\n' > /etc/default/locale && \
    git config --system url."https://github.com/".insteadOf ssh://git@github.com/ && \
    npm config set registry https://registry.npmmirror.com

## 1.4：Node.js 工具安装（已精简）
# 保留：openclaw（主体）、clawhub（官方扩展市场 CLI）
# 已移除：
#   - @steipete/bird：npm 已标记 deprecated（上游停止维护），Twitter 能力由 agent-reach 承担
#   - opencode-ai：openclaw.json 的 modelPolicy 只放行 deepseek 模型，coding-agent skill 已禁用
#   - playwright / playwright-extra / puppeteer-extra-plugin-stealth：
#     openclaw 自带 playwright-core（1.63.0），浏览器走 openclaw.json 的
#     browser.executablePath=/usr/bin/chromium（apt 版，双架构原生）；
#     playwright-extra 与 stealth 插件 2023 年后停更且无任何配置引用
RUN npm install -g openclaw@${OPENCLAW_VERSION} clawhub

## 1.5：Python 命令别名
# 已移除：bun（官方运行时镜像不含 Bun，仓库内无使用）、uv（init.sh 装 agent-reach 用 pip+venv）、
#         websockify（无 noVNC 引用，18888 是 gateway 端口）、@tobilu/qmd（无引用；
#         如日后 memory.search 切 qmd 后端，可加回并直接用最新版 @2.x）
RUN ln -sf /usr/local/bin/python3 /usr/local/bin/python

## 1.6：清理
# （原 1.6 Playwright Chromium 预缓存层已删除：钉死的 chromium-1223 与 openclaw 内嵌
#   playwright-core 1.63.0 要求的 rev 1243 不匹配，且缓存在 /root/.cache 下、
#   gateway 以 node 用户运行根本读不到，属无效死重；原 1.7 install-deps 一并移除，
#   apt 安装的 chromium 自带全部系统依赖）
RUN apt-get autoremove -y --purge && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /root/.npm /root/.cache

# 2. 插件安装（作为 node 用户以避免后期权限修复带来的镜像膨胀）
RUN mkdir -p /home/node/.openclaw/workspace /home/node/.openclaw/extensions && \
    chown -R node:node /home/node

USER node
ENV HOME=/home/node
WORKDIR /home/node

# 安装linuxbrew（Homebrew 的 Linux 版本），并配置环境变量
# 默认已注释：init.sh 不依赖 linuxbrew，且其 git clone（github）较慢。
# 如需让 agent 可用 brew（安装额外命令行工具），取消下面整段注释即可。
# RUN mkdir -p /home/node/.linuxbrew/Homebrew && \
#     git clone --depth 1 https://gh.llkk.cc/https://github.com/Homebrew/brew /home/node/.linuxbrew/Homebrew && \
#     mkdir -p /home/node/.linuxbrew/bin && \
#     ln -s /home/node/.linuxbrew/Homebrew/bin/brew /home/node/.linuxbrew/bin/brew && \
#     chown -R node:node /home/node/.linuxbrew && \
#     chmod -R g+rwX /home/node/.linuxbrew

# IM 渠道插件安装：默认全部注释，按需取消注释对应渠道。
# 注意：装了任意渠道后，需一并取消下面"seed 打包"段的注释，否则插件不会固化进镜像
# （运行时 extensions 命名卷会覆盖镜像层，导致 build 时装的插件不可见）。

# 公共：clawhub 登录（拉取私有扩展时需要）
# ARG CLAWHUB_TOKEN
# RUN if [ -n "$CLAWHUB_TOKEN" ]; then clawhub login --token "$CLAWHUB_TOKEN"; fi

# —— napcat（QQ/OneBot 桥接，需 git clone + npm install）——
# RUN cd /home/node/.openclaw/extensions && \
#     git clone --depth 1 https://gh.llkk.cc/https://github.com/Daiyimo/openclaw-napcat.git napcat && \
#     cd napcat && \
#     npm install --production && \
#     timeout 300 openclaw plugins install --dangerously-force-unsafe-install -l . || true

# —— 钉钉 dingtalk ——
# RUN cd /home/node/.openclaw/extensions && \
#     timeout 300 openclaw plugins install --dangerously-force-unsafe-install @soimy/dingtalk || true

# —— QQ qqbot ——
RUN cd /home/node/.openclaw/extensions && \
    timeout 300 openclaw plugins install --dangerously-force-unsafe-install @openclaw/qqbot || true

# —— 企业微信 wecom ——
# RUN cd /home/node/.openclaw/extensions && \
#     timeout 300 openclaw plugins install --dangerously-force-unsafe-install @sunnoy/wecom || true

# seed 打包：把上面已安装的插件固化为镜像内置 seed（运行时按 SYNC_EXTENSIONS_MODE 同步到卷）
# 装了任意渠道后取消下面注释，以生成 seed
RUN mkdir -p /home/node/.openclaw /home/node/.openclaw-seed && \
    find /home/node/.openclaw/extensions -name ".git" -type d -exec rm -rf {} + && \
    mv /home/node/.openclaw/extensions /home/node/.openclaw-seed/ && \
    if [ "$OPENCLAW_VERSION" = "latest" ]; then \
      VERSION_TO_WRITE="$(openclaw --version 2>/dev/null | head -n1 | sed 's/.* //' || date '+%Y.%-m.%-d')-f1"; \
    else \
      VERSION_TO_WRITE="${OPENCLAW_VERSION}-f1"; \
    fi && \
    printf '%s\n' "$VERSION_TO_WRITE" > /home/node/.openclaw-seed/extensions/.seed-version && \
    rm -rf /tmp/* /home/node/.npm /home/node/.cache

# 3. 最终配置
USER root

# 复制初始化脚本并确保换行符为 LF
COPY ./init.sh /usr/local/bin/init.sh
RUN sed -i 's/\r$//' /usr/local/bin/init.sh && \
    chmod +x /usr/local/bin/init.sh

# 设置环境变量
ENV HOME=/home/node \
    TERM=xterm-256color \
    NODE_PATH=/usr/local/lib/node_modules \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    NODE_ENV=production \
    PATH="/home/node/.linuxbrew/bin:/home/node/.linuxbrew/sbin:/usr/local/lib/node_modules/.bin:${PATH}" \
    HOMEBREW_NO_AUTO_UPDATE=1 \
    HOMEBREW_NO_INSTALL_CLEANUP=1

# 暴露端口
EXPOSE 18888

# 设置工作目录为 home
WORKDIR /home/node

# 使用初始化脚本作为入口点
ENTRYPOINT ["/bin/bash", "/usr/local/bin/init.sh"]
