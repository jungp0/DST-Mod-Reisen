"""
Build reisen_casual.zip using armor_grass as structural template.
10 frames:  0-2 = front (center, left-tilt, right-tilt)
            3-5 = side  (center, left-tilt, right-tilt)
            6-8 = back  (center, left-tilt, right-tilt)
            13  = ground (inventory icon)
Source views: Reisen jacket reskinned to grassarmor colors
  grassarmor_vest_raw_front.png  → front (120x90)
  grassarmor_vest_raw_side.png   → side  (120x120)
  grassarmor_vest_raw_back.png   → back  (120x120)

Run from mod root:
  python tools/build_sanity_style_atlas.py

Optional env: DST_VANILLA_ANIM (path to .../data/anim), KTECH (path to ktech.exe).
"""
import struct, zipfile, os, sys, subprocess, shutil, math
from pathlib import Path

from PIL import Image, ImageDraw

_MOD_ROOT = Path(__file__).resolve().parents[1]
MOD_DIR  = str(_MOD_ROOT)
TEMP     = os.path.join(MOD_DIR, "temp")
ANIM_DIR = os.path.join(MOD_DIR, "anim")
VANILLA  = os.environ.get(
    "DST_VANILLA_ANIM",
    r"E:\SteamLibrary\steamapps\common\Don't Starve Together\data\anim",
)
KTECH    = os.environ.get("KTECH", r"E:\Workspace\ktools\build\Release\ktech.exe")
STEX     = os.path.join(MOD_DIR, r"tools\bin\stex_v0.6\bin\Stex.exe")
SRC_DIR  = os.path.join(MOD_DIR, "tools", "src", "grassarmor_vest_sources")

MOD_BUILD_NAME = "reisen_casual"
MOD_BANK_NAME  = "reisen_casual"

# Reisen-jacket-proportioned sprites
VIEW_SRC = {
    "front": os.path.join(SRC_DIR, "grassarmor_vest_raw_front.png"),
    "side":  os.path.join(SRC_DIR, "grassarmor_vest_raw_side.png"),
    "back":  os.path.join(SRC_DIR, "grassarmor_vest_raw_back.png"),
}
GROUND_SRC = os.path.join(MOD_DIR, "images", "inventoryimages", "reisen_casual.png")

# Use armor_grass as template (closest proportions to jacket)
TEMPLATE_ZIP = "armor_grass.zip"

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

FLIP_H = {"side"}

# Source images are now pre-proportioned to match UV aspect ratios,
# so standard min-fit scaling works correctly for all views.
HEIGHT_FILL = None
SCALE = {"front": 0.98, "side": 0.98, "back": 0.98, "ground": 0.92}
TOP_ALIGN = True

ALPHA_THR = 15


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def sdbm_hash(s):
    h = 0
    for c in s.lower():
        h = (ord(c) + (h << 6) + (h << 16) - h) & 0xFFFFFFFF
    return h


def parse_build_bin(data):
    off = 0
    magic = data[off:off+4]; off += 4
    ver   = struct.unpack_from("<I", data, off)[0]; off += 4
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
    avc = struct.unpack_from("<I", data, off)[0]; off += 4
    verts = []
    for _ in range(avc):
        vx,vy,vz = struct.unpack_from("<3f", data, off); off += 12
        vu,vv,vw = struct.unpack_from("<3f", data, off); off += 12
        verts.append((vx,vy,vz,vu,vv,vw))
    return bname, anames, frames, verts


def patch_build_name(data, new_name):
    off = 4 + 4 + 4 + 4
    old_len = struct.unpack_from("<I", data, off)[0]
    end = off + 4 + old_len
    nb = new_name.encode()
    return data[:off] + struct.pack("<I", len(nb)) + nb + data[end:]


def patch_anim_bank(data, new_bank):
    data = bytearray(data)
    new_hash = sdbm_hash(new_bank)
    off = 8 + 4 + 4 + 4
    num = struct.unpack_from("<I", data, off)[0]; off += 4
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


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.returncode == 0, r.stdout + r.stderr


def remove_green_bg(img):
    """Chroma-key removal for bright green (#00CC00-ish) background."""
    arr = __import__("numpy").array(img)
    green = (arr[:,:,1] > 140) & (arr[:,:,0] < 130) & (arr[:,:,2] < 130)
    arr[green, 3] = 0
    return Image.fromarray(arr, "RGBA")


def load_view(path, flip=False):
    img = Image.open(path).convert("RGBA")
    img = remove_green_bg(img)
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
    if flip:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    return img


