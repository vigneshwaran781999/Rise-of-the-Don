"""M0 pipeline check: export a 1 m test cube with auto-collision to assets/models/test/.

Run from the project root (Git Bash):
    "$BLENDER" --background --python tools/blender/test_cube.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rotd_mesh as rm  # noqa: E402


def main() -> None:
    rm.clear_scene()

    orange = rm.material("test_orange", "#ff7a1a", roughness=0.6)
    visual = rm.MeshBuilder()
    visual.box_c(0.0, 0.0, 0.0, 1.0, 1.0, 1.0, orange)  # pivot at base centre
    visual.build("prop_test_cube")

    col = rm.MeshBuilder()
    col.box_c(0.0, 0.0, 0.0, 1.0, 1.0, 1.0, rm.collision_material())
    col.build("prop_test_cube-colonly")

    rm.export_glb("test", "prop_test_cube")


main()
