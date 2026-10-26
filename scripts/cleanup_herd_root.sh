#!/bin/bash
set -e

echo "Menghapus sisa helper tools Herd (root)..."
sudo launchctl bootout system/de.beyondco.herd.helper 2>/dev/null || sudo launchctl unload /Library/LaunchDaemons/de.beyondco.herd.helper.plist 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/de.beyondco.herd.helper.plist
sudo rm -f /Library/PrivilegedHelperTools/de.beyondco.herd.helper
sudo rm -f /etc/sudoers.d/herd
sudo pkill -f "de.beyondco.herd" 2>/dev/null || true

echo "✅ Sisa helper tools Herd berhasil dibersihkan total."
