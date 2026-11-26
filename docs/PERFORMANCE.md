# Performance

Target (GDD §16): 60 FPS at 1080p on a mid-range gaming laptop (GTX 1650 / RTX 3050 class) at the "Medium" preset.

## How to measure

```bash
"$GODOT_CONSOLE" --path . res://tests/perf_baseline.tscn
```

This runs the real game scene in a 1920×1080 window with VSync off. It needs a real GPU, so it can't run headless, and it takes about 3 minutes. For each viewpoint it streams in the chunks around the camera, waits 90 frames, then averages 240 frames; traffic and pedestrians are off for these, so the figures stay comparable with M3. Then it drives along a main road across the whole district at 72 km/h while chunks stream in and out, to catch loading hitches. Last, it measures the spawn street with city life at each density (M4) once the ring around the player has filled. The results print as Markdown; paste them below with the date.

## Baseline: M3, Old Town (2026-11-25)

**Machine:** Intel UHD Graphics 730 (integrated GPU), 12th Gen Core i5-12400 (12 threads). Godot 4.7.2, Forward+ (Vulkan), 1920×1080 window, VSync off.

This GPU is well below the target class: a GTX 1650 has roughly five times its graphics throughput. The figures below are a baseline for comparing future builds on this machine, not a verdict on the target.

| Viewpoint | FPS | avg ms | 1% worst ms | draw calls | objects | primitives | chunks | VRAM MB |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Spawn street, looking at the east gopuram | 37 | 26.87 | 29.23 | 506 | 1074 | 528980 | 14 | 209 |
| Signalized junction (Ring B x north road) | 38 | 26.00 | 27.83 | 451 | 895 | 410010 | 12 | 209 |
| Narrow lane (x = 80), houses both sides | 38 | 25.99 | 28.05 | 385 | 809 | 423974 | 14 | 209 |
| Market square | 41 | 24.23 | 26.90 | 369 | 711 | 323446 | 15 | 209 |
| Temple courtyard | 41 | 24.57 | 26.41 | 481 | 982 | 564912 | 16 | 209 |
| Rooftop height over the tank | 40 | 25.23 | 27.45 | 450 | 916 | 473916 | 15 | 209 |
| Aerial, whole district (worst case) | 36 | 28.00 | 29.74 | 247 | 682 | 265318 | 9 | 208 |
| Spawn street (occlusion culling off) | 38 | 26.47 | 28.82 | 432 | 791 | 442870 | 12 | 209 |
| Sky only (fixed per-pixel cost) | 67 | 14.95 | 17.09 | 8 | 8 | 37744 | 12 | 209 |
| Spawn street, SSAO off | 46 | 21.72 | 23.70 | 432 | 791 | 442870 | 12 | 209 |
| Spawn street, SSAO and glow off | 62 | 16.03 | 18.86 | 432 | 791 | 442870 | 12 | 209 |
| Spawn street, 75% 3D resolution | 52 | 19.38 | 21.88 | 432 | 791 | 442870 | 12 | 168 |

**Streaming drive** along Ring B (480 m at 72 km/h): 39 FPS average, 1% worst frame 28.6 ms, worst frame 29.6 ms. 4 chunks loaded and 4 unloaded on the way, with no visible hitch.

### What it shows

- **The scene isn't draw-call bound.** Between 250 and 500 draw calls, the frame time barely changes. Most of it is per-pixel work at 1080p:
  - About 15 ms is the fixed cost of the screen (fog, glow, tone mapping, sky), even with only the sky in view.
  - SSAO costs about 5 ms.
  - Glow costs about 6 ms.
  - The streets themselves add about 11 ms.
- **Draw calls are low thanks to the M3 work.** Every building is one draw call (baked palette material). Ground tiles and props are batched per chunk, so the district is about 14 MultiMesh batches per chunk instead of thousands of objects. For comparison, M1's small test block used about 890 draw calls at its spawn view.
- **Streaming is smooth.** A chunk is about 30 KB on disk and loads on a background thread. Adding a chunk is cheap enough that no frame in the drive went above 30 ms.
- **Occlusion culling** (box occluders inside upper floors) made no measurable difference to frame time here: 37 FPS on, 38 off, because per-pixel cost dominates. The on and off rows aren't a clean comparison of object counts either: the off run happened to have 12 chunks loaded instead of 14. It's left on; it should help more on a discrete GPU and in denser districts.

### Levers for later (graphics settings, M8 optimisation)

