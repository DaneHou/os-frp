{#
 # Copyright (C) 2024 os-frp
 # All rights reserved.
 #}

<style>
    .monitor-cards {
        display: flex;
        gap: 15px;
        margin-bottom: 20px;
        flex-wrap: wrap;
    }
    .monitor-card {
        flex: 1;
        min-width: 180px;
        background: #fff;
        border: 1px solid #ddd;
        border-radius: 4px;
        padding: 15px;
        text-align: center;
    }
    .monitor-card .card-value {
        font-size: 24px;
        font-weight: bold;
        color: #337ab7;
    }
    .monitor-card .card-label {
        font-size: 12px;
        color: #777;
        margin-top: 5px;
    }
    .chart-container {
        position: relative;
        background: #fff;
        border: 1px solid #ddd;
        border-radius: 4px;
        padding: 15px;
        margin-bottom: 20px;
    }
    .chart-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 10px;
        flex-wrap: wrap;
        gap: 10px;
    }
    .chart-header h3 {
        margin: 0;
        font-size: 16px;
    }
    .chart-controls {
        display: flex;
        gap: 5px;
        align-items: center;
        flex-wrap: wrap;
    }
    .range-btn {
        padding: 3px 10px;
        border: 1px solid #ccc;
        background: #fff;
        border-radius: 3px;
        cursor: pointer;
        font-size: 12px;
    }
    .range-btn.active {
        background: #337ab7;
        color: #fff;
        border-color: #337ab7;
    }
    .proxy-table {
        width: 100%;
    }
    .proxy-table th {
        cursor: pointer;
        user-select: none;
    }
    .proxy-table th:hover {
        background: #f0f0f0;
    }
    canvas {
        max-height: 300px;
    }
    .health-ok { color: #5cb85c; }
    .health-warn { color: #f0ad4e; }
    .health-error { color: #d9534f; }
    .health-latency-good { background: #dff0d8; }
    .health-latency-medium { background: #fcf8e3; }
    .health-latency-bad { background: #f2dede; }
    #healthTargetsSection { display: none; margin-top: 15px; }
</style>

<script src="/js/frp/chart.umd.min.js"></script>
<script src="/js/frp/chartjs-adapter-date-fns.bundle.min.js"></script>

<script>
$(document).ready(function() {
    var realtimeChart = null;
    var historyChart = null;
    var proxyList = [];
    var selectedProxy = '';
    var historyRange = '24h';
    var paused = false;
    var realtimeTimer = null;
    var summaryTimer = null;
    var proxyTableTimer = null;

    // --- Utility ---
    function formatBytes(bytes) {
        if (bytes === 0) return '0 B';
        var k = 1024;
        var sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        var i = Math.floor(Math.log(Math.abs(bytes)) / Math.log(k));
        if (i < 0) i = 0;
        if (i >= sizes.length) i = sizes.length - 1;
        return (bytes / Math.pow(k, i)).toFixed(1) + ' ' + sizes[i];
    }

    function formatSpeed(bytesPerSec) {
        return formatBytes(bytesPerSec) + '/s';
    }

    // --- Color palette ---
    var colors = [
        {in: 'rgba(54, 162, 235, 1)', out: 'rgba(75, 192, 192, 1)', inBg: 'rgba(54, 162, 235, 0.2)', outBg: 'rgba(75, 192, 192, 0.2)'},
        {in: 'rgba(255, 99, 132, 1)', out: 'rgba(255, 159, 64, 1)', inBg: 'rgba(255, 99, 132, 0.2)', outBg: 'rgba(255, 159, 64, 0.2)'},
        {in: 'rgba(153, 102, 255, 1)', out: 'rgba(255, 205, 86, 1)', inBg: 'rgba(153, 102, 255, 0.2)', outBg: 'rgba(255, 205, 86, 0.2)'},
        {in: 'rgba(0, 128, 0, 1)', out: 'rgba(128, 0, 128, 1)', inBg: 'rgba(0, 128, 0, 0.2)', outBg: 'rgba(128, 0, 128, 0.2)'},
    ];

    function getColor(idx) {
        return colors[idx % colors.length];
    }

    // --- Load proxy list ---
    function loadProxies() {
        ajaxGet('/api/frp/monitor/proxies', {}, function(resp) {
            if (resp.status === 'ok') {
                proxyList = resp.proxies || [];
                var sel = $('#proxyFilter, #historyProxyFilter');
                sel.empty().append('<option value="">All Proxies</option>');
                proxyList.forEach(function(p) {
                    sel.append('<option value="' + p.name + '">' + p.name + ' (' + p.type + ')</option>');
                });
            }
        });
    }

    // --- Summary cards ---
    function updateSummary() {
        ajaxGet('/api/frp/monitor/summary', {}, function(resp) {
            if (resp.status !== 'ok') return;
            var t = resp.totals;
            $('#card-speed-in').text(formatSpeed(t.speed_in));
            $('#card-speed-out').text(formatSpeed(t.speed_out));
            $('#card-conns').text(t.cur_conns);
            $('#card-today-in').text(formatBytes(t.today_in));
            $('#card-today-out').text(formatBytes(t.today_out));

            // Update proxy table
            updateProxyTable(resp.proxies);
        });
    }

    // --- Real-time chart ---
    function initRealtimeChart() {
        var ctx = document.getElementById('realtimeCanvas').getContext('2d');
        realtimeChart = new Chart(ctx, {
            type: 'line',
            data: { datasets: [] },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                animation: false,
                interaction: { mode: 'index', intersect: false },
                scales: {
                    x: {
                        type: 'time',
                        time: { unit: 'minute', displayFormats: { minute: 'HH:mm', second: 'HH:mm:ss' } },
                        title: { display: false }
                    },
                    y: {
                        beginAtZero: true,
                        title: { display: true, text: 'Speed' },
                        ticks: {
                            callback: function(value) { return formatSpeed(value); }
                        }
                    }
                },
                plugins: {
                    tooltip: {
                        callbacks: {
                            label: function(ctx) {
                                return ctx.dataset.label + ': ' + formatSpeed(ctx.parsed.y);
                            }
                        }
                    },
                    legend: { position: 'top' }
                }
            }
        });
    }

    function updateRealtimeChart() {
        if (paused) return;
        var url = '/api/frp/monitor/realtime?seconds=300';
        if (selectedProxy) url += '&proxy=' + encodeURIComponent(selectedProxy);

        ajaxGet(url, {}, function(resp) {
            if (resp.status !== 'ok') return;

            // Group by proxy
            var byProxy = {};
            (resp.data || []).forEach(function(d) {
                if (!byProxy[d.proxy_name]) byProxy[d.proxy_name] = [];
                byProxy[d.proxy_name].push(d);
            });

            var datasets = [];
            var idx = 0;
            Object.keys(byProxy).sort().forEach(function(name) {
                var c = getColor(idx);
                var points = byProxy[name];
                datasets.push({
                    label: name + ' In',
                    data: points.map(function(p) { return {x: p.timestamp * 1000, y: p.speed_in}; }),
                    borderColor: c.in, backgroundColor: c.inBg,
                    borderWidth: 1.5, pointRadius: 0, fill: false, tension: 0.3
                });
                datasets.push({
                    label: name + ' Out',
                    data: points.map(function(p) { return {x: p.timestamp * 1000, y: p.speed_out}; }),
                    borderColor: c.out, backgroundColor: c.outBg,
                    borderWidth: 1.5, pointRadius: 0, fill: false, tension: 0.3
                });
                idx++;
            });

            realtimeChart.data.datasets = datasets;
            realtimeChart.update('none');
        });
    }

    // --- History chart ---
    function initHistoryChart() {
        var ctx = document.getElementById('historyCanvas').getContext('2d');
        historyChart = new Chart(ctx, {
            type: 'bar',
            data: { datasets: [] },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                animation: false,
                interaction: { mode: 'index', intersect: false },
                scales: {
                    x: {
                        type: 'time',
                        time: { displayFormats: { hour: 'MMM d HH:mm', day: 'MMM d', month: 'MMM yyyy' } },
                        title: { display: false },
                        stacked: true
                    },
                    y: {
                        beginAtZero: true,
                        title: { display: true, text: 'Traffic' },
                        stacked: true,
                        ticks: {
                            callback: function(value) { return formatBytes(value); }
                        }
                    },
                    y1: {
                        beginAtZero: true,
                        position: 'right',
                        title: { display: true, text: 'Avg Speed' },
                        grid: { drawOnChartArea: false },
                        ticks: {
                            callback: function(value) { return formatSpeed(value); }
                        }
                    }
                },
                plugins: {
                    tooltip: {
                        callbacks: {
                            label: function(ctx) {
                                if (ctx.dataset.yAxisID === 'y1') {
                                    return ctx.dataset.label + ': ' + formatSpeed(ctx.parsed.y);
                                }
                                return ctx.dataset.label + ': ' + formatBytes(ctx.parsed.y);
                            }
                        }
                    },
                    legend: { position: 'top' }
                }
            }
        });
    }

    function updateHistoryChart() {
        var histProxy = $('#historyProxyFilter').val() || '';
        var url = '/api/frp/monitor/history?range=' + historyRange;
        if (histProxy) url += '&proxy=' + encodeURIComponent(histProxy);

        ajaxGet(url, {}, function(resp) {
            if (resp.status !== 'ok') return;

            var byProxy = {};
            (resp.data || []).forEach(function(d) {
                if (!byProxy[d.proxy_name]) byProxy[d.proxy_name] = [];
                byProxy[d.proxy_name].push(d);
            });

            var datasets = [];
            var idx = 0;
            Object.keys(byProxy).sort().forEach(function(name) {
                var c = getColor(idx);
                var points = byProxy[name];

                // Use bytes_in/bytes_out for aggregated data, delta_in/delta_out for raw samples
                var hasBytes = points.length > 0 && points[0].bytes_in !== undefined && points[0].bytes_in !== null;
                var hasDelta = points.length > 0 && points[0].delta_in !== undefined && points[0].delta_in !== null;

                if (hasBytes) {
                    // Aggregated data (hourly/daily or downsampled buckets)
                    datasets.push({
                        label: name + ' In',
                        data: points.map(function(p) { return {x: p.timestamp * 1000, y: parseInt(p.bytes_in) || 0}; }),
                        backgroundColor: c.inBg, borderColor: c.in, borderWidth: 1,
                        yAxisID: 'y', stack: 'traffic'
                    });
                    datasets.push({
                        label: name + ' Out',
                        data: points.map(function(p) { return {x: p.timestamp * 1000, y: parseInt(p.bytes_out) || 0}; }),
                        backgroundColor: c.outBg, borderColor: c.out, borderWidth: 1,
                        yAxisID: 'y', stack: 'traffic'
                    });
                } else if (hasDelta) {
                    // Raw samples with server-computed deltas (handles counter resets correctly)
                    datasets.push({
                        label: name + ' In',
                        data: points.map(function(p) { return {x: p.timestamp * 1000, y: parseInt(p.delta_in) || 0}; }),
                        backgroundColor: c.inBg, borderColor: c.in, borderWidth: 1,
                        yAxisID: 'y', stack: 'traffic'
                    });
                    datasets.push({
                        label: name + ' Out',
                        data: points.map(function(p) { return {x: p.timestamp * 1000, y: parseInt(p.delta_out) || 0}; }),
                        backgroundColor: c.outBg, borderColor: c.out, borderWidth: 1,
                        yAxisID: 'y', stack: 'traffic'
                    });
                } else {
                    // Fallback: compute traffic deltas client-side (legacy data without delta columns)
                    var deltas = [];
                    for (var i = 1; i < points.length; i++) {
                        var dIn = Math.max(0, (parseInt(points[i].traffic_in) || 0) - (parseInt(points[i-1].traffic_in) || 0));
                        var dOut = Math.max(0, (parseInt(points[i].traffic_out) || 0) - (parseInt(points[i-1].traffic_out) || 0));
                        deltas.push({ts: points[i].timestamp * 1000, dIn: dIn, dOut: dOut});
                    }
                    datasets.push({
                        label: name + ' In',
                        data: deltas.map(function(d) { return {x: d.ts, y: d.dIn}; }),
                        backgroundColor: c.inBg, borderColor: c.in, borderWidth: 1,
                        yAxisID: 'y', stack: 'traffic'
                    });
                    datasets.push({
                        label: name + ' Out',
                        data: deltas.map(function(d) { return {x: d.ts, y: d.dOut}; }),
                        backgroundColor: c.outBg, borderColor: c.out, borderWidth: 1,
                        yAxisID: 'y', stack: 'traffic'
                    });
                }

                // Speed overlay (line)
                datasets.push({
                    label: name + ' Avg Speed',
                    type: 'line',
                    data: points.map(function(p) { return {x: p.timestamp * 1000, y: parseFloat(p.speed_in) + parseFloat(p.speed_out)}; }),
                    borderColor: c.in, backgroundColor: 'transparent',
                    borderWidth: 1.5, pointRadius: 0, fill: false, tension: 0.3,
                    yAxisID: 'y1', stack: false
                });

                idx++;
            });

            historyChart.data.datasets = datasets;

            // Adjust time unit based on range
            var unitMap = {'1h': 'minute', '6h': 'hour', '24h': 'hour', '7d': 'day', '30d': 'day', '90d': 'day', '1yr': 'month'};
            historyChart.options.scales.x.time.unit = unitMap[historyRange] || 'hour';

            historyChart.update('none');
        });
    }

    // --- Proxy stats table ---
    function updateProxyTable(proxies) {
        if (!proxies || proxies.length === 0) {
            $('#proxyTableBody').html('<tr><td colspan="9" class="text-center">No data available. Enable the Admin Dashboard in Client or Server settings.</td></tr>');
            return;
        }

        var sortCol = $('#proxyTable').data('sortCol') || 'name';
        var sortDir = $('#proxyTable').data('sortDir') || 'asc';

        proxies.sort(function(a, b) {
            var va = a[sortCol], vb = b[sortCol];
            if (typeof va === 'string') {
                return sortDir === 'asc' ? va.localeCompare(vb) : vb.localeCompare(va);
            }
            return sortDir === 'asc' ? va - vb : vb - va;
        });

        var html = '';
        proxies.forEach(function(p) {
            html += '<tr>' +
                '<td>' + $('<span>').text(p.name).html() + '</td>' +
                '<td>' + $('<span>').text(p.type).html() + '</td>' +
                '<td>' + formatSpeed(p.speed_in) + '</td>' +
                '<td>' + formatSpeed(p.speed_out) + '</td>' +
                '<td>' + formatBytes(p.today_in) + '</td>' +
                '<td>' + formatBytes(p.today_out) + '</td>' +
                '<td>' + formatBytes(p.week_in + p.week_out) + '</td>' +
                '<td>' + formatBytes(p.month_in + p.month_out) + '</td>' +
                '<td>' + p.cur_conns + '</td>' +
                '</tr>';
        });
        $('#proxyTableBody').html(html);
    }

    // --- Init ---
    loadProxies();
    initRealtimeChart();
    initHistoryChart();
    updateSummary();
    updateRealtimeChart();
    updateHistoryChart();

    // Timers
    realtimeTimer = setInterval(function() { updateRealtimeChart(); }, 2000);
    summaryTimer = setInterval(function() { updateSummary(); }, 2000);

    // --- Event handlers ---
    $('#proxyFilter').on('change', function() {
        selectedProxy = $(this).val();
        updateRealtimeChart();
    });

    $('#historyProxyFilter').on('change', function() {
        updateHistoryChart();
    });

    $('#pauseBtn').on('click', function() {
        paused = !paused;
        $(this).text(paused ? 'Resume' : 'Pause');
        $(this).toggleClass('btn-warning btn-default');
    });

    $('.range-btn').on('click', function() {
        $('.range-btn').removeClass('active');
        $(this).addClass('active');
        historyRange = $(this).data('range');
        updateHistoryChart();
    });

    $('#proxyTable thead th[data-sort]').on('click', function() {
        var col = $(this).data('sort');
        var table = $('#proxyTable');
        if (table.data('sortCol') === col) {
            table.data('sortDir', table.data('sortDir') === 'asc' ? 'desc' : 'asc');
        } else {
            table.data('sortCol', col);
            table.data('sortDir', 'asc');
        }
        updateSummary();
    });

    $('#refreshBtn').on('click', function() {
        loadProxies();
        updateSummary();
        updateRealtimeChart();
        updateHistoryChart();
    });

    // --- Health Check ---
    function runHealthCheck() {
        $('#healthCheckBtn').prop('disabled', true).find('i').addClass('fa-spin');
        $('#healthResultsBody').html('<tr><td colspan="5" class="text-center">Checking...</td></tr>');
        $.ajax({
            url: '/api/frp/monitor/healthcheck',
            type: 'GET',
            dataType: 'json',
            success: function(resp) {
                $('#healthCheckBtn').prop('disabled', false).find('i').removeClass('fa-spin');
                if (resp.status !== 'ok' || !resp.results || resp.results.length === 0) {
                    $('#healthResultsBody').html('<tr><td colspan="5" class="text-center">No health targets configured. Click "Manage Targets" to add some.</td></tr>');
                    return;
                }
                var html = '';
                resp.results.forEach(function(r) {
                    var statusIcon, latencyClass;
                    if (r.status === 'error') {
                        statusIcon = '<i class="fa fa-times-circle health-error"></i> Error';
                        latencyClass = 'health-latency-bad';
                    } else if (r.latency_ms > 1000) {
                        statusIcon = '<i class="fa fa-exclamation-circle health-warn"></i> Slow';
                        latencyClass = 'health-latency-bad';
                    } else if (r.latency_ms > 300) {
                        statusIcon = '<i class="fa fa-check-circle health-warn"></i> OK';
                        latencyClass = 'health-latency-medium';
                    } else {
                        statusIcon = '<i class="fa fa-check-circle health-ok"></i> Fast';
                        latencyClass = 'health-latency-good';
                    }
                    var latencyText = r.latency_ms !== null ? r.latency_ms + ' ms' : '-';
                    var codeText = r.http_code || '-';
                    if (r.error) codeText = '<span class="health-error" title="' + $('<span>').text(r.error).html() + '">' + (r.error.length > 30 ? r.error.substring(0, 30) + '...' : r.error) + '</span>';
                    html += '<tr class="' + latencyClass + '">' +
                        '<td>' + $('<span>').text(r.label).html() + '</td>' +
                        '<td><small>' + $('<span>').text(r.url).html() + '</small></td>' +
                        '<td>' + statusIcon + '</td>' +
                        '<td>' + latencyText + '</td>' +
                        '<td>' + codeText + '</td>' +
                        '</tr>';
                });
                $('#healthResultsBody').html(html);
            },
            error: function() {
                $('#healthCheckBtn').prop('disabled', false).find('i').removeClass('fa-spin');
                $('#healthResultsBody').html('<tr><td colspan="5" class="text-center">No health targets configured. Click "Manage Targets" to add some.</td></tr>');
            }
        });
    }

    $('#healthCheckBtn').on('click', function() { runHealthCheck(); });
    $('#manageTargetsBtn').on('click', function() {
        $('#healthTargetsSection').toggle();
    });

    // Health targets bootgrid
    $('#grid-healthtargets').UIBootgrid({
        search: '/api/frp/healthcheck/searchItem',
        get: '/api/frp/healthcheck/getItem/',
        set: '/api/frp/healthcheck/setItem/',
        add: '/api/frp/healthcheck/addItem/',
        del: '/api/frp/healthcheck/delItem/',
        toggle: '/api/frp/healthcheck/toggleItem/',
        options: {
            requestHandler: function(request) {
                request['frp'] = {};
                return request;
            }
        }
    });

    // Auto-check on page load
    runHealthCheck();
});
</script>

<div class="content-box" style="padding: 10px;">
    <!-- Summary Cards -->
    <div class="monitor-cards">
        <div class="monitor-card">
            <div class="card-value" id="card-speed-in">-</div>
            <div class="card-label">{{ lang._('Current Speed In') }}</div>
        </div>
        <div class="monitor-card">
            <div class="card-value" id="card-speed-out">-</div>
            <div class="card-label">{{ lang._('Current Speed Out') }}</div>
        </div>
        <div class="monitor-card">
            <div class="card-value" id="card-conns">-</div>
            <div class="card-label">{{ lang._('Active Connections') }}</div>
        </div>
        <div class="monitor-card">
            <div class="card-value" id="card-today-in">-</div>
            <div class="card-label">{{ lang._('Today In') }}</div>
        </div>
        <div class="monitor-card">
            <div class="card-value" id="card-today-out">-</div>
            <div class="card-label">{{ lang._('Today Out') }}</div>
        </div>
    </div>

    <!-- Real-time Speed Chart -->
    <div class="chart-container">
        <div class="chart-header">
            <h3>{{ lang._('Real-time Speed') }}</h3>
            <div class="chart-controls">
                <select id="proxyFilter" class="form-control" style="width: auto; display: inline-block; min-width: 150px;">
                    <option value="">{{ lang._('All Proxies') }}</option>
                </select>
                <button id="pauseBtn" class="btn btn-default btn-xs">{{ lang._('Pause') }}</button>
                <button id="refreshBtn" class="btn btn-default btn-xs"><i class="fa fa-refresh"></i></button>
            </div>
        </div>
        <div style="height: 280px;">
            <canvas id="realtimeCanvas"></canvas>
        </div>
    </div>

    <!-- Historical Traffic Chart -->
    <div class="chart-container">
        <div class="chart-header">
            <h3>{{ lang._('Historical Traffic') }}</h3>
            <div class="chart-controls">
                <select id="historyProxyFilter" class="form-control" style="width: auto; display: inline-block; min-width: 150px;">
                    <option value="">{{ lang._('All Proxies') }}</option>
                </select>
                <button class="range-btn" data-range="1h">1h</button>
                <button class="range-btn active" data-range="24h">24h</button>
                <button class="range-btn" data-range="7d">7d</button>
                <button class="range-btn" data-range="30d">30d</button>
                <button class="range-btn" data-range="1yr">1yr</button>
            </div>
        </div>
        <div style="height: 280px;">
            <canvas id="historyCanvas"></canvas>
        </div>
    </div>

    <!-- Per-proxy Stats Table -->
    <div class="chart-container">
        <div class="chart-header">
            <h3>{{ lang._('Proxy Statistics') }}</h3>
        </div>
        <table id="proxyTable" class="table table-condensed table-hover table-striped proxy-table" data-sort-col="name" data-sort-dir="asc">
            <thead>
                <tr>
                    <th data-sort="name">{{ lang._('Name') }}</th>
                    <th data-sort="type">{{ lang._('Type') }}</th>
                    <th data-sort="speed_in">{{ lang._('Speed In') }}</th>
                    <th data-sort="speed_out">{{ lang._('Speed Out') }}</th>
                    <th data-sort="today_in">{{ lang._('Today In') }}</th>
                    <th data-sort="today_out">{{ lang._('Today Out') }}</th>
                    <th>{{ lang._('7-Day') }}</th>
                    <th>{{ lang._('30-Day') }}</th>
                    <th data-sort="cur_conns">{{ lang._('Connections') }}</th>
                </tr>
            </thead>
            <tbody id="proxyTableBody">
                <tr><td colspan="9" class="text-center">{{ lang._('Loading...') }}</td></tr>
            </tbody>
        </table>
    </div>

    <!-- Health Check -->
    <div class="chart-container">
        <div class="chart-header">
            <h3>{{ lang._('Health Check') }}</h3>
            <div>
                <button id="healthCheckBtn" class="btn btn-primary btn-xs"><i class="fa fa-heartbeat"></i> {{ lang._('Check Now') }}</button>
                <button id="manageTargetsBtn" class="btn btn-default btn-xs"><i class="fa fa-cog"></i> {{ lang._('Manage Targets') }}</button>
            </div>
        </div>
        <table class="table table-condensed table-hover table-striped">
            <thead>
                <tr>
                    <th>{{ lang._('Label') }}</th>
                    <th>{{ lang._('URL') }}</th>
                    <th>{{ lang._('Status') }}</th>
                    <th>{{ lang._('Latency') }}</th>
                    <th>{{ lang._('Details') }}</th>
                </tr>
            </thead>
            <tbody id="healthResultsBody">
                <tr><td colspan="5" class="text-center">{{ lang._('Click "Check Now" to test connectivity.') }}</td></tr>
            </tbody>
        </table>

        <div id="healthTargetsSection">
            <hr/>
            <h4>{{ lang._('Health Check Targets') }}</h4>
            <table id="grid-healthtargets" class="table table-condensed table-hover table-striped" data-editDialog="DialogHealthTarget" data-editAlert="frpChangeMessage">
                <thead>
                    <tr>
                        <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">{{ lang._('ID') }}</th>
                        <th data-column-id="enabled" data-width="6em" data-type="string" data-formatter="rowtoggle">{{ lang._('Enabled') }}</th>
                        <th data-column-id="label" data-type="string">{{ lang._('Label') }}</th>
                        <th data-column-id="url" data-type="string">{{ lang._('URL') }}</th>
                        <th data-column-id="commands" data-width="7em" data-formatter="commands" data-sortable="false">{{ lang._('Commands') }}</th>
                    </tr>
                </thead>
                <tbody></tbody>
                <tfoot>
                    <tr>
                        <td></td>
                        <td>
                            <button data-action="add" type="button" class="btn btn-xs btn-primary"><span class="fa fa-fw fa-plus"></span></button>
                            <button data-action="deleteSelected" type="button" class="btn btn-xs btn-default"><span class="fa fa-fw fa-trash-o"></span></button>
                        </td>
                    </tr>
                </tfoot>
            </table>
        </div>
    </div>

    {{ partial("layout_partials/base_dialog",['fields':healthTargetForm,'id':'DialogHealthTarget','label':lang._('Edit Health Target')]) }}
</div>
