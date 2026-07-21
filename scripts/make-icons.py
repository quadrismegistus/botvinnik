#!/usr/bin/env python3
"""Regenerate every baked icon from ONE master: design/roboknight.png.

    python3 scripts/make-icons.py            # write
    python3 scripts/make-icons.py --check    # verify the tree matches the master

Why a script and not a hand-export: the iOS set alone is 15 PNGs whose sizes
are dictated by its Contents.json, and the two appicon sets share names between
entries (app_icon_32.png is both 16x16@2x and 32x32@1x). Hand-exporting that
guarantees one size eventually drifts, and a drifted app icon is invisible
until App Store validation rejects it. The sizes below are READ from each
Contents.json rather than restated here, so adding an entry in Xcode is enough.

Two properties are load-bearing:

FLATTEN. The master is a black glyph on transparency. iOS refuses icons with an
alpha channel (Xcode/App Store validation), and where alpha is tolerated it is
composited onto BLACK — which would render a black glyph invisible. So every
app icon is written as RGB with no alpha, composited onto the app's cream. The
cream is the colour that already shipped; this is continuity, not a new call.

THE MASKABLE ICON IS A DIFFERENT EXPORT. Android crops maskable icons to
whatever shape the launcher picks, guaranteeing only a circle of 80% of the
icon's width. The plain framing does not survive that: the master's ink sits
higher than centre, so its top corner lands 448/512 from centre against a safe
radius of 410 and the ears clip. The maskable variants therefore re-centre the
ink and scale it until its bounding box fits inside that circle. Before this
they were byte-identical copies of the plain icons, which is the failure the
manifest's `purpose: "maskable"` was promising against.

MACOS IS THE EXCEPTION, DELIBERATELY. iOS masks an app icon with its own
superellipse, so a full-bleed opaque square is what you hand it. macOS does
not mask anything — the Dock shows exactly the pixels given, and every native
icon is a rounded plate floating in a transparent margin (Apple's grid: an
824pt body on a 1024pt canvas). The stock Flutter icon this replaces was drawn
that way; a full-bleed cream square would be the one tile in the Dock with
square corners. So the macOS set keeps alpha and gets the plate.

The in-app mark (assets/roboknight.png) also keeps its alpha, because it is
tinted at runtime via ImageIcon's srcIn blend and must not carry a background.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover - environment guard
    sys.exit('make-icons: needs Pillow — `pip install Pillow`')

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / 'design/roboknight.png'

# The cream the shipped icons already wear. Changing it changes every app icon.
BG = (245, 245, 240)

# Fraction of the icon's width that Android guarantees a maskable icon keeps,
# as a centred circle. Content whose bounding box fits inside survives any crop.
MASKABLE_SAFE = 0.80
# What we actually fit the ink to. Sitting exactly ON the guaranteed edge means
# the resampled antialiasing at 192px spills past it — measured at 77.8px
# against a 76.8px radius. The margin costs 2% of the glyph and makes the
# safe-zone assertion below true of the shipped pixels, not just the geometry.
MASKABLE_FIT = 0.78

# Apple's macOS icon grid, as fractions of the canvas: an 824pt rounded plate
# on 1024pt, corner radius 185.4pt. Everything outside the plate is transparent.
MACOS_PLATE = 824 / 1024
MACOS_RADIUS = 185.4 / 824

# Ink height as a fraction of the in-app mark's square, chosen to sit at the
# same optical weight as the Material icons beside it in the app bar.
MARK_INK_HEIGHT = 0.90

# Alpha at or above which a pixel counts as ink. The master carries a haze of
# fully-transparent pixels with non-black RGB down to y=935; PIL's getbbox()
# counts any non-zero alpha and would report the glyph 130px taller than it is.
INK_ALPHA = 16


def ink_box(alpha: Image.Image) -> tuple[int, int, int, int]:
    """Bounding box of the actual ink, ignoring transparent haze."""
    box = alpha.point(lambda v: 255 if v >= INK_ALPHA else 0).getbbox()
    if box is None:
        raise SystemExit('make-icons: the master has no ink')
    return box


def flatten(rgba: Image.Image) -> Image.Image:
    """Composite onto the cream, dropping alpha. Never resize an RGBA master
    first: its transparent pixels carry non-black RGB, and a filtered resize
    would drag that grey into the glyph's edges as a halo."""
    out = Image.new('RGB', rgba.size, BG)
    out.paste(rgba, (0, 0), rgba.getchannel('A'))
    return out


