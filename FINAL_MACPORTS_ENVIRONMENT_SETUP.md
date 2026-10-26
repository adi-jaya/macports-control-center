# Dokumentasi Final: Lingkungan Web Development MacPorts

**Host:** macOS Monterey 12.7.6 (Build 21H1320) — Arsitektur **Intel x86_64**  
**Status:** Murni Mandiri (MacPorts Native Stack)  
**Terakhir Diperbarui:** 26 Oktober 2026  

---

## 1. Arsitektur & Spesifikasi Stack

| Komponen | Versi | Status | Port / Socket / Akses | Lokasi Konfigurasi |
| :--- | :--- | :---: | :--- | :--- |
| **PHP** | 8.3.36 | ✅ Aktif | CLI via `/opt/local/bin/php` | `/opt/local/etc/php83/php.ini` |
| **PHP-FPM** | 8.3.36 | ✅ Berjalan | `127.0.0.1:9000` (User: `adijaya:staff`) | `/opt/local/etc/php83/php-fpm.d/www.conf` |
| **Nginx** | 1.30.6 | ✅ Berjalan | Port `80` (HTTP), Port `8080` (Project) | `/opt/local/etc/nginx/nginx.conf`<br>`/opt/local/etc/nginx/servers/*.conf` |
| **MariaDB** | 10.11.19 | ✅ Berjalan | Port `3306`, Socket `/tmp/mysql.sock` | `/opt/local/etc/mariadb-10.11/my.cnf`<br>Data: `/opt/local/var/db/mariadb-10.11` |
| **Composer** | 2.8.12 | ✅ Aktif | `~/.local/bin/composer` | Menggunakan PHP 8.3 MacPorts |
| **Node.js / npm** | v24.22.1 / 11.19.1 | ✅ Aktif | Dikelola via `fnm` (MacPorts) | `eval "$(fnm env --use-on-cd)"` |

---

## 2. Virtual Hosts yang Sedang Aktif

1. **Dashboard Localhost:**
   - **URL:** `http://localhost/`
   - **Root Folder:** `/Users/adijaya/Sites/localhost`
   - **Fungsi:** Dashboard monitoring status server, versi PHP, 39 modul aktif, dan daftar 24 database MariaDB.
   - **Konfigurasi:** `/opt/local/etc/nginx/servers/default.conf`

2. **Proyek Laravel SiAkurat PT SMT:**
   - **URL:** `http://localhost:8080/` (otomatis redirect ke `/login`)
   - **Root Folder:** `/Users/adijaya/MyFiles/Projects/SiAkurat/laravel-siakurat-pt-smt/public`
   - **Database:** `db_siakurat_sifat` (MariaDB 10.11)
   - **Konfigurasi:** `/opt/local/etc/nginx/servers/siakurat.conf`

---

## 3. Perintah Kontrol Cepat (Tersedia di Terminal)

Seluruh alias berikut telah ditambahkan ke `~/.zshrc` dan dapat dipanggil kapan saja:

### A. Kontrol Database (MariaDB)
```bash
db-start      # Menyalakan MariaDB 10.11 daemon
db-stop       # Mematikan MariaDB 10.11 daemon
db-status     # Memeriksa apakah proses mysqld/mariadbd sedang aktif
```

### B. Kontrol Web Server (Nginx + PHP-FPM)
```bash
web-start     # Menyalakan PHP-FPM 8.3 dan Nginx
web-stop      # Mematikan Nginx dan PHP-FPM 8.3
web-restart   # Me-restart Nginx dan PHP-FPM 8.3
web-status    # Memeriksa status proses PHP-FPM dan Nginx
```

---

## 4. Cara Menambahkan Virtual Host Proyek Baru

Direktori konfigurasi `/opt/local/etc/nginx/servers/` dimiliki oleh user `adijaya:admin`, sehingga Anda dapat membuat dan mengedit file konfigurasi tanpa `sudo`:

1. Buat berkas baru, misalnya `/opt/local/etc/nginx/servers/namaproyek.conf`:
   ```nginx
   server {
       listen 8081; # atau gunakan server_name tertentu
       server_name localhost 127.0.0.1;
       root /Users/adijaya/MyFiles/Projects/.../public;

       index index.php index.html;
       charset utf-8;

       location / {
           try_files $uri $uri/ /index.php?$query_string;
       }

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
2. Jalankan `web-restart` atau `nginx -s reload`.

---

## 5. Pembersihan File Bekas FlyEnv (Opsional)

Setelah seluruh proyek terverifikasi normal, Anda dapat membebaskan ruang disk sebesar **~1.9 GB**:
```bash
# Hapus aplikasi FlyEnv dan foldernya:
rm -rf /Applications/FlyEnv.app ~/Library/FlyEnv
```
*(Catatan: Seluruh 24 database FlyEnv sudah disalin aman ke `/opt/local/var/db/mariadb-10.11`).*
