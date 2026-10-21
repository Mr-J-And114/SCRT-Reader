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
## 选项仍逐字显示，但从第一个选项起不属于 NPC 台词。
var _speech_text_end: int = 0
var _displayed_chars: int = 0
var _char_timer: float = 0.0
var _typing_speed: float = 0.04
var _pause_timer: float = 0.0
## 无标点结尾的最后一个正文字符需保留嘴型，避免同帧开口又闭口。
var _speech_end_remaining: float = 0.0
const SPEECH_END_HOLD_SECONDS: float = 0.08
var _narration: bool = false
const MEETING_TRANSITION_SECONDS: float = 1.4
var _meeting_transition_remaining: float = 0.0
var _meeting_transition_line: int = -1
## 省略号按点显示，独立于角色语速和普通标点停顿。
const ELLIPSIS_DOT_DELAY: float = 0.2

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
	_meeting_transition_remaining = 0.0
	_meeting_transition_line = -1

	_variables = {
		"username": _main.user_mgr.get_username() if _main and _main.user_mgr and _main.user_mgr.is_logged_in else "Operator",
	}

	dialogue_started.emit(dialogue_id)
	advance()


## 停止对话（silent=true 时不发出 finished 信号，用于对话切换）
func stop_dialogue(silent: bool = false) -> void:
	if not is_active:
		return
	_meeting_transition_remaining = 0.0
	if _comm_mgr and _comm_mgr._ui:
		_comm_mgr._ui.end_meeting_transition()
	if _comm_mgr and _comm_mgr._voice:
		_comm_mgr._voice.stop()
	_typing_active = false
	_speech_end_remaining = 0.0
	if _comm_mgr:
		_comm_mgr._stop_speaking()
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
	_speech_end_remaining = 0.0
	if _comm_mgr:
		_comm_mgr._stop_speaking()
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
		if _comm_mgr and _comm_mgr._voice:
			_comm_mgr._voice.stop()
		_typing_active = false
		_speech_end_remaining = 0.0
		_displayed_chars = _full_text.length()
		line_finished.emit(current_line_index)
		_check_line_end_behavior()