def make_tilt(base_img, deg, top_frac=0.15):
    """
    Rotate `base_img` by `deg` degrees, pivoting around a point near the TOP
    of the sprite (shoulder area), so the vest swings like a pendulum.
    top_frac=0.15 → pivot at 15% from top.
    Returns a new RGBA image, canvas expanded to avoid clipping.
    """
    if deg == 0:
        return base_img.copy()
    W, H = base_img.size
    pivot_y = int(H * top_frac)

    # Translate pivot to origin, rotate, translate back
    # PIL Image.rotate() rotates around center; we shift instead.
    # Expand canvas by padding, rotate around new center that corresponds to pivot.
    pad = int(math.ceil(max(W, H) * abs(math.sin(math.radians(deg))) * 1.5)) + 4
    padded = Image.new("RGBA", (W + 2*pad, H + 2*pad), (0, 0, 0, 0))
    padded.paste(base_img, (pad, pad), base_img)
    # pivot in padded coords
    px = pad + W // 2
    py = pad + pivot_y
    # PIL rotates CCW by default; positive deg → lean right means CW → use -deg
    pW, pH = padded.size
    # PIL rotates around center of image; offset center to our pivot:
    cx, cy = pW / 2, pH / 2
    # Translate so pivot is at center, rotate, translate back using affine
    from PIL import ImageTransform
    rad = math.radians(-deg)  # PIL CCW positive, we want CW for positive lean-right
    cos_a, sin_a = math.cos(rad), math.sin(rad)
    # Affine: rotate around (px, py)
    # x' = cos*(x-px) - sin*(y-py) + px
    # y' = sin*(x-px) + cos*(y-py) + py
    # PIL affine data = (a,b,c,d,e,f) where: X = a*x+b*y+c, Y = d*x+e*y+f
    # inverse transform for PIL:
    a, b, c = cos_a, sin_a, px*(1-cos_a) - py*sin_a
    d, e, f = -sin_a, cos_a, py*(1-cos_a) + px*sin_a
    rotated = padded.transform(
        padded.size, Image.AFFINE,
        (a, b, c, d, e, f),
        resample=Image.BICUBIC
    )
    bbox = rotated.getbbox()
    if bbox:
        rotated = rotated.crop(bbox)
    return rotated


def fit_into(src, rw, rh, scale, top_align=False, height_fill=None):
    """
    Scale src to fit within rw x rh.
    height_fill: if set, scale so sprite fills this fraction of rh (height-priority).
                 Falls back to width if result would exceed rw.
    top_align=True: paste from top of region.
    """
    src = src.convert("RGBA")
    bbox = src.getbbox()
    if not bbox:
        return Image.new("RGBA", (rw, rh), (0, 0, 0, 0))
    src = src.crop(bbox)
    sw, sh = src.size
    if height_fill is not None:
        # Scale by height to fill target fraction of UV region height
        s = (rh * height_fill / sh) * scale
        nw = int(sw * s)
        if nw > rw:          # too wide — fall back to width-fit
            s = (rw / sw) * scale
    else:
        if top_align:
            s = (rw / sw) * scale
        else:
            s = min(rw / sw, rh / sh) * scale
    nw, nh = max(1, int(sw*s)), max(1, int(sh*s))
    nw = min(nw, rw)
    nh = min(nh, rh)
    resized = src.resize((nw, nh), Image.LANCZOS)
    out = Image.new("RGBA", (rw, rh), (0, 0, 0, 0))
    ox = (rw - nw) // 2
    oy = 2 if top_align else (rh - nh) // 2
    out.paste(resized, (ox, oy), resized)
    return out


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

print("=" * 60)
print("Building reisen_casual (armor_sanity style, 10 frames)")
print("=" * 60)

# 1. Load source views
print("\n[1] Loading source images...")
base_views = {}
for vname, path in VIEW_SRC.items():
    if not os.path.exists(path):
        print(f"  ERROR missing: {path}"); sys.exit(1)
    img = load_view(path, flip=(vname in FLIP_H))
    base_views[vname] = img
    print(f"  {vname}: {img.size}")

# Pre-generate tilted variants to avoid repeated computation
view_variants = {}  # (view, deg) -> image
for vname, base in base_views.items():
    for deg in (0, -8, +8):
        view_variants[(vname, deg)] = make_tilt(base, deg)
        print(f"  tilt {vname} {deg:+d}°: {view_variants[(vname,deg)].size}")

# 2. Parse template build.bin
print(f"\n[2] Parsing {TEMPLATE_ZIP} build.bin...")
sanity_zip = os.path.join(VANILLA, TEMPLATE_ZIP)
with zipfile.ZipFile(sanity_zip) as z:
    build_data = z.read("build.bin")
    anim_data  = z.read("anim.bin")
    tex_data   = z.read("atlas-0.tex")

