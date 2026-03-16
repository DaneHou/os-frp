#!/bin/sh

# FRP Watchdog — manages frpc/frps + optional hysteria2 + shadow-tls
# Implements Surge-style exponential backoff reconnection

MODE="${FRP_MODE:-client}"
WATCHDOG_ENABLED="${FRP_WATCHDOG_ENABLED:-true}"
HYSTERIA2_ENABLED="${HYSTERIA2_ENABLED:-false}"
SHADOW_TLS_ENABLED="${SHADOW_TLS_ENABLED:-false}"

LOG_FILE="/var/log/frp/watchdog.log"
FRP_PID=""
HYSTERIA2_PID=""
SHADOW_TLS_PID=""

# Backoff settings (Surge-style: aggressive initial reconnect)
BACKOFF_STEPS="0.1 0.5 1 5 10 30"
STABLE_THRESHOLD=60  # seconds of stability before resetting backoff

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] $1" | tee -a "$LOG_FILE"
}

get_backoff() {
    local attempt=$1
    local idx=0
    for delay in $BACKOFF_STEPS; do
        if [ "$idx" -eq "$attempt" ]; then
            echo "$delay"
            return
        fi
        idx=$((idx + 1))
    done
    echo "30"
}

start_shadow_tls() {
    if [ "$SHADOW_TLS_ENABLED" != "true" ]; then
        return
    fi

    if [ "$MODE" = "client" ]; then
        SHADOW_TLS_LISTEN="${SHADOW_TLS_LISTEN:-127.0.0.1:1234}"
        SHADOW_TLS_SERVER="${SHADOW_TLS_SERVER:-}"
        SHADOW_TLS_PASSWORD="${SHADOW_TLS_PASSWORD:-}"
        SHADOW_TLS_SNI="${SHADOW_TLS_SNI:-www.microsoft.com}"

        if [ -z "$SHADOW_TLS_SERVER" ] || [ -z "$SHADOW_TLS_PASSWORD" ]; then
            log "ERROR: SHADOW_TLS_SERVER and SHADOW_TLS_PASSWORD required for client mode"
            return
        fi

        log "Starting shadow-tls client: listen=$SHADOW_TLS_LISTEN server=$SHADOW_TLS_SERVER sni=$SHADOW_TLS_SNI"
        /usr/local/bin/shadow-tls client \
            --listen "$SHADOW_TLS_LISTEN" \
            --server "$SHADOW_TLS_SERVER" \
            --sni "$SHADOW_TLS_SNI" \
            --password "$SHADOW_TLS_PASSWORD" \
            >> /var/log/frp/shadow-tls.log 2>&1 &
        SHADOW_TLS_PID=$!
        log "shadow-tls client started (PID: $SHADOW_TLS_PID)"
    else
        SHADOW_TLS_LISTEN="${SHADOW_TLS_LISTEN:-0.0.0.0:443}"
        SHADOW_TLS_BACKEND="${SHADOW_TLS_BACKEND:-127.0.0.1:7000}"
        SHADOW_TLS_PASSWORD="${SHADOW_TLS_PASSWORD:-}"
        SHADOW_TLS_SNI="${SHADOW_TLS_SNI:-www.microsoft.com}"

        if [ -z "$SHADOW_TLS_PASSWORD" ]; then
            log "ERROR: SHADOW_TLS_PASSWORD required for server mode"
            return
        fi

        log "Starting shadow-tls server: listen=$SHADOW_TLS_LISTEN backend=$SHADOW_TLS_BACKEND sni=$SHADOW_TLS_SNI"
        /usr/local/bin/shadow-tls server \
            --listen "$SHADOW_TLS_LISTEN" \
            --server "$SHADOW_TLS_BACKEND" \
            --sni "$SHADOW_TLS_SNI" \
            --password "$SHADOW_TLS_PASSWORD" \
            >> /var/log/frp/shadow-tls.log 2>&1 &
        SHADOW_TLS_PID=$!
        log "shadow-tls server started (PID: $SHADOW_TLS_PID)"
    fi
}

start_hysteria2() {
    if [ "$HYSTERIA2_ENABLED" != "true" ]; then
        return
    fi

    local config_file=""
    if [ "$MODE" = "client" ]; then
        config_file="/etc/hysteria2/hysteria2.yaml"
    else
        config_file="/etc/hysteria2/hysteria2-server.yaml"
    fi

    if [ ! -f "$config_file" ]; then
        log "WARN: Hysteria2 config not found at $config_file"
        return
    fi

    log "Starting hysteria2 ($MODE) with config $config_file"
    /usr/local/bin/hysteria2 "$config_file" >> /var/log/frp/hysteria2.log 2>&1 &
    HYSTERIA2_PID=$!
    log "hysteria2 started (PID: $HYSTERIA2_PID)"
}

