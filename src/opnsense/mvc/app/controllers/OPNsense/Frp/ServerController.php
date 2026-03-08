<?php

namespace OPNsense\Frp;

use OPNsense\Base\IndexController;

class ServerController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/Frp/server');
        $this->view->serverForm = $this->getForm('server');
    }
}
