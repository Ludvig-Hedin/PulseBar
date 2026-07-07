#!/usr/bin/env python3
"""Generate PulseBar app icon PNGs for AppIcon.appiconset."""

import struct, zlib, os

OUTPUT = 'PulseBar/Assets.xcassets/AppIcon.appiconset'
os.makedirs(OUTPUT, exist_ok=True)

def write_png_rgba(path, size, pixel_fn):
    raw = bytearray()
    for y in range(size):
        raw.append(0)  # filter: None
        for x in range(size):
            raw.extend(pixel_fn(x, y, size))
    compressed = zlib.compress(bytes(raw), 6)
    def chunk(tag, data):
        crc = zlib.crc32(tag + data) & 0xffffffff
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', crc)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)))
        f.write(chunk(b'IDAT', compressed))
        f.write(chunk(b'IEND', b''))

def icon_pixel(x, y, size):
    s = float(size)
    cr = s * 0.22

    # Rounded-rect mask
    rx = min(x, size - 1 - x)
    ry = min(y, size - 1 - y)
    if rx < cr and ry < cr:
        dx = cr - rx; dy = cr - ry
        if dx * dx + dy * dy > cr * cr:
            return (0, 0, 0, 0)  # transparent corner

    # EKG pulse wave (green on dark background)
    mx = s * 0.12
    ww = s * 0.76
    rel = (x - mx) / ww

    if 0.0 <= rel <= 1.0:
        wy = s * 0.5
        if   rel < 0.25: ty = wy
        elif rel < 0.35: ty = wy - ((rel - 0.25) / 0.10) * s * 0.28
        elif rel < 0.45: ty = wy - s * 0.28 + ((rel - 0.35) / 0.10) * s * 0.56
        elif rel < 0.55: ty = wy + s * 0.28 - ((rel - 0.45) / 0.10) * s * 0.56
        elif rel < 0.65: ty = wy - s * 0.28 + ((rel - 0.55) / 0.10) * s * 0.28
        else:             ty = wy

        lw = max(s * 0.035, 2.0)
        dist = abs(y - ty)
        if dist < lw * 1.5:
            a = max(0.0, 1.0 - dist / lw)
            return (
                int(28 * (1 - a) + 50 * a),
                int(28 * (1 - a) + 215 * a),
                int(30 * (1 - a) + 75 * a),
                255,
            )

    return (28, 28, 30, 255)  # dark background

SIZES = [
    ('icon_16x16',       16),
    ('icon_16x16@2x',    32),
    ('icon_32x32',       32),
    ('icon_32x32@2x',    64),
    ('icon_128x128',     128),
    ('icon_128x128@2x',  256),
    ('icon_256x256',     256),
    ('icon_256x256@2x',  512),
    ('icon_512x512',     512),
    ('icon_512x512@2x',  1024),
]

for name, size in SIZES:
    out = f'{OUTPUT}/{name}.png'
    print(f'Generating {name} ({size}x{size})...')
    write_png_rgba(out, size, icon_pixel)
    print(f'  -> {out}')

import json
contents = {
    "images": [
        {"idiom": "mac", "scale": "1x", "size": "16x16",   "filename": "icon_16x16.png"},
        {"idiom": "mac", "scale": "2x", "size": "16x16",   "filename": "icon_16x16@2x.png"},
        {"idiom": "mac", "scale": "1x", "size": "32x32",   "filename": "icon_32x32.png"},
        {"idiom": "mac", "scale": "2x", "size": "32x32",   "filename": "icon_32x32@2x.png"},
        {"idiom": "mac", "scale": "1x", "size": "128x128", "filename": "icon_128x128.png"},
        {"idiom": "mac", "scale": "2x", "size": "128x128", "filename": "icon_128x128@2x.png"},
        {"idiom": "mac", "scale": "1x", "size": "256x256", "filename": "icon_256x256.png"},
        {"idiom": "mac", "scale": "2x", "size": "256x256", "filename": "icon_256x256@2x.png"},
        {"idiom": "mac", "scale": "1x", "size": "512x512", "filename": "icon_512x512.png"},
        {"idiom": "mac", "scale": "2x", "size": "512x512", "filename": "icon_512x512@2x.png"},
    ],
    "info": {"author": "xcode", "version": 1},
}
with open(f'{OUTPUT}/Contents.json', 'w') as f:
    json.dump(contents, f, indent=2)

print('\nDone! All icons generated.')
