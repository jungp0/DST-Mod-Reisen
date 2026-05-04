"""
Split tools/src/reisen_sleeveless_vest_three_views_ai_v9.png into
front / side / back, reduce obvious mask/template artifacts, then export
grassarmor_vest_raw_{front,side,back}.png at the same canvas sizes
for tools/build_sanity_style_atlas.py.

Run from mod root:
  python tools/prepare_sleeveless_triptych_for_casual_atlas.py
"""

from __future__ import annotations

import os
import sys
from collections import deque
from pathlib import Path

import cv2
import numpy as np
from PIL import Image
from scipy.ndimage import binary_closing, binary_opening, label

MOD_DIR = Path(__file__).resolve().parents[1]
DEFAULT_TRIPTYCH = MOD_DIR / "tools" / "src" / "reisen_sleeveless_vest_three_views_ai_v9.png"
OUT_DIR = MOD_DIR / "tools" / "src" / "grassarmor_vest_sources"

# Must match build_sanity_style_atlas.py + adj_* masks used by render_vest_hq.
CANVAS = {
    "front": (720, 1040),
    "side": (688, 1048),
    "back": (728, 992),
}

ORDER = ("front", "side", "back")
FIT_SCALE = 0.98  # match build_sanity_style_atlas SCALE values roughly


def load_rgba(path: Path) -> np.ndarray:
    return np.array(Image.open(path).convert("RGBA"), dtype=np.uint8)


def split_three_panels(rgba: np.ndarray) -> list[tuple[int, int, int, int]]:
    """Return three tight bboxes (x0,y0,x1,y1) left-to-right for main blobs."""
    h, w, _ = rgba.shape
    rgb = rgba[:, :, :3].astype(np.int16)
    corner = rgb[0 : min(40, h), 0 : min(40, w)].reshape(-1, 3).mean(axis=0)
    d = np.abs(rgb - corner[None, None, :]).sum(axis=2)
    fg = d > 52
    lab, n = label(fg)
    boxes: list[tuple[int, int, int, int, int]] = []
    for k in range(1, n + 1):
        ys, xs = np.where(lab == k)
        if len(xs) < 8000:
            continue
        x0, x1 = int(xs.min()), int(xs.max()) + 1
        y0, y1 = int(ys.min()), int(ys.max()) + 1
        area = int((lab[y0:y1, x0:x1] == k).sum())
        boxes.append((area, x0, y0, x1, y1))
    boxes.sort(reverse=True)
    if len(boxes) < 3:
        raise RuntimeError(
            f"Expected 3 large foreground components, found {len(boxes)}. "
            "Try lowering fg threshold or use a cleaner triptych export."
        )
    top3 = sorted(boxes[:3], key=lambda t: t[1])  # by x0
    return [(b[1], b[2], b[3], b[4]) for b in top3]


def rgba_to_bgr(rgba: np.ndarray) -> np.ndarray:
    bgr = rgba[:, :, :3][:, :, ::-1].copy()
    return bgr


def denoise_mask_artifacts(bgr: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """
    Remove typical gray template / houndstooth residue inside the sprite.
    Inpaint only where chroma is very low and local contrast suggests pattern.
    """
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB)
    L = lab[:, :, 0].astype(np.float32)
    a = lab[:, :, 1].astype(np.float32)
    b = lab[:, :, 2].astype(np.float32)
    chroma = np.sqrt((a - 128.0) ** 2 + (b - 128.0) ** 2)

    blur = cv2.GaussianBlur(L, (0, 0), sigmaX=1.6)
    local_std = cv2.blur((L - blur) ** 2, (11, 11))
    local_std = np.sqrt(local_std)

    gray_band = (L > 155.0) & (L < 238.0)
    low_chroma = chroma < 20.0
    patterned = local_std > 3.2
    flat_template = (local_std < 2.2) & low_chroma & (L > 175.0) & (L < 225.0)

    m = (alpha > 30) & gray_band & (patterned | flat_template)
    m = binary_closing(m, iterations=2)
    m = binary_opening(m, iterations=1)
    mask = (m.astype(np.uint8) * 255)
    if int(mask.sum()) == 0:
        return bgr
    return cv2.inpaint(bgr, mask, inpaintRadius=4, flags=cv2.INPAINT_TELEA)


