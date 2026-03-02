# ============================================================
# comm_dialogue_player.gd — 对话序列播放器
# 管理逐行推进、等待条件、分支选择
# ── 修改：条件匹配增加前缀支持
# ============================================================
class_name CommDialoguePlayer
extends RefCounted

signal dialogue_started(dialogue_id: String)
signal dialogue_finished(dialogue_id: String)
signal line_started(line_index: int)
signal line_finished(line_index: int)
signal waiting_for_condition(condition: String)
signal choice_presented(choices: Array)

var _main = null
var _comm_mgr = null

## 当前对话数据
var current_dialogue_id: String = ""
var current_lines: Array = []
var current_line_index: int = -1
var is_active: bool = false
var is_skippable: bool = true

## 当前行状态
var _typing_active: bool = false
var _waiting: bool = false
var _wait_condition: String = ""
var _auto_next_timer: float = -1.0
var _click_to_continue: bool = false

## 文本显示
var _full_text: String = ""
var _displayed_chars: int = 0
var _char_timer: float = 0.0
var _typing_speed: float = 0.04
var _pause_timer: float = 0.0

## 变量替换
var _variables: Dictionary = {}

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(main, comm_mgr) -> void:
	_main = main
	_comm_mgr = comm_mgr

# ══════════════════════════════════════════
#  播放控制
# ══════════════════════════════════════════

## 开始一个对话序列
func start_dialogue(dialogue_id: String, dialogue_data: Dictionary) -> void:
	if is_active:
		stop_dialogue()
	current_dialogue_id = dialogue_id
	current_lines = dialogue_data.get("lines", []) as Array
	is_skippable = dialogue_data.get("skippable", true)
	current_line_index = -1
	is_active = true

	_variables = {
		"username": _main.user_mgr.get_username() if _main and _main.user_mgr and _main.user_mgr.is_logged_in else "Operator",
	}

	dialogue_started.emit(dialogue_id)
	advance()


## 停止对话（silent=true 时不发出 finished 信号，用于对话切换）
func stop_dialogue(silent: bool = false) -> void:
	if not is_active:
		return
	_typing_active = false
	_waiting = false
	_click_to_continue = false
	is_active = false
	var did: String = current_dialogue_id
	current_dialogue_id = ""
	current_lines = []
	current_line_index = -1
	if not silent:
		dialogue_finished.emit(did)

## 推进到下一行
func advance() -> void:
	if not is_active:
		return
	_typing_active = false
	_waiting = false
	_click_to_continue = false
	_auto_next_timer = -1.0
	current_line_index += 1
	if current_line_index >= current_lines.size():
		stop_dialogue()
		return
	_play_current_line()

## 跳过当前行的打字效果
func skip_typing() -> void:
	if _typing_active:
		_typing_active = false
		_displayed_chars = _full_text.length()
		line_finished.emit(current_line_index)
		_check_line_end_behavior()

## 用户点击继续
func on_click() -> void:
	if _typing_active:
		skip_typing()
		return
	if _click_to_continue:
		_click_to_continue = false
		advance()

# ══════════════════════════════════════════
#  内部逻辑
# ══════════════════════════════════════════
func _play_current_line() -> void:
	var line: Dictionary = current_lines[current_line_index] as Dictionary

	var char_id: String = str(line.get("character", ""))
	var expression: String = str(line.get("expression", ""))
	var action: String = str(line.get("action", ""))
	var text: String = str(line.get("text", ""))
	text = _replace_variables(text)

	line_started.emit(current_line_index)

	if _comm_mgr:
		if not char_id.is_empty():
			_comm_mgr._set_active_character(char_id)
		if not expression.is_empty():
			_comm_mgr._set_expression(expression)
		if not action.is_empty():
			_comm_mgr._play_action(action)

	# 屏幕效果
	var screen_effect: String = str(line.get("screen_effect", ""))
	if not screen_effect.is_empty() and _main:
		_trigger_screen_effect(screen_effect)

	# 音效
	var sound: String = str(line.get("sound", ""))
	if not sound.is_empty():
		_play_sound(sound)

	# 开始逐字显示
	_full_text = text
	_displayed_chars = 0
	_typing_active = true
	_char_timer = 0.0
	_pause_timer = 0.0

	if _comm_mgr:
		_comm_mgr._start_speaking()

