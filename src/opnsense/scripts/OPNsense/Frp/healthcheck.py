#!/usr/local/bin/python3

"""
configd: configctl frp healthcheck

Read-only health summary in the os-netbaseline plugin health contract:
{"checks": [{"name", "ok": true|false|null, "severity", "detail"}]}.

* frpc / frps enabled -> its process is running (rc.d pidfile)
* the frp admin API the Monitor page already uses (webServer, only when it
  listens on localhost): proxies that are not running (frpc) / offline (frps)

The admin API user/password are read from config.xml into memory for the
HTTP Basic header only; tokens and passwords are never printed. Only
127.0.0.1 is ever contacted.
"""

import base64
import json
import os
import subprocess
import sys
import urllib.request
import xml.etree.ElementTree as ET

CONFIG_XML = '/conf/config.xml'
PIDFILE = '/var/run/frp.pid'
PS = '/bin/ps'
API_TIMEOUT = 2
LOCAL_ADDRS = ('', '127.0.0.1', 'localhost', '0.0.0.0', '::', '::1', '[::]', '[::1]')
PROXY_TYPES = ('tcp', 'udp', 'http', 'https', 'stcp', 'sudp', 'xtcp', 'tcpmux')
MAX_PROXY_CHECKS = 20


def read_settings(config_xml=CONFIG_XML):
    """-> {'client': {...}, 'server': {...}} with whitelisted fields (credentials stay in memory)."""
    root = ET.parse(config_xml).getroot()
    out = {}
    for side in ('client', 'server'):
        base = root.find('OPNsense/frp/' + side)
        if base is None:
            out[side] = {'enabled': False}
            continue
        out[side] = {
            'enabled': (base.findtext('enabled') or '0').strip() == '1',
            'web': (base.findtext('webServerEnabled') or '0').strip() == '1',
            'addr': (base.findtext('webServerAddr') or '127.0.0.1').strip(),
            'port': (base.findtext('webServerPort') or ('7400' if side == 'client' else '7500')).strip(),
            'user': base.findtext('webServerUser') or '',
            'password': base.findtext('webServerPassword') or '',
            'proxies': [(p.findtext('name') or '').strip() for p in base.findall('proxies/proxy')
                        if (p.findtext('enabled') or '1').strip() == '1' and (p.findtext('name') or '').strip()],
        }
    return out


def process_name(pidfile=PIDFILE, runner=subprocess.run):
    """-> command name of the process in the rc.d pidfile, '' when it is not running."""
    try:
        with open(pidfile) as f:
            pid = int(f.read().strip())
        os.kill(pid, 0)
    except (OSError, ValueError):
        return ''
    try:
        res = runner([PS, '-p', str(pid), '-o', 'comm='], capture_output=True, text=True, timeout=3)
    except (OSError, subprocess.TimeoutExpired):
        return ''
    return (res.stdout or '').strip()


def http_get(port, path, user, password):
    """GET http://127.0.0.1:<port><path> with Basic auth -> parsed JSON (raises on any error)."""
    req = urllib.request.Request('http://127.0.0.1:%d%s' % (port, path))
    if user:
        token = base64.b64encode(('%s:%s' % (user, password)).encode('utf-8')).decode('ascii')
        req.add_header('Authorization', 'Basic ' + token)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))     # never via an HTTP proxy
    with opener.open(req, timeout=API_TIMEOUT) as resp:
        return json.loads(resp.read(1024 * 1024).decode('utf-8', 'replace'))


def _api_target(cfg):
    """-> port when the admin API may be queried, else (None, reason)."""
    if not cfg.get('web'):
        return None, 'admin API (webServer) disabled: proxy status not checked'
    if cfg.get('addr', '').lower() not in LOCAL_ADDRS:
        return None, 'admin API not on localhost: proxy status not checked'
    try:
        port = int(cfg.get('port') or 0)
    except ValueError:
        port = 0
    if not 0 < port < 65536:
        return None, 'admin API port invalid'
    return port, ''


