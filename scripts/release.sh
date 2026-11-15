#!/bin/bash
set -e

# ==============================================================================
# MacPorts Control Center — Release & Versioning Automation Script
#
# Usage:
#   ./scripts/release.sh [OPTIONS] <version>
#
# Examples:
#   ./scripts/release.sh 1.0.0
#   ./scripts/release.sh v1.0.1 --publish
#   ./scripts/release.sh 1.1.0 --dry-run
# ==============================================================================

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="${REPO_DIR}/Resources/Info.plist"
CHANGELOG_FILE="${REPO_DIR}/CHANGELOG.md"

VERSION_INPUT=""
PUBLISH=0
DRY_RUN=0
SKIP_TESTS=0

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

show_help() {
    echo -e "${BOLD}MacPorts Control Center Release Automation${NC}"
    echo ""
    echo -e "Usage: $0 [OPTIONS] <version>"
    echo ""
    echo "Arguments:"
    echo "  <version>            Semantic version to release (e.g., 1.0.0 or v1.0.0)"
    echo ""
    echo "Options:"
    echo "  -p, --publish        Push commits/tag to origin and create GitHub Release via gh CLI"
    echo "  --skip-tests         Skip executing unit test suite (not recommended)"
    echo "  -n, --dry-run        Validate requirements and preview release steps without changing state"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 1.0.0"
    echo "  $0 v1.0.1 --publish"
    echo "  $0 1.0.0 --dry-run"
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--publish)
            PUBLISH=1
            shift
            ;;
        --skip-tests)
            SKIP_TESTS=1
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            echo -e "${RED}Error: Unknown option '$1'${NC}"
            show_help
            exit 1
            ;;
        *)
            if [ -z "${VERSION_INPUT}" ]; then
                VERSION_INPUT="$1"
            else
                echo -e "${RED}Error: Unexpected extra argument '$1'${NC}"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

if [ -z "${VERSION_INPUT}" ]; then
    echo -e "${RED}Error: Version argument is required.${NC}"
    echo ""
    show_help
    exit 1
fi

# Normalize version (strip leading 'v' or 'V')
CLEAN_VERSION="${VERSION_INPUT#[vV]}"
TAG_NAME="v${CLEAN_VERSION}"

