{#
 # Copyright (C) 2024 os-frp
 # All rights reserved.
 #}

<script>
    $(document).ready(function() {
        mapDataToFormUI({'frm_tuning': '/api/frp/settings/getTuning'}).done(function() {
            formatTokenizersUI();
            $('.selectpicker').selectpicker('refresh');
        });

        $("#saveAct").click(function(){
            saveFormToEndpoint('/api/frp/settings/setTuning', 'frm_tuning', function(){
                $("#saveAct_progress").addClass("fa fa-spinner fa-pulse");
                ajaxCall('/api/frp/frpservice/reconfigure', {}, function(data, status) {
                    $("#saveAct_progress").removeClass("fa fa-spinner fa-pulse");
                });
            });
        });
    });
</script>

<div class="content-box" style="padding: 10px;">
    <div class="col-md-12">
        {{ partial("layout_partials/base_form",['fields':tuningForm,'id':'frm_tuning'])}}
    </div>
    <div class="col-md-12">
        <hr />
        <button class="btn btn-primary" id="saveAct" type="button"><b>{{ lang._('Save & Apply') }}</b> <i id="saveAct_progress"></i></button>
    </div>
</div>
