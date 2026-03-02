# dial_manager.gd
class_name DialManager
extends RefCounted

# ══════════════════════════════════════════
#  拨号管理器：号码解析、拨号状态机、语音/窄带流程
# ══════════════════════════════════════════

enum DialState {
	IDLE,
	DTMF_PLAYING,
	RINGING,
	BUSY,
	VOICE_CONNECTING,
	VOICE_ACTIVE,
	MODEM_INIT,
	MODEM_CARRIER,
	MODEM_TRAINING,
	MODEM_NEGOTIATION,
	MODEM_DOWNLOADING,
	MODEM_COMPLETE,
	CALL_ENDED,
}

enum CallType {
	NONE,
	VOICE,
	MODEM,
	INVALID,
}

# ── 模块引用 ──
var main: Control = null
var comm_mgr = null  # CommManager
var audio_manager: Node = null
var T = null
var tone_gen: DialToneGenerator = null

# ── 状态 ──
var state: DialState = DialState.IDLE
var call_type: CallType = CallType.NONE
var _current_number: String = ""
var _resolved_character: String = ""
var _resolved_label: String = ""
var _modem_info: Dictionary = {}  # modem 拨号解析出的信息

# ── 计时器 ──
var _state_timer: float = 0.0
var _state_duration: float = 0.0

# ── DTMF 逐键播放 ──
var _dtmf_keys: Array[String] = []
var _dtmf_index: int = 0
var _dtmf_key_timer: float = 0.0
var _dtmf_key_duration: float = 0.12
var _dtmf_gap_duration: float = 0.06
var _dtmf_dash_duration: float = 0.08
var _dtmf_in_gap: bool = false
var _dtmf_display_text: String = ""

# ── 下载模拟 ──
var _simulated_bytes: float = 0.0
var _simulated_speed: float = 1200.0  # bytes per second
var _total_file_size: float = 0.0
var _download_actually_done: bool = false
var _http_request: HTTPRequest = null
var _download_body: PackedByteArray = PackedByteArray()
var _download_filename: String = ""
var _last_progress_percent: int = -1
var _download_phase_started_audio: bool = false
var _handshake_duration: float = 4.0

# ── modem 文本行输出队列 ──
var _modem_text_queue: Array[String] = []
var _modem_text_timer: float = 0.0
var _modem_text_interval: float = 0.3

# ── 号码簿 ──
# 系统内置语音号码
var _system_voice_directory: Dictionary = {}
# 系统内置 modem 号码
var _system_modem_directory: Dictionary = {}
# 故事包号码（由 disc_manager 注入）
var _story_voice_directory: Dictionary = {}
var _story_modem_directory: Dictionary = {}

# ── 回铃计数 ──
var _ring_count: int = 0
var _ring_max: int = 2
var _ring_phase: int = 0  # 0=tone, 1=silence
var _ring_phase_timer: float = 0.0

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════

func setup(p_main: Control, p_comm_mgr, p_audio_manager: Node, p_theme) -> void:
	main = p_main
	comm_mgr = p_comm_mgr
	audio_manager = p_audio_manager
	T = p_theme
	tone_gen = DialToneGenerator.new()
	# ★ 加载预设下载号码簿
	_load_preset_dial_directory()

## 注册系统内置号码（在 main._ready 或 comm_manager 中调用）
func register_system_voice(number: String, character_id: String, label: String = "") -> void:
	_system_voice_directory[number] = {
		"character": character_id,
		"label": label if not label.is_empty() else character_id,
	}

func register_system_modem(number: String, info: Dictionary) -> void:
	_system_modem_directory[number] = info

## 加载故事包号码（由 disc_manager 解析 manifest 后调用）
func load_story_directory(dial_directory: Dictionary) -> void:
	_story_voice_directory.clear()
	_story_modem_directory.clear()
	if dial_directory.has("voice"):
		var voice_dict: Dictionary = dial_directory["voice"] as Dictionary
		for number in voice_dict:
			_story_voice_directory[str(number)] = voice_dict[number]
	if dial_directory.has("modem"):
		var modem_dict: Dictionary = dial_directory["modem"] as Dictionary
		for number in modem_dict:
			_story_modem_directory[str(number)] = modem_dict[number]

## 清除故事包号码
func clear_story_directory() -> void:
	_story_voice_directory.clear()
	_story_modem_directory.clear()

