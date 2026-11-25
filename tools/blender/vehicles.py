"""Vehicles -> assets/models/vehicles/

  veh_sedan_body    4.5 m four-door sedan body (no wheels), unbadged, crimson paint
  veh_sedan_wheel   0.33 m radius wheel: tyre plus a five-spoke rim facing Blender +X
  veh_police_lightbar  roof light bar for police cars (police_red / police_blue lenses)
  veh_police_heli   police helicopter; "rotor" and "tail_rotor" are separate objects to spin
  veh_sports_body   (M7) low two-door sports coupe, rear wing; veh_wheel_sport (r 0.34, wide)
  veh_suv_body      (M7) tall five-door SUV, roof rails, spare wheel; veh_wheel_suv (r 0.40)
  veh_bus_body      (M7) 11 m city bus, doors on the left (kerb) side, CITY board; veh_wheel_heavy (r 0.5)
  veh_truck_body    (M7) 7.6 m cargo truck, cab and box body; veh_wheel_heavy
  veh_bike_body     (M7) 150 cc street motorcycle; veh_bike_wheel (r 0.3, narrow)

The car faces Blender -Y (= Godot +Z, the VehicleBody3D forward axis). Its left side is +X.
The pivot is the chassis centre: the road is at z = -0.55 and wheel centres at z = -0.22 once
the suspension has settled. Body x = +-0.89, wheelbase 2.65 m (front axle y = -1.36,
rear axle y = +1.29), track 1.52 m.

No collision is exported: a car is a moving rigid body, so its convex collision shape lives in
scenes/vehicles/sedan.tscn (a '-colonly' mesh would import as a static body).

The headlight, tail-light and reverse-light lenses use their own materials (veh_headlight,
veh_taillight, veh_reverselight) so the game can switch their glow at runtime.

Run:  "$BLENDER" --background --factory-startup --python tools/blender/vehicles.py [-- names...]
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rotd_mesh as rm  # noqa: E402

HALF_WIDTH = 0.89
FRONT_AXLE_Y = -1.36
REAR_AXLE_Y = 1.29
WHEEL_Z = -0.22
ARCH_RADIUS = 0.40
BODY_BOTTOM = -0.36


# --------------------------------------------------------------------------- helpers

def _signed_area(profile) -> float:
    return 0.5 * sum(profile[i][0] * profile[(i + 1) % len(profile)][1]
                     - profile[(i + 1) % len(profile)][0] * profile[i][1] for i in range(len(profile)))


def extrude_profile_x(mb: rm.MeshBuilder, profile, x0: float, x1: float, side_mat, edge_mat) -> None:
    """Extrude a simple (possibly concave) (y, z) side profile across X from x0 to x1.
    Each edge face gets edge_mat(i) and an outward normal worked out from the winding, which
    stays correct on concave parts such as wheel arches. The two caps get side_mat."""
    ccw = _signed_area(profile) > 0.0
    n = len(profile)
    for i in range(n):
        y0, z0 = profile[i]
        y1, z1 = profile[(i + 1) % n]
        dy, dz = y1 - y0, z1 - z0
        # For a counter-clockwise outline the outside is on the right of each edge.
        normal = Vector((0.0, dz, -dy)) if ccw else Vector((0.0, -dz, dy))
        mb.face([(x0, y0, z0), (x0, y1, z1), (x1, y1, z1), (x1, y0, z0)], edge_mat(i), outward=normal)
    mb.face([(x0, y, z) for y, z in profile], side_mat, outward=Vector((-1.0, 0.0, 0.0)))
    mb.face([(x1, y, z) for y, z in profile], side_mat, outward=Vector((1.0, 0.0, 0.0)))


def arch_points(centre_y: float, segments: int) -> list[tuple[float, float]]:
    """Points over a wheel arch, front to rear, from where the circle meets the sill line."""
    s = (BODY_BOTTOM - WHEEL_Z) / ARCH_RADIUS
    start = math.pi - math.asin(s)        # front foot of the arch
    end = math.asin(s)                    # rear foot
    pts = []
    for k in range(segments + 1):
        a = start + (end - start) * k / segments
        pts.append((centre_y + ARCH_RADIUS * math.cos(a), WHEEL_Z + ARCH_RADIUS * math.sin(a)))
    return pts


def bevelled_into(target: rm.MeshBuilder, source: rm.MeshBuilder, name: str, width: float,
                  segments: int, angle_degrees: float) -> None:
    """Build `source` as a welded mesh, bevel its sharp edges, and copy the result into
    `target` so the final model stays a single object (fewer draw calls)."""
    obj = source.build(name)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(obj.data)
    bm.free()
    mod = obj.modifiers.new("bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(angle_degrees)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    for poly in mesh.polygons:
        mat = obj.material_slots[poly.material_index].material
        pts = [mesh.vertices[v].co.copy() for v in poly.vertices]
        target.face(pts, mat, outward=poly.normal.copy())
    evaluated.to_mesh_clear()
    mesh_data = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.meshes.remove(mesh_data)


def mirrored_box(mb: rm.MeshBuilder, x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, mat) -> None:
    """Box on the +X side plus its mirror image on the -X side."""
    mb.box(x0, y0, z0, x1, y1, z1, mat)
    mb.box(-x1, y0, z0, -x0, y1, z1, mat)


def strut(mb: rm.MeshBuilder, p0, p1, radius: float, mat) -> None:
    """Square-section bar between two points (window pillars, rails, trim)."""
    mb.tube(p0, p1, radius, radius, 4, mat)


# --------------------------------------------------------------------------- sedan body

def sedan_body() -> None:
    name = "veh_sedan_body"
    rm.clear_scene()
    paint = rm.material("veh_paint", "#a3162b", roughness=0.3, metallic=0.55)
    chassis = rm.material("veh_chassis", "#141518", roughness=0.85)
    trim = rm.material("veh_trim", "#1b1c20", roughness=0.45)
    glass = rm.material("veh_glass", "#1d2a38", roughness=0.06, metallic=0.65)
    chrome = rm.material("veh_chrome", "#c8ccd2", roughness=0.18, metallic=1.0)
    plate = rm.material("veh_plate", "#f1f1ea", roughness=0.6)
    head = rm.material("veh_headlight", "#f4f2ea", roughness=0.12, emission="#fff3d2", emission_strength=0.15)
    tail = rm.material("veh_taillight", "#8c0f16", roughness=0.2, emission="#ff2a1c", emission_strength=0.3)
    reverse = rm.material("veh_reverselight", "#e9e9e6", roughness=0.15, emission="#ffffff", emission_strength=0.05)

    # ---- lower body: side profile with wheel-arch cut-outs, extruded across the width, bevelled
    lower = [
        (-2.25, -0.10), (-2.20, -0.28), (-2.08, BODY_BOTTOM),
    ]
    front_arch = arch_points(FRONT_AXLE_Y, 12)
    rear_arch = arch_points(REAR_AXLE_Y, 12)
    profile = lower + front_arch + rear_arch + [
        (2.10, BODY_BOTTOM), (2.22, -0.26), (2.26, -0.05),   # rear bumper
        (2.25, 0.22), (2.12, 0.34),                           # trunk lid
        (1.42, 0.38), (-0.82, 0.36),                          # belt line under the cabin
        (-2.02, 0.25), (-2.22, 0.15), (-2.255, 0.04),         # hood and nose
    ]
    arch_edges = set(range(len(lower), len(lower) + len(front_arch) - 1)) | \
        set(range(len(lower) + len(front_arch), len(lower) + len(front_arch) + len(rear_arch) - 1))

    def edge_material(i: int):
        if i in arch_edges:
            return chassis
        y0, z0 = profile[i]
        y1, z1 = profile[(i + 1) % len(profile)]
        if z0 <= BODY_BOTTOM + 1e-6 and z1 <= BODY_BOTTOM + 1e-6:
            return chassis                                   # underside
        return paint

    shell = rm.MeshBuilder()
    extrude_profile_x(shell, profile, -HALF_WIDTH, HALF_WIDTH, paint, edge_material)
    mb = rm.MeshBuilder()
    bevelled_into(mb, shell, "body_shell", width=0.035, segments=2, angle_degrees=35.0)

    # Dark wheel tubs fill the arches between the wheels (the front ones leave room to steer).
    for axle_y, inner in ((FRONT_AXLE_Y, 0.42), (REAR_AXLE_Y, 0.62)):
        mb.box(-inner, axle_y - ARCH_RADIUS, BODY_BOTTOM, inner, axle_y + ARCH_RADIUS, 0.16, chassis)

    # ---- cabin: tinted glass greenhouse, painted roof, pillars and rails
    wind_base, roof_front, roof_rear, rear_base = (-0.82, 0.35), (-0.16, 0.90), (0.72, 0.90), (1.42, 0.37)
    low_w, top_w = 0.80, 0.66
    mb.convex_hull([(sx * w, y, z) for sx in (-1, 1) for (y, z), w in
                    ((wind_base, low_w), (roof_front, top_w), (roof_rear, top_w), (rear_base, low_w))], glass)
    mb.convex_hull([(sx * 0.665, y, 0.893) for sx in (-1, 1) for y in (-0.18, 0.74)] +
                   [(sx * 0.615, y, 0.935) for sx in (-1, 1) for y in (-0.10, 0.66)], paint)
    for sx in (-1, 1):
        # A-pillar, roof rail, C-pillar (thicker), B-pillar (black), belt trim
        strut(mb, (sx * low_w, wind_base[0], wind_base[1] + 0.01), (sx * top_w, roof_front[0], roof_front[1]), 0.045, paint)
        strut(mb, (sx * top_w, roof_front[0], roof_front[1]), (sx * top_w, roof_rear[0], roof_rear[1]), 0.04, paint)
        strut(mb, (sx * low_w, rear_base[0] - 0.05, rear_base[1] + 0.01), (sx * top_w, roof_rear[0] - 0.06, roof_rear[1]), 0.085, paint)
        strut(mb, (sx * (low_w + 0.005), 0.24, 0.37), (sx * (top_w + 0.005), 0.24, 0.885), 0.035, trim)
        strut(mb, (sx * (low_w + 0.012), wind_base[0] + 0.05, 0.372), (sx * (low_w + 0.012), rear_base[0] - 0.1, 0.39), 0.014, chrome)

    # ---- body-side details: door seams, handles, skirts, mirrors
    sx_out = HALF_WIDTH + 0.004
    for y in (-0.78, 0.24):
        mirrored_box(mb, HALF_WIDTH - 0.004, y - 0.006, -0.24, sx_out, y + 0.006, 0.33, trim)
    mirrored_box(mb, HALF_WIDTH - 0.004, 0.95 - 0.006, 0.02, sx_out, 0.95 + 0.006, 0.33, trim)
    mirrored_box(mb, HALF_WIDTH - 0.004, -0.78, -0.246, sx_out, 0.90, -0.234, trim)
    for y in (-0.30, 0.66):
        mirrored_box(mb, HALF_WIDTH - 0.01, y - 0.07, 0.19, HALF_WIDTH + 0.018, y + 0.07, 0.235, chrome)
    mirrored_box(mb, HALF_WIDTH - 0.01, -0.94, BODY_BOTTOM, HALF_WIDTH + 0.01, 0.87, -0.27, trim)
    mirrored_box(mb, 0.86, -0.72, 0.40, 1.01, -0.60, 0.50, paint)
    mirrored_box(mb, 0.88, -0.60, 0.41, 1.0, -0.594, 0.49, glass)

    # ---- front: headlights, grille, intake, number plate (left blank)
    mirrored_box(mb, 0.46, -2.262, 0.03, 0.82, -2.12, 0.16, head)
    mb.box(-0.42, -2.265, 0.0, 0.42, -2.15, 0.13, trim)
    for z in (0.035, 0.07, 0.105):
        mb.box(-0.40, -2.270, z - 0.006, 0.40, -2.26, z + 0.006, chrome)
    mb.box(-0.55, -2.262, -0.26, 0.55, -2.15, -0.16, trim)
    mb.box(-0.25, -2.27, -0.145, 0.25, -2.20, -0.03, plate)

    # ---- rear: tail lights, reverse lights, bumper strip, plate, exhaust
    mirrored_box(mb, 0.50, 2.12, 0.08, 0.86, 2.262, 0.21, tail)
    mirrored_box(mb, 0.32, 2.12, 0.10, 0.48, 2.262, 0.19, reverse)
    mb.box(-0.80, 2.15, -0.26, 0.80, 2.255, -0.16, trim)
    mb.box(-0.25, 2.15, -0.045, 0.25, 2.268, 0.075, plate)
    mb.tube((-0.50, 2.08, -0.31), (-0.50, 2.30, -0.31), 0.035, 0.035, 8, chrome)

    mb.build(name)
    rm.export_glb("vehicles", name)


# --------------------------------------------------------------------------- wheel

def lathe_x(mb: rm.MeshBuilder, profile, segments: int, mat, inside_radius: float) -> None:
    """Revolve an open (radius, x) profile around the X axis. Faces point away from the
    ring of radius `inside_radius` in the plane x = 0 (the middle of the tyre section)."""
    rings = []
    for r, x in profile:
        rings.append([Vector((x, r * math.cos(2 * math.pi * s / segments), r * math.sin(2 * math.pi * s / segments)))
                      for s in range(segments)])
    for i in range(len(rings) - 1):
        for s in range(segments):
            t = (s + 1) % segments
            mid = 2 * math.pi * (s + 0.5) / segments
            inside = Vector((0.0, inside_radius * math.cos(mid), inside_radius * math.sin(mid)))
            mb.face([rings[i][s], rings[i][t], rings[i + 1][t], rings[i + 1][s]], mat, inside=inside)


def sedan_wheel() -> None:
    name = "veh_sedan_wheel"
    rm.clear_scene()
    rubber = rm.material("veh_tyre", "#1c1c1e", roughness=0.92)
    rim = rm.material("veh_rim", "#b9bec6", roughness=0.25, metallic=1.0)
    dark = rm.material("veh_rim_dark", "#2a2c31", roughness=0.6, metallic=0.4)

    mb = rm.MeshBuilder()
    tyre = [(0.212, 0.104), (0.298, 0.108), (0.324, 0.095), (0.33, 0.055),
            (0.33, -0.055), (0.324, -0.095), (0.298, -0.108), (0.212, -0.104)]
    lathe_x(mb, tyre, 20, rubber, 0.27)
    # Rim: a polished lip, a dark dish behind five spokes, and a hub. Faces Blender +X (outward
    # on the car's left; the right-hand wheels are turned around in the vehicle scene).
    lip = [(0.214, 0.094), (0.204, 0.088)]
    lathe_x(mb, lip, 20, rim, 0.0)
    mb.tube((0.06, 0.0, 0.0), (0.062, 0.0, 0.0), 0.205, 0.205, 20, dark, caps=True)
    mb.tube((-0.095, 0.0, 0.0), (-0.09, 0.0, 0.0), 0.212, 0.212, 20, dark, caps=True)
    for k in range(5):
        start = mb.mark()
        mb.box(0.062, -0.026, 0.05, 0.088, 0.026, 0.205, rim)
        mb.transform_since(start, Matrix.Rotation(2 * math.pi * k / 5, 4, "X"))
    mb.tube((0.055, 0.0, 0.0), (0.098, 0.0, 0.0), 0.065, 0.05, 10, rim)
    mb.build(name)
    rm.export_glb("vehicles", name)


def police_lightbar() -> None:
    """Roof light bar for police cars, 1.1 m wide, pivot at its base centre. The lenses use
    police_red / police_blue so the game can flash them."""
    name = "veh_police_lightbar"
    rm.clear_scene()
    base = rm.material("lightbar_base", "#25272c", roughness=0.5, metallic=0.4)
    red = rm.material("police_red", "#7a0b12", roughness=0.3, emission="#ff2030", emission_strength=0.2)
    blue = rm.material("police_blue", "#0b1f7a", roughness=0.3, emission="#2a5bff", emission_strength=0.2)
    mb = rm.MeshBuilder()
    for x in (-0.4, 0.4):                                    # feet on the roof
        mb.box(x - 0.05, -0.1, 0.0, x + 0.05, 0.1, 0.04, base)
    mb.box(-0.56, -0.13, 0.04, 0.56, 0.13, 0.09, base)
    mb.box(-0.53, -0.11, 0.09, -0.03, 0.11, 0.2, red)
    mb.box(0.03, -0.11, 0.09, 0.53, 0.11, 0.2, blue)
    mb.box(-0.03, -0.11, 0.09, 0.03, 0.11, 0.2, base)
    mb.build(name)
    rm.export_glb("vehicles", name)


def police_heli() -> None:
    """Police helicopter, about 11 m rotor to tail. Faces Blender -Y, pivot on the ground between
    the skids. The main rotor is its own object, "rotor", with its origin on the mast (the game
    spins it); "tail_rotor" likewise."""
    name = "veh_police_heli"
    rm.clear_scene()
    white = rm.material("heli_white", "#eef0f2", roughness=0.45)
    blue = rm.material("heli_blue", "#1f4fa0", roughness=0.45)
    glass = rm.material("heli_glass", "#1d2633", roughness=0.15, metallic=0.4)
    dark = rm.material("heli_dark", "#2a2c31", roughness=0.6, metallic=0.4)
    mb = rm.MeshBuilder()
    mb.box(-0.85, -1.6, 0.5, 0.85, 1.1, 1.95, white)                        # cabin
    mb.box(-0.86, -1.61, 0.95, 0.86, 1.11, 1.15, blue)                      # stripe
    mb.box(-0.75, -2.15, 0.6, 0.75, -1.6, 1.75, glass)                      # nose glazing
    mb.box(-0.6, -0.4, 1.95, 0.6, 1.0, 2.25, white)                         # engine housing
    mb.tube((0, 1.1, 1.45), (0, 5.6, 1.75), 0.32, 0.14, 8, white, caps=True)  # tail boom
    mb.box(-0.05, 5.2, 1.6, 0.05, 5.9, 2.7, blue)                           # fin
    mb.box(-0.9, 5.3, 1.65, 0.9, 5.6, 1.75, white)                          # tail plane
    for x in (-0.85, 0.85):                                                 # skids and struts
        mb.tube((x, -1.7, 0.08), (x, 1.3, 0.08), 0.05, 0.05, 6, dark, caps=True)
        for y in (-0.9, 0.6):
            mb.tube((x, y, 0.08), (x * 0.8, y, 0.55), 0.04, 0.04, 6, dark)
    mb.build(name)
    rotor = rm.MeshBuilder()
    rotor.cylinder(0, 0, -0.1, 0.12, 0.12, 0.25, 8, dark)
    rotor.box(-4.6, -0.125, 0.1, 4.6, 0.125, 0.14, dark)                   # two crossed blades
    rotor.box(-0.125, -4.6, 0.1, 0.125, 4.6, 0.14, dark)
    rotor_obj = rotor.build("rotor")
    rotor_obj.location = (0.0, 0.3, 2.3)
    tail = rm.MeshBuilder()
    tail.box(-0.04, -0.06, -0.6, 0.04, 0.06, 0.6, dark)
    tail.box(-0.04, -0.6, -0.06, 0.04, 0.6, 0.06, dark)
    tail_obj = tail.build("tail_rotor")
    tail_obj.location = (0.22, 5.65, 2.1)
    rm.export_glb("vehicles", name)



# --------------------------------------------------------------------------- the rest of the fleet (M7)
# Same conventions as the sedan: the vehicle faces Blender -Y, its left is +X, the pivot is the
# chassis centre. Paint (veh_paint) is tinted per car; lamp lenses use the veh_*light materials.

def fleet_materials(paint_hex: str) -> dict:
    return {
        "paint": rm.material("veh_paint", paint_hex, roughness=0.3, metallic=0.55),
        "chassis": rm.material("veh_chassis", "#141518", roughness=0.85),
        "trim": rm.material("veh_trim", "#1b1c20", roughness=0.45),
        "glass": rm.material("veh_glass", "#1d2a38", roughness=0.06, metallic=0.65),
        "chrome": rm.material("veh_chrome", "#c8ccd2", roughness=0.18, metallic=1.0),
        "plate": rm.material("veh_plate", "#f1f1ea", roughness=0.6),
        "head": rm.material("veh_headlight", "#f4f2ea", roughness=0.12, emission="#fff3d2", emission_strength=0.15),
        "tail": rm.material("veh_taillight", "#8c0f16", roughness=0.2, emission="#ff2a1c", emission_strength=0.3),
        "reverse": rm.material("veh_reverselight", "#e9e9e6", roughness=0.15, emission="#ffffff", emission_strength=0.05),
    }


def arch(centre_y: float, wheel_z: float, radius: float, bottom: float, segments: int = 10) -> list[tuple[float, float]]:
    """Points over a wheel arch of `radius` round a wheel centred at (centre_y, wheel_z), front to
    rear, from where the circle meets the sill line z = bottom (like arch_points, any size)."""
    s = max(-1.0, min(1.0, (bottom - wheel_z) / radius))
    start, end = math.pi - math.asin(s), math.asin(s)
    return [(centre_y + radius * math.cos(start + (end - start) * k / segments),
             wheel_z + radius * math.sin(start + (end - start) * k / segments)) for k in range(segments + 1)]


def shell_with_arches(mb: rm.MeshBuilder, profile, n_front: int, arches: list, half_width: float, m: dict, bottom: float,
                      bevel: float) -> None:
    """Extrude a side profile whose arch points start at index n_front (two arches, back to back)
    across the width, paint above the sill, chassis on the arches and underside, then bevel it."""
    arch_edges = set()
    k = n_front
    for a in arches:
        arch_edges |= set(range(k, k + len(a) - 1))
        k += len(a)

    def edge_material(i: int):
        if i in arch_edges:
            return m["chassis"]
        z0 = profile[i][1]
        z1 = profile[(i + 1) % len(profile)][1]
        return m["chassis"] if z0 <= bottom + 1e-6 and z1 <= bottom + 1e-6 else m["paint"]

    shell = rm.MeshBuilder()
    extrude_profile_x(shell, profile, -half_width, half_width, m["paint"], edge_material)
    bevelled_into(mb, shell, "body_shell", width=bevel, segments=2, angle_degrees=35.0)


def greenhouse(mb: rm.MeshBuilder, m: dict, wind_base, roof_front, roof_rear, rear_base, low_w: float, top_w: float) -> None:
    """Glass cabin (a hull) with a painted roof skin and pillars, like the sedan's."""
    mb.convex_hull([(sx * w, y, z) for sx in (-1, 1) for (y, z), w in
                    ((wind_base, low_w), (roof_front, top_w), (roof_rear, top_w), (rear_base, low_w))], m["glass"])
    roof_z = max(roof_front[1], roof_rear[1])
    mb.convex_hull([(sx * (top_w + 0.005), y, roof_z - 0.007) for sx in (-1, 1) for y in (roof_front[0] - 0.02, roof_rear[0] + 0.02)] +
                   [(sx * (top_w - 0.05), y, roof_z + 0.035) for sx in (-1, 1) for y in (roof_front[0] + 0.06, roof_rear[0] - 0.06)], m["paint"])
    for sx in (-1, 1):
        strut(mb, (sx * low_w, wind_base[0], wind_base[1] + 0.01), (sx * top_w, roof_front[0], roof_front[1]), 0.045, m["paint"])
        strut(mb, (sx * top_w, roof_front[0], roof_front[1]), (sx * top_w, roof_rear[0], roof_rear[1]), 0.04, m["paint"])
        strut(mb, (sx * low_w, rear_base[0] - 0.05, rear_base[1] + 0.01), (sx * top_w, roof_rear[0] - 0.06, roof_rear[1]), 0.08, m["paint"])


