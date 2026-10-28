#!/bin/bash
set -e

# ==============================================================================
# MacPorts Control Center — AppIcon Generator
# Converts any high-resolution image (recommended: 1024x1024 PNG) into
# macOS standard AppIcon.icns and places it into Resources/AppIcon.icns.
# ==============================================================================

SOURCE_IMAGE="$1"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES_DIR="${REPO_DIR}/Resources"
TARGET_ICNS="${RESOURCES_DIR}/AppIcon.icns"
TEMP_DIR="/tmp/mpcc_iconset_$$"
ICONSET_DIR="${TEMP_DIR}/AppIcon.iconset"

if [ -z "$SOURCE_IMAGE" ]; then
    echo "=========================================================="
    echo " Usage: ./scripts/generate_icon.sh <path-to-image.png>"
    echo "=========================================================="
    echo "Tips:"
    echo "  - Use a square image, ideally 1024x1024 pixels."
    echo "  - Format: PNG with transparency."
    echo "  - Example: ./scripts/generate_icon.sh ~/Downloads/logo.png"
    exit 1
fi

if [ ! -f "$SOURCE_IMAGE" ]; then
    echo "Error: Source image not found at '$SOURCE_IMAGE'"
    exit 1
fi

echo "Generating macOS AppIcon from: ${SOURCE_IMAGE}"

# Create temporary iconset directory
mkdir -p "${ICONSET_DIR}"
trap 'rm -rf "${TEMP_DIR}"' EXIT

# Generate all standard macOS icon sizes using native 'sips'
echo "Generating icon sizes..."
sips -z 16 16     "${SOURCE_IMAGE}" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
sips -z 32 32     "${SOURCE_IMAGE}" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "${SOURCE_IMAGE}" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
sips -z 64 64     "${SOURCE_IMAGE}" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "${SOURCE_IMAGE}" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
sips -z 256 256   "${SOURCE_IMAGE}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "${SOURCE_IMAGE}" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
sips -z 512 512   "${SOURCE_IMAGE}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "${SOURCE_IMAGE}" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
sips -z 1024 1024 "${SOURCE_IMAGE}" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null

# Compile iconset to .icns using native 'iconutil'
echo "Compiling .icns with iconutil..."
mkdir -p "${RESOURCES_DIR}"
iconutil -c icns "${ICONSET_DIR}" -o "${TARGET_ICNS}"

echo "=========================================================="
echo "✅ AppIcon.icns successfully created!"
echo "   Output: ${TARGET_ICNS}"
echo "   Re-run './build-app.sh' to package the app with the new icon."
echo "=========================================================="
