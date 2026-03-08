<?php

namespace OPNsense\Frp\Api;

use OPNsense\Base\ApiMutableModelControllerBase;

class ClientController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'client';
    protected static $internalModelClass = 'OPNsense\Frp\Client';
}
