#!/usr/local/bin/php
<?php

/*
 * Copyright (C) 2024 os-frp
 * All rights reserved.
 *
 * FRP Traffic Collector — polls FRP dashboard API, stores in SQLite
 * Runs via cron every 1 minute; internally throttles to ~30s intervals.
 */

define('DB_PATH', '/var/db/frp/traffic.db');
define('MIN_INTERVAL', 25); // minimum seconds between samples
define('RAW_RETENTION', 86400);       // 24 hours
define('HOURLY_RETENTION', 2592000);  // 30 days
define('DAILY_RETENTION', 31536000);  // 1 year

function initDatabase()
{
    $dir = dirname(DB_PATH);
    if (!is_dir($dir)) {
        mkdir($dir, 0755, true);
    }

    $db = new SQLite3(DB_PATH);
    $db->busyTimeout(5000);
    $db->exec('PRAGMA journal_mode=WAL');
    $db->exec('PRAGMA synchronous=NORMAL');

    $db->exec('CREATE TABLE IF NOT EXISTS traffic_samples (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        proxy_name TEXT NOT NULL,
        proxy_type TEXT NOT NULL,
        traffic_in INTEGER NOT NULL,
        traffic_out INTEGER NOT NULL,
        speed_in REAL NOT NULL DEFAULT 0,
        speed_out REAL NOT NULL DEFAULT 0,
        cur_conns INTEGER NOT NULL DEFAULT 0
    )');

    $db->exec('CREATE TABLE IF NOT EXISTS traffic_hourly (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        hour_ts INTEGER NOT NULL,
        proxy_name TEXT NOT NULL,
        proxy_type TEXT NOT NULL,
        bytes_in INTEGER NOT NULL,
        bytes_out INTEGER NOT NULL,
        avg_speed_in REAL,
        max_speed_in REAL,
        avg_speed_out REAL,
        max_speed_out REAL,
        avg_conns REAL,
        max_conns INTEGER,
        samples INTEGER NOT NULL
    )');

    $db->exec('CREATE TABLE IF NOT EXISTS traffic_daily (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        day_ts INTEGER NOT NULL,
        proxy_name TEXT NOT NULL,
        proxy_type TEXT NOT NULL,
        bytes_in INTEGER NOT NULL,
        bytes_out INTEGER NOT NULL,
        avg_speed_in REAL,
        max_speed_in REAL,
        avg_speed_out REAL,
        max_speed_out REAL,
        avg_conns REAL,
        max_conns INTEGER
    )');

    $db->exec('CREATE TABLE IF NOT EXISTS server_samples (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        total_traffic_in INTEGER NOT NULL,
        total_traffic_out INTEGER NOT NULL,
        cur_conns INTEGER NOT NULL,
        client_counts INTEGER NOT NULL,
        speed_in REAL NOT NULL DEFAULT 0,
        speed_out REAL NOT NULL DEFAULT 0
    )');

    $db->exec('CREATE TABLE IF NOT EXISTS collector_state (
        proxy_name TEXT PRIMARY KEY,
        last_traffic_in INTEGER NOT NULL,
        last_traffic_out INTEGER NOT NULL,
        last_timestamp INTEGER NOT NULL
    )');

    // Indexes for query performance
    $db->exec('CREATE INDEX IF NOT EXISTS idx_samples_ts ON traffic_samples(timestamp)');
    $db->exec('CREATE INDEX IF NOT EXISTS idx_samples_proxy_ts ON traffic_samples(proxy_name, timestamp)');
    $db->exec('CREATE INDEX IF NOT EXISTS idx_hourly_ts ON traffic_hourly(hour_ts)');
    $db->exec('CREATE INDEX IF NOT EXISTS idx_hourly_proxy_ts ON traffic_hourly(proxy_name, hour_ts)');
    $db->exec('CREATE INDEX IF NOT EXISTS idx_daily_ts ON traffic_daily(day_ts)');
    $db->exec('CREATE INDEX IF NOT EXISTS idx_daily_proxy_ts ON traffic_daily(proxy_name, day_ts)');
    $db->exec('CREATE INDEX IF NOT EXISTS idx_server_ts ON server_samples(timestamp)');

    return $db;
}

function shouldCollect($db)
{
    $result = $db->querySingle("SELECT MAX(timestamp) FROM traffic_samples");
    if ($result === null) {
        return true;
    }
    return (time() - $result) >= MIN_INTERVAL;
}

