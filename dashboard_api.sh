#!/bin/sh
echo "Content-Type: application/json"
echo "Access-Control-Allow-Origin: *"
echo ""

# CPU usage calculation with delta (real-time)
CPU_PREV="/tmp/cpu_prev.stat"
CPU_NOW="/tmp/cpu_now.stat"
awk '/^cpu[0-9]/{print $1,$2,$3,$4,$5,$6,$7,$8}' /proc/stat > "$CPU_NOW"
if [ -f "$CPU_PREV" ]; then
    CPU_JSON=$(awk 'NR==FNR{p[$1]=$2" "$3" "$4" "$5" "$6" "$7" "$8;next}
    $1 in p{
        split(p[$1],a," ");
        t1=a[1]+a[2]+a[3]+a[4]+a[5]+a[6]+a[7];i1=a[4];
        t2=$2+$3+$4+$5+$6+$7+$8;i2=$5;
        dt=t2-t1;di=i2-i1;
        if(dt>0)pct=int((dt-di)*100/dt);else pct=0;
        printf "%d,",pct
    }' "$CPU_PREV" "$CPU_NOW" | sed 's/,$//')
else
    CPU_JSON="0,0,0,0"
fi
mv "$CPU_NOW" "$CPU_PREV"
CPU0=$(echo "$CPU_JSON" | cut -d, -f1)
CPU1=$(echo "$CPU_JSON" | cut -d, -f2)
CPU2=$(echo "$CPU_JSON" | cut -d, -f3)
CPU3=$(echo "$CPU_JSON" | cut -d, -f4)
[ -z "$CPU0" ] && CPU0=0
[ -z "$CPU1" ] && CPU1=0
[ -z "$CPU2" ] && CPU2=0
[ -z "$CPU3" ] && CPU3=0

UPTIME=$(awk '{print int($1)}' /proc/uptime)
LOAD=$(awk '{print $1}' /proc/loadavg)
TEMP=$(awk '{print int($1/1000)}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)
# Storage: overlay (root) and USB - values in KB to avoid 32-bit overflow
STOR_ROOT=$(df -k / 2>/dev/null | awk 'NR==2{printf "{\"total_kb\":%s,\"used_kb\":%s,\"avail_kb\":%s,\"pct\":%d}",$2,$3,$4,int($3*100/$2)}')
STOR_USB=$(df -k /tmp/mountd/disk2_part1 2>/dev/null | awk 'NR==2{printf "{\"total_kb\":%s,\"used_kb\":%s,\"avail_kb\":%s,\"pct\":%d}",$2,$3,$4,int($3*100/$2)}')
[ -z "$STOR_ROOT" ] && STOR_ROOT='{"total_kb":0,"used_kb":0,"avail_kb":0,"pct":0}'
[ -z "$STOR_USB" ] && STOR_USB='{"total_kb":0,"used_kb":0,"avail_kb":0,"pct":0}'
MEM_TOTAL=$(awk '/MemTotal/{print $2}' /proc/meminfo)
MEM_FREE=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
MEM_PCT=$(( (MEM_TOTAL - MEM_FREE) * 100 / MEM_TOTAL ))
INET=$(ping -c1 -W1 8.8.8.8 >/dev/null 2>&1 && echo true || echo false)
CONNS=$(wc -l < /proc/net/nf_conntrack 2>/dev/null || echo 0)

WIFI_2G=0; WIFI_5G=0
for iface in wlan0 wlan0-1 wlan1 wlan1-1; do
    cnt=$(iwinfo $iface assoclist 2>/dev/null | grep -c dBm)
    case $iface in wlan0|wlan0-1) WIFI_2G=$((WIFI_2G+cnt));; wlan1|wlan1-1) WIFI_5G=$((WIFI_5G+cnt));; esac
done
WIFI_TOTAL=$((WIFI_2G+WIFI_5G))

