# 🤖 AGENTS.md — Panduan Arsitektur, Tech Stack & Operasional untuk AI Coding Agents

Pusat instruksi resmi untuk AI Coding Agent (Antigravity, Claude Code, OpenAI Codex, Cursor, Windsurf, Copilot, dll.) yang bekerja di repositori [`MacPorts_Docs`](file:///Users/adijaya/Documents/MacPorts_Docs) maupun pada lingkungan host macOS ini.

---

## 1. Mental Model: Peran Repositori

Repositori ini menjalankan dua peran saling terikat:
1. **Live Knowledge Base:** Dokumentasi web development lokal yang disajikan langsung ke browser melalui symlink:
   ```text
   /Users/adijaya/Sites/localhost/docs  ──(symlink)──>  /Users/adijaya/Documents/MacPorts_Docs
   ```
   Akses browser lokal: [http://localhost/docs/](http://localhost/docs/) (dinamis via [`index.php`](file:///Users/adijaya/Documents/MacPorts_Docs/index.php)).
2. **Configuration Source of Truth:** Template konfigurasi referensi ([`config_templates/`](file:///Users/adijaya/Documents/MacPorts_Docs/config_templates)) dan skrip pemulihan/otomasi ([`scripts/`](file:///Users/adijaya/Documents/MacPorts_Docs/scripts)) untuk seluruh stack web dev host (Laravel, PHP, Nginx, MariaDB).
3. **Remote Sinkron:** GitHub publik [**adi-jaya/macports-webdev-setup**](https://github.com/adi-jaya/macports-webdev-setup) pada branch `main`.

---

## 2. Teknologi & Bahasa Pemrograman Repositori Ini

Repositori dokumentasi ini dibangun dengan pendekatan *zero-dependency build* (tanpa Node bundler atau composer vendor) menggunakan kombinasi bahasa dan teknologi berikut:

| Lapisan / Komponen | Bahasa & Teknologi | Lokasi Berkas | Peran & Detail Implementasi |
| :--- | :--- | :--- | :--- |
| **Backend Web Viewer** | **PHP** (Native 8.3+) | [`index.php`](file:///Users/adijaya/Documents/MacPorts_Docs/index.php) | Mini-controller mandiri tanpa framework. Menangani routing `?file=`, sanitasi input, membaca markdown via `file_get_contents`, dan menyajikan konten ke frontend dalam format JSON. |
| **Frontend Markdown Parser** | **JavaScript (ES6+)** | [`index.php`](file:///Users/adijaya/Documents/MacPorts_Docs/index.php) | Parsing Markdown ke elemen DOM secara dinamis di browser menggunakan CDN [`marked.js`](https://cdn.jsdelivr.net/npm/marked/marked.min.js) (*no build step*). |
| **Styling & Antarmuka** | **HTML5 & CSS3** | [`index.php`](file:///Users/adijaya/Documents/MacPorts_Docs/index.php) | Tata letak Flexbox modern dengan *Dark Theme* (`#0f172a`, `#1e293b`, `#38bdf8`), tipografi Apple System Font, styling tabel Markdown, dan navigasi sidebar interaktif. |
| **Skrip Otomasi Sistem** | **POSIX Bash Shell** | [`scripts/*.sh`](file:///Users/adijaya/Documents/MacPorts_Docs/scripts) | Skrip shell (`#!/bin/bash` dengan `set -e`) untuk sinkronisasi database (`rsync`), konfigurasi direktori sistem (`chown`/`chmod`), dan manajemen launch daemon (`launchctl`). |
| **Format Dokumentasi** | **Markdown (GFM)** | `*.md` | Menggunakan GitHub Flavored Markdown (tabel, badge, blockquotes, syntax highlighting) yang dirender serentak di GitHub dan web viewer lokal. |
| **Konfigurasi Server** | **Nginx Conf & INI** | [`config_templates/`](file:///Users/adijaya/Documents/MacPorts_Docs/config_templates) | Sintaks konfigurasi server block Nginx (`.conf`), runtime PHP (`php.ini`), dan pool PHP-FPM (`www.conf`). |
| **Version Control** | **Git** | `.git/`, `.gitignore` | Pelacakan versi dan sinkronisasi ke remote GitHub `origin/main`. |

---

## 3. Peta Arsitektur Host & Runtime Aktif

Mesin host: **macOS Monterey 12.7.6 (Build 21H1320) — Arsitektur Intel x86_64**.

### A. Komponen Layanan Aktif (*Live Runtime*)
| Komponen | Versi | Status | Port / Socket / Jalur | File Konfigurasi Aktif di Sistem |
| :--- | :--- | :---: | :--- | :--- |
| **Nginx** | 1.30.6 | ✅ Berjalan | Port `80` (Dashboard), Port `8080+` (Proyek) | `/opt/local/etc/nginx/nginx.conf`<br>Vhosts: `/opt/local/etc/nginx/servers/*.conf` |
| **PHP CLI** | 8.3.36 | ✅ Aktif | `/opt/local/bin/php` | `/opt/local/etc/php83/php.ini` |
| **PHP-FPM** | 8.3.36 | ✅ Berjalan | `127.0.0.1:9000` (User: `adijaya:staff`) | `/opt/local/etc/php83/php-fpm.d/www.conf` |
| **MariaDB** | 10.11.19 | ✅ Berjalan | Port `3306`, Socket `/tmp/mysql.sock` | `/opt/local/etc/mariadb-10.11/my.cnf`<br>Data: `/opt/local/var/db/mariadb-10.11` (24 DB) |
| **Composer** | 2.8.12 | ✅ Aktif | `~/.local/bin/composer` | Menggunakan PHP 8.3 MacPorts |
| **Node.js** | v24.22.1 | ✅ Aktif | Dikelola via `fnm` (MacPorts) | Shell alias di `~/.zshrc` |

### B. Konvensi Lingkungan Kritis (*Unwritten Environment Conventions*)
- **Direktori Server Blocks Nginx (`/opt/local/etc/nginx/servers/`):** Dimiliki oleh `adijaya:admin`. Tulis dan edit berkas vhost langsung **tanpa `sudo`**.
- **PHP-FPM Worker User:** Wajib dikonfigurasi sebagai `user = adijaya` dan `group = staff`. Konfigurasi ini menjamin berkas `storage/` dan `bootstrap/cache` Laravel dapat ditulis serentak oleh web server dan CLI tanpa konflik hak akses.
- **Sudoers MacPorts:** User `adijaya` memiliki hak passwordless sudo untuk perintah MacPorts melalui file `/etc/sudoers.d/macports` (`NOPASSWD: /opt/local/bin/port`).
- **Alasan Larangan Laravel Herd:** Binary PHP Herd membutuhkan SDK macOS 15+ (`minos 15.0`) dan memanggil simbol C++ `__ZNSt3__122__libcpp_verbose_abortEPKcz` yang absen di macOS Monterey (Herd Bug #1600). Herd menyebabkan *instant crash* dan telah dibersihkan total.

---

## 4. Context Pointers (Progressive Disclosure)

Konsultasikan dokumen berikut hanya saat pemicu (*trigger*) yang relevan aktif:

| Berkas / Direktori | Trigger Pemicu Konsultasi | Cakupan Material |
| :--- | :--- | :--- |
| [`VIRTUAL_HOSTS_AND_DOMAINS_GUIDE.md`](file:///Users/adijaya/Documents/MacPorts_Docs/VIRTUAL_HOSTS_AND_DOMAINS_GUIDE.md) | **Setup Vhost / Domain / SSL:** Saat membuat server block baru, domain `*.test` (`/etc/hosts` atau `dnsmasq`), atau HTTPS lokal via `mkcert`. | Panduan vhost port-based, config dnsmasq, sertifikat SSL lokal, dan template server Laravel/SPA. |
| [`FRESH_INSTALL_GUIDE.md`](file:///Users/adijaya/Documents/MacPorts_Docs/FRESH_INSTALL_GUIDE.md) | **Reinstall / Multi-PHP Pools / Database:** Saat setup Mac baru dari nol, menjalankan concurrent multi-PHP FPM (8.1 s/d 8.4), atau konfigurasi database MariaDB/MySQL. | Rumus paket MacPorts, alokasi port multi-FPM (9081, 9082, 9083), inisialisasi MariaDB, dan uninstaller bersih. |
| [`FINAL_MACPORTS_ENVIRONMENT_SETUP.md`](file:///Users/adijaya/Documents/MacPorts_Docs/FINAL_MACPORTS_ENVIRONMENT_SETUP.md) | **Audit Snapshot Host:** Saat memverifikasi versi komponen aktif, alokasi port default, atau riwayat database terpasang. | Status teruji: PHP 8.3.36, Nginx 1.30.6, MariaDB 10.11.19, Composer 2.8.12, Node v24 via fnm. |
| [`HANDOFF_MACPORTS_MIGRATION.md`](file:///Users/adijaya/Documents/MacPorts_Docs/HANDOFF_MACPORTS_MIGRATION.md) | **Riset Historis Keputusan:** Saat membutuhkan latar belakang mengapa FlyEnv atau Herd ditinggalkan. | Catatan bug SDK macOS 15+ libcpp pada Herd (Issue #1600) dan migrasi 24 database FlyEnv. |
| [`config_templates/`](file:///Users/adijaya/Documents/MacPorts_Docs/config_templates) | **Sinkronisasi Konfigurasi Acuan:** Saat memperbarui template standar `nginx.conf`, `php.ini`, atau `www.conf`. | Salinan acuan (BUKAN file aktif runtime sistem di `/opt/local/etc/`). |
| [`scripts/`](file:///Users/adijaya/Documents/MacPorts_Docs/scripts) | **Eksekusi Otomasi Host:** Saat setup webserver awal atau migrasi fisik MariaDB. | Skrip Bash POSIX: `setup_webserver.sh`, `migrate_mariadb.sh`, `cleanup_herd_root.sh`, `cleanup_flyenv_root.sh`. |

---

## 5. Standard Operating Procedures (SOP) dengan Completion Criteria

### 📋 SOP 1: Penambahan Dokumen Baru ke Repositori
1. Tulis berkas Markdown baru di root: `/Users/adijaya/Documents/MacPorts_Docs/<NAMA_FILE>.md`.
2. Buka [`index.php`](file:///Users/adijaya/Documents/MacPorts_Docs/index.php), daftarkan nama berkas dan labelnya ke dalam array `$files`.
3. Tambahkan baris tautan pada tabel di [`README.md`](file:///Users/adijaya/Documents/MacPorts_Docs/README.md) dan tabel Bagian 4 di dokumen ini.
4. **Completion Criterion:**
   - Jalankan: `curl -sI "http://localhost/docs/?file=<NAMA_FILE>.md"`
   - Baris status wajib menampilkan `HTTP/1.1 200 OK`.

### 📋 SOP 2: Penambahan Virtual Host Proyek Laravel Baru
1. Deteksi port yang telah terpakai:
   ```bash
   grep -rn "listen" /opt/local/etc/nginx/servers/
   ```
   Pilih port integer berikutnya yang belum terpakai (misal `8081`, `8082`, dst.).
2. Buat berkas baru **tanpa `sudo`** di `/opt/local/etc/nginx/servers/<nama_proyek>.conf`:
   ```nginx
   server {
       listen 808X;
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
3. Uji sintaks:
   ```bash
   nginx -t
   ```
   Wajib menghasilkan keluaran: `nginx: configuration file /opt/local/etc/nginx/nginx.conf test is successful`.
4. Muat ulang server: `web-restart` (atau `sudo port reload nginx`).
5. **Completion Criterion:**
   - Jalankan: `curl -sI http://localhost:808X/`
   - Baris status wajib menampilkan `HTTP/1.1 200 OK` atau `HTTP/1.1 302 Found`.

### 📋 SOP 3: Diagnosa Layanan Host (Troubleshooting)
1. **Web Server Down:**
   - Jalankan `web-status` atau `ps aux | grep -E '[p]hp-fpm|[n]ginx'`.
   - Inspeksi log: `/opt/local/var/log/nginx/error.log` dan `/opt/local/var/log/php83/php-fpm.log`.
   - Nyalakan ulang: `web-restart`.
2. **Database Down:**
   - Jalankan `db-status`. Periksa keberadaan socket `/tmp/mysql.sock`.
   - Inspeksi log: `/opt/local/var/db/mariadb-10.11/*.err`.
   - Nyalakan: `db-start`.
3. **Laravel Permission Denied:**
   - Periksa `/opt/local/etc/php83/php-fpm.d/www.conf`: pastikan `user = adijaya` dan `group = staff`.
   - Periksa direktori proyek: pastikan kepemilikan adalah `adijaya:staff`. Jangan jalankan `chmod -R 777`.

---

## 6. Positive Guardrails & Target Actions

Terapkan target tindakan berikut pada setiap operasi:

| Target Tindakan (*What to Do*) | Batasan Ketat (*What NOT to Do*) | Rasional Arsitektur |
| :--- | :--- | :--- |
| **Pertahankan user PHP-FPM:** Pastikan `user = adijaya` & `group = staff` di `/opt/local/etc/php*/php-fpm.d/www.conf`. | Jangan ubah menjadi `nobody` atau `_www`. | Meniadakan isu hak akses file pada folder `storage/` dan `bootstrap/cache` Laravel. |
| **Gunakan hak user biasa:** Buat file di `/opt/local/etc/nginx/servers/` langsung sebagai `adijaya`. | Jangan gunakan `sudo` saat membuat file vhost. | Folder dimiliki `adijaya:admin`. Sudo akan mengubah ownership ke `root` dan mengunci akses edit. |
| **Verifikasi sintaks terlebih dahulu:** Jalankan `nginx -t` sebelum me-reload atau me-restart. | Jangan eksekusi `web-restart` jika `nginx -t` gagal. | Mencegah downtime web server akibat kesalahan ketik konfigurasi. |
| **Gunakan paket native MacPorts:** Jalankan CLI dan layanan dari `/opt/local/bin/*`. | Jangan sarankan Docker untuk dev harian atau install Laravel Herd. | Docker berat di CPU/RAM Intel Mac; Laravel Herd crash pada Monterey karena simbol C++ SDK macOS 15+ (Bug #1600). |
| **Amankan data database:** Buat backup data sebelum menjalankan skrip modifikasi database. | Jangan jalankan `migrate_mariadb.sh` tanpa instruksi eksplisit user. | Mencegah penimpaan atau korupsi fisik pada 24 database terdaftar. |

---

## 7. Efisiensi Token, Git, dan Estimasi Nilai

- **Token Optimization (RTK):** Gunakan utilitas proxy `rtk` (Rust Token Killer) untuk mengeksekusi operasi dev dan perintah terminal guna menghemat token konteks hingga 60-90%.
- **Git Audit Rules:**
  - Audit seluruh cabang aktif: `git log --all --no-merges`
  - Verifikasi perubahan kode nyata: `git show --stat <commit_hash>`
- **Value-Based Billing:**
  - Tanyakan baseline nilai proyek terlebih dahulu sebelum menaksir biaya atau Man-Days fitur baru.
  - Terapkan harga berbasis nilai yang dihantarkan (*Value-Based Pricing*), bukan jam kerja manual mentah.
