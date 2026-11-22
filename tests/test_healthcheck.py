"""configctl frp healthcheck: os-netbaseline plugin health contract, read-only, no secrets."""

import configparser
import json
import os
import types

import pytest

import healthcheck

ROOT = os.path.join(os.path.dirname(__file__), '..')
ACTIONS = os.path.join(ROOT, 'src', 'opnsense', 'service', 'conf', 'actions.d', 'actions_frp.conf')
TOKEN = 'FAKE-frp-token-6f1c'
PASSWORD = 'FAKE-dash-pass-91ab'

CONFIG = """<opnsense><OPNsense><frp>
  <client><enabled>{client}</enabled><serverAddr>203.0.113.5</serverAddr><authToken>{token}</authToken>
    <webServerEnabled>{cweb}</webServerEnabled><webServerAddr>{caddr}</webServerAddr><webServerPort>7400</webServerPort>
    <webServerUser>admin</webServerUser><webServerPassword>{password}</webServerPassword>
    <proxies>
      <proxy uuid="1"><enabled>1</enabled><name>ssh</name><proxyType>tcp</proxyType></proxy>
      <proxy uuid="2"><enabled>1</enabled><name>web</name><proxyType>http</proxyType></proxy>
      <proxy uuid="3"><enabled>0</enabled><name>old</name><proxyType>tcp</proxyType></proxy>
    </proxies>
  </client>
  <server><enabled>{server}</enabled><authToken>{token}</authToken>
    <webServerEnabled>1</webServerEnabled><webServerAddr>127.0.0.1</webServerAddr><webServerPort>7500</webServerPort>
    <webServerUser>admin</webServerUser><webServerPassword>{password}</webServerPassword>
  </server>
</frp></OPNsense></opnsense>"""

CLIENT_STATUS = {'tcp': [{'name': 'ssh', 'type': 'tcp', 'status': 'running', 'err': ''}],
                 'http': [{'name': 'web', 'type': 'http', 'status': 'start error', 'err': 'port already used'}]}
SERVER = {'/api/serverinfo': {'version': '0.67.0', 'clientCounts': 1, 'proxyTypeCount': {'tcp': 2, 'udp': 0}},
          '/api/proxy/tcp': {'proxies': [{'name': 'rustdesk', 'status': 'online', 'lastCloseTime': ''},
                                         {'name': 'ss-back', 'status': 'offline', 'lastCloseTime': '11-21 10:00:00'}]}}


class Api:
    def __init__(self, routes):
        self.routes = routes
        self.calls = []

    def __call__(self, port, path, user, password):
        self.calls.append((port, path))
        assert user == 'admin' and password == PASSWORD
        if isinstance(self.routes, Exception):
            raise self.routes
        return self.routes[path]


def setup(tmp_path, client='1', server='0', cweb='1', caddr='127.0.0.1', proc='frpc'):
    cfg = tmp_path / 'config.xml'
    cfg.write_text(CONFIG.format(client=client, server=server, cweb=cweb, caddr=caddr, token=TOKEN, password=PASSWORD))
    pid = tmp_path / 'frp.pid'
    pid.write_text(str(os.getpid()))

    def runner(argv, **kw):
        assert argv[:2] == [healthcheck.PS, '-p']
        return types.SimpleNamespace(returncode=0, stdout=proc + '\n')
    return str(cfg), str(pid), runner


def run(tmp_path, api, **kw):
    cfg, pid, runner = setup(tmp_path, **kw)
    out = healthcheck.build(cfg, pid, runner, api)
    text = json.dumps(out)
    assert TOKEN not in text and PASSWORD not in text and '203.0.113.5' not in text
    for c in out['checks']:
        assert set(c) == {'name', 'ok', 'severity', 'detail'}, c
        assert c['ok'] in (True, False, None) and c['severity'] in ('medium', 'low', 'info')
    assert len({c['name'] for c in out['checks']}) == len(out['checks'])
    return {c['name']: c for c in out['checks']}, out


def test_action_is_parameterless_script_output():
    cp = configparser.ConfigParser(interpolation=None)
    cp.read(ACTIONS)
    hc = cp['healthcheck']
    assert hc['type'] == 'script_output' and not hc.get('parameters', '').strip()
    local = hc['command'].replace('/usr/local/opnsense', os.path.join(ROOT, 'src', 'opnsense'))
    assert open(local).read().startswith('#!/usr/local/bin/python3')
    assert 'Frp/*.py $(SCRIPTS_DIR)/' in open(os.path.join(ROOT, 'Makefile')).read()


