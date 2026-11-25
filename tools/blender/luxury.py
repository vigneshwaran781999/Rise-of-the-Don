"""Luxury District kit (M7) -> assets/models/buildings/, props/

Velanagar's villas and mansions (GDD §2 district 5): clean, quiet, guarded. Each villa model is a
whole walled plot (28 x 24 m: compound wall with a gate at the front, lawn, the house, a pool),
so a row of plots lines a street. Pivot at the base centre, front (the gate) facing Blender -Y.
Material names with night glow: window_glass, lamp_lens, neon_* (see scripts/world/kit_baker.gd).

  bld_lx_villa_a       white modern villa: two storeys, flat roofs, big glass, pool at the side
  bld_lx_villa_b       sand-coloured villa with a tiled hip roof and a portico
  bld_lx_villa_c       grey and timber villa: a cantilevered upper floor over a glass ground floor
  bld_lx_mansion       the estate: 60 x 48 m walled grounds, a three-storey mansion with columns,
                       a fountain court, gatehouse, garages
  prop_lx_guard_booth  guard booth at a gated road
  prop_lx_hedge        6 m clipped hedge (lines the park)

Run:  "$BLENDER" --background --factory-startup --python tools/blender/luxury.py [-- names...]
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rotd_mesh as rm  # noqa: E402

FH = 3.0
PW, PD = 28.0, 24.0     # plot width (frontage) and depth


def compound(mb, col, x0, y0, x1, y1, wall, cap, gate_w: float, gate, lamp) -> None:
    """A 1.8 m compound wall round a plot with a gate gap at the front middle, pillars and lamps
    either side of the gate, and the gate itself (closed, slatted)."""
    h, t = 1.8, 0.25
    gx0, gx1 = -gate_w / 2, gate_w / 2
    segs = [(x0, y0, gx0 - 0.4, y0 + t), (gx1 + 0.4, y0, x1, y0 + t),
            (x0, y1 - t, x1, y1), (x0, y0 + t, x0 + t, y1 - t), (x1 - t, y0 + t, x1, y1 - t)]
    for (ax0, ay0, ax1, ay1) in segs:
        mb.box(ax0, ay0, 0.0, ax1, ay1, h, wall, skip=("bottom",))
        mb.box(ax0 - 0.05, ay0 - 0.05, h, ax1 + 0.05, ay1 + 0.05, h + 0.12, cap)
        col.box(ax0, ay0, 0.0, ax1, ay1, h)
    for px in (gx0 - 0.4, gx1):
        mb.box(px, y0 - 0.1, 0.0, px + 0.4, y0 + t + 0.1, 2.3, wall, skip=("bottom",))
        mb.box(px + 0.08, y0 - 0.02, 2.3, px + 0.32, y0 + 0.27, 2.6, lamp)
        col.box(px, y0 - 0.1, 0.0, px + 0.4, y0 + t + 0.1, 2.3)
    n = int(gate_w / 0.25)
    for i in range(n):
        x = gx0 + (i + 0.5) * gate_w / n
        mb.box(x - 0.04, y0 + 0.08, 0.1, x + 0.04, y0 + 0.16, 1.7, gate, skip=("bottom",))
    mb.box(gx0, y0 + 0.06, 1.55, gx1, y0 + 0.18, 1.65, gate)
    mb.box(gx0, y0 + 0.06, 0.25, gx1, y0 + 0.18, 0.35, gate)
    col.box(gx0, y0 + 0.06, 0.0, gx1, y0 + 0.18, 1.7)


def plot_ground(mb, x0, y0, x1, y1, lawn, drive, gate_w: float) -> None:
    mb.box(x0 + 0.25, y0 + 0.25, 0.0, x1 - 0.25, y1 - 0.25, 0.04, lawn, skip=("bottom",))
    mb.box(-gate_w / 2, y0 + 0.25, 0.0, gate_w / 2, y0 + 7.0, 0.06, drive, skip=("bottom",))


def pool(mb, cx, cy, w, d, edge, water) -> None:
    mb.box(cx - w / 2 - 0.6, cy - d / 2 - 0.6, 0.0, cx + w / 2 + 0.6, cy + d / 2 + 0.6, 0.12, edge, skip=("bottom",))
    mb.box(cx - w / 2, cy - d / 2, 0.0, cx + w / 2, cy + d / 2, 0.13, water, skip=("bottom",))


def materials(prefix: str, wall_col: str) -> dict:
    return {
        "wall": rm.material(prefix + "_wall", wall_col, roughness=0.75),
        "compound": rm.material("lx_compound", "#ece6da", roughness=0.85),
        "cap": rm.material("lx_wall_cap", "#8f8778", roughness=0.8),
        "gate": rm.material("lx_gate_black", "#1e1f22", roughness=0.45, metallic=0.6),
        "lamp": rm.material("lamp_lens", "#f6e6b0", roughness=0.2, emission="#fff1c0", emission_strength=2.0),
        "lawn": rm.material("lx_lawn", "#4f8a3a", roughness=0.95),
        "drive": rm.material("lx_drive_paving", "#b9b2a6", roughness=0.85),
        "glass": rm.material("window_glass", "#2a3644", roughness=0.18, metallic=0.35),
        "edge": rm.material("lx_pool_edge", "#eae7e0", roughness=0.6),
        "water": rm.material("lx_pool_water", "#2fb3d8", roughness=0.05, metallic=0.1),
        "trim": rm.material("lx_trim_dark", "#2c2e33", roughness=0.5, metallic=0.4),
        "glow": rm.material("neon_villa", "#c9b48a", roughness=0.2, emission="#ffd9a0", emission_strength=0.45),
    }


def villa_a() -> None:
    """White modern villa: two boxes (the upper one offset), big glass, a roof terrace rail, the
    pool beside the lawn."""
    name = "bld_lx_villa_a"
    rm.clear_scene()
    m = materials(name, "#f4f2ec")
    mb = rm.MeshBuilder()
    col = rm.CollisionSet(name)
    x0, y0, x1, y1 = -PW / 2, -PD / 2, PW / 2, PD / 2
    plot_ground(mb, x0, y0, x1, y1, m["lawn"], m["drive"], 4.0)
    compound(mb, col, x0, y0, x1, y1, m["compound"], m["cap"], 4.0, m["gate"], m["lamp"])
    hx0, hy0, hx1, hy1 = -9.0, -2.0, 7.0, 10.0
    mb.box(hx0, hy0, 0.0, hx1, hy1, FH + 0.3, m["wall"], skip=("bottom",))
    mb.box(hx0 + 1.0, hy0 - 0.04, 0.3, hx1 - 4.0, hy0, 2.8, m["glow"], skip=("back",))      # glass front, lit at night
    mb.box(-5.0, hy0 - 1.5, FH + 0.3, 11.0, hy1, 2 * FH + 0.4, m["wall"], skip=("bottom",))
    mb.box(-4.0, hy0 - 1.54, FH + 1.0, 4.0, hy0 - 1.5, 2 * FH - 0.3, m["glass"], skip=("back",))
    mb.box(hx0, hy0, FH + 0.3, -5.0, hy0 + 0.08, FH + 1.3, m["trim"])                         # terrace rail
    mb.box(-5.4, hy0 - 1.9, 2 * FH + 0.4, 11.4, hy1 + 0.3, 2 * FH + 0.7, m["wall"])          # roof slab
    pool(mb, 10.5, -5.5, 4.0, 7.0, m["edge"], m["water"])
    mb.build(name)
    col.box(hx0, hy0, 0.0, hx1, hy1, FH + 0.3)
    col.box(-5.0, hy0 - 1.5, FH + 0.3, 11.0, hy1, 2 * FH + 0.7)
    col.build()
    rm.export_glb("buildings", name)


def villa_b() -> None:
    """Sand-coloured villa: a hip roof of clay tiles, a portico of four columns at the door."""
    name = "bld_lx_villa_b"
    rm.clear_scene()
    m = materials(name, "#e6d2a8")
    tile = rm.material("clay_tile", "#b5532f", roughness=0.85)
    white = rm.material("lx_column_white", "#f7f4ec", roughness=0.7)
    mb = rm.MeshBuilder()
    col = rm.CollisionSet(name)
    x0, y0, x1, y1 = -PW / 2, -PD / 2, PW / 2, PD / 2
    plot_ground(mb, x0, y0, x1, y1, m["lawn"], m["drive"], 4.0)
    compound(mb, col, x0, y0, x1, y1, m["compound"], m["cap"], 4.0, m["gate"], m["lamp"])
    hx0, hy0, hx1, hy1 = -8.0, 0.0, 8.0, 10.0
    top = 2 * FH + 0.4
    mb.box(hx0, hy0, 0.0, hx1, hy1, top, m["wall"], skip=("bottom",))
    for k in range(2):
        for u in (-5.5, -2.0, 2.0, 5.5):
            mb.box(u - 0.7, hy0 - 0.04, k * FH + 0.8, u + 0.7, hy0, k * FH + 2.5, m["glass"] if k else m["glow"], skip=("back",))
    mb.frustum(0.0, (hy0 + hy1) / 2, top, 17.2, 11.2, 4.0, 0.6, 2.6, tile, bottom=True)            # hip roof
    mb.box(-3.0, hy0 - 3.0, 0.0, 3.0, hy0, 0.15, white, skip=("bottom",))                       # portico
    for u in (-2.6, -1.0, 0.7, 2.3):
        mb.cylinder(u + 0.15, hy0 - 2.6, 0.15, 0.2, 0.2, FH + 0.2, 8, white)
    mb.box(-3.2, hy0 - 3.2, FH + 0.35, 3.2, hy0, FH + 0.8, white)
    pool(mb, -9.0, -4.5, 3.5, 6.0, m["edge"], m["water"])
    mb.build(name)
    col.box(hx0, hy0, 0.0, hx1, hy1, top + 2.6)
    col.box(-3.2, hy0 - 3.2, FH + 0.35, 3.2, hy0, FH + 0.8)
    col.build()
    rm.export_glb("buildings", name)


def villa_c() -> None:
    """Grey and timber villa: a glass ground floor under a cantilevered timber-clad upper floor."""
    name = "bld_lx_villa_c"
    rm.clear_scene()
    m = materials(name, "#7c8086")
    timber = rm.material("lx_timber", "#8a5a36", roughness=0.75)
    mb = rm.MeshBuilder()
    col = rm.CollisionSet(name)
    x0, y0, x1, y1 = -PW / 2, -PD / 2, PW / 2, PD / 2
    plot_ground(mb, x0, y0, x1, y1, m["lawn"], m["drive"], 4.0)
    compound(mb, col, x0, y0, x1, y1, m["compound"], m["cap"], 4.0, m["gate"], m["lamp"])
    mb.box(-6.0, 1.0, 0.0, 6.0, 10.0, FH, m["glow"], skip=("bottom",))
    mb.box(-6.5, 1.0, 0.0, -6.0, 10.0, FH, m["wall"], skip=("bottom",))
    mb.box(6.0, 1.0, 0.0, 6.5, 10.0, FH, m["wall"], skip=("bottom",))
    mb.box(-10.0, -2.0, FH, 8.0, 10.5, 2 * FH + 0.3, timber, skip=())
    for u in (-7.0, -2.0, 3.0):
        mb.box(u - 1.6, -2.04, FH + 0.8, u + 1.6, -2.0, 2 * FH - 0.4, m["glass"], skip=("back",))
    mb.box(-10.3, -2.3, 2 * FH + 0.3, 8.3, 10.8, 2 * FH + 0.6, m["wall"])
    pool(mb, 9.5, -4.0, 4.0, 8.0, m["edge"], m["water"])
    mb.build(name)
    col.box(-6.5, 1.0, 0.0, 6.5, 10.0, FH)
    col.box(-10.0, -2.0, FH, 8.0, 10.5, 2 * FH + 0.6)
    col.build()
    rm.export_glb("buildings", name)


def mansion() -> None:
    """The estate: 60 x 48 m walled grounds with a gatehouse at the gate, a drive round a fountain,
    a three-storey mansion with a colonnade and a pediment, two garages."""
    name = "bld_lx_mansion"
    rm.clear_scene()
    m = materials(name, "#efe7d6")
    white = rm.material("lx_column_white", "#f7f4ec", roughness=0.7)
    roof = rm.material("lx_slate_roof", "#4a4f57", roughness=0.7)
    stone = rm.material("dt_granite", "#5c5652", roughness=0.6)
    water = m["water"]
    mb = rm.MeshBuilder()
    col = rm.CollisionSet(name)
    x0, y0, x1, y1 = -30.0, -24.0, 30.0, 24.0
    plot_ground(mb, x0, y0, x1, y1, m["lawn"], m["drive"], 6.0)
    compound(mb, col, x0, y0, x1, y1, m["compound"], m["cap"], 6.0, m["gate"], m["lamp"])
    mb.box(-12.0, y0 + 6.0, 0.0, 12.0, y0 + 22.0, 0.07, m["drive"], skip=("bottom",))         # forecourt
    mb.cylinder(0.0, y0 + 14.0, 0.0, 3.2, 3.2, 0.6, 14, stone)                                 # fountain
    mb.cylinder(0.0, y0 + 14.0, 0.0, 2.9, 2.9, 0.62, 14, water)
    mb.cylinder(0.0, y0 + 14.0, 0.62, 0.5, 0.3, 1.8, 8, stone)
    hx0, hy0, hx1, hy1 = -18.0, 0.0, 18.0, 16.0
    top = 3 * FH + 1.0
    mb.box(hx0, hy0, 0.0, hx1, hy1, top, m["wall"], skip=("bottom",))
    for k in range(3):
        for i in range(9):
            u = hx0 + 2.0 + i * 4.0
            mat = m["glow"] if k == 0 else m["glass"]
            mb.box(u - 0.8, hy0 - 0.04, k * FH + 1.0, u + 0.8, hy0, k * FH + 2.8, mat, skip=("back",))
    mb.box(-7.0, hy0 - 4.0, 0.0, 7.0, hy0, 0.4, white, skip=("bottom",))                       # colonnade
    for i in range(6):
        u = -6.0 + i * 2.4
        mb.cylinder(u, hy0 - 3.4, 0.4, 0.35, 0.3, 2 * FH, 10, white)
    mb.box(-7.3, hy0 - 4.3, 2 * FH + 0.4, 7.3, hy0, 2 * FH + 1.0, white)
    mb.prism([(hy0 - 4.3, 2 * FH + 1.0), (hy0 - 2.1, 2 * FH + 3.2), (hy0 + 0.1, 2 * FH + 1.0)], "X", -7.3, 7.3, white)
    mb.frustum(0.0, (hy0 + hy1) / 2, top, 37.0, 17.0, 26.0, 6.0, 3.2, roof, bottom=True)
    mb.box(hx0 - 0.2, hy0 - 0.2, top - 0.6, hx1 + 0.2, hy1 + 0.2, top, white)
    for gx in (-24.0, 24.0):                                                                    # garages
        mb.box(gx - 4.0, 4.0, 0.0, gx + 4.0, 14.0, FH + 0.4, m["wall"], skip=("bottom",))
        mb.box(gx - 3.0, 3.96, 0.0, gx + 3.0, 4.0, 2.6, m["trim"], skip=("back",))
    mb.box(-14.0, y0 + 0.6, 0.0, -9.0, y0 + 5.0, 3.0, m["wall"], skip=("bottom",))            # gatehouse
    mb.box(-13.5, y0 + 0.56, 1.0, -9.5, y0 + 0.6, 2.4, m["glow"], skip=("back",))
    mb.box(-14.3, y0 + 0.3, 3.0, -8.7, y0 + 5.3, 3.3, roof)
    mb.build(name)
    col.box(hx0, hy0, 0.0, hx1, hy1, top + 3.2)
    col.box(-7.3, hy0 - 4.3, 0.0, 7.3, hy0, 2 * FH + 1.0)
    col.box(-3.2, y0 + 10.8, 0.0, 3.2, y0 + 17.2, 0.6)
    for gx in (-24.0, 24.0):
        col.box(gx - 4.0, 4.0, 0.0, gx + 4.0, 14.0, FH + 0.4)
    col.box(-14.0, y0 + 0.6, 0.0, -9.0, y0 + 5.0, 3.3)
    col.build()
    rm.export_glb("buildings", name)


def guard_booth() -> None:
    name = "prop_lx_guard_booth"
    rm.clear_scene()
    wall = rm.material("lx_column_white", "#f7f4ec", roughness=0.7)
    glass = rm.material("window_glass", "#2a3644", roughness=0.18, metallic=0.35)
    roof = rm.material("lx_slate_roof", "#4a4f57", roughness=0.7)
    stripe = rm.material("lx_barrier_red", "#c8402e", roughness=0.6)
    lamp = rm.material("lamp_lens", "#f6e6b0", roughness=0.2, emission="#fff1c0", emission_strength=2.0)
    mb = rm.MeshBuilder()
    mb.box(-1.2, -1.2, 0.0, 1.2, 1.2, 1.0, wall, skip=("bottom",))
    mb.box(-1.2, -1.2, 1.0, 1.2, 1.2, 2.3, glass)
    mb.box(-1.5, -1.5, 2.3, 1.5, 1.5, 2.6, roof)
    mb.box(-0.2, -0.2, 2.6, 0.2, 0.2, 2.8, lamp)
    mb.box(1.2, -0.15, 0.0, 1.5, 0.15, 1.1, wall, skip=("bottom",))
    for i in range(6):                                          # the barrier arm, red and white
        mb.box(1.5 + i * 0.9, -0.06, 0.95, 2.4 + i * 0.9, 0.06, 1.05, stripe if i % 2 == 0 else wall)
    mb.build(name)
    col = rm.CollisionSet(name)
    col.box(-1.5, -1.5, 0.0, 1.5, 1.5, 2.6)
    col.build()
    rm.export_glb("props", name)


def hedge() -> None:
    name = "prop_lx_hedge"
    rm.clear_scene()
    leaf = rm.material("lx_hedge", "#2f6b33", roughness=0.95)
    mb = rm.MeshBuilder()
    mb.box(-3.0, -0.5, 0.0, 3.0, 0.5, 1.3, leaf, skip=("bottom",))
    mb.build(name)
    col = rm.CollisionSet(name)
    col.box(-3.0, -0.5, 0.0, 3.0, 0.5, 1.3)
    col.build()
    rm.export_glb("props", name)


BUILDERS = {
    "bld_lx_villa_a": villa_a,
    "bld_lx_villa_b": villa_b,
    "bld_lx_villa_c": villa_c,
    "bld_lx_mansion": mansion,
    "prop_lx_guard_booth": guard_booth,
    "prop_lx_hedge": hedge,
}


def main() -> None:
    for name in (rm.script_args() or list(BUILDERS)):
        BUILDERS[name]()


main()