DHCP_IOT=$(grep -c '192.168.8.' /tmp/dhcp.leases 2>/dev/null || echo 0)
DHCP_LAN=$(grep -c '192.168.10.' /tmp/dhcp.leases 2>/dev/null || echo 0)

rx_eth1=$(cat /sys/class/net/eth1/statistics/rx_bytes 2>/dev/null || echo 0)
tx_eth1=$(cat /sys/class/net/eth1/statistics/tx_bytes 2>/dev/null || echo 0)
rx_lan5=$(cat /sys/class/net/lan5/statistics/rx_bytes 2>/dev/null || echo 0)
tx_lan5=$(cat /sys/class/net/lan5/statistics/tx_bytes 2>/dev/null || echo 0)
rx_lan=$(cat /sys/class/net/br-lan/statistics/rx_bytes 2>/dev/null || echo 0)
tx_lan=$(cat /sys/class/net/br-lan/statistics/tx_bytes 2>/dev/null || echo 0)
rx_iot=$(cat /sys/class/net/br-lan.8/statistics/rx_bytes 2>/dev/null || echo 0)
tx_iot=$(cat /sys/class/net/br-lan.8/statistics/tx_bytes 2>/dev/null || echo 0)

mwan_out=$(mwan3 status 2>/dev/null)
wan_status=$(echo "$mwan_out" | grep 'interface wan ' | grep -q online && echo online || echo offline)
wan_online=$(echo "$mwan_out" | grep 'interface wan ' | sed -n 's/.*online \([^,)]*\).*/\1/p')
[ -z "$wan_online" ] && wan_online="--"
wan2_status=$(echo "$mwan_out" | grep 'interface secondwan ' | grep -q online && echo online || echo offline)
wan2_online=$(echo "$mwan_out" | grep 'interface secondwan ' | sed -n 's/.*online \([^,)]*\).*/\1/p')
[ -z "$wan2_online" ] && wan2_online="--"

# SQM stats WAN1
sqm1=$(tc -s qdisc show dev eth1 2>/dev/null)
sqm1_bw=$(echo "$sqm1" | grep -o 'bandwidth [0-9A-Za-z]*' | awk '{print $2}')
sqm1_cap=$(echo "$sqm1" | grep -o 'capacity estimate: [0-9A-Za-z]*' | awk '{print $3}')
sqm1_drop=$(echo "$sqm1" | sed -n 's/.*dropped \([0-9]*\).*/\1/p' | head -1)
sqm1_sent=$(echo "$sqm1" | awk '/Sent/{print $2}' | head -1)
sqm1_diffserv=$(echo "$sqm1" | awk '/^  bytes/{print $2,$3,$4,$5}')
sqm1_bulk=$(echo $sqm1_diffserv | awk '{print $1}'); [ -z "$sqm1_bulk" ] && sqm1_bulk=0
sqm1_besteffort=$(echo $sqm1_diffserv | awk '{print $2}'); [ -z "$sqm1_besteffort" ] && sqm1_besteffort=0
sqm1_video=$(echo $sqm1_diffserv | awk '{print $3}'); [ -z "$sqm1_video" ] && sqm1_video=0
sqm1_voice=$(echo $sqm1_diffserv | awk '{print $4}'); [ -z "$sqm1_voice" ] && sqm1_voice=0
[ -z "$sqm1_bw" ] && sqm1_bw="--"
[ -z "$sqm1_cap" ] && sqm1_cap="--"
[ -z "$sqm1_drop" ] && sqm1_drop=0
[ -z "$sqm1_sent" ] && sqm1_sent=0
# Bufferbloat metrics WAN1 (pk_delay, av_delay per tin)
sqm1_pk_delay=$(echo "$sqm1" | awk '/pk_delay/{print $2,$3,$4,$5}')
sqm1_av_delay=$(echo "$sqm1" | awk '/av_delay/{print $2,$3,$4,$5}')
sqm1_pk_bulk=$(echo $sqm1_pk_delay | awk '{print $1}'); [ -z "$sqm1_pk_bulk" ] && sqm1_pk_bulk="0us"
sqm1_pk_be=$(echo $sqm1_pk_delay | awk '{print $2}'); [ -z "$sqm1_pk_be" ] && sqm1_pk_be="0us"
sqm1_pk_video=$(echo $sqm1_pk_delay | awk '{print $3}'); [ -z "$sqm1_pk_video" ] && sqm1_pk_video="0us"
sqm1_pk_voice=$(echo $sqm1_pk_delay | awk '{print $4}'); [ -z "$sqm1_pk_voice" ] && sqm1_pk_voice="0us"
sqm1_av_bulk=$(echo $sqm1_av_delay | awk '{print $1}'); [ -z "$sqm1_av_bulk" ] && sqm1_av_bulk="0us"
sqm1_av_be=$(echo $sqm1_av_delay | awk '{print $2}'); [ -z "$sqm1_av_be" ] && sqm1_av_be="0us"
sqm1_av_video=$(echo $sqm1_av_delay | awk '{print $3}'); [ -z "$sqm1_av_video" ] && sqm1_av_video="0us"
sqm1_av_voice=$(echo $sqm1_av_delay | awk '{print $4}'); [ -z "$sqm1_av_voice" ] && sqm1_av_voice="0us"

