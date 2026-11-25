"""Pedestrian figures (M4) -> assets/models/characters/

Low-poly placeholder people, about 1.7 m tall, standing on the origin and facing Blender -Y
(Godot +Z). Each is split into parts so the game can animate a walk cycle in the vertex shader:
  body              origin at the feet (torso, head, hair, skirt or veshti)
  leg_l, leg_r      origin at the hip joint: the leg swings around it
  arm_l, arm_r      origin at the shoulder joint
Materials name the colour channels the game tints per person: chr_top (shirt, blouse),
chr_bottom (trousers, skirt, veshti), chr_skin, chr_hair. Others keep their colour.

  chr_ped_man     shirt, trousers, shoes
  chr_ped_woman   blouse, long skirt to the ankles, hair in a long braid, sandals
  chr_ped_elder   shirt, white veshti, towel over the shoulder, grey hair, sandals

No collision: the game gives pedestrians a capsule.

Run:  "$BLENDER" --background --factory-startup --python tools/blender/characters.py [-- names...]
"""

import os
import sys


sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rotd_mesh as rm  # noqa: E402

HIP_Z = 0.92
HIP_X = 0.09
SHOULDER_Z = 1.40
SHOULDER_X = 0.215


def mats() -> dict:
    return {
        "skin": rm.material("chr_skin", "#ffffff", roughness=0.7),
        "hair": rm.material("chr_hair", "#ffffff", roughness=0.8),
        "top": rm.material("chr_top", "#ffffff", roughness=0.85),
        "bottom": rm.material("chr_bottom", "#ffffff", roughness=0.85),
        "shoe": rm.material("chr_shoes", "#2a221c", roughness=0.7),
        "sole": rm.material("chr_sole", "#3a2c22", roughness=0.8),
        "towel": rm.material("chr_towel", "#efe9dc", roughness=0.9),
        "dark": rm.material("chr_detail", "#1d1b1a", roughness=0.8),
    }


def part(name: str, builder: rm.MeshBuilder, pivot: tuple) -> None:
    obj = builder.build(name)
    obj.location = pivot


def head(mb: rm.MeshBuilder, m: dict, hair: str) -> None:
    mb.cylinder(0, 0, 1.43, 0.055, 0.05, 0.1, 8, m["skin"])
    mb.sphere((0, 0, 1.62), 0.105, 10, 6, m["skin"], squash=1.15)
    mb.box(-0.025, -0.115, 1.59, 0.025, -0.095, 1.63, m["skin"])            # nose
    for x in (-0.04, 0.04):
        mb.box(x - 0.015, -0.1, 1.645, x + 0.015, -0.09, 1.66, m["dark"])  # eyes
    if hair == "short":
        mb.sphere((0, 0.012, 1.655), 0.112, 10, 5, m["hair"], squash=0.9)
    elif hair == "braid":
        mb.sphere((0, 0.015, 1.65), 0.115, 10, 5, m["hair"], squash=1.0)
        mb.tube((0, 0.1, 1.6), (0, 0.13, 1.08), 0.035, 0.02, 6, m["hair"])
    else:  # grey, receding
        mb.sphere((0, 0.03, 1.64), 0.11, 10, 5, m["hair"], squash=0.85)


def torso(mb: rm.MeshBuilder, m: dict) -> None:
    mb.frustum(0, 0, 0.95, 0.31, 0.19, 0.38, 0.21, 0.47, m["top"], bottom=True)
    mb.box(-0.045, -0.11, 1.35, 0.045, -0.1, 1.42, m["skin"])               # open neckline


def arms(m: dict, sleeve: float) -> None:
    for name, sx in (("arm_l", 1.0), ("arm_r", -1.0)):
        mb = rm.MeshBuilder()
        mb.frustum(0, 0, -sleeve, 0.105, 0.1, 0.11, 0.105, sleeve + 0.03, m["top"], bottom=True)
        mb.frustum(0, 0, -0.6, 0.065, 0.065, 0.08, 0.08, 0.6 - sleeve, m["skin"], bottom=True)
        mb.box(-0.04, -0.035, -0.7, 0.04, 0.035, -0.6, m["skin"])
        part(name, mb, (sx * SHOULDER_X, 0.0, SHOULDER_Z))


def legs(m: dict, long_skirt: bool) -> None:
    for name, sx in (("leg_l", 1.0), ("leg_r", -1.0)):
        mb = rm.MeshBuilder()
        if long_skirt:
            # Only the shins show below the hem; they still swing from the hip.
            mb.frustum(0, 0, -0.86, 0.075, 0.075, 0.085, 0.085, 0.36, m["skin"], bottom=True)
            mb.box(-0.05, -0.15, -0.92, 0.05, 0.05, -0.89, m["sole"])
            mb.box(-0.045, -0.13, -0.89, 0.045, 0.03, -0.86, m["skin"])
        else:
            mb.frustum(0, 0, -0.85, 0.1, 0.1, 0.14, 0.14, 0.85, m["bottom"], bottom=True)
            mb.box(-0.055, -0.16, -0.92, 0.055, 0.06, -0.85, m["shoe"])
        part(name, mb, (sx * HIP_X, 0.0, HIP_Z))


def person(name: str, kind: str) -> None:
    rm.clear_scene()
    m = mats()
    body = rm.MeshBuilder()
    torso(body, m)
    if kind == "man":
        body.box(-0.16, -0.1, 0.84, 0.16, 0.1, 0.98, m["bottom"])               # hips in trousers
        head(body, m, "short")
        arms(m, 0.3)
        legs(m, long_skirt=False)
    elif kind == "woman":
        body.frustum(0, 0, 0.12, 0.44, 0.34, 0.32, 0.22, 0.86, m["bottom"], bottom=True)
        body.box(-0.17, -0.11, 0.93, 0.17, 0.11, 1.0, m["skin"])                # waist
        head(body, m, "braid")
        arms(m, 0.18)
        legs(m, long_skirt=True)
    else:
        body.frustum(0, 0, 0.16, 0.38, 0.3, 0.32, 0.22, 0.82, m["bottom"], bottom=True)
        body.box(-0.17, -0.11, 0.94, 0.17, 0.11, 0.99, m["bottom"])             # folded waist
        body.box(0.06, -0.12, 1.1, 0.2, 0.12, 1.47, m["towel"])                 # towel over the shoulder
        head(body, m, "grey")
        arms(m, 0.3)
        legs(m, long_skirt=True)
    part("body", body, (0.0, 0.0, 0.0))
    rm.export_glb("characters", name)


BUILDERS = {
    "chr_ped_man": lambda: person("chr_ped_man", "man"),
    "chr_ped_woman": lambda: person("chr_ped_woman", "woman"),
    "chr_ped_elder": lambda: person("chr_ped_elder", "elder"),
}


def main() -> None:
    for name in (rm.script_args() or list(BUILDERS)):
        BUILDERS[name]()


main()
