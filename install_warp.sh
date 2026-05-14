#!/bin/bash
set -e

WARP_DIR="/etc/x-ui/warp"
MARKER_FILE="${WARP_DIR}/.installed"

# --- 检测是否已经执行过 ---
if [ -f "$MARKER_FILE" ]; then
    echo "检测到 WireProxy WARP 已经安装过，脚本已退出。"
    exit 0
fi

# --- 输入 SOCKS5 端口，并检测占用 ---
while true; do
    read -p "请输入 SOCKS5 端口（默认 40000）： " SOCKS_PORT
    SOCKS_PORT=${SOCKS_PORT:-40000}

    if ss -lnt | grep -q ":${SOCKS_PORT} "; then
        echo "端口 ${SOCKS_PORT} 已被占用，请输入其他端口。"
    else
        echo "使用端口 ${SOCKS_PORT}"
        break
    fi
done

echo "=== 创建工作目录 ==="
sudo mkdir -p $WARP_DIR
sudo chown $USER:$USER $WARP_DIR
cd $WARP_DIR

echo "=== 安装依赖 ==="
sudo apt update
# 安装 curl wget tar unzip ss 命令
sudo apt install -y curl wget tar unzip iproute2

echo "=== 下载 wgcf ==="
wget -O wgcf https://github.com/ViRb3/wgcf/releases/download/v2.2.30/wgcf_2.2.30_linux_386
chmod +x wgcf

echo "=== 注册 WARP 账号 ==="
./wgcf register
./wgcf generate

if [ ! -f wgcf-profile.conf ]; then
    echo "生成 wgcf-profile.conf 失败，请检查 wgcf"
    exit 1
fi

echo "=== 下载 wireproxy ==="
wget -O wireproxy_linux_amd64.tar.gz https://github.com/windtf/wireproxy/releases/download/v1.1.2/wireproxy_linux_amd64.tar.gz
tar -xzf wireproxy_linux_amd64.tar.gz
chmod +x wireproxy
rm wireproxy_linux_amd64.tar.gz

echo "=== 生成 wireproxy 配置 ==="
cat > wireproxy.conf <<EOF
[Interface]
PrivateKey = $(grep PrivateKey wgcf-profile.conf | awk '{print $3}')
Address = $(grep Address wgcf-profile.conf | awk '{print $3}')
DNS = 1.1.1.1

[Peer]
PublicKey = bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = engage.cloudflareclient.com:2408

[Socks5]
BindAddress = 127.0.0.1:${SOCKS_PORT}
EOF

echo "=== 创建 systemd 服务 ==="
sudo tee /etc/systemd/system/wireproxy.service > /dev/null <<EOF
[Unit]
Description=WireProxy WARP SOCKS5
After=network.target

[Service]
Type=simple
ExecStart=${WARP_DIR}/wireproxy -c ${WARP_DIR}/wireproxy.conf
Restart=always
RestartSec=5
User=root
WorkingDirectory=${WARP_DIR}

[Install]
WantedBy=multi-user.target
EOF

echo "=== 重新加载 systemd 并启用服务 ==="
sudo systemctl daemon-reload
sudo systemctl enable wireproxy
sudo systemctl start wireproxy

# --- 等待服务启动 ---
sleep 3

# --- 测试 WARP 是否生效 ---
echo "=== 测试 WARP 是否生效 ==="
for i in {1..5}; do
    if curl --socks5 127.0.0.1:${SOCKS_PORT} https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -q warp; then
        echo "warp=on ✅"
        break
    else
        echo "等待 wireproxy 启动，重试 $i/5 ..."
        sleep 2
    fi
done

# --- 标记已安装 ---
touch "$MARKER_FILE"

echo "=== 安装完成 ==="
echo "配置信息："
echo "Address: 127.0.0.1"
echo "Port: ${SOCKS_PORT}"
