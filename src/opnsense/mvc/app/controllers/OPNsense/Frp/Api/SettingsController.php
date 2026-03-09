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

    // --- Logs ---

    public function getLogsAction()
    {
        $logDir = '/var/log/frp';
        $name = $this->request->get('name', 'string', 'frpc');
        $lines = (int)$this->request->get('lines', 'int', 100);

        // Validate
        if (!preg_match('/^[a-zA-Z0-9_-]+$/', $name)) {
            return ['status' => 'error', 'message' => 'Invalid log name'];
        }
        $lines = max(10, min(1000, $lines));

        $logFile = "{$logDir}/{$name}.log";
        if (!file_exists($logFile)) {
            return ['status' => 'ok', 'name' => $name, 'lines' => []];
        }

        $output = [];
        exec("/usr/bin/tail -n {$lines} " . escapeshellarg($logFile), $output);
        return ['status' => 'ok', 'name' => $name, 'lines' => $output];
    }

    public function getLogFilesAction()
    {
        $logDir = '/var/log/frp';
        $files = [];
        if (is_dir($logDir)) {
            foreach (glob("{$logDir}/*.log") as $f) {
                $files[] = basename($f, '.log');
            }
        }
        return ['status' => 'ok', 'files' => $files];
    }

    public function clearLogsAction()
    {
        if ($this->request->isPost()) {
            $name = $this->request->getPost('name', 'string', '');
            $logDir = '/var/log/frp';
            if ($name && preg_match('/^[a-zA-Z0-9_-]+$/', $name)) {
                $logFile = "{$logDir}/{$name}.log";
                if (file_exists($logFile)) {
                    @file_put_contents($logFile, '');
                }
            } else {
                // Clear all
                foreach (glob("{$logDir}/*.log") as $f) {
                    @file_put_contents($f, '');
                }
            }
            return ['status' => 'ok'];
        }
        return ['status' => 'failed'];
    }

}
