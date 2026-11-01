"""Pinned upstream sources for the Weeping Hollow's cave kit.

Every scan below is a Poly Haven texture set, dedicated to the public domain under
CC0 1.0 (https://polyhaven.com/license). The upstream files stay CC0; everything
`tools/prepare_cave_kit.py` builds from them into `assets/world/cave/` is licensed
under CC BY-NC-SA 4.0 like the rest of `assets/` (LICENSE.md, section 3).

The files are downloaded by `tools/build_cave_kit.py` into the ignored
`.runtime/cave-source/<asset>/` and checked against these SHA-256 digests before
Blender reads them; a changed upstream file stops the build instead of silently
changing the kit.
"""

from __future__ import annotations

LICENSE_URL = "https://polyhaven.com/license"
RETRIEVED = "2026-11-01"

# `metres` is the physical edge of one tile as Poly Haven measured the scan.
ASSETS = {
    "rock_face_03": {
        "title": "Rock Face 03",
        "page": "https://polyhaven.com/a/rock_face_03",
        "authors": {"Dario Barresi": "Photography", "Rico Cilliers": "Processing"},
        "metres": 2.7,
    },
    "cliff_side": {
        "title": "Cliff Side",
        "page": "https://polyhaven.com/a/cliff_side",
        "authors": {"James Ray Cock": "Photography", "Jenelle van Heerden": "Processing",
                    "Dario Barresi": "Photography"},
        "metres": 1.83,
    },
    "dark_rock_02": {
        "title": "Dark Rock 02",
        "page": "https://polyhaven.com/a/dark_rock_02",
        "authors": {"Amal Kumar": "All"},
        "metres": 2.0,
    },
    "rocks_ground_08": {
        "title": "Rocks Ground 08",
        "page": "https://polyhaven.com/a/rocks_ground_08",
        "authors": {"Rob Tuytel": "All"},
        "metres": 3.0,
    },
    "rock_08": {
        "title": "Rock 08",
        "page": "https://polyhaven.com/a/rock_08",
        "authors": {"Rob Tuytel": "All"},
        "metres": 1.5,
    },
}

_BASE = "https://dl.polyhaven.org/file/ph-assets/Textures"