# SQM stats WAN2
sqm2=$(tc -s qdisc show dev lan5 2>/dev/null)
sqm2_bw=$(echo "$sqm2" | grep -o 'bandwidth [0-9A-Za-z]*' | awk '{print $2}')
sqm2_cap=$(echo "$sqm2" | grep -o 'capacity estimate: [0-9A-Za-z]*' | awk '{print $3}')
sqm2_drop=$(echo "$sqm2" | sed -n 's/.*dropped \([0-9]*\).*/\1/p' | head -1)
sqm2_sent=$(echo "$sqm2" | awk '/Sent/{print $2}' | head -1)
sqm2_diffserv=$(echo "$sqm2" | awk '/^  bytes/{print $2,$3,$4,$5}')
sqm2_bulk=$(echo $sqm2_diffserv | awk '{print $1}'); [ -z "$sqm2_bulk" ] && sqm2_bulk=0
sqm2_besteffort=$(echo $sqm2_diffserv | awk '{print $2}'); [ -z "$sqm2_besteffort" ] && sqm2_besteffort=0
sqm2_video=$(echo $sqm2_diffserv | awk '{print $3}'); [ -z "$sqm2_video" ] && sqm2_video=0
sqm2_voice=$(echo $sqm2_diffserv | awk '{print $4}'); [ -z "$sqm2_voice" ] && sqm2_voice=0
[ -z "$sqm2_bw" ] && sqm2_bw="--"
[ -z "$sqm2_cap" ] && sqm2_cap="--"
[ -z "$sqm2_drop" ] && sqm2_drop=0
[ -z "$sqm2_sent" ] && sqm2_sent=0
# Bufferbloat metrics WAN2 (pk_delay, av_delay per tin)
sqm2_pk_delay=$(echo "$sqm2" | awk '/pk_delay/{print $2,$3,$4,$5}')
sqm2_av_delay=$(echo "$sqm2" | awk '/av_delay/{print $2,$3,$4,$5}')
sqm2_pk_bulk=$(echo $sqm2_pk_delay | awk '{print $1}'); [ -z "$sqm2_pk_bulk" ] && sqm2_pk_bulk="0us"
sqm2_pk_be=$(echo $sqm2_pk_delay | awk '{print $2}'); [ -z "$sqm2_pk_be" ] && sqm2_pk_be="0us"
sqm2_pk_video=$(echo $sqm2_pk_delay | awk '{print $3}'); [ -z "$sqm2_pk_video" ] && sqm2_pk_video="0us"
sqm2_pk_voice=$(echo $sqm2_pk_delay | awk '{print $4}'); [ -z "$sqm2_pk_voice" ] && sqm2_pk_voice="0us"
sqm2_av_bulk=$(echo $sqm2_av_delay | awk '{print $1}'); [ -z "$sqm2_av_bulk" ] && sqm2_av_bulk="0us"
sqm2_av_be=$(echo $sqm2_av_delay | awk '{print $2}'); [ -z "$sqm2_av_be" ] && sqm2_av_be="0us"
sqm2_av_video=$(echo $sqm2_av_delay | awk '{print $3}'); [ -z "$sqm2_av_video" ] && sqm2_av_video="0us"
sqm2_av_voice=$(echo $sqm2_av_delay | awk '{print $4}'); [ -z "$sqm2_av_voice" ] && sqm2_av_voice="0us"

