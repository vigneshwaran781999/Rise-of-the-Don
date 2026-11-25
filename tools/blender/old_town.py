"""Old Town kit (M3) -> assets/models/road/, props/, buildings/

Road kit v2: tiles for the streamed Old Town district. They carry no collision: the district
builder (tools/godot/build_old_town.gd) gives each block one bevelled slab instead.
  road_main_seg      12 x 6 m four-lane road, left-hand traffic markings (double yellow centre,
                     dashed lane lines, solid edge lines); dashes line up when tiled end to end
  road_lane_seg      8 x 6 m two-lane street, dashed centre line
  road_junction_mm   12 x 12 m junction box
  road_junction_ml   12 x 8 m junction box (X = width of the road running along Y)
  road_junction_ll   8 x 8 m junction box
  road_zebra_main    12 x 4 m zebra crossing and stop line; the junction is on the Blender -Y side
  road_zebra_lane    8 x 3 m
  road_walk_main     4 x 6 m sidewalk tile, kerb on -X, top at 0.15 m
  road_walk_lane     2 x 6 m footpath tile, kerb on -X
  road_walk_corner   4 x 4 m corner tile, kerbs on -X and -Y (scaled down for footpaths)

Props: prop_signal_pole (lamp materials sig_red / sig_amber / sig_green are switched at
runtime), prop_market_stall_a/b, prop_flower_stall, prop_handcart, prop_bollard, prop_neem_tree.

Buildings (pivot at the base centre, front facing Blender -Y): a family of Old Town row houses
and shops (bld_ot_house_*, bld_ot_shop_*, bld_ot_lodge_01), bld_ot_market_hall,
bld_ot_mandapam, bld_ot_vimana and bld_ot_tank. Collision is separate convex pieces (rm.CollisionSet).

Run:  "$BLENDER" --background --factory-startup --python tools/blender/old_town.py [-- names...]
"""

import math
import os
import sys

from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rotd_mesh as rm  # noqa: E402

LOT = 0.15  # sidewalk / lot height above the road


def mats() -> dict:
    return {
        "asphalt": rm.material("asphalt", "#2e2e33", roughness=0.93),
        "asphalt_b": rm.material("asphalt_patch", "#34343a", roughness=0.93),
        "white": rm.material("marking_white", "#e9e7df", roughness=0.6),
        "yellow": rm.material("marking_yellow", "#e3b21f", roughness=0.6),
        "paver_a": rm.material("paver_a", "#a39e94", roughness=0.9),
        "paver_b": rm.material("paver_b", "#958f85", roughness=0.9),
        "paver_c": rm.material("paver_red", "#9a6d5b", roughness=0.9),
        "curb_y": rm.material("curb_yellow", "#e8c21c", roughness=0.7),
        "curb_k": rm.material("curb_black", "#202022", roughness=0.7),
    }


def extrude_x(mb: rm.MeshBuilder, profile, x0: float, x1: float, mat, caps: bool = True) -> None:
    """Extrude a simple (possibly concave) (y, z) profile across X; faces point outwards."""
    area = 0.5 * sum(profile[i][0] * profile[(i + 1) % len(profile)][1]
                     - profile[(i + 1) % len(profile)][0] * profile[i][1] for i in range(len(profile)))
    n = len(profile)
    for i in range(n):
        (ya, za), (yb, zb) = profile[i], profile[(i + 1) % n]
        normal = Vector((0.0, zb - za, ya - yb)) if area > 0 else Vector((0.0, za - zb, yb - ya))
        mb.face([(x0, ya, za), (x0, yb, zb), (x1, yb, zb), (x1, ya, za)], mat, outward=normal)
    if caps:
        mb.face([(x0, y, z) for y, z in profile], mat, outward=Vector((-1, 0, 0)))
        mb.face([(x1, y, z) for y, z in profile], mat, outward=Vector((1, 0, 0)))


def flat(mb: rm.MeshBuilder, x0, y0, x1, y1, z, mat) -> None:
    """Upward-facing rectangle at height z (road surfaces and markings)."""
    mb.face([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)], mat, outward=Vector((0, 0, 1)))


def box_collision(name: str, boxes: list) -> None:
    col = rm.CollisionSet(name)
    for b in boxes:
        col.box(*b)
    col.build()


# =========================================================================== road kit v2

MARK_Z = 0.004  # markings float just above the asphalt


def road_main_seg() -> None:
    name = "road_main_seg"
    rm.clear_scene()
    m = mats()
    mb = rm.MeshBuilder()
    flat(mb, -6, -3, 6, 3, 0.0, m["asphalt"])
    for x in (-0.2, 0.08):                                  # double yellow centre line
        flat(mb, x, -3, x + 0.12, 3, MARK_Z, m["yellow"])
    for x in (-3.0, 3.0):                                   # dashed lane dividers, 3 m on / 3 m off
        flat(mb, x - 0.06, -1.5, x + 0.06, 1.5, MARK_Z, m["white"])
    for x in (-5.8, 5.68):                                  # solid edge lines
        flat(mb, x, -3, x + 0.12, 3, MARK_Z, m["white"])
    mb.build(name)
    rm.export_glb("road", name)


def road_lane_seg() -> None:
    name = "road_lane_seg"
    rm.clear_scene()
    m = mats()
    mb = rm.MeshBuilder()
    flat(mb, -4, -3, 4, 3, 0.0, m["asphalt"])
    flat(mb, -0.06, -1.0, 0.06, 1.0, MARK_Z, m["white"])    # dashed centre, 2 m on / 4 m off
    for x in (-3.85, 3.73):
        flat(mb, x, -3, x + 0.12, 3, MARK_Z, m["yellow"])   # faded yellow edge lines
    mb.build(name)
    rm.export_glb("road", name)


