{#
 # Copyright (C) 2024 os-frp
 # All rights reserved.
 #}

<script>
    $(document).ready(function() {
        $("#grid-proxies").UIBootgrid({
            search:'/api/frp/proxy/searchItem',
            get:'/api/frp/proxy/getItem/',
            set:'/api/frp/proxy/setItem/',
            add:'/api/frp/proxy/addItem/',
            del:'/api/frp/proxy/delItem/',
            toggle:'/api/frp/proxy/toggleItem/',
            options: {
                requestHandler: function(request) {
                    // Add default sort
                    if (request.sort === undefined) {
                        request.sort = {};
                    }
                    return request;
                }
            }
        });

        /**
         * Show/hide fields based on proxy type
         */
        $(document).on('change', '#proxy\\.proxyType', function() {
            var proxyType = $(this).val();
            // tcp/udp fields
            if (proxyType === 'tcp' || proxyType === 'udp') {
                $('tr[id="row_proxy.remotePort"]').show();
                $('tr[id="row_proxy.customDomains"]').hide();
                $('tr[id="row_proxy.subdomain"]').hide();
                $('tr[id="row_proxy.httpUser"]').hide();
                $('tr[id="row_proxy.httpPassword"]').hide();
                $('tr[id="row_proxy.secretKey"]').hide();
            }
            // http/https fields
            else if (proxyType === 'http' || proxyType === 'https') {
                $('tr[id="row_proxy.remotePort"]').hide();
                $('tr[id="row_proxy.customDomains"]').show();
                $('tr[id="row_proxy.subdomain"]').show();
                $('tr[id="row_proxy.httpUser"]').show();
                $('tr[id="row_proxy.httpPassword"]').show();
                $('tr[id="row_proxy.secretKey"]').hide();
            }
            // stcp/xtcp fields
            else if (proxyType === 'stcp' || proxyType === 'xtcp') {
                $('tr[id="row_proxy.remotePort"]').hide();
                $('tr[id="row_proxy.customDomains"]').hide();
                $('tr[id="row_proxy.subdomain"]').hide();
                $('tr[id="row_proxy.httpUser"]').hide();
                $('tr[id="row_proxy.httpPassword"]').hide();
                $('tr[id="row_proxy.secretKey"]').show();
            }
            // Other types
            else {
                $('tr[id="row_proxy.remotePort"]').show();
                $('tr[id="row_proxy.customDomains"]').hide();
                $('tr[id="row_proxy.subdomain"]').hide();
                $('tr[id="row_proxy.httpUser"]').hide();
                $('tr[id="row_proxy.httpPassword"]').hide();
                $('tr[id="row_proxy.secretKey"]').hide();
            }
        });

        /**
         * Reconfigure on apply
         */
        $("#reconfigureAct").click(function(){
            $("#reconfigureAct_progress").addClass("fa fa-spinner fa-pulse");
            ajaxCall('/api/frp/frpservice/reconfigure', {}, function(data, status) {
                $("#reconfigureAct_progress").removeClass("fa fa-spinner fa-pulse");
            });
        });
    });
</script>

<div class="tab-content content-box">
    <table id="grid-proxies" class="table table-condensed table-hover table-striped" data-editDialog="DialogProxy" data-editAlert="ProxyChangeMessage">
        <thead>
            <tr>
                <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">{{ lang._('ID') }}</th>
                <th data-column-id="enabled" data-width="6em" data-type="string" data-formatter="rowtoggle">{{ lang._('Enabled') }}</th>
                <th data-column-id="name" data-type="string">{{ lang._('Name') }}</th>
                <th data-column-id="proxyType" data-type="string">{{ lang._('Type') }}</th>
                <th data-column-id="localIP" data-type="string">{{ lang._('Local IP') }}</th>
                <th data-column-id="localPort" data-type="string">{{ lang._('Local Port') }}</th>
                <th data-column-id="remotePort" data-type="string">{{ lang._('Remote Port') }}</th>
                <th data-column-id="commands" data-width="7em" data-formatter="commands" data-sortable="false">{{ lang._('Commands') }}</th>
            </tr>
        </thead>
        <tbody>
        </tbody>
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
    <div class="col-md-12">
        <div id="ProxyChangeMessage" class="alert alert-info" style="display: none" role="alert">
            {{ lang._('After changing settings, please remember to apply them with the button below') }}
        </div>
        <hr />
        <button class="btn btn-primary" id="reconfigureAct" type="button"><b>{{ lang._('Apply') }}</b> <i id="reconfigureAct_progress"></i></button>
    </div>
</div>

{{ partial("layout_partials/base_dialog",['fields':proxyForm,'id':'DialogProxy','label':lang._('Edit Proxy')])}}
