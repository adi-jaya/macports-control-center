# 🚀 Panduan Komprehensif: Setup & Manajemen MacPorts untuk Pengembang Laravel

Dokumentasi ini adalah panduan modular dan terperinci untuk membangun serta mengelola lingkungan pengembangan **Laravel** di macOS (baik **Intel x86_64** maupun **Apple Silicon ARM64**) menggunakan **MacPorts**. 

Panduan ini dirancang agar **tidak kaku pada versi tertentu**, melainkan memberikan rumus dan sistem untuk:
- Menginstal, mengaktifkan, dan beralih antar berbagai versi PHP (PHP 8.1, 8.2, 8.3, 8.4, dst.).
- Menjalankan beberapa versi PHP-FPM secara bersamaan (*concurrent*) untuk proyek-proyek Laravel dengan kebutuhan versi PHP yang berbeda.
- Mengelola database MariaDB atau MySQL dari berbagai versi rilis.
- Mengonfigurasi Nginx dengan standar keamanan dan perutean (*routing*) resmi Laravel.
- Menghapus (*uninstall*) versi atau pustaka yang sudah tidak terpakai secara bersih.

---

## 📑 Daftar Isi

1. [Arsitektur Stack untuk Laravel](#1-arsitektur-stack-untuk-laravel)
2. [Prasyarat & Konfigurasi Dasar macOS](#2-prasyarat--konfigurasi-dasar-macos)
3. [Manajemen Versi PHP untuk Laravel](#3-manajemen-versi-php-untuk-laravel)
   - [Tabel Kompatibilitas Versi Laravel & PHP](#tabel-kompatibilitas-versi-laravel--php)
   - [Rumus Instalasi Versi PHP Pilihan](#rumus-instalasi-versi-php-pilihan)
   - [Beralih Versi PHP Global (CLI)](#beralih-versi-php-global-cli)
   - [Menjalankan Multi-PHP FPM Bersamaan (Concurrent Multi-Version)](#menjalankan-multi-php-fpm-bersamaan-concurrent-multi-version)
   - [Menonaktifkan & Menghapus Versi PHP Lama](#menonaktifkan--menghapus-versi-php-lama)
4. [Manajemen Database (MariaDB & MySQL)](#4-manajemen-database-mariadb--mysql)
   - [Instalasi & Memilih Versi MariaDB](#instalasi--memilih-versi-mariadb)
   - [Inisialisasi Data Baru & Konfigurasi `my.cnf`](#inisialisasi-data-baru--konfigurasi-mycnf)
   - [Beralih Versi Database Client](#beralih-versi-database-client)
5. [Konfigurasi Web Server Nginx Khusus Laravel](#5-konfigurasi-web-server-nginx-khusus-laravel)
   - [Konfigurasi Induk (`nginx.conf`)](#konfigurasi-induk-nginxconf)
   - [Template Server Block Virtual Host Laravel](#template-server-block-virtual-host-laravel)
   - [Pilihan Domain Lokal (`.test`) vs Port-Based](#pilihan-domain-lokal-test-vs-port-based)
6. [Integrasi Ekosistem Laravel (Composer, Node/Vite, Permissions)](#6-integrasi-ekosistem-laravel-composer-nodevite-permissions)
   - [Penyelesaian Permanen Masalah Permission `storage/`](#penyelesaian-permanen-masalah-permission-storage)
   - [Composer & FNM (Node.js untuk Vite)](#composer--fnm-nodejs-untuk-vite)
7. [Shell Aliases & Cheatsheet Pengelolaan](#7-shell-aliases--cheatsheet-pengelolaan)

---

## 1. Arsitektur Stack untuk Laravel

Mengapa menggunakan MacPorts murni untuk Laravel di macOS?
* **Bebas Masalah SDK macOS:** Binary MacPorts dikompilasi langsung terhadap SDK macOS mesin Anda, menghindari crash `dyld: Symbol not found` seperti pada Laravel Herd di macOS versi lama (seperti Monterey/Ventura).
* **Multi-PHP Tanpa Konflik:** Setiap versi PHP diisolasi di folder `/opt/local/etc/phpXY` dan `/opt/local/lib/phpXY`.
* **Kinerja Native:** Tanpa virtualisasi Docker yang berat untuk siklus dev harian, menghemat RAM dan CPU.

---

## 2. Prasyarat & Konfigurasi Dasar macOS

### A. Pasang Xcode Command Line Tools
```bash
xcode-select --install
```

### B. Pasang MacPorts
1. Kunjungi: [https://www.macports.org/install.php](https://www.macports.org/install.php)
2. Unduh berkas `.pkg` sesuai versi macOS Anda (Monterey, Ventura, Sonoma, Sequoia, dll.) dan pasang.
3. Buka Terminal baru, lalu sinkronkan pustaka paket:
   ```bash
   sudo port -v selfupdate
   ```

### C. Konfigurasi Sudo Passwordless untuk MacPorts
Agar perintah `port load`, `port unload`, dan manajemen paket dapat dijalankan oleh Anda maupun AI coding assistant tanpa terus-menerus diminta password root:
```bash
echo "$(whoami) ALL=(ALL) NOPASSWD: /opt/local/bin/port" | sudo tee /etc/sudoers.d/macports
sudo chmod 0440 /etc/sudoers.d/macports
```

---

## 3. Manajemen Versi PHP untuk Laravel

### Tabel Kompatibilitas Versi Laravel & PHP

| Versi Laravel | Versi PHP yang Didukung | Versi MacPorts yang Disarankan |
| :--- | :--- | :--- |
| **Laravel 12 (Terbaru)** | PHP 8.2 s/d PHP 8.4 | `php83` atau `php84` |
| **Laravel 11** | PHP 8.2 s/d PHP 8.3 | `php82` atau `php83` |
| **Laravel 10** | PHP 8.1 s/d PHP 8.3 | `php81` atau `php82` |
| **Laravel 9 (Legacy)** | PHP 8.0 s/d PHP 8.2 | `php81` atau `php82` |

---

### Rumus Instalasi Versi PHP Pilihan

MacPorts menggunakan konvensi penamaan `php<nomor_versi>` (contoh: `php82`, `php83`, `php84`).  
Laravel memerlukan sekumpulan modul wajib (BCMath, cURL, Fileinfo, Mbstring, OpenSSL, PDO MySQL, Tokenizer, XML, Zip, GD/Intl).

Gunakan rumus satu baris berikut untuk menginstal versi PHP yang Anda butuhkan (ganti `83` dengan `82`, `84`, atau `81` sesuai kebutuhan):

```bash
# Ganti TARGET_PHP ke versi yang Anda inginkan (contoh: 82, 83, atau 84)
TARGET_PHP="83"

sudo port install php${TARGET_PHP} \
                  php${TARGET_PHP}-fpm \
                  php${TARGET_PHP}-mysql \
                  php${TARGET_PHP}-openssl \
                  php${TARGET_PHP}-curl \
                  php${TARGET_PHP}-mbstring \
                  php${TARGET_PHP}-zip \
                  php${TARGET_PHP}-gd \
                  php${TARGET_PHP}-intl \
                  php${TARGET_PHP}-sqlite \
                  php${TARGET_PHP}-iconv \
                  php${TARGET_PHP}-opcache \
                  php_select
```

*(Opsional: Jika proyek menggunakan Redis)*:
```bash
sudo port install php${TARGET_PHP}-redis
```

---

### Beralih Versi PHP Global (CLI)

Anda dapat menginstal beberapa versi PHP sekaligus di Mac Anda dan berpindah versi CLI kapan saja menggunakan utilitas `port select`:

```bash
# 1. Lihat seluruh versi PHP yang terpasang di MacPorts
port select --list php

# 2. Aktifkan versi yang Anda inginkan untuk Terminal (CLI)
sudo port select --set php php82   # Untuk beralih ke PHP 8.2
sudo port select --set php php83   # Untuk beralih ke PHP 8.3
sudo port select --set php php84   # Untuk beralih ke PHP 8.4

# 3. Verifikasi
php -v
```

---

### Menjalankan Multi-PHP FPM Bersamaan (Concurrent Multi-Version)

Seringkali developer memiliki **Proyek A yang membutuhkan PHP 8.2** dan **Proyek B yang membutuhkan PHP 8.3/8.4**. Dengan MacPorts, Anda tidak perlu bolak-balik switch versi, karena **kedua PHP-FPM dapat berjalan berdampingan pada port atau socket yang berbeda**.

#### 1. Tetapkan Port Unik untuk Masing-Masing PHP-FPM Pool
Buka konfigurasi pool untuk masing-masing versi:

* **PHP 8.2 (`/opt/local/etc/php82/php-fpm.d/www.conf`):**
  ```ini
  user = adijaya
  group = staff
  listen = 127.0.0.1:9082
  ```
* **PHP 8.3 (`/opt/local/etc/php83/php-fpm.d/www.conf`):**
  ```ini
  user = adijaya
  group = staff
  listen = 127.0.0.1:9000   ; atau 127.0.0.1:9083
  ```
* **PHP 8.4 (`/opt/local/etc/php84/php-fpm.d/www.conf`):**
  ```ini
  user = adijaya
  group = staff
  listen = 127.0.0.1:9084
  ```

#### 2. Muat Seluruh Layanan FPM yang Dibutuhkan
```bash
sudo port load php82-fpm
sudo port load php83-fpm
```

#### 3. Arahkan di Konfigurasi Nginx Virtual Host Proyek
Pada blok server Nginx milik proyek yang bersangkutan, cukup arahkan `fastcgi_pass` ke port PHP yang sesuai:
* Proyek Laravel 10 (PHP 8.2): `fastcgi_pass 127.0.0.1:9082;`
* Proyek Laravel 12 (PHP 8.3): `fastcgi_pass 127.0.0.1:9000;`

---

### Menonaktifkan & Menghapus Versi PHP Lama

Jika ada versi PHP yang sudah tidak lagi dipakai (misalnya versi eksperimental `php85` atau versi lama `php81`):

#### 1. Hentikan Layanan FPM-nya (jika aktif):
```bash
sudo port unload php85-fpm 2>/dev/null || true
```

#### 2. Nonaktifkan (*Deactivate*) Versi Tersebut:
*Menonaktifkan biner tanpa menghapusnya dari disk (bisa diaktifkan kembali sewaktu-waktu):*
```bash
sudo port deactivate php85
```

#### 3. Hapus Permanen (*Uninstall*):
*Menghapus paket beserta seluruh ekstensinya dari sistem:*
```bash
# Hapus seluruh ekstensi php85 terlebih dahulu
sudo port uninstall --follow-dependents php85

# Atau hapus spesifik:
sudo port uninstall php85-mysql php85-curl php85-fpm php85
```

#### 4. Bersihkan Pustaka Dependensi yang Tertinggal (*Leaves*):
MacPorts menyediakan perintah untuk membersihkan pustaka yang sudah tidak memiliki pengguna (*orphaned dependencies*):
```bash
sudo port uninstall leaves
```

---

## 4. Manajemen Database (MariaDB & MySQL)

### Instalasi & Memilih Versi MariaDB

Di MacPorts, Anda dapat memilih versi LTS yang stabil, seperti:
* `mariadb-10.11` (LTS stabil yang didukung jangka panjang — sangat direkomendasikan)
* `mariadb-11.4` (LTS modern)
* `mysql8` (Oracle MySQL 8.0)

**Contoh Instalasi MariaDB LTS:**
```bash
sudo port install mariadb-10.11 mariadb-10.11-server mysql_select
```

### Inisialisasi Data Baru & Konfigurasi `my.cnf`

1. **Inisialisasi Data Baru (Hanya untuk Mac baru / fresh install):**
   ```bash
   sudo /opt/local/lib/mariadb-10.11/scripts/mariadb-install-db \
     --basedir=/opt/local \
     --datadir=/opt/local/var/db/mariadb-10.11 \
     --user=_mysql
   ```

2. **Berkas Konfigurasi `/opt/local/etc/mariadb-10.11/my.cnf`:**
   ```ini
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
   ```

3. **Menyalakan Layanan MariaDB:**
   ```bash
   sudo port load mariadb-10.11-server
   ```

### Beralih Versi Database Client
Jika Anda memiliki beberapa client MySQL/MariaDB terpasang, gunakan `port select`:
```bash
port select --list mysql
sudo port select --set mysql mariadb-10.11
```

---

## 5. Konfigurasi Web Server Nginx Khusus Laravel

### Konfigurasi Induk (`/opt/local/etc/nginx/nginx.conf`)

Pastikan konfigurasi utama Nginx menggunakan user lokal Anda agar tidak terjadi masalah hak akses file saat melayani request:

```nginx
user adijaya staff; # Sesuaikan dengan username macOS Anda
worker_processes auto;
pid /opt/local/var/run/nginx/nginx.pid;
error_log /opt/local/var/log/nginx/error.log warn;

events {
    worker_connections 1024;
}

http {
    include mime.types;
    default_type application/octet-stream;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    # Wajib untuk upload file di Laravel:
    client_max_body_size 64M;

    # Gzip Compression
    gzip on;
    gzip_disable "msie6";
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript;

    # Modular Virtual Hosts
    include /opt/local/etc/nginx/servers/*.conf;
}
```

---

### Template Server Block Virtual Host Laravel

Simpan setiap konfigurasi proyek di `/opt/local/etc/nginx/servers/<nama_proyek>.conf`.  
Konfigurasi di bawah ini telah disesuaikan dengan standar keamanan dan perutean (*routing*) Laravel:

```nginx
server {
    listen 8080;                     # Port unik proyek (atau port 80 dengan server_name)
    server_name localhost 127.0.0.1;

    # Wajib mengarah ke folder public/ milik proyek Laravel:
    root /Users/adijaya/MyFiles/Projects/SiAkurat/laravel-siakurat-pt-smt/public;

    # Header Keamanan
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    index index.php index.html;
    charset utf-8;

    # Perutean URL Laravel (Mencegah 404 pada route web, Livewire, API)
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    # Handler PHP-FPM
    location ~ \.php$ {
        # Arahkan ke port PHP-FPM versi yang diinginkan:
        fastcgi_pass 127.0.0.1:9000;
        
        # Menggunakan realpath_root untuk menghindari symlink issues pada framework
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi.conf;
        fastcgi_hide_header X-Powered-By;
    }

    # Blokir akses ke berkas sensitif (.env, .git, dll.)
    location ~ /\.(?!well-known).* {
        deny all;
    }
}
```

### Pilihan Domain Lokal (`.test`) vs Port-Based

1. **Model Port-Based (Paling Mudah, Nol Konfigurasi DNS):**
   - Menggunakan `http://localhost:8080`, `http://localhost:8081`, dst.
   - Tidak perlu mengubah `/etc/hosts` dan tidak membutuhkan `dnsmasq`.
2. **Model Domain `.test` (Mirip Laravel Herd / Valet):**
   - Tambahkan entri di `/etc/hosts`:
     ```text
     127.0.0.1 siakurat.test
     ```
   - Pada Nginx server block:
     ```nginx
     listen 80;
     server_name siakurat.test;
     ```
   - Proyek dapat dibuka di browser via `http://siakurat.test/`.

---

## 6. Integrasi Ekosistem Laravel (Composer, Node/Vite, Permissions)

### Penyelesaian Permanen Masalah Permission `storage/`

Masalah paling umum bagi developer Laravel di macOS/Linux adalah:
> `The stream or file ".../storage/logs/laravel.log" could not be opened in append mode: failed to open stream: Permission denied`

**Solusi Arsitektur MacPorts yang Kita Terapkan:**
Di lingkungan ini, kita mengonfigurasi **PHP-FPM (`www.conf`) berjalan sebagai user lokal Anda (`adijaya:staff`)**, bukan user `nobody` atau `_www`.
* Ketika Anda menjalankan `php artisan` di CLI, file dibuat sebagai user `adijaya`.
* Ketika ada request HTTP dari browser via Nginx, PHP-FPM juga menulis sebagai user `adijaya`.
* **Hasil:** Konflik permission hilang 100% secara permanen tanpa perlu menjalankan perintah berbahaya `chmod -R 777 storage`.

Jika Anda mengkloning proyek baru dari Git, cukup pastikan folder storage ada dan writable oleh user Anda:
```bash
cd /path/to/laravel-project
chmod -R u+rwX storage bootstrap/cache
```

---

### Composer & FNM (Node.js untuk Vite)

#### Composer (Dipasang Mandiri di User Space):
```bash
mkdir -p ~/.local/bin
curl -sS https://getcomposer.org/installer | php
mv composer.phar ~/.local/bin/composer
chmod +x ~/.local/bin/composer
```
*Catatan:* Composer akan otomatis mendeteksi dan menggunakan versi PHP yang sedang aktif di `php -v`.

#### Node.js via FNM (Fast Node Manager):
Proyek Laravel modern menggunakan **Vite** yang membutuhkan Node.js versi modern (Node 18, 20, 22, atau 24).
```bash
# Pasang fnm via MacPorts
sudo port install fnm

# Pasang Node.js versi 24 (atau versi yang Anda butuhkan)
fnm install 24
fnm default 24
```
Di dalam proyek Laravel Anda:
```bash
npm install
npm run dev   # Untuk hot-module reload Vite
npm run build # Untuk build asset produksi
```

---

## 7. Shell Aliases & Cheatsheet Pengelolaan

Tambahkan alias berikut ke file `~/.zshrc` Anda untuk kontrol cepat sehari-hari:

```zsh
# ==========================================
# System & MacPorts PATH
# ==========================================
export PATH="/opt/local/bin:/opt/local/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.local/bin:$PATH"

# ==========================================
# Node.js Environment (fnm - MacPorts)
# ==========================================
eval "$(fnm env --use-on-cd)"

# ==========================================
# Database Control
# ==========================================
alias db-start="sudo port load mariadb-10.11-server"
alias db-stop="sudo port unload mariadb-10.11-server"
alias db-status="ps aux | grep -E '[m]ariadbd|[m]ysqld' | grep -v grep || echo 'MariaDB is not running.'"

# ==========================================
# Web Server (Nginx + PHP-FPM) Control
# ==========================================
alias web-start="sudo port load php83-fpm && sudo port load nginx"
alias web-stop="sudo port unload nginx && sudo port unload php83-fpm"
alias web-restart="sudo port unload nginx && sudo port unload php83-fpm && sudo port load php83-fpm && sudo port load nginx"
alias web-status="ps aux | grep -E '[p]hp-fpm|[n]ginx' | grep -v grep || echo 'Web Server is not running.'"

# ==========================================
# Laravel Helper Aliases
# ==========================================
alias art="php artisan"
alias mfs="php artisan migrate:fresh --seed"
```

---

## 💡 Rangkuman Siklus Perintah Harian

| Kebutuhan | Perintah |
| :--- | :--- |
| **Menyalakan seluruh stack** | `db-start && web-start` |
| **Mematikan seluruh stack** | `web-stop && db-stop` |
| **Ganti versi PHP CLI ke 8.2** | `sudo port select --set php php82` |
| **Ganti versi PHP CLI ke 8.3** | `sudo port select --set php php83` |
| **Cek versi PHP aktif** | `php -v` |
| **Tambah Virtual Host Proyek** | Buat berkas di `/opt/local/etc/nginx/servers/<project>.conf`, lalu jalankan `web-restart` |
| **Hapus paket / versi lama** | `sudo port uninstall --follow-dependents <nama_paket>` |
| **Bersihkan sisa pustaka** | `sudo port uninstall leaves` |
