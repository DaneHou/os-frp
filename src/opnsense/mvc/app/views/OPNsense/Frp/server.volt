{#
 # Copyright (C) 2024 os-frp
 # All rights reserved.
 #}

<script>
    $(document).ready(function() {
        mapDataToFormUI({'frm_server': '/api/frp/server/get'}).done(function() {
            formatTokenizersUI();
            $('.selectpicker').selectpicker('refresh');
        });

        $("#saveAct").click(function(){
            saveFormToEndpoint('/api/frp/server/set', 'frm_server', function(){
                ajaxCall('/api/frp/frpservice/reconfigure', {}, function(data, status) {
                    // Reconfigure done
                });
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
    </div>
</div>
