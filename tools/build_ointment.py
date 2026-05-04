"""
Build reisen_ointment item art: inventory icon (PNG/TEX/XML) + ground-drop anim zip.

Uses vanilla bandage.zip as structural template (same 256x256 atlas layout, same
build.bin / anim.bin structure). Only patches the build name and anim bank hash.
Sprite is cropped from reisen_ointment_src.png and composited into the same pixel
region the bandage occupies (x=[4,192], y=[4,153] in a 256x256 atlas).

Requires: Pillow, ktech.exe (KTECH env var or default path).

Usage:
    python tools/build_ointment.py [path/to/override_src.png]
"""
from __future__ import annotations

import os
import struct
import subprocess
import sys
import zipfile

from PIL import Image, ImageDraw

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
MOD_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
TOOLS_SRC = os.path.join(MOD_DIR, "tools", "src")
TEMP = os.path.join(MOD_DIR, "temp")
INV_DIR = os.path.join(MOD_DIR, "images", "inventoryimages")
ANIM_DIR = os.path.join(MOD_DIR, "anim")
VANILLA_ANIM = os.path.normpath(
    os.path.join(os.path.dirname(MOD_DIR), "..", "data", "anim")
)
KTECH = os.environ.get("KTECH") or r"E:\Workspace\ktools\build\Release\ktech.exe"

SRC_DEFAULT = os.path.join(TOOLS_SRC, "reisen_ointment_src.png")

# ---------------------------------------------------------------------------
# Item identity
# ---------------------------------------------------------------------------
ITEM_NAME = "reisen_ointment"
BUILD_NAME = "reisen_ointment"
BANK_NAME = "reisenointment"
VANILLA_REF = "bandage"

# ---------------------------------------------------------------------------
# Atlas geometry (256x256, same region bandage uses)
# ---------------------------------------------------------------------------
ATLAS_W, ATLAS_H = 256, 256
# Pixel bounding box of the sprite in the atlas (with 4px border padding).
SPRITE_BOX = (4, 4, 192, 153)  # (x0, y0, x1, y1)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def sdbm_hash(s: str) -> int:
    h = 0
    for c in s.lower():
        h = (ord(c) + (h << 6) + (h << 16) - h) & 0xFFFFFFFF
    return h


def ktech_compress(png_path: str, tex_path: str, *, mipmaps: bool = True) -> tuple[bool, str]:
    if not os.path.isfile(KTECH):
        return False, f"ktech not found: {KTECH}"
    args = [KTECH, "-c", "dxt5", png_path, tex_path]
    if not mipmaps:
        args.insert(1, "--no-mipmaps")
    r = subprocess.run(args, capture_output=True, text=True)
    return r.returncode == 0, r.stdout + r.stderr


def _sample_background_color(img: Image.Image, sample_radius: int = 4) -> tuple[int, int, int]:
    """Sample the average corner color as background estimate."""
    w, h = img.size
    samples: list[tuple[int, int, int]] = []
    for x in range(sample_radius):
        for y in range(sample_radius):
            px = img.getpixel((x, y))
            samples.append(px[:3])
            px = img.getpixel((w - 1 - x, y))
            samples.append(px[:3])
            px = img.getpixel((x, h - 1 - y))
            samples.append(px[:3])
            px = img.getpixel((w - 1 - x, h - 1 - y))
            samples.append(px[:3])
    r = sum(s[0] for s in samples) // len(samples)
    g = sum(s[1] for s in samples) // len(samples)
    b = sum(s[2] for s in samples) // len(samples)
    return (r, g, b)


