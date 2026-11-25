# Manual Testing Checklist

Automated coverage lives in `tests/smoke_test.tscn` (run it first; it must print `SMOKE TEST PASSED`), `tests/player_test.tscn` (kerb, ramps and gateway on the M1 test block) and `tests/vehicle_test.tscn` (vehicle handling figures). Performance is measured by `tests/perf_baseline.tscn` (see `docs/PERFORMANCE.md`). These checks cover what a headless run can't judge: how things look, sound and feel. Tick each box; note anything that fails in DEVELOPMENT_LOG.md.

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

## M3 — Old Town district

Since M3, **New Game starts in Old Town**. The M1 test block is still in the project (`scenes/world/test_block.tscn`) and is used by `tests/player_test.tscn`. The M1 checks that mention it (spawn view, ramps, the small gopuram courtyard) now apply to that test level, not to New Game.

### Arrival and looks
- [ ] New Game: an "OLD TOWN / VELANAGAR" title fades in at the top. You stand on a road leading west to the temple's east gopuram, with a sedan parked against the left kerb ahead.
- [ ] The temple: four gopurams, red-and-white striped walls, a tall central shrine and a pillared hall inside, palms and neem trees. There are flower stalls and bollards by each gate. You can walk through a gopuram into the courtyard.
- [ ] **Main roads:** four lanes, a double yellow centre line, dashed lane lines, black-and-yellow kerbs and sidewalks with streetlights.
- [ ] **Lanes:** narrow, with a dashed centre line and footpaths.
- [ ] **Junctions:** zebra crossings where traffic lights are.
- [ ] **Buildings:** pastel shops with awnings and blank sign boards on main roads, houses with clay-tile roofs and pillared verandahs in the lanes, a few lodges with rooftop sign frames and some apartment blocks.
- [ ] Does the mix feel like a dense, lively old town? Nothing should float, sink, overlap badly or flicker.
- [ ] Market square (north-west of the temple): a market hall, rows of stalls with red and blue canopies, flower stalls and handcarts.
- [ ] Temple tank (south-east of the temple): stone steps going down to green water, a pavilion in the middle and a railing around it.
- [ ] Two small parks full of trees. Some block courtyards have a neem tree.
- [ ] The gopurams stay on the skyline from anywhere in the district.
- [ ] Distant streets fade into a warm haze. Walking or driving at street level, you shouldn't see buildings pop in or out nearby.

### Streaming and performance
- [ ] F3 now shows draw calls and the number of loaded chunks under the FPS. Drive from one corner of the district to the other: the chunk count changes, and the drive shouldn't stutter.
- [ ] With F3, note the FPS at the spawn and in the market square on your machine. On this machine's integrated GPU it was about 37-41 FPS at 1920×1080 (`docs/PERFORMANCE.md`). Is it smooth enough for you?
- [ ] Drive the start sedan to a far corner and back past the other two parked sedans (Ring B west, and the road north of the temple). They are still parked where they were: a car whose ground is not loaded is frozen, so none falls through the world.

### Traffic lights, lanes and navmesh
- [ ] Traffic lights where two main roads cross cycle green, amber, red, one direction at a time (14 s green, 3 s amber, 2 s all red).
- [ ] Press F4 for the debug view, then F4 again to hide it. Check that:
  - cyan lanes run on the **left** side of every road (left-hand traffic), with white turn paths curving through junctions;
  - stop lines show the live light colour (green, amber or red, and yellow means give way);
  - the green navmesh outline covers sidewalks, plazas and crossings, but not roads.

### Driving in Old Town
- [ ] The ring roads are fun to drive, and the lanes are tight but drivable.
- [ ] Kerbs bump the car up onto sidewalks, and buildings and walls stop it (and damage it).
- [ ] Invisible walls stop you at the edge of the district.

## M4 — Life in the city

Headless tests already cover the logic (`tests/traffic_test.tscn`, `tests/pedestrian_test.tscn` and the smoke test). These checks are about how it looks and feels. Play at the default **Medium** density unless a step says otherwise.

