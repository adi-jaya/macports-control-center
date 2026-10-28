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

echo "=========================================================="
echo " Packaging: ${APP_NAME}.app"
echo " Target: macOS 12.0+ (x86_64)"
echo " Workspace: ${REPO_DIR}"
echo "=========================================================="

# 1. Clean previous build artifact
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 2. Compile native release executable
echo "[1/4] Compiling Swift Native release binary with swiftc..."
SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")"
swiftc -O -target x86_64-apple-macos12.0 \
    -sdk "${SDK_PATH}" \
    -whole-module-optimization \
    -parse-as-library \
    "${REPO_DIR}"/Sources/MacPortsControlCenter/Models/*.swift \
    "${REPO_DIR}"/Sources/MacPortsControlCenter/Services/*.swift \
    "${REPO_DIR}"/Sources/MacPortsControlCenter/Views/*.swift \
    "${REPO_DIR}"/Sources/MacPortsControlCenterApp/MainApp.swift \
    -o "${MACOS_DIR}/${BINARY_NAME}"

chmod +x "${MACOS_DIR}/${BINARY_NAME}"

# 3. Copy Bundle Metadata and Documentation
echo "[2/4] Copying Info.plist and documentation resources..."
cp "${REPO_DIR}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"

# Copy all repository markdown documentation into app bundle Resources
find "${REPO_DIR}" -maxdepth 1 -name "*.md" -exec cp {} "${RESOURCES_DIR}/" \;

# 4. Ad-Hoc Code Signing
echo "[3/4] Signing application bundle (ad-hoc)..."
codesign --force --deep --sign - "${APP_BUNDLE}"

# 5. Verification
echo "[4/4] Verifying code signature and bundle structure..."
codesign --verify --verbose "${APP_BUNDLE}"

BINARY_SIZE=$(ls -lh "${MACOS_DIR}/${BINARY_NAME}" | awk '{print $5}')
TOTAL_SIZE=$(du -sh "${APP_BUNDLE}" | awk '{print $1}')

echo "=========================================================="
echo "✅ Build Complete!"
echo "   Bundle: ${APP_BUNDLE}"
echo "   Binary Size: ${BINARY_SIZE}"
echo "   Total Bundle Size: ${TOTAL_SIZE}"
echo "=========================================================="
