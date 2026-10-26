# 📖 Panduan Instalasi & Konfigurasi MacPorts Web Development dari Nol (Fresh Install)

Panduan ini ditujukan bagi Anda yang baru saja melakukan **install ulang macOS**, **berpindah ke perangkat Mac baru** (Intel x86_64 maupun Apple Silicon ARM64), atau **rekan developer lain** yang ingin membangun lingkungan web development mandiri, cepat, dan stabil menggunakan **MacPorts**.

Stack yang akan dipasang:
* **PHP 8.3 & Ekstensi Lengkap** (FPM, MySQL, cURL, Mbstring, OpenSSL, GD, Intl, Zip, SQLite, OPcache)
* **Web Server Nginx** (Reverse Proxy FastCGI, arsitektur modular virtual host)
* **Database MariaDB 10.11 Server & Client**
* **Composer** (PHP Dependency Manager)
* **Node.js LTS / Latest** (Dikelola via `fnm`)
* **Otomasi Shell & Alias Kontrol Cepat**

---

## 🛠️ Langkah 1: Persiapan Sistem macOS

Sebelum memulai, pastikan Command Line Tools dan MacPorts telah terpasang di Mac Anda:

### 1. Pasang Xcode Command Line Tools
Buka Terminal dan jalankan:
```bash
xcode-select --install
```
Ikuti jendela instruksi yang muncul di layar hingga selesai.

