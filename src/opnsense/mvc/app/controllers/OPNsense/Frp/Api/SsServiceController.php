<?php

namespace OPNsense\Frp\Api;

use OPNsense\Base\ApiMutableServiceControllerBase;

class SsServiceController extends ApiMutableServiceControllerBase
{
    protected static $internalServiceClass = '';
    protected static $internalServiceEnabled = '';
    protected static $internalServiceTemplate = 'OPNsense/Frp';
    protected static $internalServiceName = 'frpss';

    /**
     * Reconfigure Shadowsocks server
     * @return array
     */
    public function reconfigureAction()
    {
        if ($this->request->isPost()) {
            $backend = new \OPNsense\Core\Backend();
            $backend->configdRun('template reload OPNsense/Frp');
            $backend->configdRun('frpss reconfigure');
            return ['status' => 'ok'];
        }
        return ['status' => 'failed'];
    }

    /**
     * Start Shadowsocks server
     * @return array
     */
    public function startAction()
    {
        if ($this->request->isPost()) {
            $backend = new \OPNsense\Core\Backend();
            $backend->configdRun('template reload OPNsense/Frp');
            $response = trim($backend->configdRun('frpss start'));
            return ['status' => 'ok', 'response' => $response];
        }
        return ['status' => 'failed'];
    }

    /**
     * Stop Shadowsocks server
     * @return array
     */
    public function stopAction()
    {
        if ($this->request->isPost()) {
            $backend = new \OPNsense\Core\Backend();
            $response = trim($backend->configdRun('frpss stop'));
            return ['status' => 'ok', 'response' => $response];
        }
        return ['status' => 'failed'];
    }

    /**
     * Get Shadowsocks server status
     * @return array
     */
    public function statusAction()
    {
        $backend = new \OPNsense\Core\Backend();
        $response = trim($backend->configdRun('frpss status'));
        return ['status' => 'ok', 'response' => $response];
    }
}
