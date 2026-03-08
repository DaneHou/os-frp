<?php

namespace OPNsense\Frp;

use OPNsense\Base\IndexController;

class ShadowsocksController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/Frp/shadowsocks');
        $this->view->shadowsocksForm = $this->getForm('shadowsocks');
    }
}
