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
