#!/bin/sh
set -e
cd "$(dirname "$0")"

# Workaround for a broken Command Line Tools install on this machine:
# a stale module.modulemap duplicates bridging.modulemap (both define
# SwiftBridging). Mask the stale one with an empty file via a VFS overlay.
# Harmless once CLT is fixed; permanent fix:
#   sudo rm /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap
OVERLAY_DIR=$(mktemp -d)
trap 'rm -rf "$OVERLAY_DIR"' EXIT
touch "$OVERLAY_DIR/empty.modulemap"
cat > "$OVERLAY_DIR/overlay.yaml" <<EOF
{
  "version": 0,
  "roots": [
    {
      "name": "/Library/Developer/CommandLineTools/usr/include/swift",
      "type": "directory",
      "contents": [
        { "name": "module.modulemap", "type": "file",
          "external-contents": "$OVERLAY_DIR/empty.modulemap" }
      ]
    }
  ]
}
EOF

APP=MD5Hash.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -parse-as-library -vfsoverlay "$OVERLAY_DIR/overlay.yaml" MD5HashApp.swift -o "$APP/Contents/MacOS/MD5Hash"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "Built $APP"