def road_junction(name: str, wx: float, wy: float) -> None:
    rm.clear_scene()
    m = mats()
    mb = rm.MeshBuilder()
    flat(mb, -wx / 2, -wy / 2, wx / 2, wy / 2, 0.0, m["asphalt"])
    # A slightly darker worn patch in the middle where turning wheels scrub.
    flat(mb, -wx * 0.3, -wy * 0.3, wx * 0.3, wy * 0.3, 0.002, m["asphalt_b"])
    mb.build(name)
    rm.export_glb("road", name)


def road_zebra(name: str, width: float, length: float) -> None:
    """Zebra crossing on the junction side (-Y) and a stop line for traffic approaching it,
    which drives on the +X half (left-hand traffic)."""
    rm.clear_scene()
    m = mats()
    mb = rm.MeshBuilder()
    hw, hl = width / 2, length / 2
    flat(mb, -hw, -hl, hw, hl, 0.0, m["asphalt"])
    zebra_end = -hl + length * 0.62
    x = -hw + 0.45
    while x + 0.5 <= hw - 0.3:
        flat(mb, x, -hl + 0.2, x + 0.5, zebra_end, MARK_Z, m["white"])
        x += 1.0
    stop0 = zebra_end + 0.45
    flat(mb, 0.15, stop0, hw - 0.3, stop0 + 0.3, MARK_Z, m["white"])
    if width > 10:
        for xx in (-0.2, 0.08):
            flat(mb, xx, zebra_end, xx + 0.12, hl, MARK_Z, m["yellow"])
    else:
        flat(mb, -0.06, zebra_end, 0.06, hl, MARK_Z, m["white"])
    mb.build(name)
    rm.export_glb("road", name)


def kerb_strip(mb: rm.MeshBuilder, axis: str, edge: float, a0: float, a1: float, m: dict) -> None:
    """Black-and-yellow kerb 0.22 m wide along an edge of a sidewalk tile, 1 m blocks."""
    n = max(1, int(round(a1 - a0)))
    step = (a1 - a0) / n
    for i in range(n):
        mat = m["curb_y"] if i % 2 == 0 else m["curb_k"]
        b0, b1 = a0 + i * step, a0 + (i + 1) * step
        if axis == "Y":   # kerb along Y at x = edge (facing -X)
            mb.box(edge, b0, 0.0, edge + 0.22, b1, LOT, mat, skip=("bottom", "back", "front", "right"))
        else:             # kerb along X at y = edge (facing -Y)
            mb.box(b0, edge, 0.0, b1, edge + 0.22, LOT, mat, skip=("bottom", "left", "right", "back"))


def paving(mb: rm.MeshBuilder, x0, y0, x1, y1, m: dict, tile: float, warm: bool = False) -> None:
    nx = max(1, int(round((x1 - x0) / tile)))
    ny = max(1, int(round((y1 - y0) / tile)))
    for i in range(nx):
        for j in range(ny):
            mat = (m["paver_c"] if warm else m["paver_a"]) if (i + j) % 2 == 0 else m["paver_b"]
            flat(mb, x0 + (x1 - x0) * i / nx, y0 + (y1 - y0) * j / ny,
                 x0 + (x1 - x0) * (i + 1) / nx, y0 + (y1 - y0) * (j + 1) / ny, LOT, mat)


def road_walk(name: str, width: float) -> None:
    rm.clear_scene()
    m = mats()
    mb = rm.MeshBuilder()
    hw = width / 2
    kerb_strip(mb, "Y", -hw, -3.0, 3.0, m)
    paving(mb, -hw + 0.22, -3.0, hw, 3.0, m, 1.0 if width > 3 else 1.2, warm=width < 3)
    mb.build(name)
    rm.export_glb("road", name)


def road_walk_corner() -> None:
    name = "road_walk_corner"
    rm.clear_scene()
    m = mats()
    mb = rm.MeshBuilder()
    kerb_strip(mb, "Y", -2.0, -2.0, 2.0, m)
    kerb_strip(mb, "X", -2.0, -1.78, 2.0, m)
    paving(mb, -1.78, -1.78, 2.0, 2.0, m, 1.0)
    mb.build(name)
    rm.export_glb("road", name)


# =========================================================================== props

def prop_signal_pole() -> None:
    name = "prop_signal_pole"
    rm.clear_scene()
    pole = rm.material("signal_pole", "#3c4047", roughness=0.5, metallic=0.6)
    stripe = rm.material("signal_stripe", "#e8c21c", roughness=0.6)
    housing = rm.material("signal_housing", "#18191c", roughness=0.6)
    red = rm.material("sig_red", "#4a0f0c", roughness=0.3, emission="#ff2a1c", emission_strength=0.05)
    amber = rm.material("sig_amber", "#4a3208", roughness=0.3, emission="#ffae1a", emission_strength=0.05)
    green = rm.material("sig_green", "#0b3d22", roughness=0.3, emission="#2dff7a", emission_strength=0.05)
    mb = rm.MeshBuilder()
    mb.box_c(0, 0, 0, 0.36, 0.36, 0.35, pole, skip=("bottom",))
    mb.tube((0, 0, 0.35), (0, 0, 4.4), 0.075, 0.065, 8, pole)
    for k in range(3):                                      # yellow bands at the foot
        mb.tube((0, 0, 0.5 + k * 0.4), (0, 0, 0.7 + k * 0.4), 0.08, 0.08, 8, stripe, caps=False)
    hy = -0.2
    mb.box(-0.27, hy - 0.02, 2.9, 0.27, hy + 0.02, 4.25, housing)        # back plate
    mb.box(-0.19, hy - 0.26, 3.0, 0.19, hy, 4.15, housing)               # lamp housing
    mb.box(-0.06, hy, 3.5, 0.06, 0.0, 3.65, pole)                         # bracket
    for k, mat in enumerate((red, amber, green)):
        z = 3.95 - k * 0.38
        mb.tube((0, hy - 0.26, z), (0, hy - 0.29, z), 0.13, 0.13, 12, mat)
        mb.box(-0.16, hy - 0.5, z + 0.13, 0.16, hy - 0.26, z + 0.16, housing)   # visor
    mb.build(name)
    box_collision(name, [(-0.18, -0.18, 0.0, 0.18, 0.18, 4.4)])
    rm.export_glb("props", name)


