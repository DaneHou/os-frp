<?php

namespace OPNsense\Frp\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Frp\Client;

class MonitorController extends ApiControllerBase
{
    private $dbPath = '/var/db/frp/traffic.db';

    private function getDb()
    {
        if (!file_exists($this->dbPath)) {
            return null;
        }
        $db = new \SQLite3($this->dbPath, SQLITE3_OPEN_READWRITE);
        $db->busyTimeout(3000);

        // Ensure delta columns exist (migration for existing databases)
        $cols = [];
        $pragma = $db->query("PRAGMA table_info(traffic_samples)");
        if ($pragma) {
            while ($col = $pragma->fetchArray(SQLITE3_ASSOC)) {
                $cols[] = $col['name'];
            }
        }
        if (!in_array('delta_in', $cols)) {
            $db->exec('ALTER TABLE traffic_samples ADD COLUMN delta_in INTEGER NOT NULL DEFAULT 0');
        }
        if (!in_array('delta_out', $cols)) {
            $db->exec('ALTER TABLE traffic_samples ADD COLUMN delta_out INTEGER NOT NULL DEFAULT 0');
        }
        if (!in_array('sample_interval', $cols)) {
            $db->exec('ALTER TABLE traffic_samples ADD COLUMN sample_interval REAL NOT NULL DEFAULT 0');
        }

        return $db;
    }

    /**
     * Safe query wrapper — returns empty array if query fails
     */
    private function queryRows($db, $sql)
    {
        $result = [];
        $query = $db->query($sql);
        if ($query) {
            while ($row = $query->fetchArray(SQLITE3_ASSOC)) {
                $result[] = $row;
            }
        }
        return $result;
    }

    /**
     * GET /api/frp/monitor/proxies
     * Returns distinct proxy names/types from the database
     */
    public function proxiesAction()
    {
        $db = $this->getDb();
        if ($db === null) {
            return ['status' => 'ok', 'proxies' => []];
        }

        $rows = $this->queryRows($db,
            "SELECT DISTINCT proxy_name, proxy_type FROM traffic_samples
             UNION SELECT DISTINCT proxy_name, proxy_type FROM traffic_hourly
             UNION SELECT DISTINCT proxy_name, proxy_type FROM traffic_daily
             ORDER BY proxy_name"
        );
        $result = [];
        foreach ($rows as $row) {
            $result[] = ['name' => $row['proxy_name'], 'type' => $row['proxy_type']];
        }
        $db->close();

        return ['status' => 'ok', 'proxies' => $result];
    }

    /**
     * GET /api/frp/monitor/realtime?proxy=&seconds=300
     * Returns raw samples for real-time charting
     */
    public function realtimeAction()
    {
        $db = $this->getDb();
        if ($db === null) {
            return ['status' => 'ok', 'data' => []];
        }

        $proxy = $this->request->get('proxy', 'string', '');
        $seconds = (int)$this->request->get('seconds', 'int', 300);
        $seconds = max(60, min(3600, $seconds));

        $since = time() - $seconds;
        $result = [];

        if (!empty($proxy)) {
            $stmt = $db->prepare(
                "SELECT timestamp, proxy_name, speed_in, speed_out, cur_conns
                 FROM traffic_samples
                 WHERE proxy_name = :proxy AND timestamp >= :since
                 ORDER BY timestamp ASC"
            );
            $stmt->bindValue(':proxy', $proxy, SQLITE3_TEXT);
            $stmt->bindValue(':since', $since, SQLITE3_INTEGER);
        } else {
            $stmt = $db->prepare(
                "SELECT timestamp, proxy_name, speed_in, speed_out, cur_conns
                 FROM traffic_samples
                 WHERE timestamp >= :since
                 ORDER BY timestamp ASC"
            );
            $stmt->bindValue(':since', $since, SQLITE3_INTEGER);
        }

        $rows = $stmt->execute();
        while ($row = $rows->fetchArray(SQLITE3_ASSOC)) {
            $result[] = $row;
        }
        $db->close();

        return ['status' => 'ok', 'data' => $result];
    }

