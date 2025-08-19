#!/bin/bash
# sites-manager.sh — Manage Apache virtual hosts on Arch Linux
# Provides commands to add/remove/list sites, fix permissions,
# start/stop services, and scaffold Laravel/WordPress projects.

set -euo pipefail

ARCH_USER=${SUDO_USER:-$USER}
SITES_DIR="/home/$ARCH_USER/Sites"
VHOSTS_DIR="/etc/httpd/conf/extra/vhosts.d"
HOSTS_FILE="/etc/hosts"
HTTPD_CONF="/etc/httpd/conf/httpd.conf"

say() { echo -e "$*"; }

# ---------------------------------------------------------------------------
# Ensure httpd.conf includes vhosts.d and has a ServerName
# ---------------------------------------------------------------------------
function ensure_include_in_httpd_conf() {
    local INCLUDE_DIRECTIVE="IncludeOptional conf/extra/vhosts.d/*.conf"

    if ! grep -qF "$INCLUDE_DIRECTIVE" "$HTTPD_CONF"; then
        say "📄 Adding IncludeOptional to $HTTPD_CONF"
        echo "" | sudo tee -a "$HTTPD_CONF" >/dev/null
        echo "$INCLUDE_DIRECTIVE" | sudo tee -a "$HTTPD_CONF" >/dev/null
    fi

    if ! grep -q "^ServerName" "$HTTPD_CONF"; then
        say "📄 Adding ServerName to $HTTPD_CONF"
        echo "ServerName localhost" | sudo tee -a "$HTTPD_CONF" >/dev/null
    fi
}

# ---------------------------------------------------------------------------
# Ensure ~/Sites exists and Apache can traverse into it
# ---------------------------------------------------------------------------
function ensure_sites_dir() {
    if [ ! -d "$SITES_DIR" ]; then
        say "📁 Creating $SITES_DIR..."
        sudo -u "$ARCH_USER" mkdir -p "$SITES_DIR"
    fi
    sudo chmod o+x "/home/$ARCH_USER"
    sudo chmod o+rx "$SITES_DIR"
}

# ---------------------------------------------------------------------------
# Add a new site and generate Apache vhost
# ---------------------------------------------------------------------------
function add_site() {
    local name="${1:-}"
    [ -z "$name" ] && say "❌ Please provide a site name (e.g. blog)" && exit 1

    local path="$SITES_DIR/$name"
    local domain="$name.test"
    local vhost_file="$VHOSTS_DIR/$name.conf"

    # Create project dir if it doesn't exist
    if [ ! -d "$path" ]; then
        say "📁 Creating project directory: $path"
        sudo -u "$ARCH_USER" mkdir -p "$path/public"
        if [ ! -f "$path/public/index.php" ]; then
            cat <<'PHP' | sudo -u "$ARCH_USER" tee "$path/public/index.php" >/dev/null
<?php phpinfo();
PHP
        fi
    fi

    # Detect DocumentRoot
    local docroot
    if [ -d "$path/public" ]; then
        docroot="$path/public"
        say "📁 Using public/ as DocumentRoot for $domain"
    else
        docroot="$path"
        say "📁 Using root folder $path as DocumentRoot"
    fi

    # Permissions
    say "🔐 Setting permissions..."
    sudo chown -R "$ARCH_USER:http" "$path"
    sudo find "$path" -type d -exec chmod 775 {} \;
    sudo find "$path" -type f -exec chmod 664 {} \;

    # Ensure vhosts dir
    if [ ! -d "$VHOSTS_DIR" ]; then
        say "📁 Creating $VHOSTS_DIR..."
        sudo mkdir -p "$VHOSTS_DIR"
    fi

    # Write Apache vhost
    say "🌐 Creating Apache config for $domain..."
    sudo tee "$vhost_file" >/dev/null <<EOF
<VirtualHost *:80>
    ServerName $domain
    DocumentRoot "$docroot"

    <Directory "$docroot">
        Require all granted
        AllowOverride All
        DirectoryIndex index.php index.html
        Options FollowSymLinks
    </Directory>

    # phpMyAdmin alias (per-vhost)
    Include conf/extra/phpmyadmin.conf

    ErrorLog "/var/log/httpd/${name}_error.log"
    CustomLog "/var/log/httpd/${name}_access.log" combined
</VirtualHost>
EOF

    # /etc/hosts entry
    if ! grep -qE "^[^#]*\s$domain(\s|$)" "$HOSTS_FILE"; then
        say "➕ Adding entry to /etc/hosts"
        echo "127.0.0.1 $domain" | sudo tee -a "$HOSTS_FILE" >/dev/null
    fi

    # Check Apache config
    say "🧪 Checking Apache config..."
    if ! sudo apachectl -t; then
        say "❌ Apache config error. Please fix and retry."
        exit 1
    fi

    # Restart Apache
    say "🔄 Restarting Apache..."
    sudo systemctl restart httpd
    say "✅ Ready: http://$domain"
}

