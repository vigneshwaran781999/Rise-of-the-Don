"""Countryside kit (M7) -> assets/models/buildings/, props/

Velanagar's villages and fields (GDD §2 district 6): green, open, a calm escape. Pivot at the base
centre, front facing Blender -Y. Material names with night glow: window_glass, lamp_lens, neon_*
(see scripts/world/kit_baker.gd).

  bld_cs_hut           round village hut, 6 m across: ochre mud walls, a conical thatched roof
  bld_cs_farmhouse     10 x 12 m farmhouse: whitewashed, tiled roof, a deep verandah on posts
  bld_cs_teastall      6 x 6 m tea stall: tin roof on poles, counter, kettle, a TEA board
  prop_cs_well         village well with a pulley frame
  prop_cs_haystack     haystack on a raised base
  prop_cs_paddy        20 x 20 m paddy-field tile: low bunds round the edge, rows of rice over
                       wet earth. Laid as ground (no collision, no shadow)

Run:  "$BLENDER" --background --factory-startup --python tools/blender/countryside.py [-- names...]
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rotd_mesh as rm  # noqa: E402


def collide(name: str, boxes: list) -> None:
    col = rm.CollisionSet(name)
    for b in boxes:
        col.box(*b)
    col.build()


def hut() -> None:
    name = "bld_cs_hut"
    rm.clear_scene()
    mud = rm.material("cs_mud_ochre", "#c08a52", roughness=0.95)
    band = rm.material("cs_lime_band", "#efe6d2", roughness=0.9)
    thatch = rm.material("bh_thatch", "#b38a4a", roughness=0.95)
    wood = rm.material("ot_door_wood", "#5a3a22", roughness=0.8)
    mb = rm.MeshBuilder()
    mb.cylinder(0.0, 0.0, 0.0, 3.0, 3.0, 0.3, 14, band)
    mb.cylinder(0.0, 0.0, 0.3, 2.8, 2.8, 2.2, 14, mud, caps=False)
    mb.cylinder(0.0, 0.0, 2.3, 3.6, 0.15, 2.6, 14, thatch)
    mb.box(-0.5, -2.86, 0.3, 0.5, -2.7, 2.1, wood, skip=("back",))
    mb.build(name)
    col = rm.CollisionSet(name)
    col.frustum(0.0, 0.0, 0.0, 5.6, 5.6, 5.6, 5.6, 2.5)
    col.frustum(0.0, 0.0, 2.3, 6.4, 6.4, 0.4, 0.4, 2.6)
    col.build()
    rm.export_glb("buildings", name)


def farmhouse() -> None:
    name = "bld_cs_farmhouse"
    rm.clear_scene()
    wall = rm.material("cs_whitewash", "#f1ece0", roughness=0.9)
    plinth = rm.material("ot_plinth", "#6d6257", roughness=0.92)
    tile = rm.material("clay_tile", "#b5532f", roughness=0.85)
    wood = rm.material("ot_door_wood", "#5a3a22", roughness=0.8)
    blue = rm.material("cs_door_blue", "#3a6ea5", roughness=0.7)
    glass = rm.material("window_glass", "#2a3644", roughness=0.18, metallic=0.35)
    mb = rm.MeshBuilder()
    x0, y0, x1, y1 = -5.0, -6.0, 5.0, 6.0
    yf = -2.5                                                  # front wall (verandah in front of it)
    mb.box(x0, y0, 0.0, x1, y1, 0.4, plinth, skip=("bottom",))
    mb.box(x0, yf, 0.4, x1, y1, 3.4, wall, skip=("bottom",))
    mb.box(-0.6, yf - 0.05, 0.4, 0.6, yf, 2.5, blue, skip=("back",))
    for u in (-3.0, 3.0):
        mb.box(u - 0.6, yf - 0.04, 1.2, u + 0.6, yf, 2.3, glass, skip=("back",))
    for px in (x0 + 0.2, -1.7, 1.5, x1 - 0.4):
        mb.box(px, y0 + 0.2, 0.4, px + 0.2, y0 + 0.4, 2.9, wood, skip=("bottom",))
    mb.prism([(y0 - 0.4, 2.8), (0.5, 5.2), (y1 + 0.4, 3.2)], "X", x0 - 0.3, x1 + 0.3, tile)
    mb.build(name)
    collide(name, [(x0, yf, 0.0, x1, y1, 5.2), (x0, y0, 0.0, x1, yf, 0.4), (x0 + 0.2, y0 + 0.2, 0.4, x0 + 0.4, y0 + 0.4, 2.9),
                   (x1 - 0.4, y0 + 0.2, 0.4, x1 - 0.2, y0 + 0.4, 2.9)])
    rm.export_glb("buildings", name)


def teastall() -> None:
    name = "bld_cs_teastall"
    rm.clear_scene()
    post = rm.material("ot_door_wood", "#5a3a22", roughness=0.8)
    tin = rm.material("cs_tin_roof", "#8a9097", roughness=0.5, metallic=0.5)
    counter = rm.material("cs_counter_green", "#3f7d4f", roughness=0.8)
    steel = rm.material("in_table_steel", "#b7bcc0", roughness=0.35, metallic=0.6)
    board = rm.material("bh_board_blue", "#1d4f8c", roughness=0.6)
    letters = rm.material("sign_letters", "#f4f1e8", roughness=0.6)
    light = rm.material("lamp_lens", "#f6e6b0", roughness=0.2, emission="#fff1c0", emission_strength=1.5)
    mb = rm.MeshBuilder()
    for (px, py) in ((-2.8, -2.8), (2.6, -2.8), (-2.8, 2.6), (2.6, 2.6)):
        mb.box(px, py, 0.0, px + 0.2, py + 0.2, 2.6, post, skip=("bottom",))
    mb.prism([(-3.2, 2.5), (-3.2, 2.6), (3.2, 2.9), (3.2, 2.8)], "X", -3.2, 3.2, tin)
    mb.box(-2.6, 0.8, 0.0, 2.6, 1.6, 1.0, counter, skip=("bottom",))
    mb.box(-2.7, 0.7, 1.0, 2.7, 1.7, 1.08, steel)
    mb.cylinder(-1.5, 1.2, 1.08, 0.25, 0.2, 0.35, 8, steel)
    mb.box(-1.8, -3.0, 0.4, 1.8, -2.5, 0.5, post)                   # bench
    mb.box(-1.6, -2.9, 0.0, -1.4, -2.6, 0.4, post)
    mb.box(1.4, -2.9, 0.0, 1.6, -2.6, 0.4, post)
    mb.box(-1.4, -3.0, 2.2, 1.4, -2.9, 2.75, board)
    rm.pixel_text(mb, "TEA", 0.0, -3.0, 2.3, 0.08, letters, depth=0.03)
    mb.box(-0.15, -0.15, 2.4, 0.15, 0.15, 2.5, light)
    mb.build(name)
    collide(name, [(-2.8, -2.8, 0.0, -2.6, -2.6, 2.6), (2.6, -2.8, 0.0, 2.8, -2.6, 2.6), (-2.8, 2.6, 0.0, -2.6, 2.8, 2.6),
                   (2.6, 2.6, 0.0, 2.8, 2.8, 2.6), (-2.6, 0.8, 0.0, 2.6, 1.6, 1.08), (-3.2, -3.2, 2.5, 3.2, 3.2, 2.9)])
    rm.export_glb("buildings", name)


def well() -> None:
    name = "prop_cs_well"
    rm.clear_scene()
    stone = rm.material("bh_rock", "#6f6a62", roughness=0.95)
    water = rm.material("fountain_water", "#2f6f8f", roughness=0.05, metallic=0.2)
    wood = rm.material("ot_door_wood", "#5a3a22", roughness=0.8)
    mb = rm.MeshBuilder()
    mb.cylinder(0.0, 0.0, 0.0, 1.2, 1.2, 0.8, 12, stone, caps=False)
    mb.cylinder(0.0, 0.0, 0.0, 0.95, 0.95, 0.5, 12, water)
    for px in (-1.0, 0.85):
        mb.box(px, -0.08, 0.8, px + 0.15, 0.08, 2.4, wood)
    mb.box(-1.0, -0.06, 2.3, 1.0, 0.06, 2.4, wood)
    mb.cylinder(0.0, 0.0, 2.0, 0.12, 0.12, 0.25, 8, wood)
    mb.build(name)
    col = rm.CollisionSet(name)
    col.frustum(0.0, 0.0, 0.0, 2.4, 2.4, 2.4, 2.4, 0.8)
    col.build()
    rm.export_glb("props", name)


def haystack() -> None:
    name = "prop_cs_haystack"
    rm.clear_scene()
    hay = rm.material("cs_hay", "#c9a450", roughness=0.95)
    hay_dark = rm.material("cs_hay_dark", "#a8843c", roughness=0.95)
    base = rm.material("ot_door_wood", "#5a3a22", roughness=0.8)
    mb = rm.MeshBuilder()
    mb.cylinder(0.0, 0.0, 0.0, 1.8, 1.8, 0.4, 10, base)
    mb.cylinder(0.0, 0.0, 0.4, 1.7, 1.9, 1.6, 10, hay)
    mb.cylinder(0.0, 0.0, 2.0, 1.9, 0.2, 1.8, 10, hay_dark)
    mb.build(name)
    col = rm.CollisionSet(name)
    col.frustum(0.0, 0.0, 0.0, 3.6, 3.6, 3.6, 3.6, 2.0)
    col.frustum(0.0, 0.0, 2.0, 3.6, 3.6, 0.4, 0.4, 1.8)
    col.build()
    rm.export_glb("props", name)


def paddy() -> None:
    """A 20 x 20 m paddy-field tile: wet earth, low earth bunds round the edge, eight rows of rice.
    Visual only (people and cars cross fields on the flat ground under it)."""
    name = "prop_cs_paddy"
    rm.clear_scene()
    water = rm.material("cs_paddy_water", "#6f7f4a", roughness=0.25)
    bund = rm.material("cs_paddy_bund", "#6e5a3c", roughness=0.95)
    rice = rm.material("cs_rice_green", "#7fae3c", roughness=0.9)
    mb = rm.MeshBuilder()
    s = 10.0
    mb.box(-s, -s, 0.0, s, s, 0.02, water, skip=("bottom",))
    for (x0, y0, x1, y1) in ((-s, -s, s, -s + 0.6), (-s, s - 0.6, s, s), (-s, -s + 0.6, -s + 0.6, s - 0.6), (s - 0.6, -s + 0.6, s, s - 0.6)):
        mb.box(x0, y0, 0.0, x1, y1, 0.18, bund, skip=("bottom",))
    for i in range(8):
        y = -s + 1.6 + i * 2.35
        mb.box(-s + 1.0, y, 0.0, s - 1.0, y + 1.3, 0.32, rice, skip=("bottom",))
    mb.build(name)
    rm.export_glb("props", name)


BUILDERS = {
    "bld_cs_hut": hut,
    "bld_cs_farmhouse": farmhouse,
    "bld_cs_teastall": teastall,
    "prop_cs_well": well,
    "prop_cs_haystack": haystack,
    "prop_cs_paddy": paddy,
}


def main() -> None:
    for name in (rm.script_args() or list(BUILDERS)):
        BUILDERS[name]()


main()
