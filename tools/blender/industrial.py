"""Industrial Zone kit (M7) -> assets/models/buildings/, props/

Velanagar's factories, warehouses and harbour (GDD §2 district 4): grey and rust by day, sodium
orange at night. Every model has its pivot at the base centre and its front facing Blender -Y.
Material names with night glow: window_glass, lamp_lens, neon_* (see scripts/world/kit_baker.gd).

  bld_in_warehouse_a    30 x 20 m corrugated warehouse, 9 m, two roll-up doors and a loading dock
  bld_in_warehouse_b    24 x 16 m smaller warehouse, rust red
  bld_in_factory        36 x 24 m brick factory with a sawtooth roof and a 32 m chimney
  bld_in_office         10 x 12 m two-storey site office
  bld_in_police         10 x 12 m police post (same footprint as the office), POLICE board
  bld_in_tanks          24 x 12 m tank farm: three storage tanks on a bund
  bld_in_crane          ship-to-shore gantry crane: 16 m between its legs, boom 52 m out over
                        the water (Blender -Y), 46 m tall; red warning lights at night
  bld_in_ship           108 x 20 m cargo ship (bow towards Blender -Y), deck loaded with
                        containers, bridge at the stern
  bld_in_fish_shed      20 x 10 m open fish-market shed for the fishing harbour
  prop_in_container_a/b/c  12.2 m shipping containers: red, blue, teal
  prop_streetlight_sodium  the city's streetlight with an orange sodium lens

Run:  "$BLENDER" --background --factory-startup --python tools/blender/industrial.py [-- names...]
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


def ribs(mb, x0, x1, plane, out, z0, z1, mat, step: float = 1.2) -> None:
    """Vertical ribs of corrugated cladding on a face at y = plane (out = -1 front, 1 back)."""
    n = max(1, int((x1 - x0) / step))
    for i in range(n + 1):
        x = x0 + (x1 - x0) * i / n
        if out < 0:
            mb.box(x - 0.05, plane - 0.08, z0, x + 0.05, plane, z1, mat, skip=("back", "bottom"))
        else:
            mb.box(x - 0.05, plane, z0, x + 0.05, plane + 0.08, z1, mat, skip=("front", "bottom"))


def shed(mb, x0, y0, x1, y1, h, rise, wall, rib, roof) -> None:
    """A clad shed: walls with ribs front and back, a shallow pitched roof (ridge along X)."""
    mb.box(x0, y0, 0.0, x1, y1, h, wall, skip=("bottom",))
    ribs(mb, x0 + 0.3, x1 - 0.3, y0, -1, 0.0, h, rib)
    ribs(mb, x0 + 0.3, x1 - 0.3, y1, 1, 0.0, h, rib)
    ym = (y0 + y1) / 2
    mb.prism([(y0 - 0.4, h - 0.1), (ym, h + rise), (y1 + 0.4, h - 0.1)], "X", x0 - 0.3, x1 + 0.3, roof)


def roll_door(mb, cx, y_front, w, h, frame, door) -> None:
    mb.box(cx - w / 2 - 0.25, y_front - 0.12, 0.0, cx + w / 2 + 0.25, y_front, h + 0.25, frame, skip=("back", "bottom"))
    mb.box(cx - w / 2, y_front - 0.16, 0.0, cx + w / 2, y_front - 0.12, h, door, skip=("back", "bottom"))
    k = 0.0
    while k < h:
        mb.box(cx - w / 2, y_front - 0.2, k, cx + w / 2, y_front - 0.16, k + 0.06, frame, skip=("back",))
        k += 0.45


def warehouse(name: str, w: float, d: float, h: float, paint: str, rib_col: str, doors: int) -> None:
    rm.clear_scene()
    wall = rm.material(name + "_wall", paint, roughness=0.6, metallic=0.3)
    rib = rm.material(name + "_rib", rib_col, roughness=0.55, metallic=0.35)
    roof = rm.material("in_roof_grey", "#8e9399", roughness=0.6, metallic=0.4)
    frame = rm.material("in_frame_dark", "#33363b", roughness=0.5, metallic=0.5)
    door = rm.material("in_door_grey", "#a7abb0", roughness=0.45, metallic=0.5)
    concrete = rm.material("in_concrete", "#9c9a94", roughness=0.9)
    lamp = rm.material("lamp_lens", "#f6c27a", roughness=0.2, emission="#ffb050", emission_strength=3.0)
    glass = rm.material("window_glass", "#2a3644", roughness=0.18, metallic=0.35)
    mb = rm.MeshBuilder()
    x0, y0, x1, y1 = -w / 2, -d / 2, w / 2, d / 2
    shed(mb, x0, y0 + 1.2, x1, y1, h, 1.6, wall, rib, roof)
    mb.box(x0, y0, 0.0, x1, y0 + 1.2, 1.1, concrete, skip=("bottom",))           # loading dock
    for i in range(doors):
        cx = x0 + w * (i + 0.5) / doors
        roll_door(mb, cx, y0 + 1.2, 4.0, 4.6, frame, door)
        mb.box(cx - 0.3, y0 + 1.0, 5.3, cx + 0.3, y0 + 1.2, 5.6, lamp)
    for i in range(int(w / 6)):                                                   # clerestory windows
        cx = x0 + 3.0 + i * 6.0
        mb.box(cx - 1.5, y0 + 1.14, h - 1.6, cx + 1.5, y0 + 1.2, h - 0.6, glass, skip=("back",))
    mb.build(name)
    collide(name, [(x0, y0 + 1.2, 0.0, x1, y1, h + 1.6), (x0, y0, 0.0, x1, y0 + 1.2, 1.1)])
    rm.export_glb("buildings", name)


def factory() -> None:
    """Brick factory: a sawtooth (north-light) roof of five bays, a tall brick chimney with a red
    warning light at the top, pipework along the front."""
    name = "bld_in_factory"
    rm.clear_scene()
    brick = rm.material("in_brick", "#9a5440", roughness=0.9)
    glass = rm.material("window_glass", "#2a3644", roughness=0.18, metallic=0.35)
    roof = rm.material("in_roof_grey", "#8e9399", roughness=0.6, metallic=0.4)
    pipe = rm.material("in_pipe_steel", "#8c9298", roughness=0.4, metallic=0.7)
    frame = rm.material("in_frame_dark", "#33363b", roughness=0.5, metallic=0.5)
    door = rm.material("in_door_grey", "#a7abb0", roughness=0.45, metallic=0.5)
    band = rm.material("in_chimney_band", "#e9e4da", roughness=0.8)
    red = rm.material("neon_red", "#7a1a1a", roughness=0.4, emission="#ff2a1a", emission_strength=4.0)
    mb = rm.MeshBuilder()
    x0, y0, x1, y1 = -18.0, -12.0, 18.0, 12.0
    h = 8.0
    mb.box(x0, y0, 0.0, x1, y1, h, brick, skip=("bottom",))
    bays = 5
    for i in range(bays):                                     # sawtooth: steep glazed face to the back
        ya = y0 + (y1 - y0) * i / bays
        yb = y0 + (y1 - y0) * (i + 1) / bays
        mb.prism([(ya, h), (yb, h + 3.0), (yb, h)], "X", x0, x1, roof)
        mb.box(x0 + 0.5, yb - 0.02, h + 0.3, x1 - 0.5, yb + 0.02, h + 2.7, glass)
    for i in range(6):
        cx = x0 + 3.0 + i * 6.0
        mb.box(cx - 1.4, y0 - 0.04, 3.0, cx + 1.4, y0, 6.4, glass, skip=("back",))
    roll_door(mb, x1 - 5.0, y0, 5.0, 5.0, frame, door)
    mb.tube((x0, y0 - 0.8, 7.0), (x1 - 8.0, y0 - 0.8, 7.0), 0.35, 0.35, 8, pipe)
    mb.tube((x0 + 2.0, y0 - 0.8, 7.0), (x0 + 2.0, y0 - 0.8, 0.0), 0.35, 0.35, 8, pipe)
    cx, cy = x0 + 4.0, y1 - 4.0                                # chimney
    mb.cylinder(cx, cy, h, 1.8, 1.2, 24.0, 12, brick)
    mb.cylinder(cx, cy, h + 20.0, 1.33, 1.25, 1.5, 12, band)
    mb.box(cx - 0.25, cy - 0.25, h + 24.0, cx + 0.25, cy + 0.25, h + 24.4, red)
    mb.build(name)
    col = rm.CollisionSet(name)
    col.box(x0, y0, 0.0, x1, y1, h + 3.0)
    col.frustum(cx, cy, h, 3.6, 3.6, 2.4, 2.4, 24.0)
    col.build()
    rm.export_glb("buildings", name)


def office(name: str, wall_col: str, sign: str | None) -> None:
    rm.clear_scene()
    wall = rm.material(name + "_wall", wall_col, roughness=0.8)
    blue = rm.material("police_blue", "#1f4fa0", roughness=0.6)
    glass = rm.material("office_glass_blue", "#35597a", roughness=0.12, metallic=0.5)
    lobby = rm.material("neon_lobby", "#c9b48a", roughness=0.2, emission="#ffd9a0", emission_strength=0.5)
    trim = rm.material("in_frame_dark", "#33363b", roughness=0.5, metallic=0.5)
    letters = rm.material("sign_letters", "#f4f1e8", roughness=0.6)
    mb = rm.MeshBuilder()
    x0, y0, x1, y1 = -5.0, -6.0, 5.0, 6.0
    top = 2 * FH + 0.5
    mb.box(x0, y0, 0.0, x1, y1, top, wall, skip=("bottom",))
    mb.box(-1.2, y0 - 0.05, 0.0, 1.2, y0, 2.6, lobby, skip=("back",))
    for k in range(2):
        for u in ((-3.2, 3.2) if k == 0 else (-3.2, 0.0, 3.2)):
            mb.box(u - 0.9, y0 - 0.04, k * FH + 0.9, u + 0.9, y0, k * FH + 2.3, glass, skip=("back",))
        for u in (-2.5, 2.5):
            mb.box(u - 0.9, y1, k * FH + 0.9, u + 0.9, y1 + 0.04, k * FH + 2.3, glass, skip=("front",))
    accent = blue if sign else trim
    mb.box(-2.0, y0 - 1.5, 2.8, 2.0, y0, 3.0, accent)
    mb.box(x0, y0, top, x1, y1, top + 0.6, accent, skip=("bottom",))
    if sign:
        mb.box(x0 + 0.6, y0 - 0.15, top + 0.8, x1 - 0.6, y0, top + 2.4, blue)
        rm.pixel_text(mb, sign, 0.0, y0 - 0.15, top + 1.05, 0.2, letters)
    mb.build(name)
    collide(name, [(x0, y0, 0.0, x1, y1, top + (2.4 if sign else 0.6))])
    rm.export_glb("buildings", name)


def tanks() -> None:
    name = "bld_in_tanks"
    rm.clear_scene()
    tank = rm.material("in_tank_white", "#dcdcd6", roughness=0.5, metallic=0.3)
    band = rm.material("in_tank_band", "#c9502e", roughness=0.6)
    bund = rm.material("in_concrete", "#9c9a94", roughness=0.9)
    pipe = rm.material("in_pipe_steel", "#8c9298", roughness=0.4, metallic=0.7)
    mb = rm.MeshBuilder()
    mb.box(-12.0, -6.0, 0.0, 12.0, 6.0, 0.6, bund, skip=("bottom",))
    for cx in (-7.6, 0.0, 7.6):
        mb.cylinder(cx, 0.0, 0.6, 3.6, 3.6, 10.0, 16, tank)
        mb.cylinder(cx, 0.0, 6.6, 3.62, 3.62, 0.7, 16, band, caps=False)
        mb.cylinder(cx, 0.0, 10.6, 3.6, 0.8, 1.2, 16, tank)
    mb.tube((-12.0, -4.4, 1.5), (12.0, -4.4, 1.5), 0.25, 0.25, 6, pipe)
    mb.build(name)
    col = rm.CollisionSet(name)
    col.box(-12.0, -6.0, 0.0, 12.0, 6.0, 0.6)
    for cx in (-7.6, 0.0, 7.6):
        col.frustum(cx, 0.0, 0.6, 7.0, 7.0, 7.0, 7.0, 11.2)
    col.build()
    rm.export_glb("buildings", name)


def crane() -> None:
    """Ship-to-shore gantry crane. Four legs on rails 16 m apart (across the quay, along Blender
    Y), a boom at 38 m reaching 52 m out over the water (-Y) and 18 m back, a machinery house,
    the driver's cab under the boom. Red and white; red lights on the boom tips at night."""
    name = "bld_in_crane"
    rm.clear_scene()
    red = rm.material("in_crane_red", "#c8402e", roughness=0.55, metallic=0.3)
    white = rm.material("in_crane_white", "#ecebe6", roughness=0.6, metallic=0.2)
    dark = rm.material("in_frame_dark", "#33363b", roughness=0.5, metallic=0.5)
    glass = rm.material("window_glass", "#2a3644", roughness=0.18, metallic=0.35)
    light = rm.material("neon_red", "#7a1a1a", roughness=0.4, emission="#ff2a1a", emission_strength=4.0)
    mb = rm.MeshBuilder()
    leg_x = (-7.0, 7.0)
    leg_y = (-8.0, 8.0)
    for x in leg_x:
        for y in leg_y:
            mb.box(x - 0.6, y - 0.6, 0.0, x + 0.6, y + 0.6, 34.0, red, skip=("bottom",))
            mb.box(x - 0.9, y - 1.6, 0.0, x + 0.9, y + 1.6, 1.2, dark)          # bogie
        mb.box(x - 0.5, leg_y[0], 30.0, x + 0.5, leg_y[1], 31.0, red)        # portal ties
        mb.box(x - 0.4, leg_y[0], 12.0, x + 0.4, leg_y[1], 12.8, red)
    for y in leg_y:
        mb.box(leg_x[0], y - 0.5, 33.0, leg_x[1], y + 0.5, 34.0, red)
    # the boom: a long box truss out over the water and back over the quay
    by0, by1 = -60.0, 26.0
    mb.box(-3.0, by0, 36.0, -2.2, by1, 37.4, white)
    mb.box(2.2, by0, 36.0, 3.0, by1, 37.4, white)
    for k in range(int((by1 - by0) / 6.0) + 1):
        y = by0 + k * 6.0
        mb.box(-3.0, y - 0.2, 36.0, 3.0, y + 0.2, 36.5, white)
    mb.box(-4.0, 10.0, 34.0, 4.0, 22.0, 39.0, white, skip=("bottom",))      # machinery house
    mb.box(-1.4, -10.0, 32.6, 1.4, -6.0, 35.6, glass)                       # cab
    mb.box(-1.6, -10.2, 35.6, 1.6, -5.8, 36.0, white)
    mb.box(-0.6, -30.0, 25.0, 0.6, -29.0, 36.0, dark)                       # spreader hoist cables
    mb.box(-2.5, -31.5, 24.0, 2.5, -27.5, 25.0, dark)
    for y in (by0, by1):
        mb.box(-0.4, y - 0.4, 37.4, 0.4, y + 0.4, 38.0, light)
    mb.build(name)
    col = rm.CollisionSet(name)
    for x in leg_x:
        for y in leg_y:
            col.box(x - 0.9, y - 1.6, 0.0, x + 0.9, y + 1.6, 34.0)
    col.box(-4.0, by0, 33.0, 4.0, by1, 39.0)
    col.build()
    rm.export_glb("buildings", name)