def lamps(mb: rm.MeshBuilder, m: dict, front_y: float, rear_y: float, head_x: tuple, head_z: tuple, tail_x: tuple, tail_z: tuple) -> None:
    """Headlights on the front face, tail and reverse lights on the back (mirrored)."""
    mirrored_box(mb, head_x[0], front_y - 0.012, head_z[0], head_x[1], front_y + 0.12, head_z[1], m["head"])
    mirrored_box(mb, tail_x[0], rear_y - 0.12, tail_z[0], tail_x[1], rear_y + 0.012, tail_z[1], m["tail"])
    rev = (tail_x[0] - 0.16, tail_x[0] - 0.02)
    mirrored_box(mb, rev[0], rear_y - 0.1, tail_z[0] + 0.02, rev[1], rear_y + 0.012, tail_z[1] - 0.02, m["reverse"])


def sports_body() -> None:
    """veh_sports_body: a low two-door sports coupe, 4.4 m, wide wheels, a rear wing. Wheels r 0.34
    centred at z -0.18 (road at -0.52); axles at y -1.32 and 1.28; body x +-0.95."""
    name = "veh_sports_body"
    rm.clear_scene()
    m = fleet_materials("#e8b313")
    hw, wz, bottom, radius = 0.95, -0.18, -0.34, 0.41
    front = [(-2.2, -0.12), (-2.16, -0.27), (-2.05, bottom)]
    arches = [arch(-1.32, wz, radius, bottom), arch(1.28, wz, radius, bottom)]
    profile = front + arches[0] + arches[1] + [
        (2.08, bottom), (2.18, -0.22), (2.22, 0.02), (2.2, 0.2), (2.05, 0.25),
        (1.45, 0.24), (-0.55, 0.14), (-1.9, 0.03), (-2.19, -0.03),
    ]
    mb = rm.MeshBuilder()
    shell_with_arches(mb, profile, len(front), arches, hw, m, bottom, 0.035)
    for axle_y, inner in ((-1.32, 0.4), (1.28, 0.55)):
        mb.box(-inner, axle_y - radius, bottom, inner, axle_y + radius, 0.1, m["chassis"])
    greenhouse(mb, m, (-0.55, 0.14), (0.05, 0.56), (0.62, 0.56), (1.45, 0.24), 0.86, 0.7)
    mirrored_box(mb, hw - 0.01, 0.55, -0.18, hw + 0.02, 1.0, 0.02, m["trim"])     # side intakes
    for x in (-0.55, 0.55):                                   # rear wing on two posts
        mb.box(x - 0.04, 1.95, 0.24, x + 0.04, 2.05, 0.4, m["trim"])
    mb.box(-0.88, 1.88, 0.4, 0.88, 2.16, 0.44, m["paint"])
    mb.box(-0.5, -2.2, -0.26, 0.5, -2.12, -0.12, m["trim"])     # front intake
    lamps(mb, m, -2.19, 2.21, (0.5, 0.86), (-0.06, 0.04), (0.45, 0.88), (0.1, 0.18))
    mb.box(-0.22, 2.2, -0.14, 0.22, 2.24, -0.04, m["plate"])
    for x in (-0.3, 0.3):
        mb.tube((x, 2.1, -0.3), (x, 2.28, -0.3), 0.045, 0.045, 8, m["chrome"])
    mb.build(name)
    rm.export_glb("vehicles", name)


