{#
 # Copyright (C) 2024 os-frp
 # All rights reserved.
 #}

<style>
    #log-output {
        height: 500px;
        overflow-y: auto;
        background: #1e1e1e;
        color: #d4d4d4;
        font-family: 'Courier New', monospace;
        font-size: 12px;
        padding: 10px;
        border: 1px solid #333;
        border-radius: 4px;
        white-space: pre-wrap;
        word-wrap: break-word;
    }
</style>

<script>
    var autoScroll = true;
    var refreshTimer = null;

    function loadLogFiles() {
        ajaxGet('/api/frp/settings/getLogFiles', {}, function(data, status) {
            if (data && data.status === 'ok' && data.files && data.files.length > 0) {
                var sel = $('#log-filter');
                sel.empty();
                $.each(data.files, function(i, name) {
                    sel.append($('<option>').val(name).text(name));
                });
                sel.selectpicker('refresh');
                refreshLogs();
            } else {
                $('#log-output').text('No log files found. Start the FRP service first, then refresh.');
            }
        }).fail(function() {
            $('#log-output').text('Failed to load log files. Check API endpoint.');
        });
    }

    function refreshLogs() {
        var name = $('#log-filter').val();
        var lines = $('#log-lines').val();
        if (!name) return;

        ajaxGet('/api/frp/settings/getLogs', {name: name, lines: lines}, function(data, status) {
            var output = $('#log-output');
            if (data && data.status === 'ok') {
                if (!data.lines || data.lines.length === 0) {
                    output.text('(no log entries)');
                } else {
                    output.text(data.lines.join('\n'));
                }
                if (autoScroll) {
                    output.scrollTop(output[0].scrollHeight);
                }
            } else {
                output.text('Failed to read log file.');
            }
        }).fail(function() {
            $('#log-output').text('Failed to fetch logs.');
        });
    }

    $(document).ready(function() {
        loadLogFiles();

        // Auto-refresh every 5 seconds
        refreshTimer = setInterval(refreshLogs, 5000);

        $('#log-filter').on('changed.bs.select', function() {
            refreshLogs();
        });

        $('#log-lines').on('changed.bs.select', function() {
            refreshLogs();
        });

        $('#btn-refresh').click(function() {
            refreshLogs();
        });

        $('#btn-autoscroll').click(function() {
            autoScroll = !autoScroll;
            $(this).toggleClass('btn-primary btn-default');
            $(this).find('span').text(autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF');
        });

        $('#btn-clear').click(function() {
            if (confirm('Clear logs for ' + $('#log-filter').val() + '?')) {
                ajaxCall('/api/frp/settings/clearLogs', {name: $('#log-filter').val()}, function(data, status) {
                    refreshLogs();
                });
            }
        });
    });
</script>

<div class="content-box" style="padding: 10px;">
    <div class="col-md-12">
        <div class="row" style="margin-bottom: 10px;">
            <div class="col-sm-3">
                <label>{{ lang._('Log File') }}</label>
                <select id="log-filter" class="selectpicker" data-width="100%">
                </select>
            </div>
            <div class="col-sm-2">
                <label>{{ lang._('Lines') }}</label>
                <select id="log-lines" class="selectpicker" data-width="100%">
                    <option value="50">50</option>
                    <option value="100" selected>100</option>
                    <option value="200">200</option>
                    <option value="500">500</option>
                </select>
            </div>
            <div class="col-sm-7" style="padding-top: 24px;">
                <button class="btn btn-default btn-xs" id="btn-refresh" type="button">
                    <i class="fa fa-refresh"></i> {{ lang._('Refresh') }}
                </button>
                <button class="btn btn-primary btn-xs" id="btn-autoscroll" type="button">
                    <span>Auto-scroll ON</span>
                </button>
                <button class="btn btn-danger btn-xs" id="btn-clear" type="button">
                    <i class="fa fa-trash"></i> {{ lang._('Clear') }}
                </button>
            </div>
        </div>
    </div>
    <div class="col-md-12">
        <pre id="log-output">(loading...)</pre>
    </div>
</div>