- **Medium/Low presets:** SSAO and glow off, which gives 60+ FPS on this integrated GPU, and a 3D render scale.
- **Mesh LODs** for the baked kit meshes. The temple courtyard view draws 0.56 M primitives, which matters more on a discrete GPU.
- **Shadow distance and split counts** in the lighting preset.

## M4: city life (2026-11-25)

Same machine and settings. The M3 viewpoints, re-measured with traffic and pedestrians off, are within 1 FPS of the table above (spawn street 37 FPS, market square 41, aerial 36; streaming drive 38 FPS average, worst frame 29.8 ms).

City life at the spawn street, with the traffic and pedestrian densities set together and measured once the ring around the player had filled:

| Density | cars | people | FPS | avg ms | 1% worst ms | physics ms | process ms | draw calls |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| None | 0 | 0 | 38 | 26.53 | 28.59 | 1.83 | 26.71 | 401 |
| Low | 7 | 12 | 38 | 26.50 | 31.31 | 5.50 | 24.87 | 409 |
| Medium | 14 | 26 | 38 | 26.64 | 35.26 | 7.21 | 23.36 | 408 |
| High | 22 | 42 | 37 | 26.72 | 33.61 | 8.57 | 22.11 | 450 |

"physics ms" is the CPU time spent on physics per rendered frame, including every NPC script. At 38 FPS, each rendered frame runs about 1.6 physics steps (60 per second).

### What it shows

- **City life costs no GPU time here.** The frame rate is set by per-pixel work (see M3), and the extra cars and people add only 10–50 draw calls. Each pedestrian is one draw call (body, limbs and clothes baked into one mesh, animated in the vertex shader). Each car is six draw calls (body, lenses and four wheels).
- **The CPU cost is moderate.** A headless run, measured per physics step, separated it out:
  - no NPCs: 1.9 ms;
  - 14 cars: 3.4 ms;
  - 26 people: 3.9 ms;
  - both: 4.5 ms.
- **Within that, the scripts are small.** All AI drivers together take 0.40 ms per step and all pedestrian scripts 0.97 ms. The rest is Jolt (14 full vehicle bodies, 26 character bodies) and navigation avoidance.
- **The slightly worse 1% frames** (31–35 ms against 29 ms) come from occasional spikes: cars or people spawning and despawning, and a crowd re-pathing when everyone runs from a crash.

### Levers for later

- **Cheaper distant traffic:** GDD §16's kinematic cars beyond about 60 m, with full physics only up close. This only matters once traffic counts rise well above 22.
- **Spreading the work:** stagger pedestrian path requests and spawns across frames to flatten the spikes.
- **LODs:** a lower-detail pedestrian mesh and car body for distant NPCs, when draw calls start to matter on a discrete GPU.

## M6: open-world systems (2026-11-25)

Same machine (Intel UHD Graphics 730, i5-12400) and settings.

**A fixed clock.** The baseline now holds the clock at 13:00, so every row is measured in the same light, and measures night as a row of its own. Before this change the run's three minutes moved the clock from 16:30 into the evening. As a result, the city-life rows were measured after dark and looked about 13 ms slower than M4. The baseline also now pauses the day/night cycle while it switches SSAO and glow off; otherwise the cycle's presets switched them back on within half a second.

| Viewpoint | FPS | avg ms | 1% worst ms | draw calls |
|---|---:|---:|---:|---:|
| Spawn street, 13:00 | 35 | 28.53 | 38.27 | 295 |
| Spawn street, night 21:30 (lamps, lit windows, 4 street lights) | 27 | 36.37 | 41.08 | 272 |
| Market square | 35 | 28.73 | 34.37 | 252 |
| Aerial, whole district (worst case) | 32 | 31.25 | 35.68 | 238 |
| Sky only | 62 | 16.09 | 21.36 | 7 |
| Spawn street, SSAO off | 44 | 22.59 | 26.47 | 292 |
| Spawn street, SSAO and glow off | 61 | 16.53 | 21.46 | 292 |

- **Streaming drive along Ring B:** 35 FPS average, worst frame 39.9 ms.
- **City life at the spawn street:** 33–35 FPS at every density, 28.7–30.4 ms (M4: 26.5–26.7 ms).

### What it shows

