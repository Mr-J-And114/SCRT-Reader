# audio_manager.gd - 音频管理器
# 负责：环境音播放、音效播放、媒体播放、音量控制、淡入淡出、Ducking
# ============================================================
extends Node

# ============================================================
#  节点引用（会在 _ready 中动态创建）
# ============================================================
var ambient_player: AudioStreamPlayer = null    # 环境音通道
var ambient_player_b: AudioStreamPlayer = null  # 环境音交叉淡入淡出用的第二通道
var sfx_player: AudioStreamPlayer = null        # 音效通道
var media_player: AudioStreamPlayer = null      # 媒体播放通道（音频/视频）

# ============================================================
#  音量设置（单位：dB）
# ============================================================
var master_volume_db: float = 0.0         # 主音量
var ambient_volume_db: float = 0.0        # 环境音音量
var sfx_volume_db: float = 0.0            # 音效音量
var media_volume_db: float = 0.0          # 媒体音量

# ============================================================
#  环境音状态
# ============================================================
var current_ambient_id: String = "" # 当前播放的环境音标识
var ambient_active_player: int = 0 # 0 = player_a, 1 = player_b（交叉淡入淡出用）
var _ambient_base_volume_db: float = 0.0   # 环境音基础音量（淡入目标值）
var _ambient_override_db: float = 0.0   # manifest 中指定的环境音音量覆盖值

# ============================================================
#  Ducking 状态（播放媒体时自动降低环境音量）
# ============================================================
var ducking_active: bool = false
var ducking_amount_db: float = -12.0       # ducking 时降低多少 dB
var _ducking_tween: Tween = null

# ============================================================
#  淡入淡出 Tween 引用
# ============================================================
var _ambient_fade_tween_a: Tween = null
var _ambient_fade_tween_b: Tween = null

# ============================================================
#  预加载的音效资源
# ============================================================
var beep_stream: AudioStream = null          # 蜂鸣音效

# ============================================================
#  音效参数控制（用于调节失真感等）
# ============================================================
## beep 音调基准值。1.0 = 原始音调
var beep_pitch_base: float = 1.0
## beep 音调随机偏移范围（每次播放在 base ± variation 之间随机，模拟硬件不稳定）
var beep_pitch_variation: float = 0.05
## beep 音量偏移（dB），可用于整体调大/调小蜂鸣
var beep_volume_offset_db: float = -20.0
## beep 音量随机偏移范围（dB）
var beep_volume_variation_db: float = 1.5

# ============================================================
#  频谱分析器缓存（供 Oscilloscope 使用）
# ============================================================
var _spectrum_bus_idx: int = -1
var _spectrum_effect_idx: int = -1

# ============================================================
#  信号
# ============================================================
signal ambient_started(ambient_id: String)
signal ambient_stopped()
signal media_playback_finished()

# ============================================================
#  生命周期
# ============================================================
func _ready() -> void:
	_create_players()
	_preload_sfx()
	_ensure_spectrum_analyzer()
	_ensure_audio_capture()
	print("[AudioManager] 音频管理器初始化完成")

## 动态创建 AudioStreamPlayer 子节点
func _create_players() -> void:
	# --- 环境音通道 A ---
	ambient_player = AudioStreamPlayer.new()
	ambient_player.name = "AmbientPlayerA"
	ambient_player.bus = "Master"
	ambient_player.volume_db = -80.0  # 初始静音
	add_child(ambient_player)

	# --- 环境音通道 B（用于交叉淡入淡出）---
	ambient_player_b = AudioStreamPlayer.new()
	ambient_player_b.name = "AmbientPlayerB"
	ambient_player_b.bus = "Master"
	ambient_player_b.volume_db = -80.0
	add_child(ambient_player_b)

	# --- 音效通道 ---
	sfx_player = AudioStreamPlayer.new()
	sfx_player.name = "SFXPlayer"
	sfx_player.bus = "Master"
	sfx_player.volume_db = 0.0
	add_child(sfx_player)

	# --- 媒体播放通道 ---
	media_player = AudioStreamPlayer.new()
	media_player.name = "MediaPlayer"
	media_player.bus = "Master"
	media_player.volume_db = 0.0
	add_child(media_player)
	media_player.finished.connect(_on_media_finished)

