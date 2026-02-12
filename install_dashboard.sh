#!/bin/sh
set -eu

usage() {
    cat << 'EOF'
Usage:
  sh install_dashboard.sh [user@router_ip] [wan_zone_index]

Examples:
  sh install_dashboard.sh
  sh install_dashboard.sh root@192.168.8.1
  sh install_dashboard.sh root@192.168.8.1 1

Arguments:
  user@router_ip   Router SSH target (default: root@192.168.8.1)
  wan_zone_index   Optional firewall WAN zone index (auto-detected if omitted)
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

if [ "$#" -gt 2 ]; then
    usage >&2
    exit 1
fi

ROUTER="${1:-root@192.168.8.1}"
WAN_ZONE_INDEX="${2:-}"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

require_file() {
    if [ ! -f "$SCRIPT_DIR/$1" ]; then
        echo "Missing required file: $1" >&2
        exit 1
    fi
}

for file in dashboard.html dashboard_api.sh speedtest_trigger.sh run_speedtest.sh traffic_history.sh; do
    require_file "$file"
done

echo "[1/5] Copying dashboard files to $ROUTER ..."
scp "$SCRIPT_DIR/dashboard.html" "$ROUTER:/www/dashboard.html"
scp "$SCRIPT_DIR/dashboard_api.sh" "$ROUTER:/www/cgi-bin/dashboard_api.sh"
scp "$SCRIPT_DIR/speedtest_trigger.sh" "$ROUTER:/www/cgi-bin/speedtest_trigger.sh"
scp "$SCRIPT_DIR/run_speedtest.sh" "$ROUTER:/usr/bin/run_speedtest.sh"
scp "$SCRIPT_DIR/traffic_history.sh" "$ROUTER:/usr/bin/traffic_history.sh"

echo "[2/5] Setting executable permissions ..."
ssh "$ROUTER" 'chmod +x /www/cgi-bin/dashboard_api.sh /www/cgi-bin/speedtest_trigger.sh /usr/bin/run_speedtest.sh /usr/bin/traffic_history.sh'

echo "[3/5] Configuring idempotent traffic history cron ..."
ssh "$ROUTER" 'grep -qF "/usr/bin/traffic_history.sh" /etc/crontabs/root || echo "0 * * * * /usr/bin/traffic_history.sh" >> /etc/crontabs/root; /etc/init.d/cron restart'

echo "[4/5] Enabling dnsmasq query logging to /tmp/dnsmasq.log ..."
ssh "$ROUTER" 'uci set dhcp.@dnsmasq[0].logqueries="1"; uci set dhcp.@dnsmasq[0].logfacility="/tmp/dnsmasq.log"; uci commit dhcp; /etc/init.d/dnsmasq restart'

if [ -z "$WAN_ZONE_INDEX" ]; then
    WAN_ZONE_INDEX=$(ssh "$ROUTER" "uci show firewall | sed -n \"s/^firewall.@zone\\[\\([0-9][0-9]*\\)\\]\\.name='wan'$/\\1/p\" | head -1")
fi

if [ -n "$WAN_ZONE_INDEX" ]; then
    echo "[5/5] Enabling firewall logging on zone index $WAN_ZONE_INDEX ..."
    ssh "$ROUTER" "uci set firewall.@zone[$WAN_ZONE_INDEX].log='1'; uci set firewall.@zone[$WAN_ZONE_INDEX].log_limit='60/minute'; uci commit firewall; fw4 reload"
else
    echo "[5/5] WARNING: Could not auto-detect WAN zone index. Skipping firewall log setup." >&2
    echo "      Run this on router to find it: uci show firewall | grep \".name='wan'\"" >&2
    echo "      Then rerun: sh install_dashboard.sh $ROUTER <wan_zone_index>" >&2
fi

ROUTER_HOST=${ROUTER#*@}
ROUTER_HOST=${ROUTER_HOST%%:*}
echo ""
echo "Installation completed."
echo "Open: http://$ROUTER_HOST/dashboard.html"
