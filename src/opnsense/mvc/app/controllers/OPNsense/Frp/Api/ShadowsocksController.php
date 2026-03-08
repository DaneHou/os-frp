<?php

namespace OPNsense\Frp\Api;

use OPNsense\Base\ApiMutableModelControllerBase;

class ShadowsocksController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'shadowsocks';
    protected static $internalModelClass = 'OPNsense\Frp\Shadowsocks';
}
