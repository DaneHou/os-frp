<?php

namespace OPNsense\Frp\Api;

use OPNsense\Base\ApiMutableServiceControllerBase;

class ServiceController extends ApiMutableServiceControllerBase
{
    protected static $internalServiceClass = '';
    protected static $internalServiceEnabled = '';
    protected static $internalServiceTemplate = 'OPNsense/Frp';
    protected static $internalServiceName = 'frp';

    /**
     * Reconfigure FRP service
     * @return array
     */
    public function reconfigureAction()
    {
        if ($this->request->isPost()) {
            $backend = new \OPNsense\Core\Backend();
            // Generate template configs
            $backend->configdRun('template reload OPNsense/Frp');
            // Restart FRP service
            $backend->configdRun('frp reconfigure');
            return ['status' => 'ok'];
        }
        return ['status' => 'failed'];
    }

    /**
     * Start FRP service
     * @return array
     */
    public function startAction()
    {
        if ($this->request->isPost()) {
            $backend = new \OPNsense\Core\Backend();
            $backend->configdRun('template reload OPNsense/Frp');
            $backend->configdRun('frp start');
            return ['result' => 'ok'];
        }
        return ['result' => 'failed'];
    }

    /**
     * Stop FRP service
     * @return array
     */
    public function stopAction()
    {
        if ($this->request->isPost()) {
            $backend = new \OPNsense\Core\Backend();
            $backend->configdRun('frp stop');
            return ['result' => 'ok'];
        }
        return ['result' => 'failed'];
    }

    /**
     * Get FRP service status
     * @return array
     */
    public function statusAction()
    {
        $backend = new \OPNsense\Core\Backend();
        $response = trim($backend->configdRun('frp status'));
        if (strpos($response, 'is running') !== false) {
            return ['result' => 'running'];
        }
        return ['result' => 'stopped'];
    }
}