# ══════════════════════════════════════════
#  号码解析
# ══════════════════════════════════════════

## 判断字符串是否为号码格式（包含数字和连字符，至少有一个数字）
func is_number_format(text: String) -> bool:
	if text.is_empty():
		return false
	var has_digit: bool = false
	for ch in text:
		if ch >= "0" and ch <= "9":
			has_digit = true
		elif ch == "-":
			continue
		else:
			return false
	return has_digit

## 解析号码，返回 { type: CallType, character, label, modem_info }
func resolve_number(number: String) -> Dictionary:
	# 优先级：故事包 > 系统内置
	# 语音号码
	if _story_voice_directory.has(number):
		var info: Dictionary = _story_voice_directory[number]
		return {
			"type": CallType.VOICE,
			"character": str(info.get("character", "")),
			"label": str(info.get("label", "")),
		}
	if _system_voice_directory.has(number):
		var info: Dictionary = _system_voice_directory[number]
		return {
			"type": CallType.VOICE,
			"character": str(info.get("character", "")),
			"label": str(info.get("label", "")),
		}
	# Modem 号码
	if _story_modem_directory.has(number):
		return {
			"type": CallType.MODEM,
			"modem_info": _story_modem_directory[number],
		}
	if _system_modem_directory.has(number):
		return {
			"type": CallType.MODEM,
			"modem_info": _system_modem_directory[number],
		}
	# 未找到
	return {"type": CallType.INVALID}

# ══════════════════════════════════════════
#  拨号入口
# ══════════════════════════════════════════

## 发起拨号（由 comm_manager 或 command_handler 调用）
func dial(number: String) -> void:
	if state != DialState.IDLE:
		_output("[color=" + T.error_hex + "]线路忙，请稍后再试。[/color]\n")
		return

	_current_number = number
	var resolved: Dictionary = resolve_number(number)
	var rtype: CallType = resolved.get("type", CallType.INVALID) as CallType

	match rtype:
		CallType.VOICE:
			call_type = CallType.VOICE
			_resolved_character = str(resolved.get("character", ""))
			_resolved_label = str(resolved.get("label", ""))
			_start_dtmf_sequence(number)
		CallType.MODEM:
			call_type = CallType.MODEM
			_modem_info = resolved.get("modem_info", {}) as Dictionary
			_start_dtmf_sequence(number)
		CallType.INVALID:
			call_type = CallType.INVALID
			_start_dtmf_sequence(number)

## 是否正在拨号/通话中
func is_active() -> bool:
	return state != DialState.IDLE

## 强制中断当前拨号/通话
func abort() -> void:
	if state == DialState.IDLE:
		return
	if _http_request != null and is_instance_valid(_http_request):
		_http_request.cancel_request()
		_http_request.queue_free()
		_http_request = null
	_stop_dial_audio()
	state = DialState.CALL_ENDED
	_state_timer = 0.0
	_state_duration = 0.5
	_output("\n[color=" + T.warning_hex + "]── CALL ABORTED ──[/color]\n")

# ══════════════════════════════════════════
#  DTMF 逐键播放
# ══════════════════════════════════════════
func _start_dtmf_sequence(number: String) -> void:
	_output("\n[color=" + T.primary_hex + "]> DIALING " + number + "...[/color]\n")
	# ★ 不再在这里开一个未闭合的 [color] 标签
	_dtmf_keys.clear()
	for ch in number:
		_dtmf_keys.append(ch)
	_dtmf_index = 0
	_dtmf_key_timer = 0.0
	_dtmf_in_gap = false
	_dtmf_display_text = ""
	state = DialState.DTMF_PLAYING
	_state_timer = 0.0
	# 立即播放第一个键
	_play_current_dtmf_key()


func _play_current_dtmf_key() -> void:
	if _dtmf_index >= _dtmf_keys.size():
		return
	var ch: String = _dtmf_keys[_dtmf_index]
	if ch == "-":
		# 连字符：不播音，仅显示
		_dtmf_display_text += "-"
		_dtmf_key_timer = 0.0
		_dtmf_in_gap = false
		# 设置短暂等待
		_state_duration = _dtmf_dash_duration
	else:
		_dtmf_display_text += ch
		var wav: AudioStreamWAV = tone_gen.generate_dtmf_key(ch, int(_dtmf_key_duration * 1000))
		_play_dial_audio(wav)
		_dtmf_key_timer = 0.0
		_dtmf_in_gap = false
		_state_duration = _dtmf_key_duration


