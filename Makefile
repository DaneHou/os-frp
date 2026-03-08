PLUGIN_NAME=	frp
PLUGIN_VERSION=	1.0.0
PLUGIN_COMMENT=	FRP Tunnel for OPNsense

PLUGIN_PREFIX=	/usr/local

# OPNsense paths
CONTROLLERS_DIR=	$(PLUGIN_PREFIX)/opnsense/mvc/app/controllers/OPNsense/Frp
MODELS_DIR=		$(PLUGIN_PREFIX)/opnsense/mvc/app/models/OPNsense/Frp
VIEWS_DIR=		$(PLUGIN_PREFIX)/opnsense/mvc/app/views/OPNsense/Frp
SCRIPTS_DIR=		$(PLUGIN_PREFIX)/opnsense/scripts/OPNsense/Frp
TEMPLATES_DIR=		$(PLUGIN_PREFIX)/opnsense/service/templates/OPNsense/Frp
ACTIONS_DIR=		$(PLUGIN_PREFIX)/opnsense/service/conf/actions.d
HOOKS_DIR=		$(PLUGIN_PREFIX)/etc/inc/plugins.inc.d
RCD_DIR=		$(PLUGIN_PREFIX)/etc/rc.d

# FRP settings
FRP_VERSION=		0.61.1
FRP_ARCH=		freebsd_amd64
FRP_URL=		https://github.com/fatedier/frp/releases/download/v$(FRP_VERSION)/frp_$(FRP_VERSION)_$(FRP_ARCH).tar.gz

.PHONY: install install-plugin install-frp activate uninstall reinstall clean

install: install-plugin install-frp activate
	@echo "==> Full installation complete"

install-plugin:
	@echo "==> Installing os-frp plugin files..."
	@# Controllers
	@mkdir -p $(CONTROLLERS_DIR)/Api
	@mkdir -p $(CONTROLLERS_DIR)/forms
	@cp src/opnsense/mvc/app/controllers/OPNsense/Frp/*.php $(CONTROLLERS_DIR)/
	@cp src/opnsense/mvc/app/controllers/OPNsense/Frp/Api/*.php $(CONTROLLERS_DIR)/Api/
	@cp src/opnsense/mvc/app/controllers/OPNsense/Frp/forms/*.xml $(CONTROLLERS_DIR)/forms/
	@# Models
	@mkdir -p $(MODELS_DIR)/ACL
	@mkdir -p $(MODELS_DIR)/Menu
	@cp src/opnsense/mvc/app/models/OPNsense/Frp/*.php $(MODELS_DIR)/
	@cp src/opnsense/mvc/app/models/OPNsense/Frp/*.xml $(MODELS_DIR)/
	@cp src/opnsense/mvc/app/models/OPNsense/Frp/ACL/*.xml $(MODELS_DIR)/ACL/
	@cp src/opnsense/mvc/app/models/OPNsense/Frp/Menu/*.xml $(MODELS_DIR)/Menu/
	@# Views
	@mkdir -p $(VIEWS_DIR)
	@cp src/opnsense/mvc/app/views/OPNsense/Frp/*.volt $(VIEWS_DIR)/
	@# Scripts
	@mkdir -p $(SCRIPTS_DIR)
	@cp src/opnsense/scripts/OPNsense/Frp/*.sh $(SCRIPTS_DIR)/
	@chmod +x $(SCRIPTS_DIR)/*.sh
	@# Templates
	@mkdir -p $(TEMPLATES_DIR)
	@cp src/opnsense/service/templates/OPNsense/Frp/* $(TEMPLATES_DIR)/
	@# Actions
	@mkdir -p $(ACTIONS_DIR)
	@cp src/opnsense/service/conf/actions.d/*.conf $(ACTIONS_DIR)/
	@# Plugin hooks
	@mkdir -p $(HOOKS_DIR)
	@cp src/etc/inc/plugins.inc.d/frp.inc $(HOOKS_DIR)/
	@# rc.d scripts
	@mkdir -p $(RCD_DIR)
	@cp src/usr/local/etc/rc.d/frp $(RCD_DIR)/frp
	@chmod +x $(RCD_DIR)/frp
	@# Config and log directories
	@mkdir -p /usr/local/etc/frp
	@mkdir -p /var/log/frp
	@echo "==> Plugin files installed"

install-frp:
	@echo "==> Downloading FRP v$(FRP_VERSION)..."
	@mkdir -p /tmp/frp-install
	@fetch -o /tmp/frp-install/frp.tar.gz $(FRP_URL)
	@tar -xzf /tmp/frp-install/frp.tar.gz -C /tmp/frp-install
	@install -m 755 /tmp/frp-install/frp_$(FRP_VERSION)_$(FRP_ARCH)/frpc $(PLUGIN_PREFIX)/bin/frpc
	@install -m 755 /tmp/frp-install/frp_$(FRP_VERSION)_$(FRP_ARCH)/frps $(PLUGIN_PREFIX)/bin/frps
	@rm -rf /tmp/frp-install
	@echo "==> FRP binaries installed"

activate:
	@echo "==> Activating plugin..."
	@# Validate PHP syntax
	@php -l $(HOOKS_DIR)/frp.inc 2>&1 || true
	@# Clear ALL OPNsense caches
	@rm -f /tmp/opnsense_menu_cache.xml 2>/dev/null || true
	@rm -f /tmp/opnsense_acl_cache.json 2>/dev/null || true
	@rm -f /var/lib/php/tmp/opnsense_menu_cache.xml 2>/dev/null || true
	@# Restart configd to pick up new actions
	@service configd restart 2>/dev/null || true
	@# Restart web GUI to flush PHP opcache and pick up menu/controllers
	@configctl webgui restart 2>/dev/null || service php_fpm restart 2>/dev/null || true
	@# Generate templates
	@pluginctl -c 2>/dev/null || true
	@echo "==> Plugin activated. Hard-refresh your browser (Ctrl+Shift+R)."

uninstall:
	@echo "==> Uninstalling os-frp plugin..."
	@# Stop services
	@service frp stop 2>/dev/null || true
	@# Remove plugin files
	@rm -rf $(CONTROLLERS_DIR)
	@rm -rf $(MODELS_DIR)
	@rm -rf $(VIEWS_DIR)
	@rm -rf $(SCRIPTS_DIR)
	@rm -rf $(TEMPLATES_DIR)
	@rm -f $(ACTIONS_DIR)/actions_frp.conf
	@rm -f $(ACTIONS_DIR)/actions_frpss.conf
	@rm -f $(HOOKS_DIR)/frp.inc
	@rm -f $(RCD_DIR)/frp
	@rm -f $(RCD_DIR)/frp_ssserver
	@# Remove config and runtime files
	@rm -rf /usr/local/etc/frp
	@rm -f /etc/rc.conf.d/frp
	@rm -f /etc/rc.conf.d/frp_ssserver
	@rm -f /var/run/frp.pid
	@rm -f /var/run/frp_ssserver.pid
	@rm -rf /var/log/frp
	@# Clear caches
	@rm -f /tmp/opnsense_menu_cache.xml 2>/dev/null || true
	@rm -f /tmp/opnsense_acl_cache.json 2>/dev/null || true
	@rm -f /var/lib/php/tmp/opnsense_menu_cache.xml 2>/dev/null || true
	@service configd restart 2>/dev/null || true
	@configctl webgui restart 2>/dev/null || service php_fpm restart 2>/dev/null || true
	@echo "==> Uninstall complete"

reinstall: uninstall install
	@echo "==> Reinstall complete"

clean:
	@rm -rf /tmp/frp-install