# ---------------------------------------------------------------------------
# Remove a site
# ---------------------------------------------------------------------------
function remove_site() {
    local name="${1:-}"
    [ -z "$name" ] && say "❌ Please provide a site name to remove." && exit 1
    local domain="$name.test"
    local vhost_file="$VHOSTS_DIR/$name.conf"

    say "🗑️ Removing virtual host for $domain..."
    sudo rm -f "$vhost_file"
    sudo sed -i "/[[:space:]]$domain$/d" "$HOSTS_FILE"

    say "🧪 Checking Apache config..."
    sudo apachectl -t

    say "🔄 Restarting Apache..."
    sudo systemctl restart httpd
    say "✅ $domain removed."
}

# ---------------------------------------------------------------------------
# List all active sites
# ---------------------------------------------------------------------------
function list_sites() {
    say "📋 Active virtual hosts:"
    shopt -s nullglob
    for f in "$VHOSTS_DIR"/*.conf; do
        echo "- $(basename "$f" .conf).test"
    done
    shopt -u nullglob
}

# ---------------------------------------------------------------------------
# Scan ~/Sites and add missing vhosts
# ---------------------------------------------------------------------------
function scan_sites() {
    say "🔍 Scanning directories in $SITES_DIR"
    shopt -s nullglob
    for dir in "$SITES_DIR"/*; do
        [ -d "$dir" ] || continue
        local name
        name=$(basename "$dir")
        if [ ! -f "$VHOSTS_DIR/$name.conf" ]; then
            say "➕ Adding site: $name"
            add_site "$name"
        fi
    done
    shopt -u nullglob
}

# ---------------------------------------------------------------------------
# Fix CMS permissions
# ---------------------------------------------------------------------------
function fix_cms_perms() {
    local name="${1:-}"
    [ -z "$name" ] && say "❌ Please provide a project name." && exit 1
    local path="$SITES_DIR/$name"

    if [ ! -d "$path" ]; then
        say "❌ Project $name does not exist in $SITES_DIR"
        exit 1
    fi

    say "🔧 Fixing CMS permissions for $name"
    sudo chown -R "$ARCH_USER:http" "$path"
    sudo find "$path" -type d -exec chmod 775 {} \;
    sudo find "$path" -type f -exec chmod 664 {} \;
    say "✅ Permissions fixed. Apache can now write to files."
}

# ---------------------------------------------------------------------------
# Service management
# ---------------------------------------------------------------------------
function start_services() {
    say "🚀 Starting services..."
    sudo systemctl start httpd
    sudo systemctl start mysqld || true
    say "✅ Services started."
}

function stop_services() {
    say "🛑 Stopping services..."
    sudo systemctl stop httpd || true
    sudo systemctl stop mysqld || true
    say "✅ Services stopped."
}

# ---------------------------------------------------------------------------
# Init Laravel project
# ---------------------------------------------------------------------------
function init_laravel() {
    local name="${1:-}"
    [ -z "$name" ] && say "❌ Usage: sites-manager init laravel <site>" && exit 1

    # Requirements
    if ! command -v composer >/dev/null; then
        say "❌ Composer is required (sudo pacman -S composer)"
        exit 1
    fi
    if ! command -v php >/dev/null; then
        say "❌ PHP is required"
        exit 1
    fi

    local path="$SITES_DIR/$name"
    say "🎯 Setting up Laravel project: $name"

    if [ ! -d "$path" ]; then
        sudo -u "$ARCH_USER" mkdir -p "$path"
    fi

    if [ ! -f "$path/composer.json" ]; then
        say "📦 composer create-project laravel/laravel \"$path\""
        sudo -u "$ARCH_USER" bash -lc "composer create-project laravel/laravel \"$path\""
    else
        say "ℹ️ composer.json already exists — skipping create-project."
    fi

    # Permissions
    sudo chown -R "$ARCH_USER:http" "$path"
    sudo find "$path" -type d -exec chmod 775 {} \;
    sudo find "$path" -type f -exec chmod 664 {} \;
    sudo chmod -R 775 "$path/storage" "$path/bootstrap/cache" 2>/dev/null || true

    add_site "$name"

    say "✅ Laravel ready at http://$name.test (DocumentRoot: $path/public)"
    say "👉 Edit .env for DB and run: php artisan key:generate"
}

# ---------------------------------------------------------------------------
# Init WordPress project
# ---------------------------------------------------------------------------
function init_wp() {
    local name="${1:-}"
    [ -z "$name" ] && say "❌ Usage: sites-manager init wp <site>" && exit 1

    # Requirements
    if ! command -v wp >/dev/null; then
        say "❌ wp-cli is required (install via pacman or manual)"
        exit 1
    fi
    if ! command -v php >/dev/null; then
        say "❌ PHP is required"
        exit 1
    fi

    local path="$SITES_DIR/$name"
    say "🎯 Setting up WordPress project: $name"

    if [ ! -d "$path" ]; then
        sudo -u "$ARCH_USER" mkdir -p "$path"
    fi

    if [ ! -f "$path/wp-settings.php" ]; then
        say "📦 wp core download"
        sudo -u "$ARCH_USER" bash -lc "cd \"$path\" && wp core download --force"
    else
        say "ℹ️ WordPress already downloaded — skipping."
    fi

    # Permissions
    sudo chown -R "$ARCH_USER:http" "$path"
    sudo find "$path" -type d -exec chmod 775 {} \;
    sudo find "$path" -type f -exec chmod 664 {} \;

    # Optional DB config if env vars exist
    local DB_NAME="${WP_DB_NAME:-}"
    local DB_USER="${WP_DB_USER:-}"
    local DB_PASS="${WP_DB_PASS:-}"
    local DB_HOST="${WP_DB_HOST:-localhost}"

    if [ -n "$DB_NAME" ] && [ -n "$DB_USER" ] && [ -n "$DB_PASS" ]; then
        say "🧩 Creating wp-config.php (DB_HOST: $DB_HOST)"
        if [ ! -f "$path/wp-config.php" ]; then
            sudo -u "$ARCH_USER" bash -lc "cd \"$path\" && wp config create --dbname=\"$DB_NAME\" --dbuser=\"$DB_USER\" --dbpass=\"$DB_PASS\" --dbhost=\"$DB_HOST\" --force"
        fi
        say "🗄️ Attempting to create DB..."
        sudo -u "$ARCH_USER" bash -lc "cd \"$path\" && wp db create" || say "ℹ️ Skipping db create (insufficient privileges?)."
        say "ℹ️ You can now run wp core install for final setup."
    else
        say "ℹ️ No WP_DB_* environment variables found — only core download done."
    fi

    add_site "$name"
    say "✅ WordPress ready at http://$name.test"
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
ensure_include_in_httpd_conf
ensure_sites_dir

case "${1:-}" in
  add)       add_site "${2:-}" ;;
  remove)    remove_site "${2:-}" ;;
  list)      list_sites ;;
  scan)      scan_sites ;;
  fix-cms)   fix_cms_perms "${2:-}" ;;
  start)     start_services ;;
  stop)      stop_services ;;
  init)
    case "${2:-}" in
      laravel) init_laravel "${3:-}" ;;
      wp)      init_wp "${3:-}" ;;
      *) 
        say "❌ Usage: sites-manager init laravel <site> | wp <site>"
        exit 1
        ;;
    esac
    ;;
  *)
    cat <<USAGE
🧰 Usage:
  sites-manager add <site>        → Add new site (auto dirs & vhost)
  sites-manager remove <site>     → Remove site
  sites-manager list              → List active sites
  sites-manager scan              → Auto-add all from ~/Sites
  sites-manager fix-cms <site>    → Fix CMS permissions
  sites-manager start             → Start Apache & MySQL
  sites-manager stop              → Stop Apache & MySQL
  sites-manager init laravel <s>  → Scaffold Laravel project + vhost
  sites-manager init wp <s>       → Scaffold WordPress project + vhost
USAGE
    ;;
esac
