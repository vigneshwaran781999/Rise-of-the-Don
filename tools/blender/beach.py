"""Beach District kit (M7) -> assets/models/buildings/, props/

Velanagar's seafront (GDD §2 district 2): resorts, seafood restaurants, pastel cottages, a pier
and a lighthouse, with umbrellas, fishing boats and lifeguard towers on the sand. Every model
has its pivot at the base centre and its front facing Blender -Y. Floors are 3 m apart (the
lit-window bands of shaders/palette_lit.gdshader). Material names with night glow: window_glass,
lamp_lens, neon_* (see scripts/world/kit_baker.gd).

  bld_bh_resort        44 x 22 m resort hotel, 6 floors, sea-view balconies, pool behind,
                       SEA BREEZE on the roof
  bld_bh_hotel         20 x 14 m small hotel, 4 floors, BEACH INN board
  bld_bh_seafood       12 x 12 m seafood restaurant: open dining room, verandah upstairs, SEAFOOD
  bld_bh_police        12 x 12 m police post, POLICE board
  bld_bh_shop_a/b      8 x 10 m beach shops with awnings
  bld_bh_cottage       8 x 10 m pastel cottage with a thatched porch
  bld_bh_lighthouse    lighthouse on a rock platform, 34 m, lantern glows at night
  bld_bh_pier          6 x 60 m wooden pier on piles (deck 1.1 m above the sand)
  prop_bh_umbrella     beach umbrella with two loungers
  prop_bh_boat         wooden fishing boat drawn up on the sand
  prop_bh_lifeguard    lifeguard tower
  prop_bh_kiosk        snack kiosk

Run:  "$BLENDER" --background --factory-startup --python tools/blender/beach.py [-- names...]
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rotd_mesh as rm  # noqa: E402

FH = 3.0


def collide(name: str, boxes: list) -> None:
    col = rm.CollisionSet(name)
    for b in boxes:
        col.box(*b)
    col.build()


def roof_parapet(mb, x0, y0, x1, y1, z, mat, h: float = 0.8) -> None:
    mb.box(x0, y0, z, x1, y1, z + 0.05, mat, skip=("bottom",))
    t = 0.2
    for (ax0, ay0, ax1, ay1) in ((x0, y0, x1, y0 + t), (x0, y1 - t, x1, y1),
                                 (x0, y0 + t, x0 + t, y1 - t), (x1 - t, y0 + t, x1, y1 - t)):
        mb.box(ax0, ay0, z, ax1, ay1, z + h, mat, skip=("bottom",))


def pitched_roof(mb, x0, y0, x1, y1, z, rise, tile) -> None:
    """Solid clay-tile roof with its ridge along X, overhanging 0.5 m front and back, 0.3 m at the ends."""
    ef, eb = y0 - 0.5, y1 + 0.5
    mb.prism([(ef, z - 0.1), ((ef + eb) / 2, z + rise), (eb, z - 0.1)], "X", x0 - 0.3, x1 + 0.3, tile)


def balconies(mb, x0, x1, plane, out, z0, floors, slab, rail, glass, bays: int) -> None:
    """Windows and a balcony slab with a railing on each floor of one face (out = -1 front, 1 back)."""
    for k in range(floors):
        zb = z0 + k * FH
        w = (x1 - x0) / bays
        for i in range(bays):
            u = x0 + w * (i + 0.5)
            if out < 0:
                mb.box(u - w * 0.32, plane - 0.04, zb + 0.3, u + w * 0.32, plane, zb + 2.6, glass, skip=("back",))
            else:
                mb.box(u - w * 0.32, plane, zb + 0.3, u + w * 0.32, plane + 0.04, zb + 2.6, glass, skip=("front",))
        ya, yb = (plane - 1.4, plane) if out < 0 else (plane, plane + 1.4)
        mb.box(x0 + 0.3, ya, zb, x1 - 0.3, yb, zb + 0.18, slab)
        ry = ya if out < 0 else yb - 0.06
        mb.box(x0 + 0.3, ry, zb + 0.18, x1 - 0.3, ry + 0.06, zb + 1.05, rail)


def resort() -> None:
    name = "bld_bh_resort"
    rm.clear_scene()
    wall = rm.material("bh_resort_white", "#f3f0e8", roughness=0.8)
    aqua = rm.material("bh_aqua_rail", "#3fb7b0", roughness=0.5)
    glass = rm.material("window_glass", "#2a3644", roughness=0.18, metallic=0.35)
    lobby = rm.material("neon_lobby", "#c9b48a", roughness=0.2, emission="#ffd9a0", emission_strength=0.5)
    board = rm.material("bh_sign_board", "#16323a", roughness=0.6)
    neon = rm.material("neon_aqua", "#2a8f8a", roughness=0.3, emission="#4dfff0", emission_strength=1.5)
    tile = rm.material("bh_pool_tile", "#e7f3f3", roughness=0.6)
    water = rm.material("bh_pool_water", "#2fb3d8", roughness=0.05, metallic=0.1)
    wood = rm.material("bh_deck_wood", "#9b6b43", roughness=0.8)
    mb = rm.MeshBuilder()
    x0, y0, x1, y1 = -22.0, -11.0, 22.0, 11.0
    floors = 6
    top = floors * FH
    mb.box(x0, y0, 0.0, x1, y1, top, wall, skip=("bottom",))
    # ground floor: glass lobby in the middle, canopy over the door
    mb.box(-8.0, y0 - 0.05, 0.0, 8.0, y0, 2.8, lobby, skip=("back",))
    mb.box(-9.0, y0 - 4.0, 3.1, 9.0, y0, 3.4, aqua)
    for px in (-8.5, 8.5):
        mb.box(px - 0.2, y0 - 3.8, 0.0, px + 0.2, y0 - 3.4, 3.1, wall, skip=("bottom",))
    balconies(mb, x0, x1, y0, -1, FH, floors - 1, wall, aqua, glass, 8)
    balconies(mb, x0, x1, y1, 1, FH, floors - 1, wall, aqua, glass, 8)
    for sx in (x0, x1):                                   # end stair towers
        mb.box(sx - 1.0, -3.0, 0.0, sx + 1.0, 3.0, top + 2.5, wall, skip=("bottom",))
    roof_parapet(mb, x0, y0, x1, y1, top, wall)
    for px in (-12.0, 12.0):
        mb.box(px - 0.15, -1.0, top, px + 0.15, -0.7, top + 5.0, aqua)
    mb.box(-14.0, -1.2, top + 1.6, 14.0, -1.0, top + 5.2, board)
    rm.pixel_text(mb, "SEA BREEZE", 0.0, -1.2, top + 2.1, 0.5, neon, depth=0.1)
    # pool and deck behind
    mb.box(-14.0, y1 + 2.0, 0.0, 14.0, y1 + 14.0, 0.12, wood, skip=("bottom",))
    mb.box(-10.0, y1 + 4.0, 0.0, 10.0, y1 + 12.0, 0.2, tile, skip=("bottom",))
    mb.box(-9.5, y1 + 4.5, 0.0, 9.5, y1 + 11.5, 0.21, water, skip=("bottom",))
    mb.build(name)
    collide(name, [(x0 - 1.0, y0, 0.0, x1 + 1.0, y1, top + 0.8)])
    rm.export_glb("buildings", name)


def hotel() -> None:
    name = "bld_bh_hotel"
    rm.clear_scene()
    wall = rm.material("bh_hotel_yellow", "#f2d27a", roughness=0.8)
    white = rm.material("bh_trim_white", "#f7f4ec", roughness=0.7)
    glass = rm.material("window_glass", "#2a3644", roughness=0.18, metallic=0.35)
    lobby = rm.material("neon_lobby", "#c9b48a", roughness=0.2, emission="#ffd9a0", emission_strength=0.5)
    board = rm.material("bh_sign_board", "#16323a", roughness=0.6)
    letters = rm.material("neon_warm", "#b07a2a", roughness=0.3, emission="#ffc46a", emission_strength=1.4)
    mb = rm.MeshBuilder()
    x0, y0, x1, y1 = -10.0, -7.0, 10.0, 7.0
    floors = 4
    top = floors * FH
    mb.box(x0, y0, 0.0, x1, y1, top, wall, skip=("bottom",))
    mb.box(-3.0, y0 - 0.05, 0.0, 3.0, y0, 2.7, lobby, skip=("back",))
    balconies(mb, x0, x1, y0, -1, FH, floors - 1, white, white, glass, 5)
    for k in range(1, floors):
        for i in range(5):
            u = x0 + 4.0 * (i + 0.5)
            mb.box(u - 1.0, y1, k * FH + 0.6, u + 1.0, y1 + 0.04, k * FH + 2.4, glass, skip=("front",))
    roof_parapet(mb, x0, y0, x1, y1, top, white)
    mb.box(-7.0, y0 - 0.2, 2.9, 7.0, y0, 3.8, board, skip=("back",))
    rm.pixel_text(mb, "BEACH INN", 0.0, y0 - 0.2, 3.03, 0.13, letters, depth=0.05)
    mb.build(name)
    collide(name, [(x0, y0, 0.0, x1, y1, top + 0.8)])
    rm.export_glb("buildings", name)


def seafood() -> None:
    """Seafood restaurant: the ground floor is an open dining room under a deep upper verandah,
    a tiled roof, SEAFOOD on a blue board with a fish."""
    name = "bld_bh_seafood"
    rm.clear_scene()
    wall = rm.material("bh_seafood_coral", "#e98b6d", roughness=0.85)
    white = rm.material("bh_trim_white", "#f7f4ec", roughness=0.7)
    dark = rm.material("shop_interior", "#17130f", roughness=0.95)
    warm = rm.material("neon_dining", "#5a3a22", roughness=0.6, emission="#ffcf8a", emission_strength=0.35)
    wood = rm.material("bh_deck_wood", "#9b6b43", roughness=0.8)
    tile = rm.material("clay_tile", "#b5532f", roughness=0.85)
    board = rm.material("bh_board_blue", "#1d4f8c", roughness=0.6)
    letters = rm.material("sign_letters", "#f4f1e8", roughness=0.6)
    fish = rm.material("bh_fish_orange", "#f0a030", roughness=0.6)
    glass = rm.material("window_glass", "#2a3644", roughness=0.18, metallic=0.35)
    mb = rm.MeshBuilder()
    x0, y0, x1, y1 = -6.0, -6.0, 6.0, 6.0
    top = 2 * FH + 0.6
    # ground floor: a back room, an open dining area under the verandah
    mb.box(x0, 0.0, 0.0, x1, y1, FH, wall, skip=("bottom",))
    mb.box(x0 + 0.3, -0.05, 0.0, x1 - 0.3, 0.0, 2.6, warm, skip=("back",))
    mb.box(x0, y0, 0.0, x1, 0.0, 0.1, wood, skip=("bottom",))
    for px in (x0, -2.1, 1.9, x1 - 0.3):
        mb.box(px, y0, 0.1, px + 0.3, y0 + 0.3, FH, white, skip=("bottom",))
    for tx in (-3.5, 0.0, 3.5):                             # tables
        mb.box(tx - 0.6, -3.4, 0.7, tx + 0.6, -2.4, 0.78, wood)
        mb.box(tx - 0.06, -2.96, 0.1, tx + 0.06, -2.84, 0.7, wood)
    # upper floor with a verandah railing
    mb.box(x0, y0, FH, x1, y1, FH + 0.25, white)
    mb.box(x0, -1.5, FH + 0.25, x1, y1, top, wall, skip=("bottom",))
    for i in range(3):
        u = x0 + 4.0 * (i + 0.5)
        mb.box(u - 0.8, -1.54, FH + 0.9, u + 0.8, -1.5, FH + 2.5, glass, skip=("back",))
    mb.box(x0 + 0.1, y0, FH + 0.25, x1 - 0.1, y0 + 0.1, FH + 1.2, wood)
    pitched_roof(mb, x0, y0, x1, y1, top, 2.2, tile)
    mb.box(-4.5, y0 - 0.15, FH - 0.95, 4.5, y0, FH - 0.1, board, skip=("back",))
    rm.pixel_text(mb, "SEAFOOD", 0.6, y0 - 0.15, FH - 0.85, 0.11, letters, depth=0.04)
    mb.box(-4.2, y0 - 0.2, FH - 0.7, -3.4, y0 - 0.15, FH - 0.35, fish, skip=("back",))
    mb.box(-3.4, y0 - 0.2, FH - 0.62, -3.1, y0 - 0.15, FH - 0.43, fish, skip=("back",))
    mb.build(name)
    collide(name, [(x0, 0.0, 0.0, x1, y1, top + 2.2), (x0, y0, 0.0, x0 + 0.3, y0 + 0.3, FH), (x1 - 0.3, y0, 0.0, x1, y0 + 0.3, FH),
                   (x0, y0, FH, x1, 0.0, top)])
    rm.export_glb("buildings", name)


def police() -> None:
    name = "bld_bh_police"
    rm.clear_scene()
    wall = rm.material("bh_police_white", "#eceae4", roughness=0.75)
    blue = rm.material("police_blue", "#1f4fa0", roughness=0.6)
    glass = rm.material("window_glass", "#2a3644", roughness=0.18, metallic=0.35)
    door = rm.material("neon_lobby", "#c9b48a", roughness=0.2, emission="#ffd9a0", emission_strength=0.5)
    letters = rm.material("sign_letters", "#f4f1e8", roughness=0.6)
    mb = rm.MeshBuilder()
    x0, y0, x1, y1 = -6.0, -6.0, 6.0, 6.0
    top = 2 * FH + 0.4
    mb.box(x0, y0, 0.0, x1, y1, top, wall, skip=("bottom",))
    mb.box(-1.2, y0 - 0.05, 0.0, 1.2, y0, 2.6, door, skip=("back",))
    mb.box(-2.0, y0 - 1.6, 2.8, 2.0, y0, 3.0, blue)
    for k in range(2):
        for u in (-4.0, 4.0) if k == 0 else (-4.0, 0.0, 4.0):
            mb.box(u - 0.8, y0 - 0.04, k * FH + 0.9, u + 0.8, y0, k * FH + 2.3, glass, skip=("back",))
    mb.box(x0 - 0.05, y0 - 0.05, FH - 0.2, x1 + 0.05, y1 + 0.05, FH + 0.1, blue, skip=("bottom",))
    roof_parapet(mb, x0, y0, x1, y1, top, blue)
    mb.box(x0 + 0.8, y0 - 0.15, top + 0.8, x1 - 0.8, y0, top + 2.6, blue)
    rm.pixel_text(mb, "POLICE", 0.0, y0 - 0.15, top + 1.1, 0.22, letters)
    mb.build(name)
    collide(name, [(x0, y0, 0.0, x1, y1, top + 2.6)])
    rm.export_glb("buildings", name)


def shop(name: str, paint: str, awning: str, floors: int) -> None:
    rm.clear_scene()
    wall = rm.material(name + "_wall", paint, roughness=0.85)
    white = rm.material("bh_trim_white", "#f7f4ec", roughness=0.7)
    dark = rm.material("neon_shopfront", "#2b3b4a", roughness=0.2, emission="#ffe8c8", emission_strength=0.12)
    aw = rm.material(name + "_awning", awning, roughness=0.8, double_sided=True)
    glass = rm.material("window_glass", "#2a3644", roughness=0.18, metallic=0.35)
    mb = rm.MeshBuilder()
    x0, y0, x1, y1 = -4.0, -5.0, 4.0, 5.0
    top = floors * FH + 0.4
    mb.box(x0, y0, 0.0, x1, y1, top, wall, skip=("bottom",))
    mb.box(x0 + 0.4, y0 - 0.05, 0.0, x1 - 0.4, y0, 2.6, dark, skip=("back",))
    for i in range(6):                                        # striped awning
        u0 = x0 + 0.1 + i * (x1 - x0 - 0.2) / 6
        u1 = u0 + (x1 - x0 - 0.2) / 6
        m = aw if i % 2 == 0 else white
        mb.face([(u0, y0, 3.0), (u1, y0, 3.0), (u1, y0 - 1.6, 2.55), (u0, y0 - 1.6, 2.55)], m, outward=(0, -0.3, 1))
        mb.face([(u0, y0, 3.0), (u1, y0, 3.0), (u1, y0 - 1.6, 2.55), (u0, y0 - 1.6, 2.55)], m, outward=(0, 0.3, -1))
    for k in range(1, floors):
        for u in (-2.0, 2.0):
            mb.box(u - 0.7, y0 - 0.04, k * FH + 0.8, u + 0.7, y0, k * FH + 2.3, glass, skip=("back",))
    roof_parapet(mb, x0, y0, x1, y1, top, white, 0.6)
    mb.build(name)
    collide(name, [(x0, y0, 0.0, x1, y1, top + 0.6)])
    rm.export_glb("buildings", name)


def cottage() -> None:
    """Pastel cottage: one storey, clay-tile roof, a thatched porch on two posts."""
    name = "bld_bh_cottage"
    rm.clear_scene()
    wall = rm.material("bh_cottage_blue", "#9fd3e0", roughness=0.85)
    white = rm.material("bh_trim_white", "#f7f4ec", roughness=0.7)
    tile = rm.material("clay_tile", "#b5532f", roughness=0.85)
    thatch = rm.material("bh_thatch", "#b38a4a", roughness=0.95)
    wood = rm.material("ot_door_wood", "#5a3a22", roughness=0.8)
    glass = rm.material("window_glass", "#2a3644", roughness=0.18, metallic=0.35)
    mb = rm.MeshBuilder()
    x0, y0, x1, y1 = -4.0, -3.0, 4.0, 5.0
    h = 3.2
    mb.box(x0, y0, 0.0, x1, y1, h, wall, skip=("bottom",))
    mb.box(-0.5, y0 - 0.05, 0.0, 0.5, y0, 2.3, wood, skip=("back",))
    for u in (-2.6, 2.6):
        mb.box(u - 0.55, y0 - 0.04, 1.0, u + 0.55, y0, 2.1, glass, skip=("back",))
    pitched_roof(mb, x0, y0, x1, y1, h, 1.8, tile)
    # porch: floor, two posts and a sloping thatch
    mb.box(x0 + 0.5, -5.0, 0.0, x1 - 0.5, y0, 0.15, white, skip=("bottom",))
    for px in (x0 + 0.7, x1 - 0.9):
        mb.box(px, -4.9, 0.15, px + 0.2, -4.7, 2.5, wood, skip=("bottom",))
    mb.face([(x0 + 0.3, -5.2, 2.45), (x1 - 0.3, -5.2, 2.45), (x1 - 0.3, y0, 3.0), (x0 + 0.3, y0, 3.0)], thatch, outward=(0, -0.3, 1))
    mb.face([(x0 + 0.3, -5.2, 2.4), (x1 - 0.3, -5.2, 2.4), (x1 - 0.3, y0, 2.95), (x0 + 0.3, y0, 2.95)], thatch, outward=(0, 0.3, -1))
    mb.build(name)
    collide(name, [(x0, y0, 0.0, x1, y1, h + 1.8), (x0 + 0.7, -4.9, 0.0, x0 + 0.9, -4.7, 2.5), (x1 - 0.9, -4.9, 0.0, x1 - 0.7, -4.7, 2.5)])
    rm.export_glb("buildings", name)


def lighthouse() -> None:
    """Lighthouse on a rock platform: a tapering tower in red and white bands, a gallery, the
    lantern (lamp_lens: it glows at night) and a dome. The beam is drawn by the city builder."""
    name = "bld_bh_lighthouse"
    rm.clear_scene()
    rock = rm.material("bh_rock", "#6f6a62", roughness=0.95)
    white = rm.material("bh_trim_white", "#f7f4ec", roughness=0.7)
    red = rm.material("bh_light_red", "#c23a2b", roughness=0.7)
    iron = rm.material("bh_iron", "#2b2d30", roughness=0.5, metallic=0.6)
    lamp = rm.material("lamp_lens", "#f6e6b0", roughness=0.2, emission="#fff1c0", emission_strength=3.0)
    mb = rm.MeshBuilder()
    mb.cylinder(0.0, 0.0, 0.0, 6.0, 5.2, 1.6, 10, rock)
    bands = 6
    tower_h = 26.0
    for i in range(bands):
        z0 = 1.6 + tower_h * i / bands
        z1 = 1.6 + tower_h * (i + 1) / bands
        r0 = 3.0 - 1.1 * i / bands
        r1 = 3.0 - 1.1 * (i + 1) / bands
        mb.cylinder(0.0, 0.0, z0, r0, r1, z1 - z0, 14, red if i % 2 == 0 else white, caps=(i == bands - 1))
    zt = 1.6 + tower_h
    mb.cylinder(0.0, 0.0, zt, 2.6, 2.6, 0.3, 14, iron)            # gallery
    for i in range(14):
        a = 2.0 * math.pi * i / 14
        mb.box(2.45 * math.cos(a) - 0.04, 2.45 * math.sin(a) - 0.04, zt + 0.3, 2.45 * math.cos(a) + 0.04,
               2.45 * math.sin(a) + 0.04, zt + 1.3, iron)
    mb.cylinder(0.0, 0.0, zt + 0.3, 1.4, 1.4, 2.6, 12, lamp)
    mb.cylinder(0.0, 0.0, zt + 2.9, 1.6, 0.2, 1.8, 12, red)
    mb.cylinder(0.0, 0.0, zt + 4.7, 0.15, 0.05, 1.0, 6, iron)
    mb.build(name)
    col = rm.CollisionSet(name)
    pts = [(5.6 * math.cos(2 * math.pi * i / 10), 5.6 * math.sin(2 * math.pi * i / 10), z) for i in range(10) for z in (0.0, 1.6)]
    col.hull(pts)
    col.frustum(0.0, 0.0, 1.6, 6.0, 6.0, 3.8, 3.8, tower_h + 3.0)
    col.build()
    rm.export_glb("buildings", name)


def pier() -> None:
    """Wooden pier, 6 m wide and 60 m long along Blender +Y (from the sand out to sea), its deck
    1.1 m up on piles, a ramp up from the sand at the near end, railings, lamp posts."""
    name = "bld_bh_pier"
    rm.clear_scene()
    deck = rm.material("bh_deck_wood", "#9b6b43", roughness=0.8)
    pile = rm.material("bh_pile_dark", "#4a3a2c", roughness=0.9)
    rail = rm.material("bh_trim_white", "#f7f4ec", roughness=0.7)
    iron = rm.material("bh_iron", "#2b2d30", roughness=0.5, metallic=0.6)
    lamp = rm.material("lamp_lens", "#f6e6b0", roughness=0.2, emission="#fff1c0", emission_strength=3.0)
    mb = rm.MeshBuilder()
    w = 3.0
    h = 1.1
    y_start, ramp_end, y_end = -30.0, -24.0, 30.0
    mb.face([(-w, y_start, 0.0), (w, y_start, 0.0), (w, ramp_end, h), (-w, ramp_end, h)], deck, outward=(0, -0.2, 1))
    mb.box(-w, ramp_end, h - 0.25, w, y_end, h, deck)
    y = ramp_end + 2.0
    while y < y_end:
        for x in (-w + 0.3, w - 0.3):
            mb.box(x - 0.18, y - 0.18, -0.6, x + 0.18, y + 0.18, h - 0.25, pile, skip=("bottom",))
        y += 4.0
    for x in (-w, w - 0.1):
        mb.box(x, ramp_end, h, x + 0.1, y_end, h + 1.0, rail, skip=("bottom",))
    mb.box(-w, y_end - 0.1, h, w, y_end, h + 1.0, rail, skip=("bottom",))
    for y in (-12.0, 8.0, 28.0):
        mb.box(w - 0.3, y - 0.08, h, w - 0.14, y + 0.08, h + 3.6, iron, skip=("bottom",))
        mb.box(w - 0.5, y - 0.22, h + 3.4, w + 0.06, y + 0.22, h + 3.7, lamp)
    mb.build(name)
    col = rm.CollisionSet(name)
    col.hull([(-w, y_start, -0.05), (w, y_start, -0.05), (-w, ramp_end, -0.05), (w, ramp_end, -0.05), (-w, ramp_end, h), (w, ramp_end, h)])
    col.box(-w, ramp_end, -0.6, w, y_end, h)
    col.box(-w, ramp_end, h, -w + 0.1, y_end, h + 1.0)
    col.box(w - 0.1, ramp_end, h, w, y_end, h + 1.0)
    col.box(-w, y_end - 0.1, h, w, y_end, h + 1.0)
    col.build()
    rm.export_glb("buildings", name)


def umbrella() -> None:
    name = "prop_bh_umbrella"
    rm.clear_scene()
    pole = rm.material("bh_trim_white", "#f7f4ec", roughness=0.7)
    a = rm.material("bh_umbrella_red", "#e24a3b", roughness=0.8, double_sided=True)
    b = rm.material("bh_umbrella_white", "#f4efe2", roughness=0.8, double_sided=True)
    frame = rm.material("bh_lounger_frame", "#d8d2c4", roughness=0.6)
    cloth = rm.material("bh_lounger_blue", "#2f7db8", roughness=0.85)
    mb = rm.MeshBuilder()
    mb.cylinder(0.0, 0.0, 0.0, 0.04, 0.04, 2.4, 6, pole)
    n = 8
    for i in range(n):
        a0 = 2 * math.pi * i / n
        a1 = 2 * math.pi * (i + 1) / n
        mb.face([(0.0, 0.0, 2.55), (1.4 * math.cos(a0), 1.4 * math.sin(a0), 2.05), (1.4 * math.cos(a1), 1.4 * math.sin(a1), 2.05)],
                a if i % 2 == 0 else b, outward=(0, 0, 1))
    for lx in (-1.0, 1.0):                                     # two loungers facing the sea (-Y)
        mb.box(lx - 0.33, -1.0, 0.25, lx + 0.33, 0.9, 0.32, frame)
        mb.box(lx - 0.3, -0.98, 0.32, lx + 0.3, 0.3, 0.36, cloth)
        mb.face([(lx - 0.3, 0.3, 0.36), (lx + 0.3, 0.3, 0.36), (lx + 0.3, 0.95, 0.85), (lx - 0.3, 0.95, 0.85)], cloth, outward=(0, -1, 1))
        for (fx, fy) in ((lx - 0.28, -0.9), (lx + 0.22, -0.9), (lx - 0.28, 0.8), (lx + 0.22, 0.8)):
            mb.box(fx, fy, 0.0, fx + 0.06, fy + 0.06, 0.25, frame, skip=("bottom",))
    mb.build(name)
    collide(name, [(-0.08, -0.08, 0.0, 0.08, 0.08, 2.4)])
    rm.export_glb("props", name)


def boat() -> None:
    """Wooden fishing boat drawn up on the sand, bow towards Blender -Y (the sea)."""
    name = "prop_bh_boat"
    rm.clear_scene()
    hull = rm.material("bh_boat_blue", "#2f6fb0", roughness=0.7)
    trim = rm.material("bh_boat_red", "#c23a2b", roughness=0.7)
    inside = rm.material("bh_deck_wood", "#9b6b43", roughness=0.8)
    mb = rm.MeshBuilder()
    # hull: a long tapered shape, keel on the sand
    pts_top = [(-0.8, -2.6), (0.8, -2.6), (0.85, 2.2), (0.0, 3.6), (-0.85, 2.2)]
    pts_bot = [(-0.35, -2.3), (0.35, -2.3), (0.4, 2.0), (0.0, 3.2), (-0.4, 2.0)]
    top_z, bot_z = 0.9, 0.0
    n = len(pts_top)
    for i in range(n):
        j = (i + 1) % n
        mb.face([(pts_bot[i][0], -pts_bot[i][1], bot_z), (pts_bot[j][0], -pts_bot[j][1], bot_z),
                 (pts_top[j][0], -pts_top[j][1], top_z), (pts_top[i][0], -pts_top[i][1], top_z)], hull, inside=(0, 0, 0.45))
    mb.face([(p[0], -p[1], top_z - 0.15) for p in pts_top], inside, outward=(0, 0, 1))
    for i in range(n):
        j = (i + 1) % n
        mb.face([(pts_top[i][0], -pts_top[i][1], top_z - 0.12), (pts_top[j][0], -pts_top[j][1], top_z - 0.12),
                 (pts_top[j][0], -pts_top[j][1], top_z + 0.05), (pts_top[i][0], -pts_top[i][1], top_z + 0.05)], trim, inside=(0, 0, 0.5))
    mb.box(-0.7, -0.6, top_z - 0.15, 0.7, -0.4, top_z + 0.05, inside)
    mb.build(name)
    col = rm.CollisionSet(name)
    col.hull([(p[0], -p[1], top_z) for p in pts_top] + [(p[0], -p[1], bot_z) for p in pts_bot])
    col.build()
    rm.export_glb("props", name)


def lifeguard() -> None:
    name = "prop_bh_lifeguard"
    rm.clear_scene()
    wood = rm.material("bh_lifeguard_white", "#f4efe2", roughness=0.8)
    red = rm.material("bh_light_red", "#c23a2b", roughness=0.7)
    yellow = rm.material("bh_lifeguard_yellow", "#f2c230", roughness=0.7)
    mb = rm.MeshBuilder()
    for (lx, ly) in ((-0.9, -0.9), (0.75, -0.9), (-0.9, 0.75), (0.75, 0.75)):
        mb.box(lx, ly, 0.0, lx + 0.15, ly + 0.15, 2.2, wood, skip=("bottom",))
    mb.box(-1.1, -1.1, 2.2, 1.1, 1.1, 2.35, wood)
    mb.box(-1.0, -0.2, 2.35, 1.0, 1.0, 4.0, red, skip=("bottom",))
    mb.box(-1.0, -1.0, 2.35, 1.0, -0.94, 3.1, yellow)
    mb.box(-1.25, -1.25, 4.0, 1.25, 1.25, 4.2, yellow)
    for k in range(7):                                           # ladder at the front
        z = 0.3 * (k + 1)
        mb.box(-0.4, -1.6 + k * 0.08, z, 0.4, -1.5 + k * 0.08, z + 0.06, wood)
    mb.build(name)
    collide(name, [(-1.1, -1.1, 0.0, 1.1, 1.1, 4.2)])
    rm.export_glb("props", name)


def kiosk() -> None:
    name = "prop_bh_kiosk"
    rm.clear_scene()
    body = rm.material("bh_kiosk_teal", "#2aa198", roughness=0.8)
    white = rm.material("bh_trim_white", "#f7f4ec", roughness=0.7)
    counter = rm.material("bh_deck_wood", "#9b6b43", roughness=0.8)
    red = rm.material("bh_umbrella_red", "#e24a3b", roughness=0.8, double_sided=True)
    light = rm.material("neon_dining", "#5a3a22", roughness=0.6, emission="#ffcf8a", emission_strength=0.35)
    mb = rm.MeshBuilder()
    mb.box(-1.4, -1.2, 0.0, 1.4, 1.2, 1.0, body, skip=("bottom",))
    mb.box(-1.5, -1.4, 1.0, 1.5, 1.2, 1.1, counter)
    mb.box(-1.3, 0.6, 1.1, 1.3, 1.2, 2.2, light)
    for (px, py) in ((-1.4, -1.3), (1.3, -1.3), (-1.4, 1.1), (1.3, 1.1)):
        mb.box(px, py, 1.1, px + 0.1, py + 0.1, 2.4, white, skip=("bottom",))
    mb.frustum(0.0, 0.0, 2.4, 3.6, 3.2, 0.3, 0.3, 0.9, red, bottom=True)
    mb.build(name)
    collide(name, [(-1.5, -1.4, 0.0, 1.5, 1.2, 2.4)])
    rm.export_glb("props", name)


BUILDERS = {
    "bld_bh_resort": resort,
    "bld_bh_hotel": hotel,
    "bld_bh_seafood": seafood,
    "bld_bh_police": police,
    "bld_bh_shop_a": lambda: shop("bld_bh_shop_a", "#3fb7b0", "#e24a3b", 1),
    "bld_bh_shop_b": lambda: shop("bld_bh_shop_b", "#f29b74", "#2f7db8", 2),
    "bld_bh_cottage": cottage,
    "bld_bh_lighthouse": lighthouse,
    "bld_bh_pier": pier,
    "prop_bh_umbrella": umbrella,
    "prop_bh_boat": boat,
    "prop_bh_lifeguard": lifeguard,
    "prop_bh_kiosk": kiosk,
}


def main() -> None:
    for name in (rm.script_args() or list(BUILDERS)):
        BUILDERS[name]()


main()