    /**
     * GET /api/frp/monitor/history?proxy=&range=24h
     * Returns data at appropriate granularity for the requested range
     */
    public function historyAction()
    {
        $db = $this->getDb();
        if ($db === null) {
            return ['status' => 'ok', 'data' => []];
        }

        $proxy = $this->request->get('proxy', 'string', '');
        $range = $this->request->get('range', 'string', '24h');

        // Parse range to seconds
        $rangeMap = [
            '1h' => 3600,
            '6h' => 21600,
            '24h' => 86400,
            '7d' => 604800,
            '30d' => 2592000,
            '90d' => 7776000,
            '1yr' => 31536000,
        ];
        $rangeSec = $rangeMap[$range] ?? 86400;
        $since = time() - $rangeSec;

        $result = [];
        $maxPoints = 300;

        if ($rangeSec <= 86400) {
            // Use raw samples, downsample if needed
            $result = $this->queryWithDownsample($db, 'traffic_samples', 'timestamp', $proxy, $since, $maxPoints);
        } elseif ($rangeSec <= 2592000) {
            // Use hourly aggregates
            $result = $this->queryHourly($db, $proxy, $since, $maxPoints);
        } else {
            // Use daily aggregates
            $result = $this->queryDaily($db, $proxy, $since, $maxPoints);
        }

        $db->close();
        return ['status' => 'ok', 'data' => $result, 'range' => $range];
    }

    private function queryWithDownsample($db, $table, $tsCol, $proxy, $since, $maxPoints)
    {
        $proxyFilter = '';
        if (!empty($proxy)) {
            $proxyFilter = "AND proxy_name = '" . $db->escapeString($proxy) . "'";
        }

        // Count rows
        $count = $db->querySingle(
            "SELECT COUNT(*) FROM {$table} WHERE {$tsCol} >= {$since} {$proxyFilter}"
        );

        $interval = 1;
        if ($count > $maxPoints) {
            $interval = (int)ceil($count / $maxPoints);
        }

        if ($interval <= 1) {
            return $this->queryRows($db,
                "SELECT {$tsCol} as timestamp, proxy_name, proxy_type, speed_in, speed_out,
                        traffic_in, traffic_out, delta_in, delta_out, cur_conns
                 FROM {$table}
                 WHERE {$tsCol} >= {$since} {$proxyFilter}
                 ORDER BY {$tsCol} ASC"
            );
        } else {
            // Group into buckets — use SUM(delta_in/delta_out) for accurate traffic
            // even when FRP counters reset (midnight or restart)
            $bucketSize = (int)ceil((time() - $since) / $maxPoints);
            return $this->queryRows($db,
                "SELECT ({$tsCol} / {$bucketSize}) * {$bucketSize} as timestamp,
                        proxy_name, proxy_type,
                        AVG(speed_in) as speed_in, AVG(speed_out) as speed_out,
                        SUM(delta_in) as bytes_in, SUM(delta_out) as bytes_out,
                        AVG(cur_conns) as cur_conns
                 FROM {$table}
                 WHERE {$tsCol} >= {$since} {$proxyFilter}
                 GROUP BY ({$tsCol} / {$bucketSize}), proxy_name
                 ORDER BY timestamp ASC"
            );
        }
    }

    private function queryHourly($db, $proxy, $since, $maxPoints)
    {
        $proxyFilter = '';
        if (!empty($proxy)) {
            $proxyFilter = "AND proxy_name = '" . $db->escapeString($proxy) . "'";
        }

        return $this->queryRows($db,
            "SELECT hour_ts as timestamp, proxy_name, proxy_type,
                    bytes_in, bytes_out,
                    avg_speed_in as speed_in, avg_speed_out as speed_out,
                    max_speed_in, max_speed_out,
                    avg_conns as cur_conns, max_conns, samples
             FROM traffic_hourly
             WHERE hour_ts >= {$since} {$proxyFilter}
             ORDER BY hour_ts ASC"
        );
    }

    private function queryDaily($db, $proxy, $since, $maxPoints)
    {
        $proxyFilter = '';
        if (!empty($proxy)) {
            $proxyFilter = "AND proxy_name = '" . $db->escapeString($proxy) . "'";
        }

        return $this->queryRows($db,
            "SELECT day_ts as timestamp, proxy_name, proxy_type,
                    bytes_in, bytes_out,
                    avg_speed_in as speed_in, avg_speed_out as speed_out,
                    max_speed_in, max_speed_out,
                    avg_conns as cur_conns, max_conns
             FROM traffic_daily
             WHERE day_ts >= {$since} {$proxyFilter}
             ORDER BY day_ts ASC"
        );
    }

