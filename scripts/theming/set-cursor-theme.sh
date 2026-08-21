#!/usr/bin/env bash
# Apply cursor theme + size. Usage: set-cursor-theme.sh <theme> [size]
#
# The stock version only wrote gsettings and ~/.icons/default, which left GTK
# ini files, Qt, Hyprland and Flatpak on whatever they had before.  Delegate to
# cursorctl so the shell settings app and the CLI cannot drift apart.
set -u

theme="${1:-}"
size="${2:-24}"
[[ -z "$theme" ]] && { echo "usage: $0 <cursor-theme> [size]" >&2; exit 1; }

exec "$HOME/.local/bin/cursorctl" apply "$theme" "$size"