## 预加载内置音效资源
func _preload_sfx() -> void:
	# 加载蜂鸣音效
	if ResourceLoader.exists("res://audio/beep.mp3"):
		beep_stream = load("res://audio/beep.mp3")
		print("[AudioManager] 蜂鸣音效已加载")
	else:
		push_warning("[AudioManager] 未找到 res://audio/beep.mp3")

## 确保 Master 总线上有 SpectrumAnalyzer 效果
func _ensure_spectrum_analyzer() -> void:
	var bus_idx: int = AudioServer.get_bus_index("Master")
	if bus_idx == -1:
		push_warning("[AudioManager] 找不到 Master 音频总线")
		return

	_spectrum_bus_idx = bus_idx

	# 查找已有的 SpectrumAnalyzer
	for i in range(AudioServer.get_bus_effect_count(bus_idx)):
		var effect = AudioServer.get_bus_effect(bus_idx, i)
		if effect is AudioEffectSpectrumAnalyzer:
			_spectrum_effect_idx = i
			print("[AudioManager] 已找到 SpectrumAnalyzer 效果（索引: ", i, "）")
			return

	# 没有则添加
	var analyzer := AudioEffectSpectrumAnalyzer.new()
	analyzer.buffer_length = 0.1
	analyzer.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
	AudioServer.add_bus_effect(bus_idx, analyzer)
	_spectrum_effect_idx = AudioServer.get_bus_effect_count(bus_idx) - 1
	print("[AudioManager] SpectrumAnalyzer 已添加到 Master 总线（索引: ", _spectrum_effect_idx, "）")

## 确保 Master 总线上有 AudioEffectCapture
func _ensure_audio_capture() -> void:
	var bus_idx: int = AudioServer.get_bus_index("Master")
	if bus_idx == -1:
		return

	for i in range(AudioServer.get_bus_effect_count(bus_idx)):
		var effect = AudioServer.get_bus_effect(bus_idx, i)
		if effect is AudioEffectCapture:
			print("[AudioManager] 已找到 AudioEffectCapture 效果（索引: ", i, "）")
			return

	var capture := AudioEffectCapture.new()
	capture.buffer_length = 0.1
	AudioServer.add_bus_effect(bus_idx, capture)
	print("[AudioManager] AudioEffectCapture 已添加到 Master 总线")

## 获取频谱分析器实例（每次调用都重新从 AudioServer 获取，确保引用有效）
func get_spectrum_analyzer_instance() -> AudioEffectSpectrumAnalyzerInstance:
	if _spectrum_bus_idx == -1 or _spectrum_effect_idx == -1:
		_ensure_spectrum_analyzer()
	if _spectrum_bus_idx == -1 or _spectrum_effect_idx == -1:
		return null
	return AudioServer.get_bus_effect_instance(_spectrum_bus_idx, _spectrum_effect_idx)

## 获取音频捕获效果实例（用于李萨如模式）
func get_audio_capture_instance() -> AudioEffectCapture:
	var bus_idx: int = AudioServer.get_bus_index("Master")
	if bus_idx == -1:
		return null
	for i in range(AudioServer.get_bus_effect_count(bus_idx)):
		var effect = AudioServer.get_bus_effect(bus_idx, i)
		if effect is AudioEffectCapture:
			return effect as AudioEffectCapture
	return null

## 播放蜂鸣音效（带随机失真）
## 每次播放时音调和音量会有微小随机变化，模拟老旧硬件的不稳定感
func play_beep() -> void:
	if beep_stream == null:
		return
	# 如果上一次 beep 还没播完，不打断（避免迟滞感）
	if sfx_player.playing:
		return

	sfx_player.stream = beep_stream

	# — 音调随机化 —
	var pitch: float = beep_pitch_base + randf_range(-beep_pitch_variation, beep_pitch_variation)
	sfx_player.pitch_scale = pitch

	# — 音量随机化 —
	var vol_offset: float = beep_volume_offset_db + randf_range(-beep_volume_variation_db, beep_volume_variation_db)
	sfx_player.volume_db = sfx_volume_db + master_volume_db + vol_offset
	sfx_player.play()

# ============================================================
#  环境音控制
# ============================================================

