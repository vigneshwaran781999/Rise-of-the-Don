"""Modular road kit -> assets/models/road/

Pieces (Blender axes; after import Blender +Y becomes Godot -Z):
  road_straight        12 x 12 m, runs along Y. 4 lanes (left-hand traffic), road top at z = 0.
  road_crosswalk       straight piece with a zebra crossing at its +Y end (Godot -Z) and a stop
                       line for the lanes approaching that end.
  road_intersection    12 x 12 m plain junction.
  road_sidewalk        4 m wide x 8 m long, top at 0.15 m. Curb on the -X side (Godot -X).
  road_sidewalk_corner 4 x 4 m. Curbs on the -X and -Y sides (Godot -X and +Z).

Collision ('-colonly') for sidewalks is bevelled on the curb side (about 27 degrees) so a
character capsule can step up onto the kerb.

Run:  "$BLENDER" --background --factory-startup --python tools/blender/road_kit.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rotd_mesh as rm  # noqa: E402

TILE = 12.0
HALF = TILE / 2.0
MARK_Z = 0.006          # markings sit just above the asphalt
CURB_H = 0.17
WALK_H = 0.15


def mats() -> dict:
    return {
        "asphalt": rm.material("asphalt", "#2e2e33", roughness=0.93),
        "white": rm.material("marking_white", "#e9e7df", roughness=0.6),
        "yellow": rm.material("marking_yellow", "#e3b21f", roughness=0.6),
        "paver_a": rm.material("paver_a", "#a39e94", roughness=0.9),
        "paver_b": rm.material("paver_b", "#958f85", roughness=0.9),
        "curb_y": rm.material("curb_yellow", "#e8c21c", roughness=0.7),
        "curb_k": rm.material("curb_black", "#202022", roughness=0.7),
        "col": rm.collision_material(),
    }


def top_quad(mb: rm.MeshBuilder, x0: float, y0: float, x1: float, y1: float, z: float, mat) -> None:
    mb.box(x0, y0, z, x1, y1, z, mat, skip=("bottom", "front", "back", "left", "right"))


def road_collision(name: str, m: dict) -> None:
    col = rm.MeshBuilder()
    col.box(-HALF, -HALF, -0.5, HALF, HALF, 0.0, m["col"])
    col.build(name + "-colonly")


def lane_markings(mb: rm.MeshBuilder, m: dict, y_end: float = HALF, dashes_until: float = HALF) -> None:
    """Edge lines, double yellow centre line (to y_end) and dashed lane lines (dashes 3 m on, 3 m off)."""
    for sx in (-1.0, 1.0):
        top_quad(mb, sx * 5.475, -HALF, sx * 5.625, HALF, MARK_Z, m["white"])
        top_quad(mb, sx * 0.07, -HALF, sx * 0.17, y_end, MARK_Z, m["yellow"])
        for d0, d1 in ((-4.5, -1.5), (1.5, 4.5)):
            if d1 <= dashes_until:
                top_quad(mb, sx * 2.94, d0, sx * 3.06, d1, MARK_Z, m["white"])


def build_straight() -> None:
    rm.clear_scene()
    m = mats()
    mb = rm.MeshBuilder()
    top_quad(mb, -HALF, -HALF, HALF, HALF, 0.0, m["asphalt"])
    lane_markings(mb, m)
    mb.build("road_straight")
    road_collision("road_straight", m)
    rm.export_glb("road", "road_straight")


def build_crosswalk() -> None:
    rm.clear_scene()
    m = mats()
    mb = rm.MeshBuilder()
    top_quad(mb, -HALF, -HALF, HALF, HALF, 0.0, m["asphalt"])
    lane_markings(mb, m, y_end=1.9, dashes_until=1.5)
    # Stop line across the lanes approaching the +Y end (left-hand traffic keeps to -X when heading +Y).
    top_quad(mb, -5.45, 1.9, -0.25, 2.25, MARK_Z, m["white"])
    # Zebra stripes, 0.55 m wide on a 1 m pitch, 3 m long.
    for i in range(11):
        cx = -5.0 + i * 1.0
        top_quad(mb, cx - 0.275, 2.7, cx + 0.275, 5.7, MARK_Z, m["white"])
    mb.build("road_crosswalk")
    road_collision("road_crosswalk", m)
    rm.export_glb("road", "road_crosswalk")


def build_intersection() -> None:
    rm.clear_scene()
    m = mats()
    mb = rm.MeshBuilder()
    top_quad(mb, -HALF, -HALF, HALF, HALF, 0.0, m["asphalt"])
    mb.build("road_intersection")
    road_collision("road_intersection", m)
    rm.export_glb("road", "road_intersection")


def curb_run(mb: rm.MeshBuilder, m: dict, along_x: bool, start: float, end: float,
             fixed0: float, fixed1: float, first_yellow: bool) -> None:
    """Kerb stones painted in alternating 1 m yellow/black blocks."""
    inner = [float(k) for k in range(math.floor(start) + 1, math.ceil(end)) if start < k < end]
    edges = [start] + inner + [end]
    for i in range(len(edges) - 1):
        a, b = edges[i], edges[i + 1]
        mat = m["curb_y"] if (i % 2 == 0) == first_yellow else m["curb_k"]
        if along_x:
            mb.box(a, fixed0, 0.0, b, fixed1, CURB_H, mat, skip=("bottom", "left", "right"))
        else:
            mb.box(fixed0, a, 0.0, fixed1, b, CURB_H, mat, skip=("bottom", "front", "back"))


def build_sidewalk() -> None:
    rm.clear_scene()
    m = mats()
    mb = rm.MeshBuilder()
    # Kerb along -X, 8 m long.
    curb_run(mb, m, along_x=False, start=-4.0, end=4.0, fixed0=-2.0, fixed1=-1.75, first_yellow=True)
    # Paving slabs, 2 m each, two alternating tones.
    for i in range(4):
        y0 = -4.0 + i * 2.0
        top_quad(mb, -1.75, y0, 2.0, y0 + 2.0, WALK_H, m["paver_a"] if i % 2 == 0 else m["paver_b"])
    mb.build("road_sidewalk")

    col = rm.MeshBuilder()
    col.convex_hull([
        (-2.0, -4.0, -0.3), (2.0, -4.0, -0.3), (2.0, 4.0, -0.3), (-2.0, 4.0, -0.3),
        (-2.0, -4.0, 0.0), (-2.0, 4.0, 0.0),
        (-1.7, -4.0, WALK_H), (2.0, -4.0, WALK_H), (2.0, 4.0, WALK_H), (-1.7, 4.0, WALK_H),
    ], m["col"])
    col.build("road_sidewalk-colonly")
    rm.export_glb("road", "road_sidewalk")


def build_sidewalk_corner() -> None:
    rm.clear_scene()
    m = mats()
    mb = rm.MeshBuilder()
    curb_run(mb, m, along_x=False, start=-2.0, end=2.0, fixed0=-2.0, fixed1=-1.75, first_yellow=True)
    curb_run(mb, m, along_x=True, start=-1.75, end=2.0, fixed0=-2.0, fixed1=-1.75, first_yellow=False)
    top_quad(mb, -1.75, -1.75, 2.0, 2.0, WALK_H, m["paver_a"])
    mb.build("road_sidewalk_corner")

    col = rm.MeshBuilder()
    col.convex_hull([
        (-2.0, -2.0, -0.3), (2.0, -2.0, -0.3), (2.0, 2.0, -0.3), (-2.0, 2.0, -0.3),
        (-2.0, -2.0, 0.0), (-2.0, 2.0, 0.0), (2.0, -2.0, 0.0),
        (-1.7, -1.7, WALK_H), (-1.7, 2.0, WALK_H), (2.0, -1.7, WALK_H), (2.0, 2.0, WALK_H),
    ], m["col"])
    col.build("road_sidewalk_corner-colonly")
    rm.export_glb("road", "road_sidewalk_corner")


BUILDERS = {
    "road_straight": build_straight,
    "road_crosswalk": build_crosswalk,
    "road_intersection": build_intersection,
    "road_sidewalk": build_sidewalk,
    "road_sidewalk_corner": build_sidewalk_corner,
}


def main() -> None:
    wanted = rm.script_args() or list(BUILDERS)
    for name in wanted:
        BUILDERS[name]()


main()
