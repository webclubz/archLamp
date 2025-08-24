#!/bin/bash
# sites-manager.sh — Manage Apache virtual hosts on Arch Linux
# Provides commands to add/remove/list sites, fix permissions,
# start/stop services, and scaffold Laravel/WordPress projects.

set -euo pipefail

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
ARCH_USER=${SUDO_USER:-$USER}
SITES_DIR="/home/$ARCH_USER/Sites"
VHOSTS_DIR="/etc/httpd/conf/extra/vhosts.d"
HOSTS_FILE="/etc/hosts"
HTTPD_CONF="/etc/httpd/conf/httpd.conf"
WEBGROUP="${WEBGROUP:-webdev}"   # <-- κοινό group για όλα

say() { echo -e "$*"; }

# ---------------------------------------------------------------------------
# Check if LAMP stack is properly installed
# ---------------------------------------------------------------------------
function check_lamp_installation() {
    local missing_components=()
    
    # Check if Apache config exists
    if [ ! -f "$HTTPD_CONF" ]; then
        missing_components+=("Apache configuration")
    fi
    
    # Check if required directories exist
    if [ ! -d "/etc/httpd" ]; then
        missing_components+=("Apache installation")
    fi
    
    # Check if Apache service is available
    if ! systemctl list-unit-files httpd.service >/dev/null 2>&1; then
        missing_components+=("Apache service")
    fi
    
    # Check if PHP-FPM is installed
    if ! systemctl list-unit-files php-fpm.service >/dev/null 2>&1; then
        missing_components+=("PHP-FPM service")
    fi
    
    if [ ${#missing_components[@]} -gt 0 ]; then
        say "❌ LAMP stack not properly installed. Missing components:"
        for component in "${missing_components[@]}"; do
            say "   - $component"
        done
        say ""
        say "🔧 Please run installLamp.sh first to set up the LAMP stack:"
        say "   ./installLamp.sh"
        say ""
        exit 1
    fi
}

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
# Ensure ~/Sites exists and Apache can traverse into it (ασφαλέστερο)
# ---------------------------------------------------------------------------
function ensure_sites_dir() {
    if [ ! -d "$SITES_DIR" ]; then
        say "📁 Creating $SITES_DIR..."
        sudo install -d -o "$ARCH_USER" -g "$WEBGROUP" -m 2775 "$SITES_DIR"
    fi
    # Δώσε traverse στο group (webdev) στο $HOME για να μπαίνει ο http
    if command -v setfacl >/dev/null 2>&1; then
        sudo setfacl -m g:"$WEBGROUP":x "/home/$ARCH_USER"
        sudo setfacl -m g:"$WEBGROUP":rwx "$SITES_DIR"
        sudo setfacl -d -m g:"$WEBGROUP":rwx "$SITES_DIR"
    else
        sudo chmod o+x "/home/$ARCH_USER"   # fallback (λιγότερο ασφαλές)
        sudo chmod 2775 "$SITES_DIR"
    fi
}

# ---------------------------------------------------------------------------
# Helper: ενιαία ρύθμιση permissions/project
# ---------------------------------------------------------------------------
_set_project_perms() {
  local path="${1:?usage: _set_project_perms /path}"
  local group_in="${2:-$WEBGROUP}"

  sudo chown -R "$ARCH_USER:$group_in" "$path"
  sudo find "$path" -type d -exec chmod 2775 {} \;
  sudo find "$path" -type f -exec chmod 664 {} \;

  if command -v setfacl >/dev/null; then
    sudo setfacl -R -m g:"$group_in":rwx "$path"
    sudo setfacl -dR -m g:"$group_in":rwx "$path"
  fi
}

# ---------------------------------------------------------------------------
# Setup function to create Sites directory with proper permissions
# ---------------------------------------------------------------------------
setup() {
  local ARCHUSER="${1:-${ARCH_USER:-$USER}}"
  local SITES_DIR_IN="${2:-/home/$ARCHUSER/Sites}"
  local WEBGROUP_IN="${3:-$WEBGROUP}"
  local PHPFPM_POOL="${4:-/etc/php/php-fpm.d/www.conf}"

  echo "[i] user=${ARCHUSER} sites=${SITES_DIR_IN} group=${WEBGROUP_IN}"

  # 1) Group συνεργασίας
  if ! getent group "$WEBGROUP_IN" >/dev/null; then
    sudo groupadd "$WEBGROUP_IN"
  fi
  sudo gpasswd -a "$ARCHUSER" "$WEBGROUP_IN" >/dev/null
  if id -u http >/dev/null 2>&1; then
    sudo gpasswd -a http "$WEBGROUP_IN" >/dev/null
  fi

  # 2) Φάκελος Sites (δημιουργία αν λείπει) + perms
  sudo install -d -o "$ARCHUSER" -g "$WEBGROUP_IN" -m 2775 "$SITES_DIR_IN"
  sudo chgrp -R "$WEBGROUP_IN" "$SITES_DIR_IN"
  sudo find "$SITES_DIR_IN" -type d -exec chmod 2775 {} \;
  sudo find "$SITES_DIR_IN" -type f -exec chmod 664 {} \;

  # 3) ACLs στο Sites
  if command -v setfacl >/dev/null; then
    sudo setfacl -R -m g:"$WEBGROUP_IN":rwx "$SITES_DIR_IN"
    sudo setfacl -dR -m g:"$WEBGROUP_IN":rwx "$SITES_DIR_IN"
  else
    echo "[!] setfacl δεν βρέθηκε. Προτείνεται: sudo pacman -S acl"
  fi

  # 4) Δώσε traverse στο group στο $HOME
  if command -v setfacl >/dev/null; then
    sudo setfacl -m g:"$WEBGROUP_IN":x "/home/$ARCHUSER"
  else
    sudo chmod o+x "/home/$ARCHUSER"
  fi

  # 5) Git: shared perms
  if command -v git >/dev/null; then
    git config --global core.sharedRepository group
  fi

  # 6) PHP-FPM να τρέχει ως http:WEBGROUP
  if [ -f "$PHPFPM_POOL" ]; then
    sudo sed -i -E \
      -e 's|^;?\s*user\s*=.*$|user = http|g' \
      -e "s|^;?\s*group\s*=.*$|group = ${WEBGROUP_IN}|g" \
      "$PHPFPM_POOL"
  else
    echo "[!] Δεν βρέθηκε pool: $PHPFPM_POOL"
  fi

  # 7) Systemd UMask=0002 για php-fpm (αρχεία 664/φάκελοι 775)
  sudo install -d -m 0755 /etc/systemd/system/php-fpm.service.d
  printf "[Service]\nUMask=0002\n" | sudo tee /etc/systemd/system/php-fpm.service.d/override.conf >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl restart php-fpm 2>/dev/null || true

  # 8) Restart webserver αν υπάρχει
  if systemctl is-enabled --quiet httpd 2>/dev/null; then sudo systemctl restart httpd; fi
  if systemctl is-enabled --quiet nginx 2>/dev/null; then sudo systemctl restart nginx; fi

  echo "[✔] Setup ολοκληρώθηκε."
  echo "    > Κάνε logout/login για να «φορεθούν» τα νέα groups στο shell σου."
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

    # Permissions (owner: user, group: WEBGROUP, setgid + ACLs)
    say "🔐 Setting permissions..."
    _set_project_perms "$path" "$WEBGROUP"
    
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
# Fix CMS permissions (ενιαία με WEBGROUP)
# ---------------------------------------------------------------------------
function fix_cms_perms() {
    local name="${1:-}"
    [ -z "$name" ] && say "❌ Please provide a project name." && exit 1
    local path="$SITES_DIR/$name"

    if [ ! -d "$path" ]; then
        say "❌ Project $name does not exist in $SITES_DIR"
        exit 1
    fi

    say "🔧 Fixing CMS permissions for $name (group: $WEBGROUP)"
    _set_project_perms "$path" "$WEBGROUP"

    # Extra για συνηθισμένους φακέλους CMS
    sudo chmod -R 775 "$path/storage" "$path/bootstrap/cache" "$path/wp-content" 2>/dev/null || true

    # βεβαιώσου ότι ο http είναι μέλος του group (μία φορά αρκεί)
    if ! id -nG http 2>/dev/null | grep -q "\b$WEBGROUP\b"; then
        say "👤 Adding http to $WEBGROUP group..."
        sudo gpasswd -a http "$WEBGROUP" >/dev/null
        say "ℹ️ Restarting php-fpm to pick up groups..."
        sudo systemctl restart php-fpm || true
    fi

    say "✅ Permissions fixed for $name!"
}

# ---------------------------------------------------------------------------
# Service management (Arch: mariadb)
# ---------------------------------------------------------------------------
function start_services() {
    say "🚀 Starting services..."
    sudo systemctl start httpd
    sudo systemctl start mariadb || true
    say "✅ Services started."
}

function stop_services() {
    say "🛑 Stopping services..."
    sudo systemctl stop httpd || true
    sudo systemctl stop mariadb || true
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

    # Permissions (ενιαία)
    _set_project_perms "$path" "$WEBGROUP"
    # Laravel ειδικά
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

    # Permissions (ενιαία)
    _set_project_perms "$path" "$WEBGROUP"

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
# Health check για permissions σε ~/Sites
# ---------------------------------------------------------------------------
function check_sites() {
    say "🔍 Checking permissions and groups in $SITES_DIR (expected: group=$WEBGROUP, files=664, dirs=2775)..."
    local issues=0
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        echo "❌ $entry"
        issues=$((issues+1))
    done < <(
        find "$SITES_DIR" \
            \( -type f ! -perm 664 -o -type d ! -perm 2775 \) -o \
            ! -group "$WEBGROUP" \
            -exec ls -ld {} \;
    )
    if [ "$issues" -eq 0 ]; then
        say "✅ All good — no permission/group issues found."
    else
        say "⚠️  Found $issues issues."
        say "👉 You can fix them with: sites-manager repair"
    fi
}

# ---------------------------------------------------------------------------
# Auto repair για permissions σε ~/Sites
# ---------------------------------------------------------------------------
function repair_sites() {
    say "🔧 Fixing permissions and groups in $SITES_DIR..."
    sudo chgrp -R "$WEBGROUP" "$SITES_DIR"
    sudo find "$SITES_DIR" -type d -exec chmod 2775 {} \;
    sudo find "$SITES_DIR" -type f -exec chmod 664 {} \;

    if command -v setfacl >/dev/null; then
        sudo setfacl -R -m g:"$WEBGROUP":rwx "$SITES_DIR"
        sudo setfacl -dR -m g:"$WEBGROUP":rwx "$SITES_DIR"
    fi
    say "✅ Permissions repaired."
}


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
# Skip LAMP check for setup command since it should work before LAMP installation
if [ "${1:-}" != "setup" ]; then
    check_lamp_installation
    ensure_include_in_httpd_conf
    ensure_sites_dir
fi

case "${1:-}" in
  setup)     setup ;;
  add)       add_site "${2:-}" ;;
  remove)    remove_site "${2:-}" ;;
  list)      list_sites ;;
  scan)      scan_sites ;;
  fix-cms)   fix_cms_perms "${2:-}" ;;
  start)     start_services ;;
  stop)      stop_services ;;
  check)     check_sites ;;
  repair)    repair_sites ;;
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
  sites-manager setup             → Initial setup: create ~/Sites with proper permissions
  sites-manager add <site>        → Add new site (auto dirs & vhost)
  sites-manager remove <site>     → Remove site
  sites-manager list              → List active sites
  sites-manager scan              → Auto-add all from ~/Sites
  sites-manager fix-cms <site>    → Fix CMS permissions
  sites-manager start             → Start Apache & MariaDB
  sites-manager stop              → Stop Apache & MariaDB
  sites-manager check              → CHealth check για permissions σε ~/Sites
  sites-manager repair             → Auto repair για permissions σε ~/Sites
  sites-manager init laravel <s>  → Scaffold Laravel project + vhost
  sites-manager init wp <s>       → Scaffold WordPress project + vhost

📝 Note: Run 'setup' first, then install LAMP stack with ./installLamp.sh
USAGE
    ;;
esac
