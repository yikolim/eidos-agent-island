#!/usr/bin/env bash
#
# build.sh — Compile Noesis.app directly with swiftc (no full Xcode needed).
#
# Compiles every Swift file under AgentMode/ into one executable and wraps a
# minimal .app bundle around it.
#
# Usage:
#   ./build.sh           # build only
#   ./build.sh --run     # build then launch Noesis.app
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Noesis.app"
MACOS_DIR="$APP/Contents/MacOS"
BIN="$MACOS_DIR/Noesis"

echo "==> Collecting Swift sources"
SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(find "$ROOT/AgentMode" -name '*.swift' | sort)
printf '    %s\n' "${SOURCES[@]#$ROOT/}"

echo "==> Preparing bundle at build/Noesis.app"
rm -rf "$APP"
mkdir -p "$MACOS_DIR"
printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>Noesis</string>
	<key>CFBundleDisplayName</key><string>Noesis</string>
	<key>CFBundleIdentifier</key><string>com.noesis.app</string>
	<key>CFBundleExecutable</key><string>Noesis</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>CFBundleShortVersionString</key><string>0.2.0</string>
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
  -target "${ARCH:-$(uname -m)}-apple-macosx14.0" \
  -framework SwiftUI -framework AppKit -framework IOKit \
  -framework UserNotifications -framework ServiceManagement \
  -parse-as-library \
  -swift-version 5 \
  -o "$BIN" \
  "${SOURCES[@]}"

echo "==> Ad-hoc code signing"
codesign --force --sign - "$APP" 2>/dev/null || echo "    (codesign skipped)"

echo "==> Built: $APP"

if [[ "${1:-}" == "--run" ]]; then
  echo "==> Launching"
  pkill -x Noesis 2>/dev/null || true
  sleep 0.3
  open "$APP"
fi
