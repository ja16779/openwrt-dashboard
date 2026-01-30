#!/bin/sh
# Snapshots interface traffic bytes every hour for dashboard history
# Stores last 24 hours of data as JSON
HIST_FILE="/tmp/traffic_history.json"
HOUR=$(date +%H)

# Read current bytes
rx_wan=$(cat /sys/class/net/eth1/statistics/rx_bytes 2>/dev/null || echo 0)
tx_wan=$(cat /sys/class/net/eth1/statistics/tx_bytes 2>/dev/null || echo 0)
rx_wan2=$(cat /sys/class/net/lan5/statistics/rx_bytes 2>/dev/null || echo 0)
tx_wan2=$(cat /sys/class/net/lan5/statistics/tx_bytes 2>/dev/null || echo 0)

# Read previous snapshot
PREV_FILE="/tmp/traffic_prev.dat"
if [ -f "$PREV_FILE" ]; then
    . "$PREV_FILE"
    # Calculate delta
    drx_wan=$((rx_wan - prev_rx_wan))
    dtx_wan=$((tx_wan - prev_tx_wan))
    drx_wan2=$((rx_wan2 - prev_rx_wan2))
    dtx_wan2=$((tx_wan2 - prev_tx_wan2))
    # Handle counter reset (reboot)
    [ "$drx_wan" -lt 0 ] && drx_wan=$rx_wan
    [ "$dtx_wan" -lt 0 ] && dtx_wan=$tx_wan
    [ "$drx_wan2" -lt 0 ] && drx_wan2=$rx_wan2
    [ "$dtx_wan2" -lt 0 ] && dtx_wan2=$tx_wan2
else
    drx_wan=0; dtx_wan=0; drx_wan2=0; dtx_wan2=0
fi

# Save current as previous
cat > "$PREV_FILE" << EOF
prev_rx_wan=$rx_wan
prev_tx_wan=$tx_wan
prev_rx_wan2=$rx_wan2
prev_tx_wan2=$tx_wan2
EOF

# Update history JSON - array of 24 entries indexed by hour
ENTRY="{\"h\":$HOUR,\"wrx\":$drx_wan,\"wtx\":$dtx_wan,\"w2rx\":$drx_wan2,\"w2tx\":$dtx_wan2}"

if [ -f "$HIST_FILE" ]; then
    # Remove existing entry for this hour and add new one
    EXISTING=$(cat "$HIST_FILE" | sed "s/{\"h\":$HOUR[,}][^}]*},\?//g" | sed 's/,]/]/;s/\[,/[/')
    # Insert new entry
    NEW=$(echo "$EXISTING" | sed "s/\]$/,$ENTRY]/")
    echo "$NEW" > "$HIST_FILE"
else
    echo "[$ENTRY]" > "$HIST_FILE"
fi
