# 🌐 Panduan Komprehensif: Manajemen Virtual Host & Domain Lokal untuk Pengembang Laravel

Dokumen ini adalah panduan teknis profesional untuk mengelola **Virtual Host (Server Blocks)** dan **Domain Lokal (`*.test`)** di Web Server Nginx (MacPorts). Panduan ini dirancang khusus bagi Anda yang ingin mengonfigurasi, menambah, atau memodifikasi lingkungan kerja proyek Laravel dan PHP secara mandiri dengan standar industri.

---

## 📑 Daftar Isi

1. [Arsitektur Virtual Host Nginx di MacPorts](#1-arsitektur-virtual-host-nginx-di-macports)
2. [Strategi 1: Virtual Host Berbasis Port (Paling Sederhana)](#2-strategi-1-virtual-host-berbasis-port-paling-sederhana)
3. [Strategi 2: Virtual Host Berbasis Domain Lokal (`*.test`)](#3-strategi-2-virtual-host-berbasis-domain-lokal-test)
   - [Metode A: Manual melalui `/etc/hosts` (Tanpa Instalasi Tambahan)](#metode-a-manual-melalui-etchosts-tanpa-instalasi-tambahan)
   - [Metode B: Otomatis Wildcard via `dnsmasq` (Pengalaman Mirip Laravel Herd/Valet)](#metode-b-otomatis-wildcard-via-dnsmasq-pengalaman-mirip-laravel-herdvalet)
4. [Strategi 3: Menambahkan HTTPS / SSL Lokal dengan `mkcert`](#4-strategi-3-menambahkan-https--ssl-lokal-dengan-mkcert)
5. [Koleksi Template Virtual Host Siap Pakai](#5-koleksi-template-virtual-host-siap-pakai)
   - [Template A: Proyek Laravel Standar (Inertia, Livewire, Blade, API)](#template-a-proyek-laravel-standar-inertia-livewire-blade-api)
   - [Template B: Proyek Laravel dengan Versi PHP Tertentu (Multi-PHP FPM)](#template-b-proyek-laravel-dengan-versi-php-tertentu-multi-php-fpm)
   - [Template C: Single Page Application (SPA / Vue / React / Frontend)](#template-c-single-page-application-spa--vue--react--frontend)
6. [Workflow Kerja Cepat & Perintah Pengelolaan](#6-workflow-kerja-cepat--perintah-pengelolaan)
7. [Troubleshooting & Pemecahan Masalah Nginx](#7-troubleshooting--pemecahan-masalah-nginx)

---

## 1. Arsitektur Virtual Host Nginx di MacPorts

Pada setup MacPorts yang telah kita bangun, konfigurasi Nginx dibuat modular dan sangat ramah bagi developer:

* **Direktori Server Blocks:** `/opt/local/etc/nginx/servers/`
* **Kepemilikan Hak Akses:** Dimiliki langsung oleh user Anda (`adijaya:admin`).  
  > [!TIP]
  > Anda **TIDAK PERLU** menggunakan perintah `sudo` untuk membuat, mengedit, atau menghapus file konfigurasi virtual host di dalam folder `/opt/local/etc/nginx/servers/`.
* **Proses Pemuatan:** Konfigurasi induk `/opt/local/etc/nginx/nginx.conf` secara otomatis menyertakan seluruh berkas `.conf` di folder tersebut melalui directive:
  ```nginx
  include /opt/local/etc/nginx/servers/*.conf;
  ```

---

## 2. Strategi 1: Virtual Host Berbasis Port (Paling Sederhana)

Metode ini adalah cara paling cepat dan tidak memerlukan modifikasi berkas DNS atau `/etc/hosts`. Masing-masing proyek Laravel diberi nomor port yang berbeda.

### Contoh Alokasi Port:
* `http://localhost/` &rarr; Dashboard Monitoring Sistem
* `http://localhost:8080/` &rarr; Proyek SiAkurat (PT SMT)
* `http://localhost:8081/` &rarr; Proyek PortalSifast
* `http://localhost:8082/` &rarr; Proyek Basic Accounting System

### Langkah Konfigurasi:
1. Buat file baru di folder servers, misalnya:
   ```bash
   nano /opt/local/etc/nginx/servers/portalsifast.conf
   ```
2. Isi dengan konfigurasi:
   ```nginx
   server {
       listen 8081;
       server_name localhost 127.0.0.1;
       root /Users/adijaya/MyFiles/Projects/RSAisyiahSitiFatimahTulangan/PortalSifast/public;

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
3. Periksa sintaks dan restart Nginx:
   ```bash
   nginx -t && web-restart
   ```

---

## 3. Strategi 2: Virtual Host Berbasis Domain Lokal (`*.test`)

Jika Anda lebih menyukai URL profesional seperti **`http://siakurat.test`** atau **`http://portalsifast.test`** tanpa perlu mengingat nomor port:

> [!NOTE]
> Domain `.test` adalah TLD resmi yang dicadangkan oleh IETF (RFC 2606) khusus untuk lingkungan testing/development lokal, sehingga dijamin tidak akan pernah bentrok dengan domain publik di internet.

Pilih salah satu metode di bawah ini:

---

### Metode A: Manual melalui `/etc/hosts` (Tanpa Instalasi Tambahan)

Metode ini cocok jika Anda hanya mengelola beberapa proyek utama dan tidak ingin memasang service background tambahan.

#### 1. Tambahkan Domain ke File `/etc/hosts`
Buka `/etc/hosts` dengan editor teks:
```bash
sudo nano /etc/hosts
```
Tambahkan baris berikut di baris paling bawah:
```text
127.0.0.1 siakurat.test
127.0.0.1 portalsifast.test
127.0.0.1 accounting.test
```
Simpan (`Ctrl+O`, `Enter`) lalu keluar (`Ctrl+X`).

#### 2. Bersihkan Cache DNS macOS
```bash
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

#### 3. Buat Server Block Nginx pada Port 80
Buat konfigurasi di `/opt/local/etc/nginx/servers/siakurat.conf`:
```nginx
server {
    listen 80;
    server_name siakurat.test;
    root /Users/adijaya/MyFiles/Projects/SiAkurat/laravel-siakurat-pt-smt/public;

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
}
```
Muat ulang Nginx:
```bash
nginx -t && web-restart
```
Sekarang buka browser di: `http://siakurat.test/`.

---

### Metode B: Otomatis Wildcard via `dnsmasq` (Pengalaman Mirip Laravel Herd/Valet)

Jika Anda mengelola puluhan proyek dan ingin **seluruh domain berakhiran `.test` otomatis mengarah ke localhost tanpa perlu pernah mengedit `/etc/hosts` lagi**:

#### 1. Pasang `dnsmasq` via MacPorts:
```bash
sudo port install dnsmasq
```

#### 2. Konfigurasikan Resolver Wildcard:
Buat folder konfigurasi jika belum ada:
```bash
sudo mkdir -p /opt/local/etc/dnsmasq.d
echo 'address=/.test/127.0.0.1' | sudo tee /opt/local/etc/dnsmasq.conf
```

#### 3. Daftarkan Resolver macOS untuk Domain `.test`:
macOS memiliki fitur resolver bawaan di `/etc/resolver/`:
```bash
sudo mkdir -p /etc/resolver
sudo tee /etc/resolver/test << 'EOF'
nameserver 127.0.0.1
EOF
```

#### 4. Nyalakan Service `dnsmasq`:
```bash
sudo port load dnsmasq
```

#### 5. Uji Coba:
Ketik di Terminal:
```bash
ping -c 1 apasaja.test
```
Hasilnya akan langsung merespons ke `127.0.0.1`!  
Kini setiap kali Anda membuat proyek baru, cukup pasang `server_name namaproyek.test;` di file konfigurasi Nginx tanpa sentuh file `/etc/hosts`.

---

## 4. Strategi 3: Menambahkan HTTPS / SSL Lokal dengan `mkcert`

Banyak fitur modern seperti otentikasi Google OAuth, payment gateway (Midtrans/Xendit callback), secure session cookie (`SameSite=None; Secure`), atau Service Worker PWA yang mewajibkan protokol **HTTPS**.

Anda bisa membuat sertifikat SSL lokal gratis yang **dipercaya 100% oleh macOS Keychain dan browser (gembok hijau tanpa peringatan keamanan)** menggunakan **`mkcert`**.

### 1. Pasang `mkcert` via MacPorts:
```bash
sudo port install mkcert
```

### 2. Pasang Root CA Lokal ke Sistem macOS:
```bash
mkcert -install
```

### 3. Buat Sertifikat SSL untuk Domain Proyek Anda:
Misalnya Anda ingin membuat sertifikat untuk `siakurat.test`:
```bash
mkdir -p /opt/local/etc/nginx/ssl
cd /opt/local/etc/nginx/ssl
mkcert siakurat.test "*.siakurat.test" localhost 127.0.0.1
```
Perintah ini akan menghasilkan dua berkas:
- `siakurat.test+3.pem` (Sertifikat publik)
- `siakurat.test+3-key.pem` (Kunci privat)

### 4. Pasang ke Blok Server Nginx:
```nginx
server {
    listen 80;
    server_name siakurat.test;
    # Otomatis redirect HTTP ke HTTPS
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name siakurat.test;
    root /Users/adijaya/MyFiles/Projects/SiAkurat/laravel-siakurat-pt-smt/public;

    # SSL Certificate
    ssl_certificate /opt/local/etc/nginx/ssl/siakurat.test+3.pem;
    ssl_certificate_key /opt/local/etc/nginx/ssl/siakurat.test+3-key.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

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
}
```
Muat ulang Nginx (`web-restart`). Kini `https://siakurat.test/` aktif dengan gembok hijau valid!

---

## 5. Koleksi Template Virtual Host Siap Pakai

Simpan template-template ini di `/opt/local/etc/nginx/servers/<nama_proyek>.conf`.

### Template A: Proyek Laravel Standar (Inertia, Livewire, Blade, API)

```nginx
server {
    listen 80;
    server_name namaproyek.test; # Atau ganti dengan listen 808X;
    root /Users/adijaya/MyFiles/Projects/PathToProject/public;

    # Keamanan Header
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    index index.php index.html;
    charset utf-8;

    # Laravel Front Controller Routing
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    # FastCGI Handler untuk PHP 8.3
    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi.conf;

        # Optimasi Buffer untuk Response Laravel yang besar
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
    }

    # Blokir akses ke file .env, .git, .editorconfig, dll.
    location ~ /\.(?!well-known).* {
        deny all;
    }
}
```

---

### Template B: Proyek Laravel dengan Versi PHP Tertentu (Multi-PHP FPM)

Jika Anda memiliki proyek lama (misal: Laravel 9 atau Laravel 10) yang membutuhkan **PHP 8.2**, sementara default sistem Anda adalah PHP 8.3:

```nginx
server {
    listen 80;
    server_name legacy-laravel.test;
    root /Users/adijaya/MyFiles/Projects/LegacyProject/public;

    index index.php index.html;
    charset utf-8;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        # Arahkan ke pool PHP 8.2 (Port 9082):
        fastcgi_pass 127.0.0.1:9082;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi.conf;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
```

---

### Template C: Single Page Application (SPA / Vue / React / Frontend)

Jika Anda memiliki proyek frontend terpisah (misalnya build hasil `npm run build` dari Vue, React, atau Next.js static export):

```nginx
server {
    listen 80;
    server_name app-frontend.test;
    root /Users/adijaya/MyFiles/Projects/FrontendApp/dist;

    index index.html;

    location / {
        # SPA Fallback ke index.html agar routing Vue/React Router berfungsi
        try_files $uri $uri/ /index.html;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires max;
        log_not_found off;
    }
}
```

---

## 6. Workflow Kerja Cepat & Perintah Pengelolaan

Sebagai developer, Anda dapat menerapkan rutinitas kerja berikut saat membuat proyek baru:

```bash
# 1. Masuk ke folder servers Nginx
cd /opt/local/etc/nginx/servers

# 2. Salin template yang ada
cp default.conf project-baru.conf

# 3. Edit root path dan server_name sesuai proyek baru
nano project-baru.conf

# 4. Uji apakah ada kesalahan sintaks
nginx -t

# 5. Reload Nginx (pilih salah satu cara)
web-restart              # Menggunakan alias zshrc
# atau
sudo port reload nginx   # Menggunakan reload native
```

---

## 7. Troubleshooting & Pemecahan Masalah Nginx

### Masalah 1: 502 Bad Gateway
* **Penyebab:** Nginx tidak dapat menghubungi PHP-FPM pada `127.0.0.1:9000` (atau port FPM yang ditentukan).
* **Solusi:**
  1. Periksa apakah PHP-FPM aktif:
     ```bash
     ps aux | grep php-fpm
     ```
  2. Jika mati, nyalakan kembali:
     ```bash
     sudo port load php83-fpm
     ```

### Masalah 2: 403 Forbidden
* **Penyebab:** Nginx tidak memiliki izin baca pada folder proyek atau direktori `index.php` tidak ditemukan.
* **Solusi:**
  1. Pastikan `root` mengarah ke folder **`public`** (bukan root folder proyek).
  2. Pastikan file `index.php` ada di dalam folder `public/`.
  3. Pastikan direktori parent memiliki hak execute (`chmod +x`):
     ```bash
     chmod +x /Users/adijaya /Users/adijaya/MyFiles /Users/adijaya/MyFiles/Projects
     ```

### Masalah 3: 404 Not Found pada Route Laravel (kecuali halaman home `/`)
* **Penyebab:** Directive `try_files` belum terpasang atau salah tulis.
* **Solusi:** Pastikan blok `location /` di Nginx memuat baris:
  ```nginx
  location / {
      try_files $uri $uri/ /index.php?$query_string;
  }
  ```

### Masalah 4: 413 Request Entity Too Large
* **Penyebab:** Ukuran upload file di formulir Laravel melebihi batas default Nginx (1 MB).
* **Solusi:** Tambahkan `client_max_body_size 64M;` di dalam blok `server {}` atau `http {}`.
