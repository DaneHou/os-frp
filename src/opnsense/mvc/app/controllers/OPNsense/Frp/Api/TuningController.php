<?php

namespace OPNsense\Frp\Api;

use OPNsense\Base\ApiMutableModelControllerBase;

class TuningController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'tuning';
    protected static $internalModelClass = 'OPNsense\Frp\Tuning';
}
