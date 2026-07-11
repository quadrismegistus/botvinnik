#!/usr/bin/env python3
"""Build static/commentary.json from the Kaggle chess-reviews-from-youtube dataset.

Usage: python3 scripts/build-commentary.py

Reads data/kaggle.huberthamelin.chess-reviews-from-youtube/{chess_commentary_dataset,videos_list}.csv
and writes a compact lookup keyed by FEN piece placement (the dataset's side-to-move
and castling fields are CNN-defaulted and meaningless, so only the placement is trusted).

Output shape:
  { "videos": ["https://youtube.com/watch?v=...", ...],
    "positions": { "<placement>": [[comment, videoIndex, startSeconds], ...] } }
"""

import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / 'data' / 'kaggle.huberthamelin.chess-reviews-from-youtube'
OUT = ROOT / 'static' / 'commentary.json'

def detok(text: str) -> str:
    """Undo the dataset's Penn-Treebank-style tokenization ("I 'm gon na" etc.)."""
    text = re.sub(r"\s+('(?:s|m|re|ve|ll|d)|n't)\b", r'\1', text, flags=re.I)
    text = re.sub(r'\b(gon|wan) na\b', r'\1na', text, flags=re.I)
    text = re.sub(r'\s+([,.!?;:%])', r'\1', text)
    return re.sub(r'\s{2,}', ' ', text).strip()


videos = {}  # dataset video id -> url
for row in csv.DictReader(open(DATA / 'videos_list.csv')):
    # strip playlist params; keep just the watch id
    m = re.search(r'v=([\w-]{11})', row['URL'])
    videos[row['ID']] = f'https://www.youtube.com/watch?v={m.group(1)}' if m else row['URL']

video_urls = []  # index-compressed
video_index = {}

positions = {}
kept = 0
seen = set()
for row in csv.DictReader(open(DATA / 'chess_commentary_dataset.csv')):
    if row['label'] != 'chess':
        continue
    comment = detok(row['comment'])
    if len(comment) < 25:  # fragments aren't worth showing
        continue
    placement = row['FEN'].split(' ')[0]
    dedupe = (placement, comment)
    if dedupe in seen:
        continue
    seen.add(dedupe)
    url = videos.get(row['video_id'], '')
    if url not in video_index:
        video_index[url] = len(video_urls)
        video_urls.append(url)
    t = int(row['start_time_ms']) // 1000
    positions.setdefault(placement, []).append([comment, video_index[url], t])
    kept += 1

OUT.write_text(json.dumps({'videos': video_urls, 'positions': positions}, ensure_ascii=False))
size_mb = OUT.stat().st_size / 1e6
print(f'{kept} comments across {len(positions)} positions from {len(video_urls)} videos')
print(f'wrote {OUT} ({size_mb:.1f} MB)')