def _remove_background_flood(img: Image.Image, threshold: int = 45) -> Image.Image:
    """
    Remove exterior background by flood-filling from all 4 image borders.

    Only pixels reachable from the border whose color is close to the
    detected corner background are made transparent.  Interior dark details
    (vines, petal patterns, shadows) enclosed by the item's black outline
    are preserved even when their color is numerically similar to the BG,
    because the thick black outlines act as a flood-fill barrier.

    This replaces the old global color-distance approach which incorrectly
    made interior decorative details semi-transparent.
    """
    from collections import deque

    img = img.convert("RGBA")
    w, h = img.size
    bg_r, bg_g, bg_b = _sample_background_color(img)
    print(f"  Detected background color: ({bg_r},{bg_g},{bg_b})")

    t2 = threshold * threshold  # compare squared distances — avoids sqrt

    # Flat pixel list for O(1) indexed access (Pillow ≥13 exposes get_flattened_data).
    _get_flat = getattr(img, "get_flattened_data", None) or img.getdata
    pixels: list[tuple[int, int, int, int]] = list(_get_flat())  # type: ignore[assignment]

    # Pre-compute per-pixel background membership (bytearray = fast + low memory).
    bg_like = bytearray(
        1 if (p[0] - bg_r) ** 2 + (p[1] - bg_g) ** 2 + (p[2] - bg_b) ** 2 < t2 else 0
        for p in pixels
    )

    # BFS: visited[i]=1 means pixel i belongs to the outer background.
    visited: bytearray = bytearray(w * h)
    queue: deque[int] = deque()

    def _seed(idx: int) -> None:
        if bg_like[idx] and not visited[idx]:
            visited[idx] = 1
            queue.append(idx)

    for x in range(w):
        _seed(x)                    # top row
        _seed((h - 1) * w + x)     # bottom row
    for y in range(1, h - 1):
        _seed(y * w)                # left column
        _seed(y * w + w - 1)       # right column

    while queue:
        idx = queue.popleft()
        y_pos = idx // w
        x_pos = idx % w
        if y_pos > 0:
            ni = idx - w
            if bg_like[ni] and not visited[ni]:
                visited[ni] = 1
                queue.append(ni)
        if y_pos < h - 1:
            ni = idx + w
            if bg_like[ni] and not visited[ni]:
                visited[ni] = 1
                queue.append(ni)
        if x_pos > 0:
            ni = idx - 1
            if bg_like[ni] and not visited[ni]:
                visited[ni] = 1
                queue.append(ni)
        if x_pos < w - 1:
            ni = idx + 1
            if bg_like[ni] and not visited[ni]:
                visited[ni] = 1
                queue.append(ni)

    # Rebuild image: outer background pixels → alpha 0, everything else unchanged.
    new_pixels = [
        (r, g, b, 0) if visited[i] else (r, g, b, a)
        for i, (r, g, b, a) in enumerate(pixels)
    ]
    result = Image.new("RGBA", (w, h))
    result.putdata(new_pixels)  # type: ignore[arg-type]
    return result


def prepare_item_rgba(src_path: str) -> Image.Image:
    """Load source, remove exterior background via flood fill, return tightly cropped RGBA."""
    img = Image.open(src_path).convert("RGBA")
    img = _remove_background_flood(img, threshold=45)
    bb = img.getbbox()
    if bb:
        img = img.crop(bb)
    return img


# ---------------------------------------------------------------------------
# Atlas composition
# ---------------------------------------------------------------------------

