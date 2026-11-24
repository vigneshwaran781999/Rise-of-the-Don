# RISE OF THE DON — Game Design Document

*Tagline: THE CITY NEVER FORGIVES.*

This is the reference spec. It describes the **end goal**. The milestones in section 15 decide what gets built and when. Build only what the current milestone asks for.

---

## 1. Identity
- **Genre:** 3D open world, action-adventure, crime story, driving, exploration, mission-based.
- **Mode:** Single-player, third-person.
- **Platform:** Windows PC first. Keep input and rendering abstracted so Android can be added later (use the Mobile or Forward+ renderer consistently, and route all input through the input map).
- **Visual target:** Stylised-realistic, cinematic lighting, low-to-mid poly. Atmosphere (lighting, fog, colour grading, neon at night) carries the look, not polygon count.
- **Originality:** Original city, characters, story, dialogue, music, logos, and UI. Inspired by the *freedom* of classic open-world crime games, never their content.

## 2. Setting: Velanagar
A fictional modern South Indian coastal metropolis. The currency is ₹.

| # | District | Contents | Mood |
|---|----------|----------|------|
| 1 | Downtown | Skyscrapers, offices, hotels, malls, busy multi-lane roads | Glass and steel, neon at night |
| 2 | Beach District | Beaches, resorts, seafood restaurants, palms, coastal road | Warm, sunset-heavy |
| 3 | Old Town | Traditional South Indian streets, markets, small shops, temple gopurams as skyline landmarks, tight lanes | Dense, colourful, lively |
| 4 | Industrial Zone | Factories, warehouses, container yard, harbour, cranes | Grey, sodium-lamp orange at night |
| 5 | Luxury District | Villas, mansions, gated gardens, premium cars | Clean, quiet, guarded |
| 6 | Countryside | Villages, paddy fields, lakes, coconut groves, small roads | Green, open, a calm escape |

Also: highways linking the districts, an airport (edge of map), police stations (one per district or so), a fishing harbour.

**World structure:** a grid of chunks (for example 256 m × 256 m), each its own scene, streamed in and out around the player by a `WorldStreamer`. Never one giant mesh. Buildings and props are instanced, with MultiMeshInstance3D for repeated items (trees, lamps, bollards) and visibility ranges (HLOD) for distant detail.

## 3. Story outline
The protagonist (original character, name to be decided in M6) arrives in Velanagar broke and unknown. He takes small jobs, gets pulled into the city's underworld, and climbs through rival gangs, corrupt officials, business owners, a persistent detective, and powerful bosses. The endgame is a choice about what kind of "don" he becomes and the city's future (2–3 endings).

**Opening missions:**
1. **Welcome to Velanagar.** Arrive by bus, explore the nearby block, reach a marker (tutorial: movement, camera, map).
2. **First Opportunity.** Meet a local fixer and deliver a package on foot, then by borrowed scooter (tutorial: interaction, vehicles).
3. **The New Connection.** Meet an important contact, with a dialogue scene that unlocks new contacts and a shop.
4. **City Chase.** Driving challenge through checkpoints while police pursue (tutorial: wanted system, escaping).
5. **Building an Empire.** Earn ₹X through side jobs and buy your first property, which becomes a save point and income source.

Later story missions, characters, and dialogue get written in M6, with the user's input.

## 4. Player character
- `CharacterBody3D` with a capsule collider.
- States (a simple state machine): Idle, Walk, Run, Sprint, Jump, Fall, Land, Swim, Punch, Interact, EnterVehicle, ExitVehicle, InVehicle, Dead.
- Stamina drains while sprinting or swimming and regenerates otherwise. Health takes damage, regenerates slowly to 50%, and on death you respawn at a hospital with a cash penalty.
- Camera: a SpringArm3D third-person rig with mouse look, pitch clamp, collision, smoothing, and a separate vehicle camera mode.
- **Art plan:** placeholder capsule with a facing indicator first. Then a rigged humanoid in GLB with an AnimationTree (BlendSpace for locomotion plus one-shots). Free-licence sources are allowed for animations and base meshes (CC0 packs such as Quaternius, or Mixamo under its licence), with the licence recorded in `CREDITS.md`. The character scene must accept any humanoid GLB that follows the bone-naming convention, so models can be swapped without code changes.

