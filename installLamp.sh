#!/bin/bash
# installLamp-fpm.sh — LAMP (Apache event MPM + PHP-FPM) for Arch Linux
# Installs Apache, MariaDB, PHP-FPM, phpMyAdmin, configures sane security defaults.

set -euo pipefail

say(){ echo -e "$*"; }

say "🔧 Starting LAMP (Apache event + PHP-FPM) installation..."

# --- Packages ----------------------------------------------------------------
say "===> Updating system and installing packages..."
sudo pacman -Syu --noconfirm
sudo pacman -S --noconfirm apache mariadb mariadb-clients \
  php php-fpm php-gd php-intl php-sqlite php-pgsql phpmyadmin

HTTPD_CONF="/etc/httpd/conf/httpd.conf"
PHPMYADMIN_CONF="/etc/httpd/conf/extra/phpmyadmin.conf"
PHPINI="/etc/php/php.ini"
VHOSTS_DIR="/etc/httpd/conf/extra/vhosts.d"
FPM_POOL="/etc/php/php-fpm.d/www.conf"

# --- Apache: event MPM + proxy_fcgi -----------------------------------------
say "===> Configuring Apache for event MPM + proxy_fcgi..."

# Enable event MPM, disable prefork if present
if grep -q '^LoadModule mpm_prefork_module' "$HTTPD_CONF"; then
  sudo sed -i 's/^LoadModule mpm_prefork_module/#LoadModule mpm_prefork_module/' "$HTTPD_CONF"
fi
if grep -q '^#LoadModule mpm_event_module' "$HTTPD_CONF"; then
  sudo sed -i 's/^#LoadModule mpm_event_module/LoadModule mpm_event_module/' "$HTTPD_CONF"
fi
grep -q '^LoadModule mpm_event_module' "$HTTPD_CONF" || \
  echo 'LoadModule mpm_event_module modules/mod_mpm_event.so' | sudo tee -a "$HTTPD_CONF" >/dev/null

# Disable mod_php if present
if grep -q '^LoadModule php_module' "$HTTPD_CONF"; then
  sudo sed -i 's/^LoadModule php_module/#LoadModule php_module/' "$HTTPD_CONF"
fi

# Ensure required modules for FPM
ensure_mod(){
  local name="$1" so="$2"
  if ! grep -q "^LoadModule ${name}_module" "$HTTPD_CONF"; then
    echo "LoadModule ${name}_module modules/${so}" | sudo tee -a "$HTTPD_CONF" >/dev/null
  fi
}
ensure_mod proxy mod_proxy.so
ensure_mod proxy_fcgi mod_proxy_fcgi.so
ensure_mod setenvif mod_setenvif.so
ensure_mod dir mod_dir.so
ensure_mod mime mod_mime.so
# Rewrite needed by many apps (ProcessWire, Laravel, etc.)
if grep -q '^#LoadModule rewrite_module' "$HTTPD_CONF"; then
  sudo sed -i 's/^#LoadModule rewrite_module/LoadModule rewrite_module/' "$HTTPD_CONF"
fi
grep -q '^LoadModule rewrite_module' "$HTTPD_CONF" || \
  echo 'LoadModule rewrite_module modules/mod_rewrite.so' | sudo tee -a "$HTTPD_CONF" >/dev/null

# Hardening & defaults
say "===> Apache hardening & defaults..."
sudo sed -i 's/^#\?ServerTokens .*/ServerTokens Prod/' "$HTTPD_CONF" || true
sudo sed -i 's/^#\?ServerSignature .*/ServerSignature Off/' "$HTTPD_CONF" || echo "ServerSignature Off" | sudo tee -a "$HTTPD_CONF" >/dev/null
sudo sed -i 's/^DirectoryIndex .*/DirectoryIndex index.php index.html/' "$HTTPD_CONF"
grep -q "^ServerName" "$HTTPD_CONF" || echo "ServerName localhost" | sudo tee -a "$HTTPD_CONF" >/dev/null

# Include vhosts.d
grep -q "IncludeOptional conf/extra/vhosts.d/*.conf" "$HTTPD_CONF" || \
  echo "IncludeOptional conf/extra/vhosts.d/*.conf" | sudo tee -a "$HTTPD_CONF" >/dev/null

