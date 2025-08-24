* νέο **group-based permission model** (webdev)
* το **setup** βήμα που κάνει auto-fix στα `~/Sites`
* τις νέες εντολές `check` και `repair`
* και τις βελτιώσεις που κάναμε στο `installLamp`.

---

### Updated


## 📦 Arch Linux LAMP Stack & Sites Manager

This repository provides helper scripts to **install**, **remove**, and **manage** a local LAMP (Linux, Apache, MariaDB, PHP) stack on Arch Linux.  
It also includes a `sites-manager` tool for easily creating and managing local virtual hosts, with sane **permissions and group handling**.

---

## ⚠️ Before you start

All projects live under `~/Sites` and use a **shared group** (`webdev`) so that both you and Apache/PHP (`http` user) can read/write files without permission conflicts.

The first step after installation is to run:

```bash
sites-manager setup
````

This will:

* Ensure the `webdev` group exists and add both your user and `http` to it.
* Create `~/Sites` with correct permissions (`2775` on dirs, `664` on files).
* Enable setgid + default ACLs so all new files/folders inherit group `webdev`.
* Configure PHP-FPM to run as `http:webdev` with `UMask=0002`.
* Fix `$HOME` permissions so Apache can traverse into `~/Sites`.

👉 After running `setup`, log out and log back in to apply new group memberships.

---

## 📂 Scripts

* `installLamp.sh` → Install & configure a hardened LAMP stack (Apache event MPM + PHP-FPM + MariaDB + phpMyAdmin)
* `removeLamp.sh` → Completely remove the LAMP stack and related configs
* `sites-manager.sh` → Manage your development sites (create, remove, list, fix, check/repair, scaffold Laravel/WordPress, etc.)

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

4. **Run initial setup**

   ```bash
   ./sites-manager.sh setup
   ```

   Then log out and back in.

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
sites-manager setup             # One-time setup (create ~/Sites, groups, ACLs, PHP-FPM config)
sites-manager add <site>        # Add new site (auto create dir & vhost)
sites-manager remove <site>     # Remove site & vhost
sites-manager list              # List active sites
sites-manager scan              # Auto-detect sites in ~/Sites and add vhosts
sites-manager fix-cms <site>    # Fix permissions for a specific project (Laravel/WP/etc.)
sites-manager check             # Check for permission/group issues under ~/Sites
sites-manager repair            # Auto-fix permission/group issues under ~/Sites
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

* **Check/fix permissions**

  ```bash
  sites-manager check   # list any issues
  sites-manager repair  # fix all issues
  ```

* **SSL for local dev**
  Use [mkcert](https://github.com/FiloSottile/mkcert) for HTTPS on `.test` domains.

---

## ⚡ Quickstart Examples

### Laravel (zero to running in 3 steps)

```bash
./installLamp.sh
sites-manager setup
sites-manager init laravel blog
xdg-open http://blog.test
```

### WordPress (with DB auto-config)

```bash
./installLamp.sh
sites-manager setup
WP_DB_NAME=wp_blog WP_DB_USER=root WP_DB_PASS=secret sites-manager init wp blog
xdg-open http://blog.test
```

---

## ✅ Requirements

* Arch Linux (or Arch-based distro)
* `sudo` privileges
* Internet access (for pacman, composer, wp-cli)
* `acl` package (for proper permission inheritance)

---

## ⚠️ Disclaimer

This is a personal project created for learning and convenience in local development environments.
The scripts are provided *as-is* without any guarantees or warranties. Use them at your OWN RISK.
I am not responsible for any data loss, misconfiguration, or damage that may result from using these scripts on your system.
Always review and adapt the code to your specific needs before running it on production or critical environments.

```

---

Θέλεις να στο στείλω και σαν `README.md` αρχείο έτοιμο να το ρίξεις μέσα στο repo;
```
