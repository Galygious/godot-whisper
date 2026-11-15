extends Control

const MODEL_PATH := "res://models/ggml-tiny.en-q5_1.bin"
var _speech: Node
var _model: Resource
var _thread: Thread
var _capture: AudioEffectCapture
var _microphone: AudioStreamPlayer
var _busy := false
var _recording := false
var _frames := PackedVector2Array()
var _record_started := 0
var _status: Label
var _result: Label
var _level: ProgressBar
var _sample_button: Button
var _record_button: Button
var _model_ready := false

func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	margin.add_child(column)
	var title := Label.new()
	title.text = "Whisper / Quest 3 test"
	title.add_theme_font_size_override("font_size", 34)
	column.add_child(title)
	var description := Label.new()
	description.text = "Offline English transcription • tiny.en Q5 • CPU\nFirst test the bundled recording, then try the microphone."
	description.add_theme_font_size_override("font_size", 22)
	column.add_child(description)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 22)
	column.add_child(_status)
	_sample_button = Button.new()
	_sample_button.text = "1. Transcribe bundled speech"
	_sample_button.custom_minimum_size.y = 72
	_sample_button.add_theme_font_size_override("font_size", 24)
	_sample_button.pressed.connect(_test_sample)
	column.add_child(_sample_button)
	_record_button = Button.new()
	_record_button.text = "2. Record 5 seconds and transcribe"
	_record_button.custom_minimum_size.y = 72
	_record_button.add_theme_font_size_override("font_size", 24)
	_record_button.pressed.connect(_request_recording)
	column.add_child(_record_button)
	_level = ProgressBar.new()
	_level.show_percentage = false
	_level.custom_minimum_size.y = 16
	column.add_child(_level)
	_result = Label.new()
	_result.text = "Transcript will appear here."
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_result.add_theme_font_size_override("font_size", 26)
	column.add_child(_result)
	if OS.has_feature("android"):
		get_tree().on_request_permissions_result.connect(_permission_result)
	_set_busy(true)
	if not ClassDB.class_exists("SpeechToText") or not ClassDB.class_exists("WhisperResource"):
		_report("FAIL: native extension did not register its classes. Capture adb logcat.")
		return
	_speech = ClassDB.instantiate("SpeechToText")
	add_child(_speech)
	_model = ClassDB.instantiate("WhisperResource")
	_model.set("file", MODEL_PATH)
	_speech.set("flash_attn", false)
	_speech.set("token_timestamps", false)
	_report("PASS: ARM64 extension loaded. Loading the offline model…")
	_thread = Thread.new()
	_thread.start(_load_model)

func _report(message: String) -> void:
	_status.text = message
	print("QUEST_WHISPER: ", message)

func _set_busy(value: bool) -> void:
	_busy = value
	_sample_button.disabled = value or not _model_ready
	_record_button.disabled = value or not _model_ready

func _load_model() -> void:
	_speech.set("language_model", _model)
	var error: String = _speech.call("get_last_error")
	call_deferred("_model_loaded", error)

func _model_loaded(error: String) -> void:
	_thread.wait_to_finish()
	if not error.is_empty():
		_report("FAIL loading model: " + error)
		return
	_model_ready = true
	_set_busy(false)
	_report("PASS: model loaded. Ready for the bundled speech test.")
	# Used for automated desktop validation; normal headset runs stay interactive.
	if "--auto-sample" in OS.get_cmdline_user_args():
		_test_sample()

func _test_sample() -> void:
	if _busy:
		return
	var wav := load("res://jfk.wav") as AudioStreamWAV
	if wav == null or wav.format != AudioStreamWAV.FORMAT_16_BITS or wav.stereo or wav.mix_rate != 16000:
		_report("FAIL: bundled test audio must be mono, PCM16, 16000 Hz.")
		return
	var bytes := wav.data
	var samples := PackedFloat32Array()
	samples.resize(bytes.size() / 2)
	for i in range(samples.size()):
		samples[i] = bytes.decode_s16(i * 2) / 32768.0
	_start_transcription(samples)

func _request_recording() -> void:
	if _busy:
		return
	if OS.has_feature("android") and not "android.permission.RECORD_AUDIO" in OS.get_granted_permissions():
		OS.request_permission("RECORD_AUDIO")
		_report("Allow microphone access, then recording will start.")
		return
	_start_recording()

func _permission_result(permission: String, granted: bool) -> void:
	if permission.ends_with("RECORD_AUDIO"):
		if granted and not _busy:
			_start_recording()
		elif not granted:
			_report("Microphone permission denied. Allow it in app permissions, then retry.")

func _start_recording() -> void:
	if _capture == null:
		var bus := AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(bus, "QuestMic")
		# Capture before muting the bus so the microphone does not feed back.
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 2.0
		AudioServer.add_bus_effect(bus, _capture)
		AudioServer.set_bus_mute(bus, true)
		_microphone = AudioStreamPlayer.new()
		_microphone.stream = AudioStreamMicrophone.new()
		_microphone.bus = "QuestMic"
		add_child(_microphone)
	_frames.clear()
	_capture.clear_buffer()
	_set_busy(true)
	_recording = true
	_record_started = Time.get_ticks_msec()
	_microphone.play()
	_report("Recording for 5 seconds. Speak now…")

func _process(_delta: float) -> void:
	if not _recording:
		return
	var chunk := _capture.get_buffer(_capture.get_frames_available())
	_frames.append_array(chunk)
	var peak := 0.0
	for frame in chunk:
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	_level.value = minf(100.0, peak * 300.0)
	if Time.get_ticks_msec() - _record_started >= 5000:
		_recording = false
		_microphone.stop()
		_level.value = 0.0
		if _frames.is_empty():
			_set_busy(false)
			_report("FAIL: no microphone frames. Check permission and headset mute.")
			return
		var max_amplitude := 0.0
		for frame in _frames:
			max_amplitude = maxf(max_amplitude, maxf(absf(frame.x), absf(frame.y)))
		if max_amplitude < 0.0001:
			_set_busy(false)
			_report("Microphone returned silence. Check headset mute and speak closer.")
			return
		var samples: PackedFloat32Array = _speech.call("resample", _frames)
		_frames.clear()
		_start_transcription(samples)

func _start_transcription(samples: PackedFloat32Array) -> void:
	_set_busy(true)
	_report("Transcribing offline on CPU…")
	_thread = Thread.new()
	_thread.start(_transcribe.bind(samples))

func _transcribe(samples: PackedFloat32Array) -> void:
	var started := Time.get_ticks_msec()
	var tokens: Array = _speech.call("transcribe", samples, "", 0)
	var error: String = _speech.call("get_last_error")
	var text := "" if tokens.is_empty() else str(tokens[0]).strip_edges()
	call_deferred("_transcribed", text, error, (Time.get_ticks_msec() - started) / 1000.0)

func _transcribed(text: String, error: String, elapsed: float) -> void:
	_thread.wait_to_finish()
	_set_busy(false)
	_result.text = text if not text.is_empty() else "No speech recognized."
	if error.is_empty():
		_report("PASS: transcription finished in %.2f seconds." % elapsed)
	else:
		_report("FAIL transcribing: " + error)
	print("QUEST_WHISPER_TRANSCRIPT: ", text)
	if "--auto-sample" in OS.get_cmdline_user_args():
		var passed := error.is_empty() and "country" in text.to_lower()
		get_tree().quit(0 if passed else 1)

func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