function getClientConfig()
{
    $configFile = '/conf/config.xml';
    if (!file_exists($configFile)) {
        return null;
    }

    $xml = simplexml_load_file($configFile);
    if ($xml === false) {
        return null;
    }

    $client = $xml->OPNsense->frp->client ?? null;
    if ($client === null) {
        return null;
    }

    if ((string)($client->webServerEnabled ?? '0') !== '1') {
        return null;
    }

    return [
        'addr' => (string)($client->webServerAddr ?? '127.0.0.1'),
        'port' => (int)($client->webServerPort ?? 7400),
        'user' => (string)($client->webServerUser ?? ''),
        'password' => (string)($client->webServerPassword ?? ''),
    ];
}

function getServerConfig()
{
    $configFile = '/conf/config.xml';
    if (!file_exists($configFile)) {
        return null;
    }

    $xml = simplexml_load_file($configFile);
    if ($xml === false) {
        return null;
    }

    $server = $xml->OPNsense->frp->server ?? null;
    if ($server === null) {
        return null;
    }

    if ((string)($server->webServerEnabled ?? '0') !== '1') {
        return null;
    }

    return [
        'addr' => (string)($server->webServerAddr ?? '127.0.0.1'),
        'port' => (int)($server->webServerPort ?? 7500),
        'user' => (string)($server->webServerUser ?? ''),
        'password' => (string)($server->webServerPassword ?? ''),
    ];
}

function fetchApi($config, $path)
{
    $url = "http://{$config['addr']}:{$config['port']}{$path}";
    $ctx = stream_context_create([
        'http' => [
            'timeout' => 5,
            'header' => !empty($config['user'])
                ? "Authorization: Basic " . base64_encode("{$config['user']}:{$config['password']}")
                : '',
        ],
    ]);

    $response = @file_get_contents($url, false, $ctx);
    if ($response === false) {
        return null;
    }

    return json_decode($response, true);
}

function collectClientData($db, $config, $now)
{
    $status = fetchApi($config, '/api/status');
    if ($status === null || !is_array($status)) {
        return;
    }

    // FRP client /api/status returns {tcp: [{...}], udp: [{...}], ...}
    $proxies = [];
    foreach ($status as $type => $items) {
        if (!is_array($items)) {
            continue;
        }
        foreach ($items as $item) {
            if (!isset($item['name'])) {
                continue;
            }
            $proxies[] = [
                'name' => $item['name'],
                'type' => $type,
                'traffic_in' => (int)($item['today_traffic_in'] ?? 0),
                'traffic_out' => (int)($item['today_traffic_out'] ?? 0),
                'cur_conns' => (int)($item['cur_conns'] ?? 0),
            ];
        }
    }

    insertProxySamples($db, $proxies, $now);
}

function collectServerData($db, $config, $now)
{
    // Collect server info
    $serverInfo = fetchApi($config, '/api/serverinfo');

    // Collect proxy data from server
    $proxyTypes = ['tcp', 'udp', 'http', 'https', 'stcp', 'sudp', 'xtcp', 'tcpmux'];
    $proxies = [];

    foreach ($proxyTypes as $type) {
        $data = fetchApi($config, "/api/proxy/{$type}");
        if ($data === null || !isset($data['proxies']) || !is_array($data['proxies'])) {
            continue;
        }
        foreach ($data['proxies'] as $item) {
            if (!isset($item['name'])) {
                continue;
            }
            $proxies[] = [
                'name' => $item['name'],
                'type' => $type,
                'traffic_in' => (int)($item['today_traffic_in'] ?? 0),
                'traffic_out' => (int)($item['today_traffic_out'] ?? 0),
                'cur_conns' => (int)($item['cur_conns'] ?? 0),
            ];
        }
    }

    insertProxySamples($db, $proxies, $now);

    // Insert server-wide sample
    if ($serverInfo !== null) {
        $totalIn = (int)($serverInfo['total_traffic_in'] ?? 0);
        $totalOut = (int)($serverInfo['total_traffic_out'] ?? 0);
        $curConns = (int)($serverInfo['cur_conns'] ?? 0);
        $clientCounts = (int)($serverInfo['client_counts'] ?? 0);

        // Compute server speed from previous sample
        $speedIn = 0;
        $speedOut = 0;
        $prev = $db->querySingle(
            "SELECT timestamp, total_traffic_in, total_traffic_out FROM server_samples ORDER BY timestamp DESC LIMIT 1",
            true
        );
        if ($prev && $prev['timestamp']) {
            $dt = $now - $prev['timestamp'];
            if ($dt > 0) {
                $deltaIn = $totalIn - $prev['total_traffic_in'];
                $deltaOut = $totalOut - $prev['total_traffic_out'];
                if ($deltaIn >= 0) {
                    $speedIn = $deltaIn / $dt;
                }
                if ($deltaOut >= 0) {
                    $speedOut = $deltaOut / $dt;
                }
            }
        }

        $stmt = $db->prepare(
            "INSERT INTO server_samples (timestamp, total_traffic_in, total_traffic_out, cur_conns, client_counts, speed_in, speed_out)
             VALUES (:ts, :ti, :to, :cc, :cl, :si, :so)"
        );
        $stmt->bindValue(':ts', $now, SQLITE3_INTEGER);
        $stmt->bindValue(':ti', $totalIn, SQLITE3_INTEGER);
        $stmt->bindValue(':to', $totalOut, SQLITE3_INTEGER);
        $stmt->bindValue(':cc', $curConns, SQLITE3_INTEGER);
        $stmt->bindValue(':cl', $clientCounts, SQLITE3_INTEGER);
        $stmt->bindValue(':si', $speedIn, SQLITE3_FLOAT);
        $stmt->bindValue(':so', $speedOut, SQLITE3_FLOAT);
        $stmt->execute();
    }
}

