<?php

namespace OPNsense\Frp\Api;

use OPNsense\Base\ApiMutableModelControllerBase;
use OPNsense\Core\Config;

class TuningController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'tuning';
    protected static $internalModelClass = 'OPNsense\Frp\Tuning';

    public function getAction()
    {
        return ['tuning' => $this->getModel()->getNodes()];
    }

    public function setAction()
    {
        $result = ['result' => 'failed'];
        if ($this->request->isPost()) {
            $mdl = $this->getModel();
            $post = $this->request->getPost('tuning');
            if ($post) {
                $mdl->setNodes($post);
            }
            $valMsgs = $mdl->performValidation();
            foreach ($valMsgs as $msg) {
                if (!isset($result['validations'])) {
                    $result['validations'] = [];
                }
                $result['validations']['tuning.' . $msg->getField()] = $msg->getMessage();
            }
            if (empty($result['validations'])) {
                $mdl->serializeToConfig();
                Config::getInstance()->save();
                $result = ['result' => 'saved'];
            }
        }
        return $result;
    }
}
