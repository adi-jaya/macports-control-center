#!/bin/bash
set -e

FLYENV_DATA="$HOME/Library/FlyEnv/server/mariadb/data-10.11"
MACPORTS_DATA="/opt/local/var/db/mariadb-10.11"
BACKUP_DATA="/opt/local/var/db/mariadb-10.11.bak.$(date +%Y%m%d%H%M%S)"

echo "=========================================================="
echo "   MIGRASI DATA MARIADB DARI FLYENV KE MACPORTS"
echo "=========================================================="

# 1. Pastikan MariaDB sedang tidak berjalan
if ps aux | grep -E '[m]ariadbd|[m]ysqld' | grep -v grep > /dev/null; then
    echo ">> Menghentikan MariaDB yang sedang berjalan..."
    sudo port unload mariadb-10.11-server 2>/dev/null || true
    sudo pkill -f mariadbd 2>/dev/null || true
    sleep 2
fi

# 2. Backup data MacPorts saat ini jika ada
if [ -d "$MACPORTS_DATA" ]; then
    echo ">> Membuat backup data MacPorts lama ke:"
    echo "   $BACKUP_DATA"
    sudo cp -R "$MACPORTS_DATA" "$BACKUP_DATA"
fi

# 3. Sinkronkan seluruh data database dari FlyEnv ke direktori MacPorts
echo ">> Menyalin seluruh database dari FlyEnv ke $MACPORTS_DATA..."
sudo rsync -av --delete "$FLYENV_DATA/" "$MACPORTS_DATA/"

# 4. Atur kepemilikan dan permission direktori MacPorts
echo ">> Menetapkan hak akses direktori ke user '_mysql:_mysql'..."
sudo chown -R _mysql:_mysql "$MACPORTS_DATA"
sudo chmod 700 "$MACPORTS_DATA"

echo "=========================================================="
echo ">> Menyalakan MariaDB MacPorts..."
sudo port load mariadb-10.11-server
sleep 3

if ps aux | grep -E '[m]ariadbd|[m]ysqld' | grep -v grep > /dev/null; then
    echo "=========================================================="
    echo "✅ SUKSES: MariaDB MacPorts berhasil menyala!"
    echo ">> Socket: /tmp/mysql.sock"
    echo ">> Port: 3306"
    echo ">> Coba tes koneksi dengan: mysql -u root"
    echo "=========================================================="
else
    echo "=========================================================="
    echo "⚠️ MariaDB belum terdeteksi aktif. Silakan cek log error:"
    echo "   tail -n 30 /opt/local/var/db/mariadb-10.11/*.err"
    echo "=========================================================="
fi
