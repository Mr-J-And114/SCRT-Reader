extends Node
## 封面独立 CW 背景声：采样级点划时序、柔和起落、每遍前等待两分钟。
## 仅复用编码表，不初始化无线电或剧情系统。

const SAMPLE_RATE := 22050.0
const MESSAGE := "READER CORE READY"
const CAESAR_SHIFT := 7
const MESSAGE_DELAY := 120.0
const CODE := preload("res://scripts/morse_engine.gd").MORSE_ENCODE

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _segments: Array[Vector2] = [] # x=持续采样数；y=是否发声
var _segment_index: int = 0
var _segment_frame: int = 0
var _wpm: float = 0.0
var _frequency: float = 550.0
var _volume: float = 0.08
var _minimum: float = 0.55
var _swell_period: float = 24.0
var _phase: float = 0.0
var _clock: float = 0.0
var _active: bool = true

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = SAMPLE_RATE
	stream.buffer_length = 0.3
	_player.stream = stream
	add_child(_player)
	set_process(false) # 由封面统一推进，隐藏／开机时暂停。

static func encrypted_message() -> String:
	var result: String = ""
	for letter in MESSAGE.to_upper():
		var code: int = letter.unicode_at(0)
		result += String.chr(65 + (code - 65 + CAESAR_SHIFT) % 26) if code >= 65 and code <= 90 else letter
	return result

func configure(layout: Dictionary) -> void:
	_frequency = clampf(float(layout.get("morse_frequency", 550.0)), 100.0, 1500.0)
	_volume = clampf(float(layout.get("morse_volume", 8.0)) / 100.0, 0.0, 1.0)
	_volume *= clampf(float(layout.get("audio_ambient_gain", 1.0)), 0.0, 1.0)
	_minimum = clampf(float(layout.get("morse_min_volume", 55.0)) / 100.0, 0.25, 1.0)
	_swell_period = maxf(4.0, float(layout.get("morse_swell_period", 24.0)))
	var wpm: float = clampf(float(layout.get("morse_wpm", 6.0)), 2.0, 20.0)
	if not is_equal_approx(wpm, _wpm):
		var progress: float = float(_segment_frame) / _segments[_segment_index].x if not _segments.is_empty() else 0.0
		_wpm = wpm
		_build_timeline()
		# 调速保留当前点划及其相对进度；音量／频率调整不重启报文。
		_segment_frame = mini(roundi(progress * _segments[_segment_index].x), int(_segments[_segment_index].x) - 1)
	_sync_playback()

func set_active(active: bool) -> void:
	_active = active
	_sync_playback()

func _sync_playback() -> void:
	if _player == null or _segments.is_empty():
		return
	if not _player.playing:
		_player.play()
		_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	_player.stream_paused = not _active or _volume <= 0.0
	if _active and _volume > 0.0:
		advance()

func _build_timeline() -> void:
	_segments.clear()
	# 首次进入及每遍报文结束共用这一段静音，不受 WPM 调整影响。
	_segments.append(Vector2(roundf(SAMPLE_RATE * MESSAGE_DELAY), 0.0))
	var unit: float = SAMPLE_RATE * 1.2 / _wpm
	var words: PackedStringArray = encrypted_message().split(" ", false)
	for word_index in range(words.size()):
		var word: String = words[word_index]
		for index in range(word.length()):
			var symbols: String = str(CODE[word[index]])
			for symbol_index in range(symbols.length()):
				_segments.append(Vector2(roundf(unit * (3.0 if symbols[symbol_index] == "-" else 1.0)), 1.0))
				if symbol_index < symbols.length() - 1:
					_segments.append(Vector2(roundf(unit), 0.0))
			if index < word.length() - 1:
				_segments.append(Vector2(roundf(unit * 3.0), 0.0))
			elif word_index < words.size() - 1:
				_segments.append(Vector2(roundf(unit * 7.0), 0.0))
	# 最后一个划／点结束直接回到 120 秒等待，不额外叠加单词间隔。

func advance() -> void:
	if not _active or _volume <= 0.0 or _playback == null or _segments.is_empty():
		return
	var frames: int = _playback.get_frames_available()
	if frames <= 0:
		return
	var buffer := PackedVector2Array()
	buffer.resize(frames)
	for index in range(frames):
		var segment: Vector2 = _segments[_segment_index]
		var length: int = int(segment.x)
		var edge: float = minf(SAMPLE_RATE * 0.02, segment.x * 0.2)
		var gate: float = smoothstep(0.0, edge, float(_segment_frame)) * smoothstep(0.0, edge, float(length - 1 - _segment_frame)) if segment.y > 0.0 else 0.0
		var swell: float = lerpf(_minimum, 1.0, 0.5 + 0.5 * sin(TAU * _clock / _swell_period))
		var sample: float = sin(_phase) * 0.6 * _volume * swell * gate
		buffer[index] = Vector2(sample, sample * 0.97)
		_phase = fposmod(_phase + TAU * _frequency / SAMPLE_RATE, TAU)
		_clock += 1.0 / SAMPLE_RATE
		_segment_frame += 1
		if _segment_frame >= length:
			_segment_frame = 0
			_segment_index = (_segment_index + 1) % _segments.size()
	_playback.push_buffer(buffer)
