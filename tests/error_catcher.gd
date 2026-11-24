extends Logger
## Collects engine and script errors while a test runs, so a test can fail on them.
## Registered with OS.add_logger(). Callbacks may arrive from any thread.

var _mutex: Mutex = Mutex.new()
var _errors: PackedStringArray = PackedStringArray()


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	var text: String = rationale if not rationale.is_empty() else code
	_mutex.lock()
	_errors.append("%s (%s:%d in %s)" % [text, file, line, function])
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass


func get_errors() -> PackedStringArray:
	_mutex.lock()
	var copy: PackedStringArray = _errors.duplicate()
	_mutex.unlock()
	return copy
