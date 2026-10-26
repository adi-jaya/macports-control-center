#!/bin/bash
set -e

export PATH="/opt/local/bin:/opt/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
TARGET_USER="${SUDO_USER:-$USER}"

echo "=========================================================="
echo "   SETUP & AKTIVASI NGINX + PHP-FPM 8.3 (MACPORTS)"
echo "=========================================================="

# 1. Hentikan service lama jika berjalan
echo ">> Menghentikan service web server jika sedang aktif..."
port unload nginx 2>/dev/null || true
port unload php83-fpm 2>/dev/null || true
pkill -f nginx 2>/dev/null || true
pkill -f php-fpm83 2>/dev/null || true
sleep 1

# 2. Buat folder yang diperlukan
echo ">> Mempersiapkan direktori konfigurasi & log..."
mkdir -p /opt/local/etc/php83/php-fpm.d
mkdir -p /opt/local/etc/nginx/servers
mkdir -p /opt/local/var/log/nginx
mkdir -p /opt/local/var/run/nginx
mkdir -p /opt/local/var/log/php83
mkdir -p /opt/local/var/run/php83

# 3. Salin file konfigurasi yang sudah disiapkan
echo ">> Menyalin konfigurasi PHP 8.3 & PHP-FPM..."
cp /Users/adijaya/macports_config/php.ini /opt/local/etc/php83/php.ini
cp /Users/adijaya/macports_config/php-fpm.conf /opt/local/etc/php83/php-fpm.conf
cp /Users/adijaya/macports_config/www.conf /opt/local/etc/php83/php-fpm.d/www.conf

echo ">> Menyalin konfigurasi Nginx..."
cp /Users/adijaya/macports_config/nginx.conf /opt/local/etc/nginx/nginx.conf
cp /Users/adijaya/macports_config/servers/default.conf /opt/local/etc/nginx/servers/default.conf
cp /Users/adijaya/macports_config/servers/siakurat.conf /opt/local/etc/nginx/servers/siakurat.conf

# 4. Tetapkan hak kepemilikan folder konfigurasi ke user lokal agar mudah di-edit
echo ">> Menetapkan hak akses direktori konfigurasi ke user '$TARGET_USER:admin'..."
chown -R "$TARGET_USER:admin" /opt/local/etc/php83 /opt/local/etc/nginx
chown -R "$TARGET_USER:admin" /opt/local/var/log/nginx /opt/local/var/run/nginx
chown -R "$TARGET_USER:admin" /opt/local/var/log/php83 /opt/local/var/run/php83

# 5. Uji sintaks konfigurasi
echo ">> Memeriksa sintaks PHP-FPM..."
/opt/local/sbin/php-fpm83 -t

echo ">> Memeriksa sintaks Nginx..."
/opt/local/sbin/nginx -t

# 6. Nyalakan layanan via MacPorts launchd
echo ">> Menyalakan layanan PHP-FPM 8.3..."
port load php83-fpm
sleep 1

echo ">> Menyalakan layanan Nginx..."
port load nginx
sleep 2

echo "=========================================================="
echo ">> Status proses yang berjalan:"
ps aux | grep -E '[p]hp-fpm83|[n]ginx' || true
echo "=========================================================="
echo "✅ Nginx dan PHP-FPM 8.3 berhasil dikonfigurasi & dijalankan!"