for iface in wlan0 wlan0-1 wlan1 wlan1-1; do
    case $iface in wlan0|wlan0-1) band="2.4G";; wlan1|wlan1-1) band="5G";; esac
    ssid=$(iwinfo $iface info 2>/dev/null | awk -F'"' '/ESSID/{print $2}')
    [ -z "$ssid" ] && ssid="Unknown"
    iwinfo $iface assoclist 2>/dev/null | grep dBm | while read mac rest; do
        sig=$(echo "$rest" | awk '{print $1}')
        nm=$(awk -v m="$mac" 'tolower($2)==tolower(m){print $4}' /tmp/dhcp.leases 2>/dev/null | head -1)
        [ -z "$nm" ] && nm="$mac"
        printf '{"mac":"%s","signal":%s,"band":"%s","ssid":"%s","name":"%s"},' "$mac" "$sig" "$band" "$ssid" "$nm"
    done
done > /tmp/wcl.tmp
wifi_json=$(cat /tmp/wcl.tmp 2>/dev/null | sed 's/,$//')
rm -f /tmp/wcl.tmp

top_json=$(awk -F'[= ]' '{for(i=1;i<=NF;i++)if($i=="src"&&$(i+1)~/^192\.168\./)print $(i+1)}' /proc/net/nf_conntrack 2>/dev/null | sort | uniq -c | sort -rn | head -5 | awk '{printf"{\"ip\":\"%s\",\"conns\":%d},",$2,$1}' | sed 's/,$//')

NOW=$(date +%s)
dhcp_json=$(awk -v now="$NOW" '{r=$1-now;n=$4;if(n=="")n="*";printf"{\"ip\":\"%s\",\"mac\":\"%s\",\"name\":\"%s\",\"remain\":%d},",$3,$2,n,r}' /tmp/dhcp.leases 2>/dev/null | sed 's/,$//')

# Build DNS cache from dnsmasq log (IP -> domain)
# Forward: reply dominio is IP
grep -E "reply [a-zA-Z].*is [0-9]" /tmp/dnsmasq.log 2>/dev/null | tail -5000 | sed -n 's/.*reply \([^ ]*\) is \([0-9][0-9.]*\).*/\2 \1/p' > /tmp/dns_cache.tmp
# Reverse PTR: reply IP is hostname
grep -E "reply [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ is" /tmp/dnsmasq.log 2>/dev/null | tail -5000 | sed -n 's/.*reply \([0-9][0-9.]*\) is \([^ ]*\).*/\1 \2/p' >> /tmp/dns_cache.tmp
# Cached entries
grep -E "cached [a-zA-Z].*is [0-9]" /tmp/dnsmasq.log 2>/dev/null | tail -5000 | sed -n 's/.*cached \([^ ]*\) is \([0-9][0-9.]*\).*/\2 \1/p' >> /tmp/dns_cache.tmp
# Make unique
sort -u /tmp/dns_cache.tmp > /tmp/dns_cache2.tmp && mv /tmp/dns_cache2.tmp /tmp/dns_cache.tmp
# Add DHCP leases
awk '{print $3,$4}' /tmp/dhcp.leases 2>/dev/null >> /tmp/dns_cache.tmp

