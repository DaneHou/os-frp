#!/bin/sh

# Docker HEALTHCHECK script
# Returns 0 (healthy) or 1 (unhealthy)

MODE="${FRP_MODE:-client}"
HEALTH_URL="${FRP_HEALTH_CHECK_URL:-}"
ADMIN_ADDR="${FRP_ADMIN_ADDR:-127.0.0.1}"
ADMIN_PORT="${FRP_ADMIN_PORT:-7400}"
ADMIN_USER="${FRP_ADMIN_USER:-}"
ADMIN_PWD="${FRP_ADMIN_PWD:-}"

# Check 1: FRP process alive
if [ "$MODE" = "client" ]; then
    pgrep -x frpc >/dev/null 2>&1 || { echo "UNHEALTHY: frpc not running"; exit 1; }
else
    pgrep -x frps >/dev/null 2>&1 || { echo "UNHEALTHY: frps not running"; exit 1; }
fi

# Check 2: FRP admin API responds (if configured)
if [ -n "$ADMIN_PORT" ] && [ "$ADMIN_PORT" != "0" ]; then
    AUTH_OPTS=""
    if [ -n "$ADMIN_USER" ]; then
        AUTH_OPTS="-u ${ADMIN_USER}:${ADMIN_PWD}"
    fi

    if [ "$MODE" = "client" ]; then
        STATUS=$(curl -sf $AUTH_OPTS "http://${ADMIN_ADDR}:${ADMIN_PORT}/api/status" -o /dev/null -w "%{http_code}" 2>/dev/null)
    else
        STATUS=$(curl -sf $AUTH_OPTS "http://${ADMIN_ADDR}:${ADMIN_PORT}/api/serverinfo" -o /dev/null -w "%{http_code}" 2>/dev/null)
    fi

    if [ "$STATUS" != "200" ] && [ "$STATUS" != "401" ]; then
        echo "UNHEALTHY: FRP admin API not responding (HTTP $STATUS)"
        exit 1
    fi
fi

# Check 3: External connectivity (if configured)
if [ -n "$HEALTH_URL" ]; then
    HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" --max-time 5 "$HEALTH_URL" 2>/dev/null)
    if [ "$HTTP_CODE" = "000" ]; then
        echo "UNHEALTHY: Cannot reach $HEALTH_URL"
        exit 1
    fi
fi

echo "HEALTHY"
exit 0
