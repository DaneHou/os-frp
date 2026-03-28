# CLAUDE.md — os-frp development guide

## Project overview

OPNsense plugin + Docker images for FRP (Fast Reverse Proxy).
Cross-border China-US tunnel with GUI management, network tuning, and GFW evasion.

Three deployment modes: OPNsense↔OPNsense, OPNsense↔Docker, Docker↔Docker.

## Quick reference

### Architecture pattern
Follows **os-proxygateway** (`/home/dianxun/synology/github/os-proxygateway`) patterns:
- Separate menu pages per concern (NOT single-page tabs)
- OPNsense Jinja2 template engine for config generation (NOT custom Python)
- `ApiMutableModelControllerBase` for settings
- `ApiMutableServiceControllerBase` for service control
- UIBootgrid for proxy CRUD

### Critical OPNsense naming rules
- **API controllers must NOT share class names with UI controllers** — Phalcon router can't distinguish them. Use `SettingsController` for API, separate names for UI (ClientController, ServerController, etc.)
- **ServiceController must be named exactly `ServiceController`** — `updateServiceControlUI('frp')` hardcodes the path `/api/frp/service/{action}`
- **Menu.xml uses bare `<menu>` root**, NOT wrapped in `<model><items>`
- **ACL.xml uses bare `<acl>` root**, NOT wrapped in `<model><items>`

### Model mounts (config.xml paths)
- `//OPNsense/frp/client` → Client.xml (includes proxies + healthTargets ArrayFields)
- `//OPNsense/frp/server` → Server.xml

### Template engine paths
Templates use dot notation matching config.xml structure:
- `OPNsense.frp.client.enabled` → `<OPNsense><frp><client><enabled>`
- `OPNsense.frp.client.proxies.proxy` → proxy ArrayField entries
- `OPNsense.frp.server.enabled` → server settings

### API routes

```text
GET  /api/frp/settings/getClient              → SettingsController::getClientAction()
POST /api/frp/settings/setClient              → SettingsController::setClientAction()
GET  /api/frp/settings/getServer              → SettingsController::getServerAction()
POST /api/frp/settings/setServer              → SettingsController::setServerAction()
GET  /api/frp/settings/exportDockerConfig     → SettingsController::exportDockerConfigAction()
POST /api/frp/proxy/searchItem                → ProxyController::searchItemAction()
POST /api/frp/proxy/addItem                   → ProxyController::addItemAction()
POST /api/frp/service/reconfigure             → ServiceController::reconfigureAction()
POST /api/frp/service/status                  → ServiceController::statusAction()
GET  /api/frp/monitor/live                    → MonitorController::liveAction()      (direct FRP API passthrough, no SQLite)
GET  /api/frp/monitor/proxies                 → MonitorController::proxiesAction()
GET  /api/frp/monitor/realtime                → MonitorController::realtimeAction()
GET  /api/frp/monitor/history                 → MonitorController::historyAction()
GET  /api/frp/monitor/summary                 → MonitorController::summaryAction()
GET  /api/frp/monitor/healthcheck             → MonitorController::healthcheckAction()
GET  /api/frp/monitor/healthHistory           → MonitorController::healthHistoryAction()
```

### Deployment commands

```bash
# On OPNsense — always uninstall first to clear stale PHP files
make uninstall && make install

# Plugin files only (no binary download)
make install-plugin && make activate

# Just activate (clear caches + restart webgui)
make activate
```

### Key files to modify for common tasks

**Add a new model field:**
1. Add field to model XML (e.g., `Client.xml`)
2. Add field to form XML (e.g., `forms/client.xml`)
3. Add to template if it affects config generation (e.g., `frpc.toml`)

**Add a new proxy type:**
1. Add option to `Client.xml` → `proxies.proxy.proxyType.OptionValues`
2. Add conditional template logic in `frpc.toml`
3. Update field visibility JS in `proxy.volt`

**Change FRP version:**
1. Update `FRP_VERSION` in `Makefile`
2. Update `FRP_VERSION` in `setup.sh`
3. Update `FRP_VERSION` in `docker/.env.example`
4. Update `ARG FRP_VERSION` in `docker/client/Dockerfile` and `docker/server/Dockerfile`

**Change Hysteria2 / shadow-TLS version:**
1. Update in `docker/.env.example`
2. Update `ARG` in both Dockerfiles

### Binary versions
- FRP: v0.67.0 (freebsd_amd64 for OPNsense, linux_amd64+arm64 for Docker)
- Hysteria 2: v2.5.1 (Docker only)
- shadow-TLS: v0.2.25 (Docker only)

### Docker structure
- `docker/shared/` — entrypoint + scripts shared between client/server
- `docker/client/` and `docker/server/` — Dockerfiles + compose + example configs
- Dockerfiles use `context: ..` (parent dir) to access `shared/`
- GitHub Actions (`docker-build.yml`) builds multi-arch images → `ghcr.io/{owner}/frp-client` and `ghcr.io/{owner}/frp-server`

### Testing checklist
1. `make install` → plugin appears under Services > FRP Tunnel
2. Client page: save settings → verify `/usr/local/etc/frp/frpc.toml` is valid TOML
3. Server page: save settings → verify `/usr/local/etc/frp/frps.toml` is valid TOML
4. Proxy page: add entries → verify `[[proxies]]` blocks in frpc.toml
5. `configctl frp start` → frpc/frps running, `configctl frp status` confirms
6. Client page Advanced: enable BBR → `sysctl net.inet.tcp.functions_default` returns `bbr`
7. Client page Advanced: enable TFO → `sysctl net.inet.tcp.fastopen.enabled` returns 1
8. Client page Advanced: enable TCP Tuning → `sysctl net.inet.tcp.recvbuf_max` returns 4194304
9. Monitor page: speed chart + health checks working (requires webServer enabled)
10. Export Docker Config: Server page → downloads valid frpc.toml
11. Docker: `docker compose up -d` → frpc/frps running, `docker compose logs` shows TCP tuning applied
12. Docker: kill frpc → watchdog restarts with backoff logging
