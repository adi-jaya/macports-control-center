#!/bin/bash
set -e

# MacPorts Control Center — Release .app Builder
# Compiles zero-dependency Swift native binary and packages macOS .app bundle.

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MacPorts Control Center"
BUILD_DIR="${REPO_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
BINARY_NAME="MacPortsControlCenterApp"

INSTALL_TARGET=""
UNIVERSAL=0
HOST_ARCH="$(uname -m)"

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--install)
            INSTALL_TARGET="/Applications"
            shift
            ;;
        --user-install)
            INSTALL_TARGET="${HOME}/Applications"
            shift
            ;;
        --universal)
            UNIVERSAL=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -i, --install      Build and install application to /Applications"
            echo "  --user-install     Build and install application to ~/Applications"
            echo "  --universal        Build universal binary (x86_64 and arm64)"
            echo "  -h, --help         Show this help message"
            exit 0
            ;;
        *)
            echo "Error: Unknown option '$1'"
            echo "Run '$0 --help' for usage."
            exit 1
            ;;
    esac
done

if [ "$UNIVERSAL" -eq 1 ]; then
    TARGET_DESC="macOS 12.0+ (Universal: x86_64 + arm64)"
else
    TARGET_DESC="macOS 12.0+ (${HOST_ARCH})"
fi

echo "=========================================================="
echo " Packaging: ${APP_NAME}.app"
echo " Target: ${TARGET_DESC}"
echo " Workspace: ${REPO_DIR}"
echo "=========================================================="

# 1. Clean previous build artifact
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 2. Compile native release executable
SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")"
SOURCE_FILES=(
    "${REPO_DIR}"/Sources/MacPortsControlCenter/Models/*.swift
    "${REPO_DIR}"/Sources/MacPortsControlCenter/Services/*.swift
    "${REPO_DIR}"/Sources/MacPortsControlCenter/Views/*.swift
    "${REPO_DIR}"/Sources/MacPortsControlCenterApp/MainApp.swift
)

if [ "$UNIVERSAL" -eq 1 ]; then
    echo "[1/5] Compiling Swift Native release binary (Universal: x86_64 + arm64)..."
    TEMP_BUILD_DIR="$(mktemp -d /tmp/mpcc_build_XXXXXX)"
    trap 'rm -rf "${TEMP_BUILD_DIR}"' EXIT

    echo "      Compiling x86_64 slice..."
    swiftc -O -target x86_64-apple-macos12.0 \
        -sdk "${SDK_PATH}" \
        -whole-module-optimization \
        -parse-as-library \
        -lsqlite3 \
        -Xlinker -dead_strip \
        "${SOURCE_FILES[@]}" \
        -o "${TEMP_BUILD_DIR}/${BINARY_NAME}_x86_64"

    echo "      Compiling arm64 slice..."
    swiftc -O -target arm64-apple-macos12.0 \
        -sdk "${SDK_PATH}" \
        -whole-module-optimization \
        -parse-as-library \
        -lsqlite3 \
        -Xlinker -dead_strip \
        "${SOURCE_FILES[@]}" \
        -o "${TEMP_BUILD_DIR}/${BINARY_NAME}_arm64"

    echo "      Creating universal binary with lipo..."
    lipo -create \
        "${TEMP_BUILD_DIR}/${BINARY_NAME}_x86_64" \
        "${TEMP_BUILD_DIR}/${BINARY_NAME}_arm64" \
        -output "${MACOS_DIR}/${BINARY_NAME}"
else
    echo "[1/5] Compiling Swift Native release binary (${HOST_ARCH})..."
    swiftc -O -target "${HOST_ARCH}-apple-macos12.0" \
        -sdk "${SDK_PATH}" \
        -whole-module-optimization \
        -parse-as-library \
        -lsqlite3 \
        -Xlinker -dead_strip \
        "${SOURCE_FILES[@]}" \
        -o "${MACOS_DIR}/${BINARY_NAME}"
fi

chmod +x "${MACOS_DIR}/${BINARY_NAME}"

# 3. Strip Mach-O linkedit local/debug symbols prior to codesigning
echo "[2/5] Stripping Mach-O linkedit symbols (strip -x)..."
strip -x "${MACOS_DIR}/${BINARY_NAME}"

# 4. Copy Bundle Metadata and Documentation
echo "[3/5] Copying Info.plist and documentation resources..."
cp "${REPO_DIR}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"

# Copy AppIcon.icns if available
if [ -f "${REPO_DIR}/Resources/AppIcon.icns" ]; then
    echo "      Including custom AppIcon.icns..."
    cp "${REPO_DIR}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# Copy all repository markdown documentation into app bundle Resources
find "${REPO_DIR}" -maxdepth 1 -name "*.md" -exec cp {} "${RESOURCES_DIR}/" \;

# 5. Ad-Hoc Code Signing
echo "[4/5] Signing application bundle (ad-hoc)..."
codesign --force --deep --sign - "${APP_BUNDLE}"

# 6. Verification
echo "[5/5] Verifying code signature and bundle structure..."
codesign --verify --verbose "${APP_BUNDLE}"

# 6. Optional Installation
if [ -n "${INSTALL_TARGET}" ]; then
    echo ""
    echo "[Install] Installing ${APP_NAME}.app into ${INSTALL_TARGET}..."

    # Close running instance if any to prevent binary replacement conflict
    if pgrep -x "${BINARY_NAME}" > /dev/null 2>&1; then
        echo "          Terminating running instance of ${BINARY_NAME}..."
        pkill -x "${BINARY_NAME}" 2>/dev/null || true
        sleep 0.5
    fi

    mkdir -p "${INSTALL_TARGET}"
    rm -rf "${INSTALL_TARGET}/${APP_NAME}.app"
    cp -R "${APP_BUNDLE}" "${INSTALL_TARGET}/"
    touch "${INSTALL_TARGET}/${APP_NAME}.app"
    echo "          Installed to: ${INSTALL_TARGET}/${APP_NAME}.app"
fi

BINARY_SIZE=$(ls -lh "${MACOS_DIR}/${BINARY_NAME}" | awk '{print $5}')
TOTAL_SIZE=$(du -sh "${APP_BUNDLE}" | awk '{print $1}')

echo "=========================================================="
echo "✅ Build Complete!"
echo "   Bundle: ${APP_BUNDLE}"
echo "   Binary Size: ${BINARY_SIZE}"
echo "   Total Bundle Size: ${TOTAL_SIZE}"
if [ -n "${INSTALL_TARGET}" ]; then
    echo "   Installed Target: ${INSTALL_TARGET}/${APP_NAME}.app"
else
    echo "   (Tip: Pass '--install' to copy to /Applications automatically)"
fi
echo "=========================================================="
