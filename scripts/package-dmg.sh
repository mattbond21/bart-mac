#!/bin/zsh
# Usage: scripts/package-dmg.sh Bart.app Bart.dmg
set -euo pipefail
cd "${0:A:h:h}"

app="${1:?Pass the built Bart.app}"
output="${2:?Pass the output DMG path}"
app="${app:A}"
output="${output:A}"
tools="$PWD/.build/dmg-tools"
background="$PWD/.build/dmg-background.png"

if [[ ! -x "$tools/bin/python" ]]; then
    python3 -m venv "$tools"
fi
"$tools/bin/python" -m pip install --disable-pip-version-check --quiet -r scripts/dmg-requirements.txt
swift scripts/make-dmg-background.swift "$background"
"$tools/bin/dmgbuild" -s scripts/dmg-settings.py \
    -D app="$app" -D background="$background" Bart "$output"
print "Packaged $output"
