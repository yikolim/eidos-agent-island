#!/usr/bin/env bash
#
# build.sh — Compile Eidos.app directly with swiftc (no full Xcode required).
#
# This bypasses xcodebuild/xcodegen so the app can be built with only the
# Command Line Tools. It compiles every Swift file under Eidos/ into a single
# executable and assembles a minimal .app bundle around it.
#
# Requirements:
#   - A working Swift toolchain that can import system frameworks. If you hit
#     "redefinition of module 'SwiftBridging'", run ./fix-toolchain.sh first.
#
# Usage:
#   ./build.sh           # build only
#   ./build.sh --run     # build then launch Eidos.app
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Eidos.app"
MACOS_DIR="$APP/Contents/MacOS"
BIN="$MACOS_DIR/Eidos"

echo "==> Collecting Swift sources"
SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(find "$ROOT/Eidos" -name '*.swift' | sort)
printf '    %s\n' "${SOURCES[@]#$ROOT/}"

echo "==> Preparing bundle at build/Eidos.app"
rm -rf "$APP"
mkdir -p "$MACOS_DIR"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Write a literal Info.plist. We do NOT copy Eidos/Info.plist because xcodegen
# regenerates that file with xcodebuild-only variables like $(EXECUTABLE_NAME),
# which the manual swiftc build cannot expand.
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>Eidos</string>
	<key>CFBundleDisplayName</key><string>Eidos</string>
	<key>CFBundleIdentifier</key><string>com.eidos.app</string>
	<key>CFBundleExecutable</key><string>Eidos</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>CFBundleShortVersionString</key><string>0.1.0</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> Compiling (target macOS 14)"
swiftc \
  -O \
  -target arm64-apple-macosx14.0 \
  -framework SwiftUI -framework AppKit -framework Network \
  -parse-as-library \
  -swift-version 5 \
  -o "$BIN" \
  "${SOURCES[@]}"

echo "==> Ad-hoc code signing"
codesign --force --sign - "$APP" 2>/dev/null || echo "    (codesign skipped)"

echo "==> Built: $APP"

if [[ "${1:-}" == "--run" ]]; then
  echo "==> Launching"
  # Kill any previous instance so the port is free.
  pkill -x Eidos 2>/dev/null || true
  sleep 0.3
  open "$APP"
fi
