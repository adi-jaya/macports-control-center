# Handoff Dokumen: Migrasi Lingkungan Web Development ke MacPorts

**Tanggal & Waktu:** 26 Oktober 2026  
**Target Lingkungan:** Murni MacPorts (Standalone Web Development Environment)  
**Host Machine:** macOS Monterey 12.7.6 (Build 21H1320) — Arsitektur **Intel x86_64**  

---

## 1. Konteks & Latar Belakang

1. **Mengapa Meninggalkan FlyEnv?**  
   FlyEnv sering menimpa `$PATH` sistem, memiliki masalah socket MySQL, dan tidak lagi diinginkan oleh user. User ingin beralih ke stack standar yang dikelola oleh MacPorts.
2. **Mengapa Tidak Menggunakan Laravel Herd?**  
   Binary PHP bawaan Laravel Herd (PHP 8.2, 8.3, 8.4) dikompilasi dengan SDK macOS 15+ (`minos 15.0`) yang membutuhkan simbol `__ZNSt3__122__libcpp_verbose_abortEPKcz` di `libc++`. Simbol ini tidak ada di macOS Monterey 12.7.6 (Bug resmi Herd Community #1600). Karena tidak kompatibel secara native, Herd telah **di-uninstall dan dibersihkan total**.
3. **Keputusan Akhir:**  
   Membangun dan mengelola seluruh service web development (PHP, Web Server, Database, Node, Composer) secara lokal menggunakan **MacPorts**.

---

## 2. Status Saat Ini (Apa yang SUDAH Selesai)

| Komponen | Status | Detail Lokasi / Konfigurasi |
| :--- | :---: | :--- |
| **MariaDB 10.11** | ✅ **Selesai & Berjalan** | - Service MacPorts: `/opt/local/lib/mariadb-10.11/bin/mysqld` (user `_mysql`)<br>- Datadir: `/opt/local/var/db/mariadb-10.11`<br>- **Seluruh 24 database FlyEnv telah dimigrasikan** (termasuk `db_siakurat_sifat`, `sik`, `basic_accounting_system`, dll.)<br>- Port: `3306`, Socket: `/tmp/mysql.sock`<br>- Konfigurasi: `/opt/local/etc/mariadb-10.11/my.cnf`<br>- CLI: `/opt/local/bin/mysql` dan symlink `~/.local/bin/mariadb` |
| **MariaDB Control** | ✅ **Selesai** | Tersedia alias di `~/.zshrc`: `db-start`, `db-stop`, `db-status` |
| **Composer** | ✅ **Selesai** | Terpasang mandiri di `~/.local/bin/composer` (v2.8.12) |
| **Node.js & npm** | ✅ **Selesai** | Dikelola via `fnm` (MacPorts). Node `v24.22.1` dan `npm 11.19.1` aktif di `~/.zshrc` |
| **Java** | ✅ **Selesai** | Liberica JDK 11 via `JAVA_HOME` di `~/.zshrc` |
| **Pembersihan `~/.zshrc`**| ✅ **Selesai** | Jejak FlyEnv dan Herd telah dihapus total. File `~/.zshrc` bersih dan memprioritaskan `/opt/local/bin` |
| **Pembersihan Herd** | ✅ **Selesai** | `Herd.app`, `~/Library/Application Support/Herd`, config, dan helper daemon root telah dihapus total |

---

## 3. Apa yang BELUM Disiapkan (Hal yang Perlu Dikerjakan di Session Baru)

### A. Versi PHP Produksi (`php83` / `php82`)
* **Masalah:** Saat ini paket yang terpasang di MacPorts adalah `php85` (PHP 8.5.12). PHP 8.5 merupakan versi rilis masa depan/eksperimental yang belum didukung oleh banyak dependensi Composer dan framework Laravel saat ini.
* **Kebutuhan:** Perlu memasang versi stabil seperti **`php83`** (atau `php82`) beserta ekstensinya:
  ```bash
  sudo port install php83 php83-fpm php83-mysql php83-openssl php83-curl \
                    php83-mbstring php83-zip php83-gd php83-intl php83-sqlite
  sudo port select --set php php83
  ```

### B. Web Server (Nginx atau Apache2)
* **Masalah:** Saat ini belum ada web server yang terpasang di MacPorts (sebelumnya web server bergantung pada FlyEnv / Herd).
* **Pilihan:**
  1. **Nginx + PHP-FPM (Disarankan untuk Laravel / serupa dengan Herd/Valet):**
     - Pasang `nginx` via MacPorts (`sudo port install nginx`).
     - Konfigurasikan `fastcgi_pass` ke socket PHP-FPM (`/opt/local/var/run/php83-fpm.sock`).
  2. **Apache2 (`sudo port install apache2`):**
     - Bisa menggunakan `mod_fastcgi` / `eventmpm` atau handler standar.

### C. Resolusi Domain Lokal (Opsional / *Nice-to-have*)
* Jika ingin kemudahan domain `*.test` seperti di Herd/Valet:
  - Pasang `dnsmasq` via MacPorts (`sudo port install dnsmasq`).
  - Arahkan resolver macOS di `/etc/resolver/test` ke `127.0.0.1`.
* Jika tidak membutuhkan `*.test`, cukup gunakan VirtualHost standar (`/etc/hosts`) atau `php artisan serve`.

### D. Pengarsipan / Penghapusan Sisa File FlyEnv Fisik di Disk
* Database sudah aman di MacPorts. Folder `~/Library/FlyEnv` dan `/Applications/FlyEnv.app` masih memakan ruang disk dan siap diarsip atau dihapus permanen:
  ```bash
  # Backup opsional:
  mv ~/Library/FlyEnv ~/Library/FlyEnv.bak
  # Atau hapus langsung:
  rm -rf /Applications/FlyEnv.app ~/Library/FlyEnv
  ```

---

## 4. Rekomendasi Urutan Kerja untuk Agent Session Baru

1. **Langkah 1 (PHP Stabil):** Pasang `php83` beserta ekstensi pentingnya via MacPorts, lalu aktifkan via `port select --set php php83`.
2. **Langkah 2 (Web Server):** Pasang dan konfigurasikan `nginx` + `php83-fpm`.
3. **Langkah 3 (Verifikasi Koneksi Proyek):** Uji coba menjalankan salah satu proyek Laravel user ke MariaDB MacPorts (`localhost` / `127.0.0.1:3306`).
4. **Langkah 4 (Housekeeping):** Hapus sisa direktori fisik FlyEnv di disk setelah proyek terverifikasi berjalan lancar.