start_frp() {
    local binary=""
    local config=""

    if [ "$MODE" = "client" ]; then
        binary="/usr/local/bin/frpc"
        # Use active config if transport probe generated one
        if [ -f /var/lib/frp/frpc_active.toml ]; then
            config="/var/lib/frp/frpc_active.toml"
        else
            config="/etc/frp/frpc.toml"
        fi
    else
        binary="/usr/local/bin/frps"
        config="/etc/frp/frps.toml"
    fi

    if [ ! -f "$config" ]; then
        log "ERROR: Config file not found: $config"
        return 1
    fi

    log "Starting $binary with config $config"
    $binary -c "$config" >> "/var/log/frp/${MODE}.log" 2>&1 &
    FRP_PID=$!
    log "FRP $MODE started (PID: $FRP_PID)"
}

check_frp_alive() {
    [ -n "$FRP_PID" ] && kill -0 "$FRP_PID" 2>/dev/null
}

check_hysteria2_alive() {
    [ -n "$HYSTERIA2_PID" ] && kill -0 "$HYSTERIA2_PID" 2>/dev/null
}

check_shadow_tls_alive() {
    [ -n "$SHADOW_TLS_PID" ] && kill -0 "$SHADOW_TLS_PID" 2>/dev/null
}

cleanup() {
    log "Shutting down..."
    [ -n "$FRP_PID" ] && kill "$FRP_PID" 2>/dev/null
    [ -n "$HYSTERIA2_PID" ] && kill "$HYSTERIA2_PID" 2>/dev/null
    [ -n "$SHADOW_TLS_PID" ] && kill "$SHADOW_TLS_PID" 2>/dev/null
    wait
    log "All processes stopped"
    exit 0
}

trap cleanup INT TERM

# --- Main Loop ---
log "=== Watchdog starting (mode=$MODE) ==="

# Start shadow-tls first (outermost proxy layer)
start_shadow_tls
sleep 0.5

# Start hysteria2
start_hysteria2
sleep 0.5

# Start FRP
start_frp

frp_attempt=0
frp_start_time=$(date +%s)
hysteria2_attempt=0
hysteria2_start_time=$(date +%s)

while true; do
    sleep 1

    now=$(date +%s)

    # --- FRP health check ---
    if ! check_frp_alive; then
        delay=$(get_backoff $frp_attempt)
        log "FRP process died (attempt $frp_attempt, backoff ${delay}s)"
        sleep "$delay"

        # Check transport probe recommendation before restart (client only)
        if [ "$MODE" = "client" ] && [ -f /var/lib/frp/transport_metrics.json ]; then
            log "Checking transport probe recommendation..."
        fi

        start_frp
        frp_attempt=$((frp_attempt + 1))
        frp_start_time=$(date +%s)
    else
        # Reset backoff if stable
        uptime=$((now - frp_start_time))
        if [ "$uptime" -gt "$STABLE_THRESHOLD" ] && [ "$frp_attempt" -gt 0 ]; then
            log "FRP stable for ${uptime}s, resetting backoff counter"
            frp_attempt=0
        fi
    fi

    # --- Hysteria2 health check ---
    if [ "$HYSTERIA2_ENABLED" = "true" ]; then
        if ! check_hysteria2_alive; then
            delay=$(get_backoff $hysteria2_attempt)
            log "Hysteria2 process died (attempt $hysteria2_attempt, backoff ${delay}s)"
            sleep "$delay"
            start_hysteria2
            hysteria2_attempt=$((hysteria2_attempt + 1))
            hysteria2_start_time=$(date +%s)
        else
            uptime=$((now - hysteria2_start_time))
            if [ "$uptime" -gt "$STABLE_THRESHOLD" ] && [ "$hysteria2_attempt" -gt 0 ]; then
                hysteria2_attempt=0
            fi
        fi
    fi

    # --- Shadow-TLS health check ---
    if [ "$SHADOW_TLS_ENABLED" = "true" ]; then
        if ! check_shadow_tls_alive; then
            log "Shadow-TLS process died, restarting..."
            start_shadow_tls
        fi
    fi
done