- **Daytime is 1.5–2 ms a frame slower than in M4.** About 1.7 ms of that is the day/night cycle re-applying its blended preset every half second (the sky's light is recomputed incrementally after each change). About 1.2 ms is the HUD (minimap, mission HUD, stars). Shops, police and missions cost nothing measurable when idle, and neither does the player's character model.
- **Night costs more, and almost all of it is the real street lights.** Lit windows and lamp lenses (the `city_lights` shader global) cost nothing measurable.
  - On this integrated GPU a single OmniLight3D costs 2.5–4 ms, depending mostly on its reach, and the cost isn't linear in the number of lights. With M6's first setting (10 lights, 24 m reach) night ran at 26 FPS against 37 FPS without the lights.
  - The pool is now 4 lights with a 16 m reach (`resources/world/day_night.tres`), and night costs about 8 ms over day.
- **Sun shadows cost 4–5 ms** by day or night; SSAO about 6 ms; glow about 6 ms.

### Levers for later (M8 graphics settings)

- **The number and reach of real street lights** belong in the graphics quality preset (0 on Low; more on a discrete GPU, where they are far cheaper).
- **Day/night updates:** update the cycle less often (or only the sky every few seconds) on Low.
- **The usual levers** from M3: SSAO, glow, shadow distance and 3D resolution.

## M7 step 1: the city and Downtown (2026-11-25)

Same machine (Intel UHD Graphics 730, i5-12400) and settings. The city now has two districts (Old Town and Downtown, 32 chunks); the always-loaded landmark scene also carries the skyline stand-ins (65 tall buildings in one mesh) and the ground and walls at the city's edge.

| Viewpoint | FPS | avg ms | 1% worst ms | draw calls | primitives |
|---|---:|---:|---:|---:|---:|
| Spawn street, 13:00 | 36 | 28.03 | 31.73 | 298 | 390,556 |
| Spawn street, night 21:30 | 29 | 34.83 | 38.75 | 276 | 356,330 |
| Aerial over Old Town (worst case) | 30 | 33.48 | 37.70 | 242 | 286,582 |
| Downtown: north road between the towers | 33 | 30.56 | 34.71 | 255 | 267,362 |
| Downtown: Central Plaza | 37 | 26.92 | 30.87 | 159 | 207,828 |
| Old Town north edge, Downtown skyline ahead | 34 | 29.18 | 32.83 | 339 | 328,756 |
| Aerial over Downtown (worst case) | 35 | 28.62 | 31.90 | 177 | 171,902 |
| Sky only | 64 | 15.70 | 20.58 | 7 | 10,048 |
| Spawn street, SSAO and glow off | 62 | 16.18 | 17.63 | 296 | 388,284 |

- **Streaming drive along Ring B:** 37 FPS average, worst frame 33.1 ms.
- **City life at the spawn street:** 36 FPS at every density (27.8–28.2 ms).
- **Video memory:** 259 MB (the city map is block-compressed: about 4 MB for the two districts).

### What it shows

- **Downtown costs no more than Old Town.** Each tower is one draw call, like any Old Town building, and the big blocks mean fewer buildings and props per chunk than Old Town's tight lanes.
- **The skyline stand-ins and the ground under the city cost nothing measurable.** Old Town's rows are the same as or slightly faster than in M6.
- **The fixed cost dominates, as before:** the sky-only row is 15.7 ms. SSAO and glow together are about 12 ms at the spawn street.

## M7 step 2: the Beach District (2026-11-25)

Same machine and settings; three districts (48 chunks), with the sea and the lighthouse beam always loaded.

| Viewpoint | FPS | avg ms | 1% worst ms | draw calls | primitives |
|---|---:|---:|---:|---:|---:|
| Spawn street, 13:00 | 35 | 28.25 | 33.01 | 297 | 390,556 |
| Spawn street, night 21:30 | 28 | 35.39 | 40.39 | 276 | 356,330 |
| Downtown: north road | 33 | 30.74 | 34.63 | 256 | 267,370 |
| Beach District: promenade, looking along the sand | 44 | 22.63 | 27.98 | 112 | 120,788 |
| Beach District: Coast Road | 37 | 27.17 | 32.19 | 246 | 282,390 |

- **Streaming drive along Ring B:** 36 FPS average, worst frame 42.6 ms. Ten chunks loaded on the way: at Ring B's east end the Beach District's first chunks now come in.
- **City life at the spawn street:** 35–37 FPS at every density.
- **Video memory:** 272 MB (+13 MB for the Beach kit and the sea).
- The sea is one flat mesh with a cheap shader; the open view along the beach is one of the lightest in the city.

## M7 step 3: the Industrial Zone (2026-11-25)

Same machine and settings; four districts (64 chunks).

| Viewpoint | FPS | avg ms | 1% worst ms | draw calls | primitives |
|---|---:|---:|---:|---:|---:|
| Spawn street, 13:00 | 36 | 28.09 | 32.22 | 297 | 391,312 |
| Spawn street, night 21:30 | 29 | 34.93 | 39.06 | 276 | 357,086 |
| Industrial Zone: the quay, container yard and cranes | 36 | 28.10 | 32.00 | 38 | 274,117 |
| Industrial Zone: warehouse street | 40 | 24.73 | 28.77 | 168 | 206,680 |

- **The container yard** (about 250 containers in stacks) is drawn as three instanced batches: the whole quay view is 38 draw calls.
- **City life at the spawn street:** 33–36 FPS. Physics time read higher than the last run (9.7–14.1 ms against 5.2–8.7 ms) with the same number of cars and people and no change to their code; the frame rate barely moved. To watch in the next runs.

## M7 steps 4-5: the Luxury District and the Countryside, the whole city (2026-11-25)

Same machine and settings. The whole city: seven 512 m cells, six districts, 112 chunks.

| Viewpoint | FPS | avg ms | 1% worst ms | draw calls | primitives |
|---|---:|---:|---:|---:|---:|
| Spawn street, 13:00 | 35 | 28.81 | 35.61 | 302 | 391,324 |
| Spawn street, night 21:30 | 28 | 35.10 | 38.97 | 281 | 357,098 |
| Downtown: north road | 33 | 30.59 | 33.99 | 256 | 268,130 |
| Beach District: Coast Road | 37 | 26.83 | 31.86 | 250 | 282,404 |
| Industrial Zone: the quay | 35 | 28.29 | 32.83 | 38 | 274,117 |
| Luxury District: villa avenue | 41 | 24.65 | 28.24 | 158 | 182,588 |
| Countryside: paddy fields from the road | 41 | 24.47 | 28.04 | 125 | 226,598 |
| Countryside: the village | 38 | 26.55 | 29.83 | 95 | 101,638 |

- **Every district runs at 33-44 FPS** on this integrated GPU; the open districts (Luxury, Countryside, the beach) are the lightest.
- **Streaming drive along Ring B:** 36 FPS average, worst frame 35.3 ms; it now streams the Countryside's chunks in at the west end.
- **City life:** 35-36 FPS at every density (physics 7-12 ms, as in step 3).
- **Video memory rose to 330 MB** (272 MB in step 3). 19 MB of that is the city map, now 6144 px square (block-compressed). The rest is not yet accounted for; to look into in M8's optimisation pass.

## M7 steps 6-8: vehicles and weather (2026-11-25)

| Viewpoint | FPS | avg ms |
|---|---:|---:|
| Spawn street, 13:00, clear | 35 | 28.50 |
| Spawn street, 13:00, rain (5,000 streaks, full cloud, wet surfaces) | 36 | - |
| Spawn street, night 21:30 | 29 | 34.90 |
| Sky only | 62 | - |

- **Rain costs nothing measurable** on this machine: the particles are small and unlit, and wet surfaces are two extra lines in the palette shader.
- **Clouds:** the first version drew the cloud texture in every weather and rewrote its tint every half second, which made the sky recompute its light each time. The sky-only row fell from 63 to 54 FPS (+2.6 ms on every frame). Clear weather now has no cloud texture at all, and the tint is only written when it changes; the sky-only row is back to 62 FPS.
- The new parked vehicles near the spawn add about 10 draw calls.

## End of M7: fists, cutscenes, the story (2026-11-26)

Same machine and method (`tests/perf_baseline.tscn`). Nothing in steps 10-12 shows up in the free-roam numbers:

| Viewpoint | FPS | avg ms | 1% worst ms | draw calls |
|---|---:|---:|---:|---:|
| Spawn street, day | 35 | 28.61 | 33.44 | 313 |
| Spawn street, night 21:30 | 28 | 35.62 | 40.69 | 287 |
| Downtown: Central Plaza | 36 | 27.46 | 31.70 | 183 |
| Industrial Zone: the quay, container yard and cranes | 35 | 28.47 | 32.41 | 38 |

Video memory is 333 MB (unchanged).

- **Streaming one chunk at a time:** to avoid an engine race in the headless test renderer (see DEVELOPMENT_LOG, step 12b), background chunk loads now run one after another instead of all at once. The streaming drive along Ring B at 72 km/h still loaded all 10 chunks it needed in time: 35 FPS average, 1% worst frame 32.9 ms, worst frame 33.8 ms (step 9: 35 FPS, 1% worst 33 ms). Watch for pop-in at higher speeds, for example on the motorcycle at full speed between districts.
- **Cutscene fill light:** one omni light without shadows, switched on only while a cutscene plays.
- **City life** (physics including all NPC scripts): 7.4 ms per step at High, as at step 9.
