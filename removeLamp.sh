#!/bin/bash

echo "💣 AGGRESSIVE LAMP REMOVAL SCRIPT FOR ARCH LINUX"
echo "=================================================="
echo "⚠️  WARNING: This will COMPLETELY DESTROY your LAMP installation!"
echo "⚠️  ALL databases, websites, configs will be PERMANENTLY DELETED!"
echo "⚠️  This action is IRREVERSIBLE!"
echo ""

read -p "🔥 Type 'DESTROY' to continue with complete removal: " confirm
[[ $confirm != "DESTROY" ]] && echo "❌ Aborted. Type exactly 'DESTROY' to proceed." && exit 1

echo "🔥 Starting aggressive LAMP removal..."

# 1. Stop and disable all services immediately
echo "🛑 Stopping and disabling all LAMP services..."
sudo systemctl stop httpd apache2 mysqld mariadb mysql php-fpm 2>/dev/null
sudo systemctl disable httpd apache2 mysqld mariadb mysql php-fpm 2>/dev/null
sudo pkill -f httpd 2>/dev/null
sudo pkill -f mysqld 2>/dev/null
sudo pkill -f php-fpm 2>/dev/null

# 2. Remove ALL related packages aggressively
echo "🧹 Aggressively removing ALL LAMP packages..."
sudo pacman -Rns --noconfirm apache mariadb mariadb-clients mysql php php-apache php-cgi php-cli php-fpm php-gd php-intl php-mysqli php-pgsql php-sqlite php-zip php-curl php-json php-mbstring php-xml php-openssl php-pear php-imagick php-redis php-memcached phpmyadmin phpMyAdmin 2>/dev/null

# 3. Remove any remaining PHP packages
echo "🔥 Removing any remaining PHP packages..."
php_packages=$(pacman -Qs php | grep -E '^local/' | awk '{print $1}' | sed 's/local\///')
if [[ -n "$php_packages" ]]; then
    sudo pacman -Rns --noconfirm $php_packages 2>/dev/null
fi

# 4. Nuclear option: Remove ALL Apache/HTTP related packages
echo "💥 Nuclear removal of HTTP server packages..."
sudo pacman -Rns --noconfirm $(pacman -Qs apache | grep -E '^local/' | awk '{print $1}' | sed 's/local\///') 2>/dev/null
sudo pacman -Rns --noconfirm $(pacman -Qs httpd | grep -E '^local/' | awk '{print $1}' | sed 's/local\///') 2>/dev/null

# 5. DESTROY all configuration directories
echo "🧨 DESTROYING all configuration directories..."
sudo rm -rf /etc/httpd
sudo rm -rf /etc/apache2  
sudo rm -rf /etc/php
sudo rm -rf /etc/my.cnf*
sudo rm -rf /etc/mysql
sudo rm -rf /etc/mariadb
sudo rm -rf /usr/share/httpd
sudo rm -rf /usr/share/apache2

# 6. ANNIHILATE all data directories  
echo "💀 ANNIHILATING all data directories..."
sudo rm -rf /srv/http
sudo rm -rf /var/www
sudo rm -rf /var/lib/mysql
sudo rm -rf /var/lib/mariadb
sudo rm -rf /var/lib/php
sudo rm -rf /run/mysqld
sudo rm -rf /run/mariadb
sudo rm -rf /run/php-fpm
sudo rm -rf /tmp/mysql*
sudo rm -rf /tmp/php*

# 7. DELETE all web applications
echo "🔥 DELETING all web applications..."
sudo rm -rf /usr/share/webapps
sudo rm -rf /usr/share/phpmyadmin
sudo rm -rf /usr/share/phpMyAdmin

# 8. ERASE all log files
echo "📝 ERASING all LAMP log files..."
sudo rm -rf /var/log/httpd
sudo rm -rf /var/log/apache2
sudo rm -rf /var/log/mysql*
sudo rm -rf /var/log/mariadb*
sudo rm -rf /var/log/php*

# 9. Remove users and groups
echo "👤 Removing LAMP users and groups..."
sudo userdel -f http 2>/dev/null
sudo userdel -f mysql 2>/dev/null  
sudo userdel -f www-data 2>/dev/null
sudo groupdel http 2>/dev/null
sudo groupdel mysql 2>/dev/null
sudo groupdel www-data 2>/dev/null

