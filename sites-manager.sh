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
    
    # Handle domain correctly - don't add .test if it already ends with .test
    local domain
    local config_name
    
    # Use explicit string comparison to avoid pattern matching issues
    if [ "${name##*.}" = "test" ]; then
        domain="$name"
        config_name="${name%.test}"  # Remove .test suffix for config file naming
    else
        domain="$name.test"
        config_name="$name"
    fi
    
    local vhost_file="$VHOSTS_DIR/$config_name.conf"

    say "🗑️ Removing virtual host for $domain..."
    say "Debug: config_name='$config_name', domain='$domain', vhost_file='$vhost_file'"
    
    # Remove vhost file
    if [ -f "$vhost_file" ]; then
        sudo rm -f "$vhost_file"
        say "✅ Removed vhost file: $vhost_file"
    else
        say "ℹ️ Vhost file not found: $vhost_file"
    fi
    
    # Remove from hosts file
    sudo sed -i "/[[:space:]]$domain$/d" "$HOSTS_FILE"
    sudo sed -i "/^127\.0\.0\.1[[:space:]]*$domain$/d" "$HOSTS_FILE"

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
    local mode="${1:-list}"  # list | apply
    say "🔍 Scanning directories in $SITES_DIR (mode: $mode)"
    shopt -s nullglob
    local planned=0 applied=0 skipped=0 existing=0
    for dir in "$SITES_DIR"/*; do
        [ -d "$dir" ] || continue
        local basename name docroot vhost_file reason
        basename=$(basename "$dir")
        # Skip dot-directories by default
        [[ "$basename" =~ ^\.|^_ ]] && { say "⏭️  Skip $basename (hidden/prefixed)"; skipped=$((skipped+1)); continue; }
        # Marker to opt-out
        [ -f "$dir/.nosite" ] && { say "⏭️  Skip $basename (.nosite present)"; skipped=$((skipped+1)); continue; }

        name="$basename"
        vhost_file="$VHOSTS_DIR/$name.conf"

        # Determine docroot
        if [ -d "$dir/public" ]; then
            docroot="$dir/public"
        else
            docroot="$dir"
        fi

        if [ -f "$vhost_file" ]; then
            say "👍 Exists: $name → $(basename "$vhost_file")"
            existing=$((existing+1))
            continue
        fi

        # Require an index file by default to avoid dead vhosts
        if [ ! -f "$docroot/index.php" ] && [ ! -f "$docroot/index.html" ] && [ ! -f "$docroot/index.htm" ]; then
            say "⏭️  Skip $name (no index in $docroot)"
            skipped=$((skipped+1))
            continue
        fi

        if [ "$mode" = "apply" ]; then
            say "➕ Adding site: $name (docroot: $docroot)"
            add_site "$name"
            applied=$((applied+1))
        else
            say "📝 Would add: $name (docroot: $docroot)"
            planned=$((planned+1))
        fi
    done
    shopt -u nullglob
    say "📊 Summary → existing=$existing, planned=$planned, applied=$applied, skipped=$skipped"
    [ "$mode" = "list" ] && say "👉 Apply changes: sites-manager scan apply"
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
# Audit vhosts for missing DocumentRoot under ~/Sites
# ---------------------------------------------------------------------------
function audit_vhosts() {
    say "🔍 Auditing vhosts in $VHOSTS_DIR for missing DocumentRoot..."
    local total=0 missing=0
    shopt -s nullglob
    for f in "$VHOSTS_DIR"/*.conf; do
        total=$((total+1))
        local domain docroot
        domain=$(awk 'tolower($1)=="servername"{print $2; exit}' "$f" | sed 's/\"//g')
        docroot=$(awk 'tolower($1)=="documentroot"{print $2; exit}' "$f" | sed 's/\"//g')
        [ -z "$domain" ] && domain="(no ServerName)"
        [ -z "$docroot" ] && docroot="(no DocumentRoot)"
        if [ -n "$docroot" ] && [ -d "$docroot" ]; then
            echo "✅ $(basename "$f"): $domain → $docroot"
        else
            echo "❌ $(basename "$f"): $domain → $docroot (missing)"
            missing=$((missing+1))
        fi
    done
    shopt -u nullglob
    say "📊 Summary: total=$total, missing=$missing"
    if [ "$missing" -gt 0 ]; then
        say "👉 To remove missing ones and clean /etc/hosts: sites-manager prune"
    fi
}

# ---------------------------------------------------------------------------
# Prune vhosts with missing DocumentRoot and clean /etc/hosts
# ---------------------------------------------------------------------------
function prune_vhosts() {
    say "🧹 Pruning vhosts with missing DocumentRoot..."
    local removed=0
    shopt -s nullglob
    for f in "$VHOSTS_DIR"/*.conf; do
        local domain docroot name
        name=$(basename "$f")
        domain=$(awk 'tolower($1)=="servername"{print $2; exit}' "$f" | sed 's/\"//g')
        docroot=$(awk 'tolower($1)=="documentroot"{print $2; exit}' "$f" | sed 's/\"//g')
        if [ -z "$docroot" ] || [ ! -d "$docroot" ]; then
            say "🗑️ Removing $(basename "$f") (domain=$domain, docroot=$docroot)"
            sudo rm -f "$f"
            if [ -n "$domain" ]; then
                # Remove host entries we created (one domain per line)
                sudo sed -i "/[[:space:]]$domain$/d" "$HOSTS_FILE" || true
                sudo sed -i "/^127\\.0\\.0\\.1[[:space:]]*$domain$/d" "$HOSTS_FILE" || true
            fi
            removed=$((removed+1))
        fi
    done
    shopt -u nullglob
    if [ "$removed" -gt 0 ]; then
        say "🧪 Checking Apache config..."
        if sudo apachectl -t; then
            say "🔄 Reloading Apache..."
            sudo systemctl reload httpd || sudo systemctl restart httpd
        else
            say "⚠️ Apache config check failed. Investigate before restarting."
        fi
        say "✅ Pruned $removed vhost(s)."
    else
        say "✅ Nothing to prune."
    fi
}

# ---------------------------------------------------------------------------
# Allow httpd to access /home (systemd override)
# ---------------------------------------------------------------------------
function allow_home_access() {
    say "🛡️ Creating systemd override for httpd to allow /home access..."
    local dir="/etc/systemd/system/httpd.service.d"
    sudo install -d -m 0755 "$dir"
    # Use read-only to keep some hardening while allowing static reads from /home
    sudo tee "$dir/override.conf" >/dev/null <<'EOF'
[Service]
ProtectHome=read-only
EOF
    say "🔄 Reloading systemd and restarting httpd..."
    sudo systemctl daemon-reload
    sudo systemctl restart httpd
    say "✅ Applied. If issues persist, try ProtectHome=false instead."
}

# ---------------------------------------------------------------------------
# Debug a site returning 403 (permissions, index, vhost, Apache)
# ---------------------------------------------------------------------------
function debug_site() {
    local input="${1:-}"
    [ -z "$input" ] && { say "❌ Usage: sites-manager debug <site|domain>"; exit 1; }

    local domain config_name vhost_file docroot docroot_src docroot_guess1 docroot_guess2
    if [ "${input##*.}" = "test" ]; then
        domain="$input"
        config_name="${input%.test}"
    else
        domain="$input.test"
        config_name="$input"
    fi
    vhost_file="$VHOSTS_DIR/$config_name.conf"

    say "🔎 Debugging: domain=$domain (config=$config_name)"
    say "   • VHost file: $vhost_file"

    # 1) Apache basic checks
    local include_line="IncludeOptional conf/extra/vhosts.d/*.conf"
    if grep -qF "$include_line" "$HTTPD_CONF"; then
        say "✅ httpd.conf includes vhosts.d"
    else
        say "❌ httpd.conf missing IncludeOptional for vhosts.d"
        say "   Fix: add 'IncludeOptional conf/extra/vhosts.d/*.conf' to $HTTPD_CONF"
    fi

    say "🧪 apachectl syntax check..."
    if sudo apachectl -t; then
        say "✅ Apache syntax OK"
    else
        say "❌ Apache syntax error — check above output"
    fi

    # 2) VHost + DocumentRoot detection
    if [ -f "$vhost_file" ]; then
        docroot=$(awk 'tolower($1)=="documentroot"{print $2; exit}' "$vhost_file" | sed 's/\"//g') || true
        [ -n "${docroot:-}" ] && docroot_src="vhost"
    fi

    docroot_guess1="$SITES_DIR/$config_name/public"
    docroot_guess2="$SITES_DIR/$config_name"
    if [ -z "${docroot:-}" ]; then
        if [ -d "$docroot_guess1" ]; then
            docroot="$docroot_guess1"; docroot_src="guess(public)";
        elif [ -d "$docroot_guess2" ]; then
            docroot="$docroot_guess2"; docroot_src="guess(root)";
        else
            docroot="/srv/http"; docroot_src="default";
        fi
    fi
    say "📂 DocumentRoot: $docroot ($docroot_src)"
    if [ ! -d "$docroot" ]; then
        say "❌ DocumentRoot does not exist"
    fi

    # 3) Index file presence
    local has_index="no"
    for idx in index.php index.html index.htm; do
        if [ -f "$docroot/$idx" ]; then has_index="yes"; break; fi
    done
    if [ "$has_index" = "yes" ]; then
        say "✅ Index file found in DocumentRoot"
    else
        say "⚠️  No index file found (index.php/html/htm missing)"
        say "   If you expect directory listing, add 'Options +Indexes' in the <Directory> block."
    fi

    # 4) Directory block sanity (Require/AllowOverride/Options)
    if [ -f "$vhost_file" ]; then
        local dir_block
        dir_block=$(awk -v d="$docroot" 'BEGIN{IGNORECASE=1;want=0}
            $0 ~ "<Directory\s*\"" d "\">" {want=1}
            want{print}
            want && $0 ~ "</Directory>" {exit}' "$vhost_file")
        if [ -n "$dir_block" ]; then
            echo "$dir_block" | grep -qi "Require all granted" && say "✅ Directory has: Require all granted" || say "⚠️  Directory missing: Require all granted"
            echo "$dir_block" | grep -qi "AllowOverride\s\+All" && say "✅ Directory has: AllowOverride All" || say "ℹ️ Directory AllowOverride not All"
            echo "$dir_block" | grep -qi "Options .*Indexes" && say "ℹ️ Directory allows Indexes" || true
        else
            say "ℹ️ No explicit <Directory \"$docroot\"> block found in vhost"
        fi
    fi

    # 5) Filesystem traversal and permissions for user 'http'
    say "🔐 Filesystem checks as user 'http'..."
    if id -u http >/dev/null 2>&1; then
        if sudo -u http bash -lc "cd \"$docroot\" 2>/dev/null"; then
            say "✅ http can cd into DocumentRoot"
        else
            say "❌ http cannot cd into DocumentRoot (likely permissions on a parent directory)"
        fi
        if sudo -u http bash -lc "[ -r \"$docroot\" ] && echo ok" >/dev/null 2>&1; then
            say "✅ http can read DocumentRoot"
        else
            say "⚠️  http cannot read DocumentRoot"
        fi
    else
        say "⚠️  System user 'http' not found"
    fi

    # 6) Group membership and ACL hints
    if id -u http >/dev/null 2>&1; then
        if id -nG http | grep -q "\b$WEBGROUP\b"; then
            say "✅ http is in group $WEBGROUP"
        else
            say "⚠️  http is NOT in group $WEBGROUP"
            say "   Fix: sudo gpasswd -a http $WEBGROUP && sudo systemctl restart php-fpm"
        fi
    fi

    # 7) Show path permissions breakdown
    say "🧭 Path permissions (namei):"
    if command -v namei >/dev/null 2>&1; then
        namei -om "$docroot" 2>/dev/null || namei -l "$docroot" 2>/dev/null || true
    else
        say "ℹ️ namei not installed"
    fi
    say "📊 DocumentRoot stat:"
    stat -c "%A %a %U:%G %n" "$docroot" 2>/dev/null || true

    # 8) .htaccess deny rules
    if [ -f "$docroot/.htaccess" ]; then
        if grep -Eiq "(^|\s)(Deny from all|Require all denied)" "$docroot/.htaccess"; then
            say "⚠️  .htaccess contains deny rules (Deny from all / Require all denied)"
        else
            say "✅ .htaccess present without global deny"
        fi
    else
        say "ℹ️ No .htaccess in DocumentRoot"
    fi

    # 9) Apache vhosts dump (short)
    say "📜 apachectl -S (vhosts overview):"
    sudo apachectl -S 2>&1 | sed -n '1,80p'

    # 10) Recent httpd errors
    say "🧾 Recent httpd errors (last 80 lines):"
    journalctl -u httpd -n 80 --no-pager 2>/dev/null || true

    say "\n➡️ Likely 403 causes and quick fixes:"
    say "   - Missing index file → add index.php or enable 'Options +Indexes'"
    say "   - No traverse perms on /home or project → sites-manager setup | repair"
    say "   - http not in $WEBGROUP → sudo gpasswd -a http $WEBGROUP; restart php-fpm"
    say "   - Deny rules in .htaccess → remove or override with Require all granted"
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
  scan)      scan_sites "${2:-list}" ;;
  fix-cms)   fix_cms_perms "${2:-}" ;;
  debug)     debug_site "${2:-}" ;;
  audit)     audit_vhosts ;;
  prune)     prune_vhosts ;;
  allow-home) allow_home_access ;;
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
  sites-manager scan [apply]      → List or add vhosts for ~/Sites
  sites-manager fix-cms <site>    → Fix CMS permissions
  sites-manager debug <site|dom>  → Debug 403s: vhost, perms, index, Apache
  sites-manager audit             → List vhosts with missing DocumentRoot
  sites-manager prune             → Remove missing vhosts and clean /etc/hosts
  sites-manager allow-home        → Allow httpd to read from /home (systemd override)
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
