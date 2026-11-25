class_name DialoguePlayer
extends Node
## Plays a few lines of mission dialogue as subtitles, "SPEAKER: text" per line. Each line stays
## up long enough to read (longer lines longer); skip() moves on at once.

signal line_started(speaker: String, text: String)
signal finished

const MIN_SECONDS: float = 2.2
const MAX_SECONDS: float = 6.5
const SECONDS_PER_CHARACTER: float = 0.05

var _lines: PackedStringArray = []
var _index: int = -1
var _left: float = 0.0


func play(lines: PackedStringArray) -> void:
	_lines = lines
	_index = -1
	_next()


func is_playing() -> bool:
	return _index >= 0


## The speaker of the line on screen ("" when nothing is playing).
func get_speaker() -> String:
	return split(_lines[_index])[0] if is_playing() else ""


func skip() -> void:
	if is_playing():
		_next()


## Ends without emitting `finished` (e.g. the mission failed mid-conversation).
func stop() -> void:
	if is_playing():
		_index = -1
		line_started.emit("", "")


## ["SPEAKER", "text"] for "SPEAKER: text"; a line without a speaker is narration.
static func split(line: String) -> PackedStringArray:
	var colon: int = line.find(":")
	if colon <= 0 or colon > 24:
		return PackedStringArray(["", line.strip_edges()])
	return PackedStringArray([line.left(colon).strip_edges(), line.substr(colon + 1).strip_edges()])


func _process(delta: float) -> void:
	if not is_playing():
		return
	_left -= delta
	if _left <= 0.0:
		_next()


func _next() -> void:
	_index += 1
	if _index >= _lines.size():
		_index = -1
		line_started.emit("", "")
		finished.emit()
		return
	var parts: PackedStringArray = split(_lines[_index])
	_left = clampf(MIN_SECONDS + parts[1].length() * SECONDS_PER_CHARACTER, MIN_SECONDS, MAX_SECONDS)
	line_started.emit(parts[0], parts[1])
