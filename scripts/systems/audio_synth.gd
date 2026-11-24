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
