# Dokumen Desain: MacPorts Control Center (macOS Native GUI)

- **Tanggal:** 28 Oktober 2026
- **Target Platform:** macOS Monterey 12.0+ (`x86_64` Intel & `arm64` Apple Silicon)
- **Teknologi Utama:** Swift Native (`SwiftUI` + `AppKit`, Swift 5.7+)
- **Direktori Proyek Aplikasi:** `/Users/adijaya/MyFiles/Projects/macports-control-center`
- **Repositori GitHub:** `adi-jaya/macports-control-center` (`https://github.com/adi-jaya/macports-control-center`)

---

## 1. Tujuan & Latar Belakang (*Intent and Why*)

Selama ini pemantauan lingkungan web development MacPorts dilakukan melalui dua skrip PHP:
1. Dashboard status lokal di `/Users/adijaya/Sites/localhost/index.php`.
2. Pembaca dokumentasi Markdown lama (`index.php`).

Pendekatan berbasis PHP tersebut memiliki kelemahan mendasar:
- Bersifat **read-only** (tidak bisa menyalakan/mematikan service, menambah virtual host, atau menginstal paket).
- **Ikut mati total** apabila Nginx atau PHP-FPM sedang berhenti atau mengalami *crash*.
- Aplikasi alternatif pihak ketiga tidak dapat digunakan di mesin ini: **Laravel Herd** mengalami *instant crash* di macOS Monterey akibat memanggil simbol C++ SDK macOS 15+ (`__ZNSt3__122__libcpp_verbose_abortEPKcz`, Herd Bug #1600), sedangkan **FlyEnv** mengacaukan `$PATH` dan socket database.

**MacPorts Control Center** dibangun sebagai aplikasi GUI desktop native macOS yang bekerja seperti Laravel Herd atau FlyEnv namun menjadikan **MacPorts (`/opt/local/bin/port`)** sebagai mesin utamanya. Aplikasi ini memicu perintah-perintah MacPorts dan memanipulasi konfigurasi layanan melalui interaksi GUI modern (tombol, *checkbox*, *dropdown*, dan formulir), sekaligus mampu mengelola paket MacPorts umum di luar ekosistem Laravel.

---

## 2. Goals, Non-Goals, dan Anti-Goals

### A. Goals (Sasaran Utama)
1. **Konsumsi RAM & CPU Ultra-Rendah:** Menggunakan komponen native macOS (`SwiftUI` + `AppKit`) tanpa mesin browser (*WebView*), dengan pemakaian RAM aktif **~15–22 MB** dan beban CPU **0.0% saat diam (*idle*)**.
2. **Distribusi Mandiri (*Zero Runtime Dependency*):** Dikompilasi menjadi satu bundel aplikasi **`MacPorts Control Center.app`** (~1 MB) yang dapat dijalankan langsung di macOS tanpa mengharuskan pengguna menginstal PHP, Node.js, maupun Rust.
3. **7 Halaman Pengelolaan Terpadu:**
   - **🟢 Services & Tools:** Kontrol *Start / Stop / Restart* untuk Nginx, PHP-FPM, MariaDB, serta deteksi otomatis seluruh subdirektori daemon MacPorts di `/opt/local/etc/LaunchDaemons/org.macports.*/org.macports.*.plist` (dan status symlink aktif di `/Library/LaunchDaemons/org.macports.*.plist`), dilengkapi tombol otomasi 1-klik untuk `dnsmasq` (`*.test`), `mkcert` (SSL lokal), Redis, dan info `fnm` / Composer.
   - **🌐 Sites / Virtual Hosts:** Pengelolaan berkas `/opt/local/etc/nginx/servers/*.conf`, form pembuatan situs baru (Port-based `808X` atau Domain `*.test`, pilihan PHP-FPM pool per proyek, template Laravel/SPA, toggle HTTPS `mkcert`), deteksi otomatis `DB_DATABASE` & `APP_URL` dari berkas `.env` proyek, serta pintasan buka di Browser/Finder/Editor.
   - **🐘 PHP & Extensions:** Pengelolaan multi-versi PHP (`php81`, `php82`, `php83`, `php84`, `php85`), instalasi *bundle* Laravel 1-klik beserta auto-konfigurasi pool `www.conf` (`user = <current_user>:staff`, port unik `908X`), pemilih versi CLI global (`port select --set php`), tombol *Uninstall Bersih* (`--follow-dependents`), *checkbox* instalasi/pelepasan subport ekstensi MacPorts (`mysql`, `mbstring`, `curl`, `openssl`, `gd`, `intl`, `zip`, `sqlite`, `iconv`, `opcache`, `redis`, `imagick`, `xdebug`, `postgresql`, `soap`, `exif`, `pcntl`, `sockets`, `sodium`, `posix`), serta badge indikator modul *Built-in Core* (`bcmath`, `json`, `ctype`, `tokenizer`, `xml`, `dom`, `fileinfo`).
   - **🗄️ MariaDB & Databases:** Pengelolaan mesin database (`mariadb-10.11`, `mariadb-11.4`, `mysql8`), daftar 24+ database aktif (via `/tmp/mysql.sock` atau `127.0.0.1:3306`), pembuatan database baru, serta tombol **Backup `.sql` (`mysqldump`)** dan **Import `.sql`**.
   - **📦 Cari Paket MacPorts (`port search` & `port installed`):** Pencarian bebas untuk ribuan paket MacPorts (termasuk *toolchain* non-Laravel seperti `rust`, `go`, `python`, `ffmpeg`, `htop`, `postgresql`), dukungan multi-versi terpasang (`name@version`), *Activate / Deactivate* versi spesifik, *Uninstall*, *Sync (`selfupdate`)*, *Upgrade Outdated*, *Hapus Leaves (`uninstall leaves`)*, serta panel **Dynamic Global Version Switcher** yang membaca seluruh grup `port select --summary` (termasuk `python`, `python3`, `mysql`, `php`, `clang`, dll.).
   - **📋 Server Logs:** Pembaca log *real-time* untuk Nginx (`error.log`, `access.log`), PHP-FPM (`php-fpm.log`), dan MariaDB (`error.log` / `.err`), lengkap dengan deteksi izin baca dan tombol perbaikan cepat via Stack Doctor.
   - **📖 MacPorts Docs:** Pembaca dokumentasi Markdown (`/Users/adijaya/MyFiles/Projects/macports-control-center/*.md` dan `Bundle.main.resourceURL`) terintegrasi yang menggantikan `index.php` lama.
4. **Docked Live Terminal Output Drawer:** Panel log terminal permanen di bagian bawah jendela aplikasi yang menampilkan *stream* `stdout` dan `stderr` baris demi baris secara langsung setiap kali perintah MacPorts dijalankan, lengkap dengan indikator status, durasi waktu, dan tombol **Batalkan Proses**.
5. **Fitur Produktivitas & Guardrail:**
   - **🛡️ Stack Doctor & Auto-Fix Guardrails:** Pemeriksaan dan perbaikan 1-klik untuk 5 indikator kesehatan: (1) passwordless sudo `/etc/sudoers.d/macports`, (2) konfigurasi `user = <user>:staff` di `www.conf`, (3) izin tulis `/opt/local/etc/nginx/servers/`, (4) ketersediaan socket `/tmp/mysql.sock`, serta (5) izin baca berkas log (`/opt/local/var/log/php*/php-fpm.log`, `/opt/local/var/log/nginx/*.log`, dan `log_error` MariaDB) & izin PID Nginx.
   - **🎛️ Quick Tuning Form (`php.ini` & Nginx):** Pengaturan cepat via input form untuk `memory_limit`, `upload_max_filesize`, `post_max_size`, `max_execution_time`, dan `client_max_body_size`.
   - **⌨️ Command Palette (`Cmd + K`) & Menu Bar Icon (`NSStatusItem`):** Pencarian aksi/halaman cepat lewat papan ketik dan ikon status ringkas di Menu Bar macOS.

### B. Non-Goals (Bukan Cakupan)
- Tidak menggantikan klien manajemen isi tabel SQL penuh seperti TablePlus atau DBeaver (operasi database dibatasi pada inspeksi daftar database, buat database baru, ekspor `.sql`, dan impor `.sql`).
- Tidak membundel binary PHP/Nginx/MariaDB sendiri di dalam `.app`; seluruh layanan dijalankan dari instalasi standar MacPorts di `/opt/local`.

### C. Anti-Goals (Hal yang Wajib Dihindari)
- **Jangan menggunakan WebView / Chromium:** Dilarang memuat `WKWebView` atau Electron untuk UI utama agar pemakaian RAM tidak membengkak ke >80–400 MB.
- **Jangan menulis berkas vhost dengan `sudo`:** Direktori `/opt/local/etc/nginx/servers/` dimiliki oleh user lokal (`adijaya:admin`); penulisan berkas `.conf` wajib dilakukan dengan hak user biasa agar kepemilikan tidak berubah menjadi `root`.
- **Jangan me-reload Nginx tanpa validasi sintaks `nginx -t`:** Setiap perubahan virtual host atau `nginx.conf` wajib diuji dengan `/opt/local/sbin/nginx -t` terlebih dahulu. Validator wajib mengenali `syntax is ok` (mengabaikan warning permission `nginx.pid` saat dijalankan non-root) namun membatalkan reload dan melakukan *rollback* berkas `.conf` apabila terdapat `[emerg]` kesalahan sintaks konfigurasi.
- **Jangan membiarkan worker PHP-FPM berjalan sebagai `nobody`/`_www`:** Setiap pembuatan atau modifikasi `www.conf` wajib menetapkan `user = <username_aktif>` dan `group = staff`.
- **Jangan menjalankan dua operasi tulis `port` secara bersamaan:** MacPorts menggunakan kunci (*lock*) pada database registry SQLite internalnya; antrean perintah di aplikasi harus mengeksekusi operasi `sudo port ...` secara berurutan (*serialized queue*).

---

## 3. Batasan Teknis & Konvensi Lingkungan (*Constraints*)

- **Sistem Operasi & Arsitektur:** macOS Monterey 12.7.6 (Build 21H1320, Intel `x86_64`) sebagai host pengembangan utama, dengan target kompilasi `macosx12.0` yang kompatibel di Intel maupun Apple Silicon.
- **Toolchain Tersedia:** Apple Swift 5.7.2 (`/usr/bin/swift`, `/usr/bin/swiftc`) via Xcode Command Line Tools. Proyek dibangun menggunakan Swift Package Manager (`Package.swift`) + skrip pembuat bundel `build-app.sh` tanpa mewajibkan instalasi Xcode IDE penuh (~12 GB).
- **Eksekusi Hak Istimewa (`sudo`):**
  - Di mesin host, `/etc/sudoers.d/macports` telah mengizinkan `NOPASSWD: /opt/local/bin/port`. Seluruh perintah MacPorts dijalankan melalui `/usr/bin/sudo -n /opt/local/bin/port <subcommand>`.
  - Untuk operasi perbaikan sistem sekali jalan yang berada di luar cakupan `/opt/local/bin/port` (seperti setup awal `/etc/sudoers.d/macports`, mengatur kepemilikan `/opt/local/etc/nginx/servers/`, serta membuka izin baca grup `admin` pada `/opt/local/var/log/php*/php-fpm.log` dan `/opt/local/var/run/nginx/nginx.pid`), fitur **Stack Doctor** menggunakan dialog otorisasi administrator macOS standar melalui `/usr/bin/osascript -e 'do shell script "..." with administrator privileges'`.

---

## 4. Pendekatan yang Dipertimbangkan (*Approaches*)

Sebelum menetapkan desain akhir, empat pendekatan arsitektur telah dievaluasi:

| Pendekatan | RAM Aktif | Ukuran `.app` | Kelebihan & Kekurangan | Keputusan |
| :--- | :---: | :---: | :--- | :---: |
| **1. Electron (Node.js + Chromium)** | ~250–450 MB | ~200 MB | Mudah memakai HTML/CSS/JS, namun sangat boros RAM dan ruang disk di Mac Intel. | ❌ Ditolak |
| **2. Node.js v24 + Swift `WKWebView` / Tauri (Rust + WebKit)** | ~80–130 MB | ~1–12 MB | Tampilan identik web, namun proses `WebKit.WebContent` tetap memakai ~80+ MB RAM selama jendela dibuka. | ❌ Ditolak |
| **3. Rust Native GUI (`egui` / `eframe`)** | ~28–45 MB | ~10 MB | Tanpa WebView, namun bersifat *immediate-mode canvas* (menggambar ulang layar di GPU/CPU saat streaming log) dan butuh instalasi toolchain Rust >1 GB. | ❌ Ditolak |
| **4. Swift Native (`SwiftUI` + `AppKit`)** | **~14–22 MB** | **~1 MB** | Memakai *Shared Framework Cache* macOS, **0% CPU saat idle**, ukuran distribusi terkecil, menyatu dengan Menu Bar macOS, dan compiler Swift sudah terpasang. | ✅ **Dipilih** |

---

## 5. Spesifikasi Arsitektur & Komponen Aplikasi

### A. Tata Letak Direktori Proyek & Pemisahan Target Swift Package
Repositori berada di [`/Users/adijaya/MyFiles/Projects/macports-control-center`](file:///Users/adijaya/MyFiles/Projects/macports-control-center) dengan jembatan *symbolic link* dari `/Users/adijaya/Documents/MacPorts_Docs` untuk kompatibilitas referensi lama.

Agar seluruh logika bisnis, parser, dan state dapat diuji secara penuh melalui `swift test` (`XCTest`) tanpa konflik simbol entry point `@main`, `Package.swift` dibagi menjadi 2 target utama:
1. **`MacPortsControlCenter` (Library Target):** Berisi seluruh `Models`, `Services`, dan `Views`.
2. **`MacPortsControlCenterApp` (Executable Target):** Berisi `MainApp.swift` (`@main`, `WindowGroup`, dan `MenuBarController` berbasis `NSStatusItem`).

```text
/Users/adijaya/MyFiles/Projects/macports-control-center/
├── Package.swift                 # Definisi Swift Package (.macOS(.v12), Library + Executable + Test targets)
├── build-app.sh                  # Skrip kompilasi & pembuat bundel "build/MacPorts Control Center.app"
├── README.md                     # Dokumentasi utama (dibundel juga ke dalam Contents/Resources/)
├── VIRTUAL_HOSTS_AND_DOMAINS_GUIDE.md
├── FRESH_INSTALL_GUIDE.md
├── FINAL_MACPORTS_ENVIRONMENT_SETUP.md
├── HANDOFF_MACPORTS_MIGRATION.md
├── AGENTS.md
├── config_templates/             # Template acuan nginx.conf, php.ini, www.conf, vhost
├── scripts/                      # Skrip otomasi POSIX sh
├── Resources/
│   └── Info.plist                # Metadata bundel macOS (LSMinimumSystemVersion 12.0)
├── Sources/
│   ├── MacPortsControlCenter/
│   │   ├── Models/
│   │   │   ├── DomainModels.swift      # Struct model terpadu (ServiceItem, VHostItem, PHPVersionItem, PortPackageItem, dll.)
│   │   │   └── AppState.swift          # State terpusat (@MainActor ObservableObject)
│   │   ├── Services/
│   │   │   ├── CommandRunner.swift     # Async Process streaming stdout/stderr + Serialized Port Queue
│   │   │   ├── MacPortsService.swift   # Parser port search, port installed, port select, LaunchDaemons & ps aux
│   │   │   ├── ConfigFileService.swift # Parser & writer nginx/*.conf, php.ini, www.conf, .env + nginx -t validator
│   │   │   ├── DatabaseService.swift   # Eksekusi mysql CLI / mysqldump via /tmp/mysql.sock
│   │   │   └── DoctorService.swift     # Evaluasi & generator perbaikan otomatis 5 guardrails AGENTS.md
│   │   └── Views/
│   │       ├── MainWindowView.swift    # Sidebar 7 menu + Area Konten + Docked Terminal Drawer
│   │       ├── ServicesView.swift      # Halaman 1: Services, Ecosystem Tools & Stack Doctor
│   │       ├── SitesView.swift         # Halaman 2: Nginx Virtual Hosts + .env detector
│   │       ├── PHPManagerView.swift    # Halaman 3: Multi-PHP, Extensions Checkbox, Quick Tuning php.ini
│   │       ├── DatabaseView.swift      # Halaman 4: MariaDB/MySQL, 24+ DBs, Backup/Import .sql
│   │       ├── PackagesView.swift      # Halaman 5: Universal port search, installed, port select
│   │       ├── LogsView.swift          # Halaman 6: Live Log Tailer (Nginx, PHP-FPM, MariaDB)
│   │       ├── DocsView.swift          # Halaman 7: Native Markdown Reader (membaca *.md dari Bundle/Repo)
│   │       ├── TerminalDrawerView.swift # Panel bawah: Live stdout/stderr + tombol Cancel/Clear
│   │       └── CommandPaletteView.swift # Overlay Cmd + K
│   └── MacPortsControlCenterApp/
│       └── MainApp.swift               # Entry point (@main), WindowGroup, MenuBarController (NSStatusItem)
└── Tests/
    └── MacPortsControlCenterTests/
        ├── MacPortsServiceTests.swift
        ├── CommandRunnerTests.swift
        ├── ConfigFileServiceTests.swift
        ├── DoctorAndDatabaseTests.swift
        └── AppStateTests.swift
```

### B. Mesin Eksekusi Perintah & *Docked Live Terminal Output Drawer* (`CommandRunner.swift`)
1. **Streaming Real-Time Tanpa Mengunci UI:**
   - Menggunakan `Foundation.Process` dan `Pipe` dengan `readabilityHandler` yang mempublikasikan setiap baris `stdout` dan `stderr` ke `@Published private(set) var terminalLines: [String]` pada `@MainActor`.
   - Jendela terminal di bagian bawah menggunakan `NSTextView` (dibungkus dengan `NSViewRepresentable`) berlatar gelap (`#020617`) dengan auto-scroll ke baris paling bawah sehingga sanggup menampilkan ribuan baris output `port install` tanpa membuat UI patah-patah.
2. **Antrean Eksekusi MacPorts (*Serialized Queue*) & Pembatalan:**
   - Operasi tulis seperti `sudo -n /opt/local/bin/port install/uninstall/load/unload/reload/activate/deactivate/select/selfupdate/upgrade` dimasukkan ke antrean sekuensial FIFO agar tidak pernah terjadi konflik kunci registry MacPorts (`sqlite error: database is locked`).
   - Tersedia tombol **⏹ Batalkan Proses** yang mengirim sinyal `interrupt()` / `terminate()` ke `Process` yang sedang berjalan.
3. **Lingkungan `$PATH` Standar:**
   - Setiap proses anak dijalankan dengan variabel `PATH="/opt/local/bin:/opt/local/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(NSHomeDirectory())/.local/bin"`.

### C. Detail Perilaku Ketujuh Halaman & Fitur Tambahan

#### 1. Halaman **🟢 Services & Tools** + **🛡️ Stack Doctor**
- **Deteksi Otomatis Daemon MacPorts:**
  - Memindai subdirektori `/opt/local/etc/LaunchDaemons/org.macports.*` (di mana berkas plist terletak di `/opt/local/etc/LaunchDaemons/org.macports.<name>/org.macports.<name>.plist`) serta memeriksa apakah symlink `/Library/LaunchDaemons/org.macports.<name>.plist` terpasang (*Enabled at Boot*).
  - Pencocokan status *Running / Stopped* melalui `ps aux` dirancang akurat terhadap proses nyata MacPorts:
    1. Mencocokkan proses wrapper `daemondo --label=<name>`, **atau**
    2. Untuk `phpXY-fpm`: mencocokkan `/opt/local/etc/phpXY/php-fpm.conf` atau `php-fpmXY`, **atau**
    3. Untuk daemon berakhiran `-server` (seperti `mariadb-10.11-server`, `postgresql16-server`): menghapus akhiran `-server` lalu mencocokkan jalur binary terkait (misal `/opt/local/lib/mariadb-10.11/bin/mysqld` atau `mariadbd`), **atau**
    4. Mencocokkan binary `/opt/local/sbin/<name>` atau `/opt/local/bin/<name>`.
  - Tombol global **Start Web Stack**, **Restart All**, dan **Stop All**.
- **Utilitas Ekosistem 1-Klik:**
  - Kartu instalasi dan pengaktifan cepat untuk **`dnsmasq`** (termasuk setup `/opt/local/etc/dnsmasq.conf` dan `/etc/resolver/test`), **`mkcert`** (termasuk `mkcert -install`), **Redis**, serta penampil status **Node.js (`fnm`)** & **Composer**.
- **Panel Stack Doctor (5 Guardrails [`AGENTS.md`](file:///Users/adijaya/MyFiles/Projects/macports-control-center/AGENTS.md)):**
  - Memeriksa 5 indikator kesehatan:
    1. **`sudoers`:** Apakah `/etc/sudoers.d/macports` aktif (`sudo -n /opt/local/bin/port version`).
    2. **`fpm-user`:** Apakah seluruh `/opt/local/etc/php*/php-fpm.d/www.conf` menggunakan `user = <current_user>` dan `group = staff`.
    3. **`nginx-writable`:** Apakah direktori `/opt/local/etc/nginx/servers/` dapat ditulis langsung oleh user biasa tanpa `sudo`.
    4. **`mysql-socket`:** Apakah socket `/tmp/mysql.sock` tersedia saat MariaDB berjalan.
    5. **`log-readable`:** Apakah berkas log `/opt/local/var/log/php*/php-fpm.log` (yang secara default dibuat `root` dengan mode `0600`) dan `/opt/local/var/log/nginx/*.log` dapat dibaca oleh user lokal.
  - Menyediakan tombol **⚡ Auto-Fix Masalah** yang memperbaiki `www.conf` secara langsung dan menjalankan skrip perbaikan hak akses/sudoers melalui prompt administrator macOS (`osascript` `with administrator privileges`).

#### 2. Halaman **🌐 Sites / Virtual Hosts**
- Membaca seluruh berkas `.conf` di `/opt/local/etc/nginx/servers/`.
- Mengekstrak `listen` (port), `server_name`, `root` (jalur folder publik), `fastcgi_pass` (port PHP-FPM), dan status SSL (`ssl_certificate`).
- **Integrasi `.env` Laravel Otomatis:** Untuk setiap vhost yang `root`-nya berakhir dengan `/public`, aplikasi membaca berkas `../.env` (jika ada) dengan membersihkan tanda kutip dan komentar inline `#` untuk menampilkan nama `DB_DATABASE` dan `APP_URL` secara langsung di baris tabel situs, ditambah tombol **Fix Permission Storage (`chmod -R u+rwX storage bootstrap/cache`)**, **Buka di Browser**, **Buka di Finder**, dan **Edit `.conf`**.
- **Formulir Tambah/Edit Virtual Host:**
  - Memilih folder proyek menggunakan dialog native macOS (`NSOpenPanel`).
  - Memilih mode akses: **Port-Based** (otomatis menyarankan port kosong berikutnya, misal `8081`, `8082`) atau **Domain Lokal `*.test`**.
  - Memilih target pool **PHP-FPM** (misal PHP 8.3 `:9000`, PHP 8.2 `:9082`, PHP 8.4 `:9084`) dan jenis template (**Laravel** atau **SPA/Static**).
  - Checkbox **Aktifkan HTTPS (`mkcert`)** yang otomatis membuat sertifikat di `/opt/local/etc/nginx/ssl/` dan memasangnya ke blok server.
  - **Validasi Sintaks `nginx -t` yang Tahan Non-Root:** Saat disimpan, menulis berkas langsung sebagai user biasa (tanpa `sudo`), lalu menjalankan `/opt/local/sbin/nginx -t`. Validator menilai konfigurasi **valid** apabila `exitCode == 0` **ATAU** output memuat `"syntax is ok"` tanpa adanya pesan `[emerg]` selain gagal buka `/opt/local/var/run/nginx/nginx.pid` akibat dijalankan non-root. Jika terdapat kesalahan sintaks sesungguhnya, berkas `.conf` otomatis di-*rollback* ke isi semula dan pesan error ditampilkan di *Live Terminal Drawer*. Jika valid, jalankan `sudo -n /opt/local/bin/port reload nginx`.

#### 3. Halaman **🐘 PHP & Extensions** + **🎛️ Quick Tuning `php.ini`**
- **Katalog Multi-PHP (`php81`, `php82`, `php83`, `php84`, `php85`):**
  - Menampilkan status tiap versi (Terpasang / Belum Terpasang, status FPM & port pool, status CLI Default).
  - **1-Klik Bundle Install + Auto-Config:** Menjalankan `sudo -n /opt/local/bin/port install phpXY phpXY-fpm phpXY-mysql phpXY-openssl phpXY-curl phpXY-mbstring phpXY-zip phpXY-gd phpXY-intl phpXY-sqlite phpXY-iconv phpXY-opcache php_select`, lalu otomatis menyiapkan `/opt/local/etc/phpXY/php-fpm.d/www.conf` dari `www.conf.default` dengan menyetel `user = <current_user>`, `group = staff`, dan `listen = 127.0.0.1:90XY` (kecuali `php83` yang tetap di `9000`).
  - **Uninstall Bersih:** Tombol untuk menghentikan FPM, menjalankan `sudo -n /opt/local/bin/port uninstall --follow-dependents phpXY`, dan membersihkan `leaves`.
- **Checkbox Ekstensi PHP & Badge Built-in Core:**
  - Daftar *checkbox* 18 subport ekstensi MacPorts (`mysql`, `mbstring`, `curl`, `openssl`, `gd`, `intl`, `zip`, `sqlite`, `iconv`, `opcache`, `redis`, `imagick`, `xdebug`, `postgresql`, `soap`, `exif`, `pcntl`, `sockets`, `sodium`, `posix`) untuk versi PHP yang sedang dipilih. Mencentrang/melepas akan menjalankan `port install` / `port uninstall` untuk `phpXY-<ext>` dan me-reload FPM terkait.
  - Menampilkan daftar modul yang sudah terkompilasi *built-in* di core PHP MacPorts (`bcmath`, `json`, `ctype`, `tokenizer`, `xml`, `dom`, `fileinfo`, `phar`) sebagai badge aktif agar pengguna tidak bingung mencari subport-nya.
- **Quick Tuning Form (`php.ini` & Nginx):**
  - Form input langsung untuk `memory_limit`, `upload_max_filesize`, `post_max_size`, `max_execution_time` pada `/opt/local/etc/phpXY/php.ini`, serta `client_max_body_size` pada `/opt/local/etc/nginx/nginx.conf` (mengabaikan baris komentar `;` atau `#`), lengkap dengan tombol simpan & reload FPM/Nginx.

#### 4. Halaman **🗄️ MariaDB & Databases**
- Menampilkan status koneksi MariaDB (`/tmp/mysql.sock` & `127.0.0.1:3306`), lokasi datadir, tombol buka `my.cnf`, serta opsi instalasi mesin database lain (`mariadb-11.4`, `mysql8`).
- Menampilkan daftar seluruh database hasil query `/opt/local/bin/mysql -u root --socket=/tmp/mysql.sock -e "SHOW DATABASES;"` (menyaring schema internal `information_schema`, `performance_schema`, `mysql`, `sys`).
- Menyediakan form **+ Buat Database Baru**, tombol **⬇ Backup `.sql` (`mysqldump`)** menggunakan `NSSavePanel` macOS, dan tombol **⬆ Import `.sql`** menggunakan `NSOpenPanel`.

#### 5. Halaman **📦 Cari Paket MacPorts (Universal Package & Toolchain Manager)**
- **Pencarian, Filter & Dukungan Multi-Versi (`name@version`):**
  - Kotak pencarian yang mengeksekusi `/opt/local/bin/port search --name --line <query>` atau menampilkan daftar lengkap `/opt/local/bin/port installed` dan `/opt/local/bin/port outdated`.
  - Setiap item paket memiliki identitas unik `id = "\(name)@\(version)"` sehingga paket yang memiliki lebih dari satu versi terpasang (misalnya satu versi inaktif dan satu versi `(active)`) tampil tanpa bentrok ID di SwiftUI dan dapat di-*Activate*, *Deactivate*, atau *Uninstall* secara spesifik per versi (`sudo -n /opt/local/bin/port activate <name> <version>`).
  - Saat menggabungkan status `installed` ke hasil `port search`, entri yang berstatus `isActive == true` selalu diprioritaskan.
- **Tombol Pemeliharaan Global:**
  - **🔄 Sync PortIndex (`selfupdate`)**, **⬆️ Upgrade Outdated**, dan **🧹 Hapus Leaves (`uninstall leaves`)**.
- **Dynamic Global Version Switcher (`port select --summary`):**
  - Membaca output `/opt/local/bin/port select --summary` secara otomatis dan merender *dropdown* pemilih versi default untuk **semua grup bahasa/toolchain** yang terdeteksi di sistem (seperti `php`, `mysql`, `python`, `python3`, dan grup baru apa pun yang diinstal di masa mendatang).

#### 6. Halaman **📋 Server Logs** & **📖 MacPorts Docs**
- **Server Logs:** Sub-tab untuk memilih berkas log (`Nginx error.log`, `Nginx access.log`, `PHP-FPM log`, `MariaDB error.log`), tombol *Refresh / Auto-Tail*, dan *Clear Log*. Jika berkas log belum memiliki izin baca bagi user lokal (seperti `/opt/local/var/log/php83/php-fpm.log` yang awalnya `0600 root:admin`), halaman menampilkan peringatan jelas beserta tombol **🔓 Perbaiki Izin Baca Log (Stack Doctor)**.
- **MacPorts Docs:** Membaca seluruh berkas `.md` di `/Users/adijaya/MyFiles/Projects/macports-control-center` (serta fallback ke `Bundle.main.resourceURL` di dalam `.app`, mencakup `README.md`, `VIRTUAL_HOSTS_AND_DOMAINS_GUIDE.md`, `FRESH_INSTALL_GUIDE.md`, `FINAL_MACPORTS_ENVIRONMENT_SETUP.md`, `HANDOFF_MACPORTS_MIGRATION.md`, `AGENTS.md`) dengan *formatting* teks terstruktur di `NSTextView` tanpa butuh PHP atau koneksi internet.

#### 7. **⌨️ Command Palette (`Cmd + K`) & Menu Bar Extra (`NSStatusItem`)**
- Menekan `Cmd + K` membuka jendela pencarian cepat untuk berpindah ke halaman mana pun atau memicu aksi cepat (*Restart Web Stack*, *Reload Nginx*, *Run Stack Doctor*, *Switch PHP*, dll.).
- Ikon kecil di *Menu Bar* macOS (`NSStatusItem`) menampilkan status ringkas (Nginx, PHP-FPM, MariaDB) dan tombol cepat *Start/Stop/Restart* serta *Buka Jendela Utama*—bahkan ketika jendela utama ditutup untuk menghemat RAM hingga ~6 MB.

---

## 6. Keputusan Builder (*What's Left to the Builder*)

Hal-hal detail implementasi berikut diserahkan kepada *builder*:
1. **Kompilasi & Pembungkusan `.app`:** Menyusun [`Package.swift`](file:///Users/adijaya/MyFiles/Projects/macports-control-center/Package.swift) dan skrip [`build-app.sh`](file:///Users/adijaya/MyFiles/Projects/macports-control-center/build-app.sh) yang mengompilasi binary Swift (`swift build -c release`) lalu membungkusnya ke `/Users/adijaya/MyFiles/Projects/macports-control-center/build/MacPorts Control Center.app` (serta opsional memasang ke `/Applications`).
2. **Integrasi Dokumentasi Repositori:** Memperbarui [`README.md`](file:///Users/adijaya/MyFiles/Projects/macports-control-center/README.md) dan [`AGENTS.md`](file:///Users/adijaya/MyFiles/Projects/macports-control-center/AGENTS.md) setelah aplikasi selesai dibangun untuk mencatat cara menjalankan dan mengompilasi aplikasi GUI ini.
3. **Parser Markdown Ringan Native:** Menggunakan parser Markdown berbasis Swift/`NSAttributedString` untuk halaman **MacPorts Docs** agar tabel, blok kode, dan *heading* tampil rapi di komponen native `NSTextView` tanpa membutuhkan `WKWebView`.