def suv_body() -> None:
    """veh_suv_body: a tall five-door SUV, 4.7 m, roof rails, a spare wheel on the tailgate. Wheels
    r 0.40 centred at z -0.1 (road at -0.5); axles at y -1.45 and 1.4; body x +-0.98."""
    name = "veh_suv_body"
    rm.clear_scene()
    m = fleet_materials("#2f5d44")
    hw, wz, bottom, radius = 0.98, -0.1, -0.26, 0.48
    front = [(-2.35, -0.04), (-2.32, -0.2), (-2.2, bottom)]
    arches = [arch(-1.45, wz, radius, bottom), arch(1.4, wz, radius, bottom)]
    profile = front + arches[0] + arches[1] + [
        (2.24, bottom), (2.34, -0.18), (2.36, 0.12), (2.34, 0.5), (2.26, 0.52),
        (-1.0, 0.5), (-2.2, 0.44), (-2.36, 0.3),
    ]
    mb = rm.MeshBuilder()
    shell_with_arches(mb, profile, len(front), arches, hw, m, bottom, 0.04)
    for axle_y, inner in ((-1.45, 0.42), (1.4, 0.55)):
        mb.box(-inner, axle_y - radius, bottom, inner, axle_y + radius, 0.2, m["chassis"])
    greenhouse(mb, m, (-1.0, 0.5), (-0.42, 1.14), (2.12, 1.15), (2.27, 0.52), 0.93, 0.86)
    for sx in (-1, 1):                                        # roof rails
        strut(mb, (sx * 0.7, -0.3, 1.22), (sx * 0.7, 2.0, 1.22), 0.03, m["trim"])
    mirrored_box(mb, hw - 0.01, -2.0, bottom, hw + 0.025, 2.1, -0.12, m["trim"])     # black cladding
    mb.box(-0.62, -2.37, -0.02, 0.62, -2.3, 0.28, m["trim"])    # grille
    for z in (0.06, 0.13, 0.2):
        mb.box(-0.6, -2.38, z - 0.008, 0.6, -2.37, z + 0.008, m["chrome"])
    mb.box(-0.8, -2.36, -0.24, 0.8, -2.28, -0.1, m["trim"])
    lamps(mb, m, -2.35, 2.35, (0.62, 0.9), (0.18, 0.3), (0.7, 0.92), (0.2, 0.45))
    mb.tube((0.0, 2.36, 0.3), (0.0, 2.6, 0.3), 0.37, 0.37, 14, m["chassis"])    # spare wheel
    mb.box(-0.22, 2.35, -0.08, 0.22, 2.39, 0.04, m["plate"])
    mb.build(name)
    rm.export_glb("vehicles", name)


