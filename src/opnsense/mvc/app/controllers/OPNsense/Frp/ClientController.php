<?php

namespace OPNsense\Frp;

use OPNsense\Base\IndexController;

class ClientController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/Frp/client');
        $this->view->clientForm = $this->getForm('client');
        $this->view->proxyForm = $this->getForm('proxy');
    }
}