## 5. Vehicles
- `VehicleBody3D` + `VehicleWheel3D` (use the Jolt physics engine if the Godot version has it built in, 4.4+, and note the choice in the log).
- Data-driven: a `VehicleStats` resource (mass, engine force, brake, max steer, steer speed, suspension stiffness/travel/damping, friction slip, top speed, health).
- Features: enter/exit (nearest vehicle within 3 m, F key), throttle, brake, reverse, handbrake, steering, wheel spin and steer visuals, collision damage (health plus visual smoke when it gets low), speedometer, chase and hood cameras, horn, headlights.
- Roster: sports car, sedan, SUV, motorcycle, bus, truck. **Build one sedan fully first.** The motorcycle is a separate controller (lean, simplified physics) and comes last.

## 6. NPCs and traffic
- **Pedestrians:** NavigationAgent3D on baked sidewalk navmeshes. Behaviours: wander, idle, talk in pairs, sit, flee from gunfire or crashes, react to the player bumping them.
- **Traffic:** follows a lane graph (Path3D or a custom node graph per road piece), not navmesh. It stops at signals, keeps distance with a forward raycast, and swerves or brakes for obstacles.
- Spawn and despawn in a ring around the player. Density is set in `Settings` (low, medium, high).

## 7. Police and wanted system (fictional mechanics)
| Level | Response |
|---|---|
| 0 | None |
| 1 | Nearby officers investigate on foot |
| 2 | Patrol cars pursue |
| 3 | Multiple cars, attempted roadblocks |
| 4 | Aggressive pursuit, spike strips |
| 5 | Citywide response, helicopter searchlight |

Crimes add heat. Being seen refreshes it. Breaking line of sight starts a search zone (a shrinking circle on the minimap), and staying outside it for N seconds clears one level. HUD shows stars or badges. A respray garage clears level ≤ 3 for a fee.

## 8. Missions
- `MissionData` resource: id, title, description, category, giver, start marker, ordered objectives (go-to, deliver, drive-through-checkpoints, reach-speed, lose-wanted, talk-to, buy-property, timer), rewards, fail conditions, prerequisite ids.
- `MissionManager` autoload: start, update objective, complete, fail, restart from checkpoint, signals for the HUD.
- Categories: story, driving, delivery, racing, exploration, rescue, business.
- Mission markers in the world and on the map, objective text on the HUD, a fail screen with retry, and a completion banner with the reward.

## 9. Economy and property
- `EconomyManager`: cash balance, transactions with signals.
- Shops (clothes, food for health), vehicle dealer, garages (store owned cars), properties (save point, some with passive income per in-game day), businesses (owned income plus optional business missions).
- Inventory: owned vehicles, properties, and key items. All saveable.

