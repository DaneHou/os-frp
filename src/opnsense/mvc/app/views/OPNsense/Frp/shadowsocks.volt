{#
 # Copyright (C) 2024 os-frp
 # All rights reserved.
 #}

<script>
    $(document).ready(function() {
        mapDataToFormUI({'frm_shadowsocks': '/api/frp/shadowsocks/get'}).done(function() {
            formatTokenizersUI();
            $('.selectpicker').selectpicker('refresh');
        });

        $("#saveAct").click(function(){
            saveFormToEndpoint('/api/frp/shadowsocks/set', 'frm_shadowsocks', function(){
                ajaxCall('/api/frp/ssservice/reconfigure', {}, function(data, status) {
                    // Reconfigure done
                });
            });
        });

        updateServiceControlUI('frpss');
    });
</script>

<div class="content-box" style="padding: 10px;">
    <div class="col-md-12">
        {{ partial("layout_partials/base_form",['fields':shadowsocksForm,'id':'frm_shadowsocks'])}}
    </div>
    <div class="col-md-12">
        <hr />
        <button class="btn btn-primary" id="saveAct" type="button"><b>{{ lang._('Save') }}</b> <i id="saveAct_progress"></i></button>
    </div>
</div>
