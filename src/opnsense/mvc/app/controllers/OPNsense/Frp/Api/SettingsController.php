<?php

namespace OPNsense\Frp\Api;

use OPNsense\Base\ApiMutableModelControllerBase;
use OPNsense\Core\Config;

class SettingsController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'Frp';
    protected static $internalModelClass = 'OPNsense\Frp\Client';

    // --- Client settings ---

    public function getClientAction()
    {
        return ['client' => $this->getModel()->getNodes()];
    }

    public function setClientAction()
    {
        $result = ['result' => 'failed'];
        if ($this->request->isPost()) {
            $mdl = $this->getModel();
            $post = $this->request->getPost('client');
            if ($post) {
                $mdl->setNodes($post);
            }
            $valMsgs = $mdl->performValidation();
            foreach ($valMsgs as $msg) {
                if (!isset($result['validations'])) {
                    $result['validations'] = [];
                }
                $result['validations']['client.' . $msg->getField()] = $msg->getMessage();
            }
            if (empty($result['validations'])) {
                $mdl->serializeToConfig();
                Config::getInstance()->save();
                $result = ['result' => 'saved'];
            }
        }
        return $result;
    }

    // --- Server settings ---

    public function getServerAction()
    {
        $mdl = new \OPNsense\Frp\Server();
        return ['server' => $mdl->getNodes()];
    }

    public function setServerAction()
    {
        $result = ['result' => 'failed'];
        if ($this->request->isPost()) {
            $mdl = new \OPNsense\Frp\Server();
            $post = $this->request->getPost('server');
            if ($post) {
                $mdl->setNodes($post);
            }
            $valMsgs = $mdl->performValidation();
            foreach ($valMsgs as $msg) {
                if (!isset($result['validations'])) {
                    $result['validations'] = [];
                }
                $result['validations']['server.' . $msg->getField()] = $msg->getMessage();
            }
            if (empty($result['validations'])) {
                $mdl->serializeToConfig();
                Config::getInstance()->save();
                $result = ['result' => 'saved'];
            }
        }
        return $result;
    }

    // --- Tuning settings ---

    public function getTuningAction()
    {
        $mdl = new \OPNsense\Frp\Tuning();
        return ['tuning' => $mdl->getNodes()];
    }

    public function setTuningAction()
    {
        $result = ['result' => 'failed'];
        if ($this->request->isPost()) {
            $mdl = new \OPNsense\Frp\Tuning();
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
