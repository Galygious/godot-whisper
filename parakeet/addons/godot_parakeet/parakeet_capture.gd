class_name ParakeetCapture
extends Node
## Phrase-based English Parakeet recognition. Models are ONNX, not Whisper .bin.
## Energy endpointing is provided here; this does not use a Silero VAD model.

signal model_loaded
signal transcribed_msg(is_complete: bool, new_text: String)
signal transcribed(text: String)
signal command_recognized(command: String, transcript: String)
signal status_changed(message: String, is_error: bool)
signal transcription_finished(seconds: float, audio_seconds: float)
signal input_level_changed(db: float)

const MODEL_FILES := ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]
@export_dir var model_directory := "res://addons/godot_parakeet/models/parakeet-tdt-0.6b-v2-int8"
@export_range(1, 8, 1) var worker_threads := 2
@export var recording := false:
	set(value):
		recording = value
		if is_node_ready() and _ready_model:
			if value:
				_start_microphone()
			else:
				if _microphone != null:
					_microphone.stop()
				finish_phrase()
@export var record_bus := "ParakeetRecord"
@export_range(-70, -10, 1) var speech_threshold_db := -40.0
@export_range(100, 2000, 50) var silence_ms := 400
@export_range(50, 1000, 50) var minimum_speech_ms := 100
@export_range(1000, 15000, 500) var maximum_phrase_ms := 4000
@export var magic_types := PackedStringArray([
	"fire", "earth", "air", "water", "plant", "metal", "lava", "clay",
	"mist", "crystal", "trap", "poison", "zombie", "copy", "time", "psychic",
	"hydra", "dragon", "phoenix", "unicorn", "fae", "golem"
])

var _thread: Thread
var _mutex := Mutex.new()
var _semaphore := Semaphore.new()
var _quit := false
var _job: Dictionary = {}
var _ready_model := false
var _busy := false
var _microphone: AudioStreamPlayer
var _capture: AudioEffectCapture
var _phrase := PackedFloat32Array()
var _preroll := PackedFloat32Array()
var _silent_samples := 0
var _voiced_samples := 0
var _sample_rate := 48000

func _ready() -> void:
	if not ClassDB.class_exists("ParakeetRecognizer"):
		_status("Parakeet native library did not load. Check platform binaries and logs.", true)
		return
	_status("Loading Parakeet model…", false)
	_thread = Thread.new()
	_thread.start(_worker)

func _status(message: String, is_error: bool = false) -> void:
	print("PARAKEET: ", message)
	status_changed.emit(message, is_error)

func _stage_models() -> Dictionary:
	for filename in MODEL_FILES:
		if not FileAccess.file_exists(model_directory.path_join(filename)):
			return {"error": "Missing model file: " + model_directory.path_join(filename)}
	if not OS.has_feature("android") or not model_directory.begins_with("res://"):
		return {"directory": model_directory}
	# ONNX Runtime needs real files. Copy packaged models once in bounded chunks.
	var destination := "user://godot_parakeet/tdt-v2-int8"
	var mkdir_result := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))
	if mkdir_result != OK:
		return {"error": "Cannot create Parakeet model cache: " + error_string(mkdir_result)}
	for filename in MODEL_FILES:
		var source := FileAccess.open(model_directory.path_join(filename), FileAccess.READ)
		if source == null:
			return {"error": "Cannot read packaged model: " + filename}
		var target := destination.path_join(filename)
		if FileAccess.file_exists(target):
			var existing := FileAccess.open(target, FileAccess.READ)
			if existing != null and existing.get_length() == source.get_length():
				continue
		call_deferred("_status", "Preparing model storage: " + filename, false)
		var temporary := target + ".part"
		var output := FileAccess.open(temporary, FileAccess.WRITE)
		if output == null:
			return {"error": "Cannot write model cache; check free storage."}
		var remaining := source.get_length()
		while remaining > 0:
			var chunk := source.get_buffer(mini(4 * 1024 * 1024, remaining))
			if chunk.is_empty():
				return {"error": "Reading model failed: " + filename}
			output.store_buffer(chunk)
			if output.get_error() != OK:
				return {"error": "Writing model failed; check free storage."}
			remaining -= chunk.size()
		output.close()
		var renamed := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(target))
		if renamed != OK:
			return {"error": "Cannot finalize model cache: " + error_string(renamed)}
	return {"directory": destination}

func _worker() -> void:
	var paths := _stage_models()
	if paths.has("error"):
		call_deferred("_status", str(paths.error), true)
		return
	var engine = ClassDB.instantiate("ParakeetRecognizer")
	if not engine.load_model(str(paths.directory), worker_threads):
		call_deferred("_status", str(engine.get_last_error()), true)
		return
	call_deferred("_model_ready")
	while true:
		_semaphore.wait()
		_mutex.lock()
		var stopping := _quit
		var job := _job
		_job = {}
		_mutex.unlock()
		if stopping:
			break
		if job.is_empty():
			continue
		var result: Dictionary = engine.transcribe(job.samples, job.sample_rate)
		call_deferred("_result", result, float(job.samples.size()) / float(job.sample_rate))

