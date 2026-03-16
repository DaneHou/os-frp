#!/bin/sh
set -e

echo "=== FRP Docker Entrypoint ==="
echo "Mode: ${FRP_MODE:-client}"
echo "Watchdog: ${FRP_WATCHDOG_ENABLED:-true}"
echo "Hysteria2: ${HYSTERIA2_ENABLED:-false}"
echo "Shadow-TLS: ${SHADOW_TLS_ENABLED:-false}"

# === TCP Fast Open (3 = client + server) ===
echo 3 > /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null || echo "WARN: TFO not available (need NET_ADMIN cap)"

# === BBR congestion control ===
if [ -f /proc/sys/net/ipv4/tcp_congestion_control ]; then
    echo bbr > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo "WARN: BBR not available"
fi

# === TCP Pacing + fq queue discipline (Surge VIF v3 AQM inspired) ===
# fq (Fair Queue) works with BBR to enable TCP pacing, preventing burst losses
if command -v tc >/dev/null 2>&1; then
    IFACE=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
    if [ -n "$IFACE" ]; then
        tc qdisc replace dev "$IFACE" root fq pacing 2>/dev/null || echo "WARN: fq qdisc not available"
    fi
fi

# === Disable slow start after idle (better for long-lived tunnels) ===
echo 0 > /proc/sys/net/ipv4/tcp_slow_start_after_idle 2>/dev/null || true

# === TCP buffer tuning for high-latency cross-border links ===
# BDP = 100Mbps x 0.2s RTT = 2.5MB, set 4MB with headroom
echo "4096 1048576 4194304" > /proc/sys/net/ipv4/tcp_rmem 2>/dev/null || true
echo "4096 1048576 4194304" > /proc/sys/net/ipv4/tcp_wmem 2>/dev/null || true

# === Enable window scaling (RFC 1323) ===
echo 1 > /proc/sys/net/ipv4/tcp_window_scaling 2>/dev/null || true

# === Enable TCP timestamps (accurate RTT measurement, needed by BBR) ===
echo 1 > /proc/sys/net/ipv4/tcp_timestamps 2>/dev/null || true

# === Enable SACK (selective acknowledgment, reduces retransmission) ===
echo 1 > /proc/sys/net/ipv4/tcp_sack 2>/dev/null || true

# === Connection backlog limit (Surge connection limit inspired) ===
echo 65535 > /proc/sys/net/core/somaxconn 2>/dev/null || true

echo "=== TCP tuning applied ==="

# Create data directory
mkdir -p /var/lib/frp /var/log/frp

# Start watchdog (manages frp + optional hysteria2 + shadow-tls)
exec /scripts/watchdog.sh