# ══════════════════════════════════════════
#  预设号码簿加载（从 res://data/ 和 scp 包）
# ══════════════════════════════════════════

## 从 res://data/dial_directory.json 加载预设号码
func _load_preset_dial_directory() -> void:
	var path: String = "res://data/dial_directory.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		push_warning("[DialManager] 预设号码簿 JSON 解析失败: " + json.get_error_message())
		return
	file.close()

	var data: Dictionary = json.data as Dictionary
	if data == null:
		return

	# 加载语音号码
	if data.has("voice"):
		var voice_dict: Dictionary = data["voice"] as Dictionary
		for number in voice_dict:
			if not _system_voice_directory.has(str(number)):
				_system_voice_directory[str(number)] = voice_dict[number]
				print("[DialManager] 预设语音号码: ", number)

	# 加载 modem 号码
	if data.has("modem"):
		var modem_dict: Dictionary = data["modem"] as Dictionary
		for number in modem_dict:
			if not _system_modem_directory.has(str(number)):
				_system_modem_directory[str(number)] = modem_dict[number]
				print("[DialManager] 预设Modem号码: ", number)

## 清理拨号系统状态
func cleanup() -> void:
	if state != DialState.IDLE:
		# 清理 HTTP 请求
		if _http_request != null and is_instance_valid(_http_request):
			_http_request.cancel_request()
			_http_request.queue_free()
			_http_request = null
		_stop_dial_audio()
		_reset()
	_story_voice_directory.clear()
	_story_modem_directory.clear()

# ══════════════════════════════════════════
#  每帧驱动（由 main._process 调用）
# ══════════════════════════════════════════

func process(delta: float) -> void:
	if state == DialState.IDLE:
		return

	_state_timer += delta

	match state:
		DialState.DTMF_PLAYING:
			_process_dtmf(delta)
		DialState.RINGING:
			_process_ringing(delta)
		DialState.BUSY:
			_process_busy(delta)
		DialState.VOICE_CONNECTING:
			_process_voice_connecting(delta)
		DialState.VOICE_ACTIVE:
			pass  # 对话由 comm_manager 驱动
		DialState.MODEM_INIT:
			_process_modem_text(delta)
		DialState.MODEM_CARRIER:
			_process_modem_phase(delta)
		DialState.MODEM_TRAINING:
			_process_modem_phase(delta)
		DialState.MODEM_NEGOTIATION:
			_process_modem_phase(delta)
		DialState.MODEM_DOWNLOADING:
			_process_download(delta)
		DialState.MODEM_COMPLETE:
			_process_modem_complete(delta)
		DialState.CALL_ENDED:
			_process_call_ended(delta)

func _process_dtmf(delta: float) -> void:
	# ★ DTMF 完成后等待 timer 期间不再处理
	if _dtmf_index >= _dtmf_keys.size():
		return
	_dtmf_key_timer += delta
	if not _dtmf_in_gap:
		# 等待按键音播完
		if _dtmf_key_timer >= _state_duration:
			# 按键音播完，进入间隔
			_dtmf_in_gap = true
			_dtmf_key_timer = 0.0
	else:
		# 间隔期
		if _dtmf_key_timer >= _dtmf_gap_duration:
			_dtmf_index += 1
			if _dtmf_index >= _dtmf_keys.size():
				# 所有键播完，由 _on_dtmf_complete 统一输出
				_on_dtmf_complete()
				return
			_play_current_dtmf_key()


func _on_dtmf_complete() -> void:
	# ★ 完整闭合的 BBCode 输出拨号序列
	_output("[color=" + T.muted_hex + "]  " + _dtmf_display_text + "[/color]\n\n")
	# DTMF 结束后等 1 秒再进入下一阶段
	_dtmf_index = _dtmf_keys.size()  # 防止 _process_dtmf 重入
	if main and main.get_tree():
		main.get_tree().create_timer(1.0).timeout.connect(func():
			if state != DialState.DTMF_PLAYING:
				return
			match call_type:
				CallType.VOICE:
					_start_ringing_voice()
				CallType.MODEM:
					_start_ringing_modem()
				CallType.INVALID:
					_start_busy()
		)


