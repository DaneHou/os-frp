<?php

namespace OPNsense\Frp;

use OPNsense\Base\IndexController;

class LogsController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/Frp/logs');
    }
}
