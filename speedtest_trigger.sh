#!/bin/sh
echo "Content-Type: application/json"
echo "Access-Control-Allow-Origin: *"
echo ""

if [ -f /tmp/speedtest.lock ]; then
    cat /tmp/speedtest_result.json 2>/dev/null || echo '{"status":"running"}'
else
    /usr/bin/run_speedtest.sh &
    echo '{"status":"started"}'
fi
