<?php

/*
 * Copyright (C) 2024 os-frp
 * All rights reserved.
 *
 * FRP Tunnel plugin for OPNsense
 */

function frp_enabled()
{
    $mdl = new \OPNsense\Frp\Client();
    $mdlServer = new \OPNsense\Frp\Server();
    return (string)$mdl->enabled === '1' || (string)$mdlServer->enabled === '1';
}

function frp_services()
{
    $services = [];

    $mdlClient = new \OPNsense\Frp\Client();
    if ((string)$mdlClient->enabled === '1') {
        $services[] = [
            'description' => gettext('FRP Client'),
            'configd' => [
                'restart' => ['frp restart client'],
                'start' => ['frp start client'],
                'stop' => ['frp stop client'],
            ],
            'name' => 'frpc',
            'pidfile' => '/var/run/frpc.pid',
        ];
    }

    $mdlServer = new \OPNsense\Frp\Server();
    if ((string)$mdlServer->enabled === '1') {
        $services[] = [
            'description' => gettext('FRP Server'),
            'configd' => [
                'restart' => ['frp restart server'],
                'start' => ['frp start server'],
                'stop' => ['frp stop server'],
            ],
            'name' => 'frps',
            'pidfile' => '/var/run/frps.pid',
        ];
    }

    return $services;
}

/**
 * MSS clamping (apply_tuning.sh) loads "match ... scrub (max-mss N)" rules into
 * the anchor frp_mss; the anchor must be referenced from the ruleset head to be
 * evaluated. Empty when MSS clamping is off.
 */
function frp_firewall(\OPNsense\Firewall\Plugin $fw)
{
    $fw->registerAnchor('frp_mss', 'fw', 0, 'head');
}

function frp_cron()
{
    // nothing to collect or watch while neither role is enabled; the GUI Apply
    // regenerates cron (Api/ServiceController) so enabling adds the jobs again
    if (!frp_enabled()) {
        return [];
    }
    return [
        [
            'description' => 'FRP Traffic Collector',
            'autocron' => ['/usr/local/sbin/configctl frp collect_traffic', '*'],
        ],
        [
            'description' => 'FRP Watchdog',
            'autocron' => ['/usr/local/sbin/configctl frp watchdog', '*'],
        ],
    ];
}

function frp_syslog()
{
    $logfacilities = [];
    $logfacilities['frp'] = ['facility' => ['frp']];
    return $logfacilities;
}
