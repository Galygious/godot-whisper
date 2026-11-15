extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(45.0).timeout.connect(func():
		push_error("Capture integration test timed out")
		quit(1))
	var capture = load("res://addons/godot_parakeet/parakeet_capture.gd").new()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--model-dir="):
			capture.model_directory = argument.trim_prefix("--model-dir=")
	root.add_child(capture)
	await capture.model_loaded
	var samples := FileAccess.get_file_as_bytes("res://tests/jfk.f32").to_float32_array()
	assert(capture.transcribe_audio(samples, 16000))
	assert(not capture.transcribe_audio(samples, 16000), "Busy recognizer must not accumulate a backlog")
	var text: String = await capture.transcribed
	assert("country" in text.to_lower(), text)
	print("PASS: asynchronous capture API, final transcript, rejects queued backlog")
	# A partial phrase is submitted on explicit stop rather than being lost.
	capture._phrase = samples
	capture._voiced_samples = samples.size()
	capture._sample_rate = 16000
	capture.recording = false
	text = await capture.transcribed
	assert("country" in text.to_lower(), text)
	print("PASS: explicit stop flushes captured phrase")
	# Commands only match complete, normalized supported phrases.
	var commands: Array[String] = []
	capture.command_recognized.connect(func(command, _text): commands.append(command))
	capture._result({"text": "Fire magic.", "error": "", "seconds": 0.0}, 1.0)
	capture._result({"text": "There is a fire outside.", "error": "", "seconds": 0.0}, 1.0)
	assert(commands == ["fire"])
	print("PASS: exact magic command matching, ignores unrelated text")
	# Shutdown must join an in-flight decoder before the native recognizer dies.
	await process_frame
	assert(capture.transcribe_audio(samples, 16000))
	capture.shutdown()
	capture.free()
	print("PASS: clean shutdown with a queued/in-flight utterance")
	quit(0)
