#!/bin/sh

# QUIC vs TCP transport probe — runs periodically on client
# Writes recommendation to /var/lib/frp/transport_metrics.json

METRICS_FILE="/var/lib/frp/transport_metrics.json"
PROBE_INTERVAL=300  # 5 minutes
CONSECUTIVE_THRESHOLD=3  # need 3 consistent probes to switch
LOG_FILE="/var/log/frp/transport_probe.log"

# Server address from environment
SERVER_ADDR="${FRP_SERVER_ADDR:-}"
SERVER_PORT="${FRP_SERVER_PORT:-7000}"
QUIC_PORT="${FRP_QUIC_PORT:-}"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [probe] $1" | tee -a "$LOG_FILE"
}

probe_tcp() {
    local result
    result=$(curl -sf -o /dev/null -w "%{time_connect}" --connect-timeout 5 "http://${SERVER_ADDR}:${SERVER_PORT}" 2>/dev/null)
    if [ $? -eq 0 ] || [ -n "$result" ]; then
        echo "$result"
    else
        echo "-1"
    fi
}

probe_quic() {
    if [ -z "$QUIC_PORT" ] || [ "$QUIC_PORT" = "0" ]; then
        echo "-1"
        return
    fi
    local result
    result=$(curl -sf -o /dev/null -w "%{time_connect}" --connect-timeout 5 "https://${SERVER_ADDR}:${QUIC_PORT}" 2>/dev/null)
    if [ $? -eq 0 ] || [ -n "$result" ]; then
        echo "$result"
    else
        echo "-1"
    fi
}

if [ -z "$SERVER_ADDR" ]; then
    log "No SERVER_ADDR configured, probe disabled"
    exit 0
fi

tcp_recommend_count=0
quic_recommend_count=0

log "Transport probe starting (server=$SERVER_ADDR tcp=$SERVER_PORT quic=$QUIC_PORT)"

while true; do
    tcp_latency=$(probe_tcp)
    quic_latency=$(probe_quic)
    now=$(date +%s)

    recommendation="tcp"
    reason="default"

    if [ "$quic_latency" != "-1" ] && [ "$tcp_latency" != "-1" ]; then
        # If QUIC latency < TCP * 1.2, prefer QUIC (good for lossy networks)
        prefer_quic=$(echo "$quic_latency $tcp_latency" | awk '{if ($1 < $2 * 1.2) print 1; else print 0}')
        if [ "$prefer_quic" = "1" ]; then
            recommendation="quic"
            reason="quic_lower_latency"
            quic_recommend_count=$((quic_recommend_count + 1))
            tcp_recommend_count=0
        else
            tcp_recommend_count=$((tcp_recommend_count + 1))
            quic_recommend_count=0
        fi
    elif [ "$tcp_latency" != "-1" ]; then
        tcp_recommend_count=$((tcp_recommend_count + 1))
        quic_recommend_count=0
        reason="quic_unavailable"
    fi

    # Hysteresis: only recommend switch after consecutive consistent probes
    stable_recommendation="$recommendation"
    if [ "$quic_recommend_count" -lt "$CONSECUTIVE_THRESHOLD" ] && [ "$tcp_recommend_count" -lt "$CONSECUTIVE_THRESHOLD" ]; then
        if [ -f "$METRICS_FILE" ]; then
            stable_recommendation=$(cat "$METRICS_FILE" | grep -o '"recommendation":"[^"]*"' | cut -d'"' -f4)
            stable_recommendation=${stable_recommendation:-tcp}
        fi
    fi

    cat > "$METRICS_FILE" <<EOF
{
    "timestamp": $now,
    "tcp_latency": "$tcp_latency",
    "quic_latency": "$quic_latency",
    "recommendation": "$stable_recommendation",
    "reason": "$reason",
    "tcp_recommend_count": $tcp_recommend_count,
    "quic_recommend_count": $quic_recommend_count
}
EOF

    log "TCP=${tcp_latency}s QUIC=${quic_latency}s recommend=$stable_recommendation ($reason)"

    sleep "$PROBE_INTERVAL"
done
