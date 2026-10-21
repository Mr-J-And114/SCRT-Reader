class_name RadioVoiceEffects
extends RefCounted
## 仅语音广播通过此总线，保留限频／失真，不添加空间混响或延迟。
const BUS: StringName = &"SCRTRadioVoice"
var config: Dictionary = {}
var lowpass: AudioEffectLowPassFilter
var distortion: AudioEffectDistortion
var _quality: float = 1.0

func setup(send: StringName) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://radio/speech_effects.json"))
	config = data if data is Dictionary else {}
	var index: int = AudioServer.get_bus_index(BUS)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(index, BUS)
	AudioServer.set_bus_send(index, send)
	for i in range(AudioServer.get_bus_effect_count(index) - 1, -1, -1): AudioServer.remove_bus_effect(index, i)
	var highpass := AudioEffectHighPassFilter.new()
	highpass.cutoff_hz = clampf(float(config.get("highpass_hz", 300.0)), 40.0, 500.0)
	lowpass = AudioEffectLowPassFilter.new()
	distortion = AudioEffectDistortion.new()
	distortion.mode = AudioEffectDistortion.MODE_ATAN
	distortion.pre_gain = clampf(float(config.get("distortion_pre_gain_db", 12.0)), -6.0, 18.0)
	distortion.post_gain = clampf(float(config.get("distortion_post_gain_db", 8.0)), -18.0, 12.0)
	for effect: AudioEffect in [highpass, distortion, lowpass]:
		AudioServer.add_bus_effect(index, effect)
		AudioServer.set_bus_effect_enabled(index, AudioServer.get_bus_effect_count(index) - 1, bool(config.get("enabled", true)))
	update(1.0, 1.0)

func update(quality: float, delta: float) -> void:
	_quality = lerpf(_quality, clampf(quality, 0.0, 1.0), minf(delta * 4.0, 1.0))
	lowpass.cutoff_hz = lerpf(clampf(float(config.get("weak_lowpass_hz", 2200.0)), 1600.0, 6000.0), clampf(float(config.get("lowpass_hz", 3000.0)), 2000.0, 8000.0), _quality)
	distortion.drive = lerpf(clampf(float(config.get("weak_distortion_drive", 0.78)), 0.0, 0.9), clampf(float(config.get("distortion_drive", 0.62)), 0.0, 0.85), _quality)

func set_output_volume(db: float) -> void:
	# 总线音量在效果后作用；调低听音音量不再削弱饱和／失真。
	var level: float = clampf(float(config.get("output_volume", 0.5)), 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUS), db + linear_to_db(level) if level > 0.0 else -80.0)
