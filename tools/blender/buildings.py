"""Placeholder buildings -> assets/models/buildings/

Every building has its pivot at the base centre and its front facing Blender -Y
(Godot +Z after import). Collision is a simple box-based '-colonly' mesh.

  bld_shophouse_01..03  8 x 12 m, 2-3 storeys: shutter or open shopfront, striped awning,
                        blank sign board with a neon strip, balcony, rooftop water tank
  bld_apartment_01..02  16 x 12 m, 6-7 storeys on stilts (walk-under parking), balconies
  bld_office_01..02     glass towers with floor bands, corner fins and a neon crown
  bld_temple_gopuram    14 x 9 m gateway tower (~27 m) with a walk-through passage
  bld_temple_shrine     6 x 6 m shrine with a stepped tower and dome

Run:  "$BLENDER" --background --factory-startup --python tools/blender/buildings.py [-- names...]
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rotd_mesh as rm  # noqa: E402

DEPTH = 0.06  # how far window glass sits proud of a wall


# --------------------------------------------------------------------------- shared details

def window(mb: rm.MeshBuilder, side: str, plane: float, u: float, z: float, w: float, h: float,
           glass, sill) -> None:
    """One window on a wall. side: front (-Y), back (+Y), left (-X), right (+X)."""
    if side == "front":
        mb.box(u - w / 2, plane - DEPTH, z, u + w / 2, plane, z + h, glass, skip=("back",))
        mb.box(u - w / 2 - 0.08, plane - 0.14, z - 0.1, u + w / 2 + 0.08, plane, z, sill, skip=("back",))
    elif side == "back":
        mb.box(u - w / 2, plane, z, u + w / 2, plane + DEPTH, z + h, glass, skip=("front",))
        mb.box(u - w / 2 - 0.08, plane, z - 0.1, u + w / 2 + 0.08, plane + 0.14, z, sill, skip=("front",))
    elif side == "left":
        mb.box(plane - DEPTH, u - w / 2, z, plane, u + w / 2, z + h, glass, skip=("right",))
        mb.box(plane - 0.14, u - w / 2 - 0.08, z - 0.1, plane, u + w / 2 + 0.08, z, sill, skip=("right",))
    else:
        mb.box(plane, u - w / 2, z, plane + DEPTH, u + w / 2, z + h, glass, skip=("left",))
        mb.box(plane, u - w / 2 - 0.08, z - 0.1, plane + 0.14, u + w / 2 + 0.08, z, sill, skip=("left",))


def parapet(mb: rm.MeshBuilder, x0: float, y0: float, x1: float, y1: float, z: float,
            h: float, t: float, mat) -> None:
    mb.box(x0, y0, z, x1, y0 + t, z + h, mat, skip=("bottom",))
    mb.box(x0, y1 - t, z, x1, y1, z + h, mat, skip=("bottom",))
    mb.box(x0, y0 + t, z, x0 + t, y1 - t, z + h, mat, skip=("bottom",))
    mb.box(x1 - t, y0 + t, z, x1, y1 - t, z + h, mat, skip=("bottom",))


def water_tank(mb: rm.MeshBuilder, x: float, y: float, z: float, stand) -> None:
    tank = rm.material("water_tank", "#1d1e20", roughness=0.55)
    mb.box_c(x, y, z, 1.3, 1.3, 0.35, stand)
    mb.cylinder(x, y, z + 0.35, 0.65, 0.65, 1.15, 10, tank)
    mb.cylinder(x, y, z + 1.5, 0.65, 0.2, 0.2, 10, tank)


def box_collision(name: str, boxes: list[tuple]) -> None:
    col = rm.MeshBuilder()
    for b in boxes:
        col.box(*b, rm.collision_material())
    col.build(name + "-colonly")


# --------------------------------------------------------------------------- shophouse

SHOPHOUSES = {
    "bld_shophouse_01": dict(floors=2, paint="#d9775c", trim="#f3e6cf", awning=("#2f8f5b", "#f4f1e8"),
                             sign="#1d7a8c", neon="#22e6ff", shop="shutter"),
    "bld_shophouse_02": dict(floors=3, paint="#efc77e", trim="#fbf3e2", awning=("#2c5fa8", "#f4f1e8"),
                             sign="#b8322a", neon="#ff2bd6", shop="open"),
    "bld_shophouse_03": dict(floors=3, paint="#7fb39a", trim="#f1efe6", awning=("#e2762b", "#f4f1e8"),
                             sign="#5b3a8c", neon="#ffb02e", shop="shutter"),
}


def shophouse(name: str, floors: int, paint: str, trim: str, awning: tuple, sign: str, neon: str,
              shop: str) -> None:
    rm.clear_scene()
    wall = rm.material(name + "_paint", paint, roughness=0.88)
    trim_m = rm.material(name + "_trim", trim, roughness=0.8)
    glass = rm.material("window_glass", "#2a3644", roughness=0.18, metallic=0.35)
    dark = rm.material("shop_interior", "#17130f", roughness=0.95)
    shutter = rm.material("shutter_metal", "#8f959c", roughness=0.45, metallic=0.5)
    rib = rm.material("shutter_rib", "#6d737a", roughness=0.5, metallic=0.5)
    aw_a = rm.material(name + "_awning_a", awning[0], roughness=0.85, double_sided=True)
    aw_b = rm.material(name + "_awning_b", awning[1], roughness=0.85, double_sided=True)
    sign_m = rm.material(name + "_sign", sign, roughness=0.6)
    neon_m = rm.material(name + "_neon", neon, roughness=0.4, emission=neon, emission_strength=2.5)
    warm = rm.material("shop_light", "#ffd9a0", roughness=0.5, emission="#ffcf8a", emission_strength=1.2)

    w, d = 8.0, 12.0
    x0, x1, y0, y1 = -w / 2, w / 2, -d / 2, d / 2
    h0, fh = 3.6, 3.1
    top = h0 + (floors - 1) * fh

    mb = rm.MeshBuilder()
    mb.box(x0, y0, 0.0, x1, y1, top, wall, skip=("bottom",))
    # Corner pilasters and floor bands on the front.
    for px in (x0, x1 - 0.45):
        mb.box(px, y0 - 0.12, 0.0, px + 0.45, y0, top, trim_m, skip=("back", "bottom"))
    for k in range(1, floors):
        z = h0 + (k - 1) * fh
        mb.box(x0 + 0.45, y0 - 0.1, z - 0.12, x1 - 0.45, y0, z + 0.06, trim_m, skip=("back",))

    # Ground-floor shopfront.
    mb.box(-3.4, y0 - 0.02, 0.0, 3.4, y0, 3.0, dark, skip=("back", "bottom"))
    if shop == "shutter":
        mb.box(-3.3, y0 - 0.06, 0.05, 3.3, y0 - 0.02, 2.9, shutter, skip=("back", "bottom"))
        for i in range(11):
            z = 0.25 + i * 0.25
            mb.box(-3.3, y0 - 0.09, z, 3.3, y0 - 0.06, z + 0.05, rib, skip=("back",))
    else:
        mb.box(-3.4, y0 - 0.05, 2.65, 3.4, y0 - 0.02, 2.8, warm, skip=("back",))        # lit pelmet
        for gx in (-3.3, 1.9):
            mb.box(gx, y0 - 0.05, 0.95, gx + 1.4, y0 - 0.02, 2.6, glass, skip=("back",))

    # Striped awning sloping down and out over the pavement.
    for i in range(8):
        ax0 = -3.8 + i * 0.95
        mb.prism([(y0, 3.5), (y0 - 1.6, 3.0), (y0 - 1.6, 2.88), (y0, 3.36)], "X", ax0, ax0 + 0.95,
                 aw_a if i % 2 == 0 else aw_b)

    # Sign board (left blank: no text, no brands) with a neon strip under it.
    mb.box(-3.75, y0 - 0.2, 3.55, 3.75, y0, 4.45, trim_m, skip=("back",))
    mb.box(-3.6, y0 - 0.26, 3.65, 3.6, y0 - 0.2, 4.35, sign_m, skip=("back",))
    mb.box(-3.6, y0 - 0.3, 3.56, 3.6, y0 - 0.22, 3.62, neon_m, skip=("back",))

    # Upper floors: windows all round, balcony on the first upper floor.
    for k in range(1, floors):
        zf = h0 + (k - 1) * fh
        for u in (-2.0, 2.0):
            window(mb, "front", y0, u, zf + 0.9, 1.4, 1.6, glass, trim_m)
            window(mb, "back", y1, u, zf + 0.9, 1.4, 1.6, glass, trim_m)
        for side, plane in (("left", x0), ("right", x1)):
            window(mb, side, plane, 2.5, zf + 1.0, 1.0, 1.3, glass, trim_m)
        if k == 1:
            mb.box(-2.9, y0 - 1.1, zf, 2.9, y0, zf + 0.15, trim_m)
            mb.box(-2.9, y0 - 1.1, zf + 0.95, 2.9, y0 - 1.0, zf + 1.05, trim_m)
            for i in range(13):
                bx = -2.85 + i * 0.475
                mb.box(bx, y0 - 1.08, zf + 0.15, bx + 0.05, y0 - 1.03, zf + 0.95, trim_m, skip=("top", "bottom"))
            for sx in (-2.9, 2.8):
                mb.box(sx, y0 - 1.1, zf + 0.15, sx + 0.1, y0, zf + 1.05, trim_m, skip=("bottom",))

    # Roof: parapet, water tank, stair cabin on taller variants.
    parapet(mb, x0, y0, x1, y1, top, 0.9, 0.2, trim_m)
    water_tank(mb, 2.2, 3.6, top, trim_m)
    if floors >= 3:
        mb.box(-3.6, 1.8, top, -1.0, 5.6, top + 2.4, wall, skip=("bottom",))
        mb.box(-3.75, 1.65, top + 2.4, -0.85, 5.75, top + 2.55, trim_m)
    mb.build(name)

    box_collision(name, [(x0, y0, 0.0, x1, y1, top + 0.9)])
    rm.export_glb("buildings", name)


# --------------------------------------------------------------------------- apartment

APARTMENTS = {
    "bld_apartment_01": dict(floors=6, paint="#efe9d8", accent="#3d4a6b", rail="#c46b4a"),
    "bld_apartment_02": dict(floors=7, paint="#a9d3d6", accent="#24506b", rail="#f2efe6"),
}


def apartment(name: str, floors: int, paint: str, accent: str, rail: str) -> None:
    rm.clear_scene()
    wall = rm.material(name + "_paint", paint, roughness=0.88)
    accent_m = rm.material(name + "_accent", accent, roughness=0.8)
    rail_m = rm.material(name + "_rail", rail, roughness=0.8)
    concrete = rm.material("concrete", "#b9b5ad", roughness=0.92)
    glass = rm.material("window_glass", "#2a3644", roughness=0.18, metallic=0.35)

    w, d = 16.0, 12.0
    x0, x1, y0, y1 = -w / 2, w / 2, -d / 2, d / 2
    h0, fh = 3.0, 3.0
    top = h0 + floors * fh

    mb = rm.MeshBuilder()
    # Stilt (parking) level: columns and a stair core that runs up to the roof cabin.
    cols = [(x, y) for x in (-7.5, -2.5, 2.5, 7.5) for y in (-5.5, 0.0, 5.5)]
    for cx, cy in cols:
        mb.box_c(cx, cy, 0.0, 0.5, 0.5, h0, concrete, skip=("bottom", "top"))
    core = (-1.5, 2.0, 1.5, 6.05)  # 5 cm proud of the back wall so the faces never z-fight
    mb.box(core[0], core[1], 0.0, core[2], core[3], top + 2.6, accent_m, skip=("bottom",))
    # Main body (its underside is the parking ceiling).
    mb.box(x0, y0, h0, x1, y1, top, wall)
    mb.box(-0.6, y0 - 0.3, h0, 0.6, y0, top + 0.9, accent_m, skip=("back",))
    for k in range(floors):
        zf = h0 + k * fh
        # Front: two balconies with solid parapets and glazed doors behind.
        for bx in (-4.2, 4.2):
            mb.box(bx - 2.6, y0 - 1.3, zf, bx + 2.6, y0, zf + 0.15, concrete)
            mb.box(bx - 2.6, y0 - 1.3, zf + 0.15, bx + 2.6, y0 - 1.15, zf + 1.05, rail_m, skip=("bottom",))
            for sx in (bx - 2.6, bx + 2.45):
                mb.box(sx, y0 - 1.15, zf + 0.15, sx + 0.15, y0, zf + 1.05, rail_m, skip=("bottom",))
            window(mb, "front", y0, bx - 1.0, zf + 0.25, 1.2, 2.2, glass, concrete)
            window(mb, "front", y0, bx + 1.2, zf + 0.9, 1.4, 1.4, glass, concrete)
        for u in (-5.5, -3.0, 3.0, 5.5):
            window(mb, "back", y1, u, zf + 0.9, 1.4, 1.4, glass, concrete)
        for u in (-3.0, 3.0):
            window(mb, "left", x0, u, zf + 0.9, 1.4, 1.4, glass, concrete)
            window(mb, "right", x1, u, zf + 0.9, 1.4, 1.4, glass, concrete)
        mb.box(x0 - 0.05, y0 - 0.05, zf + fh - 0.12, x1 + 0.05, y1 + 0.05, zf + fh, accent_m, skip=("bottom", "top"))
    parapet(mb, x0, y0, x1, y1, top, 1.0, 0.2, accent_m)
    water_tank(mb, -5.5, 3.5, top, concrete)
    water_tank(mb, 5.5, 3.5, top, concrete)
    mb.build(name)

    boxes = [(x0, y0, h0, x1, y1, top + 1.0), (core[0], core[1], 0.0, core[2], core[3], top + 2.6)]
    boxes += [(cx - 0.25, cy - 0.25, 0.0, cx + 0.25, cy + 0.25, h0) for cx, cy in cols]
    box_collision(name, boxes)
    rm.export_glb("buildings", name)


# --------------------------------------------------------------------------- office tower

OFFICES = {
    "bld_office_01": dict(w=20.0, d=20.0, floors=14, fh=3.8, lobby=6.0, glass="#1f3550",
                          neon="#22e6ff", spire=True),
    "bld_office_02": dict(w=14.0, d=14.0, floors=9, fh=3.6, lobby=5.0, glass="#1d4a4a",
                          neon="#ff2bd6", spire=False),
}


def office(name: str, w: float, d: float, floors: int, fh: float, lobby: float, glass: str,
           neon: str, spire: bool) -> None:
    rm.clear_scene()
    glass_m = rm.material(name + "_glass", glass, roughness=0.12, metallic=0.6)
    lobby_m = rm.material("lobby_glass", "#6f8796", roughness=0.1, metallic=0.3,
                          emission="#ffe2b8", emission_strength=0.35)
    concrete = rm.material("office_concrete", "#cfccc4", roughness=0.85)
    dark = rm.material("office_dark", "#2b2d31", roughness=0.7)
    neon_m = rm.material(name + "_neon", neon, roughness=0.4, emission=neon, emission_strength=3.0)
    beacon = rm.material("aviation_light", "#ff2020", emission="#ff2020", emission_strength=4.0)

    x0, x1, y0, y1 = -w / 2, w / 2, -d / 2, d / 2
    top = lobby + floors * fh

    mb = rm.MeshBuilder()
    # Lobby: recessed glass box behind a ring of columns, with a canopy over the entrance.
    mb.box(x0 + 1.2, y0 + 1.2, 0.0, x1 - 1.2, y1 - 1.2, lobby, lobby_m, skip=("bottom", "top"))
    n_cols = int(w // 4)
    for i in range(n_cols + 1):
        cx = x0 + 0.4 + i * (w - 0.8) / n_cols
        for cy in (y0 + 0.4, y1 - 0.4):
            mb.box_c(cx, cy, 0.0, 0.8, 0.8, lobby, concrete, skip=("bottom", "top"))
    for i in range(1, int(d // 4)):
        cy = y0 + 0.4 + i * (d - 0.8) / int(d // 4)
        for cx in (x0 + 0.4, x1 - 0.4):
            mb.box_c(cx, cy, 0.0, 0.8, 0.8, lobby, concrete, skip=("bottom", "top"))
    mb.box(-4.5, y0 - 3.5, 4.2, 4.5, y0 + 0.4, 4.55, concrete)
    # Tower: glass volume, a concrete band at every floor, fins at the corners.
    mb.box(x0, y0, lobby, x1, y1, top, glass_m)
    for k in range(floors + 1):
        z = lobby + k * fh
        mb.box(x0 - 0.12, y0 - 0.12, z - 0.35, x1 + 0.12, y1 + 0.12, z, concrete)
    for fx, fy in ((x0, y0), (x1, y0), (x0, y1), (x1, y1)):
        mb.box_c(fx, fy, lobby, 0.8, 0.8, top - lobby + 0.6, concrete, skip=("bottom",))
    # Crown: set-back glass level with a neon ring, plant room on the roof.
    mb.box(x0 + 1.5, y0 + 1.5, top, x1 - 1.5, y1 - 1.5, top + 4.0, glass_m, skip=("bottom",))
    mb.box(x0 + 1.4, y0 + 1.4, top + 3.6, x1 - 1.4, y1 - 1.4, top + 3.85, neon_m, skip=("bottom", "top"))
    mb.box(x0 + 1.3, y0 + 1.3, top + 4.0, x1 - 1.3, y1 - 1.3, top + 4.4, concrete)
    mb.box(-3.0, -2.0, top + 4.4, 3.0, 3.0, top + 6.4, dark, skip=("bottom",))
    if spire:
        mb.tube((0.0, 0.5, top + 6.4), (0.0, 0.5, top + 16.0), 0.3, 0.06, 8, concrete)
        mb.sphere((0.0, 0.5, top + 16.1), 0.18, 8, 5, beacon)
    mb.build(name)

    box_collision(name, [(x0, y0, 0.0, x1, y1, top + 4.4)])
    rm.export_glb("buildings", name)


# --------------------------------------------------------------------------- temple gopuram

TIER_COLOURS = ["#f0e2c4", "#d9a441", "#c4572e", "#5fa8d3", "#f0e2c4", "#6aa84f", "#d9a441"]


def kalasam(mb: rm.MeshBuilder, x: float, y: float, z: float, gold, scale: float = 1.0) -> None:
    s = scale
    mb.cylinder(x, y, z, 0.22 * s, 0.18 * s, 0.25 * s, 8, gold)
    mb.sphere((x, y, z + 0.45 * s), 0.28 * s, 8, 5, gold, squash=0.85)
    mb.cylinder(x, y, z + 0.65 * s, 0.14 * s, 0.0, 0.6 * s, 8, gold, caps=False)


def gopuram() -> None:
    name = "bld_temple_gopuram"
    rm.clear_scene()
    granite = rm.material("granite", "#7d7468", roughness=0.9)
    stone = rm.material("temple_stone", "#a8916f", roughness=0.9)
    dark = rm.material("temple_niche", "#2a211b", roughness=0.95)
    gold = rm.material("temple_gold", "#d4a017", roughness=0.3, metallic=0.85)
    tiers = [rm.material(f"gopuram_tier_{i}", c, roughness=0.8) for i, c in enumerate(TIER_COLOURS)]
    cornice = rm.material("gopuram_cornice", "#efe6d2", roughness=0.8)
    figure = [rm.material("figure_red", "#b8432f"), rm.material("figure_blue", "#3f7fb5"),
              rm.material("figure_green", "#4f8f4a"), rm.material("figure_cream", "#f3e9d2")]

    mb = rm.MeshBuilder()
    # Plinth with low steps at the passage.
    mb.box(-7.5, -5.0, 0.0, 7.5, 5.0, 0.35, granite, skip=("bottom",))
    for sy in (-1.0, 1.0):
        y_out = sy * 5.6
        mb.box(-2.2, min(y_out, sy * 5.0), 0.0, 2.2, max(y_out, sy * 5.0), 0.18, granite, skip=("bottom",))
    # Solid stone base split by a 3.6 m wide, 4.55 m tall passage.
    base_top = 6.6
    mb.box(-7.0, -4.5, 0.35, -1.8, 4.5, base_top, stone, skip=("bottom",))
    mb.box(1.8, -4.5, 0.35, 7.0, 4.5, base_top, stone, skip=("bottom",))
    mb.box(-1.8, -4.5, 4.9, 1.8, 4.5, base_top, stone)
    for sy, side in ((-4.5, "front"), (4.5, "back")):
        off = -0.15 if side == "front" else 0.15
        for px in (-2.1, 1.8, -3.9, 3.6, -5.9, 5.6):
            mb.box(px, min(sy, sy + off), 0.35, px + 0.3, max(sy, sy + off), 4.9, granite)
        for mz in (1.2, 3.0):  # bands below the lintel stop at the passage
            for bx0, bx1 in ((-7.05, -2.1), (2.1, 7.05)):
                mb.box(bx0, min(sy, sy + off), mz, bx1, max(sy, sy + off), mz + 0.18, granite)
        mb.box(-7.05, min(sy, sy + off), 6.3, 7.05, max(sy, sy + off), 6.48, granite)
    # Seven tapering tiers, each with a cornice, a dark niche and rows of little painted pavilions.
    z = base_top
    bw, bd = 13.6, 8.6
    for i in range(7):
        th = 2.5 - i * 0.08
        mb.box_c(0.0, 0.0, z, bw + 0.5, bd + 0.5, 0.3, cornice)
        mb.frustum(0.0, 0.0, z + 0.3, bw, bd, bw - 0.6, bd - 0.4, th - 0.3, tiers[i])
        mid = z + 0.3 + (th - 0.3) * 0.5
        n = max(2, 5 - i // 2)
        span = bw / 2 - 1.0
        for k in range(n):
            px = -span + k * (2 * span / (n - 1)) if n > 1 else 0.0
            if abs(px) < 0.6:
                continue
            fig = figure[(i + k) % len(figure)]
            for sy in (-1.0, 1.0):
                py = sy * (bd / 2 - 0.1)
                mb.box_c(px, py + sy * 0.15, z + 0.4, 0.55, 0.3, (th - 0.3) * 0.62, fig)
                mb.frustum(px, py + sy * 0.15, z + 0.4 + (th - 0.3) * 0.62, 0.7, 0.42, 0.2, 0.15, 0.3, cornice)
        for sy in (-1.0, 1.0):
            mb.box_c(0.0, sy * (bd / 2 - 0.12), mid - 0.55, 0.9, 0.3, 1.1, dark)
        for sx in (-1.0, 1.0):
            for py in (-bd / 4, bd / 4):
                mb.box_c(sx * (bw / 2 - 0.1) + sx * 0.12, py, z + 0.4, 0.3, 0.5, (th - 0.3) * 0.6,
                         figure[(i + 1) % len(figure)])
        z += th
        bw, bd = bw - 1.2, bd - 0.62
    # Barrel-vault crown (shala) with a row of golden finials (kalasams).
    mb.box_c(0.0, 0.0, z, bw + 0.4, bd + 0.4, 0.3, cornice)
    z += 0.3
    length = bw
    r = 1.5
    profile = [(r * math.cos(math.pi * a / 10), z + r * math.sin(math.pi * a / 10)) for a in range(11)]
    mb.prism(profile, "X", -length / 2, length / 2, tiers[2])
    crown_top = z + r
    for k in range(7):
        kx = -length / 2 + 0.5 + k * (length - 1.0) / 6
        kalasam(mb, kx, 0.0, crown_top - 0.05, gold)
    mb.build(name)

    col = rm.MeshBuilder()
    cm = rm.collision_material()
    # Plinth bevelled front and back so you can walk up through the gateway.
    col.convex_hull([
        (-7.5, -5.8, -0.1), (7.5, -5.8, -0.1), (7.5, 5.8, -0.1), (-7.5, 5.8, -0.1),
        (-7.5, -5.8, 0.0), (7.5, -5.8, 0.0), (7.5, 5.8, 0.0), (-7.5, 5.8, 0.0),
        (-7.5, -5.0, 0.35), (7.5, -5.0, 0.35), (7.5, 5.0, 0.35), (-7.5, 5.0, 0.35),
    ], cm)
    col.box(-7.0, -4.5, 0.35, -1.8, 4.5, base_top, cm)
    col.box(1.8, -4.5, 0.35, 7.0, 4.5, base_top, cm)
    col.box(-1.8, -4.5, 4.9, 1.8, 4.5, base_top, cm)
    col.frustum(0.0, 0.0, base_top, 14.1, 9.1, length, bd + 0.4, crown_top - base_top, cm, bottom=True)
    col.build(name + "-colonly")
    rm.export_glb("buildings", name)


def shrine() -> None:
    name = "bld_temple_shrine"
    rm.clear_scene()
    granite = rm.material("granite", "#7d7468", roughness=0.9)
    stone = rm.material("temple_stone", "#a8916f", roughness=0.9)
    dark = rm.material("temple_niche", "#2a211b", roughness=0.95)
    gold = rm.material("temple_gold", "#d4a017", roughness=0.3, metallic=0.85)
    cream = rm.material("gopuram_cornice", "#efe6d2", roughness=0.8)
    ochre = rm.material("gopuram_tier_1", "#d9a441", roughness=0.8)
    red = rm.material("gopuram_tier_2", "#c4572e", roughness=0.8)

    mb = rm.MeshBuilder()
    mb.box_c(0.0, 0.0, 0.0, 7.0, 7.0, 0.5, granite, skip=("bottom",))
    mb.box_c(0.0, 0.0, 0.5, 5.6, 5.6, 3.2, stone, skip=("bottom",))
    mb.box(-0.7, -2.86, 0.5, 0.7, -2.8, 2.7, dark, skip=("back",))
    for px in (-2.8, 2.45):
        for py in (-2.95, 2.6):
            mb.box(px, py, 0.5, px + 0.35, py + 0.35, 3.7, granite, skip=("bottom",))
    mb.box_c(0.0, 0.0, 3.7, 6.3, 6.3, 0.3, cream)
    z = 4.0
    for (s0, s1, h, m) in ((5.0, 4.2, 1.4, ochre), (3.8, 3.0, 1.2, red), (2.6, 2.0, 1.0, cream)):
        mb.frustum(0.0, 0.0, z, s0, s0, s1, s1, h, m)
        z += h
        mb.box_c(0.0, 0.0, z, s1 + 0.3, s1 + 0.3, 0.15, cream)
        z += 0.15
    mb.cylinder(0.0, 0.0, z, 1.25, 1.1, 0.9, 8, ochre)
    mb.cylinder(0.0, 0.0, z + 0.9, 1.1, 0.35, 0.8, 8, red, caps=False)
    kalasam(mb, 0.0, 0.0, z + 1.65, gold, scale=1.2)
    mb.build(name)

    col = rm.MeshBuilder()
    cm = rm.collision_material()
    col.box(-3.5, -3.5, 0.0, 3.5, 3.5, 0.5, cm)
    col.box(-2.8, -2.8, 0.5, 2.8, 2.8, 4.0, cm)
    col.frustum(0.0, 0.0, 4.0, 5.0, 5.0, 1.2, 1.2, z + 1.7 - 4.0, cm, bottom=True)
    col.build(name + "-colonly")
    rm.export_glb("buildings", name)


# --------------------------------------------------------------------------- entry point

def main() -> None:
    builders = {}
    for n, p in SHOPHOUSES.items():
        builders[n] = (lambda n=n, p=p: shophouse(n, **p))
    for n, p in APARTMENTS.items():
        builders[n] = (lambda n=n, p=p: apartment(n, **p))
    for n, p in OFFICES.items():
        builders[n] = (lambda n=n, p=p: office(n, **p))
    builders["bld_temple_gopuram"] = gopuram
    builders["bld_temple_shrine"] = shrine
    for name in (rm.script_args() or list(builders)):
        builders[name]()


main()
