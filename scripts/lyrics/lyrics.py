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
import base64
import html
import time

try:
    from ytmusicapi import YTMusic
    import cutlet
    HAS_LIBS = True
    kks = cutlet.Cutlet()
    kks.use_foreign_spelling = False
except ImportError:
    HAS_LIBS = False

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
}

def clean_title(title: str) -> str:
    if not title:
        return ""
    # Extract inner title from Japanese brackets like: Artist「Song Title」 MV
    m = re.search(r'[「『]([^」』]+)[」』]', title)
    base = m.group(1) if m else title

    patterns = [
        r'\s*[\(\[\{][^\)\]\}]*(?:official|audio|video|mv|lyrics|lyric|remaster|deluxe|bonus|live|version|edit|prod\.)[^\)\]\}]*[\)\]\}]',
        r'\s*[\(\[\{](?:feat\.|featuring)[^\)\]\}]+[\)\]\}]',
        r'\s*-\s*(?:official|audio|video|music video|lyrics|mv|hd|remaster(?:ed)?).*$',
    ]
    for p in patterns:
        base = re.sub(p, '', base, flags=re.I)
    return base.strip()

def clean_artist(artist: str) -> str:
    if not artist:
        return ""
    cleaned = re.split(r'[,&/]|(?:\s+(?:feat\.|featuring|vs\.?)\s+)', artist, flags=re.I)[0]
    return cleaned.strip()

def is_japanese(text: str) -> bool:
    return bool(re.search(r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF]', text))

def add_romaji(lines: list) -> list:
    if not HAS_LIBS:
        return lines
    
    new_lines = []
    for line in lines:
        text = line["text"]
        if is_japanese(text):
            try:
                romaji = kks.romaji(text)
                if romaji.strip() and romaji.lower() != text.lower():
                    text = f"{text}<br><font size='-1' opacity='0.7'>{romaji.lower()}</font>"
            except Exception:
                pass
        new_lines.append({"time": line["time"], "text": text})
    return new_lines

def _parse_lrc(lrc_text: str) -> list:
    lines = []
    metadata_keys = ('ti:', 'ar:', 'al:', 'by:', 'offset:', 'length:', 're:', 've:', 'id:')
    meta_words = ('作词', '作曲', '编曲', '制作', 'written by', 'producer', 'lyrics by', 'composed by', 'arranged by')

    for raw in lrc_text.splitlines():
        raw = raw.strip()
        if not raw:
            continue
        raw_lower = raw.lower()
        if any(raw_lower.startswith(f'[{k}') for k in metadata_keys):
            continue

        matches = list(re.finditer(r'\[(\d{1,2}):(\d{2}(?:\.\d{1,3})?)\]', raw))
        if not matches:
            continue

        text = raw[matches[-1].end():].strip()
        t_lower = text.lower()
        if any(t_lower.startswith(w) for w in meta_words):
            continue

        for m in matches:
            mins, secs = m.group(1), m.group(2)
            timestamp = int(mins) * 60 + float(secs)
            lines.append({"time": round(timestamp, 2), "text": text})

    lines.sort(key=lambda x: x["time"])
    return lines

def _is_match(d: dict, title: str, artist: str) -> bool:
    if not d.get("syncedLyrics"):
        return False
    r_title  = (d.get("trackName")  or "").lower()
    r_artist = (d.get("artistName") or "").lower()
    t, a = title.lower(), artist.lower()
    ct, ca = clean_title(title).lower(), clean_artist(artist).lower()
    title_match = (
        t in r_title or r_title in t or
        ct in r_title or r_title in ct or
        any(word in r_title for word in ct.split() if len(word) > 2)
    )
    artist_match = (
        a in r_artist or r_artist in a or
        ca in r_artist or r_artist in ca or
        any(word in r_artist for word in ca.split() if len(word) > 2)
    )
    return title_match and artist_match

# ----------------- PROVIDERS -----------------

def fetch_lrclib(title: str, artist: str, duration: float) -> tuple:
    ct = clean_title(title)
    ca = clean_artist(artist)
    urls = []
    if duration > 0:
        urls.append(f"https://lrclib.net/api/get?track_name={urllib.parse.quote(ct)}&artist_name={urllib.parse.quote(ca)}&duration={int(duration)}")
        urls.append(f"https://lrclib.net/api/get?track_name={urllib.parse.quote(title)}&artist_name={urllib.parse.quote(artist)}&duration={int(duration)}")
    urls.append(f"https://lrclib.net/api/search?track_name={urllib.parse.quote(ct)}&artist_name={urllib.parse.quote(ca)}")
    urls.append(f"https://lrclib.net/api/search?q={urllib.parse.quote(ct + ' ' + ca)}")
    if ct != title or ca != artist:
        urls.append(f"https://lrclib.net/api/search?q={urllib.parse.quote(title + ' ' + artist)}")

    for url in urls:
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=3.5) as r:
                data = json.loads(r.read().decode())
            if isinstance(data, list):
                match = next((d for d in data if _is_match(d, title, artist)), None)
                if not match and data and data[0].get("syncedLyrics"):
                    match = data[0]
                if match and match.get("syncedLyrics"):
                    lines = _parse_lrc(match["syncedLyrics"])
                    if lines:
                        return "LRCLIB", lines
            elif isinstance(data, dict) and data.get("syncedLyrics"):
                lines = _parse_lrc(data["syncedLyrics"])
                if lines:
                    return "LRCLIB", lines
        except Exception:
            continue
    return None, []