# Global PHP-FPM handler (FilesMatch)
FPM_HANDLER="/etc/httpd/conf/extra/php-fpm.conf"
sudo tee "$FPM_HANDLER" >/dev/null <<'EOF'
# PHP-FPM via Unix socket
<IfModule proxy_fcgi_module>
    # Send all .php to PHP-FPM
    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php-fpm/php-fpm.sock|fcgi://localhost"
    </FilesMatch>
    # Security: never serve raw PHP sources
    AddType application/x-httpd-php .php
</IfModule>
EOF
grep -q "Include conf/extra/php-fpm.conf" "$HTTPD_CONF" || \
  echo "Include conf/extra/php-fpm.conf" | sudo tee -a "$HTTPD_CONF" >/dev/null

# vhosts directory and a sane default vhost
sudo mkdir -p "$VHOSTS_DIR"
if [ ! -f "$VHOSTS_DIR/000-default.conf" ]; then
  sudo tee "$VHOSTS_DIR/000-default.conf" >/dev/null <<'EOF'
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot "/srv/http"
    <Directory "/srv/http">
        Require all granted
        AllowOverride All
        Options FollowSymLinks
    </Directory>
    ErrorLog "/var/log/httpd/default_error.log"
    CustomLog "/var/log/httpd/default_access.log" combined
</VirtualHost>
EOF
fi

# --- PHP-FPM: pool settings --------------------------------------------------
say "===> Configuring PHP-FPM pool..."
# Ensure socket and permissions suitable for Apache http user
sudo sed -i 's#^;*listen = .*#listen = /run/php-fpm/php-fpm.sock#' "$FPM_POOL"
sudo sed -i 's/^;*user = .*/user = http/' "$FPM_POOL"
sudo sed -i 's/^;*group = .*/group = http/' "$FPM_POOL"
sudo sed -i 's/^;*listen.owner = .*/listen.owner = http/' "$FPM_POOL"
sudo sed -i 's/^;*listen.group = .*/listen.group = http/' "$FPM_POOL"
sudo sed -i 's/^;*listen.mode = .*/listen.mode = 0660/' "$FPM_POOL"

# --- PHP: extensions & php.ini ----------------------------------------------
say "===> Configuring PHP extensions and php.ini..."
php_enable(){
  local ext="$1"
  if grep -Eq "^;?extension\s*=\s*${ext}" "$PHPINI"; then
    sudo sed -i "s/^;*extension\s*=\s*${ext}/extension=${ext}/" "$PHPINI"
  else
    echo "extension=${ext}" | sudo tee -a "$PHPINI" >/dev/null
  fi
}
# Common + ProcessWire/Laravel needs
php_enable mysqli
php_enable pdo_mysql
php_enable sqlite3
php_enable pdo_sqlite
php_enable gd
php_enable intl
php_enable exif
php_enable mbstring
php_enable iconv

# Opcache
grep -q "^zend_extension=opcache" "$PHPINI" || echo "zend_extension=opcache" | sudo tee -a "$PHPINI" >/dev/null

# php.ini tuning
sudo sed -i 's/^;*expose_php\s*=.*/expose_php = Off/' "$PHPINI"
sudo sed -i 's/^;*memory_limit\s*=.*/memory_limit = 256M/' "$PHPINI"
sudo sed -i 's/^;*upload_max_filesize\s*=.*/upload_max_filesize = 64M/' "$PHPINI"
sudo sed -i 's/^;*post_max_size\s*=.*/post_max_size = 64M/' "$PHPINI"
sudo sed -i 's/^;*max_execution_time\s*=.*/max_execution_time = 60/' "$PHPINI"

# Timezone
if grep -q '^;*date.timezone' "$PHPINI"; then
  sudo sed -i 's#^;*date.timezone\s*=.*#date.timezone = Europe/Athens#' "$PHPINI"
else
  echo "date.timezone = Europe/Athens" | sudo tee -a "$PHPINI" >/dev/null
fi

# Short open tags = On (όπως ζήτησες)
if grep -q '^;*short_open_tag' "$PHPINI"; then
  sudo sed -i 's/^;*short_open_tag\s*=.*/short_open_tag = On/' "$PHPINI"
