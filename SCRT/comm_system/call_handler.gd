# ============================================================
# call_handler.gd — 呼叫模式处理器
# 管理三种呼叫模式：静默(silent)、强制(forced)、可接听(answerable)
# ── 从 comm_manager.gd 中提取的呼叫生命周期管理
# ============================================================
class_name CallHandler
extends RefCounted

enum CallMode { SILENT, FORCED, ANSWERABLE }
enum CallState { IDLE, RINGING, WAITING_ANSWER }

signal call_accepted(dialogue_id: String)
signal call_rejected(dialogue_id: String)
signal ring_started()
signal ring_ended()

# ══════════════════════════════════════════
#  常量
# ══════════════════════════════════════════
const RING_INTERVAL: float = 3.0         # 每次铃声间隔(秒)
const FORCED_RING_COUNT: int = 2         # 强制呼叫铃声次数
const ANSWERABLE_RING_COUNT: int = 4     # 可接听呼叫铃声次数
const RING_TIMEOUT: float = 30.0         # 可接听呼叫超时(秒)

# ══════════════════════════════════════════
#  依赖
# ══════════════════════════════════════════
var _main = null
var _comm_mgr = null
var _audio_mgr: Node = null
var _T = null
var _tone_gen: DialToneGenerator = null

# ══════════════════════════════════════════
#  状态
# ══════════════════════════════════════════
var state: CallState = CallState.IDLE
var _pending_dialogue_id: String = ""
var _pending_call_mode: CallMode = CallMode.SILENT
var _pending_reject_consequence: String = ""
var _pending_caller_name: String = ""

# 铃声计时
var _ring_timer: float = 0.0
var _ring_count: int = 0
var _max_rings: int = FORCED_RING_COUNT
var _ring_playing: bool = false
var _ring_duration: float = 0.0
var _total_ring_timer: float = 0.0

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(main, comm_mgr, audio_mgr: Node, theme) -> void:
	_main = main
	_comm_mgr = comm_mgr
	_audio_mgr = audio_mgr
	_T = theme
	_tone_gen = DialToneGenerator.new()

# ══════════════════════════════════════════
#  发起呼叫
# ══════════════════════════════════════════

## 发起一次呼叫
## dialogue_id: 对话 ID
## call_mode: 呼叫模式
## reject_consequence: 拒接后果描述(仅 ANSWERABLE 模式)
## caller_name: 来电者名字(显示用)
func initiate_call(dialogue_id: String, call_mode: CallMode,
		reject_consequence: String = "", caller_name: String = "") -> void:
	if state != CallState.IDLE:
		push_warning("[CallHandler] 已有呼叫进行中，忽略: %s" % dialogue_id)
		return

	_pending_dialogue_id = dialogue_id
	_pending_call_mode = call_mode
	_pending_reject_consequence = reject_consequence
	_pending_caller_name = caller_name

	match call_mode:
		CallMode.SILENT:
			# 静默模式：直接接通
			_accept_immediately()
		CallMode.FORCED:
			# 强制模式：播放铃声后自动接通
			_max_rings = FORCED_RING_COUNT
			_start_ringing()
		CallMode.ANSWERABLE:
			# 可接听模式：播放铃声并等待玩家选择
			_max_rings = ANSWERABLE_RING_COUNT
			_start_ringing()

## 静默模式直接接通
func _accept_immediately() -> void:
	var dlg_id: String = _pending_dialogue_id
	_reset_state()
	call_accepted.emit(dlg_id)

# ══════════════════════════════════════════
#  铃声控制
# ══════════════════════════════════════════

func _start_ringing() -> void:
	state = CallState.RINGING
	_ring_count = 0
	_ring_timer = 0.0
	_total_ring_timer = 0.0
	_ring_playing = false
	ring_started.emit()
	# 立即播放第一次铃声
	_play_ring_once()

func _play_ring_once() -> void:
	_ring_playing = true
	_ring_count += 1
	# 生成来电铃声
	var ring_data: Dictionary = _tone_gen.generate_phone_ring(1)
	_ring_duration = ring_data.get("duration", 1.0)
	_ring_timer = 0.0
	# 播放音频
	if _audio_mgr and ring_data.has("stream"):
		_audio_mgr.play_media(ring_data["stream"])
	# 终端提示
	_show_ring_notification()

func _show_ring_notification() -> void:
	if _main == null:
		return
	var w_hex: String = _T.warning_hex if _T else "#ffff00"
	_main.append_output("[color=%s]RING... (%s)[/color]\n" % [w_hex, _pending_caller_name], false)

# ══════════════════════════════════════════
#  铃声结束处理
# ══════════════════════════════════════════

func _on_ringing_complete() -> void:
	ring_ended.emit()
	match _pending_call_mode:
		CallMode.FORCED:
			_on_forced_ring_complete()
		CallMode.ANSWERABLE:
			_on_answerable_ring_complete()

func _on_forced_ring_complete() -> void:
	# 强制呼叫：铃声结束后自动接通
	var dlg_id: String = _pending_dialogue_id
	_show_forced_connect_message()
	_reset_state()
	call_accepted.emit(dlg_id)

