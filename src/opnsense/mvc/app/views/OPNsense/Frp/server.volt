{#
 # Copyright (C) 2024 os-frp
 # All rights reserved.
 #}

<script>
    $(document).ready(function() {
        mapDataToFormUI({'frm_server': '/api/frp/settings/getServer'}).done(function() {
            formatTokenizersUI();
            $('.selectpicker').selectpicker('refresh');
        });

        $("#saveAct").click(function(){
            saveFormToEndpoint('/api/frp/settings/setServer', 'frm_server', function(){
                ajaxCall('/api/frp/service/reconfigure', {}, function(data, status) {
                    // Reconfigure done
                });
            });
        });

        // Docker config export
        $("#exportDockerConfig").click(function(){
            $.ajax({
                url: '/api/frp/settings/exportDockerConfig',
                type: 'GET',
                data: { mode: 'client' },
                dataType: 'json',
                success: function(resp) {
                    if (resp.status === 'ok') {
                        var blob = new Blob([resp.config], { type: 'text/plain' });
                        var url = URL.createObjectURL(blob);
                        var a = document.createElement('a');
                        a.href = url;
                        a.download = resp.filename;
                        document.body.appendChild(a);
                        a.click();
                        document.body.removeChild(a);
                        URL.revokeObjectURL(url);
                    } else {
                        alert(resp.message || 'Export failed');
                    }
                }
            });
        });

        updateServiceControlUI('frp');
    });
</script>

<div class="content-box" style="padding: 10px;">
    <div class="col-md-12">
        {{ partial("layout_partials/base_form",['fields':serverForm,'id':'frm_server'])}}
    </div>
    <div class="col-md-12">
        <hr />
        <button class="btn btn-primary" id="saveAct" type="button"><b>{{ lang._('Save') }}</b> <i id="saveAct_progress"></i></button>
        <button class="btn btn-default" id="exportDockerConfig" type="button"><i class="fa fa-download"></i> {{ lang._('Export Docker Client Config') }}</button>
    </div>
</div>
