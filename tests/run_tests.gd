extends SceneTree

func _init() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	var total := 0
	var failed := 0
	for file in DirAccess.get_files_at("res://tests"):
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd":
			continue
		if only != "" and file.get_basename() != only:
			continue
		var script: GDScript = load("res://tests/" + file)
		for m in script.get_script_method_list():
			if not m.name.begins_with("test_"):
				continue
			var t: TestCase = script.new()
			t.call(m.name)
			total += 1
			if t.failures.is_empty():
				print("  ok   ", file, "::", m.name)
			else:
				failed += 1
				print("  FAIL ", file, "::", m.name)
				for f in t.failures:
					print("       ", f)
	print("%d tests, %d échecs" % [total, failed])
	quit(1 if failed > 0 else 0)
