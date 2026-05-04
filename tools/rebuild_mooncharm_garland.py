"""
Rebuild reisen_charm world + inventory art from reference PNG (neck collar / choker).

- Keeps hat_healinggarland build.bin / anim.bin layout (reisen_hat / reisenhat) so the zip stays valid.
- Atlas: transparent 512x256 (2x vanilla); full choker scaled into each sprite cell (side / front / back / ground)
  so ground + floater always show the same art. Ground cell: soft contact shadow only (no alpha-dilate outline hack).
  512x256 gives 4x more pixels than the vanilla 256x128, improving ground-drop sharpness.
- Inventory: 64x64 from the reference (not from atlas crop).

Requires: Pillow, ktech.exe in tools/bin.
"""
from __future__ import annotations

import os
import shutil
import struct
import subprocess
import sys
import zipfile

from PIL import Image, ImageDraw

MOD_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
TEMP = os.path.join(MOD_DIR, "temp")
TMP = os.path.join(MOD_DIR, "tools", "src")
INV_DIR = os.path.join(MOD_DIR, "images", "inventoryimages")
ANIM_DIR = os.path.join(MOD_DIR, "anim")
VANILLA_ANIM = os.path.normpath(
    os.path.join(os.path.dirname(MOD_DIR), "..", "data", "anim")
)
KTECH = os.environ.get("KTECH") or r"E:\Workspace\ktools\build\Release\ktech.exe"

# Reference PNG (may be larger than 512).
MOON_REF_DEFAULT = os.path.join(TMP, "reisen_charm_generated_512.png")

def sdbm_hash(s: str) -> int:
    h = 0
    for c in s.lower():
        h = (ord(c) + (h << 6) + (h << 16) - h) & 0xFFFFFFFF
    return h


def ktech_compress(png_path: str, tex_path: str, mipmaps: bool = True) -> tuple[bool, str]:
    if not os.path.isfile(KTECH):
        return False, f"Missing ktech: {KTECH}"
    args = [KTECH, "-c", "dxt5", png_path, tex_path]
    if not mipmaps:
        args.insert(1, "--no-mipmaps")
    r = subprocess.run(args, capture_output=True, text=True)
    return r.returncode == 0, r.stdout + r.stderr


def _cut_white_bg_rgba(img: Image.Image, white_thresh: int = 248) -> Image.Image:
    """Make near-white pixels transparent (for reference art on white)."""
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if r >= white_thresh and g >= white_thresh and b >= white_thresh:
                px[x, y] = (r, g, b, 0)
    return img


def _prepare_choker_rgba(ref_path: str) -> Image.Image:
    ref = Image.open(ref_path).convert("RGBA")
    ref = _cut_white_bg_rgba(ref)
    bb = ref.getbbox()
    return ref.crop(bb) if bb else ref


# hat_healinggarland atlas layout scaled to 512x256 (2x vanilla 256x128).
# UV coordinates in build.bin are normalised floats, so the larger canvas maps identically.
# Ground cell goes from 82x21 px -> 164x42 px, giving 4x more pixel density.
ATLAS_W, ATLAS_H = 512, 256
GARLAND_REGIONS: tuple[tuple[tuple[int, int, int, int], bool], ...] = (
    ((2,  2, 254, 118), False),   # side view
    ((256, 2, 378, 124), False),  # front cluster
    ((380, 2, 504, 124), False),  # back cluster
    ((344, 128, 508, 170), True), # ground / floater
)