def container(name: str, paint: str) -> None:
    """A 12.2 x 2.44 x 2.6 m shipping container, long side along X, corrugated sides, doors at +X."""
    rm.clear_scene()
    body = rm.material(name + "_body", paint, roughness=0.6, metallic=0.3)
    rib = rm.material(name + "_rib", paint, roughness=0.5, metallic=0.4)
    dark = rm.material("in_frame_dark", "#33363b", roughness=0.5, metallic=0.5)
    mb = rm.MeshBuilder()
    x0, x1, y0, y1, h = -6.1, 6.1, -1.22, 1.22, 2.6
    mb.box(x0, y0, 0.0, x1, y1, h, body)
    for i in range(1, 9):                  # a few ribs: the yard holds hundreds of these
        x = x0 + i * (x1 - x0) / 9
        mb.box(x - 0.12, y0 - 0.04, 0.1, x + 0.12, y0, h - 0.1, rib, skip=("back", "top", "bottom"))
        mb.box(x - 0.12, y1, 0.1, x + 0.12, y1 + 0.04, h - 0.1, rib, skip=("front", "top", "bottom"))
    # The end frames stand 2 cm proud of the body (flush, the body showed through in thin lines).
    for a, b in ((x0 - 0.02, x0 + 0.12), (x1 - 0.12, x1 + 0.02)):
        mb.box(a, y0 - 0.02, 0.0, b, y1 + 0.02, h, dark)
    mb.box(x1 - 0.02, -0.06, 0.3, x1 + 0.03, 0.06, h - 0.3, dark)
    mb.build(name)
    collide(name, [(x0, y0, 0.0, x1, y1, h)])
    rm.export_glb("props", name)