def prop_market_stall(name: str, canopy: str, cloth: str) -> None:
    rm.clear_scene()
    wood = rm.material("stall_wood", "#7a5233", roughness=0.9)
    can = rm.material(name + "_canopy", canopy, roughness=0.85, double_sided=True)
    clo = rm.material(name + "_cloth", cloth, roughness=0.9)
    produce = [rm.material("produce_orange", "#e8822a", roughness=0.7),
               rm.material("produce_green", "#5f9a2e", roughness=0.7),
               rm.material("produce_red", "#c22f2a", roughness=0.7),
               rm.material("produce_yellow", "#e9c43a", roughness=0.7)]
    crate = rm.material("crate_wood", "#a47a4c", roughness=0.9)
    mb = rm.MeshBuilder()
    w, d = 2.4, 1.6
    for x in (-w / 2 + 0.05, w / 2 - 0.13):
        for y in (-d / 2 + 0.05, d / 2 - 0.13):
            mb.box(x, y, 0.0, x + 0.08, y + 0.08, 2.25 if y < 0 else 2.0, wood)
    mb.box(-w / 2, -d / 2, 0.75, w / 2, d / 2, 0.82, wood)                  # table top
    mb.box(-w / 2, -d / 2 - 0.01, 0.15, w / 2, -d / 2 + 0.01, 0.75, clo)    # cloth front
    extrude_x(mb, [(-d / 2 - 0.35, 2.2), (d / 2 + 0.15, 1.95), (d / 2 + 0.15, 2.0), (-d / 2 - 0.35, 2.25)],
              -w / 2 - 0.2, w / 2 + 0.2, can)
    k = 0
    for cx in (-0.8, -0.27, 0.27, 0.8):
        for cy in (-0.35, 0.3):
            mb.box_c(cx, cy, 0.82, 0.48, 0.5, 0.18, crate)
            mb.box_c(cx, cy, 1.0, 0.42, 0.44, 0.1 + 0.04 * (k % 2), produce[k % 4])
            k += 1
    mb.build(name)
    box_collision(name, [(-w / 2, -d / 2, 0.0, w / 2, d / 2, 1.1)])
    rm.export_glb("props", name)


def prop_flower_stall() -> None:
    name = "prop_flower_stall"
    rm.clear_scene()
    base = rm.material("stall_platform", "#6a4a32", roughness=0.9)
    basket = rm.material("basket", "#b08a52", roughness=0.9)
    marigold = rm.material("marigold", "#f29a1c", roughness=0.8)
    jasmine = rm.material("jasmine", "#f4f1e6", roughness=0.8)
    rose = rm.material("rose", "#c8234a", roughness=0.8)
    shade = rm.material("umbrella", "#2c6fb0", roughness=0.85, double_sided=True)
    pole = rm.material("umbrella_pole", "#3a3a3e", roughness=0.5, metallic=0.5)
    mb = rm.MeshBuilder()
    mb.box(-0.8, -0.6, 0.0, 0.8, 0.6, 0.45, base, skip=("bottom",))
    for i, (x, mat) in enumerate(((-0.45, marigold), (0.0, jasmine), (0.45, rose))):
        mb.cylinder(x, -0.15, 0.45, 0.2, 0.24, 0.18, 8, basket)
        mb.sphere((x, -0.15, 0.68), 0.18, 8, 4, mat, squash=0.5)
    # Garlands hanging on a rail at the back.
    mb.box(-0.75, 0.45, 1.5, 0.75, 0.5, 1.54, pole)
    for g in range(7):
        gx = -0.66 + g * 0.22
        mb.box(gx - 0.03, 0.45, 0.75, gx + 0.03, 0.5, 1.5, marigold if g % 2 == 0 else jasmine)
    mb.tube((0.7, 0.4, 0.45), (0.7, 0.4, 2.2), 0.025, 0.025, 6, pole)
    mb.tube((0.7, 0.4, 2.0), (0.7, 0.4, 2.45), 1.15, 0.05, 10, shade, caps=True)
    mb.build(name)
    box_collision(name, [(-0.8, -0.6, 0.0, 0.8, 0.6, 1.0)])
    rm.export_glb("props", name)


def prop_handcart() -> None:
    name = "prop_handcart"
    rm.clear_scene()
    wood = rm.material("cart_wood", "#8a5e38", roughness=0.9)
    metal = rm.material("cart_metal", "#4a4d52", roughness=0.5, metallic=0.6)
    tyre = rm.material("cart_tyre", "#1c1c1e", roughness=0.9)
    fruit = [rm.material("produce_orange", "#e8822a", roughness=0.7),
             rm.material("produce_green", "#5f9a2e", roughness=0.7),
             rm.material("banana", "#e6cc3d", roughness=0.7)]
    mb = rm.MeshBuilder()
    for x in (-0.55, 0.55):
        mb.tube((x - 0.04, 0, 0.32), (x + 0.04, 0, 0.32), 0.3, 0.3, 12, tyre)
    mb.tube((-0.6, 0, 0.32), (0.6, 0, 0.32), 0.03, 0.03, 6, metal)
    mb.box(-0.65, -0.95, 0.62, 0.65, 0.95, 0.72, wood)
    for x in (-0.65, 0.6):
        mb.box(x, -0.95, 0.72, x + 0.05, 0.95, 0.85, wood)
    for x in (-0.25, 0.25):
        mb.box(x - 0.025, 0.95, 0.7, x + 0.025, 1.6, 0.76, wood)          # handles
    mb.box(-0.6, -0.95, 0.0, -0.55, -0.9, 0.62, metal)                     # front leg
    for i, y in enumerate((-0.6, -0.1, 0.4)):
        mb.box_c(0.0, y, 0.72, 1.1, 0.42, 0.14, fruit[i])
    mb.build(name)
    box_collision(name, [(-0.68, -0.98, 0.0, 0.68, 0.98, 0.9)])
    rm.export_glb("props", name)


