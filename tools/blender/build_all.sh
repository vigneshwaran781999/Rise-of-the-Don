#!/usr/bin/env bash
# Re-runs every Blender asset generator, re-imports the project in Godot, then rebuilds the
# streamed city (kit meshes, chunk scenes, navmesh, lane graph, map).
# Run from the project root in Git Bash:   bash tools/blender/build_all.sh
set -euo pipefail
BLENDER="${BLENDER:-/c/Program Files/Blender Foundation/Blender 4.0/blender.exe}"
GODOT="${GODOT:-/c/Users/ADMIN/Downloads/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe}"

GENERATORS=(
  test_cube.py
  road_kit.py
  buildings.py
  props.py
  vehicles.py
  characters.py
  humans.py
  old_town.py
  downtown.py
)

for gen in "${GENERATORS[@]}"; do
  echo "== $gen"
  "$BLENDER" --background --factory-startup --python "tools/blender/$gen" 2>&1 | grep -E "^EXPORTED|Error|Traceback" || true
done

echo "== Godot import"
"$GODOT" --headless --path . --import 2>&1 | grep -E "ERROR|SCRIPT ERROR" | grep -v "NET Sdk not found" || true

echo "== City (every district)"
"$GODOT" --headless --path . --script res://tools/godot/build_city.gd 2>&1 | grep -E "build_city|ERROR" || true

echo "== Godot import (the city map image the build just drew)"
"$GODOT" --headless --path . --import 2>&1 | grep -E "ERROR|SCRIPT ERROR" | grep -v "NET Sdk not found" || true
echo "done"