function insertProxySamples($db, $proxies, $now)
{
    $insertSample = $db->prepare(
        "INSERT INTO traffic_samples (timestamp, proxy_name, proxy_type, traffic_in, traffic_out, speed_in, speed_out, cur_conns)
         VALUES (:ts, :name, :type, :ti, :to, :si, :so, :cc)"
    );

    $getState = $db->prepare("SELECT last_traffic_in, last_traffic_out, last_timestamp FROM collector_state WHERE proxy_name = :name");
    $upsertState = $db->prepare(
        "INSERT OR REPLACE INTO collector_state (proxy_name, last_traffic_in, last_traffic_out, last_timestamp)
         VALUES (:name, :ti, :to, :ts)"
    );

    foreach ($proxies as $proxy) {
        $name = $proxy['name'];

        // Get previous state for delta calculation
        $getState->bindValue(':name', $name, SQLITE3_TEXT);
        $prev = $getState->execute()->fetchArray(SQLITE3_ASSOC);
        $getState->reset();

        $speedIn = 0;
        $speedOut = 0;
        if ($prev && $prev['last_timestamp']) {
            $dt = $now - $prev['last_timestamp'];
            if ($dt > 0) {
                $deltaIn = $proxy['traffic_in'] - $prev['last_traffic_in'];
                $deltaOut = $proxy['traffic_out'] - $prev['last_traffic_out'];
                // Handle counter reset (FRP restart resets today_traffic counters)
                if ($deltaIn >= 0) {
                    $speedIn = $deltaIn / $dt;
                }
                if ($deltaOut >= 0) {
                    $speedOut = $deltaOut / $dt;
                }
            }
        }

        // Insert sample
        $insertSample->bindValue(':ts', $now, SQLITE3_INTEGER);
        $insertSample->bindValue(':name', $name, SQLITE3_TEXT);
        $insertSample->bindValue(':type', $proxy['type'], SQLITE3_TEXT);
        $insertSample->bindValue(':ti', $proxy['traffic_in'], SQLITE3_INTEGER);
        $insertSample->bindValue(':to', $proxy['traffic_out'], SQLITE3_INTEGER);
        $insertSample->bindValue(':si', $speedIn, SQLITE3_FLOAT);
        $insertSample->bindValue(':so', $speedOut, SQLITE3_FLOAT);
        $insertSample->bindValue(':cc', $proxy['cur_conns'], SQLITE3_INTEGER);
        $insertSample->execute();
        $insertSample->reset();

        // Update state
        $upsertState->bindValue(':name', $name, SQLITE3_TEXT);
        $upsertState->bindValue(':ti', $proxy['traffic_in'], SQLITE3_INTEGER);
        $upsertState->bindValue(':to', $proxy['traffic_out'], SQLITE3_INTEGER);
        $upsertState->bindValue(':ts', $now, SQLITE3_INTEGER);
        $upsertState->execute();
        $upsertState->reset();
    }
}

