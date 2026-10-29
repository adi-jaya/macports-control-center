# 📚 MacPorts Control Center & Pusat Dokumentasi Web Dev

[![GitHub Repository](https://img.shields.io/badge/GitHub-adi--jaya%2Fmacports--control--center-181717?style=flat&logo=github)](https://github.com/adi-jaya/macports-control-center)
[![macOS Monterey](https://img.shields.io/badge/macOS-Monterey%2012.7%2B%20(Intel%20x86__64)-0078D7?logo=apple)](https://apple.com)
[![Swift Native](https://img.shields.io/badge/App-SwiftUI%20%2B%20AppKit%20(Native)-FA7343?logo=swift)](build-app.sh)
[![Tests](https://img.shields.io/badge/Tests-42%2F42%20Passing-success)](Tests/)

Selamat datang di repositori **MacPorts Control Center** dan pusat dokumentasi lingkungan web development native berbasis **MacPorts** pada **macOS Monterey 12.7.6 (Intel x86_64)**. Repositori publik ini tersinkronisasi di [**github.com/adi-jaya/macports-control-center**](https://github.com/adi-jaya/macports-control-center).

Repositori ini menggabungkan dua peran utama:
1. **`MacPorts Control Center.app`**: Aplikasi GUI Desktop Native macOS berbasis **SwiftUI + AppKit** yang sangat ringan (~14–22 MB RAM, ~4.2 MB binary) dilengkapi menu bar extra (`NSStatusItem`) untuk mengelola seluruh stack web dev tanpa bergantung pada PHP web server.
2. **Dokumentasi & Knowledge Base Source of Truth**: Dokumentasi teknis, template konfigurasi acuan, dan skrip otomasi sistem untuk runtime Nginx, PHP-FPM, dan MariaDB.

---

## 🖥️ Aplikasi Desktop: `MacPorts Control Center.app`

`MacPorts Control Center.app` adalah aplikasi GUI native macOS berarsitektur **zero-dependency** (hanya menggunakan Apple macOS SDK bawaan) yang dirancang khusus untuk mengelola lingkungan development MacPorts secara visual, cepat, dan aman.

### 🌟 Fitur Utama & 7 Tab Navigasi

| Tab | Nama Fitur | Kemampuan & Operasi |
| :---: | :--- | :--- |
| 1 | **Services & Doctor** | Auto-discovery LaunchDaemons (`/Library/LaunchDaemons/org.macports.*`), deteksi proses aktif (`ps aux`), kontrol Start/Stop/Restart, dan **1-Click Stack Doctor Auto-Fix** untuk menegakkan 5 positive guardrails. |
| 2 | **Virtual Hosts** | Visual explorer untuk berkas konfigurasi `/opt/local/etc/nginx/servers/*.conf`, deteksi konflik port, validasi sintaks `nginx -t`, dan deteksi otomatis konfigurasi Laravel `.env`. |
| 3 | **PHP Manager** | Manajemen concurrent multi-PHP FPM pools (PHP 8.1 s/d 8.5), switcher PHP CLI global (`port select`), checkbox installer ekstensi PHP subport (`php83-curl`, `php83-mbstring`, dll.), dan live editor `php.ini`. |
| 4 | **Databases** | Status engine MariaDB/MySQL via socket Unix `/tmp/mysql.sock`, explorer 24+ database, **1-Click Backup `.sql`** via `NSSavePanel` + `mysqldump`, **1-Click Import `.sql`** via `NSOpenPanel`, serta installer MariaDB 11.4 LTS dan MySQL 8. |
| 5 | **MacPorts Packages** | Universal package search (`port search`), filter tab (*All / Installed / Outdated*), manajemen multi-versi port (`name@version`), upgrade outdated ports, pembersih dependency (`uninstall leaves`), dan toolchain switcher dinamis (`port select`). |
| 6 | **Server Logs** | Real-time live log tailer untuk Nginx (`error.log`, `access.log`), PHP-FPM (`php-fpm.log`), dan MariaDB (`*.err`) dilengkapi banner **🔓 Perbaiki Izin Baca Log (Stack Doctor)** otomatis saat izin file terbatas (`0600 root:admin`). |
| 7 | **Documentation** | Built-in native Markdown reader (*zero-WebKit*, *zero-Electron*) yang merender dokumentasi repositori (`*.md`) langsung dari bundel aplikasi menggunakan `NSTextView` dan `NSAttributedString`. |

### 🟢 macOS Menu Bar Extra (`NSStatusItem`)
Aplikasi tetap berjalan di Menu Bar macOS dengan status indicator dinamis bahkan ketika jendela utama ditutup:
* **Indikator Visual:** ● Hijau (Running), ● Kuning (Degraded / Updating), ● Merah (Stopped).
* **Ringkasan Status:** Header status real-time ("Web Stack: Running", "PHP 8.3 | MariaDB 10.11").
* **Quick Actions:** *Start Services*, *Restart Web Stack*, *Stop Services*.
* **Quick Links:** Buka [http://localhost:80](http://localhost:80), Buka Folder Servers (`/opt/local/etc/nginx/servers`).
* **Window Reopen:** Klik *"Open Control Center"* atau icon Dock membuka kembali jendela utama secara instan.

### ⌨️ Command Palette & Live Terminal Output Drawer
* **Command Palette (`Cmd + K`):** Quick-switcher global untuk berpindah tab atau mengeksekusi aksi sistem dengan cepat via keyboard.
* **Docked Terminal Drawer:** Konsol terminal bawah yang melakukan streaming stdout/stderr proses anak MacPorts secara asynchronous tanpa mengunci antarmuka, dilengkapi tombol pembatalan proses (⏹) dan pembersih log.

### 📦 Cara Build & Menjalankan Aplikasi

```bash
# 1. Kompilasi & buat paket .app release mandiri (ad-hoc signed) di folder build/
./build-app.sh

# 2. Atau kompilasi dan pasang langsung ke folder /Applications macOS
./build-app.sh --install

# 3. Jalankan aplikasi (dari folder build atau Applications)
open "build/MacPorts Control Center.app"
# atau: open -a "MacPorts Control Center"

# 4. Jalankan rangkaian unit test suite (42/42 tests passing)
TEST_RUNNER=1 /tmp/run-all-tests
```

### 🎨 Mengelola & Menyesuaikan Icon Aplikasi (AppIcon)

Aplikasi telah dilengkapi bundle metadata (`Resources/Info.plist`) dan icon bawaan (`Resources/AppIcon.icns`). Anda dapat mengganti icon aplikasi menggunakan gambar PNG desain Anda sendiri:

```bash
# 1. Konversi gambar PNG apa saja (disarankan 1024x1024) ke format macOS .icns
./scripts/generate_icon.sh /path/ke/gambar-logo.png

# 2. Kompilasi ulang bundel aplikasi dengan icon baru
./build-app.sh
```

*Script `generate_icon.sh` menggunakan utilitas bawaan macOS (`sips` dan `iconutil`) tanpa memerlukan dependensi pihak ketiga.*

---

## 🗂️ Struktur Dokumen di Folder Ini

| Berkas / Direktori | Deskripsi |
| :--- | :--- |
| 📄 [**`VIRTUAL_HOSTS_AND_DOMAINS_GUIDE.md`**](VIRTUAL_HOSTS_AND_DOMAINS_GUIDE.md) | **Panduan Virtual Host & Domain:** Tutorial profesional mengelola server blocks Nginx, port-based vs domain `*.test` (hosts & `dnsmasq`), SSL/HTTPS lokal via `mkcert`, dan template Laravel siap pakai. |
| 📄 [**`FRESH_INSTALL_GUIDE.md`**](FRESH_INSTALL_GUIDE.md) | **Panduan Setup Laravel dari Nol:** Tutorial komprehensif setup lingkungan Laravel di Mac baru/reinstall, manajemen multi-versi PHP (8.1 s/d 8.4+), isolasi concurrent FPM pools, manajemen MariaDB/MySQL, dan uninstaller bersih. |
| 📄 [`FINAL_MACPORTS_ENVIRONMENT_SETUP.md`](FINAL_MACPORTS_ENVIRONMENT_SETUP.md) | **Dokumentasi Utama:** Detail teknis stack yang saat ini aktif (PHP 8.3, Nginx, MariaDB, Composer, Node), port/socket, dan status layanan. |
| 📄 [`HANDOFF_MACPORTS_MIGRATION.md`](HANDOFF_MACPORTS_MIGRATION.md) | **Riwayat & Latar Belakang:** Catatan teknis migrasi dari FlyEnv dan Herd (alasan inkompatibilitas C++ SDK macOS Monterey, migrasi 24 database). |
| 📄 [**`AGENTS.md`**](AGENTS.md) | **Petunjuk & Aturan AI Agents:** Pedoman arsitektur, guardrails, konvensi hak akses file, dan perintah terminal untuk AI coding assistant. |
| 📁 [`Resources/`](Resources/) | **Resource Bundel macOS:** Berisi metadata aplikasi [`Resources/Info.plist`](Resources/Info.plist) dan berkas icon resmi [`Resources/AppIcon.icns`](Resources/AppIcon.icns). |
| 📁 [`scripts/`](scripts/) | **Koleksi Skrip Otomasi:** Berisi skrip shell yang digunakan selama proses migrasi serta utilitas developer ([`scripts/generate_icon.sh`](scripts/generate_icon.sh), `setup_webserver.sh`, `migrate_mariadb.sh`, `cleanup_herd_root.sh`, `cleanup_flyenv_root.sh`). |
| 📁 [`config_templates/`](config_templates/) | **Salinan Konfigurasi:** Template cadangan `nginx.conf`, `php.ini`, `php-fpm.conf`, `www.conf`, dan contoh blok vhost server. |

---

## 💻 Teknologi & Bahasa Pemrograman Repositori

Repositori ini dibangun dengan arsitektur mandiri (*zero-dependency build*) menggunakan kombinasi bahasa dan teknologi:

* 🐘 **PHP (Native 8.3):** Menjadi backend mini-router pada [`index.php`](index.php) untuk membaca file markdown secara aman dan menyajikannya ke viewer browser.
* ⚡ **JavaScript (ES6+) & Marked.js:** Parser Markdown sisi browser via CDN [`marked.js`](https://cdn.jsdelivr.net/npm/marked/marked.min.js) untuk rendering dinamis tanpa langkah build (*no build step*).
* 🎨 **HTML5 & CSS3:** Desain antarmuka *Dark Theme* modern (`#0f172a`), tata letak responsif Flexbox, typography Apple System Font, dan navigasi sidebar interaktif.
* 🐚 **Bash Shell (`.sh`):** Skrip shell POSIX di direktori [`scripts/`](scripts/) untuk otomasi sinkronisasi data MariaDB, setup konfigurasi Nginx/PHP, serta pembersihan background daemon.
* 📝 **GitHub Flavored Markdown (GFM):** Standar penulisan seluruh berkas dokumentasi (`*.md`).
* ⚙️ **Konfigurasi Server (Nginx Conf & INI):** Konfigurasi web server dan runtime di [`config_templates/`](config_templates/).

---

## 🚀 Cheatsheet Perintah CLI Cepat

Perintah alias berikut sudah terpasang permanen di `~/.zshrc`:

### 1. Kontrol MariaDB 10.11
```bash
db-start      # Menyalakan service MariaDB
db-stop       # Mematikan service MariaDB
db-status     # Memeriksa status proses mysqld
mysql -u root # Masuk ke CLI MariaDB via socket /tmp/mysql.sock
```

### 2. Kontrol Web Server (Nginx & PHP-FPM 8.3)
```bash
web-start     # Menyalakan PHP-FPM 8.3 dan Nginx
web-stop      # Mematikan Nginx dan PHP-FPM 8.3
web-restart   # Me-restart Nginx dan PHP-FPM 8.3
web-status    # Memeriksa status proses Nginx & PHP-FPM
```

### 3. Pemilihan Versi PHP
```bash
port select --list php           # Melihat versi PHP yang terpasang
sudo port select --set php php83 # Memilih PHP 8.3 sebagai default
```

### 4. Node.js & Composer
```bash
fnm list      # Melihat versi Node yang terpasang
composer -V   # Memeriksa versi Composer bawaan PHP 8.3
```

---

## 🌐 Akses Dashboard & Proyek Aktif

* **Dashboard Sistem:** [http://localhost/](http://localhost/)  
  Folder: `/Users/adijaya/Sites/localhost`  
  *Menampilkan status server, modul PHP aktif, dan daftar database.*
* **Proyek SiAkurat (PT SMT):** [http://localhost:8080/](http://localhost:8080/)  
  Folder: `/Users/adijaya/MyFiles/Projects/SiAkurat/laravel-siakurat-pt-smt/public`  
  *Tersambung ke database `db_siakurat_sifat` di MariaDB.*

---

## 🛠️ Panduan Menambah Proyek Laravel Baru

Folder `/opt/local/etc/nginx/servers/` memiliki izin akses user Anda (`adijaya:admin`), sehingga Anda dapat menambah project baru tanpa `sudo`:

1. Buat file baru di `/opt/local/etc/nginx/servers/<nama_proyek>.conf`:
   ```nginx
   server {
       listen 8081; # Pilih port yang belum digunakan (misal 8081, 8082, dst)
       server_name localhost 127.0.0.1;
       root /Users/adijaya/MyFiles/Projects/<folder_proyek>/public;

       index index.php index.html;
       charset utf-8;

       location / {
           try_files $uri $uri/ /index.php?$query_string;
       }

       location = /favicon.ico { access_log off; log_not_found off; }
       location = /robots.txt  { access_log off; log_not_found off; }

       error_page 404 /index.php;

       location ~ \.php$ {
           fastcgi_pass 127.0.0.1:9000;
           fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
           include fastcgi.conf;
       }

       location ~ /\.(?!well-known).* {
           deny all;
       }
   }
   ```
2. Uji sintaks Nginx:
   ```bash
   nginx -t
   ```
3. Restart web server:
   ```bash
   web-restart
   ```

---

## 📍 Peta Lokasi File & Direktori Penting

* **PHP 8.3 Config:** `/opt/local/etc/php83/php.ini`
* **PHP-FPM Config:** `/opt/local/etc/php83/php-fpm.d/www.conf`
* **Nginx Main Config:** `/opt/local/etc/nginx/nginx.conf`
* **Nginx Virtual Hosts:** `/opt/local/etc/nginx/servers/`
* **MariaDB Config:** `/opt/local/etc/mariadb-10.11/my.cnf`
* **MariaDB Data Files:** `/opt/local/var/db/mariadb-10.11/`
* **MariaDB Socket:** `/tmp/mysql.sock`
* **Web Server Logs:**
  - Nginx: `/opt/local/var/log/nginx/error.log` dan `access.log`
  - PHP-FPM: `/opt/local/var/log/php83/php-fpm.log`