bname, anames, frames, verts = parse_build_bin(build_data)
print(f"  Build={bname}  frames={len(frames)}  atlas={anames}")

# 3. Decompress atlas to get size
print("\n[3] Decompressing atlas...")
tmp_tex = os.path.join(TEMP, "_sanity_ref.tex")
tmp_png = os.path.join(TEMP, "_sanity_ref.png")
with open(tmp_tex, "wb") as f:
    f.write(tex_data)
ok, msg = run([STEX, "decompress", "-i", tmp_tex, "-o", tmp_png])
if not ok:
    print(f"  STEX failed: {msg}"); sys.exit(1)
ref_img = Image.open(tmp_png).convert("RGBA")
ATW, ATH = ref_img.size
print(f"  Atlas size: {ATW}x{ATH}")

# 4. Composite new atlas
print("\n[4] Compositing frames...")
atlas = Image.new("RGBA", (ATW, ATH), (0, 0, 0, 0))
SWAP_HASH = sdbm_hash("swap_body")

for frm in frames:
    if frm["sh"] != SWAP_HASH or frm["ac"] == 0:
        continue
    fn = frm["fn"]
    fverts = verts[frm["ai"]:frm["ai"]+frm["ac"]]
    us = [v[3] for v in fverts]; vs2 = [v[4] for v in fverts]
    xl = int(round(min(us)*ATW)); xr = int(round(max(us)*ATW))
    yt = int(round((1-max(vs2))*ATH)); yb = int(round((1-min(vs2))*ATH))
    rw, rh = max(1, xr-xl), max(1, yb-yt)

    if fn == 13:
        # Ground: inventory icon
        ground = Image.open(GROUND_SRC).convert("RGBA")
        sprite = fit_into(ground, rw, rh, SCALE["ground"])
        tag = "ground"
    elif fn in FRAME_MAP:
        vname, deg = FRAME_MAP[fn]
        src = view_variants[(vname, deg)]
        hf = HEIGHT_FILL if vname != "ground" else None
        sprite = fit_into(src, rw, rh, SCALE[vname], top_align=TOP_ALIGN, height_fill=hf)
        tag = f"{vname} {deg:+d}°"
    else:
        continue

    atlas.paste(sprite, (xl, yt), sprite)
    print(f"  frame{fn:2d} [{tag:14s}]: region ({xl},{yt})-({xr},{yb}) {rw}x{rh}")

# 5. Save atlas PNG
atlas_png = os.path.join(TEMP, "reisen_casual_atlas.png")
atlas.save(atlas_png)
print(f"\n[5] Saved atlas PNG: {atlas_png}")

# 6. Compress to TEX
atlas_tex = os.path.join(TEMP, "reisen_casual_atlas.tex")
ok, msg = run([KTECH, "--no-mipmaps", "-c", "dxt5", atlas_png, atlas_tex])
if not ok:
    print(f"  ktech failed: {msg}"); sys.exit(1)
print(f"[6] TEX: {os.path.getsize(atlas_tex)} bytes")

# 7. Patch binaries
patched_build = patch_build_name(build_data, MOD_BUILD_NAME)
patched_anim  = patch_anim_bank(anim_data, MOD_BANK_NAME)
v, _, _, _ = parse_build_bin(patched_build)
print(f"[7] Patched build name: '{v}'  bank hash: 0x{sdbm_hash(MOD_BANK_NAME):08x}")

# 8. Write zip
mod_zip = os.path.join(ANIM_DIR, "reisen_casual.zip")
backup  = os.path.join(TEMP, "reisen_casual_pre_sanity.zip")
if os.path.exists(mod_zip):
    shutil.copy2(mod_zip, backup)
    print(f"[8] Backup: {backup}")

with open(atlas_tex, "rb") as f:
    tex_bytes = f.read()
with zipfile.ZipFile(mod_zip, "w", zipfile.ZIP_STORED) as zout:
    zout.writestr("anim.bin",   patched_anim)
    zout.writestr("build.bin",  patched_build)
    zout.writestr("atlas-0.tex", tex_bytes)
print(f"    Written: {mod_zip} ({os.path.getsize(mod_zip)} bytes)")

# Verify
vn, _, _, _ = parse_build_bin(zipfile.ZipFile(mod_zip).read("build.bin"))
print(f"\nVerification: build='{vn}'  {'OK' if vn==MOD_BUILD_NAME else 'FAIL'}")
print("Done!")
