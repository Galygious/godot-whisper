extends Control

@onready var capture: ParakeetCapture = $ParakeetCapture
var _status: Label
var _transcript: Label
var _command: Label
var _start: Button
var _sample: Button
var _level: ProgressBar

func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	for text in ["Parakeet magic commands", "Say a phrase such as ‘fire magic’, then pause."]:
		var label := Label.new()
		label.text = text
		label.add_theme_font_size_override("font_size", 26)
		column.add_child(label)
	_status = Label.new()
	_status.text = "Loading model. First Android launch may copy about 630 MiB to app storage."
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_sample = Button.new()
	_sample.text = "Test bundled recording"
	_sample.custom_minimum_size.y = 60
	_sample.disabled = true
	_sample.pressed.connect(func(): capture.transcribe_audio(FileAccess.get_file_as_bytes("res://tests/jfk.f32").to_float32_array(), 16000))
	column.add_child(_sample)
	_start = Button.new()
	_start.text = "Start microphone"
	_start.custom_minimum_size.y = 60
	_start.disabled = true
	_start.pressed.connect(_request_microphone)
	column.add_child(_start)
	var stop := Button.new()
	stop.text = "Stop microphone and finish phrase"
	stop.custom_minimum_size.y = 60
	stop.pressed.connect(capture.stop_recording)
	column.add_child(stop)
	_level = ProgressBar.new()
	_level.min_value = -70
	_level.max_value = 0
	_level.value = -70
	_level.show_percentage = false
	column.add_child(_level)
	_transcript = Label.new()
	_transcript.text = "Transcript appears here."
	_transcript.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_transcript.add_theme_font_size_override("font_size", 24)
	column.add_child(_transcript)
	_command = Label.new()
	column.add_child(_command)
	capture.status_changed.connect(func(message, _error): _status.text = message)
	capture.transcribed.connect(func(text): _transcript.text = text)
	capture.command_recognized.connect(func(magic, _text): _command.text = "Recognized magic: " + magic)
	capture.input_level_changed.connect(func(db): _level.value = db)
	capture.model_loaded.connect(func():
		_start.disabled = false
		_sample.disabled = false)
	if OS.has_feature("android"):
		get_tree().on_request_permissions_result.connect(func(permission, granted):
			if permission.ends_with("RECORD_AUDIO") and granted:
				capture.start_recording())

func _request_microphone() -> void:
	if OS.has_feature("android") and not "android.permission.RECORD_AUDIO" in OS.get_granted_permissions():
		OS.request_permission("RECORD_AUDIO")
	else:
		capture.start_recording()
