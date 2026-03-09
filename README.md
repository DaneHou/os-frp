# os-frp

OPNsense plugin for [FRP](https://github.com/fatedier/frp) (Fast Reverse Proxy) — native FreeBSD, no Docker.

Designed for **cross-border tunnel stability** (e.g., China-US) with built-in transport optimizations and network tuning.

## Architecture

```
China OPNsense (frpc)              US OPNsense (frps)
┌──────────────────────┐           ┌──────────────────┐
│ frpc ──── FRP tunnel ──────────→ frps               │
│ BBR / MTU / MSS      │           │        → WAN exit │
└──────────────────────┘           └──────────────────┘
```

- **China side**: frpc (client) + proxy entries + network tuning
- **US side**: frps (server) only, traffic exits to internet
- **Shadowsocks**: use [os-shadowsocks](https://github.com/DaneHou/os-shadowsocks) separately if needed

## Features

| Feature | Description |
|---------|-------------|
| FRP Client (frpc) | Full TOML v0.60+ config via GUI |
| FRP Server (frps) | With optional web dashboard |
| Proxy Management | tcp, udp, http, https, stcp, xtcp, sudp, tcpmux |
| Cross-border Optimizations | tcpMux, heartbeat tuning, TLS, connection pooling |
| Network Tuning | TCP BBR, MTU clamping, MSS clamping (pf anchor) |
| Binary Management | Auto-download frpc/frps from GitHub releases |

## Installation

On OPNsense (FreeBSD), clone and install:

```bash
cd /root
git clone https://github.com/DaneHou/os-frp.git
cd os-frp

# Full install: plugin files + FRP binaries
make install

# Or step by step:
make install-plugin   # Install MVC files, templates, hooks, rc.d
make install-frp      # Download frpc/frps v0.61.1
make activate         # Clear caches, restart webgui + configd
```

After install, navigate to **Services > FRP Tunnel** in the OPNsense web GUI.

## Updating

```bash
cd /root/os-frp
git pull
make uninstall
make install
```

> **Important**: Always `make uninstall` before `make install` to remove stale PHP files that break OPNsense's class autoloader.

## Uninstalling

```bash
cd /root/os-frp
make uninstall
```

This removes all plugin files, configs, PID files, logs, and restarts the web GUI.

## Menu Pages

| Page | URL | Purpose |
|------|-----|---------|
| Client | `/ui/frp/client` | frpc settings (server address, auth, transport) |
| Server | `/ui/frp/server` | frps settings (bind, auth, dashboard, vhost) |
| Proxies | `/ui/frp/proxy` | Manage tunnel entries (CRUD table) |
| Tuning | `/ui/frp/tuning` | BBR, MTU clamping, MSS clamping |

## Usage

### Client Setup (China side)

1. **Services > FRP Tunnel > Client**
   - Enable FRP Client
   - Set Server Address to your US OPNsense IP
   - Set Server Port (default 7000)
   - Set Authentication Token (must match server)
   - Transport settings are pre-tuned for cross-border (tcpMux ON, heartbeat 10s, TLS ON)
   - Click **Save**

2. **Services > FRP Tunnel > Proxies**
   - Click **+** to add a proxy entry
   - Example: Name=`ss`, Type=`tcp`, Local IP=`127.0.0.1`, Local Port=`8388`, Remote Port=`8388`
   - Click **Save**, then **Apply**

3. **Services > FRP Tunnel > Tuning** (optional)
   - Enable BBR for better congestion control
   - Set MTU to 1300 on WAN interface
   - Set MSS clamp to 1260 on WAN interface
   - Click **Save & Apply**

### Server Setup (US side)

1. **Services > FRP Tunnel > Server**
   - Enable FRP Server
   - Set Bind Port (default 7000)
   - Set same Authentication Token as client
   - Optionally enable Web Dashboard (port 7500)
   - Click **Save**

## How It Works

### Data Flow

```
User saves in GUI
    → API controller validates & saves to config.xml
    → Click Apply triggers /api/frp/service/reconfigure
    → OPNsense template engine generates TOML config from config.xml
    → configd restarts frpc/frps with new config
```

### Config Generation

OPNsense's template engine (Jinja2) reads model data from `config.xml` and generates:

| Template | Output | Purpose |
|----------|--------|---------|
| `frpc.toml` | `/usr/local/etc/frp/frpc.toml` | frpc configuration |
| `frps.toml` | `/usr/local/etc/frp/frps.toml` | frps configuration |
| `frp_rc` | `/etc/rc.conf.d/frp` | rc.d enable flag + mode (client/server) |

### MVC Structure

```
Models (config.xml schema)     API Controllers              UI Controllers
┌─────────────┐                ┌──────────────────────┐     ┌──────────────────┐
│ Client.xml  │◄──────────────│ SettingsController    │     │ ClientController │
│  + proxies  │                │  getClient/setClient  │     │ ServerController │
├─────────────┤                │  getServer/setServer  │     │ ProxyController  │
│ Server.xml  │◄──────────────│  getTuning/setTuning  │     │ TuningController │
├─────────────┤                ├──────────────────────┤     └──────────────────┘
│ Tuning.xml  │                │ ProxyController      │
└─────────────┘                │  searchItem/CRUD     │
                               ├──────────────────────┤
                               │ ServiceController    │
                               │  reconfigure/status  │
                               └──────────────────────┘
```

- **Models**: 3 separate XML schemas (Client includes proxies ArrayField)
- **API SettingsController**: Single controller for all flat settings (avoids name collision with UI controllers)
- **API ProxyController**: CRUD for proxy ArrayField entries
- **API ServiceController**: Service start/stop/restart/reconfigure (must be named `ServiceController` for `updateServiceControlUI()`)
- **UI Controllers**: One per page, renders volt template with form

### Network Tuning

| Setting | Implementation | Notes |
|---------|---------------|-------|
| TCP BBR | `kldload tcp_bbr` + `sysctl net.inet.tcp.functions_default=bbr` | FreeBSD kernel module |
| MTU Clamp | `ifconfig <iface> mtu <value>` | Applied to resolved OPNsense interface |
| MSS Clamp | `pfctl -a frp_mss -f -` with scrub rule | Uses pf anchor, doesn't touch main ruleset |

### Cross-border Transport Defaults

| Setting | Default | Why |
|---------|---------|-----|
| tcpMux | ON | Multiplexes connections over single TCP stream |
| tcpMuxKeepalive | 10s | Keeps GFW from killing idle connections |
| heartbeatInterval | 10s | Fast detection of tunnel loss |
| heartbeatTimeout | 30s | Reasonable timeout before reconnect |
| TLS | ON | Encrypts tunnel metadata |
| loginFailExit | OFF | Auto-retry on auth failure (network blips) |
| poolCount | 5 | Pre-established connections reduce latency |

## Binary Versions

| Binary | Version | Source |
|--------|---------|--------|
| frpc/frps | v0.61.1 | [fatedier/frp](https://github.com/fatedier/frp) |

Binaries are installed to `/usr/local/bin/` (FreeBSD amd64).

## File Structure

```
os-frp/
├── Makefile                           # install/uninstall/activate
├── pkg-descr                          # Package description
├── README.md                          # This file
└── src/
    ├── etc/inc/plugins.inc.d/
    │   └── frp.inc                    # Plugin hooks (services, syslog)
    ├── opnsense/
    │   ├── mvc/app/
    │   │   ├── controllers/OPNsense/Frp/
    │   │   │   ├── ClientController.php       # UI: client page
    │   │   │   ├── ServerController.php       # UI: server page
    │   │   │   ├── ProxyController.php        # UI: proxy page
    │   │   │   ├── TuningController.php       # UI: tuning page
    │   │   │   ├── Api/
    │   │   │   │   ├── SettingsController.php # API: get/set all settings
    │   │   │   │   ├── ProxyController.php    # API: proxy CRUD
    │   │   │   │   └── ServiceController.php  # API: service control
    │   │   │   └── forms/
    │   │   │       ├── client.xml             # Client form fields
    │   │   │       ├── server.xml             # Server form fields
    │   │   │       ├── proxy.xml              # Proxy dialog fields
    │   │   │       └── tuning.xml             # Tuning form fields
    │   │   ├── models/OPNsense/Frp/
    │   │   │   ├── Client.php / Client.xml    # Client + proxies model
    │   │   │   ├── Server.php / Server.xml    # Server model
    │   │   │   ├── Tuning.php / Tuning.xml    # Tuning model
    │   │   │   ├── ACL/ACL.xml                # Access control
    │   │   │   └── Menu/Menu.xml              # Services menu
    │   │   └── views/OPNsense/Frp/
    │   │       ├── client.volt                # Client settings page
    │   │       ├── server.volt                # Server settings page
    │   │       ├── proxy.volt                 # Proxy bootgrid page
    │   │       └── tuning.volt                # Tuning page
    │   ├── scripts/OPNsense/Frp/
    │   │   ├── setup.sh                       # Binary download script
    │   │   └── apply_tuning.sh                # BBR/MTU/MSS script
    │   └── service/
    │       ├── conf/actions.d/
    │       │   └── actions_frp.conf           # configd actions
    │       └── templates/OPNsense/Frp/
    │           ├── +TARGETS                   # Template → file mapping
    │           ├── frpc.toml                  # frpc config template
    │           ├── frps.toml                  # frps config template
    │           └── frp_rc                     # rc.conf.d template
    └── usr/local/etc/rc.d/
        └── frp                                # rc.d service script
```

## Troubleshooting

### Menu doesn't appear after install
```bash
make activate   # Clears caches + restarts webgui
```
Then Ctrl+Shift+R in the browser.

### "Endpoint not found" errors
Old PHP files from previous installs cached by opcache:
```bash
make uninstall
make install    # Clean install with activate
```

### Check FRP logs
```bash
cat /var/log/frp/frpc.log   # Client log
cat /var/log/frp/frps.log   # Server log
```

### Check generated config
```bash
cat /usr/local/etc/frp/frpc.toml
cat /usr/local/etc/frp/frps.toml
```

### Manual service control
```bash
configctl frp start
configctl frp stop
configctl frp restart
configctl frp status
```

## License

BSD-2-Clause
