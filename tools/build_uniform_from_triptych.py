"""
One-shot pipeline: AI triptych PNG  -->  reisen_uniform.zip (10 frames).

Steps
-----
1. Split triptych into front / side / back panels.
2. Remove background (flood-fill from corners) + inpaint mask/template artifacts.
3. Fit each panel onto its canvas size.
4. Rotate each view ±8 deg around the top pivot to get three tilted variants.
5. Composite all 10 slots onto the armor_grass atlas UV layout.
6. Compress atlas PNG -> TEX, patch build/anim names, write reisen_uniform.zip.

Usage
-----
  python tools/build_uniform_from_triptych.py
  python tools/build_uniform_from_triptych.py path/to/triptych.png
  python tools/build_uniform_from_triptych.py front.png side.png back.png

With no arguments, uses the default unified triptych under tools/src/.
With three paths, treats them as front / side / back (same clean + canvas + zip pipeline).

"""

from __future__ import annotations

import argparse
import math
import os
import shutil
import struct
import subprocess
import sys
import zipfile
from collections import deque
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

MOD_DIR = Path(__file__).resolve().parents[1]
TEMP    = MOD_DIR / "temp"
ANIM    = MOD_DIR / "anim"
VANILLA = Path(r"E:\SteamLibrary\steamapps\common\Don't Starve Together\data\anim")
KTECH   = Path(r"E:\Workspace\ktools\build\Release\ktech.exe")
STEX    = MOD_DIR / "tools" / "bin" / "stex_v0.6" / "bin" / "Stex.exe"

DEFAULT_TRIPTYCH = MOD_DIR / "tools" / "src" / "reisen_jacket_three_views_dst_handdrawn_v3_sidefix.png"
DEFAULT_SEPARATE_VIEWS = (
    MOD_DIR / "tools" / "src" / "reisen_jacket_front_ai_v3.png",
    MOD_DIR / "tools" / "src" / "reisen_jacket_side_ai_v3.png",
    MOD_DIR / "tools" / "src" / "reisen_jacket_back_ai_v3.png",
)
TEMPLATE_ZIP  = "armor_grass.zip"
GROUND_SRC    = MOD_DIR / "tools" / "src" / "nightmail_inv_clean.png"

MOD_BUILD_NAME = "reisen_uniform"
MOD_BANK_NAME  = "reisen_uniform"

# Canvas sizes that match adj_*_mask.png
CANVAS = {"front": (720, 1040), "side": (688, 1048), "back": (728, 992)}
ORDER  = ("front", "back", "side")
FLIP_H: set[str] = set()   # side panel already faces left in this triptych
SCALE_H = {"front": 0.696, "side": 0.696, "back": 0.696, "ground": 0.92}
SCALE_W = {"front": 0.98, "side": 0.98, "back": 0.98, "ground": 0.92}
SCALE   = SCALE_H
VEST_REF_ZIP = VANILLA / "armor_sweatervest.zip"
TILT_ANGLES  = (0, -8, +8)
TILT_TOP_FRAC = 0.15

SHOULDER_ERASE_SIDE_PX   = 0
SHOULDER_ERASE_HEIGHT_PX = 22
SHOULDER_FEATHER_PX      = 5
SIDE_ARM_ERASE_FRAC      = 0.0

SHADOW_SHOULDER_STRENGTH = 0.18
SHADOW_WAIST_STRENGTH    = 0.12
SHADOW_BLUR_RADIUS       = 3

BACK_VERTICAL_SHIFT_PX = 15
BACK_NECK_ARC_RADIUS   = 35
BACK_NECK_TOP_FADE_PX  =  0

FRAME_MAP = {
    0:  ("front",  0),
    1:  ("front", -8),
    2:  ("front", +8),
    3:  ("side",   0),
    4:  ("side",  -8),
    5:  ("side",  +8),
    6:  ("back",   0),
    7:  ("back",  -8),
    8:  ("back",  +8),
    13: ("ground", 0),
}

# ---------------------------------------------------------------------------
# Step 1 – Split triptych
# ---------------------------------------------------------------------------

def _split_panels(rgba: np.ndarray) -> list[tuple[int, int, int, int]]:
    from scipy.ndimage import label

    h, w, _ = rgba.shape
    rgb = rgba[:, :, :3].astype(np.int16)
    corner = (
        rgb[0:30, 0:30].reshape(-1, 3).mean(0)
        + rgb[0:30, -30:].reshape(-1, 3).mean(0)
        + rgb[-30:, 0:30].reshape(-1, 3).mean(0)
        + rgb[-30:, -30:].reshape(-1, 3).mean(0)
    ) / 4.0
    d = np.abs(rgb - corner[None, None, :]).sum(2)
    lab, n = label(d > 50)

    boxes: list[tuple[int, int, int, int, int]] = []
    for k in range(1, n + 1):
        ys, xs = np.where(lab == k)
        if len(xs) < 5000:
            continue
        x0, x1 = int(xs.min()), int(xs.max()) + 1
        y0, y1 = int(ys.min()), int(ys.max()) + 1
        boxes.append(((lab[y0:y1, x0:x1] == k).sum(), x0, y0, x1, y1))

    boxes.sort(reverse=True)
    if len(boxes) < 3:
        raise RuntimeError(
            f"Found only {len(boxes)} large foreground regions (need 3). "
            "Check that the triptych has three clearly separated garments."
        )
    top3 = sorted(boxes[:3], key=lambda t: t[1])
    return [(b[1], b[2], b[3], b[4]) for b in top3]