## ── 回铃（语音）──
func _start_ringing_voice() -> void:
	_output("[color=" + T.muted_hex + "]CONNECTING...[/color]\n")
	state = DialState.RINGING
	_ring_count = 0
	_ring_max = 1 + randi() % 2  # 1~2 次
	_ring_phase = 0
	_ring_phase_timer = 0.0
	_state_timer = 0.0
	# 播放回铃音
	var ring_data: Dictionary = tone_gen.generate_ringback(_ring_max)
	_play_dial_audio(ring_data["stream"])
	_state_duration = ring_data["duration"]

## ── 回铃（modem）──
func _start_ringing_modem() -> void:
	_output("[color=" + T.muted_hex + "]MODEM INITIALIZING...[/color]\n")
	state = DialState.RINGING
	_ring_count = 0
	_ring_max = 1
	_ring_phase = 0
	_ring_phase_timer = 0.0
	_state_timer = 0.0
	var ring_data: Dictionary = tone_gen.generate_ringback(1)
	_play_dial_audio(ring_data["stream"])
	_state_duration = ring_data["duration"]

func _process_ringing(_delta: float) -> void:
	if _state_timer >= _state_duration:
		# 回铃播完
		match call_type:
			CallType.VOICE:
				_enter_voice_connecting()
			CallType.MODEM:
				_enter_modem_init()

## ── 忙音 ──
func _start_busy() -> void:
	state = DialState.BUSY
	_state_timer = 0.0
	var busy_data: Dictionary = tone_gen.generate_busy_tone(3)
	_play_dial_audio(busy_data["stream"])
	_state_duration = busy_data["duration"]

func _process_busy(_delta: float) -> void:
	if _state_timer >= _state_duration:
		_output("[color=" + T.error_hex + "]── NUMBER NOT IN SERVICE ──[/color]\n\n")
		_enter_call_ended()

## ── 语音接通 ──
func _enter_voice_connecting() -> void:
	state = DialState.VOICE_CONNECTING
	_state_timer = 0.0
	_state_duration = 0.5
	_output("[color=" + T.success_hex + "]── CALL CONNECTED ──[/color]\n")
	if not _resolved_label.is_empty():
		_output("[color=" + T.muted_hex + "]" + _resolved_label + "[/color]\n")
	_output("\n")

func _process_voice_connecting(_delta: float) -> void:
	if _state_timer >= _state_duration:
		# 转交给 comm_manager 启动对话
		state = DialState.VOICE_ACTIVE
		if comm_mgr and _resolved_character != "":
			comm_mgr.start_dialogue_from_dial(_resolved_character)

## 语音对话结束回调（由 comm_manager 在对话框关闭后调用）
func on_voice_call_ended() -> void:
	if state == DialState.VOICE_ACTIVE:
		# 播放挂机音
		if tone_gen:
			var hangup_data: Dictionary = tone_gen.generate_hangup_tone()
			_play_dial_audio(hangup_data["stream"])
		_output("\n[color=" + T.muted_hex + "]── CALL ENDED ──[/color]\n\n")
		_enter_call_ended()


# ══════════════════════════════════════════
#  Modem 握手流程
# ══════════════════════════════════════════

func _enter_modem_init() -> void:
	state = DialState.MODEM_INIT
	_state_timer = 0.0
	_modem_text_queue.clear()
	_modem_text_timer = 0.0
	_modem_text_interval = 0.3
	# AT 命令序列
	_modem_text_queue.append("[color=" + T.primary_hex + "]ATZ[/color]")
	_modem_text_queue.append("[color=" + T.success_hex + "]OK[/color]")
	_modem_text_queue.append("[color=" + T.primary_hex + "]ATDT " + _current_number + "[/color]")
	# 所有文本输出完后进入载波检测
	_state_duration = _modem_text_interval * _modem_text_queue.size() + 0.2

func _process_modem_text(delta: float) -> void:
	_modem_text_timer += delta
	if not _modem_text_queue.is_empty() and _modem_text_timer >= _modem_text_interval:
		_modem_text_timer = 0.0
		var line: String = _modem_text_queue.pop_front()
		_output(line + "\n")
	elif _modem_text_queue.is_empty() and _modem_text_timer >= 0.3:
		_enter_modem_carrier()


