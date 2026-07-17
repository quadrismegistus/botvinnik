#!/usr/bin/env python3
# Regenerate all app icons from the master (design/roboknight.png, RGBA):
# flatten onto the app's cream via the master's own alpha, then resize.
# iOS composites transparent home-screen icons onto BLACK, so the shipped
# icons must be opaque.  Usage: python3 scripts/make-icons.py
from PIL import Image

BG = '#f5f5f0'
src = Image.open('design/roboknight.png')
flat = Image.new('RGB', src.size, BG)
flat.paste(src, (0, 0), src.getchannel('A'))

flat.resize((1024, 1024), Image.LANCZOS).save('design/icon-1024-flat.png')
for size, out in [(512, 'static/icons/icon-512.png'), (192, 'static/icons/icon-192.png'), (180, 'static/icons/apple-touch-icon.png')]:
    flat.resize((size, size), Image.LANCZOS).save(out)
print('icons written')