# WAN Health: IPs, gateways, ping latency
wan_ip=$(ip -4 addr show eth1 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
wan_gw=$(ip route show default dev eth1 2>/dev/null | awk '{print $3}' | head -1)
wan2_ip=$(ip -4 addr show lan5 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
wan2_gw=$(ip route show default dev lan5 2>/dev/null | awk '{print $3}' | head -1)
[ -z "$wan_ip" ] && wan_ip="--"
[ -z "$wan_gw" ] && wan_gw="--"
[ -z "$wan2_ip" ] && wan2_ip="--"
[ -z "$wan2_gw" ] && wan2_gw="--"
# Ping via each WAN (1 packet, 1s timeout)
ping_wan=$(ping -c1 -W1 -I eth1 8.8.8.8 2>/dev/null | awk -F'[/ ]' '/avg/{for(i=1;i<=NF;i++)if($i~/^[0-9]+\.[0-9]+$/){print $i;exit}}')
ping_wan2=$(ping -c1 -W1 -I lan5 8.8.8.8 2>/dev/null | awk -F'[/ ]' '/avg/{for(i=1;i<=NF;i++)if($i~/^[0-9]+\.[0-9]+$/){print $i;exit}}')
[ -z "$ping_wan" ] && ping_wan="-1"
[ -z "$ping_wan2" ] && ping_wan2="-1"
# mwan3 policy
mwan_policy=$(echo "$mwan_out" | awk '/^balanced:/{found=1;next}found&&/^ /{print;next}found{exit}' | awk '{gsub(/[() ]/,"");printf "{\"iface\":\"%s\",\"pct\":\"%s\"},",substr($0,1,index($0,"%")-1),substr($0,index($0,"%")-2)}' 2>/dev/null | sed 's/,$//')
# Simplify: just extract percentages
mwan_wan_pct=$(echo "$mwan_out" | grep -A5 '^balanced:' | grep 'wan ' | grep -o '[0-9]*%' | head -1)
mwan_wan2_pct=$(echo "$mwan_out" | grep -A5 '^balanced:' | grep 'secondwan' | grep -o '[0-9]*%' | head -1)
[ -z "$mwan_wan_pct" ] && mwan_wan_pct="0%"
[ -z "$mwan_wan2_pct" ] && mwan_wan2_pct="0%"

# WiFi Radio info
wifi_radio_json=""
for iface in wlan0 wlan1; do
    info=$(iwinfo $iface info 2>/dev/null)
    [ -z "$info" ] && continue
    ssid=$(echo "$info" | awk -F'"' '/ESSID/{print $2}')
    ch=$(echo "$info" | grep -o 'Channel: [0-9]*' | awk '{print $2}')
    freq=$(echo "$info" | grep -o '([0-9.]* GHz)' | tr -d '()')
    htmode=$(echo "$info" | grep -o 'HT Mode: [A-Za-z0-9]*' | awk '{print $3}')
    txpwr=$(echo "$info" | grep -o 'Tx-Power: [0-9]* dBm' | awk '{print $2}')
    noise=$(echo "$info" | grep -o 'Noise: -[0-9]* dBm' | awk '{print $2}')
    hwmode=$(echo "$info" | grep -o 'HW Mode.*' | sed 's/HW Mode(s): //')
    case $iface in wlan0) band="2.4G";; wlan1) band="5G";; esac
    # Count neighbor APs from survey
    neighbors=$(iwinfo $iface survey 2>/dev/null | grep -c 'Cell ')
    wifi_radio_json="${wifi_radio_json}{\"iface\":\"$iface\",\"band\":\"$band\",\"ssid\":\"$ssid\",\"channel\":$ch,\"freq\":\"$freq\",\"htmode\":\"$htmode\",\"txpower\":$txpwr,\"noise\":$noise,\"hwmode\":\"$hwmode\",\"neighbors\":$neighbors},"
done
wifi_radio_json=$(echo "$wifi_radio_json" | sed 's/,$//')