func _enter_modem_carrier() -> void:
	state = DialState.MODEM_CARRIER
	_state_timer = 0.0
	_output("\n[color=" + T.warning_hex + "]CARRIER DETECTED[/color]\n")
	# 播放完整握手音，记录时长用于后续衔接
	var handshake_data: Dictionary = tone_gen.generate_modem_handshake()
	_play_dial_audio(handshake_data["stream"])
	_state_duration = handshake_data["duration"]
	_handshake_duration = handshake_data["duration"]  # ★ 记录握手音时长


func _process_modem_phase(delta: float) -> void:
	# 在握手音播放期间，分阶段输出文本
	match state:
		DialState.MODEM_CARRIER:
			if _state_timer >= 1.8:
				_output("[color=" + T.muted_hex + "]TRAINING...[/color]\n")
				state = DialState.MODEM_TRAINING
		DialState.MODEM_TRAINING:
			if _state_timer >= _state_duration * 0.7:
				_output("[color=" + T.muted_hex + "]NEGOTIATING...[/color]\n")
				state = DialState.MODEM_NEGOTIATION
		DialState.MODEM_NEGOTIATION:
			if _state_timer >= _state_duration:
				_enter_modem_downloading()


func _enter_modem_downloading() -> void:
	# ★ 不停止当前音频 — 让握手音自然过渡
	# 握手音播完后会自动停止，数据传输音在握手音结束后开始
	state = DialState.MODEM_DOWNLOADING
	_state_timer = 0.0
	_download_phase_started_audio = false  # ★ 标记是否已开始播放数据音

	var speed_str: String = str(_modem_info.get("speed_display", "9600 bps"))
	var label: String = str(_modem_info.get("label", "远程服务器"))
	_download_filename = str(_modem_info.get("filename", "unknown.scp"))

	# 解析模拟速度
	_simulated_speed = _parse_speed_bps(speed_str)

	_output("\n[color=" + T.success_hex + "]CONNECT " + speed_str + "[/color]\n")
	_output("[color=" + T.muted_hex + "]── CONNECTED TO: " + label + " ──[/color]\n")
	_output("[color=" + T.muted_hex + "]PROTOCOL: ZMODEM[/color]\n")
	_output("[color=" + T.primary_hex + "]RECEIVING: " + _download_filename + "[/color]\n\n")

	# 发起实际 HTTP 下载
	_download_actually_done = false
	_simulated_bytes = 0.0
	_total_file_size = 0.0
	_last_progress_percent = -1
	_download_body = PackedByteArray()

	var url: String = str(_modem_info.get("url", ""))
	if url.is_empty():
		_total_file_size = 51200.0
		_download_actually_done = true
	else:
		_start_http_download(url)


func _parse_speed_bps(speed_str: String) -> float:
	# "9600 bps" → 9600 / 8 = 1200 bytes/sec
	var num_str: String = ""
	for ch in speed_str:
		if ch >= "0" and ch <= "9":
			num_str += ch
		elif ch == " ":
			break
	if num_str.is_empty():
		return 1200.0
	return float(num_str.to_int()) / 8.0

func _start_http_download(url: String) -> void:
	_http_request = HTTPRequest.new()
	main.add_child(_http_request)
	_http_request.request_completed.connect(_on_http_completed)
	var err: Error = _http_request.request(url)
	if err != OK:
		_download_actually_done = true
		_total_file_size = 51200.0  # fallback
		push_warning("[DialManager] HTTP 请求失败: " + str(err))

func _on_http_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_download_actually_done = true
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		_download_body = body
		if _total_file_size <= 0:
			_total_file_size = float(body.size())
	else:
		push_warning("[DialManager] 下载失败: result=" + str(result) + " code=" + str(response_code))
		_download_body = PackedByteArray()
		if _total_file_size <= 0:
			_total_file_size = 51200.0
	# 清理 HTTPRequest 节点
	if _http_request != null and is_instance_valid(_http_request):
		_http_request.queue_free()
		_http_request = null

