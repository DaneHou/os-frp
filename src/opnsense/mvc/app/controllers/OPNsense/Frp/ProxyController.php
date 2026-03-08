<?php

namespace OPNsense\Frp;

use OPNsense\Base\IndexController;

class ProxyController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/Frp/proxy');
        $this->view->proxyForm = $this->getForm('proxy');
    }
}
