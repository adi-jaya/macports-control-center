# GitHub Tag, Release, & Versioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menetapkan standar Semantic Versioning (`vX.Y.Z`), membuat `CHANGELOG.md` (Keep a Changelog), menyediakan skrip otomasi rilis lokal `scripts/release.sh` dengan dukungan publish via `gh` CLI, memperbarui SOP di `AGENTS.md` & `README.md`, serta merilis versi perdana `v1.0.0` ke GitHub Releases.

**Architecture:** Menggunakan pendekatan rilis berbasis Git Tag teranotasi dan GitHub CLI (`gh`). Skrip shell `scripts/release.sh` mengotomasi siklus rilis lokal: validasi git status, eksekusi unit test suite, sinkronisasi versi `Info.plist`, validasi entri `CHANGELOG.md`, kompilasi ulang bundel aplikasi, pembuatan git commit & annotated tag, serta opsi `--publish` untuk push dan publikasi release notes ke GitHub via `gh release create`.

**Tech Stack:** POSIX Bash, Apple Property List (plutil/sed), Git, GitHub CLI (`gh`), Swift Native build & test tools.

**Spec:** Intent terkonfirmasi dari sesi interview (/grill-me) pada 2026-11-15.

## Global Constraints

- Format Tag: Wajib menggunakan prefix `v` dengan format SemVer: `vMAJOR.MINOR.PATCH` (contoh `v1.0.0`).
- Format Changelog: Mengikuti standar [Keep a Changelog](https://keepachangelog.com/id/1.0.0/) dengan kategori perubahan: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`.
- Bundle Metadata: `Resources/Info.plist` wajib sinkron: `CFBundleShortVersionString` mencerminkan `MAJOR.MINOR.PATCH` tanpa prefix `v`, dan `CFBundleVersion` integer bertambah secara monoton.
- Eksekusi Rilis: Zero-dependency di host macOS Monterey lokal; tidak mengandalkan GitHub Actions runner cloud.
- Token Optimization: Gunakan proxy `rtk` untuk operasi dev git dan shell.

## Review Focus

- Deteksi working tree dirty: Skrip rilis harus menolak berjalan jika ada uncommitted changes di luar perubahan rilis.
- Kegagalan Unit Test: Skrip rilis harus menggagalkan proses sebelum membuat tag jika test suite gagal.
- Ekstraksi Changelog: Skrip harus memotong hanya bagian versi terkait dari `CHANGELOG.md` tanpa menyertakan entri versi lain atau heading global saat upload ke GitHub Release.
- Validasi branch: Memastikan rilis hanya dijalankan dari branch `main`.
- Idempotency & Rollback: Jika build gagal di tengah jalan, perubahan Info.plist dapat dibatalkan dengan aman.

---

### Task 1: Buat `CHANGELOG.md` Root Repositori

**Files:**
- Create: `CHANGELOG.md`
- Test: Verifikasi format markdown dan keterbacaan entri `v1.0.0`

**Interfaces:**
- Consumes: Riwayat fitur yang telah terimplementasi di repositori
- Produces: `CHANGELOG.md` dengan section `[Unreleased]` dan `[1.0.0] - 2026-11-15`

- [ ] **Step 1: Tulis draft `CHANGELOG.md` mengikuti standar Keep a Changelog**
  - Section `[Unreleased]` di bagian atas
  - Section `[1.0.0] - 2026-11-15` mencakup:
    - *Added*: 7 visual tabs (Services & Doctor, Sites, PHP, Databases, Packages, Logs, Docs), Menu Bar extra controller dengan live status indicator & actions, in-app privileged elevation helper untuk `mkcert` & `dnsmasq`, automatic PHP extensions discovery, real-time log tailing, multi-architecture build support (Intel x86_64 + Apple Silicon arm64), zero-dependency Swift native architecture.
    - *Changed*: Migrasi dari legacy web viewer PHP ke aplikasi desktop native SwiftUI + AppKit.
    - *Fixed*: Scrolling di NSTextView Docs/Terminal, instant app switcher transitions, permission handling pada pool PHP-FPM user `adijaya:staff`.
- [ ] **Step 2: Verifikasi file `CHANGELOG.md`**
  - Pastikan format link versioning di bagian footer valid (`[Unreleased]`, `[1.0.0]`).
- [ ] **Step 3: Commit `CHANGELOG.md`**
  ```bash
  git add CHANGELOG.md
  git commit -m "docs: add CHANGELOG.md following Keep a Changelog standard"
  ```

---

### Task 2: Buat Skrip Otomasi Rilis `scripts/release.sh`

**Files:**
- Create: `scripts/release.sh`
- Test: Eksekusi dry-run / validasi argumen dan pengujian unit

**Interfaces:**
- Consumes: `Resources/Info.plist`, `CHANGELOG.md`, `build-app.sh`, unit test suite
- Produces: Perintah rilis `./scripts/release.sh <version> [--publish]`

- [ ] **Step 1: Tulis implementasi `scripts/release.sh`**
  Fitur skrip:
  1. Validasi argumen: `./scripts/release.sh <version> [--publish]` atau `--help`. Sanitasi prefix `v` sehingga `v1.0.1` maupun `1.0.1` diterima.
  2. Validasi branch: Harus berada di branch `main`.
  3. Validasi working directory: Harus bersih (`git diff --quiet` dan `git diff --cached --quiet`).
  4. Validasi entri di `CHANGELOG.md`: Memastikan ada heading `## [${VERSION}]` di `CHANGELOG.md`.
  5. Jalankan test suite: Mengompilasi dan mengeksekusi test suite via `/tmp/run-all-tests` (atau build test runner jika belum ada). Jika ada test yang gagal, abort.
  6. Perbarui versi di `Resources/Info.plist`:
     - Update `CFBundleShortVersionString` ke `$VERSION`.
     - Increment `CFBundleVersion`.
  7. Kompilasi ulang aplikasi: Jalankan `./build-app.sh --universal` untuk memastikan aplikasi terkompilasi bersih.
  8. Git commit & tag:
     - `git add Resources/Info.plist CHANGELOG.md`
     - `git commit -m "chore(release): v${VERSION}"`
     - `git tag -a "v${VERSION}" -m "Release v${VERSION}"`
  9. Ekstraksi release notes untuk GitHub Release: Mengambil konten changelog khusus versi tersebut.
  10. Opsi `--publish`:
      - Push commits: `git push origin main`
      - Push tag: `git push origin "v${VERSION}"`
      - Buat GitHub Release: `gh release create "v${VERSION}" --title "v${VERSION}" --notes-file <temp_notes>`
- [ ] **Step 2: Berikan hak eksekusi `chmod +x scripts/release.sh`**
- [ ] **Step 3: Uji validasi parameter & error handling pada `scripts/release.sh`**
  - Test case: `./scripts/release.sh --help` harus mencetak panduan penggunaan yang jelas.
  - Test case: `./scripts/release.sh` tanpa argumen harus menampilkan pesan error dan usage.
- [ ] **Step 4: Commit `scripts/release.sh`**
  ```bash
  git add scripts/release.sh
  git commit -m "feat(release): add automated local release script with gh release integration"
  ```

---

### Task 3: Perbarui Dokumentasi `AGENTS.md` dan `README.md`

**Files:**
- Modify: `AGENTS.md`
- Modify: `README.md`
- Test: Review visual & markdown rendering

**Interfaces:**
- Consumes: Skrip `scripts/release.sh` dan `CHANGELOG.md`
- Produces: SOP rilis versi resmi di `AGENTS.md` dan dokumentasi rilis di `README.md`

- [ ] **Step 1: Tambahkan SOP Rilis di `AGENTS.md`**
  - Tambahkan `📋 SOP 6: Release & Versioning Management`
  - Jelaskan aturan Semantic Versioning (`vMAJOR.MINOR.PATCH`).
  - Dokumentasikan alur rilis menggunakan `./scripts/release.sh <version> [--publish]`.
  - Dokumentasikan cara manual rollback atau verifikasi tag.
- [ ] **Step 2: Perbarui `README.md`**
  - Tambahkan informasi versi saat ini dan tautan ke `CHANGELOG.md`.
  - Tambahkan catatan cara merilis versi baru.
- [ ] **Step 3: Commit dokumentasi**
  ```bash
  git add AGENTS.md README.md
  git commit -m "docs: document release workflow and SOP in AGENTS.md and README.md"
  ```

---

### Task 4: Eksekusi Rilis Perdana `v1.0.0`

**Files:**
- Modify: Git state, remote `origin`, GitHub Releases

**Interfaces:**
- Consumes: Seluruh commit yang telah siap, `scripts/release.sh`, `gh` CLI
- Produces: Tag git `v1.0.0` lokal dan remote, serta GitHub Release `v1.0.0` di `adi-jaya/macports-control-center`

- [ ] **Step 1: Jalankan unit test suite lengkap**
  - Pastikan semua 57/57 tests lulus.
- [ ] **Step 2: Push commit aktif ke remote `origin/main`**
  ```bash
  git push origin main
  ```
- [ ] **Step 3: Eksekusi rilis `v1.0.0` dengan `--publish`**
  ```bash
  ./scripts/release.sh 1.0.0 --publish
  ```
- [ ] **Step 4: Verifikasi hasil rilis di GitHub**
  - `git tag -l -n` menampilkan tag `v1.0.0`.
  - `gh release view v1.0.0` menampilkan release title, tag, dan notes yang sesuai dengan `CHANGELOG.md`.
