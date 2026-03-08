#!/bin/sh

# Apply network tuning settings (BBR, MTU clamping, MSS clamping)
# Reads settings from OPNsense config.xml
# Idempotent - safe to run multiple times

CONFIG_XML="/conf/config.xml"

# Helper to read config values using xmlstarlet or a simple grep approach
get_config() {
    local path="$1"
    # Use php to read from config.xml reliably
    /usr/local/bin/php -r "
        \$xml = simplexml_load_file('${CONFIG_XML}');
        \$node = \$xml->xpath('${path}');
        echo count(\$node) > 0 ? (string)\$node[0] : '';
    " 2>/dev/null
}

# BBR Congestion Control
apply_bbr() {
    local enabled=$(get_config "//OPNsense/frp/tuning/bbrEnabled")
    if [ "$enabled" = "1" ]; then
        echo "Enabling TCP BBR..."
        # Load BBR kernel module if not loaded
        if ! kldstat -q -m tcp_bbr 2>/dev/null; then
            kldload tcp_bbr 2>/dev/null || {
                echo "Warning: Failed to load tcp_bbr module"
                return 1
            }
        fi
        sysctl net.inet.tcp.functions_default=bbr > /dev/null 2>&1
        echo "BBR enabled: $(sysctl -n net.inet.tcp.functions_default)"
    else
        # Restore default if BBR was previously enabled
        current=$(sysctl -n net.inet.tcp.functions_default 2>/dev/null)
        if [ "$current" = "bbr" ]; then
            echo "Disabling BBR, restoring default TCP stack..."
            sysctl net.inet.tcp.functions_default=freebsd > /dev/null 2>&1
        fi
    fi
}

# MTU Clamping
apply_mtu() {
    local enabled=$(get_config "//OPNsense/frp/tuning/mtuClampEnabled")
    if [ "$enabled" = "1" ]; then
        local mtu=$(get_config "//OPNsense/frp/tuning/mtuValue")
        local iface=$(get_config "//OPNsense/frp/tuning/mtuInterface")
        mtu=${mtu:-1300}
        iface=${iface:-wan}

        # Resolve OPNsense interface name to real device
        real_iface=$(/usr/local/bin/php -r "
            require_once 'config.inc';
            require_once 'interfaces.inc';
            \$iface = get_real_interface('${iface}');
            echo \$iface;
        " 2>/dev/null)
        real_iface=${real_iface:-$iface}

        echo "Setting MTU ${mtu} on ${real_iface}..."
        ifconfig "$real_iface" mtu "$mtu" 2>/dev/null || {
            echo "Warning: Failed to set MTU on ${real_iface}"
        }
    fi
}

# MSS Clamping via pf
apply_mss() {
    local enabled=$(get_config "//OPNsense/frp/tuning/mssClampEnabled")
    if [ "$enabled" = "1" ]; then
        local mss=$(get_config "//OPNsense/frp/tuning/mssValue")
        local iface=$(get_config "//OPNsense/frp/tuning/mssInterface")
        mss=${mss:-1260}
        iface=${iface:-wan}

        # Resolve OPNsense interface name to real device
        real_iface=$(/usr/local/bin/php -r "
            require_once 'config.inc';
            require_once 'interfaces.inc';
            \$iface = get_real_interface('${iface}');
            echo \$iface;
        " 2>/dev/null)
        real_iface=${real_iface:-$iface}

        echo "Setting MSS clamp ${mss} on ${real_iface}..."
        echo "scrub on ${real_iface} max-mss ${mss}" | pfctl -a frp_mss -f - 2>/dev/null || {
            echo "Warning: Failed to set MSS clamping"
        }
    else
        # Remove MSS clamp if disabled
        pfctl -a frp_mss -F rules 2>/dev/null
    fi
}

echo "Applying FRP network tuning..."
apply_bbr
apply_mtu
apply_mss
echo "Tuning complete."
