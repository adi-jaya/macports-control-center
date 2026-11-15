# Changelog

Semua perubahan penting pada proyek **MacPorts Control Center** akan didokumentasikan dalam berkas ini.

Format berkas ini mengacu pada [Keep a Changelog](https://keepachangelog.com/id/1.0.0/),
dan proyek ini mematuhi prinsip [Semantic Versioning](https://semver.org/lang/id/).

---

## [Unreleased]

### Added
- Belum ada perubahan baru yang belum dirilis.

---

## [1.0.0] - 2026-11-15

### Added
- **Aplikasi Desktop Swift Native Mandiri**: Aplikasi GUI macOS native (`SwiftUI` + `AppKit`) *zero-dependency* (~14–22 MB RAM, ~4.2 MB binary) untuk mengelola web development stack MacPorts.
- **7 Visual Tabs Utama**:
  - **Services & Stack Doctor**: Pemantauan status live (Nginx, Multi-PHP FPM, MariaDB), kontrol start/stop/restart, serta Stack Doctor 5-guardrail dengan auto-fix dan *in-app privileged osascript elevation* untuk `mkcert` dan `dnsmasq`.
  - **Sites & Virtual Hosts**: Penjelajah vhost Nginx (`/opt/local/etc/nginx/servers/`), konfigurasi port/domain, deteksi database SQLite Laravel di `.env`, dan integrasi Quick Tunnel Cloudflare.
  - **PHP Manager**: Pengelolaan multi-versi PHP (PHP 8.1, 8.2, 8.3, 8.4), switch versi default CLI, dan auto-discovery ekstensi PHP terpasang.
  - **Databases**: Pengelolaan database MariaDB (create/drop/inspect database, switch engine, dynamic status).
  - **Packages**: Pencarian paket MacPorts super cepat melalui indeks lokal SQLite registry (`registry.db`) dan PortIndex.quick dengan fallback ke CLI `port`.
  - **Logs**: Tailing log sistem realtime (Nginx error/access log, PHP-FPM log, MariaDB error log) menggunakan kqueue `DispatchSourceFileSystemObject`.
  - **Documentation**: Markdown viewer native dengan dukungan GitHub Flavored Markdown (GFM), rendering tabel grafis via `NSTextTable`, alerts/callouts, dan live link navigation.
- **Menu Bar Controller (`NSStatusItem`)**:
  - Live status indicator di macOS menu bar (hijau = running, kuning = degraded, merah = stopped, oranye = updating).
  - Quick actions: Start/Stop/Restart Web Stack, buka `http://localhost:80`, dan akses cepat folder `/opt/local/etc/nginx/servers`.
- **Command Palette (`Cmd+K`)**:
  - Navigasi cepat antar tab, pencarian perintah, dan eksekusi aksi sistem instan.
- **Integrated Terminal Drawer & External Terminal Runner**:
  - Terminal drawer terintegrasi di bagian bawah aplikasi dengan live streaming stdout/stderr async.
  - Dukungan peluncuran terminal eksternal untuk perintah interaktif (seperti inisialisasi CA `mkcert`).
- **Cloudflare Tunnels Integration**:
  - Pembuatan dan pengawasan proses quick tunnel `cloudflared` langsung dari aplikasi atau konteks vhost.
- **Build System & Packaging (`build-app.sh`)**:
  - Kompilasi Swift native release binary dengan optimasi `-whole-module-optimization` dan dead-strip.
  - Dukungan build arsitektur host (Intel x86_64) maupun Universal Binary (x86_64 + Apple Silicon arm64).
  - Stripping Mach-O linkedit debug symbols.
  - Generator icon aplikasi otomatis (`scripts/generate_icon.sh`) dari PNG ke `.icns`.
  - Opsi `--install` dan `--user-install` untuk deployment instan ke `/Applications`.

### Changed
- Migrasi arsitektur dari web viewer PHP lokal berbasis browser ke aplikasi desktop macOS native mandiri.

### Fixed
- Scrolling NSTextView pada tab Documentation, Terminal Drawer, dan Logs View.
- Transisi instan AppKit tanpa lag saat berpindah antar komponen UI.
- Penanganan izin file pool PHP-FPM `adijaya:staff` untuk mencegah permission denied pada Laravel storage/cache.

[Unreleased]: https://github.com/adi-jaya/macports-control-center/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/adi-jaya/macports-control-center/releases/tag/v1.0.0