    /**
     * GET /api/frp/monitor/summary
     * Returns per-proxy totals and current speeds
     */
    public function summaryAction()
    {
        $db = $this->getDb();
        if ($db === null) {
            return ['status' => 'ok', 'totals' => ['today_in' => 0, 'today_out' => 0, 'speed_in' => 0, 'speed_out' => 0, 'cur_conns' => 0], 'proxies' => [], 'server' => null];
        }

        $now = time();
        $todayStart = (int)strtotime('today');
        $weekAgo = $now - 604800;
        $monthAgo = $now - 2592000;

        // Determine boundaries to prevent double-counting between tables.
        // hourlyBoundary: raw samples cover from this point forward, hourly covers before.
        // dailyBoundary: hourly covers from this point forward, daily covers before.
        $hourlyBoundary = (int)$db->querySingle(
            "SELECT COALESCE(MAX(hour_ts) + 3600, 0) FROM traffic_hourly"
        );
        $dailyBoundary = (int)$db->querySingle(
            "SELECT COALESCE(MAX(day_ts) + 86400, 0) FROM traffic_daily"
        );

        // Current speed: weighted average over recent samples (smoothed)
        // Try last 10s first; if no data, fall back to 60s window
        $proxies = [];
        $since10 = $now - 10;
        $since60 = $now - 60;
        $rows = $this->queryRows($db,
            "SELECT proxy_name, proxy_type,
                    CASE WHEN SUM(sample_interval) > 0 THEN SUM(delta_in) * 1.0 / SUM(sample_interval) ELSE AVG(speed_in) END AS speed_in,
                    CASE WHEN SUM(sample_interval) > 0 THEN SUM(delta_out) * 1.0 / SUM(sample_interval) ELSE AVG(speed_out) END AS speed_out,
                    MAX(cur_conns) AS cur_conns
             FROM traffic_samples
             WHERE timestamp >= {$since10}
             GROUP BY proxy_name"
        );
        // Fall back to 60s window for proxies not found in 10s window
        $rows60 = $this->queryRows($db,
            "SELECT proxy_name, proxy_type,
                    CASE WHEN SUM(sample_interval) > 0 THEN SUM(delta_in) * 1.0 / SUM(sample_interval) ELSE AVG(speed_in) END AS speed_in,
                    CASE WHEN SUM(sample_interval) > 0 THEN SUM(delta_out) * 1.0 / SUM(sample_interval) ELSE AVG(speed_out) END AS speed_out,
                    MAX(cur_conns) AS cur_conns
             FROM traffic_samples
             WHERE timestamp >= {$since60}
             GROUP BY proxy_name"
        );
        // Index 60s results for fallback
        $fallback = [];
        foreach ($rows60 as $row) {
            $fallback[$row['proxy_name']] = $row;
        }
        // Build proxy map from 10s window
        foreach ($rows as $row) {
            $proxies[$row['proxy_name']] = [
                'name' => $row['proxy_name'],
                'type' => $row['proxy_type'],
                'speed_in' => (float)$row['speed_in'],
                'speed_out' => (float)$row['speed_out'],
                'cur_conns' => (int)$row['cur_conns'],
                'today_in' => 0,
                'today_out' => 0,
                'week_in' => 0,
                'week_out' => 0,
                'month_in' => 0,
                'month_out' => 0,
            ];
        }
        // Add proxies only present in 60s fallback
        foreach ($fallback as $name => $row) {
            if (!isset($proxies[$name])) {
                $proxies[$name] = [
                    'name' => $row['proxy_name'],
                    'type' => $row['proxy_type'],
                    'speed_in' => (float)$row['speed_in'],
                    'speed_out' => (float)$row['speed_out'],
                    'cur_conns' => (int)$row['cur_conns'],
                    'today_in' => 0,
                    'today_out' => 0,
                    'week_in' => 0,
                    'week_out' => 0,
                    'month_in' => 0,
                    'month_out' => 0,
                ];
            }
        }

        // Today's traffic: SUM of deltas since midnight (not raw FRP counter,
        // which breaks on FRP restart or timezone mismatch)
        foreach ($this->queryRows($db,
            "SELECT proxy_name, SUM(delta_in) as total_in, SUM(delta_out) as total_out
             FROM traffic_samples
             WHERE timestamp >= {$todayStart}
             GROUP BY proxy_name"
        ) as $row) {
            if (isset($proxies[$row['proxy_name']])) {
                $proxies[$row['proxy_name']]['today_in'] = max(0, (int)$row['total_in']);
                $proxies[$row['proxy_name']]['today_out'] = max(0, (int)$row['total_out']);
            }
        }

        // 7-day traffic: hourly (before boundary) + raw samples (from boundary onward)
        // No overlap because each table covers a strict time range.
        foreach ($this->queryRows($db,
            "SELECT proxy_name, SUM(bytes_in) as bytes_in, SUM(bytes_out) as bytes_out
             FROM traffic_hourly
             WHERE hour_ts >= {$weekAgo}
             GROUP BY proxy_name"
        ) as $row) {
            if (isset($proxies[$row['proxy_name']])) {
                $proxies[$row['proxy_name']]['week_in'] += (int)$row['bytes_in'];
                $proxies[$row['proxy_name']]['week_out'] += (int)$row['bytes_out'];
            }
        }
        $rawWeekStart = max($weekAgo, $hourlyBoundary);
        foreach ($this->queryRows($db,
            "SELECT proxy_name, SUM(delta_in) as bytes_in, SUM(delta_out) as bytes_out
             FROM traffic_samples
             WHERE timestamp >= {$rawWeekStart}
             GROUP BY proxy_name"
        ) as $row) {
            if (isset($proxies[$row['proxy_name']])) {
                $proxies[$row['proxy_name']]['week_in'] += max(0, (int)$row['bytes_in']);
                $proxies[$row['proxy_name']]['week_out'] += max(0, (int)$row['bytes_out']);
            }
        }

        // 30-day traffic: daily (before dailyBoundary) + hourly (from dailyBoundary) + raw samples (from hourlyBoundary)
        foreach ($this->queryRows($db,
            "SELECT proxy_name, SUM(bytes_in) as bytes_in, SUM(bytes_out) as bytes_out
             FROM traffic_daily
             WHERE day_ts >= {$monthAgo}
             GROUP BY proxy_name"
        ) as $row) {
            if (isset($proxies[$row['proxy_name']])) {
                $proxies[$row['proxy_name']]['month_in'] += (int)$row['bytes_in'];
                $proxies[$row['proxy_name']]['month_out'] += (int)$row['bytes_out'];
            }
        }
        $hourlyMonthStart = max($monthAgo, $dailyBoundary);
        foreach ($this->queryRows($db,
            "SELECT proxy_name, SUM(bytes_in) as bytes_in, SUM(bytes_out) as bytes_out
             FROM traffic_hourly
             WHERE hour_ts >= {$hourlyMonthStart}
             GROUP BY proxy_name"
        ) as $row) {
            if (isset($proxies[$row['proxy_name']])) {
                $proxies[$row['proxy_name']]['month_in'] += (int)$row['bytes_in'];
                $proxies[$row['proxy_name']]['month_out'] += (int)$row['bytes_out'];
            }
        }
        $rawMonthStart = max($monthAgo, $hourlyBoundary);
        foreach ($this->queryRows($db,
            "SELECT proxy_name, SUM(delta_in) as bytes_in, SUM(delta_out) as bytes_out
             FROM traffic_samples
             WHERE timestamp >= {$rawMonthStart}
             GROUP BY proxy_name"
        ) as $row) {
            if (isset($proxies[$row['proxy_name']])) {
                $proxies[$row['proxy_name']]['month_in'] += max(0, (int)$row['bytes_in']);
                $proxies[$row['proxy_name']]['month_out'] += max(0, (int)$row['bytes_out']);
            }
        }

        // Compute totals
        $totalTodayIn = 0;
        $totalTodayOut = 0;
        $totalSpeedIn = 0;
        $totalSpeedOut = 0;
        $totalConns = 0;
        foreach ($proxies as $p) {
            $totalTodayIn += $p['today_in'];
            $totalTodayOut += $p['today_out'];
            $totalSpeedIn += $p['speed_in'];
            $totalSpeedOut += $p['speed_out'];
            $totalConns += $p['cur_conns'];
        }

        // Server sample (latest)
        $server = null;
        $sRow = $db->querySingle(
            "SELECT * FROM server_samples ORDER BY timestamp DESC LIMIT 1",
            true
        );
        if ($sRow) {
            $server = $sRow;
        }

        $db->close();

        return [
            'status' => 'ok',
            'totals' => [
                'today_in' => $totalTodayIn,
                'today_out' => $totalTodayOut,
                'speed_in' => $totalSpeedIn,
                'speed_out' => $totalSpeedOut,
                'cur_conns' => $totalConns,
            ],
            'proxies' => array_values($proxies),
            'server' => $server,
        ];
    }

