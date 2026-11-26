# RISE OF THE DON — Standing rules

## Project
- **Game:** RISE OF THE DON — an original 3D open-world action-adventure set in Velanagar, a fictional South Indian coastal city.
- **Engine:** Godot 4.x (GDScript only, no C#). **Art:** Blender, run from scripts. **Target:** Windows PC first.
- **Everything is original.** Use no GTA (or other game) names, characters, maps, missions, logos, music, or UI layouts. Don't copy real brands onto vehicles, shops, or signs.
- Design reference: `docs/GAME_DESIGN.md`. Read only the sections the current task needs.

## Machine setup (confirmed 2026-11-24; standard Godot build since M8, 2026-11-26)
- Godot console executable (4.7.2 stable, standard build):
  `C:\Users\ADMIN\Downloads\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe`
- Godot editor executable (same folder): `Godot_v4.7.2-stable_win64.exe`
- Export templates for 4.7.2 (Windows x86_64) are installed in `%APPDATA%\Godot\export_templates\4.7.2.stable\`.
  Export: `"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/RiseOfTheDon.exe`
  (preset in `export_presets.cfg`; `build/` is git-ignored).
- The earlier .NET build (`Godot_v4.7.2-stable_mono_win64`) is still in Downloads but no longer used.
- Blender executable (4.0.2): `C:\Program Files\Blender Foundation\Blender 4.0\blender.exe`
- Project root: `D:\project\RISE OF THE DON` (this folder — the path contains spaces, always quote it)
- Shell: Claude Code on Windows runs Git Bash. Quote paths that contain spaces.
- Git Bash variables used in the commands below:
  ```bash
  GODOT="/c/Users/ADMIN/Downloads/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
  BLENDER="/c/Program Files/Blender Foundation/Blender 4.0/blender.exe"
  ```
- Physics engine: Jolt Physics (built into Godot 4.4+), set in `project.godot`.
- Treat every `ERROR:` as a failure. (The `.NET Sdk not found` message of the old .NET editor no longer appears.)

## How to validate work (you cannot see the screen, so these are your eyes)
1. **Import / parse check:** `"$GODOT" --headless --path . --import` (re-imports assets and reports script parse errors).
2. **Smoke test:** `"$GODOT" --headless --path . res://tests/smoke_test.tscn`. This scene loads the main game, simulates input for a few hundred frames, asserts expected state (for example "the player moved more than 5 m", "the car speed is above 0 after throttle"), prints `SMOKE TEST PASSED` or `FAILED: <reason>`, and quits with exit code 0 or 1. Add assertions to it for every new feature.
   Per-feature test scenes sit next to it, e.g. `"$GODOT" --headless --path . --fixed-fps 60 res://tests/vehicle_test.tscn` (vehicle handling report with sanity ranges; `--fixed-fps 60` runs it faster than real time).
3. Treat any `SCRIPT ERROR`, `ERROR:`, or parse error in the output as a failure. Fix it before moving on.
4. Headless runs prove the logic works, not that it feels or looks right. For anything visual or feel-based (camera, handling, lighting, UI layout), say exactly what the user should check in the editor, and don't mark it done until they confirm.
5. **Screenshots (optional extra eyes):** `"$GODOT" --path . res://tests/screenshot.tscn -- --scene=res://scenes/... --out=<abs path>.png` renders a scene in a real window for a few frames and saves a PNG you can open with the Read tool. It also surfaces shader compile errors, which headless runs cannot. It is a sanity check, not a substitute for the user's own look.

## Blender pipeline
- Generate assets with Python scripts in `tools/blender/`, run as `"$BLENDER" --background --factory-startup --python tools/blender/<script>.py -- <args>`. You cannot use the Blender GUI. (`--factory-startup` keeps the user's own Blender preferences and add-ons from affecting the output.)
- `tools/blender/build_all.sh` re-runs every generator, then re-import in Godot.
- Shared helpers live in `tools/blender/rotd_mesh.py` (mesh builder, materials, GLB export).
- Export GLB to `assets/models/<category>/`. Use 1 unit = 1 metre, +Y up in Godot (export with Blender's default glTF Y-up conversion), the pivot at the base centre (buildings, props, characters) or the chassis centre (vehicles), and apply transforms before export.
- Naming: `bld_`, `veh_`, `prop_`, `chr_`, `road_`. Name collision meshes with the `-col` / `-colonly` suffix so Godot's importer builds collision automatically. For collision made of several pieces, use `rm.CollisionSet` (one `-convcolonly` object per piece) so pieces never fuse into one hull.
- The streamed city is generated from the models: after changing a model the city uses or a district layout (`scripts/world/*_layout.gd`), re-import and run `"$GODOT" --headless --path . --script res://tools/godot/build_city.gd` (`build_all.sh` does both). Never hand-edit the generated chunk scenes, kit meshes, lane graph, city map or city manifest.
- Keep each generator script re-runnable. Re-running it overwrites only its own outputs.
- Low-poly, stylised geometry with simple PBR materials is the target. Don't chase photorealism from code.

## Code rules
- One responsibility per script. Use signals between systems. Autoloads only for real global state: `GameState`, `SaveManager`, `MissionManager`, `EconomyManager`, `WantedSystem`, `AudioManager`, `Settings`.
- Statically type GDScript (`var speed: float = 0.0`, typed function signatures).
- Put tunables in Resources (`.tres`) under `resources/`, not hard-coded. This covers vehicle handling, mission definitions, shop items, and NPC density.
- Prefer building complex node trees in code or in small, simple `.tscn` files. Hand-written `.tscn` files must be valid Godot 4 format. Never invent `uid://` values; omit them and let Godot assign them on import.
- Use the input map for all controls (`project.godot` `[input]` section), never raw keycodes in gameplay scripts. The input map is generated by `tools/godot/setup_project.gd` — edit that script and re-run it rather than hand-editing `[input]`.
- Don't write TODO stubs for anything the current milestone needs, and don't add buttons that do nothing. If something is out of scope, leave it out and list it in the report.

## Safety and workflow
- The project is a git repo. Commit after each working milestone with a clear message. Never force-push or rewrite history.
- Never delete or overwrite the user's files (especially anything in `assets/` they made by hand) without asking.
- Work in small steps: implement → run validation → fix → commit. Don't start the next feature while the current one is failing.
- Stop at the end of each milestone and wait for the user's approval before starting the next.
- Keep these updated: `DEVELOPMENT_LOG.md` (dated entries: what was built, what broke, how it was fixed), `README.md` (setup, run, controls), `TESTING.md` (manual test checklist per feature).

## End-of-milestone report format
1. What now works (only what you actually ran and verified)
2. Files created or changed
3. Errors hit and how they were fixed
4. What the user must test by hand, as a numbered checklist
5. Known issues and what's next
