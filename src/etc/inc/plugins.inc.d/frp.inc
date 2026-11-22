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
                'restart' => ['frp restart'],
                'start' => ['frp start'],
                'stop' => ['frp stop'],
            ],
            'name' => 'frpc',
            'pidfile' => '/var/run/frp.pid',
        ];
    }

    $mdlServer = new \OPNsense\Frp\Server();
    if ((string)$mdlServer->enabled === '1') {
        $services[] = [
            'description' => gettext('FRP Server'),
            'configd' => [
                'restart' => ['frp restart'],
                'start' => ['frp start'],
                'stop' => ['frp stop'],
            ],
            'name' => 'frps',
            'pidfile' => '/var/run/frp.pid',
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
