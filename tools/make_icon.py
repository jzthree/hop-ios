#!/usr/bin/env python3
"""hop app icon: a terminal prompt with a live cursor — ❯▊ — in hop's palette.

Three appearances (iOS 18): default (deep purple night), dark (near-black),
tinted (grayscale for the system's tint). Shapes are drawn as solid masks and
colour is composited through them, so strokes stay clean; 4x supersampled.
"""
from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = S * 4


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vgrad(top, bottom):
    img = Image.new("RGB", (SS, SS))
    d = ImageDraw.Draw(img)
    for y in range(SS):
        d.line([(0, y), (SS, y)], fill=lerp(top, bottom, y / SS))
    return img


def background(top, bottom, glow=None, glow_alpha=90):
    img = vgrad(top, bottom)
    if glow:
        gl = Image.new("L", (SS, SS), 0)
        gd = ImageDraw.Draw(gl)
        cx, cy, r = int(SS * 0.44), int(SS * 0.54), int(SS * 0.46)
        gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=glow_alpha)
        gl = gl.filter(ImageFilter.GaussianBlur(SS // 7))
        img = Image.composite(Image.new("RGB", (SS, SS), glow), img, gl)
    return img


def masks():
    """(chevron mask, cursor mask) as L images — solid, artifact-free."""
    chev = Image.new("L", (SS, SS), 0)
    d = ImageDraw.Draw(chev)
    w = int(SS * 0.088)
    x0, x1 = int(SS * 0.235), int(SS * 0.455)
    ymid = int(SS * 0.5)
    yspan = int(SS * 0.20)
    pts = [(x0, ymid - yspan), (x1, ymid), (x0, ymid + yspan)]
    d.line(pts, fill=255, width=w, joint="curve")
    r = w // 2
    for (px, py) in [pts[0], pts[2]]:
        d.ellipse([px - r, py - r, px + r, py + r], fill=255)

    cur = Image.new("L", (SS, SS), 0)
    dc = ImageDraw.Draw(cur)
    bw, bh = int(SS * 0.14), int(SS * 0.31)
    bx = int(SS * 0.565)
    by = ymid - bh // 2 + int(SS * 0.045)
    dc.rounded_rectangle([bx, by, bx + bw, by + bh],
                         radius=int(SS * 0.02), fill=255)
    return chev, cur


def compose(bg, chev_ink_top, chev_ink_bot, cursor_ink, bloom_alpha=0.5):
    chev, cur = masks()
    both = Image.new("L", (SS, SS), 0)
    both.paste(chev, (0, 0), chev)
    both.paste(cur, (0, 0), cur)

    out = bg.convert("RGB")
    # bloom first, beneath the crisp shapes
    halo = both.filter(ImageFilter.GaussianBlur(SS // 34))
    halo = halo.point(lambda a: int(a * bloom_alpha))
    out = Image.composite(Image.new("RGB", (SS, SS), cursor_ink), out, halo)
    # chevron carries a vertical gradient; cursor is flat glow
    out = Image.composite(vgrad(chev_ink_top, chev_ink_bot), out, chev)
    out = Image.composite(Image.new("RGB", (SS, SS), cursor_ink), out, cur)
    return out.resize((S, S), Image.LANCZOS)


LAV_A = (0xC6, 0xB0, 0xFF)
LAV_B = (0x96, 0x68, 0xF2)
GLOW = (0xA8, 0x55, 0xF7)

compose(background((0x1C, 0x14, 0x33), (0x0B, 0x0D, 0x14), glow=(0x35, 0x1F, 0x63)),
        LAV_A, LAV_B, GLOW).save("icon-1024.png")

compose(background((0x0A, 0x08, 0x12), (0x04, 0x05, 0x08), glow=(0x2A, 0x18, 0x52),
                   glow_alpha=70),
        LAV_A, LAV_B, GLOW, bloom_alpha=0.4).save("icon-1024-dark.png")

compose(background((0x11, 0x11, 0x13), (0x05, 0x05, 0x06)),
        (0xEE, 0xEE, 0xF2), (0xB4, 0xB4, 0xC0), (0xD6, 0xD6, 0xDE),
        bloom_alpha=0.25).save("icon-1024-tinted.png")
print("wrote icon-1024{,-dark,-tinted}.png")