function aggregateHourly($db, $now)
{
    $cutoff = $now - RAW_RETENTION;

    // Find hours that need aggregation: raw samples older than 24h that haven't been aggregated
    $hours = $db->query(
        "SELECT DISTINCT (timestamp / 3600) * 3600 AS hour_ts
         FROM traffic_samples
         WHERE timestamp < {$cutoff}
         AND (timestamp / 3600) * 3600 NOT IN (SELECT DISTINCT hour_ts FROM traffic_hourly)"
    );

    while ($row = $hours->fetchArray(SQLITE3_ASSOC)) {
        $hourTs = $row['hour_ts'];
        $nextHour = $hourTs + 3600;

        $db->exec(
            "INSERT INTO traffic_hourly (hour_ts, proxy_name, proxy_type, bytes_in, bytes_out,
                avg_speed_in, max_speed_in, avg_speed_out, max_speed_out, avg_conns, max_conns, samples)
             SELECT {$hourTs}, proxy_name, proxy_type,
                MAX(traffic_in) - MIN(traffic_in),
                MAX(traffic_out) - MIN(traffic_out),
                AVG(speed_in), MAX(speed_in),
                AVG(speed_out), MAX(speed_out),
                AVG(cur_conns), MAX(cur_conns),
                COUNT(*)
             FROM traffic_samples
             WHERE timestamp >= {$hourTs} AND timestamp < {$nextHour}
             GROUP BY proxy_name, proxy_type"
        );
    }
}

function aggregateDaily($db, $now)
{
    $cutoff = $now - HOURLY_RETENTION;

    $days = $db->query(
        "SELECT DISTINCT (hour_ts / 86400) * 86400 AS day_ts
         FROM traffic_hourly
         WHERE hour_ts < {$cutoff}
         AND (hour_ts / 86400) * 86400 NOT IN (SELECT DISTINCT day_ts FROM traffic_daily)"
    );

    while ($row = $days->fetchArray(SQLITE3_ASSOC)) {
        $dayTs = $row['day_ts'];
        $nextDay = $dayTs + 86400;

        $db->exec(
            "INSERT INTO traffic_daily (day_ts, proxy_name, proxy_type, bytes_in, bytes_out,
                avg_speed_in, max_speed_in, avg_speed_out, max_speed_out, avg_conns, max_conns)
             SELECT {$dayTs}, proxy_name, proxy_type,
                SUM(bytes_in), SUM(bytes_out),
                AVG(avg_speed_in), MAX(max_speed_in),
                AVG(avg_speed_out), MAX(max_speed_out),
                AVG(avg_conns), MAX(max_conns)
             FROM traffic_hourly
             WHERE hour_ts >= {$dayTs} AND hour_ts < {$nextDay}
             GROUP BY proxy_name, proxy_type"
        );
    }
}

function purgeOldData($db, $now)
{
    $db->exec("DELETE FROM traffic_samples WHERE timestamp < " . ($now - RAW_RETENTION));
    $db->exec("DELETE FROM server_samples WHERE timestamp < " . ($now - RAW_RETENTION));
    $db->exec("DELETE FROM traffic_hourly WHERE hour_ts < " . ($now - HOURLY_RETENTION));
    $db->exec("DELETE FROM traffic_daily WHERE day_ts < " . ($now - DAILY_RETENTION));
}

// --- Main ---

try {
    $db = initDatabase();

    if (!shouldCollect($db)) {
        $db->close();
        exit(0);
    }

    $now = time();

    $db->exec('BEGIN TRANSACTION');

    // Collect from client dashboard
    $clientConfig = getClientConfig();
    if ($clientConfig !== null) {
        collectClientData($db, $clientConfig, $now);
    }

    // Collect from server dashboard
    $serverConfig = getServerConfig();
    if ($serverConfig !== null) {
        collectServerData($db, $serverConfig, $now);
    }

    // Aggregation and cleanup
    aggregateHourly($db, $now);
    aggregateDaily($db, $now);
    purgeOldData($db, $now);

    $db->exec('COMMIT');
    $db->close();
} catch (Exception $e) {
    error_log("FRP traffic collector error: " . $e->getMessage());
    if (isset($db)) {
        @$db->exec('ROLLBACK');
        @$db->close();
    }
    exit(1);
}