# ---------------------------------------------------------------------------
# Step 2 – Remove background + inpaint mask artifacts
# ---------------------------------------------------------------------------

def _flood_bg_alpha(rgba: np.ndarray, tol: int = 55) -> np.ndarray:
    pad = 30
    h, w, _ = rgba.shape
    big = np.empty((h + 2 * pad, w + 2 * pad, 4), dtype=np.uint8)
    big[:] = [255, 255, 255, 255]
    big[pad:pad+h, pad:pad+w] = rgba
    bh, bw = big.shape[:2]
    rgb = big[:, :, :3].astype(np.int16)
    ref = (
        rgb[0:8, 0:8].reshape(-1, 3).mean(0)
        + rgb[0:8, -8:].reshape(-1, 3).mean(0)
        + rgb[-8:, 0:8].reshape(-1, 3).mean(0)
        + rgb[-8:, -8:].reshape(-1, 3).mean(0)
    ) / 4.0

    vis   = np.zeros((bh, bw), dtype=bool)
    sheet = np.zeros((bh, bw), dtype=bool)
    q: deque[tuple[int, int]] = deque()

    def _push(y: int, x: int) -> None:
        if y < 0 or y >= bh or x < 0 or x >= bw or vis[y, x]:
            return
        vis[y, x] = True
        if float(np.abs(rgb[y, x] - ref).sum()) <= tol:
            sheet[y, x] = True
            q.append((y, x))

    for x in range(bw):
        _push(0, x); _push(bh - 1, x)
    for y in range(bh):
        _push(y, 0); _push(y, bw - 1)
    while q:
        y, x = q.popleft()
        _push(y-1, x); _push(y+1, x); _push(y, x-1); _push(y, x+1)

    out = big.copy()
    out[sheet, 3] = 0
    return out[pad:pad+h, pad:pad+w]


def _inpaint_mask_artifacts(bgr: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    from scipy.ndimage import binary_closing, binary_opening

    lab    = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB)
    L      = lab[:, :, 0].astype(np.float32)
    a_ch   = lab[:, :, 1].astype(np.float32)
    b_ch   = lab[:, :, 2].astype(np.float32)
    chroma = np.sqrt((a_ch - 128.0) ** 2 + (b_ch - 128.0) ** 2)

    blur      = cv2.GaussianBlur(L, (0, 0), sigmaX=1.8)
    local_var = cv2.blur((L - blur) ** 2, (11, 11))
    local_std = np.sqrt(np.maximum(local_var, 0.0))

    suspect = (
        (alpha > 30)
        & (L > 155) & (L < 238)
        & (chroma < 22)
        & ((local_std > 3.0) | ((local_std < 2.0) & (L > 175) & (L < 225)))
    )
    suspect = binary_closing(suspect, iterations=2)
    suspect = binary_opening(suspect, iterations=1)
    m = (suspect.astype(np.uint8) * 255)
    if m.sum() == 0:
        return bgr
    return cv2.inpaint(bgr, m, inpaintRadius=4, flags=cv2.INPAINT_TELEA)


