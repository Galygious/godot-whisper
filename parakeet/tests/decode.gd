extends SceneTree

func _initialize() -> void:
	var directory := "res://addons/godot_parakeet/models/parakeet-tdt-0.6b-v2-int8"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--model-dir="):
			directory = argument.trim_prefix("--model-dir=")
	if not ClassDB.class_exists("ParakeetRecognizer"):
		push_error("ParakeetRecognizer native extension did not load")
		quit(1)
		return
	var engine = ClassDB.instantiate("ParakeetRecognizer")
	# Exercise error handling before loading a model.
	assert(not str(engine.transcribe(PackedFloat32Array(), 16000).error).is_empty())
	var started := Time.get_ticks_msec()
	if not engine.load_model(directory, 2):
		push_error(engine.get_last_error())
		quit(1)
		return
	print("PARAKEET_MODEL_LOAD_SECONDS: ", (Time.get_ticks_msec() - started) / 1000.0)
	var bytes := FileAccess.get_file_as_bytes("res://tests/jfk.f32")
	var samples := bytes.to_float32_array()
	for index in range(3):
		var result: Dictionary = engine.transcribe(samples, 16000)
		print("PARAKEET_RESULT: ", JSON.stringify(result))
		if not str(result.error).is_empty() or not "country" in str(result.text).to_lower():
			quit(1)
			return
	quit(0)
