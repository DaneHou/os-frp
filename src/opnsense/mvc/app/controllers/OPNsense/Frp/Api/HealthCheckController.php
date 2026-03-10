<?php

namespace OPNsense\Frp\Api;

use OPNsense\Base\ApiMutableModelControllerBase;

class HealthCheckController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'client';
    protected static $internalModelClass = 'OPNsense\Frp\Client';

    public function searchItemAction()
    {
        return $this->searchBase('healthTargets.healthTarget', ['enabled', 'label', 'url']);
    }

    public function getItemAction($uuid = null)
    {
        return $this->getBase('healthTarget', 'healthTargets.healthTarget', $uuid);
    }

    public function addItemAction()
    {
        return $this->addBase('healthTarget', 'healthTargets.healthTarget');
    }

    public function setItemAction($uuid)
    {
        return $this->setBase('healthTarget', 'healthTargets.healthTarget', $uuid);
    }

    public function delItemAction($uuid)
    {
        return $this->delBase('healthTargets.healthTarget', $uuid);
    }

    public function toggleItemAction($uuid, $enabled = null)
    {
        return $this->toggleBase('healthTargets.healthTarget', $uuid, $enabled);
    }
}