def fetch_netease(title: str, artist: str) -> tuple:
    ct = clean_title(title)
    ca = clean_artist(artist)
    queries = [f"{ct} {ca}".strip(), ct.strip()]
    if ct != title:
        queries.append(f"{title} {artist}".strip())

    for q in queries:
        try:
            url = "https://music.163.com/api/cloudsearch/pc"
            data = urllib.parse.urlencode({"s": q, "type": 1, "limit": 4, "offset": 0}).encode()
            req = urllib.request.Request(url, data=data, headers={**HEADERS, "Referer": "https://music.163.com/"})
            with urllib.request.urlopen(req, timeout=3.5) as r:
                res = json.loads(r.read().decode())
                songs = res.get("result", {}).get("songs", [])
                if not songs:
                    continue
                song_id = songs[0]["id"]
                lrc_url = f"https://music.163.com/api/song/lyric?id={song_id}&lv=1&kv=1&tv=-1"
                req_lrc = urllib.request.Request(lrc_url, headers={**HEADERS, "Referer": "https://music.163.com/"})
                with urllib.request.urlopen(req_lrc, timeout=3.5) as r_lrc:
                    lrc_res = json.loads(r_lrc.read().decode())
                    raw = lrc_res.get("lrc", {}).get("lyric", "")
                    if raw:
                        lines = _parse_lrc(raw)
                        if lines:
                            return "Netease Cloud Music", lines
        except Exception:
            continue
    return None, []

def fetch_kugou(title: str, artist: str, duration: float = 0) -> tuple:
    ct = clean_title(title)
    ca = clean_artist(artist)
    query = f"{ct} {ca}".strip()
    q_enc = urllib.parse.quote(query)
    try:
        search_url = f"http://mobilecdn.kugou.com/api/v3/search/song?format=json&keyword={q_enc}&page=1&pagesize=3&showtype=1"
        req = urllib.request.Request(search_url, headers={"User-Agent": "Mozilla/5.0 (Android; Mobile)"})
        with urllib.request.urlopen(req, timeout=3.5) as r:
            info = json.loads(r.read().decode()).get("data", {}).get("info", [])
            if not info:
                return None, []
            hash_val = info[0]["hash"]
            dur_ms = int(duration * 1000) if duration > 0 else info[0].get("duration", 0) * 1000
            lrc_search_url = f"http://krcs.kugou.com/search?ver=1&man=yes&client=mobi&keyword={q_enc}&duration={dur_ms}&hash={hash_val}"
            req_c = urllib.request.Request(lrc_search_url, headers=HEADERS)
            with urllib.request.urlopen(req_c, timeout=3.5) as r_c:
                cands = json.loads(r_c.read().decode()).get("candidates", [])
                if not cands:
                    return None, []
                c = cands[0]
                dl_url = f"http://lyrics.kugou.com/download?ver=1&client=pc&id={c['id']}&accesskey={c['accesskey']}&fmt=lrc&charset=utf8"
                req_dl = urllib.request.Request(dl_url, headers=HEADERS)
                with urllib.request.urlopen(req_dl, timeout=3.5) as r_dl:
                    content = json.loads(r_dl.read().decode()).get("content", "")
                    if content:
                        raw = base64.b64decode(content).decode("utf-8", errors="ignore")
                        lines = _parse_lrc(raw)
                        if lines:
                            return "Kugou", lines
    except Exception:
        pass
    return None, []