func _on_answerable_ring_complete() -> void:
	# 可接听呼叫：铃声结束后进入等待接听状态
	state = CallState.WAITING_ANSWER
	_show_answer_prompt()

func _show_forced_connect_message() -> void:
	if _main == null:
		return
	var p_hex: String = _T.primary_hex if _T else "#00ff00"
	_main.append_output("[color=%s]CONNECTED -- — %s[/color]\n\n" % [p_hex, _pending_caller_name], false)

func _show_answer_prompt() -> void:
	if _main == null:
		return
	var w_hex: String = _T.warning_hex if _T else "#ffff00"
	var m_hex: String = _T.muted_hex if _T else "#888888"
	var p_hex: String = _T.primary_hex if _T else "#00ff00"
	_main.append_output("\n[color=%s]╔══════════════════════════════════════╗[/color]\n" % w_hex, false)
	_main.append_output("[color=%s]║  INCOMING COMM -- — %s[/color]\n" % [w_hex, _pending_caller_name], false)
	_main.append_output("[color=%s]║  输入 [color=%s]comm answer[/color] 接听[/color]\n" % [m_hex, p_hex], false)
	_main.append_output("[color=%s]║  输入 [color=%s]comm reject[/color] 拒绝[/color]\n" % [m_hex, p_hex], false)
	if not _pending_reject_consequence.is_empty():
		_main.append_output("[color=%s]║  [!] 拒绝可能影响后续剧情[/color]\n" % w_hex, false)
	_main.append_output("[color=%s]╚══════════════════════════════════════╝[/color]\n\n" % w_hex, false)

# ══════════════════════════════════════════
#  玩家操作
# ══════════════════════════════════════════

## 接听来电
func accept_call() -> void:
	if state != CallState.WAITING_ANSWER:
		return
	var dlg_id: String = _pending_dialogue_id
	var p_hex: String = _T.primary_hex if _T else "#00ff00"
	if _main:
		_main.append_output("[color=%s]CONNECTED -- — %s[/color]\n\n" % [p_hex, _pending_caller_name], false)
	_reset_state()
	call_accepted.emit(dlg_id)

## 拒接来电
func reject_call() -> void:
	if state != CallState.WAITING_ANSWER:
		return
	var dlg_id: String = _pending_dialogue_id
	var consequence: String = _pending_reject_consequence
	var m_hex: String = _T.muted_hex if _T else "#888888"
	if _main:
		_main.append_output("[color=%s]REJECTED -- — %s[/color]\n\n" % [m_hex, _pending_caller_name], false)
	_reset_state()
	call_rejected.emit(dlg_id)

## 强制中断（如系统需要取消当前呼叫）
func cancel_call() -> void:
	if state == CallState.IDLE:
		return
	_reset_state()

# ══════════════════════════════════════════
#  每帧更新
# ══════════════════════════════════════════

func process(delta: float) -> void:
	if state == CallState.IDLE:
		return
	if state == CallState.RINGING:
		_process_ringing(delta)
	elif state == CallState.WAITING_ANSWER:
		_total_ring_timer += delta
		# 超时自动拒绝
		if _total_ring_timer >= RING_TIMEOUT:
			var m_hex: String = _T.muted_hex if _T else "#888888"
			if _main:
				_main.append_output("[color=%s]CALL TIMED OUT.[/color]\n\n" % m_hex, false)
			reject_call()

func _process_ringing(delta: float) -> void:
	_total_ring_timer += delta
	if _ring_playing:
		_ring_timer += delta
		if _ring_timer >= _ring_duration + 1.0:  # 铃声 + 间隔
			_ring_playing = false
			_ring_timer = 0.0
			if _ring_count >= _max_rings:
				_on_ringing_complete()
			else:
				_play_ring_once()

# ══════════════════════════════════════════
#  查询接口
# ══════════════════════════════════════════

func is_ringing() -> bool:
	return state == CallState.RINGING

func has_pending_answer() -> bool:
	return state == CallState.WAITING_ANSWER

func is_active() -> bool:
	return state != CallState.IDLE

func get_pending_caller_name() -> String:
	return _pending_caller_name

func get_pending_dialogue_id() -> String:
	return _pending_dialogue_id

func get_pending_reject_consequence() -> String:
	return _pending_reject_consequence

# ══════════════════════════════════════════
#  工具
# ══════════════════════════════════════════

## 解析呼叫模式字符串
static func parse_call_mode(mode_str: String) -> CallMode:
	match mode_str.to_lower().strip_edges():
		"forced": return CallMode.FORCED
		"answerable": return CallMode.ANSWERABLE
		_: return CallMode.SILENT

func _reset_state() -> void:
	state = CallState.IDLE
	_pending_dialogue_id = ""
	_pending_call_mode = CallMode.SILENT
	_pending_reject_consequence = ""
	_pending_caller_name = ""
	_ring_timer = 0.0
	_ring_count = 0
	_ring_playing = false
	_total_ring_timer = 0.0

func cleanup() -> void:
	cancel_call()
