# Reisen Mod - Build Tools

This folder contains the build pipeline for generating the mod's animation zip files
and inventory icon textures from source artwork.

## Directory Structure

```
tools/
├── src/                          # Source artwork (inputs to the build pipeline)
│   ├── grassarmor_vest_sources/  # Front/side/back panel PNGs for grassarmor
│   ├── reisen_grassarmor_clean_512.png
│   ├── reisen_charm_generated_512.png
│   ├── nightmail_inv_clean.png
│   ├── reisen_jacket_three_views_dst_handdrawn_v3_sidefix.png
│   ├── reisen_sleeveless_vest_three_views_ai_v9.png
│   └── ...
├── bin/                          # Place Stex.exe here (see Setup below)
├── build_casual_from_triptych.py
├── build_uniform_from_triptych.py
├── build_sanity_style_atlas.py
├── prepare_sleeveless_triptych_for_casual_atlas.py
├── rebuild_charm_garland.py
├── convert_inventory_tex.bat
└── download_stex.bat             # Run this to download Stex.exe
```

## Setup

### 1. Python Dependencies

```
pip install Pillow opencv-python numpy scipy
```

### 2. Stex (TEX atlas tool)

Run `tools/download_stex.bat` to download `Stex.exe` automatically, or download
manually from:

> https://github.com/oblivioncth/Stexatlaser/releases

Place `Stex.exe` into `tools/bin/`.

### 3. ktech (Klei TEX compressor)

`ktech.exe` is part of the official Don't Starve Together mod tools. Download from:

> https://accounts.klei.com/assets/gamedata/dont-starve-together/tools/tools.zip

Set the `KTECH` environment variable to the path of `ktech.exe`, or edit the
`KTECH` constant at the top of the relevant script.

## Build Scripts

| Script | Output | Description |
|--------|--------|-------------|
| `build_casual_from_triptych.py` | `anim/reisen_casual.zip` | Moon Rabbit Casual from triptych PNG |
| `build_uniform_from_triptych.py` | `anim/reisen_uniform.zip` | Lunar Battle Uniform from triptych PNG |
| `build_sanity_style_atlas.py` | `anim/reisen_casual.zip` | Moon Rabbit Casual from flat panel PNGs |
| `rebuild_charm_garland.py` | `anim/reisen_charm.zip` | Lunatic Vision Choker from reference PNG |
| `prepare_sleeveless_triptych_for_casual_atlas.py` | `tools/src/grassarmor_vest_sources/` | Split triptych into panels |

### Usage

Run all scripts from the mod root directory:

```bat
cd path\to\mods\reisen

python tools/build_casual_from_triptych.py
python tools/build_uniform_from_triptych.py
python tools/rebuild_charm_garland.py
```

Each script accepts an optional path argument to override the default source image:

```bat
python tools/build_casual_from_triptych.py path\to\my_triptych.png
python tools/build_uniform_from_triptych.py front.png side.png back.png
```

### Inventory Icon TEX Conversion

`convert_inventory_tex.bat` uses Stex to convert PNG inventory icons to TEX format.
Run from the mod root after placing Stex.exe in `tools/bin/`.

## Intermediate Files

Build scripts write intermediate files to `temp/` (auto-created, not tracked in git).