func _process_download(delta: float) -> void:
	# ★ 握手音播完后开始播放数据传输噪音（持续足够长时间）
	if not _download_phase_started_audio:
		# ★ 基于时间判断握手音是否已播完（比检测音频状态更可靠）
		if _state_timer >= _handshake_duration + 0.1:
			_download_phase_started_audio = true
			# 播放长时间数据传输噪音（120秒足够覆盖任何下载）
			var data_noise: AudioStreamWAV = tone_gen.generate_data_noise(120.0)
			_play_dial_audio(data_noise)

	# 设置文件大小
	if _total_file_size <= 0 and _download_body.size() > 0:
		_total_file_size = float(_download_body.size())
	if _total_file_size <= 0:
		_total_file_size = 51200.0

	_simulated_bytes += _simulated_speed * delta
	var progress: float = clampf(_simulated_bytes / _total_file_size, 0.0, 1.0)
	var percent: int = int(progress * 100.0)

	# ★ 每 10% 更新一次进度（减少输出量）
	if percent != _last_progress_percent and (percent % 10 == 0 or percent >= 100):
		_last_progress_percent = percent
		_update_progress_display(progress)

	# 完成条件
	if progress >= 1.0 and _download_actually_done:
		_enter_modem_complete()


func _update_progress_display(progress: float) -> void:
	var percent: int = int(progress * 100.0)
	var received_kb: String = "%.1f" % (_simulated_bytes / 1024.0)
	var total_kb: String = "%.1f" % (_total_file_size / 1024.0)
	var speed_display: String = "%.1f" % (_simulated_speed / 1024.0) + " KB/s"

	# ★ 紧凑单行格式，每次一行
	if percent >= 100:
		_output("[color=" + T.success_hex + "] " + received_kb + " / " + total_kb + " KB  [100%]  TRANSFER COMPLETE[/color]\n")
	else:
		# 简短的进度指示：用 ▓ 和 ░ 构建 10 格迷你进度条
		var filled: int = int(progress * 10.0)
		var empty_count: int = 10 - filled
		var bar: String = "▓".repeat(filled) + "░".repeat(empty_count)
		_output("[color=" + T.primary_hex + "]  " + bar + "  " + str(percent) + "%  " + received_kb + "/" + total_kb + " KB  " + speed_display + "[/color]\n")


func _enter_modem_complete() -> void:
	# ★ 下载完成，停止数据传输噪音
	_stop_dial_audio()
	state = DialState.MODEM_COMPLETE
	_state_timer = 0.0
	_state_duration = 1.0

	# 保存文件
	var saved_path: String = ""
	if not _download_body.is_empty():
		saved_path = _save_downloaded_file(_download_body, _download_filename)
		_output("\n[color=" + T.success_hex + "]── TRANSFER COMPLETE ──[/color]\n")
		_output("[color=" + T.success_hex + "]FILE SAVED: " + saved_path + "[/color]\n")
	else:
		_output("\n[color=" + T.warning_hex + "]── TRANSFER COMPLETE (模拟) ──[/color]\n")

	_output("[color=" + T.muted_hex + "]── DISCONNECTED ──[/color]\n\n")

	if not _download_filename.is_empty():
		var story_name: String = _download_filename.get_basename()
		_output("[color=" + T.muted_hex + "]输入 'load <NUM>' 加载 " + story_name + " 虚拟磁盘。[/color]\n\n")


func _process_modem_complete(_delta: float) -> void:
	if _state_timer >= _state_duration:
		_enter_call_ended()


func _save_downloaded_file(data: PackedByteArray, filename: String) -> String:
	# ★ 保存到 exe 根目录下的 vdisc/ 文件夹
	# 开发时使用 res://vdisc/，导出后使用 exe 所在目录/vdisc/
	var base_dir: String = ""
	if OS.has_feature("editor"):
		# 编辑器中：使用项目根目录
		base_dir = ProjectSettings.globalize_path("res://")
	else:
		# 导出后：使用 exe 所在目录
		base_dir = OS.get_executable_path().get_base_dir()

	var save_dir: String = base_dir.path_join("vdisc")

	# 确保目录存在
	if not DirAccess.dir_exists_absolute(save_dir):
		var err: Error = DirAccess.make_dir_recursive_absolute(save_dir)
		if err != OK:
			push_warning("[DialManager] 无法创建目录: " + save_dir + " err=" + str(err))
			return "(目录创建失败)"

	var full_path: String = save_dir.path_join(filename)
	var file: FileAccess = FileAccess.open(full_path, FileAccess.WRITE)
	if file:
		file.store_buffer(data)
		file.close()
		print("[DialManager] 文件已保存: " + full_path)
		return "vdisc/" + filename
	else:
		push_warning("[DialManager] 无法保存文件: " + full_path + " err=" + str(FileAccess.get_open_error()))
		return "(保存失败)"

# ══════════════════════════════════════════
#  通话结束
# ══════════════════════════════════════════

