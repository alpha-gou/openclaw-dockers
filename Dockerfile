# OpenClaw Docker 镜像
FROM docker.m.daocloud.io/node:22-slim

# 从 国内镜像源 拷贝 Python 3.12 (确保使用与 node 镜像一致的 Debian Bookworm 版本)
COPY --from=docker.m.daocloud.io/python:3.12-slim-bookworm /usr/local /usr/local

# 设置工作目录
WORKDIR /app

# 设置环境变量
ENV BUN_INSTALL="/usr/local" \
    PATH="/usr/local/bin:$PATH" \
    DEBIAN_FRONTEND=noninteractive

# Openclaw版本
# 默认使用最新版，指定版本命令：
#     docker build --build-arg OPENCLAW_VERSION=2026.6.1 -t myclawimage .
ARG OPENCLAW_VERSION=latest

# 1. 系统依赖与环境安装
## 1.1：换源和基础更新
RUN rm -f /etc/apt/sources.list.d/* && \
    echo "deb http://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list && \
    echo "deb http://mirrors.ustc.edu.cn/debian-security/ bookworm-security main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    apt-get update

## 1.2：安装基础工具
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
    socat \
    tini \
    gosu \
    build-essential \
    docker.io \
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

## 1.4：Node.js 工具安装（单独一层，便于缓存）
RUN npm install -g openclaw@${OPENCLAW_VERSION} opencode-ai@latest clawhub playwright playwright-extra puppeteer-extra-plugin-stealth @steipete/bird

## 1.5：安装运行时工具
# bun 的 npm 包靠可选依赖 @oven/bun-linux-<arch> 下平台二进制；npmmirror 对最新版
# 平台包常有同步延迟(当前缺 1.4.2 的 x64/aarch64)，会导致 install.js 失败。
# 先走 npmmirror(国内快)，失败再回退官方 npm 源(总有最新平台包)。两架构通用。
RUN (npm install -g bun || npm install -g bun --registry=https://registry.npmjs.org) && \
    ln -sf /usr/local/bin/python3 /usr/local/bin/python && \
    /usr/local/bin/python3 -m pip install --break-system-packages --index-url https://mirrors.aliyun.com/pypi/simple/ uv && \
    /usr/local/bin/python3 -m pip install --no-cache-dir --index-url https://mirrors.aliyun.com/pypi/simple/ websockify && \
    npm install -g @tobilu/qmd@1.1.6

## 1.6：国内镜像安装 Playwright Chromium
# 按架构区分：x86_64 下 npmmirror 提供 chrome-for-testing linux64；arm64 下 npmmirror
# 无对应 arm64 构建，跳过缓存下载，运行时改用 apt 安装的 /usr/bin/chromium(arm64 原生，
# 也是 openclaw.json 里 browser.executablePath 指向的路径)。
RUN if [ "$(uname -m)" = "x86_64" ]; then \
      CHROMIUM_REV=1223 && \
      CFT_VER=148.0.7778.96 && \
      TARGET_DIR=/root/.cache/ms-playwright/chromium-${CHROMIUM_REV} && \
      mkdir -p ${TARGET_DIR}/chrome-linux64 && \
      cd /tmp && \
      curl -fL \
        "https://cdn.npmmirror.com/binaries/chrome-for-testing/${CFT_VER}/linux64/chrome-linux64.zip" \
        -o chrome.zip && \
      unzip -q chrome.zip && \
      cp -r chrome-linux64/* ${TARGET_DIR}/chrome-linux64/ && \
      date > ${TARGET_DIR}/INSTALLATION_COMPLETE && \
      rm -rf /tmp/chrome.zip /tmp/chrome-linux64; \
    else \
      echo "非 x86_64 架构 ($(uname -m))：跳过 playwright chromium 缓存下载，运行时使用 /usr/bin/chromium"; \
    fi

## 1.7：验证（可选，build 阶段就能提前暴露问题）
RUN npx playwright install-deps chromium || true

## 1.8：清理
RUN apt-get purge -y --auto-remove && \
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