# Validate SemVer pattern: MAJOR.MINOR.PATCH
if ! [[ "${CLEAN_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}Error: Version '${VERSION_INPUT}' does not conform to Semantic Versioning (MAJOR.MINOR.PATCH, e.g. 1.0.0)${NC}"
    exit 1
fi

echo -e "${BLUE}==========================================================${NC}"
echo -e "${BOLD} MacPorts Control Center Release Preparation: ${TAG_NAME}${NC}"
echo -e "${BLUE}==========================================================${NC}"
echo " Repository:  ${REPO_DIR}"
echo " Version:     ${CLEAN_VERSION} (Tag: ${TAG_NAME})"
echo " Publish:     $([ "${PUBLISH}" -eq 1 ] && echo -e "${GREEN}Yes (Push + GitHub Release)${NC}" || echo "No (Local only)")"
echo " Mode:        $([ "${DRY_RUN}" -eq 1 ] && echo -e "${YELLOW}DRY-RUN (Simulasi)${NC}" || echo "Production")"
echo ""

# 1. Pre-flight Git Checks
echo -e "${BOLD}[1/7] Checking Git workspace state...${NC}"

CURRENT_BRANCH="$(git -C "${REPO_DIR}" symbolic-ref --short HEAD 2>/dev/null || echo "")"
if [ "${CURRENT_BRANCH}" != "main" ]; then
    echo -e "${RED}Error: Releases must be cut from the 'main' branch (current: '${CURRENT_BRANCH}').${NC}"
    exit 1
fi

if git -C "${REPO_DIR}" rev-parse "${TAG_NAME}" >/dev/null 2>&1; then
    echo -e "${RED}Error: Git tag '${TAG_NAME}' already exists locally.${NC}"
    exit 1
fi

# Check uncommitted changes (only enforce when not in dry-run)
if [ "${DRY_RUN}" -eq 0 ]; then
    if ! git -C "${REPO_DIR}" diff --quiet || ! git -C "${REPO_DIR}" diff --cached --quiet; then
        echo -e "${RED}Error: Working directory has uncommitted changes. Please commit or stash them first.${NC}"
        git -C "${REPO_DIR}" status --short
        exit 1
    fi
fi
echo -e "${GREEN}      Git workspace is clean on branch 'main'.${NC}"

# 2. Check CHANGELOG.md entry
echo -e "${BOLD}[2/7] Checking CHANGELOG.md for release notes...${NC}"
if [ ! -f "${CHANGELOG_FILE}" ]; then
    echo -e "${RED}Error: ${CHANGELOG_FILE} not found.${NC}"
    exit 1
fi

# Extract release notes section for this version
extract_release_notes() {
    local ver="$1"
    local file="$2"
    awk -v ver="$ver" '
      BEGIN { recording = 0; found = 0 }
      $0 ~ "^## \\[" ver "\\]" { recording = 1; found = 1; next }
      recording && /^## \[/ { recording = 0 }
      recording && /^---$/ { recording = 0 }
      recording && /^\[.*\]:/ { recording = 0 }
      recording { print }
    ' "$file" | sed -e '/./,$!d'
}

RELEASE_NOTES="$(extract_release_notes "${CLEAN_VERSION}" "${CHANGELOG_FILE}")"
if [ -z "${RELEASE_NOTES}" ]; then
    echo -e "${RED}Error: No release notes found for version '[${CLEAN_VERSION}]' in CHANGELOG.md.${NC}"
    echo -e "Please add a section '## [${CLEAN_VERSION}] - YYYY-MM-DD' with release details."
    exit 1
fi
echo -e "${GREEN}      Found release notes for [${CLEAN_VERSION}] ($(echo "${RELEASE_NOTES}" | wc -l | tr -d ' ') lines).${NC}"

# 3. Execute Unit Test Suite
echo -e "${BOLD}[3/7] Verifying Unit Test Suite...${NC}"
if [ "${SKIP_TESTS}" -eq 1 ]; then
    echo -e "${YELLOW}      Skipped (--skip-tests specified).${NC}"
else
    echo "      Compiling test runner..."
    SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")"
    swiftc -target "$(uname -m)-apple-macos12.0" \
        -sdk "${SDK_PATH}" \
        -parse-as-library \
        "${REPO_DIR}"/Sources/MacPortsControlCenter/Models/*.swift \
        "${REPO_DIR}"/Sources/MacPortsControlCenter/Services/*.swift \
        "${REPO_DIR}"/Sources/MacPortsControlCenter/Views/*.swift \
        "${REPO_DIR}"/Tests/MacPortsControlCenterTests/*.swift \
        -lsqlite3 \
        -o /tmp/run-all-tests

    echo "      Executing all tests..."
    TEST_RUNNER=1 /tmp/run-all-tests
    echo -e "${GREEN}      All unit tests passed successfully!${NC}"
fi

# 4. Synchronize Info.plist version metadata
echo -e "${BOLD}[4/7] Updating Resources/Info.plist version metadata...${NC}"
CURRENT_SHORT_VER="$(plutil -extract CFBundleShortVersionString raw "${INFO_PLIST}" 2>/dev/null || echo "")"
CURRENT_BUILD_NUM="$(plutil -extract CFBundleVersion raw "${INFO_PLIST}" 2>/dev/null || echo "1")"

if [ "${CURRENT_SHORT_VER}" != "${CLEAN_VERSION}" ]; then
    NEXT_BUILD_NUM=$((CURRENT_BUILD_NUM + 1))
    echo "      Current: CFBundleShortVersionString=${CURRENT_SHORT_VER}, CFBundleVersion=${CURRENT_BUILD_NUM}"
    echo "      Target:  CFBundleShortVersionString=${CLEAN_VERSION}, CFBundleVersion=${NEXT_BUILD_NUM}"

    if [ "${DRY_RUN}" -eq 0 ]; then
        plutil -replace CFBundleShortVersionString -string "${CLEAN_VERSION}" "${INFO_PLIST}"
        plutil -replace CFBundleVersion -string "${NEXT_BUILD_NUM}" "${INFO_PLIST}"
        echo -e "${GREEN}      Info.plist updated.${NC}"
    else
        echo -e "${YELLOW}      [Dry-run] Info.plist modification skipped.${NC}"
    fi
else
    echo "      Info.plist is already at version ${CLEAN_VERSION} (Build: ${CURRENT_BUILD_NUM})."
fi

# 5. Compile Application Bundle
echo -e "${BOLD}[5/7] Compiling release application bundle (Universal Binary)...${NC}"
if [ "${DRY_RUN}" -eq 0 ]; then
    "${REPO_DIR}/build-app.sh" --universal
    echo -e "${GREEN}      App bundle compiled and verified.${NC}"
else
    echo -e "${YELLOW}      [Dry-run] App build skipped.${NC}"
fi

# 6. Git Commit & Annotated Tag
echo -e "${BOLD}[6/7] Creating Git commit and annotated release tag...${NC}"
if [ "${DRY_RUN}" -eq 0 ]; then
    # Stage Info.plist if modified
    if ! git -C "${REPO_DIR}" diff --quiet "${INFO_PLIST}"; then
        git -C "${REPO_DIR}" add "${INFO_PLIST}"
        git -C "${REPO_DIR}" commit -m "chore(release): bump version to ${CLEAN_VERSION} (build ${NEXT_BUILD_NUM})"
        echo -e "${GREEN}      Committed version bump to ${CLEAN_VERSION}.${NC}"
    fi

    git -C "${REPO_DIR}" tag -a "${TAG_NAME}" -m "Release ${TAG_NAME}"
    echo -e "${GREEN}      Created annotated tag: ${TAG_NAME}${NC}"
else
    echo -e "${YELLOW}      [Dry-run] Would commit Info.plist and tag '${TAG_NAME}'.${NC}"
fi

# 7. Publish to GitHub
echo -e "${BOLD}[7/7] GitHub Publication...${NC}"
if [ "${PUBLISH}" -eq 1 ]; then
    if [ "${DRY_RUN}" -eq 1 ]; then
        echo -e "${YELLOW}      [Dry-run] Would push 'main' and tag '${TAG_NAME}', then run 'gh release create'.${NC}"
    else
        # Verify gh CLI is installed and authenticated
        if ! command -v gh >/dev/null 2>&1; then
            echo -e "${RED}Error: GitHub CLI ('gh') is not installed. Please install it with 'sudo port install gh'${NC}"
            exit 1
        fi

        if ! gh auth status >/dev/null 2>&1; then
            echo -e "${RED}Error: GitHub CLI is not authenticated. Please run 'gh auth login'${NC}"
            exit 1
        fi

        echo "      Pushing main branch to origin..."
        git -C "${REPO_DIR}" push origin main

        echo "      Pushing tag '${TAG_NAME}' to origin..."
        git -C "${REPO_DIR}" push origin "${TAG_NAME}"

        echo "      Creating GitHub Release via gh CLI..."
        NOTES_FILE="$(mktemp /tmp/release_notes_XXXXXX.md)"
        echo "${RELEASE_NOTES}" > "${NOTES_FILE}"

        gh release create "${TAG_NAME}" \
            --title "${TAG_NAME}" \
            --notes-file "${NOTES_FILE}"

        rm -f "${NOTES_FILE}"
        echo -e "${GREEN}      GitHub Release ${TAG_NAME} successfully published!${NC}"
    fi
else
    echo "      Publication skipped (pass -p or --publish to push and create GitHub Release)."
    echo "      To publish manually, run:"
    echo "        git push origin main"
    echo "        git push origin ${TAG_NAME}"
    echo "        gh release create ${TAG_NAME} --title \"${TAG_NAME}\" --notes \"...\""
fi

echo ""
echo -e "${GREEN}==========================================================${NC}"
echo -e "${BOLD}✅ Release process complete for ${TAG_NAME}!${NC}"
echo -e "${GREEN}==========================================================${NC}"