func _enter_call_ended() -> void:
	state = DialState.CALL_ENDED
	_state_timer = 0.0
	_state_duration = 0.3

func _process_call_ended(_delta: float) -> void:
	if _state_timer >= _state_duration:
		_reset()

func _reset() -> void:
	state = DialState.IDLE
	call_type = CallType.NONE
	_current_number = ""
	_resolved_character = ""
	_resolved_label = ""
	_modem_info = {}
	_dtmf_keys.clear()
	_dtmf_index = 0
	_simulated_bytes = 0.0
	_total_file_size = 0.0
	_download_actually_done = false
	_download_body = PackedByteArray()
	_download_filename = ""
	_last_progress_percent = -1
	_download_phase_started_audio = false
	_handshake_duration = 4.0
	_modem_text_queue.clear()

# ══════════════════════════════════════════
#  号码簿显示
# ══════════════════════════════════════════

func get_phonebook_text() -> String:
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var s: String = T.success_hex
	var w: String = T.warning_hex

	var lines: Array[String] = []
	lines.append("[color=" + p + "]═══ PHONE DIRECTORY ═══[/color]")

	# 语音号码
	var voice_entries: Array[Dictionary] = []
	for number in _system_voice_directory:
		var info: Dictionary = _system_voice_directory[number]
		voice_entries.append({"number": number, "label": str(info.get("label", "")), "source": ""})
	for number in _story_voice_directory:
		var info: Dictionary = _story_voice_directory[number]
		voice_entries.append({"number": number, "label": str(info.get("label", "")), "source": "[DISC]"})

	if not voice_entries.is_empty():
		lines.append("")
		lines.append("[color=" + s + "]  VOICE CALLS:[/color]")
		for entry in voice_entries:
			var src_tag: String = ""
			if not entry["source"].is_empty():
				src_tag = " [color=" + w + "]" + entry["source"] + "[/color]"
			lines.append("[color=" + p + "]    " + entry["number"] + "[/color]  [color=" + m + "]" + entry["label"] + "[/color]" + src_tag)

	# Modem 号码
	var modem_entries: Array[Dictionary] = []
	for number in _system_modem_directory:
		var info: Dictionary = _system_modem_directory[number]
		modem_entries.append({"number": number, "label": str(info.get("label", "")), "source": ""})
	for number in _story_modem_directory:
		var info: Dictionary = _story_modem_directory[number]
		modem_entries.append({"number": number, "label": str(info.get("label", "")), "source": "[DISC]"})

	if not modem_entries.is_empty():
		lines.append("")
		lines.append("[color=" + w + "]  MODEM LINES:[/color]")
		for entry in modem_entries:
			var src_tag: String = ""
			if not entry["source"].is_empty():
				src_tag = " [color=" + w + "]" + entry["source"] + "[/color]"
			lines.append("[color=" + p + "]    " + entry["number"] + "[/color]  [color=" + m + "]" + entry["label"] + "[/color]" + src_tag)

	if voice_entries.is_empty() and modem_entries.is_empty():
		lines.append("")
		lines.append("[color=" + m + "]  (无可用号码)[/color]")

	lines.append("")
	lines.append("[color=" + p + "]═══════════════════════[/color]")
	return "\n".join(lines) + "\n"



## 获取所有已注册号码（用于 Tab 补全）
func get_all_numbers() -> Array[String]:
	var numbers: Array[String] = []
	for num in _system_voice_directory:
		numbers.append(str(num))
	for num in _system_modem_directory:
		numbers.append(str(num))
	for num in _story_voice_directory:
		if str(num) not in numbers:
			numbers.append(str(num))
	for num in _story_modem_directory:
		if str(num) not in numbers:
			numbers.append(str(num))
	return numbers

# ══════════════════════════════════════════
#  音频播放辅助
# ══════════════════════════════════════════

func _play_dial_audio(stream: AudioStreamWAV) -> void:
	if audio_manager and audio_manager.has_method("play_media"):
		audio_manager.play_media(stream)

func _stop_dial_audio() -> void:
	if audio_manager and audio_manager.has_method("stop_media"):
		audio_manager.stop_media()

# ══════════════════════════════════════════
#  输出辅助
# ══════════════════════════════════════════

func _output(text: String) -> void:
	if main and main.has_method("append_output"):
		main.append_output(text, false, false)
