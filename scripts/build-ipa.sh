#!/usr/bin/env bash
#
# build-ipa.sh — archive MCLauncher and package a signed .ipa for sideloading.
#
# Usage:
#   ./scripts/build-ipa.sh [TEAM_ID] [BUNDLE_ID]
#
# Prerequisites: Xcode command line tools, and (recommended) xcodegen.
# See BUILD.md for full instructions.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="MCLauncher"
PROJECT="MCLauncher.xcodeproj"
CONFIG="Release"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/MCLauncher.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
IPA="$BUILD_DIR/MCLauncher.ipa"

TEAM_ID="${1:-}"
BUNDLE_ID="${2:-}"

echo "==> MC Launcher IPA builder"

# ---------------------------------------------------------------------------
# 0. Regenerate the project if XcodeGen is available.
# ---------------------------------------------------------------------------
if command -v xcodegen >/dev/null 2>&1; then
  echo "==> Generating $PROJECT from project.yml"
  xcodegen generate
else
  echo "!!  xcodegen not found — using the existing $PROJECT (if any)."
  echo "    Install it with: brew install xcodegen"
fi

if [[ ! -d "$PROJECT" ]]; then
  echo "ERROR: $PROJECT not found. Run 'xcodegen generate' first." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Optionally override the bundle id / team via xcconfig-style build flags.
# ---------------------------------------------------------------------------
EXTRA_ARGS=()
if [[ -n "$TEAM_ID" ]]; then
  EXTRA_ARGS+=("DEVELOPMENT_TEAM=$TEAM_ID")
fi
if [[ -n "$BUNDLE_ID" ]]; then
  EXTRA_ARGS+=("PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID")
fi

# ---------------------------------------------------------------------------
# 2. Archive.
# ---------------------------------------------------------------------------
mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE" "$EXPORT_DIR" "$IPA"

echo "==> Archiving ($CONFIG, device)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  "${EXTRA_ARGS[@]}" \
  archive

# ---------------------------------------------------------------------------
# 3. Export the .app out of the archive.
# ---------------------------------------------------------------------------
echo "==> Extracting .app"
APP_PATH="$ARCHIVE/Products/Applications/MCLauncher.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: $APP_PATH not found in the archive." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 4. Re-sign any embedded binaries (JRE / dylibs), if present.
#    This mirrors the run-script described in BUILD.md. Skipped when no
#    identity is available (e.g. when just testing the shell).
# ---------------------------------------------------------------------------
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [[ -n "$IDENTITY" && -d "$APP_PATH/Frameworks" ]]; then
  echo "==> Signing embedded frameworks/binaries"
  find "$APP_PATH/Frameworks" -type f \
    \( -name "*.dylib" -o -name "*.so" \) -print0 |
    while IFS= read -r -d '' f; do
      codesign --force --sign "$IDENTITY" \
        --preserve-metadata=identifier,entitlements "$f" || true
    done
fi

# ---------------------------------------------------------------------------
# 5. Package Payload/ into an .ipa (an IPA is just a zip).
# ---------------------------------------------------------------------------
echo "==> Packaging IPA"
STAGE="$(mktemp -d)"
mkdir -p "$STAGE/Payload"
cp -R "$APP_PATH" "$STAGE/Payload/"
( cd "$STAGE" && zip -qr "$IPA" Payload )
rm -rf "$STAGE"

echo
echo "=============================================="
echo " IPA ready: $IPA"
echo " Size:      $(du -h "$IPA" | cut -f1)"
echo "=============================================="
echo
echo "Install with Sideloadly or AltStore. See BUILD.md → Step 5."
