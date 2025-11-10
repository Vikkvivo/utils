cat > start-vnc.sh <<'SH'
#!/usr/bin/env bash
# --- clean old ---
pkill -f cloudflared 2>/dev/null || true
pkill -f novnc_proxy 2>/dev/null || true
pkill -f x11vnc 2>/dev/null || true
pkill -f Xvfb 2>/dev/null || true

# --- fix Tencent mirror to Ubuntu global ---
sed -i "s|http://mirrors.cloud.tencent.com/ubuntu/|http://archive.ubuntu.com/ubuntu/|g" /etc/apt/sources.list
apt update --fix-missing && apt upgrade -y

# --- install base ---
apt install -y xfce4 xfce4-terminal dbus-x11 gvfs udev sudo xvfb x11vnc git python3 wget ca-certificates midori

# --- start display & desktop ---
Xvfb :0 -screen 0 1280x800x16 >/tmp/xvfb.log 2>&1 &
export DISPLAY=:0
sleep 2
startxfce4 >/tmp/xfce.log 2>&1 &
sleep 3

# --- start x11vnc (port 5900) ---
x11vnc -display :0 -rfbport 5900 -nopw -forever -shared >/tmp/x11vnc.log 2>&1 &
sleep 2

# --- noVNC setup ---
[ -d /opt/noVNC ] || git clone https://github.com/novnc/noVNC.git /opt/noVNC
cd /opt/noVNC
ln -sf vnc.html index.html
# run via bash (not python)
bash /opt/noVNC/utils/novnc_proxy --vnc localhost:5900 --listen 6080 >/tmp/novnc.log 2>&1 &
sleep 3

# --- cloudflared tunnel (robust installer + runner) ---
CLOUDFLARED_PATH=/usr/local/bin/cloudflared
# If cloudflared missing or not executable, download the right binary for this host
if ! command -v cloudflared >/dev/null 2>&1 || [ ! -x "$CLOUDFLARED_PATH" ]; then
  ARCH="$(uname -m)"
  if [ "$ARCH" = "x86_64" ]; then
    BINNAME=cloudflared-linux-amd64
  elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    BINNAME=cloudflared-linux-arm64
  else
    echo "Unsupported architecture: $ARCH" >/tmp/cloudflared.log
    echo "Cloudflared not installed (unsupported arch)" >/tmp/cloudflared.log
  fi

  if [ -n "${BINNAME:-}" ]; then
    echo "Downloading $BINNAME ..." >/tmp/cloudflared.log
    # try curl then wget
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL -o /tmp/$BINNAME "https://github.com/cloudflare/cloudflared/releases/latest/download/$BINNAME" || true
    else
      wget -q -O /tmp/$BINNAME "https://github.com/cloudflare/cloudflared/releases/latest/download/$BINNAME" || true
    fi
    if [ -f /tmp/$BINNAME ]; then
      mv -f /tmp/$BINNAME "$CLOUDFLARED_PATH"
      chmod +x "$CLOUDFLARED_PATH"
      echo "cloudflared installed to $CLOUDFLARED_PATH" >> /tmp/cloudflared.log
    else
      echo "Failed to download cloudflared binary" >> /tmp/cloudflared.log
    fi
  fi
fi

# Start cloudflared tunnel (background) and capture logs
pkill -f 'cloudflared tunnel --url' 2>/dev/null || true
if [ -x "$CLOUDFLARED_PATH" ]; then
  "$CLOUDFLARED_PATH" tunnel --no-autoupdate --url http://localhost:6080 >/tmp/cloudflared.log 2>&1 &
  CLOUDFLARED_PID=$!
  echo "cloudflared started (pid $CLOUDFLARED_PID)" >> /tmp/cloudflared.log
else
  echo "cloudflared binary not available or not executable; check /tmp/cloudflared.log for details" >/tmp/cloudflared.log
fi

# Wait up to 15 seconds and try to extract trycloudflare URL from log
URL=""
for i in $(seq 1 15); do
  sleep 1
  if [ -f /tmp/cloudflared.log ]; then
    URL=$(grep -oE "https://[a-zA-Z0-9.-]+\\.trycloudflare\\.com" /tmp/cloudflared.log | tail -n 1 || true)
    if [ -n "$URL" ]; then
      echo "Found Cloudflared URL: $URL" >> /tmp/cloudflared.log
      break
    fi
  fi
done

if [ -n "$URL" ]; then
  echo "$URL" > /tmp/cloudflared_url
else
  echo "URL not ready; check /tmp/cloudflared.log for details" > /tmp/cloudflared_url
fi

# --- open Tencent Cloud login in XFCE ---
URL_TENCENT="https://www.tencentcloud.com/account/login?s_url=https%3A%2F%2Fwww.tencentcloud.com%2F"
dbus-launch midori "$URL_TENCENT" >/tmp/midori.log 2>&1 &

# --- summary ---
sleep 3
echo
echo "✅ XFCE desktop + noVNC + Cloudflared tunnel ready!"
echo
echo ">>> Ports listening:"
ss -tunlp | egrep "5900|6080" || true
echo
echo ">>> Cloudflared URL:"
# print URL if found, otherwise show helpful message
if [ -f /tmp/cloudflared_url ]; then
  cat /tmp/cloudflared_url
else
  grep -oE "https://[a-zA-Z0-9.-]+\\.trycloudflare\\.com" /tmp/cloudflared.log | tail -n 1 || echo "URL not ready (see /tmp/cloudflared.log)"
fi
SH

chmod +x start-vnc.sh && ./start-vnc.sh
