#!/usr/bin/env bash

# List the Wallpaper Engine library as JSON, for the shell's wallpaper selector.
#
# Uses wpe-manager's own scanner rather than re-reading project.json by hand, so
# titles, preview resolution and age ratings match exactly what its GUI shows.
#
# Prints [] rather than failing when the library or wpe-manager is missing.

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
WPE_CONFIG_FILE="$XDG_CONFIG_HOME/wpe-manager/config.json"

library_dir=""
if [[ -f "$WPE_CONFIG_FILE" ]]; then
    library_dir="$(jq -r '.library_dir // empty' "$WPE_CONFIG_FILE" 2>/dev/null)"
fi

if [[ -z "$library_dir" || ! -d "$library_dir" ]]; then
    echo '[]'
    exit 0
fi

# The system interpreter, deliberately: wpe_manager lives in the system
# site-packages and is not visible from the shell's own virtualenv.
/usr/bin/python - "$library_dir" <<'PY'
import json
import sys
from pathlib import Path

try:
    from wpe_manager import library
except ImportError:
    print("[]")
    sys.exit(0)

entries = []
for wallpaper in library.scan(Path(sys.argv[1])):
    if not wallpaper.has_preview:
        continue
    entries.append({
        "id": wallpaper.id,
        "title": wallpaper.title,
        "type": wallpaper.type,
        "preview": str(wallpaper.preview),
        "age": wallpaper.age,
    })

print(json.dumps(entries))
PY
