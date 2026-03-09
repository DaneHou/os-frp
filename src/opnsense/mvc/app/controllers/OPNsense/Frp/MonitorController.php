<?php

namespace OPNsense\Frp;

use OPNsense\Base\IndexController;

class MonitorController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/Frp/monitor');
    }
}