# DNS Analytics
dns_total=$(grep -c 'query\[A\]' /tmp/dnsmasq.log 2>/dev/null || echo 0)
dns_cached=$(grep -c 'cached' /tmp/dnsmasq.log 2>/dev/null || echo 0)
dns_forwarded=$(grep -c 'forwarded' /tmp/dnsmasq.log 2>/dev/null || echo 0)
dns_blocked=$(grep -c 'NXDOMAIN\|/etc/adblock' /tmp/dnsmasq.log 2>/dev/null || echo 0)
if [ "$dns_total" -gt 0 ]; then
    dns_hit_pct=$((dns_cached * 100 / (dns_cached + dns_forwarded + 1)))
else
    dns_hit_pct=0
fi
dns_top=$(grep 'query\[A\]' /tmp/dnsmasq.log 2>/dev/null | awk '{print $NF}' | sed 's/from$//' | sort | uniq -c | sort -rn | head -8 | awk '{printf"{\"d\":\"%s\",\"c\":%d},",$2,$1}' | sed 's/,$//')
dns_top_clients=$(grep 'query\[A\]' /tmp/dnsmasq.log 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="from")print $(i+1)}' | sort | uniq -c | sort -rn | head -5 | awk '{printf"{\"ip\":\"%s\",\"c\":%d},",$2,$1}' | sed 's/,$//')

# Firewall Log (last rejected/dropped packets)
fw_json=$(logread 2>/dev/null | grep -iE 'DROP|REJECT|fw4' | tail -15 | awk '{
    ts=$1" "$2" "$3;
    src=""; dst=""; dpt=""; proto=""; act=""
    for(i=1;i<=NF;i++){
        if($i~/^SRC=/)src=substr($i,5)
        if($i~/^DST=/)dst=substr($i,5)
        if($i~/^DPT=/)dpt=substr($i,5)
        if($i~/^PROTO=/)proto=substr($i,7)
        if($i~/DROP/)act="DROP"
        if($i~/REJECT/)act="REJECT"
    }
    if(src!="")printf"{\"ts\":\"%s\",\"src\":\"%s\",\"dst\":\"%s\",\"port\":\"%s\",\"proto\":\"%s\",\"action\":\"%s\"},",ts,src,dst,dpt,proto,act
}' | sed 's/,$//')
fw_total=$(logread 2>/dev/null | grep -ciE 'DROP|REJECT|fw4' || echo 0)
fw_top_src=$(logread 2>/dev/null | grep -iE 'DROP|REJECT' | grep -oE 'SRC=[0-9.]+' | sed 's/SRC=//' | sort | uniq -c | sort -rn | head -5 | awk '{printf"{\"ip\":\"%s\",\"c\":%d},",$2,$1}' | sed 's/,$//')
fw_top_port=$(logread 2>/dev/null | grep -iE 'DROP|REJECT' | grep -oE 'DPT=[0-9]+' | sed 's/DPT=//' | sort | uniq -c | sort -rn | head -5 | awk '{printf"{\"port\":%s,\"c\":%d},",$2,$1}' | sed 's/,$//')

# Traffic History (hourly)
traffic_hist=$(cat /tmp/traffic_history.json 2>/dev/null || echo '[]')

# Speedtest: read last result if available
speedtest_json=$(cat /tmp/speedtest_result.json 2>/dev/null || echo '{"dl":0,"ul":0,"ping":0,"ts":"--"}')

