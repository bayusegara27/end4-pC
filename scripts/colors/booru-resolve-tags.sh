#!/usr/bin/env bash

# Turn a free-text wallpaper search into Moebooru tags.
#
# Image board tags are exact identifiers, so what people type rarely matches
# one directly. Three things go wrong without help:
#
#   "genshin"       has no tag; the one with the artwork is genshin_impact
#   "genshin ganyu" is two concepts, not one tag, and matches nothing joined
#   "mountain"      substring-matches an *artist* named urayama_(backmountain),
#                   whose gallery is not what anyone meant
#
# So: try the whole phrase as a single tag first, since real tags like
# raiden_shogun and blue_archive are phrases; fall back to resolving each word
# on its own and ANDing them. Within a lookup an exact name wins, artist tags
# lose to everything else, and a tag with no posts is never chosen.
#
# Usage: booru-resolve-tags.sh <host> <query>
# Prints the tag string to use, or nothing when the query is empty.

HOST="${1:-}"
QUERY="${2:-}"
USER_AGENT="quickshell-wallpaper/1.0"

[[ -n "$HOST" && -n "$QUERY" ]] || exit 0

# Moebooru tag types. 1 is artist: matching one of those means the search
# collapses to a single illustrator rather than a subject.
TAG_TYPE_ARTIST=1

# A substring match only counts when the tag is actually used. "mountain"
# otherwise lands on aoyama_blue_mountain — a character who happens to have the
# word in her name, with two posts. Below this, returning nothing is the more
# honest answer, and the size and ratio filters would have emptied it anyway.
MIN_POSTS_FOR_FUZZY_MATCH=10

lookup_tag() {
    local term="$1"
    [[ -n "$term" ]] || return 1

    local candidates
    candidates="$(curl -s -m 15 -A "$USER_AGENT" -G "$HOST/tag.json" \
        --data-urlencode "name=*${term}*" \
        --data-urlencode "order=count" \
        --data-urlencode "limit=20" 2>/dev/null)" || return 1

    # Ranked, most specific first. A plain substring is deliberately not enough:
    # "night" sits inside arknights, and "mountain" inside the artist
    # urayama_(backmountain); both outrank anything anyone meant. The term has to
    # land on a word boundary — the start, or beside _ ( ) : / - characters.
    # Python rather than jq here purely for a correct regex escape: tags contain
    # parentheses and colons, which are regex metacharacters.
    python3 -c '
import json, re, sys

term = sys.argv[1]
min_posts = int(sys.argv[2])
artist_type = int(sys.argv[3])

try:
    tags = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(tags, list):
    sys.exit(0)

boundary = re.compile(r"(^|[_():/-])" + re.escape(term) + r"([_():/-]|$)")
usable = [t for t in tags if t.get("count", 0) >= min_posts]

def prefer_subjects(group):
    subjects = [t for t in group if t.get("type") != artist_type]
    return subjects or group

# An exact name is what was asked for, however rarely it is used.
for group in (
    [t for t in tags if t.get("name") == term and t.get("count", 0) > 0],
    prefer_subjects([t for t in usable if t.get("name", "").startswith(term)]),
    prefer_subjects([t for t in usable if boundary.search(t.get("name", ""))]),
):
    if group:
        print(group[0]["name"])
        break
' "$term" "$MIN_POSTS_FOR_FUZZY_MATCH" "$TAG_TYPE_ARTIST" <<< "$candidates" 2>/dev/null
}

# Lowercase, collapse whitespace.
normalized="$(printf '%s' "$QUERY" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ')"
normalized="${normalized# }"
normalized="${normalized% }"
[[ -n "$normalized" ]] || exit 0

read -r -a words <<< "$normalized"
joined="$(IFS=_; echo "${words[*]}")"

# A phrase that is itself a tag — raiden_shogun, blue_archive, zenless_zone_zero.
phrase_tag="$(lookup_tag "$joined")"
if [[ -n "$phrase_tag" ]]; then
    echo "$phrase_tag"
    exit 0
fi

# Otherwise every word narrows the search: "genshin ganyu" becomes
# genshin_impact AND ganyu_(genshin_impact).
if (( ${#words[@]} > 1 )); then
    resolved=()
    for word in "${words[@]}"; do
        tag="$(lookup_tag "$word")"
        resolved+=("${tag:-$word}")
    done
    echo "${resolved[*]}"
    exit 0
fi

# Nothing matched. Keep what was typed so the search comes back empty rather
# than silently showing something unrelated.
echo "$joined"
