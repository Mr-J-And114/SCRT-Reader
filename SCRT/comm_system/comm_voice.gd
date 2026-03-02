# ============================================================
# comm_voice.gd — Undertale 风格逐字符语音合成
# 每个字符触发一个短促的合成音
# ============================================================
class_name CommVoice
extends RefCounted

var _audio_player: AudioStreamPlayer = null
var _main_node: Node = null

## 语音配置（由角色提供）
var config: Dictionary = {
	"tone": "sine",
	"base_pitch": 1.0,
	"pitch_variance": 0.15,
	"speed": "normal",
	"char_sound_duration": 50,
	"vowel_pitch_boost": 0.1,
	"punctuation_pause": 200,
}

## 元音集合
const VOWELS: String = "aeiouAEIOUaeiouàáâãäåèéêëìíîïòóôõöùúûü"
const PUNCTUATION: String = ".,!?;:—…"

## 速度映射
var _char_delay: float = 0.04  # 每字符间隔(秒)

# 预生成的音频样本缓存
var _sample_cache: Dictionary = {}

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════

func setup(main_node: Node) -> void:
	_main_node = main_node
	_audio_player = AudioStreamPlayer.new()
	_audio_player.name = "CommVoicePlayer"
	_audio_player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_audio_player.volume_db = -8.0
	_main_node.add_child(_audio_player)

## 应用角色配置
func apply_config(voice_cfg: Dictionary) -> void:
	for key in voice_cfg.keys():
		config[key] = voice_cfg[key]
	# 更新字符延迟
	match str(config.get("speed", "normal")):
		"slow":
			_char_delay = 0.06
		"fast":
			_char_delay = 0.025
		_:
			_char_delay = 0.04
	# 清除缓存，因为配置变了
	_sample_cache.clear()

# ══════════════════════════════════════════
#  发声
# ══════════════════════════════════════════

## 为一个字符发声
func speak_char(ch: String) -> void:
	if ch.strip_edges().is_empty():
		return  # 空格不发声
	if _audio_player == null:
		return

	var pitch: float = float(config.get("base_pitch", 1.0))
	var variance: float = float(config.get("pitch_variance", 0.15))

	# 元音音高提升
	if ch.length() == 1 and VOWELS.contains(ch):
		pitch += float(config.get("vowel_pitch_boost", 0.1))

	# 随机波动
	pitch += randf_range(-variance, variance)
	pitch = clampf(pitch, 0.3, 3.0)

	var stream: AudioStream = _get_or_generate_sample(pitch)
	if stream:
		_audio_player.stream = stream
		_audio_player.pitch_scale = pitch
		_audio_player.play()

## 获取字符延迟（秒）
func get_char_delay() -> float:
	return _char_delay

## 获取标点停顿（秒）
func get_punctuation_pause(ch: String) -> float:
	if ch.length() == 1 and PUNCTUATION.contains(ch):
		return float(config.get("punctuation_pause", 200)) / 1000.0
	return 0.0

## 是否为标点
func is_punctuation(ch: String) -> bool:
	return ch.length() == 1 and PUNCTUATION.contains(ch)

# ══════════════════════════════════════════
#  音频生成
# ══════════════════════════════════════════

## 生成或获取缓存的音频样本
func _get_or_generate_sample(pitch: float) -> AudioStream:
	# 简化的缓存key（量化到0.1精度避免过多缓存）
	var quantized_pitch: float = snapped(pitch, 0.1)
	var cache_key: String = str(config.get("tone", "sine")) + "_" + str(quantized_pitch)

	if _sample_cache.has(cache_key):
		return _sample_cache[cache_key]

	var stream: AudioStream = _generate_tone_sample()
	if stream:
		_sample_cache[cache_key] = stream
	return stream

## 生成合成音样本
func _generate_tone_sample() -> AudioStream:
	var tone_type: String = str(config.get("tone", "sine"))
	var duration_ms: int = int(config.get("char_sound_duration", 50))
	var sample_rate: int = 22050
	var num_samples: int = int(sample_rate * duration_ms / 1000.0)
	var frequency: float = 220.0  # 基础频率，实际通过 pitch_scale 调整

	var data := PackedVector2Array()
	data.resize(num_samples)

	for i in range(num_samples):
		var t: float = float(i) / float(sample_rate)
		var phase: float = t * frequency * TAU
		var sample: float = 0.0

		match tone_type:
			"sine":
				sample = sin(phase)
			"square":
				sample = 1.0 if fmod(phase, TAU) < PI else -1.0
				sample *= 0.5  # 降低音量
			"saw":
				sample = 2.0 * (fmod(phase, TAU) / TAU) - 1.0
				sample *= 0.4
			"noise":
				sample = randf_range(-1.0, 1.0) * 0.3
			_:
				sample = sin(phase)

		# 简单包络：快速 attack + decay
		var env: float = 1.0
		var attack_samples: int = int(num_samples * 0.05)
		var decay_start: int = int(num_samples * 0.3)
		if i < attack_samples:
			env = float(i) / float(attack_samples)
		elif i > decay_start:
			env = 1.0 - (float(i - decay_start) / float(num_samples - decay_start))
		sample *= env * 0.6  # 总音量控制

		data[i] = Vector2(sample, sample)

	# 创建 AudioStreamWAV 不太方便，用 AudioStreamGenerator 的替代方案
	# Godot 4 中可以用 AudioStreamWAV
	var wav := AudioStreamWAV.new()
	wav.mix_rate = sample_rate
	wav.stereo = true
	wav.format = AudioStreamWAV.FORMAT_16_BITS

	# 将 float 样本转为 16-bit PCM
	var pcm_data := PackedByteArray()
	pcm_data.resize(num_samples * 4)  # 16bit stereo = 4 bytes per sample
	for i in range(num_samples):
		var left: int = clampi(int(data[i].x * 32767.0), -32768, 32767)
		var right: int = clampi(int(data[i].y * 32767.0), -32768, 32767)
		pcm_data.encode_s16(i * 4, left)
		pcm_data.encode_s16(i * 4 + 2, right)

	wav.data = pcm_data
	return wav

# ══════════════════════════════════════════
#  清理
# ══════════════════════════════════════════

func cleanup() -> void:
	_sample_cache.clear()
	if _audio_player and is_instance_valid(_audio_player):
		_audio_player.stop()
		_audio_player.queue_free()
