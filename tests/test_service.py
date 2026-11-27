"""Service plumbing: separate client/server roles, only our own processes, one cron mechanism."""

import configparser
import os
import re

ROOT = os.path.join(os.path.dirname(__file__), '..')


def read(*parts):
    with open(os.path.join(ROOT, *parts)) as f:
        return f.read()


RC = read('src', 'usr', 'local', 'etc', 'rc.d', 'frp')
INC = read('src', 'etc', 'inc', 'plugins.inc.d', 'frp.inc')
MAKE = read('Makefile')
ACTIONS = os.path.join(ROOT, 'src', 'opnsense', 'service', 'conf', 'actions.d', 'actions_frp.conf')


def test_stop_never_kills_by_bare_process_name():
    assert 'pgrep -x' not in RC and 'killall' not in RC
    # the only pgrep is anchored to our own binary + config file
    assert RC.count('pgrep') == 1 and 'pgrep -f "^/usr/local/bin/${bin} -c ${config}' in RC


def test_roles_have_their_own_pidfiles_and_legacy_is_adopted():
    assert 'role_pidfile() { echo "/var/run/$(role_bin "$1").pid"; }' in RC
    assert 'legacy_pidfile="/var/run/frp.pid"' in RC
    assert RC.index('adopt_legacy_pid\nrun_rc_command') > 0
    # an old rc.conf.d (frp_mode only) still maps to a role
    assert 'server) frp_client_enable="NO"; frp_server_enable="YES"' in RC


def test_gui_services_are_split():
    assert "'stop' => ['frp stop client']" in INC and "'stop' => ['frp stop server']" in INC
    assert "'/var/run/frpc.pid'" in INC and "'/var/run/frps.pid'" in INC
    assert "'/var/run/frp.pid'" not in INC


def test_actions_pass_the_role_and_ignore_rcvar():
    cp = configparser.ConfigParser(interpolation=None)
    cp.read(ACTIONS)
    for act in ('start', 'stop', 'restart'):
        assert cp[act]['command'] == '/usr/local/etc/rc.d/frp one' + act
        assert cp[act]['parameters'] == '%s'
    assert cp['reconfigure']['command'].endswith('onerestart')


def test_template_writes_both_role_flags():
    t = read('src', 'opnsense', 'service', 'templates', 'OPNsense', 'Frp', 'frp_rc')
    assert 'frp_client_enable=' in t and 'frp_server_enable=' in t and 'elif' not in t


def test_cron_only_through_the_hook_and_only_when_enabled():
    assert 'crontab' not in MAKE.replace("root's crontab", '')
    body = INC[INC.index('function frp_cron()'):]
    assert body.index('if (!frp_enabled())') < body.index("'autocron'")
    svc = read('src', 'opnsense', 'mvc', 'app', 'controllers', 'OPNsense', 'Frp', 'Api', 'ServiceController.php')
    assert "configdRun('cron restart')" in svc
    assert MAKE.count('configctl cron restart') == 2


def test_watchdog_starts_only_the_missing_role():
    wd = read('src', 'opnsense', 'scripts', 'OPNsense', 'Frp', 'watchdog.sh')
    assert 'pgrep' not in wd and 'frp.pid' not in wd
    assert '"$RC" onestatus "$role"' in wd and 'configctl frp start "$role"' in wd
    assert wd.count('/usr/local/bin/php') == 1


def test_version_bumped():
    assert re.search(r'^PLUGIN_VERSION=\s+1\.3\.0$', MAKE, re.M)
