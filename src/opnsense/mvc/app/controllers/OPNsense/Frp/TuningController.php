<?php

namespace OPNsense\Frp;

use OPNsense\Base\IndexController;

class TuningController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/Frp/tuning');
        $this->view->tuningForm = $this->getForm('tuning');
    }
}