else
  echo "short_open_tag = On" | sudo tee -a "$PHPINI" >/dev/null
fi

# Opcache recommended settings
OPCACHE_BLOCK=$(cat <<'OPC'
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=128
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.validate_timestamps=1
opcache.revalidate_freq=2
OPC
)
grep -q "opcache.enable_cli" "$PHPINI" || echo "$OPCACHE_BLOCK" | sudo tee -a "$PHPINI" >/dev/null

# --- phpMyAdmin --------------------------------------------------------------
say "===> Configuring phpMyAdmin..."
PHPMYADMIN_CFG="/etc/webapps/phpmyadmin/config.inc.php"
if [ ! -f "$PHPMYADMIN_CFG" ]; then
  sudo cp /etc/webapps/phpmyadmin/config.sample.inc.php "$PHPMYADMIN_CFG"
fi
BLOWFISH_SECRET=$(openssl rand -base64 32)
sudo sed -i "s|\(\$cfg\['blowfish_secret'\]\s*=\s*\).*;|\1'$BLOWFISH_SECRET';|" "$PHPMYADMIN_CFG"

# 1) Create Static TempDir
sudo mkdir -p /var/lib/phpmyadmin/tmp
sudo chown -R http:http /var/lib/phpmyadmin
sudo chmod 750 /var/lib/phpmyadmin
sudo chmod 770 /var/lib/phpmyadmin/tmp

# 2) Set $cfg['TempDir']
sudo sed -i "s#^\(\$cfg\['TempDir'\]\s*=\s*\).*$#\1'/var/lib/phpmyadmin/tmp';#" /etc/webapps/phpmyadmin/config.inc.php \
  || echo "\$cfg['TempDir'] = '/var/lib/phpmyadmin/tmp';" | sudo tee -a /etc/webapps/phpmyadmin/config.inc.php

sudo tee "$PHPMYADMIN_CONF" >/dev/null <<'EOF'
Alias /phpmyadmin "/usr/share/webapps/phpMyAdmin"
<Directory "/usr/share/webapps/phpMyAdmin">
    DirectoryIndex index.php
    AllowOverride All
    Options FollowSymLinks
    Require all granted
</Directory>
EOF

# --- DocumentRoot & sample ---------------------------------------------------
say "===> Setting up /srv/http..."
sudo mkdir -p /srv/http
echo "<?php phpinfo(); ?>" | sudo tee /srv/http/info.php >/dev/null
sudo chown -R http:http /srv/http
sudo chmod -R 755 /srv/http

# --- MariaDB -----------------------------------------------------------------
say "===> Initializing MariaDB (if needed)..."
if [ ! -d /var/lib/mysql/mysql ]; then
  sudo mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
fi

say "===> Setting default utf8mb4 charset..."
sudo mkdir -p /etc/my.cnf.d
sudo tee /etc/my.cnf.d/server.cnf >/dev/null <<'EOF'
[mysqld]
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
EOF

say "===> Enabling and starting MariaDB..."
sudo systemctl enable --now mariadb

say "===> Running mariadb-secure-installation (interactive)..."
sudo mariadb-secure-installation || true

# --- Enable services ---------------------------------------------------------
say "===> Verifying Apache config..."
sudo apachectl -t

say "===> Enabling and starting PHP-FPM & Apache..."
sudo systemctl enable --now php-fpm
sudo systemctl enable --now httpd

# --- Health check ------------------------------------------------------------
say "===> Checking service status..."
for svc in php-fpm httpd mariadb; do
  if ! systemctl is-active --quiet "$svc"; then
    say "❌ Service $svc failed to start!"
    journalctl -xeu "$svc" | tail -n 120
    exit 1
  else
    say "✅ $svc is running."
  fi
done

say ""
say "✅ Installation completed successfully (event MPM + PHP-FPM)."
say "👉 Test URLs:"
say "   http://localhost/info.php"
say "   http://localhost/phpmyadmin"
say ""
read -p "🔁 Do you want to reboot now? [y/N]: " confirm
if [[ "${confirm:-N}" =~ ^[Yy]$ ]]; then
  say "🔁 Rebooting..."
  sudo reboot
else
  say "⏹ You can reboot later with: sudo reboot"
fi