def estimate_alpha_from_bg(rgba: np.ndarray, pad: int = 28) -> np.ndarray:
    """Opaque crop -> RGBA with transparent sheet background (border flood)."""
    h, w, _ = rgba.shape
    big = np.ones((h + 2 * pad, w + 2 * pad, 4), dtype=np.uint8) * 255
    big[:, :, 3] = 255
    big[pad : pad + h, pad : pad + w] = rgba
    rgb = big[:, :, :3].astype(np.int16)
    bh, bw = big.shape[:2]

    ref = (
        rgb[0:8, 0:8].reshape(-1, 3).mean(axis=0)
        + rgb[0:8, -8:].reshape(-1, 3).mean(axis=0)
        + rgb[-8:, 0:8].reshape(-1, 3).mean(axis=0)
        + rgb[-8:, -8:].reshape(-1, 3).mean(axis=0)
    ) / 4.0
    tol = 52

    def dist(y: int, x: int) -> float:
        return float(np.abs(rgb[y, x] - ref).sum())

    vis = np.zeros((bh, bw), dtype=bool)
    sheet = np.zeros((bh, bw), dtype=bool)
    q: deque[tuple[int, int]] = deque()

    def try_push(y: int, x: int) -> None:
        if y < 0 or y >= bh or x < 0 or x >= bw or vis[y, x]:
            return
        vis[y, x] = True
        if dist(y, x) <= tol:
            sheet[y, x] = True
            q.append((y, x))

    for x in range(bw):
        try_push(0, x)
        try_push(bh - 1, x)
    for y in range(bh):
        try_push(y, 0)
        try_push(y, bw - 1)
    while q:
        y, x = q.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < bh and 0 <= nx < bw and not vis[ny, nx]:
                vis[ny, nx] = True
                if dist(ny, nx) <= tol:
                    sheet[ny, nx] = True
                    q.append((ny, nx))

    out = big.copy()
    out[sheet, 3] = 0
    out = out[pad : pad + h, pad : pad + w]
    return out


def paste_fit_canvas(rgba: np.ndarray, tw: int, th: int, scale: float) -> Image.Image:
    """Uniform scale to fit inside tw x th, top-centered like atlas build."""
    bbox = Image.fromarray(rgba, "RGBA").getbbox()
    if not bbox:
        return Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    x0, y0, x1, y1 = bbox
    crop = rgba[y0:y1, x0:x1]
    ch, cw = crop.shape[:2]
    s = min(tw / cw, th / ch) * scale
    nw, nh = max(1, int(round(cw * s))), max(1, int(round(ch * s)))
    pil = Image.fromarray(crop, "RGBA").resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    ox = (tw - nw) // 2
    oy = 2  # TOP_ALIGN in build_sanity_style_atlas
    canvas.paste(pil, (ox, oy), pil)
    return canvas


def process_triptych(src: Path) -> None:
    rgba = load_rgba(src)
    boxes = split_three_panels(rgba)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    for view, bb in zip(ORDER, boxes):
        x0, y0, x1, y1 = bb
        pad = 4
        x0 = max(0, x0 - pad)
        y0 = max(0, y0 - pad)
        x1 = min(rgba.shape[1], x1 + pad)
        y1 = min(rgba.shape[0], y1 + pad)
        patch = rgba[y0:y1, x0:x1].copy()

        patch = estimate_alpha_from_bg(patch)
        a = patch[:, :, 3]
        bgr = rgba_to_bgr(patch)
        bgr2 = denoise_mask_artifacts(bgr, a)
        patch[:, :, :3] = bgr2[:, :, ::-1]

        tw, th = CANVAS[view]
        out_pil = paste_fit_canvas(patch, tw, th, FIT_SCALE)
        out_path = OUT_DIR / f"grassarmor_vest_raw_{view}.png"
        out_pil.save(out_path)
        print(f"  {view}: crop {x1-x0}x{y1-y0} -> canvas {tw}x{th} -> {out_path}")


def main() -> None:
    src = Path(os.environ.get("REISEN_TRIPTYCH", DEFAULT_TRIPTYCH))
    if not src.is_file():
        print(f"Missing triptych: {src}", file=sys.stderr)
        sys.exit(1)
    print(f"Reading {src} ({src.stat().st_size} bytes)")
    process_triptych(src)
    print("Done. Next: python tools/build_sanity_style_atlas.py (if ktools/STEX paths are valid on this machine)")


if __name__ == "__main__":
    main()
