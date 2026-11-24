# Manual Testing Checklist

Automated coverage lives in `tests/smoke_test.tscn` (run it first; it must print `SMOKE TEST PASSED`) and, for vehicle handling figures, `tests/vehicle_test.tscn` (`VEHICLE TEST PASSED`). These checks cover what a headless run can't judge: how things look, sound and feel. Tick each box; note anything that fails in DEVELOPMENT_LOG.md.

---

## M0 — Project setup

- [ ] The project opens in the Godot 4.7.2 editor without errors in the Output panel. (The .NET editor build prints `.NET Sdk not found` once; that's expected and harmless.)
- [ ] `assets/models/test/prop_test_cube.glb` opens in the editor and shows an orange 1 m cube sitting on the ground plane (pivot at its base).

## M1 — Playable prototype

### Main menu
- [ ] F5 opens the main menu: "RISE OF THE / DON" title, tagline, animated neon skyline and a scrolling grid.
- [ ] A soft ambient music loop fades in within a second or two.
- [ ] Arrow keys / D-pad move between buttons; the focused button has a cyan edge and plays a short blip.
- [ ] **Continue** is greyed out and can't be selected.
- [ ] **Settings** opens on the right. Dragging *Master* or *Music* changes the music volume right away; dragging *Effects* plays a footstep at the new level.
- [ ] **Settings**: change mouse sensitivity and invert look, press Back, quit and restart the game: the values are remembered.
- [ ] **Controls** lists the bindings. **Credits** shows the credits and the Godot licence; arrow keys scroll it.
- [ ] Esc / B closes an open panel. **Exit** quits.
- [ ] Mouse-only and gamepad-only navigation both work through every screen.

### The city block
- [ ] **New Game** loads the block within a few seconds. You stand on a road, looking north, with shop-houses on the left and the temple wall on the right.
- [ ] Late-afternoon light: warm sun from the west-southwest, long shadows, hazy warm horizon.
- [ ] Look around: 3 × 3 road grid, crosswalks at every junction, yellow/black kerbs, streetlights, palms, 10 buildings (shop-houses, two apartment blocks, two office towers) plus the temple gopuram and shrine.
- [ ] The gopuram (east of the spawn) has a walk-through gateway into a walled courtyard with a raised platform and a small shrine.
- [ ] Nothing floats or sinks, and there are no flickering (z-fighting) surfaces on roads, kerbs or building fronts.
- [ ] Walking to the edge of the block, an invisible wall stops you.

### Player movement and camera (feel)
- [ ] W/A/S/D moves relative to where the camera looks. The capsule turns smoothly to face its direction (watch the magenta "nose").
- [ ] Run speed (default) feels right for a city. Ctrl+move walks, Shift+move sprints, and sprinting drains the cyan stamina bar.
- [ ] Sprint until stamina runs out: sprinting stops, the bar dims and you can't sprint again until it refills a little.
- [ ] Space jumps about 1 m. The jump feels responsive, not floaty; you can jump just after walking off a ledge.
- [ ] You can walk up onto sidewalks from the road without jumping, and up through the gopuram gateway.
- [ ] Temple platform: the west ramp (facing the gateway) can be walked up; the steep south ramp can't.
- [ ] Mouse look is smooth, vertical look stops before flipping over, and the speed matches the sensitivity setting.
- [ ] Back the camera into a wall or building: it pulls in instead of clipping through.
- [ ] The camera follows smoothly with no jitter while running or sprinting (try a high-refresh monitor if you have one).
- [ ] The field of view widens slightly while sprinting.
- [ ] Footsteps play while moving and get faster and louder with speed; landing a jump makes a thud.

### HUD and pause
- [ ] Top-left HUD shows health (pink) and stamina (cyan) bars.
- [ ] F3 toggles an FPS counter at the top right.
- [ ] Esc pauses: the world freezes, the mouse cursor appears, and the pause menu shows Resume, Settings, Main Menu and Quit to Desktop.
- [ ] Esc again (or Resume) continues; the mouse is captured again.
- [ ] Pause → Settings → change something → Back returns to the pause menu.
- [ ] Pause → Main Menu returns to the title screen (music fades back in); New Game works again from there.
- [ ] Pause → Quit to Desktop closes the game.

## M2 — First car

### Getting in and out
- [ ] The crimson sedan is parked against the left kerb a few metres ahead of where you start. It looks like an ordinary unbadged four-door saloon: wheels sit in the arches, nothing floats or pokes through.
- [ ] Walk up to it: a "F  GET IN" prompt appears at the bottom of the screen within about 3 m and disappears when you walk away. Walking into the car doesn't push it.
- [ ] F: the player steps to the nearer front door and vanishes inside; the camera glides from behind the player to behind the car (no cut, no clipping through the car). The engine starts.
- [ ] A one-off reminder of the driving keys shows along the bottom for a few seconds the first time you get in.
- [ ] F when stopped: you get out of the driver's door (the car's right side, as in India). The on-foot camera takes over facing the same way.
- [ ] F at speed: the car brakes hard by itself and you hop out once it's nearly stopped.
- [ ] Park with the driver's side against a wall (or the boundary): F gets you out of the passenger side.

### Handling (feel)
- [ ] W pulls away briskly (about 8 s to 100 km/h); the engine note rises and drops through the gear changes.
- [ ] S brakes firmly (the tail lights brighten); holding S once stopped reverses (white reverse lights, gear "R").
- [ ] Steering feels responsive at low speed (tight U-turn in one go on the 12 m road) but calmer at high speed, with no twitchiness.
- [ ] Taking a corner too fast makes the car run wide (understeer) rather than spin.
- [ ] Space (handbrake) at speed with some steering swings the tail round; tyres squeal while sliding.
- [ ] The car stays planted over kerbs and through junctions; driving onto a sidewalk bumps up over the kerb.
- [ ] Letting go of everything, the car rolls to a stop gently (engine braking).
- [ ] Gamepad: RT / LT are progressive, the left stick steers smoothly.

### Cameras
- [ ] Chase camera: follows smoothly with no jitter, drops back a little and widens the view as you speed up, softens suspension bounce.
- [ ] Look around with the mouse / right stick; about a second after you stop, it swings back behind the car (only while moving).
- [ ] The chase camera pulls in instead of clipping through buildings or walls.
- [ ] V switches to the hood camera (bonnet in view, looking ahead) and back. Mouse look works in the hood view and drifts back to straight ahead.

### HUD, sounds, lights, damage
- [ ] Bottom-right speedometer: speed in km/h matches how fast it feels, the arc fills and turns magenta near top speed, gear letter and rev arc move sensibly, the orange CAR bar shows the car's health.
- [ ] H holds the horn (two-tone); L switches the headlights on (lenses glow, beams light the road) and off.
- [ ] Crashing into a building at 30+ km/h makes a crunch and drops the CAR bar; gentle bumps don't.
- [ ] Below about a third health, grey smoke rises from the engine; below 15 % it turns dark; at zero the smoke goes black and the engine won't run (you can still get out).
- [ ] If the car ever ends up on its side or roof while you are in it, it rights itself after about 2.5 s. (Hard to do on purpose in this flat block; the vehicle test checks it.)
- [ ] Pausing while driving freezes the car and its sounds; resuming carries on.