def prop_bollard() -> None:
    name = "prop_bollard"
    rm.clear_scene()
    conc = rm.material("bollard", "#d8d3c8", roughness=0.85)
    band = rm.material("curb_black", "#202022", roughness=0.7)
    mb = rm.MeshBuilder()
    mb.cylinder(0, 0, 0, 0.13, 0.11, 0.85, 8, conc)
    mb.cylinder(0, 0, 0.6, 0.118, 0.115, 0.1, 8, band, caps=False)
    mb.sphere((0, 0, 0.85), 0.11, 8, 4, conc)
    mb.build(name)
    box_collision(name, [(-0.13, -0.13, 0.0, 0.13, 0.13, 0.95)])
    rm.export_glb("props", name)


def prop_neem_tree() -> None:
    name = "prop_neem_tree"
    rm.clear_scene()
    bark = rm.material("neem_bark", "#5e4a3a", roughness=0.95)
    leaves = [rm.material("neem_leaf_a", "#4f7d2c", roughness=0.85),
              rm.material("neem_leaf_b", "#5f8f33", roughness=0.85),
              rm.material("neem_leaf_c", "#406b26", roughness=0.85)]
    mb = rm.MeshBuilder()
    mb.tube((0, 0, 0), (0.15, 0.05, 2.6), 0.28, 0.2, 8, bark)
    branches = [((0.15, 0.05, 2.4), (1.6, 0.5, 4.1)), ((0.15, 0.05, 2.5), (-1.3, 0.8, 4.3)),
                ((0.15, 0.05, 2.6), (0.2, -1.5, 4.4)), ((0.15, 0.05, 2.6), (0.4, 0.3, 5.0))]
    for a, b in branches:
        mb.tube(a, b, 0.14, 0.08, 6, bark)
    blobs = [((1.6, 0.5, 4.6), 1.7), ((-1.3, 0.8, 4.8), 1.8), ((0.2, -1.4, 4.9), 1.7),
             ((0.4, 0.3, 5.7), 2.0), ((-0.4, -0.6, 5.2), 1.5), ((1.0, -0.6, 5.5), 1.4), ((-0.8, 1.6, 5.4), 1.3)]
    for i, (c, r) in enumerate(blobs):
        mb.sphere(c, r, 8, 5, leaves[i % 3], squash=0.62)
    mb.build(name)
    box_collision(name, [(-0.3, -0.3, 0.0, 0.3, 0.3, 3.0)])
    rm.export_glb("props", name)


# =========================================================================== buildings

H0, FH = 3.4, 3.0   # ground-floor and upper-floor heights