conn_json=$(awk -F'[= ]' -v cache="/tmp/dns_cache.tmp" '
BEGIN{while((getline line < cache)>0){split(line,a," ");dns[a[1]]=a[2]}}
NR<=30&&/^ipv4/{
    p=($3==6?"TCP":"UDP");s="";d="";sp="";dp="";b=0;st="-"
    for(i=1;i<=NF;i++){
        if($i=="src"&&s=="")s=$(i+1)
        if($i=="dst"&&d=="")d=$(i+1)
        if($i=="sport"&&sp=="")sp=$(i+1)
        if($i=="dport"&&dp=="")dp=$(i+1)
        if($i=="bytes")b=$(i+1)
    }
    if(/ESTABLISHED/)st="EST";else if(/TIME_WAIT/)st="TW"
    src_name=(s in dns)?dns[s]:"-"
    dst_name=(d in dns)?dns[d]:"-"
    if(s!=""&&d!="")printf"{\"proto\":\"%s\",\"src\":\"%s\",\"dst\":\"%s\",\"sport\":\"%s\",\"dport\":\"%s\",\"bytes\":%d,\"state\":\"%s\",\"src_dns\":\"%s\",\"dst_dns\":\"%s\"},",p,s,d,sp,dp,b,st,src_name,dst_name
}' /proc/net/nf_conntrack 2>/dev/null | sed 's/,$//')
rm -f /tmp/dns_cache.tmp

cat << ENDJSON
{
  "system":{"uptime":$UPTIME,"load":"$LOAD","temp":$TEMP,"mem_pct":$MEM_PCT,"internet":$INET,"connections":$CONNS,"cpu":[$CPU0,$CPU1,$CPU2,$CPU3],"storage":{"root":$STOR_ROOT,"usb":$STOR_USB}},
  "clients":{"wifi_total":$WIFI_TOTAL,"wifi_2g":$WIFI_2G,"wifi_5g":$WIFI_5G,"dhcp_iot":$DHCP_IOT,"dhcp_lan":$DHCP_LAN},
  "traffic":{"wan":{"rx":$rx_eth1,"tx":$tx_eth1,"status":"$wan_status","online":"$wan_online"},"wan2":{"rx":$rx_lan5,"tx":$tx_lan5,"status":"$wan2_status","online":"$wan2_online"},"lan":{"rx":$rx_lan,"tx":$tx_lan},"iot":{"rx":$rx_iot,"tx":$tx_iot}},
  "sqm":{"wan":{"bw":"$sqm1_bw","capacity":"$sqm1_cap","sent":$sqm1_sent,"dropped":$sqm1_drop,"bulk":$sqm1_bulk,"besteffort":$sqm1_besteffort,"video":$sqm1_video,"voice":$sqm1_voice,"bloat":{"pk":["$sqm1_pk_bulk","$sqm1_pk_be","$sqm1_pk_video","$sqm1_pk_voice"],"av":["$sqm1_av_bulk","$sqm1_av_be","$sqm1_av_video","$sqm1_av_voice"]}},"wan2":{"bw":"$sqm2_bw","capacity":"$sqm2_cap","sent":$sqm2_sent,"dropped":$sqm2_drop,"bulk":$sqm2_bulk,"besteffort":$sqm2_besteffort,"video":$sqm2_video,"voice":$sqm2_voice,"bloat":{"pk":["$sqm2_pk_bulk","$sqm2_pk_be","$sqm2_pk_video","$sqm2_pk_voice"],"av":["$sqm2_av_bulk","$sqm2_av_be","$sqm2_av_video","$sqm2_av_voice"]}}},
  "wifi_clients":[$wifi_json],
  "top_clients":[$top_json],
  "dhcp_leases":[$dhcp_json],
  "active_conns":[$conn_json],
  "wan_health":{"wan":{"ip":"$wan_ip","gw":"$wan_gw","ping":$ping_wan,"status":"$wan_status","online":"$wan_online","lb":"$mwan_wan_pct"},"wan2":{"ip":"$wan2_ip","gw":"$wan2_gw","ping":$ping_wan2,"status":"$wan2_status","online":"$wan2_online","lb":"$mwan_wan2_pct"}},
  "wifi_radios":[$wifi_radio_json],
  "dns":{"total":$dns_total,"cached":$dns_cached,"forwarded":$dns_forwarded,"blocked":$dns_blocked,"hit_pct":$dns_hit_pct,"top":[$dns_top],"top_clients":[$dns_top_clients]},
  "firewall":{"total":$fw_total,"log":[$fw_json],"top_src":[$fw_top_src],"top_port":[$fw_top_port]},
  "traffic_history":$traffic_hist,
  "speedtest":$speedtest_json
}
ENDJSON
