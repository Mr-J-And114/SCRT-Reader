class_name CommVoice
extends RefCounted
## 逐字符短音：基础音色 + 谐波明亮度 + 音量包络。
const SAMPLE_RATE: int = 22050
const PUNCTUATION: String = "，。！？；：、…—,.!?;:（）()「」『』“”\""
const DEFAULT_CONFIG: Dictionary = {
	"tone": "warm", "base_frequency_hz": 345.0, "pitch_variance": 0.04,
	"char_sound_duration": 65, "brightness": 0.25, "volume_db": -13.0,
	"attack_ms": 5.0, "release_ms": 30.0, "punctuation_pause": 200, "voice_every_n": 1,
}
var config: Dictionary = DEFAULT_CONFIG.duplicate()
var _audio_player: AudioStreamPlayer = null
var _sample: AudioStreamWAV = null
var _spoken_chars: int = 0

func setup(main_node: Node) -> void:
	_audio_player = AudioStreamPlayer.new()
	_audio_player.name = "CommVoicePlayer"
	_audio_player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_audio_player.max_polyphony = 2
	main_node.add_child(_audio_player)
	_audio_player.volume_db = float(config["volume_db"])

func apply_config(voice_cfg: Dictionary) -> void:
	config = DEFAULT_CONFIG.duplicate()
	config.merge(voice_cfg, true)
	if not voice_cfg.has("base_frequency_hz") and voice_cfg.has("base_pitch"):
		config["base_frequency_hz"] = 220.0 * float(voice_cfg["base_pitch"])
	_sample = null
	_spoken_chars = 0
	if _audio_player:
		_audio_player.stop()
		_audio_player.volume_db = clampf(float(config["volume_db"]), -40.0, 0.0)

func speak_char(ch: String) -> void:
	if _audio_player == null or ch.strip_edges().is_empty() or is_punctuation(ch):
		return
	_spoken_chars += 1
	if (_spoken_chars - 1) % maxi(1, int(config.get("voice_every_n", 1))) != 0:
		return
	if _sample == null:
		_sample = _generate_sample()
		_audio_player.stream = _sample
	var variance: float = clampf(float(config.get("pitch_variance", 0.04)), 0.0, 0.25)
	_audio_player.pitch_scale = 1.0 + randf_range(-variance, variance)
	_audio_player.play()

func stop() -> void:
	if _audio_player:
		_audio_player.stop()

func get_char_delay() -> float:
	match str(config.get("speed", "normal")):
		"slow": return 0.06
		"fast": return 0.025
		_: return 0.04

func get_punctuation_pause(ch: String) -> float:
	return maxf(0.0, float(config.get("punctuation_pause", 200))) / 1000.0 if is_punctuation(ch) else 0.0

func is_punctuation(ch: String) -> bool:
	return ch.length() == 1 and PUNCTUATION.contains(ch)

func _generate_sample() -> AudioStreamWAV:
	var tone: String = str(config.get("tone", "warm"))
	var frequency: float = clampf(float(config.get("base_frequency_hz", 345.0)), 140.0, 700.0)
	var duration: int = clampi(int(config.get("char_sound_duration", 65)), 25, 180)
	var brightness: float = clampf(float(config.get("brightness", 0.25)), 0.0, 1.0)
	var count: int = maxi(1, int(SAMPLE_RATE * duration / 1000.0))
	var attack_count: int = maxi(1, int(SAMPLE_RATE * clampf(float(config.get("attack_ms", 5.0)), 1.0, 30.0) / 1000.0))
	var release_count: int = maxi(1, int(SAMPLE_RATE * clampf(float(config.get("release_ms", 30.0)), 2.0, 100.0) / 1000.0))
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	for i in range(count):
		var phase: float = TAU * frequency * float(i) / float(SAMPLE_RATE)
		var fundamental: float = sin(phase)
		var triangle: float = 2.0 / PI * asin(sin(phase))
		# 有限谐波避免直接锯齿/方波的高频混叠；尖锐度由 brightness 控制。
		var harmonics: float = 0.0
		for harmonic in range(2, 9):
			harmonics += sin(phase * harmonic) / float(harmonic)
		var sample: float = 0.0
		match tone:
			"warm": sample = fundamental * (0.90 - brightness * 0.35) + triangle * (0.10 + brightness * 0.35)
			"clear": sample = fundamental * (0.70 - brightness * 0.25) + triangle * 0.25 + sin(phase * 2.0) * (0.05 + brightness * 0.25)
			"sharp", "saw": sample = fundamental * 0.55 + harmonics * (0.15 + brightness * 0.30)
			"chime": sample = fundamental * 0.65 + sin(phase * 2.0) * (0.20 + brightness * 0.10) + sin(phase * 3.0) * 0.15
			"square": sample = fundamental * 0.7 + sin(phase * 3.0) * 0.23 + sin(phase * 5.0) * 0.14
			"noise": sample = randf_range(-0.5, 0.5)
			_: sample = fundamental
		var envelope: float = minf(1.0, float(i) / float(attack_count))
		envelope *= minf(1.0, float(count - 1 - i) / float(release_count))
		pcm.encode_s16(i * 2, clampi(int(sample * envelope * 0.40 * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.data = pcm
	return wav

func cleanup() -> void:
	_sample = null
	if _audio_player and is_instance_valid(_audio_player):
		_audio_player.stop()
		_audio_player.queue_free()
	_audio_player = null
