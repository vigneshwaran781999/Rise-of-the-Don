"""Street props -> assets/models/props/

  prop_streetlight   8.4 m pole, arm reaching 2.6 m along Blender +X (Godot +X), warm emissive lens
  prop_palm_tree     7.5 m leaning coconut palm with drooping fronds and a coconut cluster
  prop_temple_wall   4 m compound-wall segment along X, painted in red and white vertical stripes

Pivot at the base centre. Collision is a simple '-colonly' box.

Run:  "$BLENDER" --background --factory-startup --python tools/blender/props.py [-- names...]
"""

import math
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rotd_mesh as rm  # noqa: E402


def streetlight() -> None:
    name = "prop_streetlight"
    rm.clear_scene()
    base_m = rm.material("lamp_base", "#3a3d42", roughness=0.6, metallic=0.4)
    pole_m = rm.material("lamp_pole", "#5b6068", roughness=0.45, metallic=0.6)
    lens_m = rm.material("lamp_lens", "#ffe2b0", roughness=0.3, emission="#ffd590", emission_strength=1.5)

    mb = rm.MeshBuilder()
    mb.box_c(0.0, 0.0, 0.0, 0.36, 0.36, 0.6, base_m, skip=("bottom",))
    mb.tube((0.0, 0.0, 0.6), (0.0, 0.0, 8.2), 0.1, 0.075, 8, pole_m)
    mb.tube((0.0, 0.0, 7.9), (1.2, 0.0, 8.35), 0.06, 0.05, 6, pole_m)
    mb.tube((1.2, 0.0, 8.35), (2.4, 0.0, 8.42), 0.05, 0.045, 6, pole_m)
    mb.box(2.0, -0.22, 8.25, 2.9, 0.22, 8.47, base_m, skip=("bottom",))
    mb.box(2.05, -0.18, 8.22, 2.85, 0.18, 8.25, lens_m, skip=("top",))
    mb.build(name)

    col = rm.MeshBuilder()
    col.box_c(0.0, 0.0, 0.0, 0.36, 0.36, 8.2, rm.collision_material())
    col.build(name + "-colonly")
    rm.export_glb("props", name)


def palm_tree() -> None:
    name = "prop_palm_tree"
    rm.clear_scene()
    bark_a = rm.material("palm_bark_a", "#7a5c40", roughness=0.95)
    bark_b = rm.material("palm_bark_b", "#664b33", roughness=0.95)
    leaf = rm.material("palm_leaf", "#3f7d3a", roughness=0.8, double_sided=True)
    leaf_dark = rm.material("palm_leaf_dark", "#2f6230", roughness=0.8, double_sided=True)
    nut = rm.material("coconut", "#6b5a24", roughness=0.7)

    height, lean, segs = 7.5, 1.2, 8
    mb = rm.MeshBuilder()

    def trunk_point(t: float) -> Vector:
        return Vector((lean * t * t, 0.0, height * t))

    for i in range(segs):
        t0, t1 = i / segs, (i + 1) / segs
        r0 = 0.24 - 0.09 * t0
        r1 = 0.24 - 0.09 * t1
        mb.tube(trunk_point(t0), trunk_point(t1), r0 + 0.015, r1, 7, bark_a if i % 2 == 0 else bark_b,
                caps=(i == 0 or i == segs - 1))
    top = trunk_point(1.0)

    # Fronds: rise, then droop; a raised mid-rib gives each leaf a shallow V.
    fronds = 10
    for f in range(fronds):
        ang = 2.0 * math.pi * f / fronds + (0.25 if f % 2 else 0.0)
        length = 3.4 if f % 2 == 0 else 3.0
        droop = 2.4 if f % 2 == 0 else 1.9
        d = Vector((math.cos(ang), math.sin(ang), 0.0))
        side = Vector((-math.sin(ang), math.cos(ang), 0.0))
        steps = 6
        left, mid, right = [], [], []
        for k in range(steps + 1):
            s = k / steps
            centre = top + d * (length * s) + Vector((0.0, 0.0, 0.9 * s - droop * s * s))
            half_w = 0.55 * math.sin(math.pi * min(1.0, 0.12 + s * 0.95)) * (1.0 - 0.35 * s)
            left.append(centre + side * half_w - Vector((0, 0, 0.06 * half_w)))
            right.append(centre - side * half_w - Vector((0, 0, 0.06 * half_w)))
            mid.append(centre + Vector((0, 0, 0.12 * half_w)))
        mat = leaf if f % 3 else leaf_dark
        for k in range(steps):
            mb.face([left[k], mid[k], mid[k + 1], left[k + 1]], mat, outward=(0, 0, 1))
            mb.face([mid[k], right[k], right[k + 1], mid[k + 1]], mat, outward=(0, 0, 1))
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        mb.sphere(top + Vector((0.28 * math.cos(a), 0.28 * math.sin(a), -0.35)), 0.16, 7, 5, nut)
    mb.build(name)

    col = rm.MeshBuilder()
    col.box_c(0.0, 0.0, 0.0, 0.5, 0.5, 4.0, rm.collision_material())
    col.build(name + "-colonly")
    rm.export_glb("props", name)


def temple_wall() -> None:
    name = "prop_temple_wall"
    rm.clear_scene()
    granite = rm.material("granite", "#7d7468", roughness=0.9)
    red = rm.material("wall_red", "#b3261e", roughness=0.85)
    white = rm.material("wall_white", "#f2ede4", roughness=0.85)
    cream = rm.material("gopuram_cornice", "#efe6d2", roughness=0.8)

    mb = rm.MeshBuilder()
    mb.box(-2.0, -0.3, 0.0, 2.0, 0.3, 0.3, granite, skip=("bottom", "left", "right"))
    for i in range(8):
        x0 = -2.0 + i * 0.5
        mb.box(x0, -0.25, 0.3, x0 + 0.5, 0.25, 2.1, red if i % 2 == 0 else white,
               skip=("bottom", "top", "left", "right"))
    mb.box(-2.0, -0.32, 2.1, 2.0, 0.32, 2.4, cream, skip=("left", "right"))
    mb.build(name)

    col = rm.MeshBuilder()
    col.box(-2.0, -0.3, 0.0, 2.0, 0.3, 2.4, rm.collision_material())
    col.build(name + "-colonly")
    rm.export_glb("props", name)


BUILDERS = {
    "prop_streetlight": streetlight,
    "prop_palm_tree": palm_tree,
    "prop_temple_wall": temple_wall,
}


def main() -> None:
    for name in (rm.script_args() or list(BUILDERS)):
        BUILDERS[name]()


main()