### Traffic
- [ ] Within a few seconds of New Game, cars are driving on the roads around you. Their colours vary (white, silver, black, red, blue, green, yellow, grey), and they keep **left**.
- [ ] Cars never pop into existence or vanish where you are looking at close range. They appear in the distance or out of sight.
- [ ] At traffic lights, cars stop before the line on red. They leave a car's gap to the car in front, brake lights glow, and they pull away on green. Nobody runs a red.
- [ ] Where a lane meets a main road, cars stop briefly at the line, then pull out when the junction is clear.
- [ ] Following: cars slow down behind slower cars and leave a gap. Stand in a lane in front of a car: it stops short of you and honks after about 5 s.
- [ ] Park your car in the outer lane of a main road (four lanes) and watch: cars change into the other lane, drive past and carry on. In a narrow lane they stop behind it and honk instead.
- [ ] Ram a traffic car: it stops for a few seconds, then drives on. Traffic cars can be wrecked and pushed like your own car.
- [ ] Steering looks smooth: no weaving in straight lanes, sensible lines through turns, no cutting across kerbs.
- [ ] Turn F3 on: the third line shows the number of cars and people about. Set Traffic density to Low, then High, in pause → Settings: the car count settles at 7 / 22 within a few seconds (Medium is 14).

### Pedestrians
- [ ] People walk the sidewalks in varied looks: men in shirts and trousers, women in long skirts with a braid, older men in white veshtis. Their legs and arms swing as they walk.
- [ ] They cross roads at zebra crossings and at the corners of lanes, not in the middle of a road.
- [ ] Some stop, and pairs stand facing each other chatting with small hand movements. Some sit on benches: in the temple courtyard, the parks, the market and the tank yard. Does the sitting pose (upright, legs forward to the ground) read well?
- [ ] Nobody floats, sinks into the ground, walks inside a building or stands on a bench.
- [ ] Walk into someone: they step out of your way.
- [ ] Honk at people in front of your car: they hurry aside.
- [ ] Crash your car hard near people: everyone nearby runs.
- [ ] Hit someone with the car at speed: they fall flat. The car isn't stopped dead by the impact. Nearby people run, and the person gets up after about 3 s and runs away from the car.
- [ ] Set Pedestrian density to Low / Medium / High: about 12 / 26 / 42 people (F3).

### Performance
- [ ] With F3 at Medium density, the FPS at the spawn street should be about the same as without people and cars. This machine measured 37–38 FPS at every density (GPU-bound; `docs/PERFORMANCE.md`). Is it still smooth on yours, including at High?

## M5 — Core loop

`tests/mission_test.tscn` and `tests/save_test.tscn` cover the logic. These checks are about how missions feel and read. Start with **New Game**.

### Mission 1: Welcome to Velanagar
- [ ] You start on the sidewalk beside the bus stand, looking down the road at the east gopuram. Behind you is the shelter: blue panels, a bench and a round blue bus stop sign.
- [ ] "OLD TOWN" fades in first, then the "WELCOME TO VELANAGAR" banner. The conductor's line and the inner-monologue line show as subtitles at the bottom, with a cyan hint just above them naming your movement keys.
- [ ] Top left: mission title and objective. Top right: ₹200.
- [ ] A cyan light beam stands at the temple gate, and a diamond with the distance floats over it. Turn away: an arrow at the screen edge keeps pointing to it.
- [ ] Walking to the gate, into the courtyard and to the temple tank updates the objective each time with a short chime. Each step's hint names the right key (Shift to run, Space to jump).
- [ ] At the tank: "MISSION PASSED +₹300", a rising jingle, and the cash counts up to ₹500 with "+₹300" under it. The fixer calls out to you.

