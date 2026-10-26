class_name ErrorCounter
extends Logger

var errors: Array[String] = []

func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	var text := rationale if rationale != "" else code
	errors.append("%s (%s:%d)" % [text, file, line])