func _model_ready() -> void:
	_ready_model = true
	_status("Model ready. Start recording and say a magic type.")
	model_loaded.emit()
	if recording:
		_start_microphone()

func start_recording() -> void:
	recording = true

func stop_recording() -> void:
	recording = false

func _start_microphone() -> void:
	if OS.has_feature("android") and not "android.permission.RECORD_AUDIO" in OS.get_granted_permissions():
		_status("Microphone permission required. Request RECORD_AUDIO, then start recording again.", true)
		return
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		_status("Enable Audio > Driver > Enable Input in Project Settings.", true)
		return
	if _capture == null:
		var index := AudioServer.get_bus_index(record_bus)
		if index == -1:
			index = AudioServer.bus_count
			AudioServer.add_bus()
			AudioServer.set_bus_name(index, record_bus)
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 1.0
		AudioServer.add_bus_effect(index, _capture)
		AudioServer.set_bus_mute(index, true)
		_microphone = AudioStreamPlayer.new()
		_microphone.stream = AudioStreamMicrophone.new()
		_microphone.bus = record_bus
		add_child(_microphone)
	_capture.clear_buffer()
	_phrase.clear()
	_preroll.clear()
	_silent_samples = 0
	_voiced_samples = 0
	_sample_rate = int(AudioServer.get_mix_rate())
	_microphone.play()
	_status("Listening. Say a short phrase, then pause.")

func _process(_delta: float) -> void:
	if _capture == null:
		return
	var available := _capture.get_frames_available()
	if available <= 0:
		return
	var frames := _capture.get_buffer(available)
	if not recording or _busy or frames.is_empty():
		return
	var samples := PackedFloat32Array()
	samples.resize(frames.size())
	var squares := 0.0
	for index in range(frames.size()):
		var sample := (frames[index].x + frames[index].y) * 0.5
		samples[index] = sample
		squares += sample * sample
	var rms := sqrt(squares / samples.size())
	var db := linear_to_db(maxf(rms, 0.000001))
	input_level_changed.emit(db)
	var voice := db >= speech_threshold_db
	if _phrase.is_empty():
		if not voice:
			_preroll.append_array(samples)
			var keep := int(_sample_rate * 0.15)
			if _preroll.size() > keep:
				_preroll = _preroll.slice(_preroll.size() - keep)
			return
		_phrase.append_array(_preroll)
		_preroll.clear()
	_phrase.append_array(samples)
	if voice:
		_voiced_samples += samples.size()
		_silent_samples = 0
	else:
		_silent_samples += samples.size()
	if _silent_samples * 1000 / _sample_rate >= silence_ms or _phrase.size() * 1000 / _sample_rate >= maximum_phrase_ms:
		finish_phrase()

func finish_phrase() -> void:
	if _voiced_samples * 1000 / maxi(_sample_rate, 1) >= minimum_speech_ms:
		transcribe_audio(_phrase, _sample_rate)
	_phrase = PackedFloat32Array()
	_preroll.clear()
	_silent_samples = 0
	_voiced_samples = 0

## Queue one utterance. Returns false while loading or decoding; no backlog.
func transcribe_audio(samples: PackedFloat32Array, sample_rate: int = 16000) -> bool:
	if not _ready_model or _busy or samples.is_empty() or sample_rate < 8000 or sample_rate > 192000:
		return false
	_busy = true
	_mutex.lock()
	_job = {"samples": samples, "sample_rate": sample_rate}
	_mutex.unlock()
	_semaphore.post()
	_status("Transcribing… wait before the next phrase.")
	return true

func _result(result: Dictionary, audio_seconds: float) -> void:
	_busy = false
	if _capture != null:
		_capture.clear_buffer()
	if not str(result.error).is_empty():
		_status(str(result.error), true)
		return
	var text := str(result.text).strip_edges()
	transcribed_msg.emit(true, text)
	transcribed.emit(text)
	transcription_finished.emit(float(result.seconds), audio_seconds)
	var expression := RegEx.new()
	expression.compile("[^a-z0-9 ]")
	var normalized := expression.sub(text.to_lower(), "", true).strip_edges()
	for magic in magic_types:
		if normalized == magic + " magic":
			command_recognized.emit(magic, text)
			break
	_status("Decoded %.2f s audio in %.2f s. %s" % [audio_seconds, float(result.seconds), "Listening…" if recording else "Stopped."])

func shutdown() -> void:
	if _microphone != null:
		_microphone.stop()
	if _thread != null and _thread.is_started():
		_mutex.lock()
		_quit = true
		_mutex.unlock()
		_semaphore.post()
		_thread.wait_to_finish()

func _exit_tree() -> void:
	shutdown()
