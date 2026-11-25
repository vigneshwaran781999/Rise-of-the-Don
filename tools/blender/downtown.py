"""Downtown kit (M7) -> assets/models/buildings/, props/

Velanagar's business district: glass and steel, neon at night (GDD §2 district 1). Every model
has its pivot at the base centre and its front facing Blender -Y (the street). Floors are 3 m
apart and start on multiples of 3 m, so the lit-window bands of shaders/palette_lit.gdshader
light whole floors at night. Material names the district builder treats specially (see
scripts/world/kit_baker.gd): office_glass* (office windows, lit by floor at night),
window_glass (home windows, warm), neon_* (signs and lobby glass: glow at night only).

  bld_dt_tower_a       20 x 20 m glass office tower, 78 m, teal glass and white fins, mast light
  bld_dt_tower_b       24 x 20 m stepped tower, 120 m with its spire: the skyline landmark
  bld_dt_tower_c       18 x 18 m residential tower, 60 m, balconies, water tank
  bld_dt_office_a      16 x 16 m mid-rise office, 24 m, ribbon windows
  bld_dt_office_b      12 x 14 m terracotta office, 15 m, shop and awning at street level
  bld_dt_retail_a/b    12 x 14 m two-storey shops with neon signs (CAFE, SALON)
  bld_dt_hotel         24 x 18 m hotel, 45 m, balconies, HOTEL in neon on the roof
  bld_dt_mall          44 x 48 m shopping mall, 18 m, glass atrium, VELA MALL in neon
  bld_dt_police        16 x 16 m police headquarters, 15 m, POLICE on the roof
  prop_dt_fountain     6 m round fountain for the plaza

Run:  "$BLENDER" --background --factory-startup --python tools/blender/downtown.py [-- names...]
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rotd_mesh as rm  # noqa: E402

FH = 3.0   # floor height (= the lit-window band height)


def collide(name: str, boxes: list) -> None:
    col = rm.CollisionSet(name)
    for b in boxes:
        col.box(*b)
    col.build()


def curtain_wall(mb: rm.MeshBuilder, x0, y0, x1, y1, z0, z1, glass, spandrel, fin, fin_step: float,
                 fin_depth: float = 0.3) -> None:
    """Glass floors from z0 to z1 (multiples of FH): an opaque spandrel band at each floor slab, a
    band of glass above it, and vertical fins every fin_step metres on all four sides."""
    floors = max(1, round((z1 - z0) / FH))
    for k in range(floors):
        zb = z0 + k * FH
        mb.box(x0 - 0.06, y0 - 0.06, zb, x1 + 0.06, y1 + 0.06, zb + 0.8, spandrel, skip=("top", "bottom"))
        mb.box(x0, y0, zb + 0.8, x1, y1, zb + FH - 0.02, glass, skip=("top", "bottom"))
    for (a0, a1, fixed, axis, outward) in ((x0, x1, y0, "x", -1), (x0, x1, y1, "x", 1),
                                           (y0, y1, x0, "y", -1), (y0, y1, x1, "y", 1)):
        n = max(1, round((a1 - a0) / fin_step))
        for i in range(n + 1):
            a = a0 + (a1 - a0) * i / n
            if axis == "x":
                ya, yb = (fixed - fin_depth, fixed) if outward < 0 else (fixed, fixed + fin_depth)
                mb.box(a - 0.09, ya, z0, a + 0.09, yb, z1, fin, skip=("bottom",))
            else:
                xa, xb = (fixed - fin_depth, fixed) if outward < 0 else (fixed, fixed + fin_depth)
                mb.box(xa, a - 0.09, z0, xb, a + 0.09, z1, fin, skip=("bottom",))


def roof_slab(mb, x0, y0, x1, y1, z, mat, parapet: float = 0.9) -> None:
    mb.box(x0 - 0.1, y0 - 0.1, z, x1 + 0.1, y1 + 0.1, z + 0.3, mat, skip=("bottom",))
    t = 0.25
    for (ax0, ay0, ax1, ay1) in ((x0, y0, x1, y0 + t), (x0, y1 - t, x1, y1),
                                 (x0, y0 + t, x0 + t, y1 - t), (x1 - t, y0 + t, x1, y1 - t)):
        mb.box(ax0, ay0, z + 0.3, ax1, ay1, z + 0.3 + parapet, mat, skip=("bottom",))


def lobby(mb, x0, y0, x1, y1, height, frame, glow, canopy) -> None:
    """Street-level lobby: a glass box set back 1 m behind corner columns, glowing at night,
    with a canopy over the front door."""
    mb.box(x0 + 1.0, y0 + 1.0, 0.0, x1 - 1.0, y1 - 1.0, height, glow, skip=("bottom",))
    for cx, cy in ((x0, y0), (x1 - 0.8, y0), (x0, y1 - 0.8), (x1 - 0.8, y1 - 0.8)):
        mb.box(cx, cy, 0.0, cx + 0.8, cy + 0.8, height, frame, skip=("bottom",))
    for i in range(1, 4):
        cx = x0 + (x1 - x0) * i / 4 - 0.3
        mb.box(cx, y0, 0.0, cx + 0.6, y0 + 0.6, height, frame, skip=("bottom",))
    mb.box(-4.0, y0 - 2.5, height - 1.6, 4.0, y0 + 1.0, height - 1.3, canopy)


def mast(mb, x, y, z, height, steel, light) -> None:
    mb.cylinder(x, y, z, 0.25, 0.12, height, 6, steel)
    mb.box(x - 0.3, y - 0.3, z + height, x + 0.3, y + 0.3, z + height + 0.5, light)


def tower_a() -> None:
    name = "bld_dt_tower_a"
    rm.clear_scene()
    glass = rm.material("office_glass_teal", "#3f7f8e", roughness=0.12, metallic=0.6)
    span = rm.material("dt_spandrel_white", "#dfe3e6", roughness=0.5)
    fin = rm.material("dt_fin_white", "#f2f4f5", roughness=0.4, metallic=0.2)
    frame = rm.material("dt_frame_grey", "#4a4f57", roughness=0.4, metallic=0.5)
    lobby_glow = rm.material("neon_lobby", "#c9b48a", roughness=0.2, emission="#ffd9a0", emission_strength=0.5)
    roof = rm.material("dt_roof_grey", "#8d9096", roughness=0.9)
    red = rm.material("neon_red", "#7a1a1a", roughness=0.4, emission="#ff2a1a", emission_strength=4.0)
    mb = rm.MeshBuilder()
    x0, y0, x1, y1 = -10.0, -10.0, 10.0, 10.0
    lobby(mb, x0, y0, x1, y1, 6.0, frame, lobby_glow, frame)
    mb.box(x0, y0, 5.6, x1, y1, 6.0, frame)
    top = 78.0
    curtain_wall(mb, x0, y0, x1, y1, 6.0, top, glass, span, fin, 2.5)
    roof_slab(mb, x0, y0, x1, y1, top, roof)
    mb.box_c(0.0, 1.0, top + 0.3, 9.0, 8.0, 3.6, roof)
    mast(mb, 0.0, 1.0, top + 3.9, 12.0, frame, red)
    mb.build(name)
    collide(name, [(x0, y0, 0.0, x1, y1, top + 1.2), (-4.5, -3.0, top, 4.5, 5.0, top + 3.9)])
    rm.export_glb("buildings", name)


def tower_b() -> None:
    name = "bld_dt_tower_b"
    rm.clear_scene()
    glass = rm.material("office_glass_dark", "#263241", roughness=0.1, metallic=0.7)
    span = rm.material("dt_spandrel_bronze", "#6b5a3e", roughness=0.45, metallic=0.4)
    gold = rm.material("dt_fin_gold", "#c2a061", roughness=0.35, metallic=0.8)
    granite = rm.material("dt_granite", "#5c5652", roughness=0.6)
    lobby_glow = rm.material("neon_lobby", "#c9b48a", roughness=0.2, emission="#ffd9a0", emission_strength=0.5)
    red = rm.material("neon_red", "#7a1a1a", roughness=0.4, emission="#ff2a1a", emission_strength=4.0)
    crown = rm.material("neon_crown", "#d9c48f", roughness=0.3, metallic=0.6, emission="#ffe2a8", emission_strength=0.8)
    mb = rm.MeshBuilder()
    lobby(mb, -12.0, -10.0, 12.0, 10.0, 6.0, granite, lobby_glow, gold)
    mb.box(-12.0, -10.0, 5.6, 12.0, 10.0, 6.0, granite)
    # podium: two floors of granite and glass
    curtain_wall(mb, -12.0, -10.0, 12.0, 10.0, 6.0, 12.0, glass, granite, granite, 4.0, 0.4)
    mb.box(-12.2, -10.2, 12.0, 12.2, 10.2, 12.6, granite)
    curtain_wall(mb, -10.0, -8.0, 10.0, 8.0, 12.0, 66.0, glass, span, gold, 2.5)
    mb.box(-10.2, -8.2, 66.0, 10.2, 8.2, 66.6, gold)
    curtain_wall(mb, -7.0, -6.0, 7.0, 6.0, 66.0, 102.0, glass, span, gold, 2.3)
    mb.box(-7.3, -6.3, 102.0, 7.3, 6.3, 103.0, gold)
    # crown: a lit band, then a tapering spire with the aircraft light
    mb.box(-6.0, -5.0, 103.0, 6.0, 5.0, 105.0, crown, skip=("bottom",))
    mb.frustum(0.0, 0.0, 105.0, 8.0, 7.0, 0.6, 0.6, 14.0, gold)
    mast(mb, 0.0, 0.0, 119.0, 3.0, gold, red)
    mb.build(name)
    collide(name, [(-12.0, -10.0, 0.0, 12.0, 10.0, 12.6), (-10.0, -8.0, 12.0, 10.0, 8.0, 66.6),
                   (-7.0, -6.0, 66.0, 7.0, 6.0, 105.0)])
    rm.export_glb("buildings", name)


def tower_c() -> None:
    """Residential tower: concrete, a strip of windows on every floor, balconies front and back."""
    name = "bld_dt_tower_c"
    rm.clear_scene()
    wall = rm.material("dt_concrete_warm", "#d3c8b6", roughness=0.85)
    band = rm.material("dt_band_terracotta", "#b0664a", roughness=0.8)
    glass = rm.material("window_glass", "#2a3644", roughness=0.18, metallic=0.35)
    rail = rm.material("window_bars", "#2c2e33", roughness=0.5, metallic=0.5)
    lobby_glow = rm.material("neon_lobby", "#c9b48a", roughness=0.2, emission="#ffd9a0", emission_strength=0.5)
    tank = rm.material("water_tank", "#1d1e20", roughness=0.55)
    mb = rm.MeshBuilder()
    x0, y0, x1, y1 = -9.0, -9.0, 9.0, 9.0
    lobby(mb, x0, y0, x1, y1, 6.0, wall, lobby_glow, band)
    mb.box(x0, y0, 5.6, x1, y1, 6.0, wall)
    floors = 18
    top = 6.0 + floors * FH
    mb.box(x0, y0, 6.0, x1, y1, top, wall, skip=("bottom",))
    for k in range(floors):
        zb = 6.0 + k * FH
        for side, plane in (("front", y0), ("back", y1)):
            out = -1 if side == "front" else 1
            for (wx0, wx1) in ((x0 + 1.0, -1.0), (1.0, x1 - 1.0)):
                if side == "front":
                    mb.box(wx0, plane - 0.04, zb + 0.9, wx1, plane, zb + 2.6, glass, skip=("back",))
                else:
                    mb.box(wx0, plane, zb + 0.9, wx1, plane + 0.04, zb + 2.6, glass, skip=("front",))
            # balcony slab and railing
            ya, yb = (plane - 1.3, plane) if out < 0 else (plane, plane + 1.3)
            mb.box(x0 + 0.6, ya, zb, x1 - 0.6, yb, zb + 0.18, wall)
            ry = ya if out < 0 else yb - 0.06
            mb.box(x0 + 0.6, ry, zb + 1.0, x1 - 0.6, ry + 0.06, zb + 1.08, rail)
        for side_x, out in ((x0, -1), (x1, 1)):
            xa, xb = (side_x - 0.04, side_x) if out < 0 else (side_x, side_x + 0.04)
            mb.box(xa, -2.5, zb + 0.9, xb, 2.5, zb + 2.6, glass, skip=("right",) if out < 0 else ("left",))
        if k % 6 == 5:
            mb.box(x0 - 0.08, y0 - 0.08, zb + FH - 0.5, x1 + 0.08, y1 + 0.08, zb + FH, band, skip=("bottom",))
    roof_slab(mb, x0, y0, x1, y1, top, wall)
    mb.box_c(2.0, 2.0, top + 0.3, 5.0, 5.0, 3.0, wall)
    mb.cylinder(-4.5, 4.5, top + 0.3, 1.2, 1.2, 2.4, 10, tank)
    mb.build(name)
    collide(name, [(x0, y0, 0.0, x1, y1, top + 1.2)])
    rm.export_glb("buildings", name)


def office_a() -> None:
    """Mid-rise office: concrete with a ribbon of blue glass on every floor, glass shopfront."""
    name = "bld_dt_office_a"
    rm.clear_scene()
    wall = rm.material("dt_concrete_cool", "#b9bec4", roughness=0.8)
    glass = rm.material("office_glass_blue", "#35597a", roughness=0.12, metallic=0.5)
    shop = rm.material("neon_shopfront", "#2b3b4a", roughness=0.2, emission="#ffe8c8", emission_strength=0.12)
    frame = rm.material("dt_frame_grey", "#4a4f57", roughness=0.4, metallic=0.5)
    mb = rm.MeshBuilder()
    x0, y0, x1, y1 = -8.0, -8.0, 8.0, 8.0
    top = 24.0
    mb.box(x0, y0, 0.0, x1, y1, top, wall, skip=("bottom",))
    mb.box(x0 + 0.5, y0 - 0.05, 0.0, x1 - 0.5, y0, 2.6, shop, skip=("back",))
    mb.box(x0 + 0.2, y0 - 1.5, 2.7, x1 - 0.2, y0, 2.95, frame)
    for k in range(1, 8):
        zb = k * FH
        mb.box(x0 - 0.05, y0 - 0.05, zb + 0.9, x1 + 0.05, y1 + 0.05, zb + 2.5, glass, skip=("top", "bottom"))
    roof_slab(mb, x0, y0, x1, y1, top, wall)
    mb.box_c(-3.0, 3.0, top + 0.3, 4.0, 3.0, 2.2, frame)
    mb.build(name)
    collide(name, [(x0, y0, 0.0, x1, y1, top + 1.2)])
    rm.export_glb("buildings", name)


def office_b() -> None:
    """Terracotta office, five floors of punched windows, a shop with an awning at street level."""
    name = "bld_dt_office_b"
    rm.clear_scene()
    wall = rm.material("dt_terracotta", "#b86a4c", roughness=0.85)
    trim = rm.material("dt_trim_cream", "#efe6d2", roughness=0.7)
    glass = rm.material("office_glass_blue", "#35597a", roughness=0.12, metallic=0.5)
    shop = rm.material("neon_shopfront", "#2b3b4a", roughness=0.2, emission="#ffe8c8", emission_strength=0.12)
    awning = rm.material("dt_awning_green", "#2f6d55", roughness=0.8, double_sided=True)
    mb = rm.MeshBuilder()
    x0, y0, x1, y1 = -6.0, -7.0, 6.0, 7.0
    top = 15.0
    mb.box(x0, y0, 0.0, x1, y1, top, wall, skip=("bottom",))
    mb.box(x0 + 0.4, y0 - 0.05, 0.0, x1 - 0.4, y0, 2.6, shop, skip=("back",))
    mb.box(x0 + 0.2, y0 - 1.6, 2.75, x1 - 0.2, y0, 2.9, awning)
    for k in range(1, 5):
        zb = k * FH
        mb.box(x0 - 0.05, y0 - 0.06, zb - 0.1, x1 + 0.05, y0, zb + 0.12, trim, skip=("back",))
        for i in range(4):
            u = x0 + 12.0 * (i + 0.5) / 4
            mb.box(u - 0.8, y0 - 0.04, zb + 0.8, u + 0.8, y0, zb + 2.4, glass, skip=("back",))
            mb.box(u - 0.8, y1, zb + 0.8, u + 0.8, y1 + 0.04, zb + 2.4, glass, skip=("front",))
    roof_slab(mb, x0, y0, x1, y1, top, trim, parapet=0.7)
    mb.build(name)
    collide(name, [(x0, y0, 0.0, x1, y1, top + 1.0)])
    rm.export_glb("buildings", name)


def retail(name: str, paint: str, neon_name: str, neon: str, word: str) -> None:
    """Two-storey shop: a glass front, a neon word on a dark board, a flat roof."""
    rm.clear_scene()
    wall = rm.material(name + "_wall", paint, roughness=0.85)
    frame = rm.material("dt_frame_grey", "#4a4f57", roughness=0.4, metallic=0.5)
    shop = rm.material("neon_shopfront", "#2b3b4a", roughness=0.2, emission="#ffe8c8", emission_strength=0.12)
    glass = rm.material("office_glass_blue", "#35597a", roughness=0.12, metallic=0.5)
    board = rm.material("dt_sign_board", "#16181d", roughness=0.6)
    tube = rm.material(neon_name, neon, roughness=0.3, emission=neon, emission_strength=1.4)
    mb = rm.MeshBuilder()
    x0, y0, x1, y1 = -6.0, -7.0, 6.0, 7.0
    top = 6.0
    mb.box(x0, y0, 0.0, x1, y1, top, wall, skip=("bottom",))
    mb.box(x0 + 0.4, y0 - 0.05, 0.0, x1 - 0.4, y0, 2.7, shop, skip=("back",))
    mb.box(x0 + 0.6, y0 - 0.05, 3.9, x1 - 0.6, y0, 5.4, glass, skip=("back",))
    mb.box(x0 + 0.3, y0 - 0.25, 2.8, x1 - 0.3, y0, 3.75, board, skip=("back",))
    rm.pixel_text(mb, word, 0.0, y0 - 0.25, 2.95, 0.13, tube, depth=0.06)
    mb.box(x0, y0, top, x1, y1, top + 0.6, frame, skip=("bottom",))
    mb.build(name)
    collide(name, [(x0, y0, 0.0, x1, y1, top + 0.6)])
    rm.export_glb("buildings", name)


def hotel() -> None:
    """Hotel: a cream slab with balconies on every floor, a glowing lobby, HOTEL on the roof."""
    name = "bld_dt_hotel"
    rm.clear_scene()
    wall = rm.material("dt_hotel_cream", "#e8dcc2", roughness=0.8)
    glass = rm.material("window_glass", "#2a3644", roughness=0.18, metallic=0.35)
    rail = rm.material("window_bars", "#2c2e33", roughness=0.5, metallic=0.5)
    lobby_glow = rm.material("neon_lobby", "#c9b48a", roughness=0.2, emission="#ffd9a0", emission_strength=0.5)
    gold = rm.material("dt_fin_gold", "#c2a061", roughness=0.35, metallic=0.8)
    board = rm.material("dt_sign_board", "#16181d", roughness=0.6)
    neon = rm.material("neon_magenta", "#a0306f", roughness=0.3, emission="#ff3aa8", emission_strength=1.5)
    mb = rm.MeshBuilder()
    x0, y0, x1, y1 = -12.0, -9.0, 12.0, 9.0
    lobby(mb, x0, y0, x1, y1, 6.0, wall, lobby_glow, gold)
    mb.box(x0, y0, 5.6, x1, y1, 6.0, wall)
    floors = 13
    top = 6.0 + floors * FH
    mb.box(x0, y0, 6.0, x1, y1, top, wall, skip=("bottom",))
    for k in range(floors):
        zb = 6.0 + k * FH
        for plane, out in ((y0, -1), (y1, 1)):
            for i in range(6):
                u = x0 + 24.0 * (i + 0.5) / 6
                if out < 0:
                    mb.box(u - 1.2, plane - 0.04, zb + 0.4, u + 1.2, plane, zb + 2.6, glass, skip=("back",))
                else:
                    mb.box(u - 1.2, plane, zb + 0.4, u + 1.2, plane + 0.04, zb + 2.6, glass, skip=("front",))
            ya, yb = (plane - 1.1, plane) if out < 0 else (plane, plane + 1.1)
            mb.box(x0 + 0.4, ya, zb, x1 - 0.4, yb, zb + 0.16, wall)
            ry = ya if out < 0 else yb - 0.05
            mb.box(x0 + 0.4, ry, zb + 0.95, x1 - 0.4, ry + 0.05, zb + 1.02, rail)
    roof_slab(mb, x0, y0, x1, y1, top, wall)
    # rooftop sign on two legs, facing the front
    for px in (-7.0, 7.0):
        mb.box(px - 0.15, -1.0, top + 0.3, px + 0.15, -0.7, top + 6.0, rail)
    mb.box(-9.0, -1.2, top + 2.0, 9.0, -1.0, top + 6.0, board)
    rm.pixel_text(mb, "HOTEL", 0.0, -1.2, top + 2.6, 0.55, neon, depth=0.1)
    mb.build(name)
    collide(name, [(x0, y0, 0.0, x1, y1, top + 1.2)])
    rm.export_glb("buildings", name)


def mall() -> None:
    """Shopping mall: a long low block, a tall glass atrium over the entrance with VELA MALL in
    neon above it, panelled side walls, a rooftop plant box."""
    name = "bld_dt_mall"
    rm.clear_scene()
    panel = rm.material("dt_mall_panel", "#d7d3cc", roughness=0.6)
    stripe = rm.material("dt_mall_stripe", "#3a5f8a", roughness=0.5)
    glass = rm.material("office_glass_teal", "#3f7f8e", roughness=0.12, metallic=0.6)
    lobby_glow = rm.material("neon_lobby", "#c9b48a", roughness=0.2, emission="#ffd9a0", emission_strength=0.5)
    frame = rm.material("dt_frame_grey", "#4a4f57", roughness=0.4, metallic=0.5)
    board = rm.material("dt_sign_board", "#16181d", roughness=0.6)
    neon = rm.material("neon_cyan", "#1f7f86", roughness=0.3, emission="#30f0ff", emission_strength=1.5)
    roof = rm.material("dt_roof_grey", "#8d9096", roughness=0.9)
    mb = rm.MeshBuilder()
    x0, y0, x1, y1 = -22.0, -24.0, 22.0, 24.0
    top = 18.0
    mb.box(x0, y0, 0.0, x1, y1, top, panel, skip=("bottom",))
    for z in (6.0, 12.0):
        mb.box(x0 - 0.08, y0 - 0.08, z - 0.4, x1 + 0.08, y1 + 0.08, z + 0.4, stripe, skip=("top", "bottom"))
    # atrium: glass box standing proud of the front, glowing lobby inside
    ax0, ax1 = -9.0, 9.0
    mb.box(ax0, y0 - 3.0, 0.0, ax1, y0, 21.0, glass, skip=("bottom", "back"))
    mb.box(ax0 + 1.0, y0 - 2.9, 0.0, ax1 - 1.0, y0 - 2.85, 4.5, lobby_glow, skip=("back",))
    for i in range(7):
        fx = ax0 + 18.0 * i / 6
        mb.box(fx - 0.12, y0 - 3.2, 0.0, fx + 0.12, y0 - 3.0, 21.0, frame, skip=("bottom",))
    mb.box(-12.0, y0 - 7.0, 4.8, 12.0, y0 - 3.0, 5.2, frame)                 # entrance canopy
    for cx in (-11.0, 11.0):
        mb.box(cx - 0.2, y0 - 6.8, 0.0, cx + 0.2, y0 - 6.4, 4.8, frame, skip=("bottom",))
    mb.box(-11.0, y0 - 3.4, 15.2, 11.0, y0 - 3.2, 19.6, board, skip=("back",))
    rm.pixel_text(mb, "VELA MALL", 0.0, y0 - 3.4, 15.9, 0.6, neon, depth=0.12)
    roof_slab(mb, x0, y0, x1, y1, top, roof, parapet=1.2)
    mb.box_c(8.0, 10.0, top + 0.3, 12.0, 14.0, 3.0, roof)
    mb.build(name)
    collide(name, [(x0, y0, 0.0, x1, y1, top + 1.5), (ax0, y0 - 3.2, 0.0, ax1, y0, 21.0)])
    rm.export_glb("buildings", name)


def police() -> None:
    """Police headquarters: white with bands of blue glass, a blue rooftop board saying POLICE."""
    name = "bld_dt_police"
    rm.clear_scene()
    wall = rm.material("dt_police_white", "#eceae4", roughness=0.75)
    blue = rm.material("police_blue", "#1f4fa0", roughness=0.6)
    glass = rm.material("office_glass_blue", "#35597a", roughness=0.12, metallic=0.5)
    lobby_glow = rm.material("neon_lobby", "#c9b48a", roughness=0.2, emission="#ffd9a0", emission_strength=0.5)
    bars = rm.material("window_bars", "#2c2e33", roughness=0.5, metallic=0.5)
    letters = rm.material("sign_letters", "#f4f1e8", roughness=0.6)
    mb = rm.MeshBuilder()
    x0, y0, x1, y1 = -8.0, -8.0, 8.0, 8.0
    top = 15.0
    mb.box(x0, y0, 0.0, x1, y1, top, wall, skip=("bottom",))
    mb.box(-3.0, y0 - 0.05, 0.0, 3.0, y0, 2.8, lobby_glow, skip=("back",))
    mb.box(-4.0, y0 - 2.0, 3.0, 4.0, y0, 3.3, blue)
    for k in range(1, 5):
        zb = k * FH
        mb.box(x0 - 0.05, y0 - 0.05, zb + 0.9, x1 + 0.05, y1 + 0.05, zb + 2.3, glass, skip=("top", "bottom"))
    mb.box(x0 - 0.1, y0 - 0.1, 2.9, x1 + 0.1, y1 + 0.1, 3.3, blue, skip=("bottom",))
    mb.box(x0, y0, top, x1, y1, top + 0.8, blue, skip=("bottom",))
    for px in (x0 + 1.0, x1 - 1.15):
        mb.box(px, y0 + 0.4, top + 0.8, px + 0.15, y0 + 0.55, top + 4.0, bars)
    mb.box(x0 + 0.6, y0 + 0.3, top + 1.6, x1 - 0.6, y0 + 0.4, top + 4.2, blue)
    rm.pixel_text(mb, "POLICE", 0.0, y0 + 0.3, top + 2.3, 0.25, letters)
    mb.build(name)
    collide(name, [(x0, y0, 0.0, x1, y1, top + 0.8)])
    rm.export_glb("buildings", name)


def fountain() -> None:
    """Plaza fountain: a 6 m stone basin of water with a stepped column in the middle."""
    name = "prop_dt_fountain"
    rm.clear_scene()
    stone = rm.material("dt_granite", "#5c5652", roughness=0.6)
    light = rm.material("dt_stone_light", "#cfc8bc", roughness=0.7)
    water = rm.material("fountain_water", "#2f6f8f", roughness=0.05, metallic=0.2)
    mb = rm.MeshBuilder()
    mb.cylinder(0.0, 0.0, 0.0, 3.0, 3.0, 0.6, 16, light)
    mb.cylinder(0.0, 0.0, 0.0, 2.7, 2.7, 0.62, 16, water, caps=True)
    mb.cylinder(0.0, 0.0, 0.62, 0.7, 0.5, 1.2, 10, stone)
    mb.cylinder(0.0, 0.0, 1.82, 1.2, 1.2, 0.2, 12, light)
    mb.cylinder(0.0, 0.0, 2.02, 0.3, 0.2, 0.9, 8, stone)
    mb.build(name)
    col = rm.CollisionSet(name)
    pts = []
    for i in range(12):
        a = 2.0 * math.pi * i / 12
        for z in (0.0, 0.6):
            pts.append((3.0 * math.cos(a), 3.0 * math.sin(a), z))
    col.hull(pts)
    col.box(-0.6, -0.6, 0.6, 0.6, 0.6, 2.9)
    col.build()
    rm.export_glb("props", name)


BUILDERS = {
    "bld_dt_tower_a": tower_a,
    "bld_dt_tower_b": tower_b,
    "bld_dt_tower_c": tower_c,
    "bld_dt_office_a": office_a,
    "bld_dt_office_b": office_b,
    "bld_dt_retail_a": lambda: retail("bld_dt_retail_a", "#2f3b4c", "neon_cyan", "#30f0ff", "CAFE"),
    "bld_dt_retail_b": lambda: retail("bld_dt_retail_b", "#5a2d48", "neon_magenta", "#ff3aa8", "SALON"),
    "bld_dt_hotel": hotel,
    "bld_dt_mall": mall,
    "bld_dt_police": police,
    "prop_dt_fountain": fountain,
}


def main() -> None:
    for name in (rm.script_args() or list(BUILDERS)):
        BUILDERS[name]()


main()
