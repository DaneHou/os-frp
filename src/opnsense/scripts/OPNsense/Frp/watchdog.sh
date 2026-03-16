#!/bin/sh

# FRP Watchdog — checks frpc/frps process and restarts if needed
# Runs via cron every minute

CONFIG_XML="/conf/config.xml"
LOG_DIR="/var/log/frp"
LOG_FILE="${LOG_DIR}/watchdog.log"
PID_FILE="/var/run/frp.pid"

# Ensure log dir exists
mkdir -p "${LOG_DIR}"

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] $1" >> "${LOG_FILE}"
}

# Helper to read config values
get_config() {
    local path="$1"
    /usr/local/bin/php -r "
        \$xml = simplexml_load_file('${CONFIG_XML}');
        \$node = \$xml->xpath('${path}');
        echo count(\$node) > 0 ? (string)\$node[0] : '';
    " 2>/dev/null
}

# Determine what should be running
client_enabled=$(get_config "//OPNsense/frp/client/enabled")
server_enabled=$(get_config "//OPNsense/frp/server/enabled")

if [ "$client_enabled" != "1" ] && [ "$server_enabled" != "1" ]; then
    # Nothing should be running
    exit 0
fi

# Check if process is alive
is_running=0
if [ -f "${PID_FILE}" ]; then
    pid=$(cat "${PID_FILE}" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        is_running=1
    fi
fi

# Also check by process name
if [ "$is_running" = "0" ]; then
    if [ "$client_enabled" = "1" ]; then
        if pgrep -x frpc >/dev/null 2>&1; then
            is_running=1
        fi
    fi
    if [ "$server_enabled" = "1" ]; then
        if pgrep -x frps >/dev/null 2>&1; then
            is_running=1
        fi
    fi
fi

if [ "$is_running" = "0" ]; then
    log_msg "FRP process not running, restarting..."
    /usr/local/bin/configctl frp restart
    log_msg "Restart command issued"
fi

# Trim log file if too large (>1MB)
if [ -f "${LOG_FILE}" ]; then
    log_size=$(stat -f%z "${LOG_FILE}" 2>/dev/null || echo 0)
    if [ "$log_size" -gt 1048576 ]; then
        tail -n 100 "${LOG_FILE}" > "${LOG_FILE}.tmp"
        mv "${LOG_FILE}.tmp" "${LOG_FILE}"
    fi
fi
