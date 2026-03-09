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

function frp_cron()
{
    return [
        [
            'description' => 'FRP Traffic Collector',
            'origin' => 'frp',
            'freq' => '1',
            'autocron' => '1',
            'command' => '/usr/local/bin/configctl frp collect_traffic',
        ],
    ];
}

function frp_syslog()
{
    $logfacilities = [];
    $logfacilities['frp'] = ['facility' => ['frp']];
    return $logfacilities;
}