def ot_building(name: str, w: float, d: float, floors: int, paint: str, trim: str, ground: str,
                roof: str, balcony: bool = False, awning: str | None = None, sign: str | None = None,
                pillars: int = 0, rooftop_sign: str | None = None, tank: bool = False) -> None:
    """Old Town row building. ground: 'shop', 'house' or 'verandah' (set-back front with pillars
    and raised thinnai seats); roof: 'flat' (parapet terrace) or 'tile' (pitched clay tiles)."""
    rm.clear_scene()
    wall = rm.material(name + "_wall", paint, roughness=0.9)
    trim_m = rm.material(name + "_trim", trim, roughness=0.85)
    plinth = rm.material("ot_plinth", "#6d6257", roughness=0.92)
    oxide = rm.material("red_oxide_floor", "#8e3b2e", roughness=0.7)
    wood = rm.material("ot_door_wood", "#5a3a22", roughness=0.8)
    dark = rm.material("shop_interior", "#17130f", roughness=0.95)
    glass = rm.material("window_glass", "#2a3644", roughness=0.18, metallic=0.35)
    bars = rm.material("window_bars", "#2c2e33", roughness=0.5, metallic=0.5)
    shutter = rm.material("shutter_metal", "#8f959c", roughness=0.45, metallic=0.5)
    tiles = rm.material("clay_tile", "#b5532f", roughness=0.85)
    ridge_m = rm.material("clay_ridge", "#7e3a22", roughness=0.85)

    x0, x1, y0, y1 = -w / 2, w / 2, -d / 2, d / 2
    top = H0 + (floors - 1) * FH
    setback = 1.8 if ground == "verandah" else 0.0
    yf = y0 + setback                       # ground-floor front wall
    mb = rm.MeshBuilder()
    collide = [(x0, yf, 0.0, x1, y1, H0)]

    # Body: plinth band, ground floor, upper floors.
    mb.box(x0 - 0.05, yf - 0.05, 0.0, x1 + 0.05, y1 + 0.05, 0.45, plinth, skip=("bottom",))
    mb.box(x0, yf, 0.45, x1, y1, H0, wall, skip=("bottom", "top") if floors > 1 and setback == 0 else ("bottom",))
    if floors > 1:
        mb.box(x0, y0, H0, x1, y1, top, wall, skip=() if setback > 0 else ("bottom",))
        collide.append((x0, y0, H0, x1, y1, top))
        for k in range(1, floors):          # floor bands
            z = H0 + (k - 1) * FH
            mb.box(x0, y0 - 0.08, z - 0.1, x1, y0, z + 0.08, trim_m, skip=("back",))
    pilaster_base = 0.45 if setback == 0 else H0
    if top - pilaster_base > 0.1:
        for px in (x0, x1 - 0.3):           # corner pilasters
            mb.box(px, y0 - 0.06, pilaster_base, px + 0.3, y0, top, trim_m, skip=("back", "bottom"))

    # Verandah: oxide floor, pillars, thinnai seats either side of the door.
    if setback > 0:
        mb.box(x0, y0, 0.0, x1, yf, 0.22, oxide, skip=("bottom",))
        n = max(2, pillars)
        for i in range(n):
            px = x0 + 0.35 + (w - 0.7 - 0.3) * i / (n - 1)
            mb.box(px, y0 + 0.15, 0.22, px + 0.3, y0 + 0.45, H0 if floors > 1 else top, trim_m, skip=("bottom",))
            collide.append((px, y0 + 0.15, 0.0, px + 0.3, y0 + 0.45, H0))
        for sx0, sx1 in ((x0 + 0.2, -0.75), (0.75, x1 - 0.2)):
            if sx1 - sx0 > 0.6:
                mb.box(sx0, yf - 0.85, 0.22, sx1, yf, 0.62, oxide)
                collide.append((sx0, yf - 0.85, 0.0, sx1, yf, 0.62))

    # Ground-floor front.
    if ground == "shop":
        ox0, ox1 = x0 + 0.45, x1 - 0.45
        mb.box(ox0, yf - 0.02, 0.45, ox1, yf, 2.75, dark, skip=("back",))
        mb.box(ox0 + 0.05, yf - 0.05, 1.75, ox1 - 0.05, yf - 0.02, 2.75, shutter, skip=("back",))
        for i in range(4):
            z = 1.85 + i * 0.24
            mb.box(ox0 + 0.05, yf - 0.08, z, ox1 - 0.05, yf - 0.05, z + 0.05, bars, skip=("back",))
        if awning:
            aw = rm.material(name + "_awning", awning, roughness=0.85, double_sided=True)
            extrude_x(mb, [(yf, 2.95), (yf - 1.5, 2.55), (yf - 1.5, 2.5), (yf, 2.88)], x0 + 0.15, x1 - 0.15, aw)
        if sign:
            sg = rm.material(name + "_sign", sign, roughness=0.6)
            mb.box(x0 + 0.3, yf - 0.12, 2.98, x1 - 0.3, yf, 3.32, sg, skip=("back",))
    else:
        mb.box(-0.5, yf - 0.06, 0.45, 0.5, yf, 2.55, wood, skip=("back",))            # door
        mb.box(-0.62, yf - 0.1, 2.55, 0.62, yf, 2.7, trim_m, skip=("back",))
        for u in (x0 + w * 0.22, x1 - w * 0.22):
            if abs(u) < 1.2:
                continue
            mb.box(u - 0.5, yf - 0.03, 1.1, u + 0.5, yf, 2.3, dark, skip=("back",))
            for b in range(5):
                bx = u - 0.4 + b * 0.2
                mb.box(bx - 0.02, yf - 0.06, 1.1, bx + 0.02, yf - 0.03, 2.3, bars, skip=("back",))
        mb.box(x0 + 0.3, yf - 0.55, 2.75, x1 - 0.3, yf, 2.83, trim_m)                  # chajja sunshade

    # Upper floors: windows with sunshades front and back, optional balcony.
    n_win = max(1, int(w / 2.6))
    for k in range(1, floors):
        zf = H0 + (k - 1) * FH
        for i in range(n_win):
            u = x0 + w * (i + 0.5) / n_win
            for side, plane in (("front", y0), ("back", y1)):
                if side == "front":
                    mb.box(u - 0.55, plane - 0.04, zf + 0.8, u + 0.55, plane, zf + 2.15, glass, skip=("back",))
                    mb.box(u - 0.7, plane - 0.45, zf + 2.3, u + 0.7, plane, zf + 2.38, trim_m)
                else:
                    mb.box(u - 0.5, plane, zf + 0.9, u + 0.5, plane + 0.04, zf + 2.1, glass, skip=("front",))
        if balcony and k == 1:
            mb.box(x0 + 0.4, y0 - 0.95, zf, x1 - 0.4, y0, zf + 0.14, trim_m)
            mb.box(x0 + 0.4, y0 - 0.95, zf + 0.95, x1 - 0.4, y0 - 0.88, zf + 1.02, bars)
            nb = int((w - 0.8) / 0.18)
            for b in range(nb + 1):
                bx = x0 + 0.42 + b * (w - 0.84) / nb
                mb.box(bx - 0.015, y0 - 0.94, zf + 0.14, bx + 0.015, y0 - 0.9, zf + 0.95, bars, skip=("top", "bottom"))

    # Roof.
    if roof == "tile":
        eave_f = y0 - 0.55
        eave_b = y1 + 0.45
        ridge = top + (eave_b - eave_f) * 0.27
        ym = (eave_f + eave_b) / 2
        extrude_x(mb, [(eave_f, top - 0.12), (ym, ridge), (eave_b, top - 0.12),
                       (eave_b, top - 0.02), (ym, ridge + 0.12), (eave_f, top - 0.02)],
                  x0 - 0.25, x1 + 0.25, tiles)
        for sx, nx in ((x0, -1), (x1, 1)):                       # gable walls
            mb.face([(sx, y0, top), (sx, ym, ridge - 0.05), (sx, y1, top)], wall, outward=Vector((nx, 0, 0)))
        mb.box(x0 - 0.3, ym - 0.12, ridge, x1 + 0.3, ym + 0.12, ridge + 0.2, ridge_m)
        collide.append((x0, y0, top, x1, y1, ridge))
    else:
        t = 0.18
        for (ax0, ay0, ax1, ay1) in ((x0, y0, x1, y0 + t), (x0, y1 - t, x1, y1),
                                     (x0, y0 + t, x0 + t, y1 - t), (x1 - t, y0 + t, x1, y1 - t)):
            mb.box(ax0, ay0, top, ax1, ay1, top + 0.8, trim_m, skip=("bottom",))
        mb.box(x0, y0, top, x1, y1, top + 0.02, plinth, skip=("bottom",))
        if tank:
            tm = rm.material("water_tank", "#1d1e20", roughness=0.55)
            mb.box_c(x1 - 1.4, y1 - 1.6, top, 1.2, 1.2, 0.35, trim_m)
            mb.cylinder(x1 - 1.4, y1 - 1.6, top + 0.35, 0.6, 0.6, 1.1, 10, tm)
        collide.append((x0, y0, top, x1, y1, top + 0.8))
    if rooftop_sign:
        sg = rm.material(name + "_roofsign", rooftop_sign, roughness=0.6)
        for px in (x0 + 0.8, x1 - 0.95):
            mb.box(px, y0 + 0.4, top, px + 0.15, y0 + 0.55, top + 3.0, bars)
        mb.box(x0 + 0.5, y0 + 0.3, top + 1.6, x1 - 0.5, y0 + 0.4, top + 3.2, sg)
    mb.build(name)
    box_collision(name, collide)
    rm.export_glb("buildings", name)