## 用户点击继续
func on_click() -> void:
	if _meeting_transition_remaining > 0.0:
		return
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
	if str(line.get("display_mode", "")) == "meeting" and _comm_mgr and _comm_mgr._ui \
			and _comm_mgr._ui._display_mode == "card" and _meeting_transition_line != current_line_index:
		_meeting_transition_line = current_line_index
		_meeting_transition_remaining = MEETING_TRANSITION_SECONDS
		_full_text = ""
		_displayed_chars = 0
		_comm_mgr._stop_speaking()
		_comm_mgr._ui.begin_meeting_transition()
		return

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

		# ── 图层覆盖: 临时替换/隐藏角色图层 ──
		# JSON: "layer_override": { "eye_L": "eye_L_close", "eye_R": "eye_R_open" }
		#        "layer_override_duration": 5.0  (可选，默认永久直到下一行清除)
		var layer_override = line.get("layer_override")
		if layer_override is Dictionary and not layer_override.is_empty():
			var duration: float = float(line.get("layer_override_duration", -1.0))
			_comm_mgr._apply_layer_override(layer_override, duration)

		# ── 清除图层覆盖 ──
		# JSON: "clear_overrides": true
		if line.get("clear_overrides", false):
			_comm_mgr._clear_layer_overrides()

		# ── 服装切换 ──
		# JSON: "costume": "lab_coat" (空字符串 = 恢复默认)
		var costume: String = str(line.get("costume", ""))
		if line.has("costume"):
			_comm_mgr._set_costume(costume)

		# ── 预设动画效果 ──
		# JSON: "anim_effect": "wink_left:2.0" / "wink_right:3.0" /
		#        "eyes_closed:1.5" / "surprised:2.0"
		var anim_effect: String = str(line.get("anim_effect", ""))
		if not anim_effect.is_empty():
			_comm_mgr._play_anim_effect(anim_effect)

		# Meeting 模式相关字段
		var display_mode: String = str(line.get("display_mode", ""))
		var meeting_slot: String = str(line.get("meeting_slot", ""))
		var char_anim: String = str(line.get("char_anim", ""))

		if not display_mode.is_empty():
			_comm_mgr.set_display_mode(display_mode)
		for participant in line.get("meeting_participants", []):
			if participant is Dictionary:
				_comm_mgr.set_meeting_char(str(participant.get("id", "")), str(participant.get("slot", "center")))

		# meeting/presentation 模式下设置角色位置
		# 行显式声明 meeting/presentation，或当前已在会议模式（后续行仅写 meeting_slot）都生效
		var _ui: Variant = _comm_mgr._ui if _comm_mgr else null
		var in_meeting_mode: bool = _ui != null and (_ui._display_mode == "meeting" or _ui._display_mode == "presentation")
		if (display_mode == "meeting" or display_mode == "presentation" or in_meeting_mode) and not char_id.is_empty():
			_comm_mgr.set_meeting_char(char_id, meeting_slot)

		# 播放角色动画（card/meeting 均可用）
		if not char_anim.is_empty() and not char_id.is_empty():
			_comm_mgr.play_meeting_anim(char_id, char_anim)

		# ── 演示模式幻灯片 ──
		# JSON: "slide_image": "images/slide1.png"
		#   "slide_position": [0.55, 0.1]       归一化坐标 (可选)
		#   "slide_size": [0.4, 0.5]             归一化尺寸 (可选)
		#   "slide_area": [x, y, w, h]           展示区域 (覆盖 position/size, 可选)
		#   "slide_fit": "contain"               适配: contain/cover/stretch/actual (可选)
		#   "slide_align": "center"              对齐: center/top_left/top_center/... (可选)
		#   "slide_transition": "fade"           过渡: fade/instant/slide_left/slide_right (可选)
		var slide_image: String = str(line.get("slide_image", ""))
		if not slide_image.is_empty():
			var slide_config: Dictionary = {
				"image": slide_image,
				"position": line.get("slide_position", [0.55, 0.1]),
				"size": line.get("slide_size", [0.4, 0.5]),
				"transition": str(line.get("slide_transition", "fade")),
			}
			if line.has("slide_area"):
				slide_config["area"] = line.get("slide_area")
			if line.has("slide_fit"):
				slide_config["fit"] = str(line.get("slide_fit"))
			if line.has("slide_align"):
				slide_config["align"] = str(line.get("slide_align"))
			if line.has("slide_background_alpha"):
				slide_config["background_alpha"] = float(line["slide_background_alpha"])
			_comm_mgr.show_presentation_slide(slide_config)
		elif line.get("slide_hide", false) != false:
			# JSON: "slide_hide": true  或 "slide_hide": "slide_left"（false 时不触发）
			var hide_transition: String = str(line.get("slide_hide", "fade"))
			if hide_transition == "true" or hide_transition == "True":
				hide_transition = "fade"
			_comm_mgr.hide_presentation_slide(hide_transition)

	# 屏幕效果
	var screen_effect: String = str(line.get("screen_effect", ""))
	if not screen_effect.is_empty() and _main:
		_trigger_screen_effect(screen_effect)

	# 音效
	var sound: String = str(line.get("sound", ""))
	if not sound.is_empty():
		_play_sound(sound)

	# ── 剧情动作（触发器动作字符串，如 "score:1:daily"）──
	var story_action = line.get("story_action")
	if story_action is String and not str(story_action).is_empty():
		_execute_story_action(str(story_action))
	elif story_action is Array:
		for act in story_action:
			_execute_story_action(str(act))
	var reward: Dictionary = line.get("score_once", {})
	if not reward.is_empty() and _main and _main.daily_dialogue_mgr:
		_main.daily_dialogue_mgr.award_score_once(str(reward.get("id", "")),
			int(reward.get("amount", 1)), str(reward.get("category", "daily")))

	# 开始逐字显示
	# 中文省略号也拆成单个点；仅处理显示文本，不改动剧情原文。
	_full_text = text.replace("…", "...")
	_speech_text_end = _full_text.length()
	if str(line.get("wait_for", "")).begins_with("choice:") or not line.get("choice", []).is_empty():
		var option_marker := RegEx.new()
		option_marker.compile("(?m)^[ \\t]*\\[[0-9]+\\]")
		var first_option := option_marker.search(_full_text)
		if first_option:
			_speech_text_end = first_option.get_start()
	_narration = bool(line.get("narration", false))
	_displayed_chars = 0
	_typing_active = true
	_char_timer = 0.0
	_pause_timer = 0.0
	_speech_end_remaining = 0.0

	if _comm_mgr:
		if _comm_mgr._voice:
			_typing_speed = _comm_mgr._voice.get_char_delay()
		# 直到实际输出可发声字符才动嘴，行首省略号也保持静止。
		_comm_mgr._stop_speaking()