## 播放环境音
## ambient_id: 环境音的唯一标识（通常是文件路径）
## stream: 已加载的 AudioStream 资源
## fade_in_duration: 淡入时间（秒）
## loop: 是否循环（默认 true）
func play_ambient(ambient_id: String, stream: AudioStream, volume_override_db: float = 0.0, fade_in_duration: float = 1.5, loop: bool = true) -> void:
	if stream == null:
		push_warning("[AudioManager] play_ambient: stream 为 null，忽略")
		return

	# 如果已经在播放相同的环境音，不重复播放
	if ambient_id == current_ambient_id and _get_active_ambient_player().playing:
		return

	# 保存 manifest 指定的音量覆盖值
	_ambient_override_db = volume_override_db

	# 设置循环
	_set_stream_loop(stream, loop)

	# 如果当前有环境音在播放，做交叉淡入淡出
	if current_ambient_id != "" and _get_active_ambient_player().playing:
		_crossfade_ambient(stream, fade_in_duration)
	else:
		_fade_in_ambient(stream, fade_in_duration)

	current_ambient_id = ambient_id
	ambient_started.emit(ambient_id)
	print("[AudioManager] 环境音开始播放: ", ambient_id, " 音量覆盖: ", volume_override_db, "dB")

## 停止环境音
## fade_out_duration: 淡出时间（秒）
func stop_ambient(fade_out_duration: float = 1.5) -> void:
	if current_ambient_id == "":
		return

	var player: AudioStreamPlayer = _get_active_ambient_player()
	if player.playing:
		_fade_out_player(player, fade_out_duration)

	current_ambient_id = ""
	_ambient_override_db = 0.0
	ambient_stopped.emit()
	print("[AudioManager] 环境音停止")

## 检查是否有环境音在播放
func is_ambient_playing() -> bool:
	return current_ambient_id != "" and _get_active_ambient_player().playing

# ============================================================
#  音效控制
# ============================================================

## 播放一次性音效
func play_sfx(stream: AudioStream, volume_offset_db: float = 0.0) -> void:
	if stream == null:
		return
	sfx_player.stream = stream
	sfx_player.volume_db = sfx_volume_db + master_volume_db + volume_offset_db
	sfx_player.play()

# ============================================================
#  媒体播放控制（用于音频播放器界面）
# ============================================================

## 播放媒体音频
func play_media(stream: AudioStream) -> void:
	if stream == null:
		push_warning("[AudioManager] play_media: stream 为 null")
		return

	# 确保媒体播放不循环
	_set_stream_loop(stream, false)

	media_player.stream = stream
	media_player.volume_db = media_volume_db + master_volume_db
	media_player.play()
	_duck_ambient(true)

## 暂停/恢复媒体
func pause_media() -> void:
	media_player.stream_paused = !media_player.stream_paused

## 媒体是否暂停
func is_media_paused() -> bool:
	return media_player.stream_paused

## 媒体是否正在播放
func is_media_playing() -> bool:
	return media_player.playing

## 停止媒体
func stop_media() -> void:
	media_player.stop()
	_duck_ambient(false)

## 获取媒体播放位置（秒）
func get_media_playback_position() -> float:
	return media_player.get_playback_position()

## 获取媒体总时长（秒）
func get_media_length() -> float:
	if media_player.stream:
		return media_player.stream.get_length()
	return 0.0

## 跳转媒体播放位置
func seek_media(position: float) -> void:
	media_player.seek(position)

## 媒体播放完成回调
func _on_media_finished() -> void:
	_duck_ambient(false)
	media_playback_finished.emit()

# ============================================================
#  音量调节
# ============================================================

## 设置主音量（0.0 ~ 1.0 线性值）
func set_master_volume(linear: float) -> void:
	master_volume_db = linear_to_db(clampf(linear, 0.001, 1.0))
	_update_all_volumes()

## 设置环境音音量（0.0 ~ 1.0）
func set_ambient_volume(linear: float) -> void:
	ambient_volume_db = linear_to_db(clampf(linear, 0.001, 1.0))
	_ambient_base_volume_db = ambient_volume_db
	_update_ambient_volume()

## 设置音效音量（0.0 ~ 1.0）
func set_sfx_volume(linear: float) -> void:
	sfx_volume_db = linear_to_db(clampf(linear, 0.001, 1.0))