### 2. Unduh & Pasang MacPorts
1. Buka situs resmi: [https://www.macports.org/install.php](https://www.macports.org/install.php)
2. Unduh paket installer `.pkg` yang sesuai dengan versi macOS Anda (Monterey, Ventura, Sonoma, Sequoia, dll.).
3. Lakukan instalasi `.pkg` seperti biasa.

### 3. Perbarui Port Index & Pastikan `$PATH` Aktif
Tutup dan buka kembali Terminal, lalu jalankan:
```bash
sudo port -v selfupdate
```
Pastikan path MacPorts (`/opt/local/bin` dan `/opt/local/sbin`) berada paling depan di sistem Anda.

---

## 🔑 Langkah 2: Konfigurasi Sudo Passwordless untuk MacPorts

Agar Anda maupun coding agent (seperti Antigravity, Claude Code, Cursor) dapat mengontrol service (`port load` / `port unload`) dan memasang paket tanpa harus terus-menerus mengetik password root:

```bash
echo "$(whoami) ALL=(ALL) NOPASSWD: /opt/local/bin/port" | sudo tee /etc/sudoers.d/macports
sudo chmod 0440 /etc/sudoers.d/macports
```

---

## 🗄️ Langkah 3: Instalasi & Inisialisasi MariaDB 10.11

### 1. Pasang Paket MariaDB via MacPorts
```bash
sudo port install mariadb-10.11 mariadb-10.11-server mysql_select
```

### 2. Tetapkan Client Default
```bash
sudo port select --set mysql mariadb-10.11
# Symlink mariadb CLI ke ~/.local/bin (opsional untuk kenyamanan)
mkdir -p ~/.local/bin
ln -sf /opt/local/lib/mariadb-10.11/bin/mariadb ~/.local/bin/mariadb
```

### 3. Inisialisasi Data Directory (Hanya untuk Mac Baru / Database Kosong)
```bash
sudo /opt/local/lib/mariadb-10.11/scripts/mariadb-install-db \
  --basedir=/opt/local \
  --datadir=/opt/local/var/db/mariadb-10.11 \
  --user=_mysql
```

### 4. Konfigurasi `my.cnf`
Buat direktori dan file konfigurasi MariaDB di `/opt/local/etc/mariadb-10.11/my.cnf`:
```bash
sudo mkdir -p /opt/local/etc/mariadb-10.11
sudo tee /opt/local/etc/mariadb-10.11/my.cnf << 'EOF'
[client-server]
socket = /tmp/mysql.sock
port = 3306

[mysqld]
user = _mysql
datadir = /opt/local/var/db/mariadb-10.11
socket = /tmp/mysql.sock
port = 3306
bind-address = 127.0.0.1
sql_mode = NO_ENGINE_SUBSTITUTION
EOF
```

### 5. Nyalakan Layanan MariaDB
```bash
sudo port load mariadb-10.11-server
```
*Uji coba koneksi:*
```bash
mysql -u root -e "SELECT VERSION();"
```

---

## 🐘 Langkah 4: Instalasi PHP 8.3 & Ekstensi Penting

### 1. Pasang Paket PHP 8.3 via MacPorts
```bash
sudo port install php83 php83-fpm php83-mysql php83-openssl php83-curl \
                  php83-mbstring php83-zip php83-gd php83-intl php83-sqlite \
                  php83-iconv php83-opcache php_select
```

### 2. Pilih PHP 8.3 sebagai Versi Default Sistem
```bash
sudo port select --set php php83
```
*Periksa versi PHP:*
```bash
php -v
# Seharusnya muncul: PHP 8.3.x (cli)
```

---

## 🌐 Langkah 5: Instalasi Nginx Web Server

```bash
sudo port install nginx
```

---

## ⚙️ Langkah 6: Terapkan Konfigurasi Web Server & PHP-FPM

Jika Anda meng-clone repositori [`adi-jaya/macports-webdev-setup`](https://github.com/adi-jaya/macports-webdev-setup), Anda cukup menjalankan skrip otomatis yang sudah disediakan:

```bash
git clone https://github.com/adi-jaya/macports-webdev-setup.git ~/Documents/MacPorts_Docs
cd ~/Documents/MacPorts_Docs
sudo ./scripts/setup_webserver.sh
```

### Penjelasan Manual (Jika Tidak Menggunakan Skrip):
1. **Konfigurasi `php.ini`:**
   - Salin dari `/opt/local/etc/php83/php.ini-development` ke `/opt/local/etc/php83/php.ini`.
   - Atur `date.timezone = Asia/Jakarta`.
   - Atur `memory_limit = 512M`, `upload_max_filesize = 64M`, `post_max_size = 64M`.
   - Atur `mysqli.default_socket = /tmp/mysql.sock` dan `pdo_mysql.default_socket = /tmp/mysql.sock`.
2. **Konfigurasi `php-fpm` (`/opt/local/etc/php83/php-fpm.d/www.conf`):**
   - Atur `user = <username_anda>` dan `group = staff`.
   - Atur `listen = 127.0.0.1:9000`.
3. **Konfigurasi `nginx.conf` (`/opt/local/etc/nginx/nginx.conf`):**
   - Atur worker `user <username_anda> staff;`.
   - Tambahkan baris `include /opt/local/etc/nginx/servers/*.conf;`.
4. **Kepemilikan Direktori Config:**
   - Serahkan hak milik folder `/opt/local/etc/php83` dan `/opt/local/etc/nginx` ke user Anda (`$(whoami):admin`) agar dapat membuat virtual host baru tanpa `sudo`.

---

## 📦 Langkah 7: Instalasi Composer & Node.js (FNM)

### 1. Pasang Composer (Mandiri di User Space)
```bash
mkdir -p ~/.local/bin
curl -sS https://getcomposer.org/installer | php
mv composer.phar ~/.local/bin/composer
chmod +x ~/.local/bin/composer
```
*Uji:* `composer --version`

### 2. Pasang Node.js via FNM (Fast Node Manager)
```bash
sudo port install fnm
fnm install 24
fnm default 24
```
*Uji:* `node -v` dan `npm -v`

---

## 💻 Langkah 8: Konfigurasi Shell `~/.zshrc`

Buka file `~/.zshrc` dan pastikan konfigurasi berikut terpasang:

```zsh
typeset -U PATH path

# ==========================================
# System & MacPorts PATH
# ==========================================
export PATH="/opt/local/bin:/opt/local/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.local/bin:$PATH"

# ==========================================
# Node.js Environment (fnm - MacPorts)
# ==========================================
eval "$(fnm env --use-on-cd)"

# ==========================================
# MariaDB (MacPorts) Control Aliases
# ==========================================
alias db-start="sudo port load mariadb-10.11-server"
alias db-stop="sudo port unload mariadb-10.11-server"
alias db-status="ps aux | grep -E '[m]ariadbd|[m]ysqld' | grep -v grep || echo 'MariaDB is not running.'"

# ==========================================
# Web Server (Nginx + PHP-FPM) Control Aliases
# ==========================================
alias web-start="sudo port load php83-fpm && sudo port load nginx"
alias web-stop="sudo port unload nginx && sudo port unload php83-fpm"
alias web-restart="sudo port unload nginx && sudo port unload php83-fpm && sudo port load php83-fpm && sudo port load nginx"
alias web-status="ps aux | grep -E '[p]hp-fpm83|[n]ginx' | grep -v grep || echo 'Web Server is not running.'"
```

Muat ulang shell Anda:
```bash
source ~/.zshrc
```

---

## ✅ Langkah 9: Verifikasi Akhir

Jalankan perintah berikut untuk menyalakan seluruh service:
```bash
db-start
web-start
```

Periksa status proses:
```bash
db-status
web-status
```

Buka browser dan akses:
* **[http://localhost/](http://localhost/)** &rarr; Menampilkan dashboard status web server, PHP 8.3, dan MariaDB.

Selamat! Lingkungan MacPorts Web Development Anda kini sudah siap digunakan untuk proyek Laravel, PHP, Node.js, dan database MariaDB.
