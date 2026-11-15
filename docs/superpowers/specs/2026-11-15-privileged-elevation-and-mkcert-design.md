# Privileged Elevation & In-App mkcert Setup Design

**Author:** AI Assistant & Adi Jaya  
**Date:** 2026-11-15  
**Status:** Approved  
**Scope:** Small Change  

---

## 1. Intent & Context

Pada aplikasi MacPorts Control Center, fitur *1-Click Ecosystem Utilities* pada tab Services menyediakan utilitas pendukung web development lokal seperti `dnsmasq`, `mkcert`, `redis`, dan `fnm`/`composer`.

Sebelumnya, perintah `setupMkcert()` menggunakan `commandRunner.openExternalTerminal(command: "echo '=== Setup mkcert Root CA ===' && mkcert -install")` yang secara otomatis membuka jendela aplikasi `Terminal.app` eksternal. Hal ini dilakukan karena binary `mkcert` (Go CLI) secara default memanggil `sudo security add-trusted-cert ...` yang menuntut sesi TTY interaktif untuk meminta password administrator, sementara runner di dalam aplikasi bersifat non-interaktif (*no controlling TTY*).

Di sisi lain, fitur seperti penyiapan `/etc/resolver/test` pada `dnsmasq` dan *Doctor Auto-Fix* menggunakan popup dialog password native macOS melalui:
```bash
/usr/bin/osascript -e 'do shell script "..." with administrator privileges'
```

Tujuan desain ini adalah mengalihkan `setupMkcert()` ke dialog popup password native macOS (*in-app*), merapikan eksekusi penulisan file `dnsmasq.conf` agar tidak memicu error `sudo: a password is required`, serta tetap mempertahankan method `openExternalTerminal` untuk kebutuhan sesi interaktif nyata dan tombol manual *"Open in Terminal"*.

---

## 2. Goals, Non-Goals, and Anti-Goals

### Goals
- Mengeliminasi pembukaan otomatis `Terminal.app` saat pengguna menekan tombol **Install & Setup mkcert** / **Re-setup mkcert CA**.
- Menjalankan `mkcert -install` secara mulus di dalam aplikasi menggunakan dialog popup password native macOS (*Authorization Services via osascript*).
- Memastikan Root CA yang dibuat tetap berada di direktori pengguna (`~/Library/Application Support/mkcert`), bukan di `/var/root`, serta dimiliki oleh `currentUser:staff`.
- Memperbaiki `setupDnsmasq()` agar penulisan `/opt/local/etc/dnsmasq.conf` dan pembuatan `/etc/resolver/test` berada dalam satu transaksi elevasi privilese (menghilangkan pesan gagal `sudo -n /bin/cp: a password is required`).
- Menjaga method `openExternalTerminal()` di `CommandRunner.swift` tetap utuh untuk tombol manual di Terminal Drawer.

### Non-Goals
- Menghapus method `openExternalTerminal()` dari `CommandRunner.swift`.
- Mengubah arsitektur privilege `sudoers` global macOS (tidak menambahkan rule NOPASSWD untuk `/usr/bin/security`).
- Mengubah tampilan UI tombol pada `ServicesView.swift`.

### Anti-Goals
- Menjalankan `mkcert -install` tanpa menentukan `CAROOT`, yang akan menyebabkan Root CA tersimpan di `/var/root/Library/...` dan mematahkan validasi SSL lokal untuk browser pengguna biasa.
- Mengunci UI atau membiarkan aplikasi freeze saat pengguna menekan tombol "Cancel" pada dialog popup password.

---

## 3. Approaches Considered & Trade-offs

### Pendekatan A: Tetap Membuka Terminal Eksternal (*Status Quo*)
- **Deskripsi:** Membiarkan `commandRunner.openExternalTerminal` membuka Terminal.app untuk mengetik password `sudo`.
- **Alasan Ditolak:** Merusak alur pengguna (*window switching*), tidak konsisten dengan tombol `dnsmasq` dan *Doctor Auto-Fix* yang memiliki popup dialog native.