def bus_body() -> None:
    """veh_bus_body: an 11 m city bus. Livery paint below and above a band of windows, doors on the
    left (kerb) side, a lit destination board saying CITY. Wheels r 0.5 centred at z -0.85 (road at
    -1.35); axles at y -3.6 and 3.2; body x +-1.25."""
    name = "veh_bus_body"
    rm.clear_scene()
    m = fleet_materials("#b8322a")
    cream = rm.material("veh_bus_cream", "#efe6cf", roughness=0.6)
    board = rm.material("veh_bus_board", "#141518", roughness=0.6)
    lettering = rm.material("veh_headlight", "#f4f2ea", roughness=0.12, emission="#fff3d2", emission_strength=0.15)
    hw, wz, bottom, radius = 1.25, -0.85, -1.05, 0.6
    front = [(-5.5, 1.62), (-5.56, 0.0), (-5.5, -0.95), (-5.4, bottom)]
    arches = [arch(-3.6, wz, radius, bottom), arch(3.2, wz, radius, bottom)]
    profile = front + arches[0] + arches[1] + [(5.4, bottom), (5.5, -0.95), (5.5, 1.62), (5.38, 1.78), (-5.38, 1.78)]
    mb = rm.MeshBuilder()
    shell_with_arches(mb, profile, len(front), arches, hw, m, bottom, 0.06)
    for axle_y in (-3.6, 3.2):
        mb.box(-0.8, axle_y - radius, bottom, 0.8, axle_y + radius, -0.4, m["chassis"])
    # cream band and windows along both sides; doors on the left (+X) side
    for sx in (-1, 1):
        x_out = sx * (hw + 0.012)
        mb.box(min(sx * hw, x_out), -5.3, 0.15, max(sx * hw, x_out), 5.2, 1.45, cream)
        y = -4.55 if sx < 0 else -3.0
        while y < 4.9:
            mb.box(min(sx * hw, x_out + sx * 0.01), y, 0.3, max(sx * hw, x_out + sx * 0.01), y + 1.25, 1.35, m["glass"])
            y += 1.4
        if sx > 0:
            for door_y in (-4.95, 0.6):
                mb.box(hw - 0.01, door_y, -0.95, hw + 0.03, door_y + 1.2, 1.45, m["glass"])
                mb.box(hw + 0.03, door_y + 0.58, -0.95, hw + 0.04, door_y + 0.62, 1.45, m["trim"])
    mb.box(-1.18, -5.6, -0.15, 1.18, -5.5, 1.38, m["glass"])                 # windscreen
    mb.box(-1.1, -5.58, 1.42, 1.1, -5.5, 1.72, board)
    rm.pixel_text(mb, "CITY", 0.0, -5.58, 1.47, 0.045, lettering, depth=0.02)
    mb.box(-0.9, -1.5, 1.78, 0.9, 1.5, 2.1, cream)                           # roof air-conditioning
    mb.box(-1.25, -5.6, -1.0, 1.25, -5.48, -0.75, m["trim"])                  # bumpers
    mb.box(-1.25, 5.48, -1.0, 1.25, 5.6, -0.75, m["trim"])
    lamps(mb, m, -5.55, 5.5, (0.85, 1.15), (-0.6, -0.4), (0.9, 1.18), (-0.55, -0.15))
    mb.box(-0.25, 5.5, -0.7, 0.25, 5.54, -0.55, m["plate"])
    mb.build(name)
    rm.export_glb("vehicles", name)


