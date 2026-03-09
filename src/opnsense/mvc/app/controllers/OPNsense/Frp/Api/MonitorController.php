<?php

namespace OPNsense\Frp\Api;

use OPNsense\Base\ApiControllerBase;

class MonitorController extends ApiControllerBase
{
    private $dbPath = '/var/db/frp/traffic.db';

    private function getDb()
    {
        if (!file_exists($this->dbPath)) {
            return null;
        }
        $db = new \SQLite3($this->dbPath, SQLITE3_OPEN_READONLY);
        $db->busyTimeout(3000);
        return $db;
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

        $result = [];
        $query = $db->query(
            "SELECT DISTINCT proxy_name, proxy_type FROM traffic_samples
             UNION SELECT DISTINCT proxy_name, proxy_type FROM traffic_hourly
             UNION SELECT DISTINCT proxy_name, proxy_type FROM traffic_daily
             ORDER BY proxy_name"
        );
        while ($row = $query->fetchArray(SQLITE3_ASSOC)) {
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

        $result = [];
        if ($interval <= 1) {
            $query = $db->query(
                "SELECT {$tsCol} as timestamp, proxy_name, proxy_type, speed_in, speed_out, traffic_in, traffic_out, cur_conns
                 FROM {$table}
                 WHERE {$tsCol} >= {$since} {$proxyFilter}
                 ORDER BY {$tsCol} ASC"
            );
            while ($row = $query->fetchArray(SQLITE3_ASSOC)) {
                $result[] = $row;
            }
        } else {
            // Group into buckets
            $bucketSize = (int)ceil((time() - $since) / $maxPoints);
            $query = $db->query(
                "SELECT ({$tsCol} / {$bucketSize}) * {$bucketSize} as timestamp,
                        proxy_name, proxy_type,
                        AVG(speed_in) as speed_in, AVG(speed_out) as speed_out,
                        MAX(traffic_in) as traffic_in, MAX(traffic_out) as traffic_out,
                        AVG(cur_conns) as cur_conns
                 FROM {$table}
                 WHERE {$tsCol} >= {$since} {$proxyFilter}
                 GROUP BY ({$tsCol} / {$bucketSize}), proxy_name
                 ORDER BY timestamp ASC"
            );
            while ($row = $query->fetchArray(SQLITE3_ASSOC)) {
                $result[] = $row;
            }
        }

        return $result;
    }

    private function queryHourly($db, $proxy, $since, $maxPoints)
    {
        $proxyFilter = '';
        if (!empty($proxy)) {
            $proxyFilter = "AND proxy_name = '" . $db->escapeString($proxy) . "'";
        }

        $result = [];
        $query = $db->query(
            "SELECT hour_ts as timestamp, proxy_name, proxy_type,
                    bytes_in, bytes_out,
                    avg_speed_in as speed_in, avg_speed_out as speed_out,
                    max_speed_in, max_speed_out,
                    avg_conns as cur_conns, max_conns, samples
             FROM traffic_hourly
             WHERE hour_ts >= {$since} {$proxyFilter}
             ORDER BY hour_ts ASC"
        );
        while ($row = $query->fetchArray(SQLITE3_ASSOC)) {
            $result[] = $row;
        }

        return $result;
    }

    private function queryDaily($db, $proxy, $since, $maxPoints)
    {
        $proxyFilter = '';
        if (!empty($proxy)) {
            $proxyFilter = "AND proxy_name = '" . $db->escapeString($proxy) . "'";
        }

        $result = [];
        $query = $db->query(
            "SELECT day_ts as timestamp, proxy_name, proxy_type,
                    bytes_in, bytes_out,
                    avg_speed_in as speed_in, avg_speed_out as speed_out,
                    max_speed_in, max_speed_out,
                    avg_conns as cur_conns, max_conns
             FROM traffic_daily
             WHERE day_ts >= {$since} {$proxyFilter}
             ORDER BY day_ts ASC"
        );
        while ($row = $query->fetchArray(SQLITE3_ASSOC)) {
            $result[] = $row;
        }

        return $result;
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
        $todayStart = (int)(floor($now / 86400) * 86400);
        $weekAgo = $now - 604800;
        $monthAgo = $now - 2592000;

        // Current speed: latest sample per proxy
        $proxies = [];
        $query = $db->query(
            "SELECT s.proxy_name, s.proxy_type, s.speed_in, s.speed_out, s.cur_conns, s.traffic_in, s.traffic_out
             FROM traffic_samples s
             INNER JOIN (SELECT proxy_name, MAX(timestamp) as max_ts FROM traffic_samples GROUP BY proxy_name) latest
             ON s.proxy_name = latest.proxy_name AND s.timestamp = latest.max_ts"
        );
        while ($row = $query->fetchArray(SQLITE3_ASSOC)) {
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

        // Today's traffic from raw samples
        $query = $db->query(
            "SELECT proxy_name, MAX(traffic_in) - MIN(traffic_in) as bytes_in,
                    MAX(traffic_out) - MIN(traffic_out) as bytes_out
             FROM traffic_samples
             WHERE timestamp >= {$todayStart}
             GROUP BY proxy_name"
        );
        while ($row = $query->fetchArray(SQLITE3_ASSOC)) {
            if (isset($proxies[$row['proxy_name']])) {
                $proxies[$row['proxy_name']]['today_in'] = max(0, (int)$row['bytes_in']);
                $proxies[$row['proxy_name']]['today_out'] = max(0, (int)$row['bytes_out']);
            }
        }

        // 7-day traffic from hourly
        $query = $db->query(
            "SELECT proxy_name, SUM(bytes_in) as bytes_in, SUM(bytes_out) as bytes_out
             FROM traffic_hourly
             WHERE hour_ts >= {$weekAgo}
             GROUP BY proxy_name"
        );
        while ($row = $query->fetchArray(SQLITE3_ASSOC)) {
            if (isset($proxies[$row['proxy_name']])) {
                $proxies[$row['proxy_name']]['week_in'] += (int)$row['bytes_in'];
                $proxies[$row['proxy_name']]['week_out'] += (int)$row['bytes_out'];
            }
        }

        // 30-day traffic from hourly + daily
        $query = $db->query(
            "SELECT proxy_name, SUM(bytes_in) as bytes_in, SUM(bytes_out) as bytes_out
             FROM traffic_hourly
             WHERE hour_ts >= {$monthAgo}
             GROUP BY proxy_name"
        );
        while ($row = $query->fetchArray(SQLITE3_ASSOC)) {
            if (isset($proxies[$row['proxy_name']])) {
                $proxies[$row['proxy_name']]['month_in'] += (int)$row['bytes_in'];
                $proxies[$row['proxy_name']]['month_out'] += (int)$row['bytes_out'];
            }
        }
        $query = $db->query(
            "SELECT proxy_name, SUM(bytes_in) as bytes_in, SUM(bytes_out) as bytes_out
             FROM traffic_daily
             WHERE day_ts >= {$monthAgo}
             GROUP BY proxy_name"
        );
        while ($row = $query->fetchArray(SQLITE3_ASSOC)) {
            if (isset($proxies[$row['proxy_name']])) {
                $proxies[$row['proxy_name']]['month_in'] += (int)$row['bytes_in'];
                $proxies[$row['proxy_name']]['month_out'] += (int)$row['bytes_out'];
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
}
