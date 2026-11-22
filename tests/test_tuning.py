"""Network tuning must really take effect on FreeBSD/OPNsense (static checks)."""

import os

ROOT = os.path.join(os.path.dirname(__file__), '..', 'src')


def read(*parts):
    with open(os.path.join(ROOT, *parts)) as f:
        return f.read()


TUNING = read('opnsense', 'scripts', 'OPNsense', 'Frp', 'apply_tuning.sh')


def test_mss_uses_match_rules_in_a_referenced_head_anchor():
    # "scrub on" rules inside an anchor are never evaluated; match ... scrub (max-mss) are
    assert 'scrub on' not in TUNING and TUNING.count('scrub (max-mss %s)') == 4
    inc = read('etc', 'inc', 'plugins.inc.d', 'frp.inc')
    assert "registerAnchor('frp_mss', 'fw', 0, 'head')" in inc


def test_tfo_uses_existing_sysctls():
    assert 'fastopen.enabled' not in TUNING and 'fastopen.server_enable=1' in TUNING


def test_buffers_are_never_lowered():
    assert '2097152' not in TUNING and '-lt 4194304' in TUNING


def test_tuning_runs_before_every_start():
    rc = read('usr', 'local', 'etc', 'rc.d', 'frp')
    start = rc[rc.index('frp_start()'):]
    assert start.index('apply_tuning.sh') < start.index('binary=')