def truck_body() -> None:
    """veh_truck_body: a 7.6 m cargo truck: painted cab at the front, a grey box body behind.
    Wheels r 0.5 centred at z -0.75 (road at -1.25); axles at y -2.8 and 2.4; body x +-1.2."""
    name = "veh_truck_body"
    rm.clear_scene()
    m = fleet_materials("#2c5f9e")
    box_m = rm.material("veh_truck_box", "#cfd2d4", roughness=0.6, metallic=0.2)
    rib = rm.material("veh_truck_rib", "#b5b9bc", roughness=0.55, metallic=0.25)
    hw = 1.2
    mb = rm.MeshBuilder()
    mb.box(-0.55, -3.7, -0.75, 0.55, 3.75, -0.5, m["chassis"])                # frame
    # cab: a box with a sloping windscreen, side windows, a step and a sun visor
    mb.convex_hull([(sx * hw, y, z) for sx in (-1, 1) for (y, z) in
                    ((-3.8, -0.55), (-3.85, 0.45), (-3.6, 1.55), (-2.0, 1.6), (-2.0, -0.55))], m["paint"])
    mb.convex_hull([(sx * (hw - 0.1), y, z) for sx in (-1, 1) for (y, z) in ((-3.87, 0.55), (-3.66, 1.42))] +
                   [(sx * (hw - 0.1), -3.75, z) for sx in (-1, 1) for z in (0.5, 1.4)], m["glass"])
    mirrored_box(mb, hw - 0.01, -3.35, 0.55, hw + 0.012, -2.4, 1.35, m["glass"])
    mirrored_box(mb, 0.9, -3.75, -0.85, 1.15, -3.3, -0.75, m["trim"])
    mb.box(-hw, -3.95, 1.55, hw, -3.6, 1.62, m["trim"])
    mirrored_box(mb, hw, -3.4, 0.8, hw + 0.25, -3.3, 1.1, m["trim"])          # mirrors
    # mudguards over the wheels
    for axle_y in (-2.8, 2.4):
        mirrored_box(mb, 0.75, axle_y - 0.65, -0.32, hw, axle_y + 0.65, -0.24, m["chassis"])
    # the cargo box: ribbed sides, doors at the back
    mb.box(-hw, -1.85, -0.5, hw, 3.8, 2.15, box_m)
    for y in [(-1.85 + 0.55 * k) for k in range(1, 11)]:
        mirrored_box(mb, hw, y - 0.04, -0.45, hw + 0.03, y + 0.04, 2.1, rib)
    mb.box(-0.02, 3.8, -0.45, 0.02, 3.83, 2.1, m["trim"])
    mb.box(-1.2, -3.95, -0.85, 1.2, -3.8, -0.6, m["trim"])                     # front bumper
    lamps(mb, m, -3.9, 3.8, (0.75, 1.05), (-0.45, -0.25), (0.85, 1.15), (-0.45, -0.25))
    mb.box(-0.3, -3.96, -0.55, 0.3, -3.92, -0.42, m["plate"])
    mb.build(name)
    rm.export_glb("vehicles", name)


