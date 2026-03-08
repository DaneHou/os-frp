<?php

namespace OPNsense\Frp\Api;

use OPNsense\Base\ApiMutableModelControllerBase;

class ServerController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'server';
    protected static $internalModelClass = 'OPNsense\Frp\Server';
}