def test_client_running_with_failed_and_missing_proxies(tmp_path):
    status = json.loads(json.dumps(CLIENT_STATUS))
    c, _ = run(tmp_path, Api({'/api/status': status}))
    assert c['frpc running']['ok'] is True
    assert c['frpc proxy web'] == {'name': 'frpc proxy web', 'ok': False, 'severity': 'medium',
                                   'detail': 'http proxy status "start error": port already used'}
    assert c['frpc proxies']['ok'] is False and c['frpc proxies']['detail'] == '1 running, 1 not running'
    assert 'frpc proxy ssh' not in c and 'frpc proxy old' not in c       # running / disabled
    del status['tcp']
    (tmp_path / 'b').mkdir()
    c, _ = run(tmp_path / 'b', Api({'/api/status': status}))
    assert 'not known to frpc' in c['frpc proxy ssh']['detail']


def test_client_user_prefixed_names(tmp_path):
    status = {'tcp': [{'name': 'me.ssh', 'status': 'running'}], 'http': [{'name': 'me.web', 'status': 'running'}]}
    c, _ = run(tmp_path, Api({'/api/status': status}))
    assert c['frpc proxies']['ok'] is True and len(c) == 2


def test_api_not_queried_when_disabled_or_not_local(tmp_path):
    api = Api({})
    c, _ = run(tmp_path, api, cweb='0')
    assert c['frpc proxies']['ok'] is None and api.calls == []
    (tmp_path / 'b').mkdir()
    c, _ = run(tmp_path / 'b', api, caddr='192.168.1.50')
    assert c['frpc proxies']['ok'] is None and 'not on localhost' in c['frpc proxies']['detail'] and api.calls == []


def test_api_unreachable_is_low(tmp_path):
    c, _ = run(tmp_path, Api(OSError('refused')))
    assert c['frpc admin API']['ok'] is False and c['frpc admin API']['severity'] == 'low'


def test_process_not_running(tmp_path):
    cfg, pid, runner = setup(tmp_path)
    os.remove(pid)
    out = healthcheck.build(cfg, pid, runner, Api({}))
    assert out['checks'] == [{'name': 'frpc running', 'ok': False, 'severity': 'medium', 'detail': 'not running'}]
    (tmp_path / 'b').mkdir()
    c, _ = run(tmp_path / 'b', Api({}), proc='sshd')
    assert c['frpc running']['ok'] is False and 'sshd' in c['frpc running']['detail']


def test_server_offline_proxies_are_low_and_only_used_types_queried(tmp_path):
    api = Api(SERVER)
    c, _ = run(tmp_path, api, client='0', server='1', proc='frps')
    assert c['frps running']['ok'] is True
    assert c['frps proxies']['detail'] == '1 online, 1 offline, 1 client(s) connected'
    assert c['frps proxy ss-back'] == {'name': 'frps proxy ss-back', 'ok': False, 'severity': 'low',
                                       'detail': 'tcp proxy offline since 11-21 10:00:00'}
    assert [p for _, p in api.calls] == ['/api/serverinfo', '/api/proxy/tcp']
    assert {port for port, _ in api.calls} == {7500}


def test_disabled_and_both_enabled(tmp_path):
    c, out = run(tmp_path, Api({}), client='0', server='0')
    assert out == {'checks': []}
    (tmp_path / 'b').mkdir()
    c, _ = run(tmp_path / 'b', Api({'/api/status': CLIENT_STATUS}), client='1', server='1')
    assert c['frps running']['ok'] is None


def test_http_get_only_talks_to_localhost(monkeypatch):
    seen = {}

    class Resp:
        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

        def read(self, n):
            return b'{"ok": 1}'

    class Opener:
        def open(self, req, timeout):
            seen['url'] = req.full_url
            seen['auth'] = req.get_header('Authorization')
            return Resp()
    monkeypatch.setattr(healthcheck.urllib.request, 'build_opener', lambda *h: Opener())
    assert healthcheck.http_get(7400, '/api/status', 'admin', 'pw') == {'ok': 1}
    assert seen['url'] == 'http://127.0.0.1:7400/api/status' and seen['auth'].startswith('Basic ')


@pytest.mark.parametrize('bad', ['', 'not xml'])
def test_unreadable_config(tmp_path, bad):
    p = tmp_path / 'c.xml'
    p.write_text(bad)
    out = healthcheck.build(str(p), str(tmp_path / 'pid'), None, Api({}))
    assert out['checks'][0]['ok'] is None