def fetch_qqmusic(title: str, artist: str) -> tuple:
    ct = clean_title(title)
    ca = clean_artist(artist)
    q_enc = urllib.parse.quote(f"{ct} {ca}".strip())
    try:
        url = f"https://c.y.qq.com/splcloud/fcgi-bin/smartbox_new.fcg?key={q_enc}&format=json"
        req = urllib.request.Request(url, headers={**HEADERS, "Referer": "https://y.qq.com/"})
        with urllib.request.urlopen(req, timeout=3.5) as r:
            songs = json.loads(r.read().decode()).get("data", {}).get("song", {}).get("itemlist", [])
            if not songs:
                return None, []
            songmid = songs[0]["mid"]
            lrc_url = f"https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid={songmid}&format=json&nobase64=1"
            req_lrc = urllib.request.Request(lrc_url, headers={**HEADERS, "Referer": "https://y.qq.com/"})
            with urllib.request.urlopen(req_lrc, timeout=3.5) as r_lrc:
                raw = json.loads(r_lrc.read().decode()).get("lyric", "")
                if raw:
                    lines = _parse_lrc(html.unescape(raw))
                    if lines:
                        return "QQ Music", lines
    except Exception:
        pass
    return None, []

def fetch_ytmusic(title: str, artist: str) -> tuple:
    if not HAS_LIBS:
        return None, []
    try:
        yt = YTMusic()
        results = yt.search(f"{title} {artist}", filter="songs", limit=1)
        if not results:
            return None, []

        watch = yt.get_watch_playlist(videoId=results[0]["videoId"])
        lyrics_id = watch.get("lyrics")
        if not lyrics_id:
            return None, []

        lyrics_data = yt.get_lyrics(lyrics_id)
        if lyrics_data and lyrics_data.get("lyrics"):
            text = lyrics_data["lyrics"]
            # YTMusic usually returns raw text if unsynced. Pacing fallback
            lines = []
            for i, line in enumerate(text.splitlines()):
                if not line.strip():
                    continue
                lines.append({"time": i * 4.5, "text": line.strip()})
            return "YouTube Music", lines
    except Exception:
        pass
    return None, []

# ----------------- MAIN FLOW -----------------

def main():
    if len(sys.argv) < 3:
        print("no_info", flush=True)
        sys.exit(0)

    title    = sys.argv[1].strip()
    artist   = sys.argv[2].strip() if len(sys.argv) > 2 else ""
    duration = float(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].replace('.', '', 1).isdigit() else 0.0
    preferred = sys.argv[4].lower().strip() if len(sys.argv) > 4 else "auto"

    if not title:
        print("no_info", flush=True)
        sys.exit(0)

    provider_name = ""
    lines = []

    # Map requested provider
    if preferred == "lrclib":
        provider_name, lines = fetch_lrclib(title, artist, duration)
    elif preferred in ("netease", "163"):
        provider_name, lines = fetch_netease(title, artist)
    elif preferred == "kugou":
        provider_name, lines = fetch_kugou(title, artist, duration)
    elif preferred in ("qqmusic", "qq"):
        provider_name, lines = fetch_qqmusic(title, artist)
    elif preferred in ("ytmusic", "youtube"):
        provider_name, lines = fetch_ytmusic(title, artist)
    else:
        # "auto" prioritized fallback chain:
        # 1. LRCLIB (global synced lyrics)
        # 2. Netease Cloud Music (world-class CJK/Anime/Western coverage)
        # 3. Kugou Music (massive synced database)
        # 4. QQ Music (Tencent library)
        # 5. YouTube Music (official fallback)
        chain = [
            lambda: fetch_lrclib(title, artist, duration),
            lambda: fetch_netease(title, artist),
            lambda: fetch_kugou(title, artist, duration),
            lambda: fetch_qqmusic(title, artist),
            lambda: fetch_ytmusic(title, artist),
        ]
        for fetcher in chain:
            try:
                p_name, p_lines = fetcher()
                if p_lines:
                    provider_name = p_name
                    lines = p_lines
                    break
            except Exception:
                continue

    if not lines:
        print("not_found", flush=True)
        sys.exit(0)

    # Enhance Japanese text with romaji annotations
    lines = add_romaji(lines)

    parts = []
    for line in lines:
        parts.append(str(line["time"]))
        parts.append(line["text"].replace("§", ""))

    # Append provider metadata
    parts.append("provider")
    parts.append(provider_name or "Automatic")
    parts.append("ok")

    print("§".join(parts), flush=True)

if __name__ == "__main__":
    main()