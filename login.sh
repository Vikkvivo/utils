echo "Your IP: $(curl -s ifconfig.me)"; PORT=3000
tmp=$(mktemp)

# start cloudflared in background, force line-buffering, log to temp file
stdbuf -oL cloudflared tunnel --url http://localhost:$PORT >"$tmp" 2>&1 & CF_PID=$!

# print the first 30 lines as they appear (then this tail+sed will exit)
( tail -n +1 -F "$tmp" 2>/dev/null | sed -n '1,9p' ) & TAIL_PID=$!

# wait until the URL appears in the log, then print it
URL=$(grep -m1 -oE 'https://[-A-Za-z0-9.]+\.trycloudflare\.com' "$tmp")
# stop the tail follower if still running, keep cloudflared running
kill $TAIL_PID 2>/dev/null || true

echo "$URL"
echo "...(logs hidden, tunnel still running)..."
echo "cloudflared PID: $CF_PID (use 'kill $CF_PID' to stop)"
