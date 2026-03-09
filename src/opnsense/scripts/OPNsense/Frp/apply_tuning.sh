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
    local real=$(/usr/local/bin/php -r "
        require_once 'config.inc';
        require_once 'interfaces.inc';
        \$iface = get_real_interface('${iface}');
        echo \$iface;
    " 2>/dev/null)
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
            printf "scrub on %s proto tcp to %s port %s max-mss %s\nscrub on %s proto tcp from %s port %s max-mss %s\n" \
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
            printf "scrub on %s proto tcp to port %s max-mss %s\nscrub on %s proto tcp from port %s max-mss %s\n" \
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

mode=$(get_active_mode)
echo "Applying FRP network tuning (mode: ${mode:-none})..."
apply_bbr "$mode"
apply_mss "$mode"
echo "Tuning complete."