## 设置媒体音量（0.0 ~ 1.0）
func set_media_volume(linear: float) -> void:
	media_volume_db = linear_to_db(clampf(linear, 0.001, 1.0))
	if media_player:
		media_player.volume_db = media_volume_db + master_volume_db

## 更新所有通道音量
func _update_all_volumes() -> void:
	_update_ambient_volume()
	if sfx_player:
		sfx_player.volume_db = sfx_volume_db + master_volume_db
	if media_player:
		media_player.volume_db = media_volume_db + master_volume_db

## 计算环境音的目标音量（综合：基础 + 主音量 + manifest覆盖 + ducking）
func _get_ambient_target_db() -> float:
	var target_db: float = ambient_volume_db + master_volume_db + _ambient_override_db
	if ducking_active:
		target_db += ducking_amount_db
	return target_db

## 更新环境音音量（考虑 ducking）
func _update_ambient_volume() -> void:
	var target_db: float = _get_ambient_target_db()
	if ambient_player and ambient_player.playing:
		ambient_player.volume_db = target_db
	if ambient_player_b and ambient_player_b.playing:
		ambient_player_b.volume_db = target_db

# ============================================================
#  Ducking 控制（媒体播放时降低环境音量）
# ============================================================
func _duck_ambient(duck: bool, duration: float = 0.5) -> void:
	if ducking_active == duck:
		return
	ducking_active = duck

	# 取消之前的 tween
	if _ducking_tween and _ducking_tween.is_valid():
		_ducking_tween.kill()

	var player: AudioStreamPlayer = _get_active_ambient_player()
	if not player.playing:
		return

	var target_db: float = ambient_volume_db + master_volume_db + _ambient_override_db
	if duck:
		target_db += ducking_amount_db

	_ducking_tween = create_tween()
	_ducking_tween.tween_property(player, "volume_db", target_db, duration)

# ============================================================
#  内部辅助函数
# ============================================================

## 获取当前活跃的环境音播放器
func _get_active_ambient_player() -> AudioStreamPlayer:
	if ambient_active_player == 0:
		return ambient_player
	else:
		return ambient_player_b

## 获取备用的环境音播放器（用于交叉淡入淡出）
func _get_inactive_ambient_player() -> AudioStreamPlayer:
	if ambient_active_player == 0:
		return ambient_player_b
	else:
		return ambient_player

## 设置音频流的循环属性
func _set_stream_loop(stream: AudioStream, loop: bool) -> void:
	if stream is AudioStreamOggVorbis:
		stream.loop = loop
	elif stream is AudioStreamWAV:
		if loop:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		else:
			stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif stream is AudioStreamMP3:
		stream.loop = loop

## 直接淡入新环境音（没有旧环境音时使用）
func _fade_in_ambient(stream: AudioStream, duration: float) -> void:
	var player: AudioStreamPlayer = _get_active_ambient_player()

	# 取消之前的淡入 tween
	var tween_ref: Tween = _get_active_fade_tween()
	if tween_ref and tween_ref.is_valid():
		tween_ref.kill()

	player.stream = stream
	player.volume_db = -80.0
	player.play()

	var target_db: float = _get_ambient_target_db()
	var new_tween: Tween = create_tween()
	new_tween.tween_property(player, "volume_db", target_db, duration)
	_set_active_fade_tween(new_tween)

## 交叉淡入淡出（从旧环境音过渡到新环境音）
func _crossfade_ambient(new_stream: AudioStream, duration: float) -> void:
	var old_player: AudioStreamPlayer = _get_active_ambient_player()
	var new_player: AudioStreamPlayer = _get_inactive_ambient_player()

	# 淡出旧的
	_fade_out_player(old_player, duration)

	# 切换活跃播放器
	ambient_active_player = 1 - ambient_active_player

	# 淡入新的
	new_player.stream = new_stream
	new_player.volume_db = -80.0
	new_player.play()

	var target_db: float = _get_ambient_target_db()
	var tween_ref: Tween = _get_active_fade_tween()
	if tween_ref and tween_ref.is_valid():
		tween_ref.kill()

	var new_tween: Tween = create_tween()
	new_tween.tween_property(new_player, "volume_db", target_db, duration)
	_set_active_fade_tween(new_tween)

