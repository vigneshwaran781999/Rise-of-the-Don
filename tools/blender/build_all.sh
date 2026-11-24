#!/usr/bin/env bash
# Re-runs every Blender asset generator, then re-imports the project in Godot.
# Run from the project root in Git Bash:   bash tools/blender/build_all.sh
set -euo pipefail
BLENDER="${BLENDER:-/c/Program Files/Blender Foundation/Blender 4.0/blender.exe}"
GODOT="${GODOT:-/c/Users/ADMIN/Downloads/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe}"

GENERATORS=(
  test_cube.py
  road_kit.py
  buildings.py
  props.py
)

for gen in "${GENERATORS[@]}"; do
  echo "== $gen"
  "$BLENDER" --background --factory-startup --python "tools/blender/$gen" 2>&1 | grep -E "^EXPORTED|Error|Traceback" || true
done

echo "== Godot import"
"$GODOT" --headless --path . --import 2>&1 | grep -E "ERROR|SCRIPT ERROR" | grep -v "NET Sdk not found" || true
echo "done"
