#!/usr/bin/env python3
import sys
import os
import subprocess

VENV_DIR = os.path.expanduser("~/.cache/quickshell/lyrics_venv")

# --- BOOTSTRAP VENV ---
def bootstrap():
    if not os.path.exists(VENV_DIR):
        try:
            subprocess.run([sys.executable, "-m", "venv", VENV_DIR], check=True)
            subprocess.run([os.path.join(VENV_DIR, "bin", "pip"), "install", "ytmusicapi", "cutlet", "fugashi", "unidic-lite"], check=True)
        except Exception:
            pass # Fail silently, fallback to standard libs if it fails
            
    if sys.prefix != VENV_DIR and os.path.exists(os.path.join(VENV_DIR, "bin", "python3")):
        # Use subprocess to run the script in venv and forward stdout to avoid O_CLOEXEC pipe closure
        proc = subprocess.run([os.path.join(VENV_DIR, "bin", "python3")] + sys.argv, capture_output=True, text=True)
        sys.stdout.write(proc.stdout)
        sys.stderr.write(proc.stderr)
        sys.stdout.flush()
        sys.exit(proc.returncode)

bootstrap()
# ----------------------

import urllib.request
import urllib.parse
import json
import re

try:
    from ytmusicapi import YTMusic
    import cutlet
    HAS_LIBS = True
    kks = cutlet.Cutlet()
    kks.use_foreign_spelling = False
except ImportError:
    HAS_LIBS = False

def is_japanese(text):
    return bool(re.search(r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF]', text))

def add_romaji(lines):
    if not HAS_LIBS:
        return lines
    
    new_lines = []
    for line in lines:
        text = line["text"]
        if is_japanese(text):
            romaji = kks.romaji(text)
            if romaji.strip() and romaji.lower() != text.lower():
                text = f"{text}<br><font size='-1' opacity='0.7'>{romaji.lower()}</font>"
        new_lines.append({"time": line["time"], "text": text})
    return new_lines

def _parse_lrc(lrc_text: str) -> list:
    lines = []
    for raw in lrc_text.splitlines():
        raw = raw.strip()
        if not raw: continue
        try:
            tag_end = raw.index("]")
            time_str = raw[1:tag_end]
            text = raw[tag_end + 1:].strip()
            mins, secs = time_str.split(":")
            timestamp = int(mins) * 60 + float(secs)
            lines.append({"time": timestamp, "text": text})
        except Exception:
            continue
    return sorted(lines, key=lambda x: x["time"])

def _is_match(d: dict, title: str, artist: str) -> bool:
    if not d.get("syncedLyrics"): return False
    r_title  = (d.get("trackName")  or "").lower()
    r_artist = (d.get("artistName") or "").lower()
    t, a = title.lower(), artist.lower()
    title_match = (t in r_title or r_title in t or any(word in r_title for word in t.split() if len(word) > 3))
    artist_match = (a in r_artist or r_artist in a or any(word in r_artist for word in a.split() if len(word) > 3))
    return title_match and artist_match

def fetch_lrclib(title: str, artist: str, duration: float) -> list:
    urls = [
        f"https://lrclib.net/api/get?track_name={urllib.parse.quote(title)}&artist_name={urllib.parse.quote(artist)}&duration={int(duration)}",
        f"https://lrclib.net/api/search?track_name={urllib.parse.quote(title)}&artist_name={urllib.parse.quote(artist)}",
        f"https://lrclib.net/api/search?q={urllib.parse.quote(title + ' ' + artist)}",
    ]
    for url in urls:
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=5) as r:
                data = json.loads(r.read().decode())
            if isinstance(data, list):
                data = next((d for d in data if _is_match(d, title, artist)), None)
            if data and _is_match(data, title, artist):
                lines = _parse_lrc(data["syncedLyrics"])
                if lines: return lines
        except Exception:
            continue
    return []

def fetch_ytmusic(title: str, artist: str) -> list:
    if not HAS_LIBS: return []
    try:
        yt = YTMusic()
        results = yt.search(f"{title} {artist}", filter="songs", limit=1)
        if not results: return []
        
        watch = yt.get_watch_playlist(videoId=results[0]["videoId"])
        lyrics_id = watch.get("lyrics")
        if not lyrics_id: return []
        
        lyrics_data = yt.get_lyrics(lyrics_id)
        if lyrics_data and lyrics_data.get("lyrics"):
            text = lyrics_data["lyrics"]
            # YTMusic usually returns raw text if unsynced. We will fake sync it if so
            lines = []
            for i, line in enumerate(text.splitlines()):
                if not line.strip(): continue
                lines.append({"time": i * 5, "text": line.strip()}) # Fake 5s pacing for unsynced
            return lines
    except Exception:
        pass
    return []

def main():
    if len(sys.argv) < 4:
        print("no_info", flush=True)
        sys.exit(0)
    title    = sys.argv[1]
    artist   = sys.argv[2]
    duration = float(sys.argv[3])
    if not title or not artist:
        print("no_info", flush=True)
        sys.exit(0)
        
    lines = []
    import time
    MAX_RETRIES = 5
    for attempt in range(MAX_RETRIES):
        lines = fetch_lrclib(title, artist, duration)
        if lines:
            break
        lines = fetch_ytmusic(title, artist)
        if lines:
            break
        time.sleep(1)
        
    if not lines:
        print("not_found", flush=True)
        sys.exit(0)
        
    lines = add_romaji(lines)
    
    parts = []
    for line in lines:
        parts.append(str(line["time"]))
        parts.append(line["text"].replace("§", ""))
    parts.append("ok")
    print("§".join(parts), flush=True)

if __name__ == "__main__":
    main()