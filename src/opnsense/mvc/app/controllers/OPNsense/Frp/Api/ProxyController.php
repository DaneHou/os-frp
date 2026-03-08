<?php

namespace OPNsense\Frp\Api;

use OPNsense\Base\ApiMutableModelControllerBase;

class ProxyController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'proxy';
    protected static $internalModelClass = 'OPNsense\Frp\Proxy';

    public function searchItemAction()
    {
        return $this->searchBase('proxies.proxy', ['enabled', 'name', 'proxyType', 'localIP', 'localPort', 'remotePort']);
    }

    public function getItemAction($uuid = null)
    {
        return $this->getBase('proxy', 'proxies.proxy', $uuid);
    }

    public function addItemAction()
    {
        return $this->addBase('proxy', 'proxies.proxy');
    }

    public function setItemAction($uuid)
    {
        return $this->setBase('proxy', 'proxies.proxy', $uuid);
    }

    public function delItemAction($uuid)
    {
        return $this->delBase('proxies.proxy', $uuid);
    }

    public function toggleItemAction($uuid, $enabled = null)
    {
        return $this->toggleBase('proxies.proxy', $uuid, $enabled);
    }
}
