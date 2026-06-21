#!/usr/bin/env bash
#
# fix-toolchain.sh — Repair the broken Command Line Tools Swift toolchain.
#
# Symptom:
#   swiftc fails on ANY file that imports a system framework with:
#     error: redefinition of module 'SwiftBridging'
#
# Cause:
#   The CLT 16.1 update left a stale duplicate modulemap behind:
#     /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap   (2023, stale)
#     /Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap (2024, current)
#   Both declare `module SwiftBridging`, so the compiler errors on the conflict.
#   The two files are byte-identical except for the copyright year.
#
# Fix:
#   Move the stale 2023 file out of the way. Reinstalling the CLT would restore
#   it cleanly, so this is safe and reversible (a backup is kept next to it).
#
# Requires sudo (the file is owned by root).
#
set -euo pipefail

STALE="/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap"
KEEP="/Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap"

if [[ ! -f "$STALE" ]]; then
  echo "Stale modulemap not present — nothing to do. Toolchain may already be fixed."
  exit 0
fi

echo "This will move the stale duplicate modulemap aside:"
echo "  $STALE  ->  $STALE.bak"
echo "(The current $KEEP is kept.)"
echo
sudo mv "$STALE" "$STALE.bak"
echo "Done. Verifying with a SwiftUI smoke compile..."

TMP="$(mktemp -d)"
cat > "$TMP/t.swift" <<'EOF'
import SwiftUI
import AppKit
import Network
print("toolchain ok")
EOF
if swiftc "$TMP/t.swift" -o "$TMP/t" 2>"$TMP/err"; then
  "$TMP/t"
  echo "Toolchain repaired. You can now run ./build.sh"
else
  echo "Still failing:"
  cat "$TMP/err"
  echo "You may need to install full Xcode from the App Store instead."
  exit 1
fi
rm -rf "$TMP"
