#!/bin/bash
set -euo pipefail

# Snapwell Mac App — Build and Export for App Store
#
# Prerequisites:
#   1. "Apple Distribution" certificate in Keychain
#   2. Xcode command line tools selected:
#      sudo xcode-select -s /Applications/Xcode.app
#
# Usage:
#   ./scripts/build-for-appstore.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/Snapwell.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

step() { echo -e "\n${BLUE}▸ $1${NC}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

# ---------------------------------------------------------------------------
# 1. Preflight checks
# ---------------------------------------------------------------------------
step "Preflight checks"

if ! command -v xcodegen &>/dev/null; then
  fail "XcodeGen not found. Install with: brew install xcodegen"
fi

if ! command -v xcbeautify &>/dev/null; then
  warn "xcbeautify not found — raw xcodebuild output will be shown"
  BEAUTIFY=false
else
  BEAUTIFY=true
fi

if ! security find-identity -v -p codesigning | grep -q "Apple Distribution"; then
  fail "No 'Apple Distribution' certificate found in Keychain"
fi
success "Apple Distribution certificate found"

# ---------------------------------------------------------------------------
# 2. Generate Xcode project
# ---------------------------------------------------------------------------
step "Generating Xcode project with XcodeGen"
cd "$PROJECT_DIR"
xcodegen generate
success "Project generated"

# ---------------------------------------------------------------------------
# 3. Clean previous build artifacts
# ---------------------------------------------------------------------------
step "Cleaning previous build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------------------
# 4. Archive
# ---------------------------------------------------------------------------
step "Building archive (Release)"

ARCHIVE_CMD=(
  xcodebuild archive
  -project Snapwell.xcodeproj
  -scheme Snapwell
  -configuration Release
  -archivePath "$ARCHIVE_PATH"
  -allowProvisioningUpdates
)

if [ "$BEAUTIFY" = true ]; then
  "${ARCHIVE_CMD[@]}" 2>&1 | xcbeautify --quiet
else
  "${ARCHIVE_CMD[@]}"
fi
success "Archive created at $ARCHIVE_PATH"

# ---------------------------------------------------------------------------
# 5. Export archive for App Store
# ---------------------------------------------------------------------------
step "Exporting archive for App Store"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$PROJECT_DIR/ExportOptions.plist" \
  -allowProvisioningUpdates \
  2>&1 | if [ "$BEAUTIFY" = true ]; then xcbeautify --quiet; else cat; fi

PKG_PATH=$(find "$EXPORT_DIR" -name "*.pkg" -maxdepth 1 | head -1)
if [ -z "$PKG_PATH" ]; then
  fail "Export failed — no .pkg found in $EXPORT_DIR"
fi
success "Exported: $PKG_PATH"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  App Store build complete!${NC}"
echo -e "${GREEN}  Package: $PKG_PATH${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Upload via Transporter.app (drag the .pkg file)"
echo "     or: xcrun altool --upload-app --file \"$PKG_PATH\" --type osx"
echo "  2. Wait for processing in App Store Connect (~5-30 min)"
echo "  3. Select the build in your app's version page"
echo "  4. Submit for review"