def fleet_wheel(name: str, radius: float, width: float, rim_hex: str, spokes: int) -> None:
    """A wheel like the sedan's, scaled: the tyre profile is the sedan's stretched to `radius` and
    `width`; the rim has `spokes` spokes (8 short ones read as a steel wheel)."""
    rm.clear_scene()
    rubber = rm.material("veh_tyre", "#1c1c1e", roughness=0.92)
    rim = rm.material("veh_rim_" + name, rim_hex, roughness=0.3, metallic=0.9)
    dark = rm.material("veh_rim_dark", "#2a2c31", roughness=0.6, metallic=0.4)
    sr, sw = radius / 0.33, width / 0.216
    mb = rm.MeshBuilder()
    tyre = [(0.212 * sr, 0.104 * sw), (0.298 * sr, 0.108 * sw), (0.324 * sr, 0.095 * sw), (0.33 * sr, 0.055 * sw),
            (0.33 * sr, -0.055 * sw), (0.324 * sr, -0.095 * sw), (0.298 * sr, -0.108 * sw), (0.212 * sr, -0.104 * sw)]
    lathe_x(mb, tyre, 20, rubber, 0.27 * sr)
    lathe_x(mb, [(0.214 * sr, 0.094 * sw), (0.204 * sr, 0.088 * sw)], 20, rim, 0.0)
    mb.tube((0.06 * sw, 0.0, 0.0), (0.062 * sw, 0.0, 0.0), 0.205 * sr, 0.205 * sr, 20, dark, caps=True)
    mb.tube((-0.095 * sw, 0.0, 0.0), (-0.09 * sw, 0.0, 0.0), 0.212 * sr, 0.212 * sr, 20, dark, caps=True)
    inner = 0.05 * sr if spokes <= 6 else 0.13 * sr
    for k in range(spokes):
        start = mb.mark()
        mb.box(0.062 * sw, -0.026 * sr, inner, 0.088 * sw, 0.026 * sr, 0.205 * sr, rim)
        mb.transform_since(start, Matrix.Rotation(2 * math.pi * k / spokes, 4, "X"))
    mb.tube((0.055 * sw, 0.0, 0.0), (0.098 * sw, 0.0, 0.0), 0.065 * sr, 0.05 * sr, 10, rim)
    mb.build(name)
    rm.export_glb("vehicles", name)