    /**
     * GET /api/frp/monitor/healthcheck
     * Curl enabled health targets and return latency
     */
    public function healthcheckAction()
    {
        $mdl = new Client();
        $results = [];

        foreach ($mdl->healthTargets->healthTarget->iterateItems() as $uuid => $target) {
            if ((string)$target->enabled !== '1') {
                continue;
            }

            $label = (string)$target->label;
            $url = (string)$target->url;

            $ch = curl_init();
            curl_setopt_array($ch, [
                CURLOPT_URL => $url,
                CURLOPT_NOBODY => true,
                CURLOPT_TIMEOUT => 5,
                CURLOPT_CONNECTTIMEOUT => 5,
                CURLOPT_FOLLOWLOCATION => true,
                CURLOPT_MAXREDIRS => 3,
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_SSL_VERIFYPEER => false,
            ]);

            $ok = curl_exec($ch);
            $entry = [
                'uuid' => $uuid,
                'label' => $label,
                'url' => $url,
            ];

            if ($ok === false) {
                $entry['status'] = 'error';
                $entry['latency_ms'] = null;
                $entry['http_code'] = 0;
                $entry['error'] = curl_error($ch);
            } else {
                $totalTime = curl_getinfo($ch, CURLINFO_TOTAL_TIME);
                $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
                $entry['status'] = 'ok';
                $entry['latency_ms'] = round($totalTime * 1000, 1);
                $entry['http_code'] = (int)$httpCode;
                $entry['error'] = null;
            }

            curl_close($ch);
            $results[] = $entry;
        }

        return ['status' => 'ok', 'results' => $results];
    }