def _fit_into_box(
    item: Image.Image,
    box: tuple[int, int, int, int],
    *,
    ground_shadow: bool = False,
    canvas: Image.Image,
) -> None:
    x0, y0, x1, y1 = box
    bw, bh = x1 - x0, y1 - y0
    iw, ih = item.size
    if iw <= 0 or ih <= 0 or bw <= 0 or bh <= 0:
        return
    margin = 4
    scale = min((bw - margin * 2) / iw, (bh - margin * 2) / ih)
    nw = max(1, int(iw * scale))
    nh = max(1, int(ih * scale))
    resized = item.resize((nw, nh), Image.LANCZOS)
    px = x0 + (bw - nw) // 2
    py = y0 + (bh - nh) // 2
    if ground_shadow:
        dr = ImageDraw.Draw(canvas)
        pad = max(4, nw // 6)
        sy0 = min(y1 - 4, py + nh - 2)
        sy1 = min(y1, sy0 + 8)
        sx0 = px + pad
        sx1 = px + nw - pad
        if sx1 > sx0 and sy1 > sy0:
            dr.ellipse([sx0, sy0, sx1, sy1], fill=(20, 20, 20, 120))
    canvas.paste(resized, (px, py), resized)


def compose_item_atlas(item: Image.Image) -> Image.Image:
    """Place item sprite into the bandage-compatible atlas region."""
    atlas = Image.new("RGBA", (ATLAS_W, ATLAS_H), (0, 0, 0, 0))
    _fit_into_box(item, SPRITE_BOX, ground_shadow=True, canvas=atlas)
    return atlas


# ---------------------------------------------------------------------------
# Binary patching (mirrors rebuild_charm_garland.py approach)
# ---------------------------------------------------------------------------

def patch_build_name(data: bytes, new_name: str) -> bytes:
    offset = 16  # skip magic(4) + version(4) + sym_count(4) + frame_count(4)
    old_name_len = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    new_name_bytes = new_name.encode("utf-8")
    result = bytearray()
    result.extend(data[:16])
    result.extend(struct.pack("<I", len(new_name_bytes)))
    result.extend(new_name_bytes)
    result.extend(data[16 + 4 + old_name_len:])
    return bytes(result)


def patch_anim_bank_hash(data: bytes, new_bank_name: str) -> bytes:
    data = bytearray(data)
    new_hash = sdbm_hash(new_bank_name)
    offset = 8
    _num_elems = struct.unpack_from("<I", data, offset)[0]; offset += 4
    _num_frames = struct.unpack_from("<I", data, offset)[0]; offset += 4
    _num_events = struct.unpack_from("<I", data, offset)[0]; offset += 4
    num_anims = struct.unpack_from("<I", data, offset)[0]; offset += 4
    for _ in range(num_anims):
        name_len = struct.unpack_from("<I", data, offset)[0]; offset += 4
        offset += name_len  # skip anim name string
        offset += 1         # facing byte
        struct.pack_into("<I", data, offset, new_hash); offset += 4
        offset += 4         # frame_rate
        anim_frame_count = struct.unpack_from("<I", data, offset)[0]; offset += 4
        for _ in range(anim_frame_count):
            offset += 16    # bbox (4 floats)
            f_events = struct.unpack_from("<I", data, offset)[0]; offset += 4
            f_elems = struct.unpack_from("<I", data, offset)[0]; offset += 4
            offset += f_events * 4
            offset += f_elems * 40
    return bytes(data)


# ---------------------------------------------------------------------------
# Output builders
# ---------------------------------------------------------------------------

def build_inventory_icon(item: Image.Image) -> None:
    """Create 64x64 inventory PNG, TEX and XML."""
    iw, ih = item.size
    dim = max(iw, ih, 1)
    square = Image.new("RGBA", (dim, dim), (0, 0, 0, 0))
    square.paste(item, ((dim - iw) // 2, (dim - ih) // 2), item)
    icon = square.resize((64, 64), Image.LANCZOS)

    png_path = os.path.join(INV_DIR, f"{ITEM_NAME}.png")
    tex_path = os.path.join(INV_DIR, f"{ITEM_NAME}.tex")
    xml_path = os.path.join(INV_DIR, f"{ITEM_NAME}.xml")

    icon.save(png_path)
    print(f"  Inventory PNG: {png_path}")

    ok, msg = ktech_compress(png_path, tex_path, mipmaps=False)
    if not ok:
        print(f"  WARNING: ktech failed for inventory TEX: {msg}")
    else:
        print(f"  Inventory TEX: {tex_path}")

    xml_content = (
        f'<Atlas>'
        f'<Texture filename="{ITEM_NAME}.tex" />'
        f'<Elements>'
        f'<Element name="{ITEM_NAME}.tex" u1="0.0078125" u2="0.9921875" v1="0.0078125" v2="0.9921875" />'
        f'</Elements>'
        f'</Atlas>'
    )
    with open(xml_path, "w", encoding="utf-8") as f:
        f.write(xml_content)
    print(f"  Inventory XML: {xml_path}")


def build_anim_zip(atlas_img: Image.Image) -> None:
    """Create reisen_ointment.zip using bandage as structural template."""
    vanilla_zip = os.path.join(VANILLA_ANIM, f"{VANILLA_REF}.zip")
    if not os.path.isfile(vanilla_zip):
        raise FileNotFoundError(f"Vanilla reference not found: {vanilla_zip}")

    with zipfile.ZipFile(vanilla_zip, "r") as z:
        vanilla_build = z.read("build.bin")
        vanilla_anim = z.read("anim.bin")

    patched_build = patch_build_name(vanilla_build, BUILD_NAME)
    patched_anim = patch_anim_bank_hash(vanilla_anim, BANK_NAME)

    atlas_png_path = os.path.join(TEMP, f"atlas_{ITEM_NAME}_composed.png")
    atlas_tex_path = os.path.join(TEMP, f"atlas_{ITEM_NAME}_composed.tex")
    atlas_img.save(atlas_png_path)

    ok, msg = ktech_compress(atlas_png_path, atlas_tex_path, mipmaps=True)
    if not ok:
        raise RuntimeError(f"ktech atlas compression failed: {msg}")
    print(f"  Atlas TEX: {atlas_tex_path}")

    with open(atlas_tex_path, "rb") as f:
        tex_bytes = f.read()

    out_zip = os.path.join(ANIM_DIR, f"{ITEM_NAME}.zip")
    with zipfile.ZipFile(out_zip, "w", zipfile.ZIP_STORED) as zout:
        zout.writestr("anim.bin", patched_anim)
        zout.writestr("build.bin", patched_build)
        zout.writestr("atlas-0.tex", tex_bytes)

    print(f"  Anim ZIP: {out_zip} ({os.path.getsize(out_zip):,} bytes)")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    src = sys.argv[1] if len(sys.argv) > 1 else SRC_DEFAULT
    if not os.path.isfile(src):
        print(f"Source PNG not found: {src}")
        return 1

    os.makedirs(TEMP, exist_ok=True)
    os.makedirs(INV_DIR, exist_ok=True)
    os.makedirs(ANIM_DIR, exist_ok=True)

    print(f"Loading source: {src}")
    item = prepare_item_rgba(src)
    print(f"  Cropped item size: {item.size}")

    print("Building inventory icon...")
    build_inventory_icon(item)

    print("Compositing ground atlas...")
    atlas = compose_item_atlas(item)
    print("Building anim zip...")
    build_anim_zip(atlas)

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