## 检查行结束后的行为
func _check_line_end_behavior() -> void:
	var line: Dictionary = current_lines[current_line_index] as Dictionary
	if _comm_mgr:
		for char_id in line.get("hide_characters_after", []):
			_comm_mgr.hide_meeting_char(str(char_id))

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

## 执行剧情动作（转发给触发器系统）
func _execute_story_action(action_str: String) -> void:
	if _main == null or _main.trigger_sys == null:
		return
	_main.trigger_sys._execute(action_str, {})

# ══════════════════════════════════════════
#  每帧更新
# ══════════════════════════════════════════
func process(delta: float) -> void:
	if not is_active:
		return
	if _meeting_transition_remaining > 0.0:
		_meeting_transition_remaining = maxf(0.0, _meeting_transition_remaining - delta)
		_comm_mgr._ui.update_meeting_transition(1.0 - _meeting_transition_remaining / MEETING_TRANSITION_SECONDS)
		if _meeting_transition_remaining == 0.0:
			_comm_mgr._ui.end_meeting_transition()
			_play_current_line()
		return
	if _typing_active:
		_process_typing(delta)
	if _auto_next_timer > 0.0:
		_auto_next_timer -= delta
		if _auto_next_timer <= 0.0:
			advance()

func _process_typing(delta: float) -> void:
	if _speech_end_remaining > 0.0:
		_speech_end_remaining = maxf(0.0, _speech_end_remaining - delta)
		if _speech_end_remaining == 0.0:
			_finish_typing()
		return
	# 前一个字先显示正常间隔，标点停顿及省略号等待期间保持闭嘴。
	if _pause_timer > 0.0:
		_pause_timer -= delta
		return
	_char_timer += delta
	# 省略号等待较长：保留前一个字的正常显示间隔，再闭嘴等待点出现。
	if _comm_mgr and _displayed_chars < _full_text.length() and _char_timer >= _typing_speed:
		var next_char: String = _full_text[_displayed_chars]
		if next_char.strip_edges().is_empty() or CommVoice.PUNCTUATION.contains(next_char):
			_comm_mgr._stop_speaking()
	var ellipsis_dot: bool = _is_ellipsis_dot(_displayed_chars)
	var char_delay: float = ELLIPSIS_DOT_DELAY if ellipsis_dot else _typing_speed
	if _char_timer < char_delay:
		return
	_char_timer -= char_delay
	if _displayed_chars < _full_text.length():
		var is_speech: bool = not _narration and _displayed_chars < _speech_text_end
		if not is_speech and _comm_mgr:
			_comm_mgr._stop_speaking()
			if _comm_mgr._voice:
				_comm_mgr._voice.stop()
		var ch: String = _full_text[_displayed_chars]
		_displayed_chars += 1
		# 跳过 BBCode 标签
		if ch == "[":
			var close_pos: int = _full_text.find("]", _displayed_chars)
			if close_pos >= 0:
				_displayed_chars = close_pos + 1
				return
		# 语音
		if is_speech and _comm_mgr:
			_comm_mgr._speak_char(ch)
		# 标点停顿
		if not ellipsis_dot and _comm_mgr and _comm_mgr._voice:
			_pause_timer = _comm_mgr._voice.get_punctuation_pause(ch)
		if _displayed_chars >= _full_text.length() and is_speech and _comm_mgr \
				and not ch.strip_edges().is_empty() and not CommVoice.PUNCTUATION.contains(ch):
			_speech_end_remaining = SPEECH_END_HOLD_SECONDS
			return
	if _displayed_chars >= _full_text.length():
		_finish_typing()

func _finish_typing() -> void:
	_typing_active = false
	line_finished.emit(current_line_index)
	_check_line_end_behavior()

## 只对连续三个及以上的点应用省略号节奏，避免影响小数、网址。
func _is_ellipsis_dot(index: int) -> bool:
	if index >= _full_text.length() or _full_text[index] != ".":
		return false
	var run_start: int = index
	var run_end: int = index + 1
	while run_start > 0 and _full_text[run_start - 1] == ".":
		run_start -= 1
	while run_end < _full_text.length() and _full_text[run_end] == ".":
		run_end += 1
	return run_end - run_start >= 3

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