def bike_body() -> None:
    """veh_bike_body (M7): a 150 cc street motorcycle, 2.1 m. Faces Blender -Y like the cars, pivot
    at the chassis centre: road at z -0.55, wheels (r 0.3) centred at z -0.25 on axles at y -0.68
    and 0.67. Painted tank and tail, black seat, chrome fork and exhaust, a round headlight."""
    name = "veh_bike_body"
    rm.clear_scene()
    m = fleet_materials("#1f4fa0")
    seat = rm.material("veh_bike_seat", "#141416", roughness=0.7)
    engine = rm.material("veh_bike_engine", "#55595f", roughness=0.4, metallic=0.7)
    mb = rm.MeshBuilder()
    # frame: steering head down to the swing-arm pivot, and back under the seat
    strut(mb, (0.0, -0.52, 0.3), (0.0, 0.12, -0.12), 0.035, m["trim"])
    strut(mb, (0.0, -0.45, 0.28), (0.0, 0.5, 0.18), 0.03, m["trim"])
    for sx in (-1, 1):                                          # swing arm to the rear axle
        strut(mb, (sx * 0.1, 0.12, -0.14), (sx * 0.1, 0.67, -0.25), 0.025, m["trim"])
        strut(mb, (sx * 0.08, -0.52, 0.32), (sx * 0.08, -0.68, -0.25), 0.025, m["chrome"])   # fork legs
    mb.box(-0.15, -0.28, -0.32, 0.15, 0.14, 0.02, engine)        # engine block
    for k in range(4):
        z = -0.26 + k * 0.07
        mb.box(-0.17, -0.24, z, 0.17, 0.08, z + 0.025, engine)    # cooling fins
    mb.convex_hull([(sx * w, y, z) for sx in (-1, 1) for (y, z, w) in
                    ((-0.46, 0.12, 0.1), (-0.42, 0.36, 0.13), (0.02, 0.36, 0.15), (0.06, 0.12, 0.13))], m["paint"])  # tank
    mb.box(-0.13, 0.02, 0.2, 0.13, 0.52, 0.29, seat)              # seat
    mb.convex_hull([(sx * w, y, z) for sx in (-1, 1) for (y, z, w) in
                    ((0.48, 0.18, 0.12), (0.5, 0.3, 0.12), (0.8, 0.33, 0.07), (0.82, 0.24, 0.07))], m["paint"])   # tail
    mb.box(-0.06, 0.8, 0.24, 0.06, 0.84, 0.3, m["tail"])
    mb.box(-0.09, 0.78, 0.05, 0.09, 0.8, 0.17, m["plate"])
    # front: mudguard over the wheel, handlebar, round headlight, small mirrors
    mb.convex_hull([(sx * 0.07, y, z) for sx in (-1, 1) for (y, z) in ((-0.95, -0.02), (-0.68, 0.08), (-0.45, -0.02), (-0.68, 0.11))], m["paint"])
    strut(mb, (-0.36, -0.48, 0.46), (0.36, -0.48, 0.46), 0.018, m["chrome"])
    strut(mb, (0.0, -0.52, 0.32), (0.0, -0.48, 0.46), 0.03, m["trim"])
    for sx in (-1, 1):
        strut(mb, (sx * 0.3, -0.48, 0.46), (sx * 0.38, -0.48, 0.46), 0.025, seat)   # grips
        strut(mb, (sx * 0.24, -0.48, 0.46), (sx * 0.27, -0.46, 0.62), 0.008, m["chrome"])
        mb.box(sx * 0.27 - 0.04, -0.47, 0.6, sx * 0.27 + 0.04, -0.45, 0.66, m["glass"])
    mb.tube((0.0, -0.58, 0.32), (0.0, -0.66, 0.32), 0.09, 0.09, 10, m["chrome"])
    mb.tube((0.0, -0.66, 0.32), (0.0, -0.67, 0.32), 0.08, 0.08, 10, m["head"])
    mb.tube((0.14, -0.05, -0.27), (0.17, 0.82, -0.08), 0.04, 0.05, 8, m["chrome"])      # exhaust
    mb.build(name)
    rm.export_glb("vehicles", name)

BUILDERS = {
    "veh_sedan_body": sedan_body,
    "veh_sedan_wheel": sedan_wheel,
    "veh_police_lightbar": police_lightbar,
    "veh_police_heli": police_heli,
    "veh_sports_body": sports_body,
    "veh_suv_body": suv_body,
    "veh_bus_body": bus_body,
    "veh_truck_body": truck_body,
    "veh_wheel_sport": lambda: fleet_wheel("veh_wheel_sport", 0.34, 0.27, "#2b2d31", 5),
    "veh_wheel_suv": lambda: fleet_wheel("veh_wheel_suv", 0.40, 0.26, "#9aa0a8", 6),
    "veh_wheel_heavy": lambda: fleet_wheel("veh_wheel_heavy", 0.50, 0.30, "#c9ccd0", 8),
    "veh_bike_body": bike_body,
    "veh_bike_wheel": lambda: fleet_wheel("veh_bike_wheel", 0.30, 0.11, "#2b2d31", 6),
}


def main() -> None:
    for name in (rm.script_args() or list(BUILDERS)):
        BUILDERS[name]()


main()