def _strip_panel_frame(rgba: np.ndarray,
                       dark_lum: float = 80.0,
                       dark_frac: float = 0.25,
                       max_strip: int = 22,
                       min_opaque: int = 50) -> np.ndarray:
    """Strip rectangular dark border frame left after flood-fill.

    Scans inward from each edge of the opaque-content bounding box.
    Columns/rows with fewer than `min_opaque` opaque pixels are treated as
    sparse edge noise and always stripped (scan continues past them).
    Stops only when a *dense* row/col is reached that is not mostly dark.
    """
    alpha = rgba[:, :, 3]
    opaque = alpha > 30
    if not opaque.any():
        return rgba

    ys, xs = np.where(opaque)
    r0, r1 = int(ys.min()), int(ys.max()) + 1
    c0, c1 = int(xs.min()), int(xs.max()) + 1

    rgb = rgba[:, :, :3].astype(np.float32)
    lum = 0.299 * rgb[:, :, 0] + 0.587 * rgb[:, :, 1] + 0.114 * rgb[:, :, 2]

    out = rgba.copy()

    def _row_decision(r: int):
        """Return True=strip, False=stop, None=sparse→strip and continue."""
        row_a = alpha[r, c0:c1]
        row_l = lum[r, c0:c1]
        op    = row_a > 30
        cnt   = int(op.sum())
        if cnt == 0:
            return None
        if cnt < min_opaque:
            return None   # sparse edge noise
        df = float((row_l[op] < dark_lum).sum()) / float(cnt)
        return df >= dark_frac   # True=dark frame, False=content

    def _col_decision(c: int):
        """Return True=strip, False=stop, None=sparse→strip and continue."""
        col_a = alpha[r0:r1, c]
        col_l = lum[r0:r1, c]
        op    = col_a > 30
        cnt   = int(op.sum())
        if cnt == 0:
            return None
        if cnt < min_opaque:
            return None
        df = float((col_l[op] < dark_lum).sum()) / float(cnt)
        return df >= dark_frac

    # Top
    for i in range(r0, min(r0 + max_strip, r1)):
        d = _row_decision(i)
        if d is False:
            break
        out[i, :, 3] = 0          # strip (True=frame or None=sparse)

    # Bottom
    for i in range(r1 - 1, max(r1 - 1 - max_strip, r0 - 1), -1):
        d = _row_decision(i)
        if d is False:
            break
        out[i, :, 3] = 0

    # Left
    for j in range(c0, min(c0 + max_strip, c1)):
        d = _col_decision(j)
        if d is False:
            break
        out[:, j, 3] = 0

    # Right
    for j in range(c1 - 1, max(c1 - 1 - max_strip, c0 - 1), -1):
        d = _col_decision(j)
        if d is False:
            break
        out[:, j, 3] = 0

    return out


def _erode_alpha(rgba: np.ndarray, radius: int = 2) -> np.ndarray:
    """Light erosion to smooth jagged edges after border strip."""
    from scipy.ndimage import binary_erosion
    alpha  = rgba[:, :, 3]
    mask   = alpha > 30
    eroded = binary_erosion(mask, iterations=radius)
    out    = rgba.copy()
    out[~eroded, 3] = 0
    return out


def clean_panel(rgba: np.ndarray) -> np.ndarray:
    rgba  = _flood_bg_alpha(rgba)
    alpha = rgba[:, :, 3]
    bgr   = rgba[:, :, :3][:, :, ::-1].copy()
    bgr2  = _inpaint_mask_artifacts(bgr, alpha)
    out   = rgba.copy()
    out[:, :, :3] = bgr2[:, :, ::-1]
    # _strip_panel_frame not needed: flood-fill now seeds from inside the frame
    # so background is fully removed. Only a light erosion to smooth crop-edge px.
    out   = _erode_alpha(out, radius=1)
    return out


# ---------------------------------------------------------------------------
# Step 3 – Fit panel onto target canvas
# ---------------------------------------------------------------------------