# 10. Clean systemd unit files
echo "🗂️ Cleaning systemd unit files..."
sudo rm -f /etc/systemd/system/httpd.service
sudo rm -f /etc/systemd/system/apache2.service  
sudo rm -f /etc/systemd/system/mysqld.service
sudo rm -f /etc/systemd/system/mariadb.service
sudo rm -f /etc/systemd/system/php-fpm.service
sudo systemctl daemon-reload

# 11. Remove any leftover binaries and libraries
echo "🔧 Removing leftover binaries and libraries..."
sudo rm -f /usr/bin/httpd /usr/bin/apache2 /usr/bin/mysql* /usr/bin/mariadb* /usr/bin/php*
sudo rm -rf /usr/lib/httpd
sudo rm -rf /usr/lib/apache2
sudo rm -rf /usr/lib/mysql
sudo rm -rf /usr/lib/mariadb  
sudo rm -rf /usr/lib/php

# 12. Clean include files
echo "📚 Cleaning include files..."
sudo rm -rf /usr/include/httpd
sudo rm -rf /usr/include/apache2
sudo rm -rf /usr/include/mysql
sudo rm -rf /usr/include/mariadb
sudo rm -rf /usr/include/php

# 13. Remove man pages and documentation
echo "📖 Removing documentation..."
sudo rm -rf /usr/share/man/man*/httpd*
sudo rm -rf /usr/share/man/man*/apache*
sudo rm -rf /usr/share/man/man*/mysql*
sudo rm -rf /usr/share/man/man*/mariadb*
sudo rm -rf /usr/share/man/man*/php*
sudo rm -rf /usr/share/doc/apache*
sudo rm -rf /usr/share/doc/mysql*
sudo rm -rf /usr/share/doc/mariadb*
sudo rm -rf /usr/share/doc/php*

# 14. Clean home directory artifacts
echo "🏠 Cleaning user home directory artifacts..."
rm -rf ~/.mysql_history
rm -rf ~/.php_history
rm -rf ~/.my.cnf

# 15. Remove any remaining config files in /etc
echo "⚙️ Final cleanup of /etc..."
sudo find /etc -name "*httpd*" -type f -delete 2>/dev/null
sudo find /etc -name "*apache*" -type f -delete 2>/dev/null  
sudo find /etc -name "*mysql*" -type f -delete 2>/dev/null
sudo find /etc -name "*mariadb*" -type f -delete 2>/dev/null
sudo find /etc -name "*php*" -type f -delete 2>/dev/null

# 16. Aggressive orphan package removal (multiple passes)
echo "🧼 Aggressive orphan package cleanup..."
for i in {1..3}; do
    orphans=$(pacman -Qdtq 2>/dev/null)
    if [[ -n "$orphans" ]]; then
        echo "🗑️ Pass $i: Removing orphaned packages..."
        sudo pacman -Rns --noconfirm $orphans 2>/dev/null
    else
        echo "✅ No orphaned packages found in pass $i"
        break
    fi
done

# 17. Clean package manager cache aggressively  
echo "🗑️ Aggressively cleaning package cache..."
sudo pacman -Scc --noconfirm 2>/dev/null
sudo paccache -rk0 2>/dev/null

# 18. Clear any remaining temporary files
echo "🧽 Final temporary file cleanup..."
sudo find /tmp -name "*mysql*" -delete 2>/dev/null
sudo find /tmp -name "*apache*" -delete 2>/dev/null
sudo find /tmp -name "*httpd*" -delete 2>/dev/null
sudo find /tmp -name "*php*" -delete 2>/dev/null

# 19. Update package database
echo "📊 Updating package database..."
sudo pacman -Sy

echo ""
echo "💀💀💀 LAMP STACK COMPLETELY ANNIHILATED! 💀💀💀"
echo "🔥 All Apache/HTTP, MySQL/MariaDB, PHP components DESTROYED"
echo "💣 All databases, websites, configurations PERMANENTLY DELETED"
echo "🧹 System cleaned of all LAMP traces"
echo ""
echo "⚠️  If you want to reinstall LAMP, run ./installLamp.sh"
echo "✅ Removal complete. System is now LAMP-free."
