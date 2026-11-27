#!/bin/sh

# FRP Watchdog — checks that each enabled role (frpc client, frps server) runs
# and starts only the one that is down. Runs via cron every minute.

CONFIG_XML="/conf/config.xml"
LOG_DIR="/var/log/frp"
LOG_FILE="${LOG_DIR}/watchdog.log"
RC="/usr/local/etc/rc.d/frp"

# Ensure log dir exists
mkdir -p "${LOG_DIR}"

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] $1" >> "${LOG_FILE}"
}

# client and server enabled flags in one PHP run: "<client> <server>"
read_enabled() {
    /usr/local/bin/php -r "
        \$xml = @simplexml_load_file('${CONFIG_XML}');
        if (\$xml === false) { exit(1); }
        \$c = \$xml->xpath('//OPNsense/frp/client/enabled');
        \$s = \$xml->xpath('//OPNsense/frp/server/enabled');
        echo (count(\$c) ? (string)\$c[0] : '0') . ' ' . (count(\$s) ? (string)\$s[0] : '0');
    " 2>/dev/null
}

enabled=$(read_enabled) || exit 0
client_enabled=${enabled% *}
server_enabled=${enabled#* }

for role in client server; do
    if [ "$role" = "client" ]; then on="$client_enabled"; else on="$server_enabled"; fi
    [ "$on" = "1" ] || continue
    # rc.d status checks the role's own pidfile (and adopts a pre-1.3 one)
    if ! "$RC" onestatus "$role" >/dev/null 2>&1; then
        log_msg "FRP ${role} not running, starting it..."
        /usr/local/sbin/configctl frp start "$role" >/dev/null 2>&1
        log_msg "Start command issued for ${role}"
    fi
done

# Trim log file if too large (>1MB)
if [ -f "${LOG_FILE}" ]; then
    log_size=$(stat -f%z "${LOG_FILE}" 2>/dev/null || echo 0)
    if [ "$log_size" -gt 1048576 ]; then
        tail -n 100 "${LOG_FILE}" > "${LOG_FILE}.tmp"
        mv "${LOG_FILE}.tmp" "${LOG_FILE}"
    fi
fi