## 淡出某个播放器
func _fade_out_player(player: AudioStreamPlayer, duration: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(player, "volume_db", -80.0, duration)
	tween.tween_callback(player.stop)

## 获取/设置活跃通道的 fade tween
func _get_active_fade_tween() -> Tween:
	if ambient_active_player == 0:
		return _ambient_fade_tween_a
	else:
		return _ambient_fade_tween_b

func _set_active_fade_tween(t: Tween) -> void:
	if ambient_active_player == 0:
		_ambient_fade_tween_a = t
	else:
		_ambient_fade_tween_b = t

# ============================================================
#  从字节数据加载音频流（用于从 ZIP 虚拟文件系统读取）
# ============================================================

## 从文件字节数据创建 AudioStream
## file_path: 文件路径（用于判断格式）
## data: 文件的原始字节数据
func load_audio_from_bytes(file_path: String, data: PackedByteArray) -> AudioStream:
	if data.is_empty():
		push_warning("[AudioManager] load_audio_from_bytes: 数据为空")
		return null

	var ext: String = file_path.get_extension().to_lower()

	match ext:
		"ogg":
			return _load_ogg_from_bytes(data)
		"wav":
			return _load_wav_from_bytes(data)
		"mp3":
			return _load_mp3_from_bytes(data)
		_:
			push_warning("[AudioManager] 不支持的音频格式: ", ext)
			return null

## 从字节加载 OGG
func _load_ogg_from_bytes(data: PackedByteArray) -> AudioStream:
	var ogg_stream := AudioStreamOggVorbis.load_from_buffer(data)
	if ogg_stream == null:
		push_warning("[AudioManager] 无法解析 OGG 数据")
	else:
		ogg_stream.loop = false
	return ogg_stream

## 从字节加载 WAV
func _load_wav_from_bytes(data: PackedByteArray) -> AudioStream:
	# WAV 格式解析（标准 PCM）
	# WAV 文件结构: RIFF header → fmt chunk → data chunk
	if data.size() < 44:
		push_warning("[AudioManager] WAV 数据太短")
		return null

	# 验证 RIFF 头
	var riff: String = data.slice(0, 4).get_string_from_ascii()
	if riff != "RIFF":
		push_warning("[AudioManager] 无效的 WAV 文件（缺少 RIFF 头）")
		return null

	# 解析 fmt chunk
	var audio_format: int = data.decode_u16(20)
	var channels: int = data.decode_u16(22)
	var sample_rate: int = data.decode_u32(24)
	var bits_per_sample: int = data.decode_u16(34)

	if audio_format != 1:  # 只支持 PCM
		push_warning("[AudioManager] WAV 非 PCM 格式，不支持")
		return null

	# 查找 data chunk
	var data_offset: int = 12
	var audio_data_size: int = 0
	while data_offset < data.size() - 8:
		var chunk_id: String = data.slice(data_offset, data_offset + 4).get_string_from_ascii()
		var chunk_size: int = data.decode_u32(data_offset + 4)
		if chunk_id == "data":
			data_offset += 8
			audio_data_size = chunk_size
			break
		data_offset += 8 + chunk_size

	if audio_data_size == 0:
		push_warning("[AudioManager] WAV 中找不到 data chunk")
		return null

	var audio_data: PackedByteArray = data.slice(data_offset, data_offset + audio_data_size)

	var wav_stream := AudioStreamWAV.new()
	wav_stream.mix_rate = sample_rate
	wav_stream.stereo = (channels == 2)
	wav_stream.data = audio_data

	if bits_per_sample == 8:
		wav_stream.format = AudioStreamWAV.FORMAT_8_BITS
	elif bits_per_sample == 16:
		wav_stream.format = AudioStreamWAV.FORMAT_16_BITS
	else:
		push_warning("[AudioManager] WAV 不支持的位深: ", bits_per_sample)
		return null

	return wav_stream

## 从字节加载 MP3
func _load_mp3_from_bytes(data: PackedByteArray) -> AudioStream:
	var mp3_stream := AudioStreamMP3.new()
	mp3_stream.data = data
	mp3_stream.loop = false
	return mp3_stream
