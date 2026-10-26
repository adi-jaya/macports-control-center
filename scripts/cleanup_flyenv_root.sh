#!/bin/bash
set -e

echo ">> Menghapus sisa background helper FlyEnv (root)..."
sudo launchctl bootout system/com.flyenv.helper 2>/dev/null || sudo launchctl unload /Library/LaunchDaemons/com.flyenv.helper.plist 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/com.flyenv.helper.plist
sudo rm -rf "/Library/Application Support/FlyEnv"
sudo pkill -f "flyenv-helper" 2>/dev/null || true

echo "✅ Background helper FlyEnv berhasil dibersihkan total."