OT_BUILDINGS = {
    # houses (lanes): verandah fronts and clay-tile roofs
    "bld_ot_house_01": dict(w=6, d=10, floors=1, paint="#6fa8c8", trim="#f4efe4", ground="verandah", roof="tile", pillars=2),
    "bld_ot_house_02": dict(w=6, d=10, floors=2, paint="#e9a6b4", trim="#fbf3ea", ground="house", roof="flat", balcony=True, tank=True),
    "bld_ot_house_03": dict(w=8, d=10, floors=1, paint="#f0d36b", trim="#f7f1e3", ground="verandah", roof="tile", pillars=3),
    "bld_ot_house_04": dict(w=8, d=10, floors=2, paint="#9ccf8a", trim="#f4f1e6", ground="house", roof="tile"),
    "bld_ot_house_05": dict(w=10, d=12, floors=2, paint="#efe6d4", trim="#8a2f2a", ground="verandah", roof="tile", pillars=4),
    "bld_ot_house_06": dict(w=6, d=10, floors=1, paint="#c96f9e", trim="#f4efe4", ground="house", roof="tile"),
    "bld_ot_house_07": dict(w=8, d=10, floors=2, paint="#78c4b8", trim="#fbf6ec", ground="verandah", roof="flat", pillars=2, tank=True),
    # shops (main roads and busy lanes)
    "bld_ot_shop_01": dict(w=6, d=10, floors=2, paint="#d98c5f", trim="#f6ecdb", ground="shop", roof="flat", awning="#2f7d4f", sign="#1d6f8c", tank=True),
    "bld_ot_shop_02": dict(w=6, d=12, floors=3, paint="#78c4b8", trim="#f4f0e6", ground="shop", roof="flat", awning="#c23a2b", sign="#f2c230", balcony=True),
    "bld_ot_shop_03": dict(w=8, d=12, floors=2, paint="#c96f9e", trim="#fbf2ea", ground="shop", roof="flat", awning="#2c5fa8", sign="#efe6c8"),
    "bld_ot_shop_04": dict(w=10, d=12, floors=3, paint="#f0d36b", trim="#fbf5e6", ground="shop", roof="flat", awning="#7a2f8c", sign="#2a2f6b", balcony=True, rooftop_sign="#d8342b"),
    "bld_ot_shop_05": dict(w=8, d=10, floors=1, paint="#9ccf8a", trim="#f4f1e6", ground="shop", roof="tile", awning="#e2762b", sign="#5b3a8c"),
    "bld_ot_shop_06": dict(w=6, d=10, floors=2, paint="#6fa8c8", trim="#f4efe4", ground="shop", roof="flat", awning="#e9c43a", sign="#b8322a"),
    "bld_ot_lodge_01": dict(w=12, d=12, floors=4, paint="#f3efe6", trim="#2c6fb0", ground="shop", roof="flat", awning="#2c6fb0", sign="#2c6fb0", balcony=True, rooftop_sign="#ffb02e", tank=True),
}


def market_hall() -> None:
    name = "bld_ot_market_hall"
    rm.clear_scene()
    stone = rm.material("hall_stone", "#a39581", roughness=0.9)
    pillar = rm.material("hall_pillar", "#e9e2d2", roughness=0.85)
    tiles = rm.material("clay_tile", "#b5532f", roughness=0.85)
    ridge_m = rm.material("clay_ridge", "#7e3a22", roughness=0.85)
    beam = rm.material("hall_beam", "#5a3a22", roughness=0.8)
    w, d = 20.0, 14.0
    mb = rm.MeshBuilder()
    mb.frustum(0, 0, 0.0, w, d, w - 0.6, d - 0.6, LOT, stone)                 # bevelled floor slab
    cols = []
    for i in range(5):
        for j in range(3):
            x = -w / 2 + 1.0 + (w - 2.0) * i / 4
            y = -d / 2 + 1.0 + (d - 2.0) * j / 2
            mb.box_c(x, y, LOT, 0.45, 0.45, 4.2, pillar)
            cols.append((x - 0.23, y - 0.23, 0.0, x + 0.23, y + 0.23, 4.4))
    mb.box(-w / 2 + 0.6, -d / 2 + 0.6, 4.35, w / 2 - 0.6, d / 2 - 0.6, 4.6, beam)
    extrude_x(mb, [(-d / 2 - 1.0, 4.4), (0, 7.6), (d / 2 + 1.0, 4.4), (d / 2 + 1.0, 4.55), (0, 7.75), (-d / 2 - 1.0, 4.55)],
              -w / 2 - 0.8, w / 2 + 0.8, tiles)
    mb.box(-w / 2 - 0.9, -0.15, 7.65, w / 2 + 0.9, 0.15, 7.95, ridge_m)
    for sx, nx in ((-w / 2 - 0.8, -1), (w / 2 + 0.8, 1)):
        mb.face([(sx, -d / 2 - 1.0, 4.55), (sx, 0, 7.75), (sx, d / 2 + 1.0, 4.55)], beam, outward=Vector((nx, 0, 0)))
    mb.build(name)
    col = rm.CollisionSet(name)
    col.frustum(0, 0, 0.0, w, d, w - 0.6, d - 0.6, LOT)
    for c in cols:
        col.box(*c)
    col.box(-w / 2 - 0.8, -d / 2 - 1.0, 4.4, w / 2 + 0.8, d / 2 + 1.0, 7.8)
    col.build()
    rm.export_glb("buildings", name)