def ship() -> None:
    """Cargo ship lying alongside the quay: a dark hull with a red bottom stripe at the waterline,
    a bow (Blender -Y) that narrows to a point, containers stacked on deck, and the white bridge
    and funnel at the stern. 108 m long, 20 m wide, the hull 9 m above the water."""
    name = "bld_in_ship"
    rm.clear_scene()
    hull = rm.material("in_ship_hull", "#22323f", roughness=0.6, metallic=0.3)
    red = rm.material("in_ship_red", "#9c2f23", roughness=0.6)
    deck = rm.material("in_ship_deck", "#6b4b3a", roughness=0.8)
    white = rm.material("in_crane_white", "#ecebe6", roughness=0.6, metallic=0.2)
    glass = rm.material("window_glass", "#2a3644", roughness=0.18, metallic=0.35)
    funnel = rm.material("in_ship_funnel", "#d8a024", roughness=0.6)
    box_a = rm.material("in_cargo_red", "#b8432f", roughness=0.6, metallic=0.3)
    box_b = rm.material("in_cargo_blue", "#2f5f9a", roughness=0.6, metallic=0.3)
    box_c = rm.material("in_cargo_teal", "#2f8a83", roughness=0.6, metallic=0.3)
    mb = rm.MeshBuilder()
    hw, z_top = 10.0, 9.0
    outline = [(-hw, 54.0), (hw, 54.0), (hw, -36.0), (5.0, -50.0), (0.0, -54.0), (-5.0, -50.0), (-hw, -36.0)]
    n = len(outline)
    for i in range(n):
        (xa, ya), (xb, yb) = outline[i], outline[(i + 1) % n]
        mb.face([(xa, ya, -1.0), (xb, yb, -1.0), (xb, yb, z_top), (xa, ya, z_top)], hull, inside=(0, 0, 4.0))
        mb.face([(xa, ya, -1.0), (xb, yb, -1.0), (xb, yb, 1.2), (xa, ya, 1.2)], red, inside=(0, 0, 4.0))
    mb.face([(x, y, z_top) for x, y in outline], deck, outward=(0, 0, 1))
    colours = (box_a, box_b, box_c)
    for row in range(5):                                       # containers on deck, bow to midships
        y = -30.0 + row * 13.0
        for col in range(6):
            x = -7.5 + col * 3.0
            height = 2 + (row + col) % 3
            for lvl in range(height):
                mb.box(x - 1.2, y - 6.0, z_top + lvl * 2.6, x + 1.2, y + 6.0, z_top + (lvl + 1) * 2.6 - 0.05,
                       colours[(row * 3 + col + lvl) % 3], skip=("bottom",))
    mb.box(-9.0, 38.0, z_top, 9.0, 52.0, z_top + 12.0, white, skip=("bottom",))       # bridge
    for k in range(3):
        z = z_top + 3.0 + k * 3.0
        mb.box(-8.0, 37.95, z, 8.0, 38.0, z + 1.4, glass, skip=("back",))
    mb.box(-12.0, 37.5, z_top + 10.5, 12.0, 40.0, z_top + 11.0, white)                # bridge wings
    mb.box(-2.2, 46.0, z_top + 12.0, 2.2, 50.0, z_top + 18.0, funnel, skip=("bottom",))
    mb.build(name)
    col = rm.CollisionSet(name)
    col.hull([(x, y, z) for x, y in outline for z in (-1.0, z_top)])
    col.box(-9.0, 38.0, z_top, 9.0, 52.0, z_top + 12.0)
    col.box(-9.0, -36.0, z_top, 9.0, 30.0, z_top + 10.4)
    col.build()
    rm.export_glb("buildings", name)


