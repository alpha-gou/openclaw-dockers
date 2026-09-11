#!/bin/sh
# 为 CADDY_IP 生成自签 TLS 证书（SAN 含该 IP/域名），供 Caddyfile 使用。
#
# 用法（在项目根目录执行）：
#   sh caddy/generate-cert.sh 123.57.245.84        # 直接传 IP
#   或先 export CADDY_IP=123.57.245.84 再运行
#   sh caddy/generate-cert.sh
#
# 生成后把 caddy.crt 装到客户端「受信任的根证书颁发机构」可消除浏览器警告。
# 私钥 caddy.key 切勿提交（已加入 .gitignore）。
set -e

IP="${1:-${CADDY_IP}}"
if [ -z "$IP" ]; then
  echo "用法: sh caddy/generate-cert.sh <IP或域名>" >&2
  echo "  或先 export CADDY_IP=<IP或域名> 再运行" >&2
  exit 1
fi

DIR="$(cd "$(dirname "$0")" && pwd)"

# IPv4 用 IP SAN，其余（域名/IPv6）用 DNS SAN
if echo "$IP" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
  SAN="IP:$IP"
else
  SAN="DNS:$IP"
fi

echo "→ 为 $IP 生成自签证书（SAN=$SAN，有效期 10 年）..."
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout "$DIR/caddy.key" \
  -out "$DIR/caddy.crt" \
  -subj "/CN=$IP" \
  -addext "subjectAltName=$SAN"

echo "✅ 完成："
echo "   证书：$DIR/caddy.crt"
echo "   私钥：$DIR/caddy.key（勿提交）"
echo "→ 把 caddy.crt 装到客户端「受信任的根证书颁发机构」可消除浏览器警告。"
