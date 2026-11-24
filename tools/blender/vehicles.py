"""Vehicles -> assets/models/vehicles/

  veh_sedan_body    4.5 m four-door sedan body (no wheels), unbadged, crimson paint
  veh_sedan_wheel   0.33 m radius wheel: tyre plus a five-spoke rim facing Blender +X

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


BUILDERS = {
    "veh_sedan_body": sedan_body,
    "veh_sedan_wheel": sedan_wheel,
}


def main() -> None:
    for name in (rm.script_args() or list(BUILDERS)):
        BUILDERS[name]()


main()
