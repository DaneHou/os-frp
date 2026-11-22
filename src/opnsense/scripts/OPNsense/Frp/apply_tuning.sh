#!/bin/sh

# Apply network tuning settings (BBR, MSS clamping)
# Reads settings from both Client and Server models
# Idempotent - safe to run multiple times

CONFIG_XML="/conf/config.xml"

# Helper to read config values using php
get_config() {
    local path="$1"
    /usr/local/bin/php -r "
        \$xml = simplexml_load_file('${CONFIG_XML}');
        \$node = \$xml->xpath('${path}');
        echo count(\$node) > 0 ? (string)\$node[0] : '';
    " 2>/dev/null
}

# Resolve OPNsense interface name to real device
resolve_iface() {
    local iface="$1"
    # Read the real device name directly from config.xml
    local real=$(get_config "//interfaces/${iface}/if")
    if [ -z "$real" ]; then
        # Fallback: get interface from default route
        real=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
    fi
    echo "${real:-$iface}"
}

# Determine which mode is active (client or server)
# Returns the config path prefix
get_active_mode() {
    local client_enabled=$(get_config "//OPNsense/frp/client/enabled")
    local server_enabled=$(get_config "//OPNsense/frp/server/enabled")
    if [ "$client_enabled" = "1" ]; then
        echo "client"
    elif [ "$server_enabled" = "1" ]; then
        echo "server"
    else
        echo ""
    fi
}

# BBR Congestion Control (system-wide — no per-connection option in FreeBSD)
apply_bbr() {
    local mode="$1"
    local enabled=""
    if [ -n "$mode" ]; then
        enabled=$(get_config "//OPNsense/frp/${mode}/bbrEnabled")
    fi

    if [ "$enabled" = "1" ]; then
        echo "Enabling TCP BBR..."
        if ! kldstat -q -m tcp_bbr 2>/dev/null; then
            kldload tcp_bbr 2>/dev/null || {
                echo "Warning: Failed to load tcp_bbr module"
                return 1
            }
        fi
        sysctl net.inet.tcp.functions_default=bbr > /dev/null 2>&1
        echo "BBR enabled: $(sysctl -n net.inet.tcp.functions_default)"
    else
        current=$(sysctl -n net.inet.tcp.functions_default 2>/dev/null)
        if [ "$current" = "bbr" ]; then
            echo "Disabling BBR, restoring default TCP stack..."
            sysctl net.inet.tcp.functions_default=freebsd > /dev/null 2>&1
        fi
    fi
}

# MSS Clamping via pf — FRP-specific rules only
apply_mss() {
    local mode="$1"
    local enabled=""
    if [ -n "$mode" ]; then
        enabled=$(get_config "//OPNsense/frp/${mode}/mssClampEnabled")
    fi

    if [ "$enabled" = "1" ]; then
        local mss=$(get_config "//OPNsense/frp/${mode}/mssValue")
        mss=${mss:-1260}
        local real_iface=$(resolve_iface "wan")

        if [ "$mode" = "client" ]; then
            # Client mode: clamp traffic to/from the remote FRP server
            local server_addr=$(get_config "//OPNsense/frp/client/serverAddr")
            local server_port=$(get_config "//OPNsense/frp/client/serverPort")
            server_port=${server_port:-7000}

            if [ -z "$server_addr" ]; then
                echo "Warning: No server address configured, skipping MSS clamping"
                return 1
            fi

            echo "Setting MSS clamp ${mss} on ${real_iface} for FRP client traffic to ${server_addr}:${server_port}..."
            printf "match on %s proto tcp to %s port %s scrub (max-mss %s)\nmatch on %s proto tcp from %s port %s scrub (max-mss %s)\n" \
                "$real_iface" "$server_addr" "$server_port" "$mss" \
                "$real_iface" "$server_addr" "$server_port" "$mss" \
                | pfctl -a frp_mss -f - 2>/dev/null || {
                echo "Warning: Failed to set MSS clamping"
            }
        elif [ "$mode" = "server" ]; then
            # Server mode: clamp traffic on the bind port (all FRP client connections)
            local bind_port=$(get_config "//OPNsense/frp/server/bindPort")
            bind_port=${bind_port:-7000}

            echo "Setting MSS clamp ${mss} on ${real_iface} for FRP server port ${bind_port}..."
            printf "match on %s proto tcp to port %s scrub (max-mss %s)\nmatch on %s proto tcp from port %s scrub (max-mss %s)\n" \
                "$real_iface" "$bind_port" "$mss" \
                "$real_iface" "$bind_port" "$mss" \
                | pfctl -a frp_mss -f - 2>/dev/null || {
                echo "Warning: Failed to set MSS clamping"
            }
        fi
    else
        pfctl -a frp_mss -F rules 2>/dev/null
    fi
}

# TCP Fast Open (system-wide kernel setting)
apply_tfo() {
    local mode="$1"
    local enabled=""
    if [ -n "$mode" ]; then
        enabled=$(get_config "//OPNsense/frp/${mode}/tfoEnabled")
    fi

    if [ "$enabled" = "1" ]; then
        echo "Enabling TCP Fast Open..."
        sysctl net.inet.tcp.fastopen.server_enable=1 > /dev/null 2>&1
        sysctl net.inet.tcp.fastopen.client_enable=1 > /dev/null 2>&1
        echo "TFO enabled: server=$(sysctl -n net.inet.tcp.fastopen.server_enable) client=$(sysctl -n net.inet.tcp.fastopen.client_enable)"
    else
        current=$(sysctl -n net.inet.tcp.fastopen.server_enable 2>/dev/null)
        if [ "$current" = "1" ]; then
            echo "Disabling TCP Fast Open..."
            sysctl net.inet.tcp.fastopen.server_enable=0 net.inet.tcp.fastopen.client_enable=0 > /dev/null 2>&1
        fi
    fi
}

# TCP deep tuning — buffers, window scaling, SACK (system-wide)
apply_tcp_tuning() {
    local mode="$1"
    local enabled=""
    if [ -n "$mode" ]; then
        enabled=$(get_config "//OPNsense/frp/${mode}/tcpTuningEnabled")
    fi

    if [ "$enabled" = "1" ]; then
        echo "Applying TCP buffer tuning..."
        # raise only: never lower a larger system default
        for oid in net.inet.tcp.recvbuf_max net.inet.tcp.sendbuf_max; do
            [ "$(sysctl -n $oid 2>/dev/null || echo 0)" -lt 4194304 ] && sysctl $oid=4194304 > /dev/null 2>&1
        done
        sysctl net.inet.tcp.rfc1323=1 > /dev/null 2>&1
        sysctl net.inet.tcp.sack.enable=1 > /dev/null 2>&1
        sysctl net.inet.tcp.nolocaltimewait=1 > /dev/null 2>&1
        echo "TCP tuning applied (buffers >= 4MB, SACK, RFC 1323)"
    fi
    # off: leave the system's buffer limits alone (they may be larger than any FRP default)
}

mode=$(get_active_mode)
echo "Applying FRP network tuning (mode: ${mode:-none})..."
apply_bbr "$mode"
apply_mss "$mode"
apply_tfo "$mode"
apply_tcp_tuning "$mode"
echo "Tuning complete."