def fish_shed() -> None:
    """Fishing harbour market: an open shed on posts, a tin roof, a concrete floor with tables."""
    name = "bld_in_fish_shed"
    rm.clear_scene()
    post = rm.material("in_frame_dark", "#33363b", roughness=0.5, metallic=0.5)
    roof = rm.material("in_roof_blue", "#3c6f9c", roughness=0.55, metallic=0.4)
    floor = rm.material("in_concrete", "#9c9a94", roughness=0.9)
    table = rm.material("in_table_steel", "#b7bcc0", roughness=0.35, metallic=0.6)
    light = rm.material("lamp_lens", "#f6e6b0", roughness=0.2, emission="#fff1c0", emission_strength=2.0)
    mb = rm.MeshBuilder()
    mb.box(-10.0, -5.0, 0.0, 10.0, 5.0, 0.2, floor, skip=("bottom",))
    for x in (-9.7, -3.3, 3.1, 9.5):
        for y in (-4.7, 4.5):
            mb.box(x, y, 0.2, x + 0.2, y + 0.2, 4.2, post, skip=("bottom",))
    mb.prism([(-5.6, 4.0), (0.0, 5.2), (5.6, 4.0)], "X", -10.4, 10.4, roof)
    for x in (-6.0, 0.0, 6.0):
        mb.box(x - 2.0, -1.0, 0.85, x + 2.0, 1.0, 0.95, table)
        for (tx, ty) in ((x - 1.9, -0.9), (x + 1.8, -0.9), (x - 1.9, 0.8), (x + 1.8, 0.8)):
            mb.box(tx, ty, 0.2, tx + 0.1, ty + 0.1, 0.85, table)
        mb.box(x - 0.3, -0.3, 3.6, x + 0.3, 0.3, 3.8, light)
    mb.build(name)
    col = rm.CollisionSet(name)
    col.box(-10.0, -5.0, 0.0, 10.0, 5.0, 0.2)
    for x in (-9.7, -3.3, 3.1, 9.5):
        for y in (-4.7, 4.5):
            col.box(x, y, 0.2, x + 0.2, y + 0.2, 4.2)
    col.box(-10.4, -5.6, 4.0, 10.4, 5.6, 5.2)
    col.build()
    rm.export_glb("buildings", name)


