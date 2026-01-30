#!/bin/sh
# Triggered by dashboard to run speedtest
RESULT_FILE="/tmp/speedtest_result.json"
LOCK_FILE="/tmp/speedtest.lock"

# Prevent concurrent runs
if [ -f "$LOCK_FILE" ]; then
    echo '{"status":"running"}'
    exit 0
fi
touch "$LOCK_FILE"

echo '{"status":"running","ts":"'$(date +%H:%M)'"}' > "$RESULT_FILE"

# Run speedtest-netperf (sequential mode, 10s per direction)
OUTPUT=$(/usr/bin/speedtest-netperf.sh -t 10 -H netperf.bufferbloat.net -p 8.8.8.8 2>&1)

DL=$(echo "$OUTPUT" | grep -i 'download' | grep -oE '[0-9]+\.[0-9]+' | head -1)
UL=$(echo "$OUTPUT" | grep -i 'upload' | grep -oE '[0-9]+\.[0-9]+' | head -1)
IDLE=$(echo "$OUTPUT" | grep -i 'idle.*latency' | grep -oE '[0-9]+\.[0-9]+' | head -1)
DL_LAT=$(echo "$OUTPUT" | grep -i 'download.*latency' | grep -oE '[0-9]+\.[0-9]+' | head -1)
UL_LAT=$(echo "$OUTPUT" | grep -i 'upload.*latency' | grep -oE '[0-9]+\.[0-9]+' | head -1)

[ -z "$DL" ] && DL=0
[ -z "$UL" ] && UL=0
[ -z "$IDLE" ] && IDLE=0
[ -z "$DL_LAT" ] && DL_LAT=0
[ -z "$UL_LAT" ] && UL_LAT=0

cat > "$RESULT_FILE" << EOF
{"status":"done","dl":$DL,"ul":$UL,"idle_lat":$IDLE,"dl_lat":$DL_LAT,"ul_lat":$UL_LAT,"ts":"$(date '+%Y-%m-%d %H:%M')","raw":"$(echo "$OUTPUT" | tail -5 | tr '\n' '|' | sed 's/"/\\"/g')"}
EOF

rm -f "$LOCK_FILE"
