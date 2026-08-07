#!/usr/bin/env bash
#
# build.sh — Compile AgentMode.app directly with swiftc (no full Xcode needed).
#
# Mirrors the root Eidos build.sh: compiles every Swift file under
# AgentMode/ into one executable and wraps a minimal .app bundle around it.
#
# Usage:
#   ./build.sh           # build only
#   ./build.sh --run     # build then launch AgentMode.app
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/AgentMode.app"
MACOS_DIR="$APP/Contents/MacOS"
BIN="$MACOS_DIR/AgentMode"

echo "==> Collecting Swift sources"
SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(find "$ROOT/AgentMode" -name '*.swift' | sort)
printf '    %s\n' "${SOURCES[@]#$ROOT/}"

echo "==> Preparing bundle at build/AgentMode.app"
rm -rf "$APP"
mkdir -p "$MACOS_DIR"
printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>AgentMode</string>
	<key>CFBundleDisplayName</key><string>Agent Mode</string>
	<key>CFBundleIdentifier</key><string>com.agentmode.app</string>
	<key>CFBundleExecutable</key><string>AgentMode</string>
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
  -target "$(uname -m)-apple-macosx14.0" \
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
  pkill -x AgentMode 2>/dev/null || true
  sleep 0.3
  open "$APP"
fi