def fit_into(src: Image.Image, rw: int, rh: int, scale: float,
             top_align: bool = True,
             scale_w: float | None = None,
             y_offset: int = 0) -> Image.Image:
    src  = src.convert("RGBA")
    bbox = src.getbbox()
    if not bbox:
        return Image.new("RGBA", (rw, rh), (0, 0, 0, 0))
    src  = src.crop(bbox)
    sw, sh = src.size
    s_base  = min(rw / sw, rh / sh) * scale
    nw_base = max(1, int(sw * s_base))
    nh      = min(max(1, int(sh * s_base)), rh)
    if scale_w is not None and scale > 0:
        nw = min(max(1, int(nw_base * (scale_w / scale))), rw)
    else:
        nw = min(nw_base, rw)
    rs  = src.resize((nw, nh), Image.LANCZOS)
    out = Image.new("RGBA", (rw, rh), (0, 0, 0, 0))
    ox  = (rw - nw) // 2
    oy  = (2 if top_align else (rh - nh) // 2) + y_offset
    src_y0  = max(0, -oy)
    dst_y0  = max(0,  oy)
    paste_h = min(nh - src_y0, rh - dst_y0)
    if paste_h > 0:
        out.paste(rs.crop((0, src_y0, nw, src_y0 + paste_h)), (ox, dst_y0))
    return out


# ---------------------------------------------------------------------------
# Hand-drawn shadow overlay
# ---------------------------------------------------------------------------

def _add_body_shadow(img: Image.Image, vname: str) -> Image.Image:
    if vname not in ("front", "back"):
        return img
    if SHADOW_SHOULDER_STRENGTH <= 0 and SHADOW_WAIST_STRENGTH <= 0:
        return img

    arr     = np.array(img)
    alpha   = arr[:, :, 3]
    content = alpha > 30
    if not content.any():
        return img

    h, w     = arr.shape[:2]
    rows_any = content.any(axis=1)
    top_row  = int(np.argmax(rows_any))
    bot_row  = int(h - 1 - np.argmax(rows_any[::-1]))
    ch       = max(bot_row - top_row, 1)

    mark_len   = max(24, w // 22)
    mark_w     = max(4,  w // 120)
    sp_x       = max(20, w // 25)
    sp_y       = max(16, w // 30)
    angle_base = 50
    INK        = (35, 25, 15)

    rng = np.random.default_rng(42)

    shadow_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(shadow_layer)

    def _in_content(x: int, y: int) -> bool:
        xi, yi = int(np.clip(x, 0, w - 1)), int(np.clip(y, 0, h - 1))
        return bool(content[yi, xi])

    def _row_bounds(y: int) -> tuple[int, int]:
        row = content[int(np.clip(y, 0, h - 1))]
        if not row.any():
            return 0, 0
        return int(np.argmax(row)), int(w - 1 - np.argmax(row[::-1]))

    def _draw_zone(y0: int, y1: int, side_only: bool, strength: float) -> None:
        alpha_max = int(255 * strength)
        y = y0
        while y < y1:
            left, right = _row_bounds(y)
            if right <= left:
                y += sp_y
                continue
            gw = right - left
            x  = left + rng.integers(0, max(sp_x, 1))
            while x < right:
                cx        = (left + right) / 2.0
                in_centre = abs(x - cx) < gw * 0.20
                if side_only and in_centre:
                    x += sp_x // 2
                    continue
                if not _in_content(x, y):
                    x += sp_x // 2
                    continue
                length = mark_len + rng.integers(-mark_len // 4, mark_len // 4 + 1)
                angle  = angle_base + rng.integers(-12, 13)
                a_val  = int(alpha_max * rng.uniform(0.55, 1.0))
                rad    = math.radians(angle)
                x2     = int(x + length * math.cos(rad))
                y2     = int(y - length * math.sin(rad))
                draw.line([(x, y), (x2, y2)], fill=(*INK, a_val), width=mark_w)
                x += sp_x + rng.integers(-sp_x // 3, sp_x // 3 + 1)
            y += sp_y + rng.integers(-sp_y // 4, sp_y // 4 + 1)

    if SHADOW_SHOULDER_STRENGTH > 0:
        _draw_zone(top_row,
                   top_row + int(ch * 0.25),
                   side_only=True,
                   strength=SHADOW_SHOULDER_STRENGTH)

    if SHADOW_WAIST_STRENGTH > 0:
        _draw_zone(top_row + int(ch * 0.55),
                   top_row + int(ch * 0.75),
                   side_only=False,
                   strength=SHADOW_WAIST_STRENGTH)

    if SHADOW_BLUR_RADIUS > 0:
        br = SHADOW_BLUR_RADIUS * (w // 90)
        shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=br))

    s_arr = np.array(shadow_layer, dtype=np.float32)
    s_arr[:, :, 3] *= content.astype(np.float32)

    src = np.array(img, dtype=np.float32)
    sa  = s_arr[:, :, 3:4] / 255.0
    src[:, :, :3] = np.clip(src[:, :, :3] * (1.0 - sa * 0.7), 0, 255)
    return Image.fromarray(src.clip(0, 255).astype(np.uint8), "RGBA")


# ---------------------------------------------------------------------------
# Step 4 – Tilt rotation around top pivot
# ---------------------------------------------------------------------------

def make_tilt(img: Image.Image, deg: float, top_frac: float = TILT_TOP_FRAC) -> Image.Image:
    if deg == 0:
        return img.copy()
    W, H    = img.size
    pivot_y = int(H * top_frac)
    pad     = int(math.ceil(max(W, H) * abs(math.sin(math.radians(deg))) * 1.5)) + 4
    padded  = Image.new("RGBA", (W + 2*pad, H + 2*pad), (0, 0, 0, 0))
    padded.paste(img, (pad, pad), img)
    pW, pH = padded.size
    px, py = pad + W // 2, pad + pivot_y
    rad    = math.radians(-deg)
    c, s   = math.cos(rad), math.sin(rad)
    a, b, cc = c, s, px * (1 - c) - py * s
    d, e, f  = -s, c, py * (1 - c) + px * s
    rotated = padded.transform(padded.size, Image.AFFINE, (a, b, cc, d, e, f),
                               resample=Image.BICUBIC)
    bbox = rotated.getbbox()
    return rotated.crop(bbox) if bbox else rotated


# ---------------------------------------------------------------------------
# DST binary helpers
# ---------------------------------------------------------------------------

def sdbm_hash(s: str) -> int:
    h = 0
    for c in s.lower():
        h = (ord(c) + (h << 6) + (h << 16) - h) & 0xFFFFFFFF
    return h


def _parse_build_bin(data: bytes):
    off    = 0
    magic  = data[off:off+4]; off += 4
    ver    = struct.unpack_from("<I", data, off)[0]; off += 4
    if magic != b"BILD" or ver != 6:
        raise ValueError(f"Bad build.bin: {magic} v{ver}")
    sym_c  = struct.unpack_from("<I", data, off)[0]; off += 4
    _fc    = struct.unpack_from("<I", data, off)[0]; off += 4
    nl     = struct.unpack_from("<I", data, off)[0]; off += 4
    bname  = data[off:off+nl].decode(); off += nl
    ac     = struct.unpack_from("<I", data, off)[0]; off += 4
    anames = []
    for _ in range(ac):
        l = struct.unpack_from("<I", data, off)[0]; off += 4
        anames.append(data[off:off+l].decode()); off += l
    frames = []
    for _ in range(sym_c):
        sh = struct.unpack_from("<I", data, off)[0]; off += 4
        sf = struct.unpack_from("<I", data, off)[0]; off += 4
        for _ in range(sf):
            fn  = struct.unpack_from("<I", data, off)[0]; off += 4
            dur = struct.unpack_from("<I", data, off)[0]; off += 4
            x,y,w,h = struct.unpack_from("<4f", data, off); off += 16
            ai  = struct.unpack_from("<I", data, off)[0]; off += 4
            ac2 = struct.unpack_from("<I", data, off)[0]; off += 4
            frames.append({"sh": sh, "fn": fn, "x": x, "y": y,
                           "w": w, "h": h, "ai": ai, "ac": ac2})
    avc   = struct.unpack_from("<I", data, off)[0]; off += 4
    verts = []
    for _ in range(avc):
        vx,vy,vz = struct.unpack_from("<3f", data, off); off += 12
        vu,vv,vw = struct.unpack_from("<3f", data, off); off += 12
        verts.append((vx,vy,vz,vu,vv,vw))
    return bname, anames, frames, verts


def _check_height_vs_vest(atlas: "Image.Image",
                          frames: list, verts: list,
                          ATW: int, ATH: int) -> None:
    VEST_FRAME_NAMES = {0: "front+0", 3: "side+0", 6: "back+0"}
    SWAP_H = sdbm_hash("swap_body")
    vest_heights: dict[str, int] = {}

    if VEST_REF_ZIP.is_file():
        try:
            with zipfile.ZipFile(VEST_REF_ZIP) as vzf:
                vb, _, vframes, vverts = _parse_build_bin(vzf.read("build.bin"))
                vtex = TEMP / "_vest_ref.tex"
                vtex.write_bytes(vzf.read("atlas-0.tex"))
            vpng = TEMP / "_vest_ref.png"
            ok, _ = _run([STEX, "decompress", "-i", vtex, "-o", vpng])
            if ok:
                vest_img = Image.open(vpng).convert("RGBA")
                varr = np.array(vest_img)
                VW, VH = vest_img.size
                for vfrm in vframes:
                    if vfrm["sh"] != SWAP_H or vfrm["ac"] == 0:
                        continue
                    fn = vfrm["fn"]
                    if fn not in VEST_FRAME_NAMES:
                        continue
                    fv  = vverts[vfrm["ai"]: vfrm["ai"] + vfrm["ac"]]
                    us  = [v[3] for v in fv]; vs2 = [v[4] for v in fv]
                    xl  = int(round(min(us)*VW)); xr = int(round(max(us)*VW))
                    yt  = int(round((1-max(vs2))*VH)); yb = int(round((1-min(vs2))*VH))
                    crop = varr[yt:yb, xl:xr]
                    ys   = np.where(crop[:,:,3] > 10)[0]
                    ch   = int(ys.max() - ys.min() + 1) if len(ys) else 0
                    vest_heights[VEST_FRAME_NAMES[fn]] = ch
        except Exception as e:
            print(f"    [height-check] Could not load sweatervest ref: {e}")

    arr = np.array(atlas)
    FRAME_VIEW_MAP = {0: "front+0", 3: "side+0", 6: "back+0"}
    print("\n[6b] Height consistency check vs armor_sweatervest:")
    print(f"    {'view':<10} {'slot_h':>6} {'reisen_h':>8} {'vest_h':>6} {'delta':>6} {'match?'}")
    for frm in frames:
        if frm["sh"] != SWAP_H or frm["ac"] == 0 or frm["fn"] not in FRAME_VIEW_MAP:
            continue
        fn   = frm["fn"]
        name = FRAME_VIEW_MAP[fn]
        fv   = verts[frm["ai"]: frm["ai"] + frm["ac"]]
        us   = [v[3] for v in fv]; vs2 = [v[4] for v in fv]
        xl   = int(round(min(us)*ATW)); xr = int(round(max(us)*ATW))
        yt   = int(round((1-max(vs2))*ATH)); yb = int(round((1-min(vs2))*ATH))
        rh   = max(1, yb - yt)
        crop = arr[yt:yb, xl:xr]
        ys   = np.where(crop[:,:,3] > 10)[0]
        ch   = int(ys.max() - ys.min() + 1) if len(ys) else 0
        vest_h  = vest_heights.get(name, -1)
        delta   = ch - vest_h if vest_h >= 0 else 0
        sym     = "OK" if abs(delta) <= 8 else (f"+{delta}px TOO LONG" if delta > 0 else f"{delta}px short")
        vest_str = str(vest_h) if vest_h >= 0 else "n/a"
        print(f"    {name:<10} {rh:>6}px {ch:>6}px   {vest_str:>5}   {delta:>+5}    {sym}")


def _patch_build_name(data: bytes, new_name: str) -> bytes:
    off     = 4 + 4 + 4 + 4
    old_len = struct.unpack_from("<I", data, off)[0]
    end     = off + 4 + old_len
    nb      = new_name.encode()
    return data[:off] + struct.pack("<I", len(nb)) + nb + data[end:]


def _patch_anim_bank(data: bytes, new_bank: str) -> bytes:
    data     = bytearray(data)
    new_hash = sdbm_hash(new_bank)
    off      = 8 + 4 + 4 + 4
    num      = struct.unpack_from("<I", data, off)[0]; off += 4
    for _ in range(num):
        nl = struct.unpack_from("<I", data, off)[0]; off += 4 + nl
        off += 1
        struct.pack_into("<I", data, off, new_hash); off += 4 + 4
        afc = struct.unpack_from("<I", data, off)[0]; off += 4
        for _ in range(afc):
            off += 16
            fe   = struct.unpack_from("<I", data, off)[0]; off += 4
            fele = struct.unpack_from("<I", data, off)[0]; off += 4
            off += fe * 4 + fele * 40
    return bytes(data)


def _run(cmd: list) -> tuple[bool, str]:
    r = subprocess.run([str(c) for c in cmd], capture_output=True, text=True)
    return r.returncode == 0, r.stdout + r.stderr


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def _pack_atlas_and_zip(base_views: dict[str, Image.Image]) -> None:
    print("\n[3] Generating ±8° tilt variants …")
    variants: dict[tuple[str, int], Image.Image] = {}
    for view, base in base_views.items():
        shadowed = _add_body_shadow(base, view)
        for deg in TILT_ANGLES:
            tilted = make_tilt(shadowed, deg)
            variants[(view, deg)] = tilted
            print(f"    {view} {deg:+d}°  {tilted.size}")

    print(f"\n[4] Parsing template {TEMPLATE_ZIP} …")
    tmpl = VANILLA / TEMPLATE_ZIP
    if not tmpl.is_file():
        print(f"    ERROR: {tmpl} not found"); sys.exit(1)
    with zipfile.ZipFile(tmpl) as z:
        build_data = z.read("build.bin")
        anim_data  = z.read("anim.bin")
        tex_data   = z.read("atlas-0.tex")
    bname, anames, frames, verts = _parse_build_bin(build_data)
    print(f"    build={bname}  frames={len(frames)}  atlas={anames}")

    print("\n[5] Decompressing reference atlas …")
    tmp_tex = TEMP / "_ref_nightmail_build.tex"
    tmp_png = TEMP / "_ref_nightmail_build.png"
    tmp_tex.write_bytes(tex_data)
    ok, msg = _run([STEX, "decompress", "-i", tmp_tex, "-o", tmp_png])
    if not ok:
        print(f"    STEX failed: {msg}"); sys.exit(1)
    ref_img = Image.open(tmp_png).convert("RGBA")
    ATW, ATH = ref_img.size
    print(f"    Atlas size: {ATW}x{ATH}")

    print("\n[6] Compositing frames …")
    atlas      = Image.new("RGBA", (ATW, ATH), (0, 0, 0, 0))
    SWAP_HASH  = sdbm_hash("swap_body")

    for frm in frames:
        if frm["sh"] != SWAP_HASH or frm["ac"] == 0:
            continue
        fn     = frm["fn"]
        fverts = verts[frm["ai"]: frm["ai"] + frm["ac"]]
        us     = [v[3] for v in fverts]
        vs2    = [v[4] for v in fverts]
        xl = int(round(min(us) * ATW)); xr = int(round(max(us) * ATW))
        yt = int(round((1 - max(vs2)) * ATH)); yb = int(round((1 - min(vs2)) * ATH))
        rw, rh = max(1, xr - xl), max(1, yb - yt)

        if fn == 13:
            if GROUND_SRC.is_file():
                ground_src = Image.open(GROUND_SRC).convert("RGBA")
            else:
                print(f"    [ground] WARNING: {GROUND_SRC} not found, falling back to front canvas")
                ground_src = variants[("front", 0)]
            sprite = fit_into(ground_src, rw, rh, SCALE_H["ground"],
                              top_align=False, scale_w=SCALE_W.get("ground"))
            g_arr = np.array(sprite)
            g_arr[g_arr[:, :, 3] > 50, 3] = 255
            sprite = Image.fromarray(g_arr, "RGBA")
            tag    = "ground"
        elif fn in FRAME_MAP:
            vname, deg = FRAME_MAP[fn]
            if vname == "back" and (BACK_VERTICAL_SHIFT_PX > 0 or BACK_NECK_ARC_RADIUS > 0):
                shift = max(0, min(BACK_VERTICAL_SHIFT_PX, rh // 2))
                full  = fit_into(variants[(vname, deg)], rw, rh, SCALE_H[vname],
                                 top_align=True, scale_w=SCALE_W.get(vname))
                sprite = Image.new("RGBA", (rw, rh), (0, 0, 0, 0))
                sprite.paste(full.crop((0, shift, rw, rh)), (0, shift))
                if BACK_NECK_ARC_RADIUS > 0:
                    arr = np.array(sprite)
                    R   = float(BACK_NECK_ARC_RADIUS)
                    cx  = rw / 2.0
                    xs  = np.arange(rw, dtype=float)
                    dx  = np.abs(xs - cx)
                    arc_extra = np.where(dx <= R,
                                         R - np.sqrt(np.maximum(R * R - dx * dx, 0.0)),
                                         R)
                    depths = np.minimum((shift + arc_extra).astype(int), rh // 2)
                    ys     = np.arange(rh)[:, np.newaxis]
                    mask   = ys < depths[np.newaxis, :]
                    arr[mask] = 0
                    sprite = Image.fromarray(arr, "RGBA")
            else:
                sprite = fit_into(variants[(vname, deg)], rw, rh, SCALE_H[vname],
                                  top_align=True, scale_w=SCALE_W.get(vname))

            if vname in ("front", "back") and SHOULDER_ERASE_SIDE_PX > 0:
                arr = np.array(sprite, dtype=np.float32)
                ew  = min(SHOULDER_ERASE_SIDE_PX, rw // 3)
                eh  = min(SHOULDER_ERASE_HEIGHT_PX, rh // 3)
                fw  = min(SHOULDER_FEATHER_PX, ew, eh)
                x_mul = np.ones(rw, dtype=np.float32)
                for px in range(ew):
                    fade = min(1.0, max(0.0, (px - (ew - fw)) / max(1, fw)))
                    x_mul[px] = fade
                    x_mul[rw - 1 - px] = fade
                y_mul = np.ones(rh, dtype=np.float32)
                for py in range(eh):
                    ramp_start = max(0, eh - fw)
                    if py < ramp_start:
                        y_mul[py] = 0.0
                    else:
                        y_mul[py] = (py - ramp_start) / max(1, fw)
                combined = y_mul[:, None] * x_mul[None, :]
                arr[:, :, 3] *= combined
                sprite = Image.fromarray(arr.astype(np.uint8), "RGBA")
            elif vname == "side" and SIDE_ARM_ERASE_FRAC > 0:
                arr     = np.array(sprite)
                erase_w = max(1, int(rw * SIDE_ARM_ERASE_FRAC))
                erase_h = max(1, int(rh * 0.55))
                arr[:erase_h, :erase_w, 3] = 0
                sprite  = Image.fromarray(arr, "RGBA")
            tag = f"{vname} {deg:+d}°"
        else:
            continue

        atlas.paste(sprite, (xl, yt), sprite)
        print(f"    frame{fn:2d} [{tag:<14s}]: ({xl},{yt})-({xr},{yb}) {rw}x{rh}")

    _check_height_vs_vest(atlas, frames, verts, ATW, ATH)

    atlas_png = TEMP / "reisen_uniform_atlas.png"
    atlas.save(atlas_png)
    print(f"\n[7] Atlas PNG: {atlas_png}")

    print("[8] Compressing to TEX …")
    atlas_tex = TEMP / "reisen_uniform_atlas.tex"
    ok, msg   = _run([KTECH, "--no-mipmaps", "-c", "dxt5", atlas_png, atlas_tex])
    if not ok:
        print(f"    ktech failed: {msg}"); sys.exit(1)
    print(f"    TEX: {atlas_tex.stat().st_size} bytes")

    print("[9] Patching build/anim names …")
    patched_build = _patch_build_name(build_data, MOD_BUILD_NAME)
    patched_anim  = _patch_anim_bank(anim_data, MOD_BANK_NAME)
    v, _, _, _    = _parse_build_bin(patched_build)
    print(f"    build='{v}'  bank_hash=0x{sdbm_hash(MOD_BANK_NAME):08x}")

    mod_zip = ANIM / "reisen_uniform.zip"
    backup  = TEMP / "reisen_uniform_pre_triptych.zip"
    if mod_zip.exists():
        shutil.copy2(mod_zip, backup)
        print(f"    Backed up old zip → {backup.name}")
    with zipfile.ZipFile(mod_zip, "w", zipfile.ZIP_STORED) as zout:
        zout.writestr("anim.bin",    patched_anim)
        zout.writestr("build.bin",   patched_build)
        zout.writestr("atlas-0.tex", atlas_tex.read_bytes())
    print(f"    Written: {mod_zip}  ({mod_zip.stat().st_size} bytes)")

    chk, _, _, _ = _parse_build_bin(zipfile.ZipFile(mod_zip).read("build.bin"))
    ok_str = "OK" if chk == MOD_BUILD_NAME else f"FAIL (got '{chk}')"
    print(f"\nVerification: build='{chk}' → {ok_str}")
    print("\nDone!")


def main_triptych(triptych_path: Path) -> None:
    print("=" * 62)
    print("  reisen_uniform 10-frame build (triptych)")
    print("=" * 62)

    print(f"\n[1] Loading triptych: {triptych_path.name}")
    rgba = np.array(Image.open(triptych_path).convert("RGBA"), dtype=np.uint8)
    print(f"    {rgba.shape[1]}x{rgba.shape[0]} px")
    boxes = _split_panels(rgba)
    print(
        "    Panels: "
        + "  ".join(f"{v}=[{b[0]},{b[1]})-({b[2]},{b[3]})" for v, b in zip(ORDER, boxes))
    )

    # Crop just inside the panel border so flood-fill corners land on the inner
    # background (cream inside the frame) rather than the outer cream that the
    # frame blocks. Net inset from detected bbox = FRAME_INSET - FLOOD_PAD.
    # Keep this small (≈2 px) so hem/sides aren't clipped.
    FRAME_INSET = 5   # px: slightly past the ~3-4 px frame line
    FLOOD_PAD   = 3   # px: context margin added inside the inset (< FRAME_INSET)

    print("\n[2] Removing background + mask artifacts …")
    base_views: dict[str, Image.Image] = {}
    for view, bb in zip(ORDER, boxes):
        x0, y0, x1, y1 = bb
        # Crop just inside the panel frame so flood-fill can reach inner background
        ix0 = max(0,              x0 + FRAME_INSET - FLOOD_PAD)
        iy0 = max(0,              y0 + FRAME_INSET - FLOOD_PAD)
        ix1 = min(rgba.shape[1],  x1 - FRAME_INSET + FLOOD_PAD)
        iy1 = min(rgba.shape[0],  y1 - FRAME_INSET + FLOOD_PAD)
        patch = rgba[iy0:iy1, ix0:ix1].copy()
        patch = clean_panel(patch)
        pil = Image.fromarray(patch, "RGBA")
        if view in FLIP_H:
            pil = pil.transpose(Image.FLIP_LEFT_RIGHT)
        tw, th = CANVAS[view]
        pil = fit_into(pil, tw, th, SCALE[view], top_align=True)
        base_views[view] = pil
        print(f"    {view}: panel {ix1-ix0}x{iy1-iy0} -> canvas {tw}x{th}")

    _pack_atlas_and_zip(base_views)


def main_three_pngs(front: Path, side: Path, back: Path) -> None:
    print("=" * 62)
    print("  reisen_uniform 10-frame build (3 separate PNGs)")
    print("=" * 62)

    paths = {"front": front, "side": side, "back": back}
    print("\n[1] Loading three views …")
    for v, p in paths.items():
        if not p.is_file():
            print(f"    ERROR missing {v}: {p}", file=sys.stderr)
            sys.exit(1)
        print(f"    {v}: {p.name}")

    print("\n[2] Removing background + mask artifacts …")
    base_views: dict[str, Image.Image] = {}
    for view, path in paths.items():
        rgba = np.array(Image.open(path).convert("RGBA"), dtype=np.uint8)
        patch = clean_panel(rgba)
        pil = Image.fromarray(patch, "RGBA")
        if view in FLIP_H:
            pil = pil.transpose(Image.FLIP_LEFT_RIGHT)
        tw, th = CANVAS[view]
        w0, h0 = pil.size
        pil = fit_into(pil, tw, th, SCALE[view], top_align=True)
        base_views[view] = pil
        print(f"    {view}: source {w0}x{h0} -> canvas {tw}x{th}")

    _pack_atlas_and_zip(base_views)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Build reisen_uniform.zip from a triptych or three view PNGs.",
    )
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help="No args: default triptych. One path: triptych. Three paths: front, side, back.",
    )
    parser.add_argument(
        "--default-views",
        action="store_true",
        help=f"Use preset separate views: {DEFAULT_SEPARATE_VIEWS[0].name} etc.",
    )
    args = parser.parse_args()

    if args.default_views:
        main_three_pngs(*DEFAULT_SEPARATE_VIEWS)
    elif len(args.paths) == 0:
        if not DEFAULT_TRIPTYCH.is_file():
            print(f"ERROR: default triptych not found: {DEFAULT_TRIPTYCH}", file=sys.stderr)
            sys.exit(1)
        main_triptych(DEFAULT_TRIPTYCH)
    elif len(args.paths) == 1:
        p = args.paths[0]
        if not p.is_file():
            print(f"ERROR: not found: {p}", file=sys.stderr)
            sys.exit(1)
        main_triptych(p)
    elif len(args.paths) == 3:
        main_three_pngs(args.paths[0], args.paths[1], args.paths[2])
    else:
        parser.error("Give 0, 1 (triptych), or 3 (front side back) path arguments.")