## 10. UI
Style: dark translucent panels, neon accents (magenta and cyan), clean sans-serif typography (an open-licence font such as Inter or Rajdhani, recorded in CREDITS.md). Every screen is navigable by keyboard, mouse, and gamepad.
- **HUD:** health, stamina, cash, minimap, mission title and objective, wanted level, speedometer (in vehicles), interaction prompt.
- **Main menu:** New Game, Continue (disabled when there's no save), Settings, Controls, Credits, Exit.
- **Pause:** Resume, Map, Missions, Inventory, Settings, Save, Main Menu.
- **Settings:** resolution, window mode, VSync, quality preset, render scale, shadows, view distance, NPC and traffic density, the three volume sliders, mouse sensitivity, invert Y, key rebinding.

## 11. Map and navigation
- Minimap: a top-down orthographic SubViewport camera following the player (rotating with them), or a pre-rendered map texture with icons. Start with the SubViewport approach.
- Full map: pan, zoom, district names, mission, shop, and property icons, click to set a waypoint. The waypoint shows a GPS route on the road graph.

## 12. Day/night and weather
- `TimeOfDay` autoload: configurable day length (default 24 real minutes). It drives the sun angle and colour, the sky (ProceduralSkyMaterial or PhysicalSky), ambient light, and fog. Streetlights and building window emission turn on at dusk (use pooled lights; only the nearest N are real OmniLights, the rest are emissive-only).
- Weather states: clear, cloudy, fog, rain (GPU particles near the camera, wet-road roughness, rain audio). Transitions blend over time.

## 13. Audio
Bus layout: Master → Music, SFX, Ambience, UI. Engine sound pitched by RPM, footsteps by surface, collisions, rain, city ambience per district, mission stingers, UI clicks. All audio must be original, CC0, or royalty-free, and listed in `CREDITS.md`. Generated placeholders (simple synthesised tones) are fine until real audio exists.

## 14. Save/load
JSON in `user://saves/slot_N.json`, with a version field for migrations. Saves: player position and rotation, health, cash, completed missions, current mission and checkpoint, properties, vehicles, time of day, and stats. Settings are saved separately in `user://settings.cfg` (ConfigFile). Three manual slots plus one autosave.

## 15. Milestones (each ends in something playable plus a report, then waits for approval)

| # | Milestone | Done when |
|---|-----------|-----------|
| **M0** | Setup and pipeline check | Godot and Blender paths confirmed, git initialised, project structure created, a Blender script exports a test cube GLB that Godot imports, smoke test runs headless |
| **M1** | Playable prototype | Main menu → New Game loads a small city block (procedural roads, sidewalks, 8–12 Blender-made placeholder buildings, streetlights), and a placeholder player walks, runs, sprints, and jumps with a smooth collision-aware camera. Pause menu with Resume, Main Menu, and Quit works |
| **M2** | First car | The sedan drives with tuned handling. Enter/exit, vehicle camera, speedometer HUD, basic damage |
| **M3** | City district | One full district (Old Town or Downtown) on the chunk system, with road kit pieces, signals, lane graph, and navmesh. A performance baseline is logged (FPS, draw calls) |
| **M4** | Life in the city | Pedestrians, traffic following lanes and obeying signals, density settings |
| **M5** | Core loop | Mission system plus missions 1–2, cash and rewards, HUD objectives, save/load |
| **M6** | Open-world systems | Wanted levels and police AI, minimap and full map with waypoints, day/night, shops, first property, mission 3–5 |
| **M7** | Expansion | Remaining districts, remaining vehicles, weather, audio pass, story characters and dialogue, cutscenes (AnimationPlayer-driven camera rigs with letterboxing) |
| **M8** | Polish and ship | Real character model and animations, visual pass, optimisation to target, bug pass, Windows export via export presets |

## 16. Performance targets
- 60 FPS at 1080p on a mid-range gaming laptop (GTX 1650 / RTX 3050 class) at the "Medium" preset.
- Tools: chunk streaming, MultiMesh for repeated props, visibility ranges, occluders in dense districts, simple convex or box colliders (never trimesh on dynamic bodies), light pooling, shadow distance limits, physics only for nearby NPC vehicles (distant traffic is kinematic or path-following).
- Every graphics option in Settings must actually change something.

## 17. Project structure
```
res://
  scenes/   main/ player/ vehicles/ world/ world/chunks/ buildings/ npc/ missions/ ui/ interiors/
  scripts/  player/ vehicles/ world/ npc/ missions/ police/ economy/ systems/ ui/
  assets/   models/ textures/ materials/ animations/ audio/ fonts/
  resources/ vehicles/ missions/ characters/ shops/
  data/     (JSON dialogue, map data)
  shaders/
  tests/    smoke_test.tscn + per-feature test scenes
  tools/blender/   (asset generator scripts, not shipped)
docs/GAME_DESIGN.md
CLAUDE.md  README.md  DEVELOPMENT_LOG.md  TESTING.md  CREDITS.md
```
