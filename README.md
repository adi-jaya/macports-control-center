# 📚 Pusat Dokumentasi Lingkungan Web Development (MacPorts)

[![GitHub Pages](https://img.shields.io/badge/Live_Site-GitHub_Pages-38bdf8?style=flat&logo=github)](https://adi-jaya.github.io/macports-webdev-setup/)
[![GitHub Repository](https://img.shields.io/badge/GitHub-adi--jaya%2Fmacports--webdev--setup-181717?style=flat&logo=github)](https://github.com/adi-jaya/macports-webdev-setup)

Selamat datang di direktori dokumentasi terpusat untuk lingkungan web development native berbasis **MacPorts** pada **macOS Monterey 12.7.6 (Intel x86_64)**. Halaman dokumentasi online dapat diakses langsung di [**adi-jaya.github.io/macports-webdev-setup**](https://adi-jaya.github.io/macports-webdev-setup/).

Folder ini menyimpan seluruh panduan, catatan riwayat migrasi, konfigurasi sistem, dan template virtual host agar mudah dirujuk kembali kapan saja.

---

## 🗂️ Struktur Dokumen di Folder Ini

| Berkas / Direktori | Deskripsi |
| :--- | :--- |
| 📄 [`FINAL_MACPORTS_ENVIRONMENT_SETUP.md`](FINAL_MACPORTS_ENVIRONMENT_SETUP.md) | **Dokumentasi Utama:** Detail teknis stack yang saat ini aktif (PHP 8.3, Nginx, MariaDB, Composer, Node), port/socket, dan status layanan. |
| 📄 [`HANDOFF_MACPORTS_MIGRATION.md`](HANDOFF_MACPORTS_MIGRATION.md) | **Riwayat & Latar Belakang:** Catatan teknis migrasi dari FlyEnv dan Herd (alasan inkompatibilitas C++ SDK macOS Monterey, migrasi 24 database). |
| 📁 [`scripts/`](scripts/) | **Koleksi Skrip Otomasi:** Berisi skrip shell yang digunakan selama proses migrasi (`setup_webserver.sh`, `migrate_mariadb.sh`, `cleanup_herd_root.sh`). |
| 📁 [`config_templates/`](config_templates/) | **Salinan Konfigurasi:** Template cadangan `nginx.conf`, `php.ini`, `php-fpm.conf`, `www.conf`, dan contoh blok vhost server. |

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
