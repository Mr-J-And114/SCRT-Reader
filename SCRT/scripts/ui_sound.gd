# ============================================================
# ui_sound.gd - 操作音效体系
# 职责：为终端操作提供沉浸式音效反馈
#
# 音效类型：
#   - keystroke    键盘敲击（每次输入字符时）
#   - enter        回车确认（提交命令时）
#   - backspace    退格删除
#   - error        错误反馈（未知命令、权限不足等）
#   - success      成功反馈（解锁、登录等）
#   - boot_hum     开机电流嗡鸣
#   - hdd_read     硬盘读取音（打开文件时）
#   - hdd_seek     磁头寻道音（切换目录时）
#   - click        UI 点击（Tab补全、菜单操作）
#   - beep         系统提示音（邮件到达等）
#
# 所有音效通过 AudioStreamGenerator 程序化合成，
# 无需外部音频文件，保持极简部署。
# ============================================================
class_name UiSound
extends RefCounted

# ── 音频播放器池 ──
var _players: Array[AudioStreamPlayer] = []
const POOL_SIZE: int = 6  # 同时播放的最大音效数
var _pool_index: int = 0

# ── 主引用 ──
var _tree: SceneTree = null
var _root: Node = null

# ── 开关 ──
var enabled: bool = true
var volume_db: float = -12.0  # 默认较低音量，不干扰主内容

# ── 采样率 ──
const SAMPLE_RATE: float = 22050.0

# ============================================================
# 初始化
# ============================================================
func setup(scene_tree: SceneTree) -> void:
	_tree = scene_tree
	_root = scene_tree.root
	# 创建播放器池
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		player.volume_db = volume_db
		_root.add_child.call_deferred(player)
		_players.append(player)

func set_enabled(val: bool) -> void:
	enabled = val

func set_volume(linear: float) -> void:
	volume_db = linear_to_db(clampf(linear, 0.01, 1.0))
	for p in _players:
		p.volume_db = volume_db

# ============================================================
# 播放器池管理
# ============================================================
func _get_player() -> AudioStreamPlayer:
	# 轮询获取下一个播放器
	var player: AudioStreamPlayer = _players[_pool_index]
	_pool_index = (_pool_index + 1) % POOL_SIZE
	# 如果正在播放，停止它
	if player.playing:
		player.stop()
	return player

# ============================================================
# 核心：从 PackedFloat32Array 生成 AudioStreamWAV
# ============================================================
func _make_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.mix_rate = int(SAMPLE_RATE)
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	# 转换 float32 -> int16 PCM
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var val: float = clampf(samples[i], -1.0, 1.0)
		var int16_val: int = int(val * 32767.0)
		data[i * 2] = int16_val & 0xFF
		data[i * 2 + 1] = (int16_val >> 8) & 0xFF
	stream.data = data
	return stream

func _play_samples(samples: PackedFloat32Array, vol_offset: float = 0.0) -> void:
	if not enabled or _players.is_empty():
		return
	var player: AudioStreamPlayer = _get_player()
	player.stream = _make_stream(samples)
	player.volume_db = volume_db + vol_offset
	player.play()

# ============================================================
# 音效合成函数
# ============================================================

## 键盘敲击音 —— 短促的白噪声 + 高频衰减
func play_keystroke() -> void:
	var duration: float = 0.025  # 25ms
	var count: int = int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = exp(-t * 180.0)  # 极快衰减
		var noise: float = randf_range(-1.0, 1.0)
		# 混入一点高频正弦，模拟机械键盘的"咔嗒"
		var click: float = sin(t * TAU * 4500.0) * 0.3
		samples[i] = (noise * 0.5 + click) * env * 0.4
	_play_samples(samples, -6.0)

## 回车确认音 —— 略长的低频+中频双音
func play_enter() -> void:
	var duration: float = 0.08
	var count: int = int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = exp(-t * 40.0)
		var tone1: float = sin(t * TAU * 800.0) * 0.4
		var tone2: float = sin(t * TAU * 1200.0) * 0.2
		var noise: float = randf_range(-1.0, 1.0) * 0.1
		samples[i] = (tone1 + tone2 + noise) * env * 0.5
	_play_samples(samples, -3.0)

## 退格音 —— 短促低沉
func play_backspace() -> void:
	var duration: float = 0.02
	var count: int = int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = exp(-t * 200.0)
		var tone: float = sin(t * TAU * 600.0)
		samples[i] = tone * env * 0.3
	_play_samples(samples, -8.0)


## 硬盘读取音 —— 模拟机械硬盘的"嗒嗒"声
func play_hdd_read() -> void:
	var duration: float = 0.35
	var count: int = int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	# 生成3~5次随机间隔的咔嗒声
	var click_count: int = randi_range(3, 5)
	var click_times: Array[float] = []
	for c in range(click_count):
		click_times.append(randf_range(0.0, duration * 0.8))
	click_times.sort()
	for i in range(count):
		var t: float = float(i) / SAMPLE_RATE
		var val: float = 0.0
		for ct in click_times:
			var dt: float = t - ct
			if dt >= 0.0 and dt < 0.012:
				var click_env: float = exp(-dt * 350.0)
				val += (randf_range(-1.0, 1.0) * 0.4 + sin(dt * TAU * 3000.0) * 0.3) * click_env
		# 底层低频嗡声
		val += sin(t * TAU * 120.0) * 0.05 * (1.0 - t / duration)
		samples[i] = clampf(val * 0.5, -1.0, 1.0)
	_play_samples(samples, -3.0)



## UI 点击音
func play_click() -> void:
	var duration: float = 0.015
	var count: int = int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = exp(-t * 250.0)
		samples[i] = sin(t * TAU * 3000.0) * env * 0.3
	_play_samples(samples, -6.0)



## 打字机输出音 —— 用于 typewriter 逐字输出时的微弱点击
func play_typewriter_tick() -> void:
	var duration: float = 0.008  # 8ms 极短
	var count: int = int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = exp(-t * 400.0)
		var tone: float = sin(t * TAU * 2800.0)
		samples[i] = tone * env * 0.15
	_play_samples(samples, -14.0)
