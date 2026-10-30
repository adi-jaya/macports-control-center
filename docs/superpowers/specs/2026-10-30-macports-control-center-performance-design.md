# Dokumen Spesifikasi Desain: Optimasi Performa, Memori & Ukuran Bundel MacPorts Control Center

- **Tanggal:** 30 Oktober 2026
- **Target Platform:** macOS Monterey 12.0+ (`x86_64` Intel & `arm64` Apple Silicon)
- **Lingkungan Host Acuan:** macOS Monterey 12.7.6 (Build `21H1320`, Intel `x86_64`) — Apple Swift 5.7.2 Command Line Tools
- **Dokumen Dasar Audit:** Laporan Pemeriksaan Performa (`PERF-01` s/d `PERF-14`, 29 Oktober 2026)
- **Spesifikasi Induk:** [`docs/superpowers/specs/2026-10-27-macports-control-center-design.md`](file:///Users/adijaya/MyFiles/Projects/macports-control-center/docs/superpowers/specs/2026-10-27-macports-control-center-design.md)
- **Rencana Implementasi Pasangan:** [`docs/superpowers/plans/2026-10-30-macports-control-center-performance.md`](file:///Users/adijaya/MyFiles/Projects/macports-control-center/docs/superpowers/plans/2026-10-30-macports-control-center-performance.md)

---

## 1. Tujuan & Latar Belakang (*Objective*)

Audit performa empiris terhadap aplikasi aktif `MacPorts Control Center.app` pada macOS Monterey 12.7.6 menunjukkan deviasi signifikan terhadap sasaran desain awal:
1. **UI Freeze ($O(N^2)$) pada Streaming Terminal:** Mengalirkan `2.500` baris output membutuhkan **`13.859 ms` (`13,86 detik`)** di Main Thread akibat penggabungan ulang `terminalLines.joined(separator: "\n")` di dalam `View.body` dan penggantian penuh `NSTextView.string`, diperparah oleh penyalinan buffer `Data` per baris di `StreamCollector`.
2. **Banjir Polling pada Terminal & Subprocess Duplikat:** Satu kali `AppState.refreshAll()` mengeksekusi 6 tahap secara sekuensial (`~669 ms`), memanggil `ps aux` 2× dan `port select --summary` 2× melalui `/bin/zsh -c`, serta menumpahkan **`976` baris** mentah ke `terminalLines` setiap kali refresh.
3. **Pencarian Paket Lambat Tanpa Cache:** `searchPackages("php")` mengeksekusi ulang `port installed` + `port outdated` + `port search` secara berurutan (`945–1.810 ms`) dan merender `1.610` baris sekaligus di dalam `VStack` berlapis.
4. **Jejak RAM Tinggi (`48,3 MB`, Peak `65,7 MB`) & Kebocoran Idle CPU:** Menutup jendela utama (`Cmd+W`) hanya memanggil `orderOut(nil)` sehingga seluruh pohon `NSHostingView`, `94` region `CoreAnimation`, dan timer `2.0s` `LogsView` (membaca ulang `250 KB` terus-menerus) tetap aktif di latar belakang.
5. **Latensi Render Markdown (`65,2 ms`) & Ukuran Bundel (`5,3 MB`):** `MarkdownStyler` memanggil parser `AttributedString(markdown:)` ratusan kali per klik tanpa *fast-path* maupun cache, sedangkan binary Release menyimpan `2,98 MB` tabel simbol `__LINKEDIT` yang belum di-*strip* dan `AppIcon.icns` berukuran `924 KB`.

Spesifikasi ini mengunci desain arsitektur untuk menuntaskan seluruh **14 temuan (`PERF-01` s/d `PERF-14`)** tanpa mengurangi fitur dan dengan mempertahankan **100% kelulusan 42 unit test yang sudah ada**.

---

## 2. Sasaran Kuantitatif (*Success Criteria*)

| Metrik Performa | Baseline Aktual | Target Pasca-Optimasi (Wajib Tercapai) | Cara Verifikasi |
| :--- | :---: | :---: | :--- |
| **Unit Test Suite Eksisting + Baru** | `42/42` lulus | **100% lulus (`exit code 0`)** | `TEST_RUNNER=1 /tmp/run-all-tests` |
| **Streaming `NSTextView` (`2.500` baris / `250` batch)** | `13.859,01 ms` | **`< 200 ms`** | Microbenchmark Release `-O` |
| **`StreamCollector.appendData` (`1.610` baris / `136 KB`)** | `9,86 ms` | **`< 1,0 ms`** | Microbenchmark Release `-O` |
| **Latensi `AppState.refreshAll()` End-to-End** | `669,45 ms` (`+976` baris log) | **`< 120 ms`** (**`0` baris** di `terminalLines`) | Headless benchmark Release `-O` |
| **Latensi `AppState.searchPackages("php")`** | `945 – 1.810 ms` (`+1.749` baris log) | **`< 35 ms`** via `PortIndex.quick` (**`0` baris** di `terminalLines`) | Headless benchmark Release `-O` |
| **Render `MarkdownStyler.style()` (`AGENTS.md`)** | `65,19 ms` setiap klik | **`< 15 ms` cold / `< 0,2 ms` cached** | Microbenchmark Release `-O` |
| **Physical Footprint RAM (Jendela Terbuka)** | `48,3 MB` (Peak `65,7 MB`) | **`< 25 MB`** | `vmmap -summary <pid>` |
| **Physical Footprint RAM (Setelah `Cmd+W`, Ikon Dock Tetap Aktif)** | `48,3 MB` | **`< 14 MB`** | `vmmap -summary <pid>` setelah `Cmd+W` |
| **Beban CPU Idle (Termasuk di Tab `LogsView` & Saat Tertutup)** | Bangun tiap `2.0s` baca `250 KB` | **`0.0%` CPU idle** | `top -l 2 -pid <pid>` |
| **Ukuran Bundel `MacPorts Control Center.app`** | `5,3 MB` (Binary `4,3 MB`) | **`< 2,0 MB`** (`codesign` valid) | `./build-app.sh` + `du -sh` + `codesign -vv` |

---

## 3. Tech Stack & Perintah Eksekusi Standar (*Commands*)

- **Bahasa & Framework:** Apple Swift 5.7+ (`SwiftUI`, `AppKit`, `Foundation`, `Combine`, `SQLite3`, `UniformTypeIdentifiers`), target minimum `macOS 12.0`.
- **Toolchain Host:** Xcode Command Line Tools (`/usr/bin/swiftc`, `/usr/bin/strip`, `/usr/bin/lipo`, `/usr/bin/codesign`, `/usr/bin/sips`, `/usr/bin/iconutil`) — **tanpa ketergantungan Xcode IDE penuh maupun library pihak ketiga**.

### Perintah Kompilasi & Eksekusi Unit Test (Tanpa Xcode IDE / `XCTest.framework`)
Karena host menggunakan Command Line Tools (modul `XCTest` tidak tersedia, sehingga suite memakai shim `XCTestCase` di `MacPortsServiceTests.swift` dan entry point `@main` di `TestRunnerMain.swift`), kompilasi dan jalankan pengujian dengan perintah berikut:

```bash
SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")"
swiftc -target "$(uname -m)-apple-macos12.0" \
    -sdk "${SDK_PATH}" \
    -parse-as-library \
    Sources/MacPortsControlCenter/Models/*.swift \
    Sources/MacPortsControlCenter/Services/*.swift \
    Sources/MacPortsControlCenter/Views/*.swift \
    Tests/MacPortsControlCenterTests/*.swift \
    -lsqlite3 \
    -o /tmp/run-all-tests && TEST_RUNNER=1 /tmp/run-all-tests
```

### Perintah Kompilasi Bundel Release `.app`
```bash
./build-app.sh              # Build arsitektur native host (uname -m) + dead_strip + strip -x (<2.0 MB)
./build-app.sh --universal  # Build Universal Binary (x86_64 + arm64 via lipo)
./build-app.sh --install    # Build dan pasang ke /Applications
```

---

## 4. Peta Struktur Berkas yang Dimodifikasi (*Project Structure*)

Tidak ada target baru atau dependensi eksternal baru. Seluruh perubahan terfokus pada berkas yang sudah ada:

```text
/Users/adijaya/MyFiles/Projects/macports-control-center/
├── build-app.sh                                                        # [PERF-12] Deteksi uname -m, opsi --universal, -dead_strip, strip -x, -lsqlite3
├── scripts/generate_icon.sh                                            # [PERF-12] Hapus ICC profile & batasi/kompres PNG agar .icns < 400 KB
├── Resources/AppIcon.icns                                              # [PERF-12] Aset ikon yang telah dioptimasi (< 400 KB)
├── Sources/
│   ├── MacPortsControlCenter/
│   │   ├── Models/
│   │   │   └── AppState.swift                                          # [PERF-01,05,06,07,09,10,13,14] Paralel refreshAll, cache, equality guard, deterministic IDs
│   │   ├── Services/
│   │   │   ├── CommandRunner.swift                                     # [PERF-01,03,04,14] O(N) StreamCollector, logToTerminal, batch coalescing 30fps, clean queueTail
│   │   │   ├── MacPortsService.swift                                   # [PERF-05,06,13] Native SQLite registry.db, /opt/local/etc/select, PortIndex.quick + fallback
│   │   │   └── DoctorService.swift                                     # [PERF-13] Validasi username ASCII tanpa kompilasi regex berulang
│   │   └── Views/
│   │       ├── MainWindowView.swift                                    # [PERF-09] Hapus duplikasi .environmentObject(appState)
│   │       ├── TerminalDrawerView.swift                                # [PERF-02] Incremental NSTextStorage.append via Coordinator tanpa .joined()
│   │       ├── PackagesView.swift                                      # [PERF-06,10] Paginasi ringan 200 item (Load More) & Task cancellation
│   │       ├── LogsView.swift                                          # [PERF-08] DispatchSource kqueue watcher, potong di batas \n, debounce filter
│   │       ├── DocsView.swift                                          # [PERF-07,11] Fast-path teks polos, static regex, cache NSAttributedString, single layout pass
│   │       ├── DatabaseView.swift                                      # [PERF-10,13] Gunakan state socket/engine ter-cache & validasi nama DB ASCII
│   │       ├── PHPManagerView.swift                                    # [PERF-10,14] Load php.ini async & hindari I/O sinkron di klik kartu
│   │       └── SitesView.swift                                         # [PERF-10] Gunakan LazyVStack untuk daftar virtual host
│   └── MacPortsControlCenterApp/
│       └── MainApp.swift                                               # [PERF-01,07,09] Teardown NSHostingView saat Cmd+W (tetap .regular di Dock), cache NSImage MenuBar, drawer terlipat di awal
└── Tests/
    └── MacPortsControlCenterTests/
        ├── CommandRunnerTests.swift                                    # Unit test StreamCollector O(N), logToTerminal: false, coalescing
        ├── MacPortsServiceTests.swift                                  # Unit test SQLite reader, filesystem select reader, PortIndex Tcl parser
        ├── AppStateTests.swift                                         # Unit test ID stabil PaletteCommand, cache MarkdownStyler, LogFileTailer UTF-8 boundary
        └── TestRunnerMain.swift                                        # Registrasi seluruh fungsi unit test baru untuk Command Line Tools
```

---

## 5. Keputusan Desain Terkunci & Spesifikasi Teknis per Sub-Sistem

### A. Mesin Eksekusi & Streaming Terminal (`PERF-01`, `PERF-02`, `PERF-03`, `PERF-04`, `PERF-14b`)

1. **`StreamCollector` Zero-Copy $O(N)$ (`CommandRunner.swift`):**
   - Tambahkan properti `let splitLines: Bool` (default `true`).
   - Jika `splitLines == false` (digunakan saat `logToTerminal == false` dan `onLine == nil`), `appendData(_:)` hanya menambahkan chunk ke `allBytes` di bawah `NSLock` dan langsung mengembalikan `[]` tanpa mencari `\n` atau mendekode `String` per potongan; dekode UTF-8 hanya dilakukan sekali pada `finish()`.
   - Jika `splitLines == true`, pindai `byteBuffer` sekali menggunakan `withUnsafeBytes` dan indeks `cursor = 0..<count`: setiap ketemu byte `0x0A` (`\n`), abaikan `0x0D` (`\r`) di ujung baris, dekode slice `bytes[lineStart..<lineEnd]` menjadi `String`, dan majukan `lineStart = idx + 1`. Di akhir loop, hanya simpan ekor sisa `byteBuffer = (lineStart == 0) ? byteBuffer : (lineStart < count ? Data(byteBuffer[lineStart...]) : Data())` **satu kali per chunk pipe**, bukan per baris.

2. **Pemisahan Aksi Mutasi vs Kuery Latar Belakang (`PERF-01`):**
   - Perbarui tanda tangan dengan nilai default yang 100% kompatibel mundur:
     ```swift
     public func runShell(
         _ command: String,
         label: String,
         serialized: Bool = true,
         logToTerminal: Bool = true
     ) async -> CommandResult

     public func run(
         executable: String,
         arguments: [String],
         label: String,
         serialized: Bool = true,
         logToTerminal: Bool = true,
         onLine: ((String) -> Void)? = nil
     ) async -> CommandResult
     ```
   - Ketika `logToTerminal == false`:
     - **Jangan** mencatat baris `$ <command>`, `stdout`, maupun `stderr` ke `terminalLines`.
     - **Jangan** mengubah `isRunning`, `currentCommandLabel`, atau mendaftarkan proses ke `activeProcesses` (sehingga refresh latar belakang tidak memicu kedipan tombol merah *"Cancel Process"* maupun status oranye *"Updating..."* di Menu Bar).
     - **Tetap jalankan** blok shortcut `ProcessInfo.processInfo.environment["TEST_RUNNER"] == "1"` persis seperti sebelumnya agar pengujian headless tidak pernah mengeksekusi `port` atau `mysql` sungguhan bila dipanggil dalam mode test.
   - Ketika `logToTerminal == true` (default untuk semua perintah mutasi seperti `port install/uninstall/load/unload/reload/activate/deactivate/upgrade/selfupdate/select`, `mysqldump`, `mysql <`, `CREATE/DROP DATABASE`, `sudo /bin/cp`, `chmod`, `osascript`):
     - Panggil closure opsional `public var onMutationCommandStart: (() -> Void)?` pada `@MainActor` tepat saat proses mutasi dimulai.
     - Di `AppDelegate`, daftarkan `state.isTerminalDrawerExpanded = false` saat aplikasi GUI pertama kali diluncurkan (sementara nilai default properti di `AppState` tetap `true` demi menjaga `testInitialStateProperties`), dan set `state.commandRunner.onMutationCommandStart = { [weak state] in state?.isTerminalDrawerExpanded = true }` sehingga *Terminal Drawer* otomatis membentang saat perintah mutasi berjalan!

3. **Batching Baris, *Coalescing* 30fps, Urutan Deterministik, & Pembersihan `queueTail` (`PERF-03`, `PERF-14b`):**
   - Tambahkan `@Published public private(set) var terminalGeneration: Int = 0` pada `CommandRunner`.
   - Sediakan antrean sementara `pendingLines: [String]` di `@MainActor` yang di-*flush* ke `terminalLines` secara terkelompok maksimal setiap `33 ms` (~30 fps) selama proses masih berjalan, **dan wajib di-*flush* secara sinkron di `@MainActor` tepat setelah proses selesai** (sebelum `execute(...)` mengembalikan `CommandResult`) menggunakan satu antrean serial `pipeCallbackQueue` untuk pembacaan pipe dan `readDataToEndOfFile()` sehingga urutan baris terjamin 100% berurutan dan seluruh unit test langsung melihat semua baris di `terminalLines` begitu `await runShell(...)` kembali.
   - Pangkas `terminalLines` dengan *hysteresis*: hanya saat `terminalLines.count > 5500`, hapus kelebihannya sehingga tersisa `5000` baris (`removeFirst(terminalLines.count - 5000)`) dan naikkan `terminalGeneration += 1` (naikkan juga saat `clearLog()`).
   - Pada antrean serial (`serialized == true`), simpan `let taskID = UUID()` untuk menandai ekor antrean dan bersihkan `queueTail = nil` apabila task yang baru selesai masih merupakan task paling akhir, agar referensi `Task` tidak tertahan di memori saat idle.

4. **Perenderan Inkremental `NSTextStorage` pada `TerminalDrawerView` (`PERF-02`):**
   - Ubah `TerminalTextViewRepresentable` agar menerima `lines: [String]` dan `generation: Int` secara langsung (hapus `runner.terminalLines.joined(separator: "\n")` dari `TerminalDrawerView.body`).
   - `Coordinator` menyimpan `lastGeneration: Int = -1` dan `renderedLineCount: Int = 0`.
   - Di `updateNSView`:
     - Jika `generation != coordinator.lastGeneration` atau `lines.count < coordinator.renderedLineCount` (terjadi `clearLog()` atau pemangkasan *hysteresis*): ganti isi `textStorage` satu kali dari `lines.joined(separator: "\n")`, set `lastGeneration = generation`, dan `renderedLineCount = lines.count`.
     - Jika `lines.count > coordinator.renderedLineCount`: bangun potongan teks hanya untuk `lines[coordinator.renderedLineCount..<lines.count]` (diawali `"\n"` bila `renderedLineCount > 0`), tambahkan via `textStorage.beginEditing()` → `textStorage.append(NSAttributedString(string: chunk, attributes: defaultAttributes))` → `textStorage.endEditing()`, perbarui `renderedLineCount = lines.count`, lalu panggil `textView.scrollToEndOfDocument(nil)`.
     - Jika `lines.count == coordinator.renderedLineCount` dan `generation == coordinator.lastGeneration`: keluar seketika ($O(1)$ no-op).

---

### B. Pembacaan Native MacPorts, Paralelisasi `refreshAll()`, & Mesin Pencarian (`PERF-05`, `PERF-06`, `PERF-13`, `PERF-14a`)

1. **Pembacaan Read-Only `registry.db` via `SQLite3` (`MacPortsService.readInstalledPortsSQLite`):**
   - Impor modul sistem `SQLite3` (tautkan `-lsqlite3` pada `build-app.sh` dan `Package.swift` `linkerSettings: [.linkedLibrary("sqlite3")]`).
   - Buka `/opt/local/var/macports/registry/registry.db` **khusus read-only** dengan URI `"file:\(dbPath)?mode=ro"` dan flag `SQLITE_OPEN_READONLY | SQLITE_OPEN_URI`.
   - Wajib membungkus handle dengan `defer { sqlite3_close(db) }` dan `defer { sqlite3_finalize(stmt) }` agar koneksi ditutup dalam `< 2 ms` dan **tidak pernah menahan lock** terhadap `sudo port install/upgrade`.
   - Jalankan query `SELECT name, version, revision, variants, state FROM ports WHERE state IN ('installed', 'imaged');` (tanpa `ORDER BY version` di SQL agar tidak memicu custom collation `VERSION` milik MacPorts).
   - Bersihkan tanda kutip tunggal pembungkus pada kolom `version` (`ver.trimmingCharacters(in: CharacterSet(charactersIn: "'"))`), susun string versi `"@\(cleanVer)_\(revision)\(variants)"`, set `isActive = (state == "installed")`, urutkan di Swift dengan `localizedCaseInsensitiveCompare`, dan kembalikan `[PortPackageItem]`. Jika file tidak ada atau bukan `SQLITE_OK`, kembalikan `nil` agar pemanggil otomatis jatuh kembali (*fallback*) ke `/opt/local/bin/port` `["installed"]`.

2. **Pembacaan Direktori `/opt/local/etc/select/` via `FileManager` (`MacPortsService.readPortSelectGroupsFilesystem`):**
   - Pindai subdirektori non-tersembunyi di `/opt/local/etc/select` secara terurut.
   - Untuk setiap grup `<group>`: baca target symlink `current` via `destinationOfSymbolicLink(atPath:)` (ambil komponen nama berkas terakhirnya; jika symlink tidak ada, bernilai `"none"`).
   - Kumpulkan berkas opsi di dalam `<group>` selain `"base"`, `"current"`, dan berkas berawalan `"."`. Urutkan nama opsi secara alfabetis dengan menempatkan `"none"` selalu di urutan paling akhir (mis. `["mariadb-10.11", "mariadb-11.4", "none"]`) agar hasilnya 100% identik dengan `MacPortsService.parsePortSelectSummary`. Kembalikan `nil` bila direktori `/opt/local/etc/select` tidak dapat diakses agar pemanggil jatuh kembali ke `/opt/local/bin/port` `["select", "--summary"]`.

3. **Mesin Pencarian Paket Native `PortIndex.quick` + `PortIndex` (`MacPortsService.searchPortsNativeIndex`):**
   - Jika kueri mengandung karakter pola glob/regex (`*`, `?`, `[`, `]`, `^`, `$`, `\`), langsung kembalikan `nil` agar `AppState` menjalankan fallback `/opt/local/bin/port` `["search", "--name", "--line", query]`.
   - Resolusi lokasi berkas `PortIndex` & `PortIndex.quick` dari `/opt/local/etc/macports/sources.conf`:
     - Dukung entri `file:///path/ke/ports` → `/path/ke/ports/PortIndex`
     - Dukung entri `rsync://host/jalur/ports.tar` atau `rsync://host/jalur/ports/` → `/opt/local/var/macports/sources/<host>/<jalur_tanpa_akhiran_.tar>/PortIndex` (dengan fallback langsung ke jalur standar `/opt/local/var/macports/sources/rsync.macports.org/macports/release/tarballs/ports/PortIndex` jika ada).
   - Pindai `PortIndex.quick` di memori secara linear dalam byte UTF-8 (tiap baris berformat `<nama_lowercase> <byte_offset>\n`), cocokkan apakah `<nama_lowercase>` memuat `query.lowercased()`.
   - Untuk setiap offset yang cocok, lakukan `FileHandle.seek(toFileOffset: offset)` pada `PortIndex`, baca baris header `<NamaAsli> <panjangByte>\n` diikuti tepat `<panjangByte>` byte data Tcl dictionary di bawahnya.
   - Ekstrak field `version`, `categories`, dan `description` menggunakan tokenizer daftar Tcl ringan `MacPortsService.parseTclPortIndexRecord(_ record: String)` yang mendukung nilai ber-kurung kurawal berimbang `{...}` (termasuk kurung bersarang `{{...}}` dan karakter escape `\`) maupun token kata tunggal tanpa kurung. Gabungkan dengan peta `installed` dan himpunan `outdated` untuk menghasilkan `[PortPackageItem]` terurut berdasarkan nama.

4. **Paralelisasi `AppState.refreshAll()`, Cache Paket, & Deduplikasi Proses (`AppState.swift`):**
   - Jalankan pengambilan data secara konkuren (`async let`) tanpa `/bin/zsh -c` dan dengan `logToTerminal: false`:
     - Satu panggilan `/bin/ps` dengan argumen `["-axo", "command"]` dipakai bersama oleh `discoverLaunchDaemons` dan pendeteksian proses `phpXY-fpm`.
     - Satu pembacaan `installedPorts` (`readInstalledPortsSQLite()` atau fallback CLI) dipakai untuk membangun `phpVersions`, `installedDatabaseEngines`, sekaligus mengisi `cachedInstalledPorts`!
     - Satu pembacaan `selectGroups` (`readPortSelectGroupsFilesystem()` atau fallback CLI) dipakai bersama untuk `phpVersions` (`defaultPHP`) dan `portSelectGroups`.
     - Cek keberadaan `/tmp/mysql.sock` (`DoctorService.isMySQLSocketPresent`) terlebih dahulu; hanya panggil `/opt/local/bin/mysql` (`["-u", "root", "--socket=\(defaultSocketPath)", "-N", "-B", "-e", "SHOW DATABASES;"]`, `logToTerminal: false`) apabila socket tersedia.
     - Pembacaan berkas `.conf` virtual host (`ConfigFileService.parseVHost`) dan berkas kesehatan `DoctorService` dijalankan di fungsi helper *nonisolated* / background task, lalu seluruh properti `@Published` di `AppState` diperbarui di `@MainActor` memakai penjaga kesamaan (`if self.prop != newProp { self.prop = newProp }`) agar refresh tanpa perubahan status tidak memicu re-render SwiftUI.
   - Cache `cachedInstalledPorts: [PortPackageItem]?` dan `cachedOutdatedPorts: Set<String>?` di `AppState`. Invalidate keduanya pada setiap aksi mutasi paket (`refreshAfterPackageChange`, `installPHPBundle`, `togglePHPExtension`, `uninstallPHPVersion`, `installDatabaseEngine`, `setupDnsmasq`, `setupMkcert`, `setupRedis`, `setupFnmAndComposer`, `runSelfUpdate`, `runUpgradeOutdated`, `runUninstallLeaves`).
   - Pada `stopAllServices()`, gabungkan seluruh nama service yang sedang berjalan ke dalam satu eksekusi `sudo -n /opt/local/bin/port unload <svc1> <svc2> ...` (tetap `logToTerminal: true`, `serialized: true`).

---

### C. Siklus Hidup Jendela Utama, Menu Bar, & `LogsView` Event-Driven (`PERF-07`, `PERF-08`, `PERF-09`)

1. **Pelepasan Memori Saat `Cmd+W` Sambil Mempertahankan Ikon Dock (`.regular`) (`MainApp.swift`):**
   - Ketika pengguna menutup jendela utama (`windowShouldClose(_ sender: NSWindow) -> Bool`):
     1. Kirim `NotificationCenter.default.post(name: .mpccMainWindowDidClose, object: nil)` agar view aktif seperti `LogsView` segera menutup file descriptor `DispatchSource`.
     2. Simpan posisi jendela `sender.saveFrame(usingName: "MacPortsControlCenterMainWindow")`.
     3. Lepaskan hirarki view & backing store CoreAnimation: `sender.delegate = nil`, `sender.contentView = nil`, `sender.orderOut(nil)`, dan `self.mainWindow = nil`.
     4. Panggil `appState.purgeTransientCachesForBackground()` yang mengosongkan `selectedDocContent = ""`, memanggil `MarkdownStyler.clearCache()`, dan membersihkan hasil pencarian ribuan paket non-installed (jika `packageSearchQuery` tidak kosong).
     5. **Pertahankan `NSApp.setActivationPolicy(.regular)`** sehingga ikon aplikasi **tetap tampil di Dock dan `Cmd+Tab`**.
   - Ketika `showMainWindow()` dipanggil (baik dari klik ikon di Dock melalui `applicationShouldHandleReopen` maupun dari item `"Open Control Center"` di Menu Bar): apabila `self.mainWindow == nil`, panggil `createAndShowMainWindow()` untuk merekonstruksi `NSWindow` + `NSHostingView` baru dari `appState` yang masih hidup.

2. **Deduplikasi `MenuBarController` & Cache `NSImage` (`MainApp.swift`):**
   - Buat kamus statis `statusImages: [StackStatus: NSImage]` berisi 4 gambar lingkaran indikator (`12×12`) yang digambar satu kali saja saat inisialisasi.
   - Ganti langganan `appState.objectWillChange` dengan `Publishers.CombineLatest3(appState.$services, appState.$isLoading, appState.commandRunner.$isRunning)` yang dipetakan ke `StackStatus` (wajib menjadikan `StackStatus: Equatable`), difilter dengan `.removeDuplicates()`, dan diterima di `DispatchQueue.main`.
   - Hapus penyuntikan ganda `.environmentObject(appState)` di `MainWindowView.swift`.

3. **Pemantau Log Kernel `DispatchSource` (`kqueue`) & Potongan UTF-8 Bersih (`LogsView.swift`):**
   - Ekstrak pengelola pembacaan & pemantauan log ke kelas `@MainActor final class LogFileTailer: ObservableObject` di `LogsView.swift` agar dapat diuji unit secara deterministik:
     - Saat membaca ekor berkas berukuran `> 250 KB` (`maxBytesToRead = 250 * 1024`), mulai baca dari `fileSize - maxBytesToRead`, lalu cari indeks byte `0x0A` (`\n`) pertama di dalam `Data` dan buang potongan baris parsial di depannya agar teks selalu dimulai pada awal baris utuh tanpa karakter UTF-8 multi-byte yang terbelah!
     - Simpan sidik jari berkas `(inode: UInt64, size: UInt64, mtime: Date)` sehingga pembacaan ulang pada berkas yang tidak berubah dilewati dalam $O(1)$.
     - Gunakan `DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.extend, .write, .attrib, .delete, .rename], queue: .main)` saat `isAutoTailEnabled == true` dan berkas ada. Jika event `.delete` atau `.rename` muncul (rotasi log), tutup source lama dan buka kembali. Hanya gunakan timer ringan pengecekan keberadaan berkas (`3.0s`) apabila berkas target belum ada di disk, lalu segera matikan timer begitu `DispatchSource` aktif.
     - Hentikan seluruh `DispatchSource` / timer dan tutup `fd` pada `onDisappear`, saat `isAutoTailEnabled` dimatikan, maupun saat menerima `.mpccMainWindowDidClose` (**jaminan `0.0%` CPU idle**).
     - Debounce pencarian `filterQuery` selama `150 ms` melalui `Task` yang dapat dibatalkan, dan simpan hasil `displayedText` di `@Published` agar `LogsView.body` tidak pernah memanggil `components(separatedBy:)` di setiap render.

---

### D. Optimasi `MarkdownStyler`, Virtualisasi View, & Ukuran Bundel (`PERF-10`, `PERF-11`, `PERF-12`, `PERF-13b`)

1. **`MarkdownStyler` Fast-Path & Cache (`DocsView.swift`):**
   - Kompilasi `orderedListRegex` (`^(\d+\.)\s+(.*)$`) dan `brTagRegex` (`<br\s*/?>`) satu kali sebagai `private static let`.
   - Tambahkan *fast-path* awal di `decodeHTMLEntities` (`guard raw.contains("&") else { return raw }`) dan `cleanCellText` (`if text.contains("<")`).
   - Tambahkan pemeriksa karakter inline Markdown (`private static func containsInlineMarkdownSyntax(_ s: String) -> Bool` yang mengecek keberadaan salah satu karakter `` `*_[~\ ``). Baris paragraf, daftar, blockquote, dan sel tabel yang **tidak** mengandung karakter tersebut langsung membangun `NSAttributedString` dengan font & paragraf standar tanpa memanggil `AttributedString(markdown:)`.
   - Sediakan cache di memori `MarkdownStyler.cachedStyle(for key: String, markdown: String) -> NSAttributedString` yang diindeks berdasarkan `(key, markdown.utf8.count, markdown.hashValue)` serta `MarkdownStyler.clearCache()`, sambil mempertahankan `public static func style(_ markdown: String) -> NSAttributedString` murni untuk kompatibilitas penuh unit test.
   - Di `DocsView.onAppear`, panggil `appState.ensureSelectedDocLoaded()`. Di `DocsScrollView` & `MarkdownTextViewRepresentable`, hindari pemanggilan ganda `ensureLayout(for:)` pada lebar yang sama.

2. **ID Deterministik `PaletteCommand`, Paginasi `PackagesView`, & Penghapusan I/O di `View.body` (`PERF-10`):**
   - Berikan `id` eksplisit dan deterministik untuk seluruh `PaletteCommand` di `AppState.buildPaletteCommands()` (`"nav-\(section.rawValue)"`, `"action-restart-stack"`, `"php-cli-\(php.portName)"`, dst.).
   - Di `PackagesView`, tambahkan `@State private var visibleLimit: Int = 200` (direset ke `200` setiap kali `searchInput` atau `selectedFilter` berubah) dan tombol **"Show More Packages (... remaining)"** yang menambah `+200` item per klik, serta batalkan `Task` pencarian sebelumnya bila pengguna memicu pencarian baru.
   - Di `DatabaseView`, baca `appState.isMySQLSocketConnected` dan `appState.installedDatabaseEngines` tanpa memanggil `FileManager.fileExists` di dalam `body`, serta ganti regex `CreateDatabaseSheet.isValidDbName` dengan pengecekan karakter ASCII langsung.
   - Di `PHPManagerView`, muat `loadQuickTuning` secara asinkron di background task saat versi PHP berubah. Di `SitesView`, ganti `VStack` daftar vhost menjadi `LazyVStack`.

3. **Optimasi Ukuran Binary & `AppIcon.icns` (`PERF-12`):**
   - Pada [`build-app.sh`](file:///Users/adijaya/MyFiles/Projects/macports-control-center/build-app.sh):
     - Deteksi arsitektur host secara dinamis `HOST_ARCH="$(uname -m)"` (`x86_64` atau `arm64`) sebagai target default `-target "${HOST_ARCH}-apple-macos12.0"`.
     - Tambahkan opsi `--universal` yang mengompilasi `x86_64-apple-macos12.0` dan `arm64-apple-macos12.0` secara terpisah lalu menggabungkannya dengan `lipo -create`.
     - Tambahkan flag `-lsqlite3 -Xlinker -dead_strip` pada `swiftc`, dan jalankan `strip -x "${MACOS_DIR}/${BINARY_NAME}"` **sebelum** `codesign --force --deep --sign -`.
   - Pada [`scripts/generate_icon.sh`](file:///Users/adijaya/MyFiles/Projects/macports-control-center/scripts/generate_icon.sh) dan [`Resources/AppIcon.icns`](file:///Users/adijaya/MyFiles/Projects/macports-control-center/Resources/AppIcon.icns):
     - Hapus metadata profil warna ICC (`sips --deleteColorManagementProperties`) pada seluruh PNG di iconset. Jika `pngquant` tersedia di sistem, kompres palet seluruh ukuran hingga `1024×1024`; jika tidak tersedia (standar Command Line Tools murni), hasilkan ukuran standar Retina lengkap hingga `512×512` (`icon_16x16` s/d `icon_256x256@2x` dan `icon_512x512`) sehingga ukuran `Resources/AppIcon.icns` turun dari `924 KB` ke **`~374 KB`** dan ukuran total `MacPorts Control Center.app` mencapai **`~1,9 MB` (`< 2,0 MB`)**.

---

## 6. Strategi Pengujian & Batasan Operasional (*Testing Strategy & Boundaries*)

### Strategi Pengujian
1. **Regresi 0% terhadap 42 Unit Test Lama:** Seluruh pengujian di `MacPortsServiceTests` (5), `CommandRunnerTests` (6), `ConfigFileServiceTests` (8), `DoctorAndDatabaseTests` (6), dan `AppStateTests` (17) wajib tetap utuh dan lulus tanpa mengubah ekspektasi asersi.
2. **Unit Test Baru Terarah:** Setiap komponen baru wajib diuji dengan unit test deterministik (menggunakan berkas sementara di `NSTemporaryDirectory()`, termasuk pembuatan database SQLite uji sementara untuk `readInstalledPortsSQLite`, direktori symlink uji untuk `readPortSelectGroupsFilesystem`, indeks mini `PortIndex.quick` + `PortIndex` untuk `searchPortsNativeIndex`, chunk UTF-8 terpotong untuk `StreamCollector` & `LogFileTailer`, serta verifikasi ID stabil `PaletteCommand` dan `logToTerminal: false`), dan **seluruh fungsi test baru wajib didaftarkan di `Tests/MacPortsControlCenterTests/TestRunnerMain.swift`**.
3. **Verifikasi Benchmark & Memori Host:** Di akhir implementasi, jalankan benchmark kompilasi `-O -whole-module-optimization` serta verifikasi `vmmap -summary`, `top`, `du -sh`, dan `codesign --verify --verbose`.

### Batasan (*Boundaries*)
- **Selalu Lakukan (*Always*):**
  - Jalankan kompilasi & seluruh unit test (`TEST_RUNNER=1 /tmp/run-all-tests`) di akhir setiap task sebelum `git commit`.
  - Buka `registry.db` hanya dengan `SQLITE_OPEN_READONLY | SQLITE_OPEN_URI` (`mode=ro`) dan tutup handle segera dengan `defer`.
  - Sediakan fallback otomatis ke CLI `/opt/local/bin/port` apabila pembacaan native SQLite / `/opt/local/etc/select` / `PortIndex.quick` mengembalikan `nil`.
  - Pertahankan ikon aplikasi tetap muncul di Dock (`.regular`) ketika jendela utama ditutup (`Cmd+W`).
- **Tanyakan Terlebih Dahulu (*Ask First*):**
  - Menambah dependensi eksternal di `Package.swift` atau mengubah skema konfigurasi host di `/opt/local/etc/`.
- **Dilarang Keras (*Never*):**
  - Menghapus, melewati, atau melemahkan satu pun dari 42 unit test yang sudah ada.
  - Menggunakan `sudo` saat menulis ke `/opt/local/etc/nginx/servers/`.
  - Melewatkan validasi `/opt/local/sbin/nginx -t` sebelum reload Nginx, atau mengubah user PHP-FPM menjadi `nobody`/`_www`.
  - Menyembunyikan aplikasi ke `.accessory` (menghilangkan ikon Dock) saat `Cmd+W`.