### Pendekatan B: In-App Privileged via `osascript` dengan `CAROOT` Explicit (Dipilih)
- **Deskripsi:** 
  1. Jalankan `port install mkcert` (sudah passwordless via `NOPASSWD: /opt/local/bin/port`).
  2. Susun skrip bash: `mkdir -p '$CAROOT' && CAROOT='$CAROOT' /opt/local/bin/mkcert -install && chown -R $USER:staff '$CAROOT'`.
  3. Bungkus skrip dengan `DoctorService.buildOsascriptAdminCommand(shellScript:)` dan jalankan via `commandRunner.run`.
- **Trade-off & Mengapa Dipilih:**
  - Hanya 1x popup password native macOS.
  - Saat dijalankan lewat `osascript ... with administrator privileges`, proses berstatus root (UID 0).
  - Berdasarkan source code `mkcert` (`commandWithSudo`), jika UID 0, `mkcert` langsung mengeksekusi `/usr/bin/security add-trusted-cert` tanpa memanggil `sudo` lagi, sehingga tidak butuh TTY terminal.
  - Memberikan pengalaman 100% *in-app* dengan output streaming di drawer terminal.

### Pendekatan C: Menambahkan NOPASSWD untuk `/usr/bin/security` di `/etc/sudoers.d/macports`
- **Deskripsi:** Menghilangkan password prompt sepenuhnya dengan memberikan hak sudo tanpa password untuk perintah security.
- **Alasan Ditolak:** Risiko keamanan tinggi (*security vulnerability*) karena sembarang skrip lokal dapat menyusupkan sertifikat tanpa sepengetahuan pengguna.

---

## 4. Technical Specifications & Interface Changes

### 4.1. Helper Builder di `DoctorService.swift`
Menambahkan dua builder murni yang dapat diuji (*pure & testable*):

```swift
/// Builds shell command to install mkcert CA into system trust store using user CAROOT
public static func buildMkcertInstallScript(currentUser: String, carootPath: String) -> String

/// Builds privileged script to configure dnsmasq.conf and create /etc/resolver/test atomically
public static func buildDnsmasqPrivilegedSetupScript(
    dnsmasqConfPath: String = "/opt/local/etc/dnsmasq.conf",
    appendConfig: String = "\naddress=/.test/127.0.0.1\nlisten-address=127.0.0.1\n",
    resolverDir: String = "/etc/resolver",
    resolverFile: String = "/etc/resolver/test",
    nameserverEntry: String = "nameserver 127.0.0.1"
) -> String
```

### 4.2. Perubahan di `AppState.swift`

- **`setupMkcert()`**:
  ```swift
  public func setupMkcert() async {
      _ = await commandRunner.runShell("sudo -n /opt/local/bin/port install mkcert", label: "install-mkcert")
      let currentUser = NSUserName()
      let carootPath = ("~/Library/Application Support/mkcert" as NSString).expandingTildeInPath
      let script = DoctorService.buildMkcertInstallScript(currentUser: currentUser, carootPath: carootPath)
      let adminArgs = DoctorService.buildOsascriptAdminCommand(shellScript: script)
      _ = await commandRunner.run(executable: DoctorService.osascriptBinary, arguments: adminArgs, label: "setup-mkcert-ca")
      invalidatePackageCaches()
  }
  ```

- **`setupDnsmasq()`**:
  Menghilangkan pemanggilan `writeConfigFile(content: newConf, targetPath: dnsmasqConfPath)` yang gagal dengan `sudo: a password is required`. Sebagai gantinya, jika direktori/file belum memuat `address=/.test/127.0.0.1`, masukkan instruksi append ke dalam satu skrip `buildDnsmasqPrivilegedSetupScript` yang dieksekusi via `osascript`.

---

## 5. Verification & Testing

1. **Unit Tests:**
   - Uji `DoctorService.buildMkcertInstallScript` dengan variasi user dan path (termasuk spasi dan karakter path normal).
   - Uji `DoctorService.buildDnsmasqPrivilegedSetupScript` memastikan sintaks append dan resolver creation valid dan aman.
   - Uji `DoctorAndDatabaseTests` lulus seluruhnya.
2. **Build Test:**
   - Jalankan `./build-app.sh` untuk memastikan kompilasi bundle ad-hoc codesigned berhasil.
3. **Smoke Verification:**
   - Eksekusi test suite via `TEST_RUNNER=1 /tmp/run-all-tests`.