def _draw_ground_shadow(
    atlas: Image.Image,
    px: int,
    py: int,
    nw: int,
    nh: int,
    y1: int,
) -> None:
    """Soft contact shadow under the item (follows item width, no chunky outer ring)."""
    dr = ImageDraw.Draw(atlas)
    pad = max(3, nw // 10)
    sy0 = min(y1 - 8, py + nh - 1)
    sy1 = min(y1, sy0 + 10)
    sx0 = px + pad
    sx1 = px + nw - pad
    if sx1 <= sx0 or sy1 <= sy0:
        return
    dr.ellipse([sx0, sy0, sx1, sy1], fill=(18, 14, 12, 140))
    dr.ellipse(
        [sx0 + 2, sy0 + 1, sx1 - 2, sy1 - 1],
        fill=(10, 8, 6, 100),
    )


def _fit_paste_choker(
    atlas: Image.Image,
    box: tuple[int, int, int, int],
    choker: Image.Image,
    *,
    ground_shadow: bool,
) -> None:
    x0, y0, x1, y1 = box
    bw, bh = x1 - x0, y1 - y0
    cw, ch = choker.size
    if cw <= 0 or ch <= 0 or bw <= 0 or bh <= 0:
        return
    margin = 2
    scale = min((bw - margin * 2) / cw, (bh - margin * 2) / ch)
    nw = max(1, int(cw * scale))
    nh = max(1, int(ch * scale))
    s = choker.resize((nw, nh), Image.LANCZOS)
    px = x0 + (bw - nw) // 2
    py = y0 + (bh - nh) // 2
    if ground_shadow:
        _draw_ground_shadow(atlas, px, py, nw, nh, y1)
    atlas.paste(s, (px, py), s)


def compose_mooncharm_item_atlas(ref_path: str) -> Image.Image:
    choker = _prepare_choker_rgba(ref_path)
    atlas = Image.new("RGBA", (ATLAS_W, ATLAS_H), (0, 0, 0, 0))
    for box, shadow in GARLAND_REGIONS:
        _fit_paste_choker(atlas, box, choker, ground_shadow=shadow)
    return atlas


def parse_build_bin(data: bytes):
    offset = 0
    magic = data[offset : offset + 4]
    offset += 4
    version = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    if magic != b"BILD" or version != 6:
        raise ValueError(f"Bad build.bin: {magic!r} v{version}")

    sym_count = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    frame_count = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    name_len = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    build_name = data[offset : offset + name_len].decode("utf-8", errors="replace")
    offset += name_len

    atlas_count = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    atlas_names = []
    for _ in range(atlas_count):
        n = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        atlas_names.append(data[offset : offset + n].decode("utf-8", errors="replace"))
        offset += n

    frames = []
    for _ in range(sym_count):
        struct.unpack_from("<I", data, offset)[0]
        offset += 4
        sym_frames = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        for _ in range(sym_frames):
            struct.unpack_from("<I", data, offset)[0]
            offset += 4
            struct.unpack_from("<I", data, offset)[0]
            offset += 4
            struct.unpack_from("<f", data, offset)[0]
            offset += 4
            struct.unpack_from("<f", data, offset)[0]
            offset += 4
            struct.unpack_from("<f", data, offset)[0]
            offset += 4
            struct.unpack_from("<f", data, offset)[0]
            offset += 4
            alphaidx = struct.unpack_from("<I", data, offset)[0]
            offset += 4
            alphacount = struct.unpack_from("<I", data, offset)[0]
            offset += 4
            frames.append({"alphaidx": alphaidx, "alphacount": alphacount})

    alpha_vert_count = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    verts = []
    for _ in range(alpha_vert_count):
        vx, vy, vz = struct.unpack_from("<3f", data, offset)
        offset += 12
        vu, vv, vw = struct.unpack_from("<3f", data, offset)
        offset += 12
        verts.append((vx, vy, vz, vu, vv, vw))

    return build_name, atlas_names, frames, verts


def patch_build_name(data: bytes, new_name: str) -> bytes:
    offset = 0
    offset += 4
    offset += 4
    offset += 4
    offset += 4
    name_len_offset = offset
    old_name_len = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    old_name_end = offset + old_name_len
    new_name_bytes = new_name.encode("utf-8")
    result = bytearray()
    result.extend(data[:name_len_offset])
    result.extend(struct.pack("<I", len(new_name_bytes)))
    result.extend(new_name_bytes)
    result.extend(data[old_name_end:])
    return bytes(result)


def patch_anim_bank_hash(data: bytes, new_bank_name: str) -> bytes:
    data = bytearray(data)
    new_hash = sdbm_hash(new_bank_name)
    offset = 8
    num_elems = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    num_frames = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    num_events = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    num_anims = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    for _ in range(num_anims):
        name_len = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        offset += name_len
        offset += 1
        struct.pack_into("<I", data, offset, new_hash)
        offset += 4
        offset += 4
        anim_frame_count = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        for _ in range(anim_frame_count):
            offset += 16
            f_events = struct.unpack_from("<I", data, offset)[0]
            offset += 4
            f_elems = struct.unpack_from("<I", data, offset)[0]
            offset += 4
            offset += f_events * 4
            offset += f_elems * 40
    return bytes(data)


def rebuild_atlas_zip_from_png(atlas_png: Image.Image) -> None:
    vanilla_ref = "hat_healinggarland"
    mod_name = "reisen_charm"
    mod_build = "reisen_hat"
    mod_bank = "reisenhat"

    vanilla_zip_path = os.path.join(VANILLA_ANIM, f"{vanilla_ref}.zip")
    if not os.path.isfile(vanilla_zip_path):
        raise FileNotFoundError(vanilla_zip_path)

    with zipfile.ZipFile(vanilla_zip_path, "r") as z:
        vanilla_build_data = z.read("build.bin")
        vanilla_anim_data = z.read("anim.bin")

    patched_build = patch_build_name(vanilla_build_data, mod_build)
    patched_anim = patch_anim_bank_hash(vanilla_anim_data, mod_bank)

    atlas_png_path = os.path.join(TEMP, "atlas_reisen_charm_composed.png")
    atlas_png.save(atlas_png_path)

    atlas_tex_out = os.path.join(TEMP, "atlas_reisen_charm_composed.tex")
    ok, msg = ktech_compress(atlas_png_path, atlas_tex_out, mipmaps=True)
    if not ok:
        raise RuntimeError(f"Atlas ktech: {msg}")

    with open(atlas_tex_out, "rb") as f:
        tex_bytes = f.read()

    mod_zip_path = os.path.join(ANIM_DIR, f"{mod_name}.zip")
    with zipfile.ZipFile(mod_zip_path, "w", zipfile.ZIP_STORED) as zout:
        zout.writestr("anim.bin", patched_anim)
        zout.writestr("build.bin", patched_build)
        zout.writestr("atlas-0.tex", tex_bytes)

    new_bname, _, _, _ = parse_build_bin(patched_build)
    print(f"  Build: {new_bname!r}, zip: {mod_zip_path} ({os.path.getsize(mod_zip_path)} bytes)")


def rebuild_inventory_icon_from_ref(ref_path: str) -> None:
    """64x64 icon from full reference art (matches inventory / concept)."""
    name = "reisen_charm"
    choker = _prepare_choker_rgba(ref_path)
    cw, ch = choker.size
    max_dim = max(cw, ch)
    square = Image.new("RGBA", (max_dim, max_dim), (0, 0, 0, 0))
    square.paste(choker, ((max_dim - cw) // 2, (max_dim - ch) // 2), choker)
    icon = square.resize((64, 64), Image.LANCZOS)
    png_path = os.path.join(INV_DIR, f"{name}.png")
    icon.save(png_path)
    tex_path = os.path.join(INV_DIR, f"{name}.tex")
    ok, msg = ktech_compress(png_path, tex_path, mipmaps=False)
    if not ok:
        raise RuntimeError(f"Inventory ktech: {msg}")
    print(f"  Inventory: {png_path}")


def save_working_preview(ref_path: str) -> None:
    """Mirror reference into tmp for a stable preview path."""
    out = os.path.join(TMP, "reisen_charm_clean_512.png")
    shutil.copy2(ref_path, out)
    print(f"  Working preview: {out}")


def main() -> int:
    ref = MOON_REF_DEFAULT
    if len(sys.argv) > 1:
        ref = sys.argv[1]
    if not os.path.isfile(ref):
        print(f"Moon reference not found: {ref}")
        return 1

    os.makedirs(TEMP, exist_ok=True)
    os.makedirs(TMP, exist_ok=True)

    print(f"Building item atlas from {ref}...")
    atlas = compose_mooncharm_item_atlas(ref)
    save_working_preview(ref)

    print("Rebuilding inventory icon...")
    rebuild_inventory_icon_from_ref(ref)

    print("Rebuilding anim zip...")
    rebuild_atlas_zip_from_png(atlas)
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
