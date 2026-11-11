#!/bin/bash
# Builds the web export into build/web: the build command of the Render static site, which
# serves the game on cafenavette.com. Downloads the Godot editor and its web templates.
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
base="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable"
tools="$(mktemp -d)"

curl -sSLo "$tools/godot.zip" "$base/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
curl -sSLo "$tools/templates.tpz" "$base/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
unzip -q "$tools/godot.zip" -d "$tools"
godot="$tools/Godot_v${GODOT_VERSION}-stable_linux.x86_64"
chmod +x "$godot"
dest="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
mkdir -p "$dest"
unzip -q -o -j "$tools/templates.tpz" 'templates/web_*' 'templates/version.txt' -d "$dest"
rm -f "$tools/godot.zip" "$tools/templates.tpz"

"$godot" --headless --path . --import
rm -rf build/web
mkdir -p build/web
"$godot" --headless --path . --export-release "Web" build/web/index.html
test -f build/web/index.pck