# (asset, map) -> (url, sha256). Maps: diff (sRGB JPEG), nor_gl (OpenGL normal,
# 16-bit PNG), rough, ao (JPEG) and disp (16-bit PNG), all at 2k.
FILES = {
    ("rock_face_03", "diff"): (f"{_BASE}/jpg/2k/rock_face_03/rock_face_03_diff_2k.jpg",
        "644ee79df7ffbf5f6afc330b64dd3f33794bab8820915fe61ffe0c88ecfd7ece"),
    ("rock_face_03", "nor_gl"): (f"{_BASE}/png/2k/rock_face_03/rock_face_03_nor_gl_2k.png",
        "53044f276b4f1c3041b91c7d4767bda0d75cb4b2d237f08b64eb4e95ee456a93"),
    ("rock_face_03", "rough"): (f"{_BASE}/jpg/2k/rock_face_03/rock_face_03_rough_2k.jpg",
        "9ca3e9e196685f702328f24d66f039b72f5330fc35cf2a2c265cfa50a7916301"),
    ("rock_face_03", "ao"): (f"{_BASE}/jpg/2k/rock_face_03/rock_face_03_ao_2k.jpg",
        "c4fbf883896aed4c787cdca51ebcac40673b1b87d8b7aa35b7714075e0521a94"),
    ("rock_face_03", "disp"): (f"{_BASE}/png/2k/rock_face_03/rock_face_03_disp_2k.png",
        "3cb398fc7e958c4a1c05428dbdb124da70ac5c62dab0820c1fada48065370d2b"),
    ("cliff_side", "diff"): (f"{_BASE}/jpg/2k/cliff_side/cliff_side_diff_2k.jpg",
        "bc6f92d72eb6383ecc3a1094ed9f5b37efb36ccf83cf29699bb5990e6775afee"),
    ("cliff_side", "nor_gl"): (f"{_BASE}/png/2k/cliff_side/cliff_side_nor_gl_2k.png",
        "7674007afe533d0073ff373e028c29048362d14224bf0eb2e6045bb42fc18c89"),
    ("cliff_side", "rough"): (f"{_BASE}/jpg/2k/cliff_side/cliff_side_rough_2k.jpg",
        "7fd4f6d289b1b44c812533eaea7802e640dda55070b9746025a9d33117a1bd1f"),
    ("cliff_side", "ao"): (f"{_BASE}/jpg/2k/cliff_side/cliff_side_ao_2k.jpg",
        "1eece16c4b89c4acc5e2d3e66cf1b34403e8404f75630df227a854f735c495cd"),
    ("cliff_side", "disp"): (f"{_BASE}/png/2k/cliff_side/cliff_side_disp_2k.png",
        "be974eb7ef5ecb17be1a574c8cadf09d47794983cacc0c27e953bbe47dedfd6f"),
    ("dark_rock_02", "diff"): (f"{_BASE}/jpg/2k/dark_rock_02/dark_rock_02_diff_2k.jpg",
        "da78fb6dd90414ada98f6e1627aca6bc1acb480c8bce7aabfbde8e3beb666a71"),
    ("dark_rock_02", "nor_gl"): (f"{_BASE}/png/2k/dark_rock_02/dark_rock_02_nor_gl_2k.png",
        "5dde27931ec17e3f664b0cef14665315dbadbd18b78627b67b7e82327ec7002b"),
    ("dark_rock_02", "rough"): (f"{_BASE}/jpg/2k/dark_rock_02/dark_rock_02_rough_2k.jpg",
        "862e12577eb957fd34f181895965623cbcd0a55c9106d4ded6eac3d8cd503f89"),
    ("dark_rock_02", "ao"): (f"{_BASE}/jpg/2k/dark_rock_02/dark_rock_02_ao_2k.jpg",
        "a2999bb18c58189e228cbc86841339c91a574865b90033896a2328581e6d97b0"),
    ("dark_rock_02", "disp"): (f"{_BASE}/png/2k/dark_rock_02/dark_rock_02_disp_2k.png",
        "f1f452f2bbc13b2c094f52262b39e0e4e7fd7114bb4eaea33f805f1cd972ae4f"),
    ("rocks_ground_08", "diff"): (f"{_BASE}/jpg/2k/rocks_ground_08/rocks_ground_08_diff_2k.jpg",
        "7d27d8f729950d5d23cb4ca111ed67875792776c9e4c0f185d939a734d442ee1"),
    ("rocks_ground_08", "nor_gl"): (f"{_BASE}/png/2k/rocks_ground_08/rocks_ground_08_nor_gl_2k.png",
        "9b37dda5dbbe9fb140b1aa3c546bcd2ba62565d993edb886cba5c5fed8677d63"),
    ("rocks_ground_08", "rough"): (f"{_BASE}/jpg/2k/rocks_ground_08/rocks_ground_08_rough_2k.jpg",
        "669beb86f18008582c58c70eb1f458f5e4a849f70fabdb583de4ac93f5bd1d4d"),
    ("rocks_ground_08", "ao"): (f"{_BASE}/jpg/2k/rocks_ground_08/rocks_ground_08_ao_2k.jpg",
        "8932a656285ad95795f2d41265a33dce98b4e6146e622ac98a6735196ffc5610"),
    ("rocks_ground_08", "disp"): (f"{_BASE}/png/2k/rocks_ground_08/rocks_ground_08_disp_2k.png",
        "ee9ab75dedfa1eecb8f3a0c73c310f5f62ca82e9399764d17df1d956e2a2c4b2"),
    ("rock_08", "diff"): (f"{_BASE}/jpg/2k/rock_08/rock_08_diff_2k.jpg",
        "1d55cc7c6357ad30b9486c38f280c6da095a0a07246b2659403a3a36006db521"),
    ("rock_08", "nor_gl"): (f"{_BASE}/png/2k/rock_08/rock_08_nor_gl_2k.png",
        "d7f01008d159f013311dfa2b062a6c51bafd181355214c4af6cfeedd50704ed4"),
    ("rock_08", "rough"): (f"{_BASE}/jpg/2k/rock_08/rock_08_rough_2k.jpg",
        "7605d6f529bed165c52486d221f2778632e34012f9cb06645377e374cad0b647"),
    ("rock_08", "ao"): (f"{_BASE}/jpg/2k/rock_08/rock_08_ao_2k.jpg",
        "2785bac58ce6d53a179ea81120da211d849bdcec3bb35a108b080f76762fd213"),
    ("rock_08", "disp"): (f"{_BASE}/png/2k/rock_08/rock_08_disp_2k.png",
        "866391452999271579c0e419bde021ea49ec86b54a87f0f226d8240ea05ddaa3"),
}


def local_name(asset: str, kind: str) -> str:
    """The file name a pinned download is stored under in its asset folder."""
    return FILES[(asset, kind)][0].rsplit("/", 1)[1]
