## 📦 Arch Linux LAMP Stack & Sites Manager

This repository provides helper scripts to **install**, **remove**, and **manage** a local LAMP (Linux, Apache, MariaDB, PHP) stack on Arch Linux.
It also includes a `sites-manager` tool for easily creating and managing local virtual hosts.

---

## ⚠️ Before you start

Make sure your `$HOME/Sites` directory is accessible by Apache:

```bash
mkdir -p ~/Sites
chmod o+x ~
chmod o+rx ~/Sites
```

This allows Apache (running as user `http`) to traverse into your home directory and serve project files.

---

## 📂 Scripts

* `installLamp.sh` → Install & configure a hardened LAMP stack
* `removeLamp.sh` → Completely remove the LAMP stack and related configs
* `sites-manager.sh` → Manage your development sites (create, remove, list, scaffold Laravel/WordPress, etc.)

---

## 🚀 Installation

1. **Clone or copy the scripts**

   ```bash
   git clone https://github.com/webclubz/archLamp.git
   cd archLamp
   ```

2. **Make them executable**

   ```bash
   chmod +x installLamp.sh removeLamp.sh sites-manager.sh
   ```

3. **Run installation**

   ```bash
   ./installLamp.sh
   ```

   This installs Apache, MariaDB, PHP (with common extensions), phpMyAdmin, configures vhosts, and applies sane defaults.

---

## 🧰 Sites Manager

The `sites-manager` script simplifies creating and managing local vhosts.

### Install globally

```bash
sudo cp sites-manager.sh /usr/local/bin/sites-manager
sudo chmod +x /usr/local/bin/sites-manager
```

### Usage

```bash
sites-manager add <site>        # Add new site (auto create dir & vhost)
sites-manager remove <site>     # Remove site & vhost
sites-manager list              # List active sites
sites-manager scan              # Auto-detect sites in ~/Sites and add vhosts
sites-manager fix-cms <site>    # Fix permissions (useful for Laravel/WordPress)
sites-manager start             # Start Apache + MariaDB
sites-manager stop              # Stop Apache + MariaDB
sites-manager init laravel <s>  # Scaffold new Laravel project + vhost
sites-manager init wp <s>       # Scaffold new WordPress site + vhost
```

Projects are created under `~/Sites/<site>` and served at `http://<site>.test`.

---

## 🗑 Removing LAMP

To remove everything:

```bash
./removeLamp.sh
```

---

## 💡 Tips & Tricks

* **Logs**

  ```bash
  sudo journalctl -u httpd -f
  tail -f /var/log/httpd/<site>_error.log
  ```

* **MariaDB security**

  ```bash
  sudo mariadb-secure-installation
  ```

* **phpMyAdmin**
  [http://localhost/phpmyadmin](http://localhost/phpmyadmin)

* **Quick restart**

  ```bash
  sites-manager stop && sites-manager start
  ```

* **Laravel after init**

  ```bash
  cd ~/Sites/blog
  php artisan migrate
  php artisan serve
  ```

* **WordPress with DB env vars**

  ```bash
  WP_DB_NAME=wp_blog WP_DB_USER=root WP_DB_PASS=secret sites-manager init wp blog
  ```

* **SSL for local dev**
  Use [mkcert](https://github.com/FiloSottile/mkcert) for HTTPS on `.test` domains.

---

## ⚡ Quickstart Examples

### Laravel (zero to running in 3 steps)

```bash
./installLamp.sh
sites-manager init laravel blog
xdg-open http://blog.test
```

### WordPress (with DB auto-config)

```bash
./installLamp.sh
WP_DB_NAME=wp_blog WP_DB_USER=root WP_DB_PASS=secret sites-manager init wp blog
xdg-open http://blog.test
```

---

## ✅ Requirements

* Arch Linux (or Arch-based distro)
* `sudo` privileges
* Internet access (for pacman, composer, wp-cli)

---


## ⚠️  Disclaimer

This is a personal project created for learning and convenience in local development environments. The scripts are provided *as-is* without any guarantees or warranties. Use them at your OWN RISK. I am not responsible for any data loss, misconfiguration, or damage that may result from using these scripts on your system. Always review and adapt the code to your specific needs before running it on production or critical environments.