    /**
     * GET /api/frp/monitor/healthHistory?target=&range=24h
     * Returns historical health check latency data
     */
    public function healthHistoryAction()
    {
        $db = $this->getDb();
        if ($db === null) {
            return ['status' => 'ok', 'data' => [], 'targets' => []];
        }

        // Ensure health_samples table exists
        $db->exec('CREATE TABLE IF NOT EXISTS health_samples (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            target_label TEXT NOT NULL,
            target_url TEXT NOT NULL,
            latency_ms REAL,
            http_code INTEGER,
            status TEXT NOT NULL,
            error TEXT
        )');

        $target = $this->request->get('target', 'string', '');
        $range = $this->request->get('range', 'string', '24h');

        $rangeMap = [
            '1h' => 3600,
            '6h' => 21600,
            '24h' => 86400,
            '7d' => 604800,
        ];
        $rangeSec = $rangeMap[$range] ?? 86400;
        $since = time() - $rangeSec;

        // Get distinct targets
        $targets = $this->queryRows($db,
            "SELECT DISTINCT target_label FROM health_samples WHERE timestamp >= {$since} ORDER BY target_label"
        );

        $targetFilter = '';
        if (!empty($target)) {
            $targetFilter = "AND target_label = '" . $db->escapeString($target) . "'";
        }

        $data = $this->queryRows($db,
            "SELECT timestamp, target_label, latency_ms, http_code, status, error
             FROM health_samples
             WHERE timestamp >= {$since} {$targetFilter}
             ORDER BY timestamp ASC"
        );

        $db->close();

        return [
            'status' => 'ok',
            'data' => $data,
            'targets' => array_column($targets, 'target_label'),
            'range' => $range,
        ];
    }
}
