#!/bin/sh
# Speedtest for both WAN interfaces using curl + Cloudflare
RESULT_FILE="/tmp/speedtest_result.json"
LOCK_FILE="/tmp/speedtest.lock"

if [ -f "$LOCK_FILE" ]; then
    exit 0
fi
touch "$LOCK_FILE"

DL_URL="https://speed.cloudflare.com/__down?bytes=50000000"
UL_URL="https://speed.cloudflare.com/__up"
DURATION=8

to_mbps() {
    awk "BEGIN{v=$1*8/1000000; printf \"%.1f\", v}"
}

# Auto-detect WAN device (supports PPPoE)
wan_dev=$(ip route show default 2>/dev/null | awk '/dev pppoe-/{print $5;exit}')
[ -z "$wan_dev" ] && wan_dev=$(ip route show default 2>/dev/null | awk 'NR==1{print $5}')

# --- WAN1 (Telmex) ---
echo '{"status":"running","phase":"wan1_download","ts":"'"$(date +%H:%M)"'"}' > "$RESULT_FILE"
DL1=$(curl -o /dev/null -s -w '%{speed_download}' --max-time $DURATION --interface "$wan_dev" "$DL_URL" 2>/dev/null)
DL1_MBPS=$(to_mbps "${DL1:-0}")

echo '{"status":"running","phase":"wan1_upload","ts":"'"$(date +%H:%M)"'"}' > "$RESULT_FILE"
UL1=$(dd if=/dev/urandom bs=1M count=10 2>/dev/null | curl -s -w '%{speed_upload}' --max-time $DURATION --interface "$wan_dev" -X POST -H "Content-Type: application/octet-stream" --data-binary @- "$UL_URL" 2>/dev/null | tail -1)
UL1_MBPS=$(to_mbps "${UL1:-0}")

PING1=$(ping -c 3 -W 1 -I "$wan_dev" 1.1.1.1 2>/dev/null | awk -F'[/ ]' '/avg/{for(i=1;i<=NF;i++)if($i~/^[0-9]+\.[0-9]+$/){print $i;exit}}')
[ -z "$PING1" ] && PING1="0"

# --- WAN2 (lan5 - Megacable) ---
echo '{"status":"running","phase":"wan2_download","ts":"'"$(date +%H:%M)"'"}' > "$RESULT_FILE"
DL2=$(curl -o /dev/null -s -w '%{speed_download}' --max-time $DURATION --interface lan5 "$DL_URL" 2>/dev/null)
DL2_MBPS=$(to_mbps "${DL2:-0}")

echo '{"status":"running","phase":"wan2_upload","ts":"'"$(date +%H:%M)"'"}' > "$RESULT_FILE"
UL2=$(dd if=/dev/urandom bs=1M count=10 2>/dev/null | curl -s -w '%{speed_upload}' --max-time $DURATION --interface lan5 -X POST -H "Content-Type: application/octet-stream" --data-binary @- "$UL_URL" 2>/dev/null | tail -1)
UL2_MBPS=$(to_mbps "${UL2:-0}")

PING2=$(ping -c 3 -W 1 -I lan5 1.1.1.1 2>/dev/null | awk -F'[/ ]' '/avg/{for(i=1;i<=NF;i++)if($i~/^[0-9]+\.[0-9]+$/){print $i;exit}}')
[ -z "$PING2" ] && PING2="0"

cat > "$RESULT_FILE" << EOF
{"status":"done","wan1":{"dl":$DL1_MBPS,"ul":$UL1_MBPS,"ping":$PING1},"wan2":{"dl":$DL2_MBPS,"ul":$UL2_MBPS,"ping":$PING2},"ts":"$(date '+%Y-%m-%d %H:%M')"}
EOF

rm -f "$LOCK_FILE"
