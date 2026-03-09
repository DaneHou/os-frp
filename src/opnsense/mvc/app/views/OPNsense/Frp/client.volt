{#
 # Copyright (C) 2024 os-frp
 # All rights reserved.
 #}

<script>
    $(document).ready(function() {
        mapDataToFormUI({'frm_client': '/api/frp/settings/getClient'}).done(function() {
            formatTokenizersUI();
            $('.selectpicker').selectpicker('refresh');

            // Hide advanced fields by default
            $('.advanced_fields').closest('tr').hide();

            // Toggle advanced fields visibility
            $('#client\\.showAdvanced').change(function() {
                if ($(this).is(':checked')) {
                    $('.advanced_fields').closest('tr').show();
                } else {
                    $('.advanced_fields').closest('tr').hide();
                }
            });
        });

        $("#saveAct").click(function(){
            saveFormToEndpoint('/api/frp/settings/setClient', 'frm_client', function(){
                ajaxCall('/api/frp/service/reconfigure', {}, function(data, status) {
                    // Reconfigure done
                });
            });
        });

        updateServiceControlUI('frp');
    });
</script>

<div class="content-box" style="padding: 10px;">
    <div class="col-md-12">
        {{ partial("layout_partials/base_form",['fields':clientForm,'id':'frm_client'])}}
    </div>
    <div class="col-md-12">
        <hr />
        <button class="btn btn-primary" id="saveAct" type="button"><b>{{ lang._('Save') }}</b> <i id="saveAct_progress"></i></button>
    </div>
</div>
