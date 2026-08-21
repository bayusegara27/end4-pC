#!/usr/bin/env bash

# Shrink a freshly downloaded wallpaper to something the screen can actually use.
#
# The online sources hand over originals — image board scans run to 5760x3240 and
# beyond. Every one of those pixels is paid for repeatedly: several elements in
# the shell decode the wallpaper on every change (the wallpaper itself, the one
# it crossfades from, the user card, …), and none of them can show more than the
# screen has. Measured on a 1920x1080 screen, one wallpaper change cost 440ms of
# shell CPU at 3840x2160 and 215ms at 2560x1440.
#
# 2560x1440 rather than the screen's own size leaves headroom for the crop that
# PreserveAspectCrop does on anything that is not exactly 16:9. `^` fills that
# box rather than fitting inside it, and `>` only ever shrinks, so a wallpaper
# smaller than the box is left completely alone.
#
# Usage: fit-wallpaper.sh <image> [maximum]

image="${1:-}"
maximum="${2:-2560x1440}"

[[ -f "$image" ]] || exit 0
command -v magick >/dev/null 2>&1 || exit 0

temporary="$image.fit.tmp"
if magick "$image" -resize "${maximum}^>" -quality 92 "$temporary" 2>/dev/null \
    && [[ -s "$temporary" ]]; then
    mv "$temporary" "$image"
else
    rm -f "$temporary"
fi