def maskable_master(rgba: Image.Image) -> Image.Image:
    """The plain framing re-centred and shrunk to fit the maskable safe circle."""
    size = rgba.width
    x0, y0, x1, y1 = ink_box(rgba.getchannel('A'))
    ink = rgba.crop((x0, y0, x1, y1))
    w, h = ink.size
    # A box fits in a circle exactly when its diagonal is the diameter.
    scale = (MASKABLE_FIT * size) / math.hypot(w, h)
    if scale > 1:  # already inside the circle; do not upscale the master
        scale = 1.0
    new = (max(1, round(w * scale)), max(1, round(h * scale)))
    ink = ink.resize(new, Image.LANCZOS)
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    canvas.paste(ink, ((size - new[0]) // 2, (size - new[1]) // 2))
    return flatten(canvas)


def macos_master(flat: Image.Image) -> Image.Image:
    """The flat icon inset into Apple's rounded plate, transparent outside it.

    Drawn at 4x and downsampled: PIL's rounded_rectangle has hard edges, and a
    jagged corner is the tell that separates a real macOS icon from a resized
    screenshot."""
    size = flat.width
    ss = 4
    plate = round(size * MACOS_PLATE)
    body = flat.resize((plate * ss, plate * ss), Image.LANCZOS).convert('RGBA')
    mask = Image.new('L', (plate * ss, plate * ss), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, plate * ss - 1, plate * ss - 1),
        radius=round(plate * ss * MACOS_RADIUS),
        fill=255,
    )
    body.putalpha(mask)
    body = body.resize((plate, plate), Image.LANCZOS)
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    off = (size - plate) // 2
    canvas.paste(body, (off, off))
    return canvas


def in_app_mark(rgba: Image.Image, size: int) -> Image.Image:
    """Black-on-transparent square for ImageIcon, which tints through alpha."""
    x0, y0, x1, y1 = ink_box(rgba.getchannel('A'))
    # Resize the ALPHA alone; the master's RGB is meaningless where alpha is 0.
    alpha = rgba.getchannel('A').crop((x0, y0, x1, y1))
    h = round(size * MARK_INK_HEIGHT)
    w = max(1, round(alpha.width * h / alpha.height))
    alpha = alpha.resize((w, h), Image.LANCZOS)
    canvas = Image.new('L', (size, size), 0)
    canvas.paste(alpha, ((size - w) // 2, (size - h) // 2))
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.putalpha(canvas)
    return out


def appicon_sizes(contents: Path) -> dict[str, int]:
    """filename -> pixel size, read from an .appiconset's Contents.json.

    Entries share filenames (app_icon_32.png is 16x16@2x AND 32x32@1x), so a
    repeat is fine as long as it agrees; a disagreement is a broken set."""
    sizes: dict[str, int] = {}
    for image in json.loads(contents.read_text())['images']:
        name = image.get('filename')
        if not name:
            continue
        px = round(float(image['size'].split('x')[0]) * float(image['scale'].rstrip('x')))
        if sizes.setdefault(name, px) != px:
            raise SystemExit(f'{contents}: {name} is claimed at two sizes')
    if not sizes:
        raise SystemExit(f'{contents}: no images')
    return sizes


def build() -> dict[str, Image.Image]:
    """Every output, keyed by repo-relative path. Nothing is written here, so
    --check can compare against the tree without touching it."""
    master = Image.open(MASTER)
    if master.size != (1024, 1024) or master.mode != 'RGBA':
        raise SystemExit(f'{MASTER}: expected 1024x1024 RGBA, got {master.size} {master.mode}')
    master = master.convert('RGBA')

    plain = flatten(master)
    masked = maskable_master(master)

    out: dict[str, Image.Image] = {
        # kept in design/ as the flat master the app icons derive from — it is
        # the thing to open when checking what the icon looks like composited
        'design/icon-1024-flat.png': plain,
        'flutter/web/favicon.png': plain.resize((192, 192), Image.LANCZOS),
        'flutter/web/icons/Icon-192.png': plain.resize((192, 192), Image.LANCZOS),
        'flutter/web/icons/Icon-512.png': plain.resize((512, 512), Image.LANCZOS),
        'flutter/web/icons/Icon-maskable-192.png': masked.resize((192, 192), Image.LANCZOS),
        'flutter/web/icons/Icon-maskable-512.png': masked.resize((512, 512), Image.LANCZOS),
        # tinted at runtime beside the wordmark, so it keeps its alpha
        'flutter/assets/roboknight.png': in_app_mark(master, 128),
    }

    for appiconset, source in (
        ('flutter/macos/Runner/Assets.xcassets/AppIcon.appiconset', macos_master(plain)),
        ('flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset', plain),
    ):
        for name, px in appicon_sizes(ROOT / appiconset / 'Contents.json').items():
            out[f'{appiconset}/{name}'] = source.resize((px, px), Image.LANCZOS)

    return out


def assert_sane(out: dict[str, Image.Image]) -> None:
    """The tool's exit code proves nothing. Check the pixels we are about to
    ship: an app icon that kept its alpha, or a maskable that is a copy of the
    plain one, both look fine in a file listing."""
    for path, image in out.items():
        wants_alpha = path.endswith('assets/roboknight.png') or '/macos/' in path
        if (image.mode == 'RGBA') != wants_alpha:
            raise SystemExit(f'{path}: mode {image.mode}, wants_alpha={wants_alpha}')
        if image.width != image.height:
            raise SystemExit(f'{path}: not square ({image.size})')
        if '/ios/' in path:
            # An opaque corner is the cheap proof that iOS got no alpha and no
            # pre-rounded artwork: iOS applies its own mask over the full bleed.
            if image.getpixel((0, 0)) != BG:
                raise SystemExit(f'{path}: corner is {image.getpixel((0, 0))}, wanted the cream')
        if '/macos/' in path and image.width >= 64:
            # and a transparent corner is the proof macOS got the plate
            if image.getpixel((0, 0))[3] != 0:
                raise SystemExit(f'{path}: corner is opaque; the macOS plate did not apply')
            if image.getpixel((image.width // 2, image.height // 2))[3] != 255:
                raise SystemExit(f'{path}: centre is transparent')

    for size in (192, 512):
        plain = out[f'flutter/web/icons/Icon-{size}.png']
        masked = out[f'flutter/web/icons/Icon-maskable-{size}.png']
        if plain.tobytes() == masked.tobytes():
            raise SystemExit(f'maskable-{size} is a copy of the plain icon')
        # The safe circle, measured on the shipped pixels rather than assumed
        # from the scale factor: every non-background pixel must sit inside it.
        box = masked.convert('L').point(lambda v: 0 if abs(v - 245) < 12 else 255).getbbox()
        # getbbox()'s right/bottom are exclusive; the last ink pixel is one in.
        x0, y0, x1, y1 = box[0], box[1], box[2] - 1, box[3] - 1
        cx = cy = (size - 1) / 2
        far = max(
            math.hypot(x - cx, y - cy)
            for x, y in ((x0, y0), (x1, y0), (x0, y1), (x1, y1))
        )
        if far > MASKABLE_SAFE * size / 2:
            raise SystemExit(f'maskable-{size}: ink reaches {far:.1f}px, safe radius is '
                             f'{MASKABLE_SAFE * size / 2:.1f}px')

    mark = out['flutter/assets/roboknight.png']
    if mark.getchannel('A').getextrema()[1] != 255:
        raise SystemExit('the in-app mark has no opaque ink')
    if min(mark.convert('RGBA').getchannel('R').getextrema()) != 0:
        raise SystemExit('the in-app mark is not black; ImageIcon tints via alpha only')


def main() -> int:
    check = '--check' in sys.argv[1:]
    out = build()
    assert_sane(out)

    if check:
        bad = []
        for path, image in sorted(out.items()):
            f = ROOT / path
            if not f.exists():
                bad.append(f'{path}: missing')
                continue
            have = Image.open(f)
            # Compare PIXELS, not bytes: a different zlib would re-encode the
            # same image differently and that is not drift.
            # Mode BEFORE pixels. `have.convert(image.mode)` drops an extra
            # alpha channel and keeps the RGB, so an iOS icon that regained
            # alpha compared EQUAL — and alpha in an iOS app icon is an App
            # Store rejection, which the header calls load-bearing.
            if have.mode != image.mode:
                bad.append(f"{path}: mode {have.mode}, expected {image.mode}")
                continue
            if have.size != image.size or have.tobytes() != image.tobytes():
                bad.append(f'{path}: differs from the master ({have.size} {have.mode})')
        for line in bad:
            print(line, file=sys.stderr)
        print(f'checked {len(out)} icons against {MASTER.name}: '
              f'{"OK" if not bad else f"{len(bad)} STALE"}')
        return 1 if bad else 0

    for path, image in sorted(out.items()):
        f = ROOT / path
        f.parent.mkdir(parents=True, exist_ok=True)
        image.save(f, 'PNG', optimize=True)
        # Re-read what landed on disk. A save that silently wrote the wrong
        # size or kept an alpha channel is exactly the failure this file exists
        # to prevent, and it is not visible in the exit code.
        back = Image.open(f)
        if back.size != image.size or back.mode != image.mode:
            raise SystemExit(f'{path}: wrote {back.size} {back.mode}, wanted {image.size} {image.mode}')
        print(f'{back.size[0]:>4}x{back.size[1]:<4} {back.mode:<4} {path}')
    print(f'{len(out)} icons written from {MASTER.name}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