def mandapam() -> None:
    name = "bld_ot_mandapam"
    rm.clear_scene()
    granite = rm.material("granite", "#7d7468", roughness=0.9)
    pillar = rm.material("mandapam_pillar", "#cdbfa6", roughness=0.85)
    cream = rm.material("gopuram_cornice", "#efe6d2", roughness=0.8)
    gold = rm.material("kalasam_gold", "#d4a63a", roughness=0.35, metallic=0.9)
    w, d = 14.0, 10.0
    mb = rm.MeshBuilder()
    mb.frustum(0, 0, 0.0, w, d, w - 0.6, d - 0.6, LOT, granite)

    cols = []
    for i in range(5):
        for j in range(4):
            x = -w / 2 + 1.0 + (w - 2.0) * i / 4
            y = -d / 2 + 1.0 + (d - 2.0) * j / 3
            mb.box_c(x, y, LOT, 0.5, 0.5, 3.6, pillar)
            mb.box_c(x, y, 3.75, 0.75, 0.75, 0.25, granite)                     # capital
            cols.append((x - 0.25, y - 0.25, 0.0, x + 0.25, y + 0.25, 4.0))
    mb.box(-w / 2, -d / 2, 4.0, w / 2, d / 2, 4.5, granite)
    mb.box(-w / 2 - 0.3, -d / 2 - 0.3, 4.5, w / 2 + 0.3, d / 2 + 0.3, 4.65, cream)
    for i in range(14):                                                          # parapet merlons
        x = -w / 2 + 0.5 + i * (w - 1.0) / 13
        for y in (-d / 2, d / 2 - 0.4):
            mb.box(x - 0.2, y, 4.65, x + 0.2, y + 0.4, 5.15, cream)
    for x in (-w / 2 + 1.0, 0.0, w / 2 - 1.0):
        mb.sphere((x, 0, 5.0), 0.3, 8, 5, gold, squash=1.3)
        mb.cylinder(x, 0, 5.3, 0.06, 0.0, 0.5, 6, gold)
    mb.build(name)
    col = rm.CollisionSet(name)
    col.frustum(0, 0, 0.0, w, d, w - 0.6, d - 0.6, LOT)

    for c in cols:
        col.box(*c)
    col.box(-w / 2 - 0.3, -d / 2 - 0.3, 4.0, w / 2 + 0.3, d / 2 + 0.3, 5.2)
    col.build()
    rm.export_glb("buildings", name)


def vimana() -> None:
    """Central shrine of the temple: a moulded base, a stepped pyramidal tower and a dome."""
    name = "bld_ot_vimana"
    rm.clear_scene()
    granite = rm.material("granite", "#7d7468", roughness=0.9)
    cream = rm.material("gopuram_cornice", "#efe6d2", roughness=0.8)
    ochre = rm.material("vimana_ochre", "#d9a85a", roughness=0.85)
    red = rm.material("vimana_red", "#b8432f", roughness=0.85)
    gold = rm.material("kalasam_gold", "#d4a63a", roughness=0.35, metallic=0.9)
    dark = rm.material("shop_interior", "#17130f", roughness=0.95)
    mb = rm.MeshBuilder()
    mb.frustum(0, 0, 0.0, 11.0, 11.0, 10.4, 10.4, LOT, granite)
    mb.box_c(0, 0, LOT, 10.0, 10.0, 1.0, granite)
    mb.box_c(0, 0, 1.15, 9.0, 9.0, 4.6, ochre)
    for z in (1.15, 3.2, 5.6):
        mb.box_c(0, 0, z, 9.3, 9.3, 0.18, cream)
    for i in range(3):                                   # niches on each face
        u = -3.0 + i * 3.0
        for side in range(4):
            start = mb.mark()
            mb.box(u - 0.6, -4.55, 2.0, u + 0.6, -4.5, 4.6, red)
            mb.transform_since(start, Matrix.Rotation(side * math.pi / 2, 4, "Z"))
    mb.box(-1.0, -5.6, LOT, 1.0, -4.5, 3.4, granite)     # entrance porch
    mb.box(-0.7, -5.62, 1.15, 0.7, -5.58, 3.0, dark)
    z, size = 5.75, 8.6
    for tier in range(5):
        h = 2.2 - tier * 0.15
        mb.frustum(0, 0, z, size, size, size - 0.6, size - 0.6, h, ochre if tier % 2 == 0 else red)
        mb.box_c(0, 0, z + h, size - 0.3, size - 0.3, 0.2, cream)
        z += h + 0.2
        size -= 1.35
    mb.cylinder(0, 0, z, size * 0.5, size * 0.5, 0.6, 8, cream)
    mb.sphere((0, 0, z + 1.6), 1.5, 10, 6, ochre, squash=0.9)
    mb.cylinder(0, 0, z + 2.9, 0.35, 0.05, 1.4, 8, gold)
    mb.sphere((0, 0, z + 3.0), 0.35, 8, 5, gold, squash=1.3)
    mb.build(name)
    col = rm.CollisionSet(name)
    col.frustum(0, 0, 0.0, 11.0, 11.0, 10.4, 10.4, LOT)
    col.box(-5.0, -5.0, 0.0, 5.0, 5.0, z + 3.0)
    col.box(-1.0, -5.6, 0.0, 1.0, -4.5, 3.4)
    col.build()
    rm.export_glb("buildings", name)


