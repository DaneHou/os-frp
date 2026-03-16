# os-frp

OPNsense plugin + Docker images for [FRP](https://github.com/fatedier/frp) (Fast Reverse Proxy).

Designed for **cross-border tunnel stability** (e.g., China-US) with TCP tuning, smart reconnection, health monitoring, and optional GFW evasion via Hysteria 2 / shadow-TLS.

## Deployment Options

| US Side (Server) | China Side (Client) | How |
|------------------|--------------------|----|
| OPNsense (frps) | Docker (frpc) | **Most common** — GUI server + lightweight client |
| Docker (frps) | Docker (frpc) | No OPNsense needed |
| OPNsense (frps) | OPNsense (frpc) | Both sides have OPNsense |

```
China (frpc)                         US (frps)
┌────────────────────────┐           ┌──────────────────┐
│ frpc ─── FRP tunnel ──────────────→ frps → internet   │
│ BBR / TFO / TCP tuning │           │ BBR / TFO        │
│ + Hysteria2 (optional) │           │ + Hysteria2      │
│ + shadow-TLS (GFW)     │           │ + shadow-TLS     │
└────────────────────────┘           └──────────────────┘
```

## Quick Start

### Option A: Docker (easiest)

Pull pre-built images from GitHub Container Registry — no building required.

**Server (US side):**

```bash
mkdir -p frp-server && cd frp-server

# Download example configs
curl -fSLO https://raw.githubusercontent.com/DaneHou/os-frp/main/docker/server/docker-compose.yml
curl -fSLO https://raw.githubusercontent.com/DaneHou/os-frp/main/docker/.env.example
mkdir -p config
curl -fSL https://raw.githubusercontent.com/DaneHou/os-frp/main/docker/server/config/frps.toml.example -o config/frps.toml

# Edit config — set your auth token
nano config/frps.toml

# Copy and edit env
cp .env.example .env

# Run
docker compose up -d
```

**Client (China side):**

```bash
mkdir -p frp-client && cd frp-client

# Download example configs
curl -fSLO https://raw.githubusercontent.com/DaneHou/os-frp/main/docker/client/docker-compose.yml
curl -fSLO https://raw.githubusercontent.com/DaneHou/os-frp/main/docker/.env.example
mkdir -p config
curl -fSL https://raw.githubusercontent.com/DaneHou/os-frp/main/docker/client/config/frpc.toml.example -o config/frpc.toml

# Edit config — set server IP and auth token
nano config/frpc.toml

# Copy and edit env
cp .env.example .env

# Run
docker compose up -d
```

**What you get out of the box:**
- TCP Fast Open + BBR + fq pacing + 4MB buffer tuning (automatic via sysctl)
- Watchdog with exponential backoff reconnection (0.1s → 30s)
- Docker HEALTHCHECK on frpc/frps process + admin API
- Optional: Hysteria 2, shadow-TLS, QUIC/TCP auto-switching (see [Advanced Features](#advanced-features))

### Option B: OPNsense Plugin

On OPNsense (FreeBSD):

```bash
cd /root
git clone https://github.com/DaneHou/os-frp.git
cd os-frp
make install          # Plugin files + FRP binaries + activate
```

Then go to **Services > FRP Tunnel** in the web GUI.

**Update:**
```bash
cd /root/os-frp && git pull && make uninstall && make install
```

> Always `make uninstall` before `make install` to clear stale PHP files.

**Uninstall:**
```bash
cd /root/os-frp && make uninstall
```

## OPNsense GUI Pages

| Page | URL | Purpose |
|------|-----|---------|
| Client | `/ui/frp/client` | frpc settings + proxy management |
| Server | `/ui/frp/server` | frps settings |
| Monitor | `/ui/frp/monitor` | Real-time speed, traffic history, health checks |

### Client Setup (China side)

1. **Services > FRP Tunnel > Client**
   - Enable, set Server Address / Port / Auth Token
   - Click **Save** (auto-reconfigures)

2. Add proxies in the **Proxies** section below:
   - Example: Name=`web`, Type=`tcp`, Local=`127.0.0.1:80`, Remote=`8080`
   - Click **Save**, then **Apply**

3. Optional: expand **Advanced > Network Tuning**
   - Enable BBR, TCP Fast Open, TCP Buffer Tuning
   - Enable MSS Clamping (1260) if cross-border MTU issues

### Server Setup (US side)

1. **Services > FRP Tunnel > Server**
   - Enable, set Bind Port, Auth Token (same as client)
   - Optionally enable Web Dashboard (port 7500)
   - Click **Save**

### Docker Config Export

If one side is OPNsense and the other is Docker:
- Server page → **Export Docker Client Config** (generates `frpc.toml` for the Docker peer)
- Client page → **Export Docker Server Config** (generates `frps.toml` for the Docker peer)

### Monitoring

The **Monitor** page shows:
- Real-time speed (in/out) with per-proxy breakdown
- Historical traffic charts (1h / 24h / 7d / 30d / 1yr)
- Per-proxy statistics table (today, 7-day, 30-day totals)
- Health check with configurable targets (latency, HTTP status)
- Health latency history chart (1h / 24h / 7d trends)

> Requires **Admin Dashboard** enabled in Client or Server advanced settings.

## Features

| Feature | OPNsense | Docker |
|---------|----------|--------|
| FRP Client/Server | GUI config | TOML config |
| Proxy Management | Bootgrid CRUD | Edit TOML |
| Transport Protocols | TCP, WebSocket, WSS, KCP, QUIC | Same |
| TCP BBR | Toggle in GUI | Automatic |
| TCP Fast Open | Toggle in GUI | Automatic |
| TCP Buffer Tuning (4MB) | Toggle in GUI | Automatic |
| MSS Clamping | Toggle in GUI | N/A (host network) |
| Watchdog (auto-restart) | Cron every 1min | Exponential backoff |
| Traffic Monitoring | Chart.js dashboard | Via FRP admin API |
| Health Checks | Latency history + chart | Docker HEALTHCHECK |
| Hysteria 2 | Not available | `HYSTERIA2_ENABLED=true` |
| shadow-TLS (GFW evasion) | Not available | `SHADOW_TLS_ENABLED=true` |
| QUIC/TCP auto-switching | Not available | Transport probe script |
| Docker peer config export | Export button in GUI | N/A |

## Advanced Features

### Hysteria 2 (Docker only)

[Hysteria 2](https://v2.hysteria.network/) runs as a parallel QUIC-based tunnel alongside FRP, using Brutal congestion control optimized for lossy networks.

```bash
# Copy example config
cp config/hysteria2.yaml.example config/hysteria2.yaml
# Edit with your server details
nano config/hysteria2.yaml

# Enable in docker-compose environment:
HYSTERIA2_ENABLED=true
```

Both client and server Docker images include Hysteria 2.

### shadow-TLS (Docker only, GFW evasion)

[shadow-TLS](https://github.com/ihciah/shadow-tls) wraps FRP traffic to look like normal HTTPS connections (e.g., to `www.microsoft.com`), defeating GFW deep packet inspection.

```
frpc → shadow-tls-client:1234 ═══internet═══> shadow-tls-server:443 → frps:7000
       (looks like HTTPS to microsoft.com)
```

**Client side** (`docker-compose.yml` environment):
```yaml
- SHADOW_TLS_ENABLED=true
- SHADOW_TLS_SERVER=your-us-server:443
- SHADOW_TLS_PASSWORD=your-shared-secret
- SHADOW_TLS_SNI=www.microsoft.com
- SHADOW_TLS_LISTEN=127.0.0.1:1234
```

**Server side:**
```yaml
- SHADOW_TLS_ENABLED=true
- SHADOW_TLS_LISTEN=0.0.0.0:443
- SHADOW_TLS_PASSWORD=your-shared-secret
- SHADOW_TLS_SNI=www.microsoft.com
- SHADOW_TLS_BACKEND=127.0.0.1:7000
```

When shadow-TLS is enabled, set `serverAddr = "127.0.0.1"` and `serverPort = 1234` in `frpc.toml`.

### QUIC vs TCP Auto-Switching (Docker client only)

The transport probe script runs every 5 minutes, testing TCP and QUIC latency to the server. After 3 consecutive probes favor one protocol, the watchdog switches `frpc.toml` on next restart. Requires `FRP_SERVER_ADDR`, `FRP_QUIC_PORT` environment variables.

## Transport Protocols

| Protocol | Underlying | GFW Resistance | Speed | Notes |
|----------|-----------|----------------|-------|-------|
| **TCP** | TCP | Low | Baseline | Default. Easy to fingerprint |
| **WebSocket** | TCP | Medium | ~TCP | Looks like HTTP upgrade |
| **WSS** | TCP+TLS | **High** | ~TCP | Looks like HTTPS. **Best for GFW evasion** |
| **KCP** | UDP | Medium-High | **Fastest** | Trades bandwidth for latency |
| **QUIC** | UDP | Medium-High | Fast | Built-in TLS 1.3, 0-RTT reconnect |

**Recommendation:** Start with **WSS**. If slow on lossy links, try **QUIC** or **KCP**. If ISP throttles UDP, stick with WSS. For maximum GFW resistance, use **shadow-TLS** (Docker).

## Network Tuning

| Setting | What it does | OPNsense | Docker |
|---------|-------------|----------|--------|
| TCP BBR | Modern congestion control, better throughput on lossy links | `kldload tcp_bbr` | `sysctl tcp_congestion_control=bbr` |
| TCP Fast Open | Skip 1 RTT on connection setup | `sysctl net.inet.tcp.fastopen` | `echo 3 > tcp_fastopen` |
| TCP Buffers 4MB | Large windows for high BDP links (100Mbps × 200ms RTT) | `sysctl recvbuf_max/sendbuf_max` | `echo ... > tcp_rmem/tcp_wmem` |
| SACK | Selective acknowledgment, reduces retransmission | `sysctl sack.enable` | `echo 1 > tcp_sack` |
| fq pacing | Fair queue + BBR pacing, prevents burst losses | N/A | `tc qdisc fq pacing` |
| MSS Clamping | Fix MTU issues on cross-border PPPoE links | pf anchor `frp_mss` | N/A |

## How It Works

### Config Generation (OPNsense)

```
User saves in GUI → API validates → config.xml → template engine → TOML config → configd restarts frp
```

| Template | Output | Purpose |
|----------|--------|---------|
| `frpc.toml` | `/usr/local/etc/frp/frpc.toml` | frpc configuration |
| `frps.toml` | `/usr/local/etc/frp/frps.toml` | frps configuration |
| `frp_rc` | `/etc/rc.conf.d/frp` | rc.d enable flag + mode |

### Docker Watchdog

```
entrypoint.sh → sysctl tuning → watchdog.sh
                                  ├── shadow-tls (if enabled)
                                  ├── hysteria2 (if enabled)
                                  └── frpc/frps (with exponential backoff)
```

## API Routes (OPNsense)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/frp/settings/getClient` | Get client settings |
| POST | `/api/frp/settings/setClient` | Save client settings |
| GET | `/api/frp/settings/getServer` | Get server settings |
| POST | `/api/frp/settings/setServer` | Save server settings |
| GET | `/api/frp/settings/exportDockerConfig?mode=client\|server` | Export Docker peer config |
| POST | `/api/frp/proxy/searchItem` | List proxies |
| POST | `/api/frp/proxy/addItem` | Add proxy |
| POST | `/api/frp/service/reconfigure` | Apply config + restart |
| POST | `/api/frp/service/status` | Service status |
| GET | `/api/frp/monitor/realtime` | Real-time speed data |
| GET | `/api/frp/monitor/history` | Historical traffic |
| GET | `/api/frp/monitor/summary` | Dashboard summary |
| GET | `/api/frp/monitor/healthcheck` | Run health checks |
| GET | `/api/frp/monitor/healthHistory` | Health latency history |

## File Structure

```
os-frp/
├── Makefile                              # OPNsense install/uninstall
├── README.md
├── LICENSE                               # BSD-2-Clause
├── .github/workflows/
│   └── docker-build.yml                  # CI: build + push Docker images
├── docker/                               # Docker deployment
│   ├── .env.example
│   ├── docker-compose.example.yml        # Pre-built image compose
│   ├── client/
│   │   ├── Dockerfile
│   │   ├── docker-compose.yml            # Build-from-source compose
│   │   └── config/
│   │       ├── frpc.toml.example
│   │       ├── hysteria2.yaml.example
│   │       └── shadow-tls.env.example
│   ├── server/
│   │   ├── Dockerfile
│   │   ├── docker-compose.yml
│   │   └── config/
│   │       ├── frps.toml.example
│   │       ├── hysteria2-server.yaml.example
│   │       └── shadow-tls.env.example
│   └── shared/
│       ├── entrypoint.sh                 # TCP tuning + launch watchdog
│       └── scripts/
│           ├── watchdog.sh               # Process manager + backoff
│           ├── healthcheck.sh            # Docker HEALTHCHECK
│           └── transport_probe.sh        # QUIC vs TCP auto-switching
└── src/                                  # OPNsense plugin
    ├── etc/inc/plugins.inc.d/frp.inc     # Plugin hooks + cron
    ├── opnsense/
    │   ├── mvc/app/
    │   │   ├── controllers/OPNsense/Frp/
    │   │   │   ├── ClientController.php
    │   │   │   ├── ServerController.php
    │   │   │   ├── Api/
    │   │   │   │   ├── SettingsController.php
    │   │   │   │   ├── ProxyController.php
    │   │   │   │   ├── ServiceController.php
    │   │   │   │   └── MonitorController.php
    │   │   │   └── forms/
    │   │   │       ├── client.xml
    │   │   │       ├── server.xml
    │   │   │       └── proxy.xml
    │   │   ├── models/OPNsense/Frp/
    │   │   │   ├── Client.xml / Client.php
    │   │   │   ├── Server.xml / Server.php
    │   │   │   ├── ACL/ACL.xml
    │   │   │   └── Menu/Menu.xml
    │   │   └── views/OPNsense/Frp/
    │   │       ├── client.volt
    │   │       ├── server.volt
    │   │       └── monitor.volt
    │   ├── scripts/OPNsense/Frp/
    │   │   ├── setup.sh                  # Binary download
    │   │   ├── apply_tuning.sh           # BBR/TFO/TCP/MSS
    │   │   ├── watchdog.sh               # Process watchdog
    │   │   └── traffic_collector.php     # Traffic + health metrics
    │   └── service/
    │       ├── conf/actions.d/actions_frp.conf
    │       └── templates/OPNsense/Frp/
    │           ├── frpc.toml
    │           ├── frps.toml
    │           └── frp_rc
    └── usr/local/etc/rc.d/frp
```

## Troubleshooting

### Menu doesn't appear after install
```bash
make activate   # Clears caches + restarts webgui
```
Then Ctrl+Shift+R in browser.

### "Endpoint not found" errors
```bash
make uninstall && make install   # Clean install
```

### Check logs
```bash
# OPNsense
cat /var/log/frp/frpc.log
cat /var/log/frp/frps.log
cat /var/log/frp/watchdog.log

# Docker
docker compose logs -f
docker compose exec frp-client cat /var/log/frp/watchdog.log
```

### Check generated config
```bash
# OPNsense
cat /usr/local/etc/frp/frpc.toml
cat /usr/local/etc/frp/frps.toml

# Docker
docker compose exec frp-client cat /etc/frp/frpc.toml
```

### Manual service control (OPNsense)
```bash
configctl frp start
configctl frp stop
configctl frp restart
configctl frp status
```

## Binary Versions

| Binary | Version | Source |
|--------|---------|--------|
| frpc/frps | v0.67.0 | [fatedier/frp](https://github.com/fatedier/frp) |
| Hysteria 2 | v2.5.1 | [apernet/hysteria](https://github.com/apernet/hysteria) (Docker only) |
| shadow-TLS | v0.2.25 | [ihciah/shadow-tls](https://github.com/ihciah/shadow-tls) (Docker only) |

## License

[BSD-2-Clause](LICENSE)
