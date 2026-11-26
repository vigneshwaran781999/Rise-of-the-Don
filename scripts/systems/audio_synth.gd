class_name AudioSynth
extends RefCounted
## Builds simple placeholder sounds in code (original, no external files) as AudioStreamWAV.
## GDD §13 allows synthesised placeholders until real audio exists.

const RATE: int = 22050
const PAD_RATE: int = 16000


static func to_wav(samples: PackedFloat32Array, rate: int = RATE, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i: int in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


## Short sine blips played one after another (menu move / accept / back).
static func blips(freqs: PackedFloat32Array, note_seconds: float, volume: float) -> AudioStreamWAV:
	var per_note: int = int(note_seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(per_note * freqs.size())
	for n: int in freqs.size():
		for i: int in per_note:
			var t: float = float(i) / RATE
			var env: float = minf(1.0, t / 0.004) * exp(-t * 7.0 / note_seconds)
			out[n * per_note + i] = sin(TAU * freqs[n] * t) * env * volume
	return to_wav(out)


## Filtered noise burst over a low sine thump (footsteps, landings).
static func thump(seconds: float, brightness: float, thump_hz: float, volume: float, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var count: int = int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var low_passed: float = 0.0
	for i: int in count:
		var t: float = float(i) / RATE
		var env: float = minf(1.0, t / 0.003) * exp(-t * 6.0 / seconds)
		low_passed += (rng.randf_range(-1.0, 1.0) - low_passed) * brightness
		var body: float = sin(TAU * thump_hz * t) * exp(-t * 10.0 / seconds)
		out[i] = (low_passed * 0.9 + body * 0.6) * env * volume
	return to_wav(out)


## A swish of air (a punch thrown): noise swelling and fading over `seconds`, brightest in the
## middle of the swing.
static func whoosh(seconds: float, volume: float, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var count: int = int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var low: float = 0.0
	var lower: float = 0.0
	for i: int in count:
		var x: float = float(i) / count
		var env: float = pow(sin(PI * x), 2.0)
		low += (rng.randf_range(-1.0, 1.0) - low) * (0.05 + 0.25 * env)
		lower += (low - lower) * 0.08
		out[i] = (low - lower) * env * volume * 3.0          # band-passed: no rumble, no hiss
	return to_wav(out)


## Engine speed the engine loop is recorded at. Playing it at pitch_scale = rpm / ENGINE_LOOP_RPM
## gives that engine speed.
const ENGINE_LOOP_RPM: float = 2000.0


## Four-cylinder engine note at ENGINE_LOOP_RPM (firing at 66.7 Hz), looping seamlessly every
## 0.6 s: every partial, the firing pulses and the noise table repeat a whole number of times.
static func engine_loop() -> AudioStreamWAV:
	var loop_seconds: float = 0.6
	var count: int = int(loop_seconds * RATE)
	var fire_hz: float = ENGINE_LOOP_RPM / 60.0 * 2.0
	# Combustion noise: one table four firings long, low-passed in a circle so it tiles cleanly.
	var table_size: int = int(round(RATE * 4.0 / fire_hz))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var raw := PackedFloat32Array()
	raw.resize(table_size)
	for i: int in table_size:
		raw[i] = rng.randf_range(-1.0, 1.0)
	var noise := PackedFloat32Array()
	noise.resize(table_size)
	var state: float = 0.0
	for pass_index: int in 2:
		for i: int in table_size:
			state += (raw[i] - state) * 0.18
			noise[i] = state
	var out := PackedFloat32Array()
	out.resize(count)
	var peak: float = 0.0
	for i: int in count:
		var t: float = float(i) / RATE
		var phase: float = TAU * fire_hz * t
		var s: float = 0.0
		for k: int in range(1, 11):
			var amp: float = 1.0 / pow(float(k), 0.85)
			if k == 2 or k == 3:
				amp *= 1.4
			s += sin(phase * k + float(k) * 0.7) * amp
		s += sin(phase * 0.5) * 0.55 + sin(phase * 0.25 + 1.3) * 0.3   # uneven firing burble
		var pulse: float = pow(0.5 + 0.5 * cos(phase), 4.0)
		s += noise[i % table_size] * (0.6 + 2.2 * pulse)
		out[i] = s
		peak = maxf(peak, absf(s))
	var gain: float = 0.55 / maxf(peak, 0.001)
	for i: int in count:
		out[i] *= gain
	return to_wav(out, RATE, true)


## Two-tone car horn, looping every 0.5 s (both notes complete whole cycles).
static func horn_loop() -> AudioStreamWAV:
	var count: int = int(0.5 * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i: int in count:
		var t: float = float(i) / RATE
		var low: float = tanh(2.6 * sin(TAU * 420.0 * t))
		var high: float = tanh(2.6 * sin(TAU * 504.0 * t))
		out[i] = (low + high) * 0.24
	return to_wav(out, RATE, true)


## Tyre screech for sliding: band-limited noise plus a wavering squeal, looping every second.
static func skid_loop() -> AudioStreamWAV:
	var count: int = RATE
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var raw := PackedFloat32Array()
	raw.resize(count)
	for i: int in count:
		raw[i] = rng.randf_range(-1.0, 1.0)
	var out := PackedFloat32Array()
	out.resize(count)
	var low: float = 0.0
	var band: float = 0.0
	for pass_index: int in 2:   # second pass makes the filtered noise wrap around cleanly
		for i: int in count:
			low += (raw[i] - low) * 0.5
			band += (low - band) * 0.08
			var t: float = float(i) / RATE
			var squeal: float = sin(TAU * 1100.0 * t + 2.0 * sin(TAU * 6.0 * t))
			out[i] = (low - band) * 0.5 + squeal * 0.22
	return to_wav(out, RATE, true)


## Metal-and-glass crunch for collisions: a low thump, inharmonic clanks and a noise burst.
static func crash() -> AudioStreamWAV:
	var seconds: float = 0.6
	var count: int = int(seconds * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var out := PackedFloat32Array()
	out.resize(count)
	var low_passed: float = 0.0
	var clanks: Array = [[410.0, 0.35, 9.0], [622.0, 0.3, 11.0], [1133.0, 0.22, 16.0], [1657.0, 0.16, 22.0], [2390.0, 0.1, 30.0]]
	for i: int in count:
		var t: float = float(i) / RATE
		var attack: float = minf(1.0, t / 0.002)
		low_passed += (rng.randf_range(-1.0, 1.0) - low_passed) * 0.45
		var s: float = low_passed * exp(-t * 9.0) * 0.8
		s += sin(TAU * 55.0 * t) * exp(-t * 12.0) * 0.9
		for c: Array in clanks:
			s += sin(TAU * float(c[0]) * t) * float(c[1]) * exp(-t * float(c[2]))
		out[i] = tanh(s * attack * 1.2) * 0.8
	return to_wav(out)


## Moody D-minor drone with a slow sub-bass pulse, looping seamlessly every 4 s
## (every partial completes whole cycles in the loop). Menu music placeholder.
## Takes a fraction of a second, so AudioManager builds it on a worker thread.
static func ambient_pad() -> AudioStreamWAV:
	var loop_seconds: float = 4.0
	var count: int = int(loop_seconds * PAD_RATE)
	# [frequency Hz (multiples of 0.25), amplitude, tremolo phase]
	var voices: Array = [
		[146.75, 0.20, 0.0], [147.0, 0.14, 1.7],     # D3 + slow-beating twin
		[174.5, 0.16, 2.9], [220.0, 0.16, 4.1],      # F3, A3
		[220.25, 0.10, 0.6], [329.75, 0.08, 3.3],    # A3 twin, E4
		[523.25, 0.035, 5.0],                        # C5 shimmer
	]
	var out := PackedFloat32Array()
	out.resize(count)
	var peak: float = 0.0
	for i: int in count:
		var t: float = float(i) / PAD_RATE
		var s: float = 0.0
		for v: Array in voices:
			var trem: float = 0.65 + 0.35 * sin(TAU * 0.25 * t + float(v[2]))
			s += sin(TAU * float(v[0]) * t) * float(v[1]) * trem
		var beat: float = fmod(t, 2.0)                # sub pulse every 2 s, starts on a zero crossing
		s += sin(TAU * 73.5 * t) * 0.35 * (1.0 - exp(-beat * 40.0)) * exp(-beat * 2.2)
		out[i] = s
		peak = maxf(peak, absf(s))
	var gain: float = 0.42 / maxf(peak, 0.001)
	for i: int in count:
		out[i] *= gain
	return to_wav(out, PAD_RATE, true)


## Police siren: a wail sweeping 650-1350 Hz and back every 1.6 s, looping on the sweep.
static func siren_loop() -> AudioStreamWAV:
	var seconds: float = 3.2
	var count: int = int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in count:
		var t: float = float(i) / RATE
		var sweep: float = 0.5 - 0.5 * cos(TAU * t / 1.6)
		var freq: float = lerpf(650.0, 1350.0, sweep)
		phase += TAU * freq / RATE
		var tone: float = sin(phase) * 0.75 + sin(phase * 3.0) * 0.12
		out[i] = tone * 0.28
	return to_wav(out, RATE, true)


## Helicopter rotor: noise chopped by the blades about 18 times a second, over a low drone.
static func rotor_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var count: int = int(1.0 * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var low: float = 0.0
	for i: int in count:
		var t: float = float(i) / RATE
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.08
		var chop: float = pow(0.5 + 0.5 * cos(TAU * 18.0 * t), 3.0)
		out[i] = (low * (0.35 + 0.9 * chop) + sin(TAU * 54.0 * t) * 0.15) * 0.6
	return to_wav(out, RATE, true)


## Steady rain: soft filtered noise (the hiss of the downpour) with scattered drop ticks, looping
## every 3 s. The end fades into the start so the loop has no seam.
static func rain_loop() -> AudioStreamWAV:
	var seconds: float = 3.0
	var count: int = int(seconds * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var out := PackedFloat32Array()
	out.resize(count)
	var low: float = 0.0
	var band: float = 0.0
	for i: int in count:
		var white: float = rng.randf_range(-1.0, 1.0)
		low += (white - low) * 0.18            # take the harsh top off
		band += (low - band) * 0.6
		out[i] = (low - band * 0.5) * 0.55
	for drop: int in 140:                       # little ticks of single drops
		var at: int = rng.randi() % (count - 400)
		var size: float = rng.randf_range(0.08, 0.25)
		for k: int in 300:
			out[at + k] += sin(k * rng.randf_range(0.9, 1.4)) * size * exp(-k / 40.0)
	var fade: int = int(0.25 * RATE)          # crossfade the tail into the head
	for k: int in fade:
		var t: float = float(k) / fade
		out[k] = out[k] * t + out[count - fade + k] * (1.0 - t)
	out.resize(count - fade)
	return to_wav(out, RATE, true)


# --------------------------------------------------------------------------- footsteps and ambience (M7)

## A footstep on `surface` (CityData.SURFACES): a burst of filtered noise over a low body, shaped
## per surface. Road: dull. Paved: a crisp tap. Sand: a soft scuff. Grass: a rustle. Wood: a hollow
## knock. Water: a splash.
static func footstep(surface: StringName) -> AudioStreamWAV:
	# [seconds, noise brightness, noise level, body Hz, body level, attack seconds, volume, seed]
	var shapes: Dictionary = {
		&"road": [0.09, 0.22, 0.8, 80.0, 0.7, 0.003, 0.55, 11],
		&"paved": [0.08, 0.5, 0.9, 115.0, 0.45, 0.002, 0.5, 13],
		&"sand": [0.14, 0.12, 1.0, 60.0, 0.15, 0.02, 0.45, 17],
		&"grass": [0.13, 0.35, 0.9, 70.0, 0.15, 0.012, 0.4, 19],
		&"wood": [0.16, 0.3, 0.5, 190.0, 0.9, 0.002, 0.6, 23],
		&"water": [0.3, 0.45, 1.0, 90.0, 0.2, 0.015, 0.5, 29],
	}
	var s: Array = shapes.get(surface, shapes[&"paved"])
	var seconds: float = s[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s[7])
	var count: int = int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var low: float = 0.0
	for i: int in count:
		var t: float = float(i) / RATE
		var env: float = minf(1.0, t / float(s[5])) * exp(-t * 6.0 / seconds)
		low += (rng.randf_range(-1.0, 1.0) - low) * float(s[1])
		var body: float = sin(TAU * float(s[3]) * t) * exp(-t * 10.0 / seconds)
		if surface == &"wood":
			body += sin(TAU * float(s[3]) * 2.07 * t) * 0.4 * exp(-t * 14.0 / seconds)    # hollow ring
		if surface == &"water":
			low *= 0.85 + 0.15 * sin(TAU * 23.0 * t)                                       # sloshing
		out[i] = (low * float(s[2]) + body * float(s[4])) * env * float(s[6])
	return to_wav(out)


const AMBIENCE_RATE: int = 16000


## Fades the last `fade_seconds` of a loop into its start and cuts them off, so it repeats seamlessly.
static func _seamless(out: PackedFloat32Array, rate: int, fade_seconds: float) -> PackedFloat32Array:
	var fade: int = int(fade_seconds * rate)
	var count: int = out.size()
	for k: int in fade:
		var t: float = float(k) / fade
		out[k] = out[k] * t + out[count - fade + k] * (1.0 - t)
	out.resize(count - fade)
	return out


## Distant city traffic: a low rumble of engines and tyres, a faint mains hum, the odd far-off horn.
static func city_hum_loop() -> AudioStreamWAV:
	var rate: int = AMBIENCE_RATE
	var count: int = int(6.0 * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = 301
	var out := PackedFloat32Array()
	out.resize(count)
	var low: float = 0.0
	var lower: float = 0.0
	for i: int in count:
		var t: float = float(i) / rate
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.05
		lower += (low - lower) * 0.1
		var swell: float = 0.75 + 0.25 * sin(TAU * t / 6.0)
		out[i] = (low * 0.9 + lower * 1.6) * swell * 0.6 + sin(TAU * 98.0 * t) * 0.01
	for horn: Array in [[1.3, 415.0, 0.35], [3.9, 470.0, 0.25], [4.4, 470.0, 0.2]]:
		var at: int = int(float(horn[0]) * rate)
		for k: int in int(0.35 * rate):
			var t: float = float(k) / rate
			var env: float = minf(1.0, t / 0.02) * minf(1.0, (0.35 - t) / 0.05)
			out[at + k] += (sin(TAU * float(horn[1]) * t) + 0.5 * sin(TAU * float(horn[1]) * 1.26 * t)) * env * 0.04 * float(horn[2]) * 4.0
	return to_wav(_seamless(out, rate, 0.5), rate, true)


## Waves on the shore: hissing surf rising and falling twice every 8 s.
static func waves_loop() -> AudioStreamWAV:
	var rate: int = AMBIENCE_RATE
	var seconds: float = 8.5
	var count: int = int(seconds * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = 302
	var out := PackedFloat32Array()
	out.resize(count)
	var low: float = 0.0
	var lower: float = 0.0
	for i: int in count:
		var t: float = float(i) / rate
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.25
		lower += (low - lower) * 0.08
		var phase: float = fposmod(t, 4.0) / 4.0              # a wave breaks, then draws back
		var swell: float = pow(sin(PI * minf(phase * 1.6, 1.0)), 2.0) * (1.0 - phase * 0.4) + 0.12
		out[i] = (low * 0.45 + lower * 0.9) * swell * 0.75
	return to_wav(_seamless(out, rate, 0.5), rate, true)


## The Industrial Zone: a low machine drone with a slow beat, hiss, and metal clanks now and then.
static func industrial_loop() -> AudioStreamWAV:
	var rate: int = AMBIENCE_RATE
	var count: int = int(6.5 * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = 303
	var out := PackedFloat32Array()
	out.resize(count)
	var low: float = 0.0
	for i: int in count:
		var t: float = float(i) / rate
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.15
		var drone: float = sin(TAU * 49.0 * t) * 0.5 + sin(TAU * 98.5 * t) * 0.25 + sin(TAU * 147.0 * t) * 0.1
		out[i] = drone * (0.8 + 0.2 * sin(TAU * 0.5 * t)) * 0.12 + low * 0.12
	for clank: float in [0.7, 2.6, 4.1]:
		var at: int = int(clank * rate)
		for k: int in int(0.6 * rate):
			var t: float = float(k) / rate
			var ring: float = sin(TAU * 523.0 * t) + 0.7 * sin(TAU * 1371.0 * t) + 0.5 * sin(TAU * 2213.0 * t)
			out[at + k] += ring * exp(-t * 9.0) * 0.08
	return to_wav(_seamless(out, rate, 0.5), rate, true)


## Birdsong: bright little chirps and trills scattered over 6 s, over a faint breeze.
static func birds_loop() -> AudioStreamWAV:
	var rate: int = AMBIENCE_RATE
	var count: int = int(6.5 * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = 304
	var out := PackedFloat32Array()
	out.resize(count)
	var low: float = 0.0
	for i: int in count:
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.03
		out[i] = low * 0.15
	for call: int in 14:
		var at: float = rng.randf_range(0.0, 5.8)
		var base: float = rng.randf_range(2200.0, 3800.0)
		var notes: int = rng.randi_range(2, 5)
		for n: int in notes:
			var start: int = int((at + n * 0.07) * rate)
			var length: int = int(0.05 * rate)
			var phase: float = 0.0
			for k: int in length:
				if start + k >= count:
					break
				var t: float = float(k) / length
				phase += TAU * base * (1.0 + 0.35 * t) / rate         # a quick upward sweep
				out[start + k] += sin(phase) * sin(PI * t) * 0.06
	return to_wav(_seamless(out, rate, 0.5), rate, true)


## Crickets at night: two high trills pulsing on and off.
static func crickets_loop() -> AudioStreamWAV:
	var rate: int = AMBIENCE_RATE
	var count: int = int(3.4 * rate)
	var out := PackedFloat32Array()
	out.resize(count)
	for i: int in count:
		var t: float = float(i) / rate
		var a: float = (1.0 if fposmod(t, 0.9) < 0.45 else 0.0) * (0.5 + 0.5 * sin(TAU * 32.0 * t))
		var b: float = (1.0 if fposmod(t + 0.3, 1.3) < 0.5 else 0.0) * (0.5 + 0.5 * sin(TAU * 27.0 * t))
		out[i] = sin(TAU * 4300.0 * t) * a * 0.035 + sin(TAU * 3900.0 * t) * b * 0.025
	return to_wav(_seamless(out, rate, 0.4), rate, true)