def client_proxy_checks(cfg, get):
    port, reason = _api_target(cfg)
    if port is None:
        return [{'name': 'frpc proxies', 'ok': None, 'severity': 'info', 'detail': reason}]
    try:
        status = get(port, '/api/status', cfg['user'], cfg['password'])
    except Exception as e:      # noqa: BLE001 - any failure is one check
        return [{'name': 'frpc admin API', 'ok': False, 'severity': 'low',
                 'detail': 'not reachable on 127.0.0.1:%d (%s)' % (port, type(e).__name__)}]
    seen, checks = {}, []
    for ptype, items in (status.items() if isinstance(status, dict) else []):
        for item in items if isinstance(items, list) else []:
            if isinstance(item, dict) and item.get('name'):
                seen[str(item['name'])] = (str(ptype), str(item.get('status', '')), str(item.get('err', '')))
    bad = []
    for name, (ptype, st, err) in sorted(seen.items()):
        if st != 'running':
            bad.append(name)
            if len(checks) < MAX_PROXY_CHECKS:
                checks.append({'name': 'frpc proxy %s' % name[:40], 'ok': False, 'severity': 'medium',
                               'detail': '%s proxy status "%s"%s' % (ptype, st or 'unknown',
                                                                     (': ' + err[:100]) if err else '')})
    for name in cfg.get('proxies') or []:
        known = name in seen or any(n.endswith('.' + name) for n in seen)     # "<user>.<name>" with frpc user
        if not known and len(checks) < MAX_PROXY_CHECKS:
            bad.append(name)
            checks.append({'name': 'frpc proxy %s' % name[:40], 'ok': False, 'severity': 'medium',
                           'detail': 'configured but not known to frpc (Apply / restart needed?)'})
    checks.insert(0, {'name': 'frpc proxies', 'ok': not bad, 'severity': 'medium',
                      'detail': '%d running, %d not running' % (len(seen) - len([n for n in bad if n in seen]),
                                                                  len(bad))})
    return checks


def server_proxy_checks(cfg, get):
    port, reason = _api_target(cfg)
    if port is None:
        return [{'name': 'frps proxies', 'ok': None, 'severity': 'info', 'detail': reason}]
    try:
        info = get(port, '/api/serverinfo', cfg['user'], cfg['password'])
        counts = info.get('proxyTypeCount') if isinstance(info, dict) else None
        # only the proxy types that have proxies (frps logs every API call), like the Monitor page
        types = [t for t in PROXY_TYPES if (counts or {}).get(t)] if isinstance(counts, dict) else list(PROXY_TYPES)
        proxies = []
        for t in types:
            data = get(port, '/api/proxy/%s' % t, cfg['user'], cfg['password'])
            for p in (data.get('proxies') if isinstance(data, dict) else None) or []:
                if isinstance(p, dict) and p.get('name'):
                    proxies.append((t, str(p['name']), str(p.get('status', '')), str(p.get('lastCloseTime') or '')))
    except Exception as e:      # noqa: BLE001
        return [{'name': 'frps admin API', 'ok': False, 'severity': 'low',
                 'detail': 'not reachable on 127.0.0.1:%d (%s)' % (port, type(e).__name__)}]
    offline = [p for p in proxies if p[2] != 'online']
    clients = info.get('clientCounts') if isinstance(info, dict) else None
    checks = [{'name': 'frps proxies', 'ok': True, 'severity': 'info',
               'detail': '%d online, %d offline, %s client(s) connected' % (
                   len(proxies) - len(offline), len(offline), clients if clients is not None else '?')}]
    # an offline proxy on frps = the remote frpc that registered it is gone (frps keeps it listed
    # until restart, also after a rename on the client): low
    for t, name, st, closed in sorted(offline, key=lambda p: p[1])[:MAX_PROXY_CHECKS]:
        checks.append({'name': 'frps proxy %s' % name[:40], 'ok': False, 'severity': 'low',
                       'detail': '%s proxy %s%s' % (t, st or 'offline', (' since ' + closed[:20]) if closed else '')})
    return checks


def build(config_xml=CONFIG_XML, pidfile=PIDFILE, runner=subprocess.run, get=http_get):
    try:
        cfg = read_settings(config_xml)
    except (OSError, ET.ParseError):
        return {'checks': [{'name': 'configuration', 'ok': None, 'severity': 'low', 'detail': 'config.xml not readable'}]}
    # rc.d runs one mode: client when enabled, else server (frp_rc template)
    if cfg['client']['enabled']:
        mode, side = 'frpc', 'client'
    elif cfg['server']['enabled']:
        mode, side = 'frps', 'server'
    else:
        return {'checks': []}
    running = process_name(pidfile, runner)
    checks = [{'name': '%s running' % mode, 'ok': running == mode, 'severity': 'medium',
               'detail': 'running' if running == mode else (
                   'not running' if not running else 'pidfile belongs to %s, not %s' % (running[:20], mode))}]
    if running == mode:
        checks += (client_proxy_checks if side == 'client' else server_proxy_checks)(cfg[side], get)
    if cfg['client']['enabled'] and cfg['server']['enabled']:
        checks.append({'name': 'frps running', 'ok': None, 'severity': 'info',
                       'detail': 'client and server both enabled: only frpc is started'})
    return {'checks': checks}


def main():
    print(json.dumps(build()))
    return 0


if __name__ == '__main__':
    sys.exit(main())