## 检查行结束后的行为
func _check_line_end_behavior() -> void:
	var line: Dictionary = current_lines[current_line_index] as Dictionary

	if _comm_mgr:
		_comm_mgr._stop_speaking()

	# 检查 wait_for
	var wait_for: String = str(line.get("wait_for", ""))
	if not wait_for.is_empty():
		_start_waiting(wait_for)
		return

	# 检查 choice
	var choices: Array = line.get("choice", []) as Array
	if not choices.is_empty():
		choice_presented.emit(choices)
		_waiting = true
		return

	# 检查 auto_next
	var auto_next = line.get("auto_next", null)
	if auto_next != null:
		_auto_next_timer = float(auto_next)
		return

	# 默认：等待点击
	_click_to_continue = true

## 开始等待条件
func _start_waiting(condition: String) -> void:
	_waiting = true
	_wait_condition = condition
	waiting_for_condition.emit(condition)

## 条件满足时调用（由 comm_manager 转发）
## ── 增加前缀匹配：wait_for="command:disc" 可被 "command:disc list" 满足
func notify_condition_met(condition: String) -> void:
	if not _waiting or _wait_condition.is_empty():
		return

	var matched: bool = false

	# 精确匹配
	if condition == _wait_condition:
		matched = true
	# 前缀匹配：通知的条件以等待条件为前缀
	# 例如 wait="command:disc", notify="command:disc list" → 匹配
	elif condition.begins_with(_wait_condition):
		# 确保前缀后面是空格或字符串结束（避免 "command:discover" 匹配 "command:disc"）
		var remainder: String = condition.substr(_wait_condition.length())
		if remainder.is_empty() or remainder.begins_with(" "):
			matched = true

	if matched:
		_waiting = false
		_wait_condition = ""
		advance()

## 替换变量
func _replace_variables(text: String) -> String:
	for key in _variables.keys():
		text = text.replace("{" + key + "}", str(_variables[key]))
	return text

## 触发屏幕效果
func _trigger_screen_effect(effect: String) -> void:
	if _main == null:
		return
	match effect:
		"glitch":
			_main.trigger_glitch(0.4, 0.8)
		"shake":
			_main.trigger_shake(0.015, 0.5)
		"noise":
			_main.trigger_noise_burst(0.6, 0.3)
		"blackout":
			_main.trigger_screen_off(1.5)
		"tear":
			_main.trigger_tear(0.08, 0.5)

## 播放音效
func _play_sound(sound_path: String) -> void:
	pass

# ══════════════════════════════════════════
#  每帧更新
# ══════════════════════════════════════════
func process(delta: float) -> void:
	if not is_active:
		return
	if _typing_active:
		_process_typing(delta)
	if _auto_next_timer > 0.0:
		_auto_next_timer -= delta
		if _auto_next_timer <= 0.0:
			advance()

func _process_typing(delta: float) -> void:
	if _pause_timer > 0.0:
		_pause_timer -= delta
		return
	_char_timer += delta
	if _char_timer < _typing_speed:
		return
	_char_timer = 0.0
	if _displayed_chars < _full_text.length():
		var ch: String = _full_text[_displayed_chars]
		_displayed_chars += 1
		# 跳过 BBCode 标签
		if ch == "[":
			var close_pos: int = _full_text.find("]", _displayed_chars)
			if close_pos >= 0:
				_displayed_chars = close_pos + 1
				return
		# 语音
		if _comm_mgr:
			_comm_mgr._speak_char(ch)
		# 标点停顿
		if _comm_mgr and _comm_mgr._voice:
			_pause_timer = _comm_mgr._voice.get_punctuation_pause(ch)
	if _displayed_chars >= _full_text.length():
		_typing_active = false
		line_finished.emit(current_line_index)
		_check_line_end_behavior()

# ══════════════════════════════════════════
#  查询
# ══════════════════════════════════════════
func get_displayed_text() -> String:
	if _full_text.is_empty():
		return ""
	if _displayed_chars >= _full_text.length():
		return _full_text
	return _full_text.substr(0, _displayed_chars)

func get_full_text() -> String:
	return _full_text

func get_current_line_data() -> Dictionary:
	if current_line_index >= 0 and current_line_index < current_lines.size():
		return current_lines[current_line_index]
	return {}

func is_waiting_for_input() -> bool:
	return _click_to_continue or _waiting