### Mission 2: First Opportunity
- [ ] A magenta beam stands by the fixer (dark shirt) at the tank. Walking into it starts "FIRST OPPORTUNITY".
- [ ] The fixer turns to face you as you come close. "E  TALK TO FIXER" shows when you're next to him. During his lines he gestures, and E skips a line.
- [ ] Afterwards you carry a brown parcel in front of you. Follow the arrow to the tailor (white veshti) on the main road east of the big junction: "E  GIVE TAILOR THE PARCEL".
- [ ] The tailor's teal car is parked at the kerb with a diamond over it. Get in: a 2:00 clock starts top left, and it turns red under 15 s.
- [ ] Drive round to the flower market by the temple, stop in the cyan ring ("Stop in the marker" if you're too fast), get out and give the buyer the parcel: "MISSION PASSED +₹1,000", ₹1,500.
- [ ] Wreck the tailor's car (or let the clock run out): after a moment the game pauses on "MISSION FAILED" with the reason. **Retry** after you've got in puts you back beside a fresh car with the parcel. **Retry** before that, or after **Quit Mission**, starts again at the fixer.
- [ ] Does the route feel fair for two minutes with traffic about? Is any dialogue line too long to read before it moves on?

### Saving and loading
- [ ] Pause → Save Game: the autosave row is greyed out. Pick Slot 1: "Saved to slot 1.", and the row shows the mission, cash, play time and date. Pick it again: it asks before overwriting.
- [ ] Main Menu: Continue and Load Game are now enabled. Continue loads the newest save. Load Game lists all four slots and loads the one you pick.
- [ ] Saving during mission 2 after the tailor has given you his car, then loading: you're back beside the car with the parcel and the clock not yet started. Saving before that puts you back at the fixer.
- [ ] Health, cash, position and missions passed come back as saved. The autosave after each mission shows "Free roam, N missions passed".
- [ ] Save files are in `%APPDATA%\Godot\app_userdata\Rise of the Don\saves\`.

## M6 — Open-world systems

### Day and night
- [ ] The clock under the cash runs: about one in-game hour per real minute. Pause → Save, quit and load: the time of day comes back.
- [ ] Sunset to night (around 18:00–19:00): the sky goes orange, then dark blue. Lamps glow, windows light up floor by floor (not all at once, not every one), and street lights pool on the road near you.
- [ ] At night you can still see where you're going on foot and in the car (L for headlights). Traffic drives with headlights on.
- [ ] Dawn (around 06:00–07:00): the lights go off again. Nothing flickers or pops as the light changes.
- [ ] Press F3 by day and after dark: on this PC expect about 35 FPS by day and about 27 at night (4 street lights). Is night smooth enough to drive? Do the street-light pools look right, or too sparse?

### Map and GPS
- [ ] The minimap (bottom left) turns with you; "N" stays on north. Driving fast zooms it out.
- [ ] **M** opens the full map centred on the district, with place names (temple, tank, flower market, parks, bus stand, police). Drag or W A S D moves it; the wheel or = / − zoom.
- [ ] Click a road: a waypoint appears and a route is drawn on the map and the minimap, following the traffic direction. Click it again (or right-click) to clear it. **M** or Esc closes the map.
- [ ] Driving along the route, it updates as you go and clears when you arrive.

### Wanted level and police
To get wanted: drive into a pedestrian. For higher levels, keep at it, or ram a police car a few times.
- [ ] One star appears under the clock (stars fill from the right). Officers on foot (khaki) come running.
- [ ] At two stars, white police cars with flashing red and blue bars arrive with sirens. They drive along the roads towards you (against the traffic if need be), and stop short of you on foot to let officers out.
- [ ] Stand still: an officer reaches you and the screen shows BUSTED. You're fined (10% of your cash, at least ₹100), and you stand outside the police station on Ring B (white with blue trim and a blue "POLICE" board on the roof). The police have gone.
- [ ] During a mission, getting busted fails it with "You were busted.", with Retry / Quit Mission.
- [ ] **Escaping:** get out of sight (round corners, through lanes). The stars blink and a red circle shows on the minimap, shrinking. Leave the circle and stay out: a star goes every ~8 s until none are left. The police drive off.
- [ ] **Three or more stars, driving fast:** a roadblock appears ahead, with police cars parked across all lanes. At four stars a yellow-and-black spike strip lies before it. Driving over it bursts your tyres: the car slides and won't go much over 45 km/h.
- [ ] **Five stars:** a helicopter flies in and circles overhead (rotor thudding), with its searchlight on you. At night a faint beam shows. It's hard to get out of its sight.
- [ ] Is the chase fair and fun? Can you escape two or three stars in a car? Do police cars cope with corners and narrow lanes, or get stuck? Does the siren get tiring?
- [ ] Street lamps and palm trees are solid: you can't walk or drive through them.

### The player, shops, the house and side jobs
- [ ] You are a low-poly man (Vetri) in a blue shirt and khaki trousers, not a capsule. Walking, his legs and arms swing in step; running and sprinting, the stride lengthens and the swing widens; in a jump the legs stay apart. Does it look right, or do the feet slide?
- [ ] **Tiffin stall** (green "TIFFIN" board across the road from the bus stand): after the conductor's lines, step into the green ring: "E  BUY FOOD". The menu shows coffee, idli and vada, and full meals with prices; your cash is top right. Hurt yourself (a fall or a crash), then eat: health goes up and cash goes down. When full: "You're not hungry."
- [ ] **Velanagar Textiles** (pink building, "TEXTILES" board, Ring B west of the police station; it serves you once you have met Kamalam in The New Connection): six outfits. Buy one: you're wearing it at once (look at Vetri when you leave). Switch back to the travelling clothes and again: free. One you can't afford says so.
- [ ] **Garage** (red "GARAGE" board, far east on the east road): drive in under the board and stop: "E  RESPRAY". With 1–3 stars and no police in sight: the screen fades, and the car comes out a new colour, smoke gone, tyres fixed, stars gone, ₹500 less. With 4+ stars, or police watching, it refuses and charges nothing. Is the bay easy to drive into?
- [ ] **House for sale** (verandah house north of Ring B, east; the yellow FOR SALE board appears after City Chase): "E  BUY VERANDAH HOUSE  ₹6,000". Without the cash it says so. Once bought: the board goes, the map badge turns to H, and E at the door opens the save slots (Esc goes straight back to the game). Rent arrives every in-game day at midnight ("Rent from the verandah house: +₹400").
- [ ] Map: green F, C and G badges for the shops, an orange ₹ for the house (H once bought).
- [ ] **Side jobs** (after The New Connection): a magenta beam by Selvi at the tiffin stall and by Murugan at the garage. **Tiffin Delivery:** she hands you a carrier; run (or drive) to the marked door within 100 s for ₹250. **Garage Run:** take the yellow car to its owner within 120 s for ₹600. Both come back on offer, usually with another address.
- [ ] Save, quit and load: your outfit, the house and the outfits you've bought come back.

### Missions 3 to 5
`tests/story_test.tscn` plays these through. These checks are about how they play.
- [ ] **Names:** in First Opportunity the fixer is now **Durai**, the tailor **Rafiq** and the buyer **Meena**. The prompts and subtitles use the names.
- [ ] **The New Connection** (magenta beam by Durai at the tank after First Opportunity): he sends you to Kamalam at the market hall (maroon top, gold skirt).
  - Press E next to her: the camera cuts to a side view of you both, black bars slide in, and you can't walk off.
  - Read the conversation (Kamalam and Vetri speak; E moves on a line). At the end the camera and control come back. "MISSION PASSED +₹1,500", then "Velanagar Textiles is open to you now."
  - Is the camera framing good? Does any line go by too fast?
- [ ] **City Chase** (magenta beam by Kamalam afterwards): she briefs you.
  - Get into the black car by the flower market: two stars at once, police on their way, and a 2:30 clock. The objective reads "Drive through the checkpoints (1/5)" with a cyan marker and GPS route.
  - Drive through all five (round Ring B, past the police station); the count goes up with a chime.
  - Then "Lose the police." Escape them, or respray in the garage. Then "Leave the car in Murugan's garage": stop in the bay. "MISSION PASSED +₹2,000", Murugan's line, and the house goes on sale.
  - Try failing: wreck the car, or get busted. "Retry" puts you back by the car with no stars.
  - Is 150 s fair with the police on you? Do roadblocks appear if it reaches three stars?
- [ ] **Building an Empire** (magenta beam by Durai at the verandah house):
  - Walking in with less than ₹6,000 says it needs ₹6,000 and doesn't start. Do side jobs until you have it, then walk in again.
  - Durai talks, then "Buy the verandah house." Buy it at the door: "MISSION PASSED +₹1,000". The house is now your save point and pays rent.

## M7 — Expansion (in progress)

### Downtown and the city (step 1)
- [ ] **Old Town is unchanged:** the bus stand, shops, police station, garage and the house are where they were, and missions 1–5 play the same.
- [ ] **Getting there:** from the temple's north gopuram, drive or walk north. At the edge of Old Town the road carries straight on and "DOWNTOWN · VELANAGAR" fades in at the top of the screen. Coming back shows "OLD TOWN".
- [ ] **Looks by day:** glass towers (one stepped tower with a gold spire, about 120 m), white residential towers with balconies, terracotta offices, shops with CAFE and SALON signs, the cream HOTEL with its rooftop sign. Central Plaza (fountain, palms, benches) sits west of the north road; Vela Mall, with its glass atrium, to the east. Does it read as a business district? Is anything floating, sunk into the ground, or blocking a sidewalk?
- [ ] **Looks at night:** office floors light up (some floors dark), the hotel and residential windows glow warm, shop signs and lobbies glow. Is it too bright or too dark? Do the neon signs keep their colour?
- [ ] **The skyline:** from Old Town (from the temple area, or anywhere with a view north) Downtown's towers stand on the horizon, also at night with some lit floors. As you drive north, the simple far-off shapes should turn into the detailed towers without an obvious pop. Is the swap noticeable?
- [ ] **Traffic and people** come and go in Downtown as in Old Town: cars stop at the many traffic lights, people walk the wide sidewalks.
- [ ] **Map:** the full map (M) shows both districts with their names written large, and the header shows the district you're in. CENTRAL PLAZA, VELA MALL and POLICE HQ are labelled. Set a waypoint in Downtown from Old Town: the GPS route crosses into it.
- [ ] **Police:** get busted in Downtown: you're released at the police headquarters there (white building, blue POLICE board, on the central east-west road just west of Central Plaza), not in Old Town.
- [ ] **The edge:** walls stop you at the north edge of Downtown and at the city's other edges; beyond is plain ground. Roads that reach the east and west edges end in a turning area.
- [ ] **Performance:** with F3, compare FPS in Downtown's north road and in Old Town. Note both.

### The Beach District (step 2)
- [ ] **Getting there:** drive east from the bus stand along the east gopuram road. Past the garage, Old Town ends and "BEACH DISTRICT" fades in. Keep going to the Coast Road and the sea.
- [ ] **Looks by day:** seafood restaurants (coral walls, SEAFOOD board with a fish), the yellow BEACH INN, striped-awning shops, pastel cottages with thatched porches, the two white Sea Breeze resorts facing the sea with their pools behind. Across the road: palms and benches on the promenade, kiosks, rows of red-and-white umbrellas, blue fishing boats near the water, lifeguard towers. Is the sand the right colour (not glaring white)?
- [ ] **The sea:** turquoise near the shore, deeper blue further out, small waves, a band of foam washing at the water's edge. It carries on to the horizon past the edge of the city. Does the shoreline look right where the sand meets the water?
- [ ] **Wading:** walk (or drive) into the sea: you can go about 40 m out, then something invisible stops you. Is that acceptable for now, or should the water get deep and stop you another way?
- [ ] **The pier:** walk up the ramp and out to the end. Railings stop you falling off; lamps on posts.
- [ ] **The lighthouse** (south end of the beach): red and white bands, a lantern that glows at night, and a beam that sweeps slowly round from dusk. Is the beam too strong or too faint? Does it look right from the Coast Road and from Old Town?
- [ ] **Sunset on the beach** (about 18:00–18:40): this is the district's best hour. Worth a look.
- [ ] **People** walk the promenade and the sand but never into the sea.
- [ ] **Map:** VELA BEACH, PIER, LIGHTHOUSE and the two SEA BREEZE resorts are labelled; the sea is blue.
- [ ] **Police:** busted on the beach, you're released at the Beach District police post (white with a blue POLICE board, on the main road just north-west of the northern resort).

### The Industrial Zone (step 3)
- [ ] **Getting there:** from Downtown, drive east along any east-west road; or from the Beach, north up the Coast Road (it becomes the harbour road). "INDUSTRIAL ZONE" fades in.
- [ ] **Looks:** corrugated warehouses with roll-up doors and loading docks, a brick factory with a sawtooth roof and a tall chimney (red light on top at night), white tank farms, site offices. Big concrete yards with some container stacks. Does it feel like an industrial area, or too empty?
- [ ] **The harbour:** a container yard of red, blue and teal stacks; three red-and-white gantry cranes with their booms over a moored cargo ship; the fishing harbour at the south end (fish-market shed, boats along the quay, benches). Walk between the container stacks: are any floating or overlapping?
- [ ] **At night** the street lamps are sodium orange (their light too, near you), the cranes and the chimney show red warning lights.
- [ ] **Driving:** the big yards and wide roads make for good chases. Do traffic and the police cope with the long straight roads and the T-junctions at the harbour road?
- [ ] **Police:** busted here, you're released at the Industrial Zone's police post (a small white office with a blue POLICE board).
- [ ] **Map:** HARBOUR, CONTAINER YARD, FISHING HARBOUR and FACTORY are labelled.

### The Luxury District (step 4)
- [ ] **Getting there:** from Downtown, drive west along any east-west road. "LUXURY DISTRICT" fades in.
- [ ] **Looks:** avenues lined with walled villa plots: white modern villas, sand-coloured ones with tiled roofs and porticos, grey-and-timber ones; lawns, pools, closed black gates with lamps on the gate pillars. Green verges and trees between plots. Does it feel quiet and wealthy? Any villa poking through its own wall, or a wall across a sidewalk?
- [ ] **The estate** (in the middle, gate on the central east-west road): the mansion with its columns and pediment, the fountain court, the gatehouse, two garages, palms round the grounds. The gate is shut: you can't drive in (yet).
- [ ] **Sandalwood Park** next to it: trees, hedges, benches.
- [ ] **Guard booths** stand where the two main roads leave south for the Countryside.
- [ ] **At night:** gate lamps and ground-floor glass glow; streets are darker than Downtown.

### The Countryside (step 5)
- [ ] **Getting there:** drive west out of Old Town on any street: they meet a country lane along the edge, and the middle road (the highway) carries straight on west. Or drive south out of the Luxury District on either main road. "COUNTRYSIDE" fades in once; driving on into the southern half doesn't show it again.
- [ ] **Looks:** paddy fields in rows behind earth bunds, farmhouses and haystacks, coconut groves, the lake (north) and the reservoir (south) with benches on their banks, two villages: round thatched huts, farmhouses with verandahs, a tea stall with a TEA board, a small shrine, a well. Does it feel calm and open after the city?
- [ ] **The roads** are the city's four-lane roads with sidewalks (narrow country roads aren't in the road kit yet). Do they look too urban out here?
- [ ] **At night** there are no streetlights in the Countryside: is it too dark on foot? (Headlights work.)
- [ ] **People** walk the villages and the lake banks, never into the water. You can wade into the lakes.
- [ ] **Police:** busted out here, you're released at the village police post.
- [ ] **The whole city** (full map, M): six districts, Countryside twice the size of the others; two empty cells south of Old Town and the Beach where roads end at the city's edge.
