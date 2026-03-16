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

    // --- Docker Config Export ---

    public function exportDockerConfigAction()
    {
        $result = ['status' => 'error', 'message' => 'Invalid request'];

        $mode = $this->request->get('mode', 'string', '');

        if ($mode === 'client') {
            // OPNsense runs server, export client frpc.toml for Docker peer
            $mdl = new \OPNsense\Frp\Server();
            $serverEnabled = (string)$mdl->enabled;
            if ($serverEnabled !== '1') {
                return ['status' => 'error', 'message' => 'FRP Server is not enabled'];
            }

            $bindPort = (string)($mdl->bindPort ?? '7000');
            $authMethod = (string)($mdl->authMethod ?? '');
            $authToken = (string)($mdl->authToken ?? '');
            $transportTcpMux = (string)($mdl->transportTcpMux ?? '1');
            $quicBindPort = (string)($mdl->quicBindPort ?? '0');

            $toml = "# frpc.toml — Generated from OPNsense FRP Server config\n";
            $toml .= "# Deploy this on the Docker client peer\n\n";
            $toml .= "serverAddr = \"YOUR_SERVER_IP\"\n";
            $toml .= "serverPort = {$bindPort}\n\n";

            if ($authMethod === 'token' && !empty($authToken)) {
                $toml .= "auth.method = \"token\"\n";
                $toml .= "auth.token = \"{$authToken}\"\n\n";
            }

            $toml .= "transport.tcpMux = " . ($transportTcpMux === '1' ? 'true' : 'false') . "\n";

            if ((int)$quicBindPort > 0) {
                $toml .= "# QUIC is available on port {$quicBindPort}\n";
                $toml .= "# transport.protocol = \"quic\"\n";
            }

            $toml .= "\nlog.to = \"/var/log/frp/frpc.log\"\nlog.level = \"info\"\n";
            $toml .= "\n# Add your proxy definitions below:\n";
            $toml .= "# [[proxies]]\n# name = \"example\"\n# type = \"tcp\"\n# localIP = \"127.0.0.1\"\n# localPort = 80\n# remotePort = 8080\n";

            return ['status' => 'ok', 'config' => $toml, 'filename' => 'frpc.toml'];

        } elseif ($mode === 'server') {
            // OPNsense runs client, export server frps.toml for Docker peer
            $mdl = $this->getModel();
            $clientEnabled = (string)$mdl->enabled;
            if ($clientEnabled !== '1') {
                return ['status' => 'error', 'message' => 'FRP Client is not enabled'];
            }

            $serverPort = (string)($mdl->serverPort ?? '7000');
            $authMethod = (string)($mdl->authMethod ?? '');
            $authToken = (string)($mdl->authToken ?? '');
            $transportTcpMux = (string)($mdl->transportTcpMux ?? '1');
            $transportProtocol = (string)($mdl->transportProtocol ?? 'tcp');

            $toml = "# frps.toml — Generated from OPNsense FRP Client config\n";
            $toml .= "# Deploy this on the Docker server peer\n\n";
            $toml .= "bindAddr = \"0.0.0.0\"\n";
            $toml .= "bindPort = {$serverPort}\n\n";

            if ($authMethod === 'token' && !empty($authToken)) {
                $toml .= "auth.method = \"token\"\n";
                $toml .= "auth.token = \"{$authToken}\"\n\n";
            }

            $toml .= "transport.tcpMux = " . ($transportTcpMux === '1' ? 'true' : 'false') . "\n";

            if ($transportProtocol === 'quic') {
                $toml .= "quicBindPort = {$serverPort}\n";
            }

            $toml .= "\nlog.to = \"/var/log/frp/frps.log\"\nlog.level = \"info\"\n";
            $toml .= "\nwebServer.addr = \"0.0.0.0\"\nwebServer.port = 7500\n";

            return ['status' => 'ok', 'config' => $toml, 'filename' => 'frps.toml'];
        }

        return $result;
    }

}