def tank() -> None:
    """Temple tank: a square stepped pond with a small pavilion in the middle, fenced off."""
    name = "bld_ot_tank"
    rm.clear_scene()
    granite = rm.material("granite", "#7d7468", roughness=0.9)
    step_b = rm.material("tank_step", "#8c8274", roughness=0.9)
    water = rm.material("tank_water", "#2f6d6a", roughness=0.08, metallic=0.2)
    rail = rm.material("tank_rail", "#2c2e33", roughness=0.5, metallic=0.6)
    cream = rm.material("gopuram_cornice", "#efe6d2", roughness=0.8)
    pillar = rm.material("mandapam_pillar", "#cdbfa6", roughness=0.85)
    half = 15.0
    mb = rm.MeshBuilder()
    col = rm.CollisionSet(name)
    # Coping at lot level, then 6 steps down towards the water.
    mb.box(-half, -half, -0.25, half, -half + 1.0, 0.0, granite, skip=("bottom",))
    mb.box(-half, half - 1.0, -0.25, half, half, 0.0, granite, skip=("bottom",))
    mb.box(-half, -half + 1.0, -0.25, -half + 1.0, half - 1.0, 0.0, granite, skip=("bottom",))
    mb.box(half - 1.0, -half + 1.0, -0.25, half, half - 1.0, 0.0, granite, skip=("bottom",))
    r = half - 1.0
    z = 0.0
    for s in range(6):
        z_next = z - 0.4
        mat = step_b if s % 2 == 0 else granite
        for (ax0, ay0, ax1, ay1) in ((-r, -r, r, -r + 1.0), (-r, r - 1.0, r, r),
                                     (-r, -r + 1.0, -r + 1.0, r - 1.0), (r - 1.0, -r + 1.0, r, r - 1.0)):
            mb.box(ax0, ay0, z_next - 0.4, ax1, ay1, z_next, mat, skip=("bottom",))
        # The riser faces of this step (vertical walls facing the middle).
        r -= 1.0
        z = z_next
    flat(mb, -11.0, -11.0, 11.0, 11.0, -1.45, water)   # covers the lower three steps
    # Central pavilion on a plinth rising out of the water.
    mb.box_c(0, 0, z - 0.5, 5.0, 5.0, 1.2 - z, granite)
    for x in (-1.9, 1.9):
        for y in (-1.9, 1.9):
            mb.box_c(x, y, 0.7, 0.4, 0.4, 2.6, pillar)
    mb.box_c(0, 0, 3.3, 5.2, 5.2, 0.35, granite)
    mb.frustum(0, 0, 3.65, 4.2, 4.2, 1.0, 1.0, 1.6, cream)
    # Railing around the edge.
    for (ax0, ay0, ax1, ay1) in ((-half, -half, half, -half + 0.08), (-half, half - 0.08, half, half),
                                 (-half, -half, -half + 0.08, half), (half - 0.08, -half, half, half)):
        mb.box(ax0, ay0, 0.85, ax1, ay1, 0.92, rail)
        col.box(ax0, ay0, 0.0, ax1, ay1, 1.0)
    for i in range(16):
        t = -half + i * (2 * half) / 15
        for (px, py) in ((t, -half + 0.04), (t, half - 0.04), (-half + 0.04, t), (half - 0.04, t)):
            mb.box_c(px, py, 0.0, 0.06, 0.06, 0.92, rail)
    mb.build(name)
    col.build()
    rm.export_glb("buildings", name)


BUILDERS = {
    "road_main_seg": road_main_seg,
    "road_lane_seg": road_lane_seg,
    "road_junction_mm": lambda: road_junction("road_junction_mm", 12.0, 12.0),
    "road_junction_ml": lambda: road_junction("road_junction_ml", 12.0, 8.0),
    "road_junction_ll": lambda: road_junction("road_junction_ll", 8.0, 8.0),
    "road_zebra_main": lambda: road_zebra("road_zebra_main", 12.0, 4.0),
    "road_zebra_lane": lambda: road_zebra("road_zebra_lane", 8.0, 3.0),
    "road_walk_main": lambda: road_walk("road_walk_main", 4.0),
    "road_walk_lane": lambda: road_walk("road_walk_lane", 2.0),
    "road_walk_corner": road_walk_corner,
    "prop_signal_pole": prop_signal_pole,
    "prop_market_stall_a": lambda: prop_market_stall("prop_market_stall_a", "#d8342b", "#f2c230"),
    "prop_market_stall_b": lambda: prop_market_stall("prop_market_stall_b", "#2c6fb0", "#e8822a"),
    "prop_flower_stall": prop_flower_stall,
    "prop_handcart": prop_handcart,
    "prop_bollard": prop_bollard,
    "prop_neem_tree": prop_neem_tree,
    "bld_ot_market_hall": market_hall,
    "bld_ot_mandapam": mandapam,
    "bld_ot_vimana": vimana,
    "bld_ot_tank": tank,
}
for _name, _params in OT_BUILDINGS.items():
    BUILDERS[_name] = (lambda n=_name, p=_params: ot_building(n, **p))


def main() -> None:
    for name in (rm.script_args() or list(BUILDERS)):
        BUILDERS[name]()


main()