def sodium_streetlight() -> None:
    """The city streetlight (the same shape as props.py prop_streetlight, so the street-light pool's
    lamp offset fits it) with an orange sodium lens."""
    name = "prop_streetlight_sodium"
    rm.clear_scene()
    base_m = rm.material("lamp_base", "#3a3d42", roughness=0.6, metallic=0.4)
    pole_m = rm.material("lamp_pole_galvanised", "#7d8287", roughness=0.45, metallic=0.6)
    lens_m = rm.material("lamp_lens", "#f2a64a", roughness=0.3, emission="#ff9a2e", emission_strength=1.5)
    mb = rm.MeshBuilder()
    mb.box_c(0.0, 0.0, 0.0, 0.36, 0.36, 0.6, base_m, skip=("bottom",))
    mb.tube((0.0, 0.0, 0.6), (0.0, 0.0, 8.2), 0.1, 0.075, 8, pole_m)
    mb.tube((0.0, 0.0, 7.9), (1.2, 0.0, 8.35), 0.06, 0.05, 6, pole_m)
    mb.tube((1.2, 0.0, 8.35), (2.4, 0.0, 8.42), 0.05, 0.045, 6, pole_m)
    mb.box(2.0, -0.22, 8.25, 2.9, 0.22, 8.47, base_m, skip=("bottom",))
    mb.box(2.05, -0.18, 8.22, 2.85, 0.18, 8.25, lens_m, skip=("top",))
    mb.build(name)
    collide(name, [(-0.18, -0.18, 0.0, 0.18, 0.18, 8.2)])
    rm.export_glb("props", name)


BUILDERS = {
    "bld_in_warehouse_a": lambda: warehouse("bld_in_warehouse_a", 30.0, 20.0, 9.0, "#8d98a3", "#7a858f", 2),
    "bld_in_warehouse_b": lambda: warehouse("bld_in_warehouse_b", 24.0, 16.0, 8.0, "#a2553d", "#8e4834", 1),
    "bld_in_factory": factory,
    "bld_in_office": lambda: office("bld_in_office", "#d9d5cb", None),
    "bld_in_police": lambda: office("bld_in_police", "#eceae4", "POLICE"),
    "bld_in_tanks": tanks,
    "bld_in_crane": crane,
    "bld_in_ship": ship,
    "bld_in_fish_shed": fish_shed,
    "prop_in_container_a": lambda: container("prop_in_container_a", "#b8432f"),
    "prop_in_container_b": lambda: container("prop_in_container_b", "#2f5f9a"),
    "prop_in_container_c": lambda: container("prop_in_container_c", "#2f8a83"),
    "prop_streetlight_sodium": sodium_streetlight,
}


def main() -> None:
    for name in (rm.script_args() or list(BUILDERS)):
        BUILDERS[name]()


main()
