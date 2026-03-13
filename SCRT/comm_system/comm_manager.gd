# ============================================================
# comm_manager.gd — 通讯系统主管理器
# 调度角色、对话、UI、语音、触发条件
# ── 重构：角色管理委托给 CharacterRegistry
# ── 新增：图层覆盖、服装切换、预设动画效果
# ============================================================
class_name CommManager
extends RefCounted

signal comm_started(dialogue_id: String)
signal comm_finished(dialogue_id: String)

var _main = null
var _fs: FileSystem = null
var _T = null

# 子系统
var _ui: CommUI = null
var _player: CommDialoguePlayer = null
var _voice: CommVoice = null
var _call_handler: CallHandler = null

# ── 角色管理（委托给 CharacterRegistry） ──
var _registry: CharacterRegistry = null
var _active_character: CommCharacter = null

# 对话库 { "tutorial_main": { ... dialogue_data } }
var _dialogues: Dictionary = {}

# 状态
var is_active: bool = false

# ── 教程/选项系统 ──
var _pending_choice_id: String = ""          # 当前等待选项的 ID
var _completed_dialogues: Dictionary = {}    # { "dialogue_id": true }
const SAVE_SECTION: String = "comm_completed"

# ── 教程串联队列 ──
var _dialogue_queue: Array[String] = []      # 连续触发的对话 ID 队列

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(main, fs: FileSystem, theme) -> void:
	_main = main
	_fs = fs
	_T = theme

	# 初始化角色注册中心
	_registry = CharacterRegistry.new()
	_registry.setup(main, fs)

	_ui = CommUI.new()
	_ui.setup(main, theme)

	_player = CommDialoguePlayer.new()
	_player.setup(main, self)

	_voice = CommVoice.new()
	_voice.setup(main)

	# 呼叫处理器
	_call_handler = CallHandler.new()
	_call_handler.setup(main, self, main.audio_manager if main else null, theme)
	_call_handler.call_accepted.connect(_on_call_accepted)
	_call_handler.call_rejected.connect(_on_call_rejected)

	# 信号连接
	_player.dialogue_started.connect(_on_dialogue_started)
	_player.dialogue_finished.connect(_on_dialogue_finished)
	_player.line_started.connect(_on_line_started)
	_player.line_finished.connect(_on_line_finished)
	_player.waiting_for_condition.connect(_on_waiting_for_condition)

	# 加载内置教程数据
	_load_tutorial_json()

## 获取角色注册中心（供外部访问）
func get_registry() -> CharacterRegistry:
	return _registry

## 获取素材库（供外部访问）
func get_asset_library() -> CharacterAssetLibrary:
	return _registry.get_asset_library() if _registry else null

## 从 manifest 加载通讯数据
func load_from_manifest(manifest: Dictionary) -> void:
	# 加载角色
	var chars: Dictionary = manifest.get("comm_characters", {}) as Dictionary
	for char_id in chars.keys():
		var char_config: Dictionary = chars[char_id] as Dictionary
		_registry.register_character(char_id, char_config, CharacterRegistry.CharacterSource.BUILTIN)

	# 如果没有角色，创建默认角色
	if _registry.is_empty():
		_create_default_character()

	# 加载对话
	var dialogues: Dictionary = manifest.get("comm_dialogues", {}) as Dictionary
	for dlg_id in dialogues.keys():
		_dialogues[dlg_id] = dialogues[dlg_id]
		print("[CommManager] 已加载对话: %s" % dlg_id)

## 加载内置教程 JSON
func _load_tutorial_json() -> void:
	var path: String = "res://data/tutorial.json"
	if not FileAccess.file_exists(path):
		push_warning("[CommManager] 教程文件不存在: " + path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[CommManager] 无法打开教程文件: " + path)
		return
	var json_text: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(json_text)
	if err != OK:
		push_warning("[CommManager] 教程JSON解析失败: " + json.get_error_message())
		return

	var data: Dictionary = json.data as Dictionary
	if data == null:
		return

	# 加载教程角色
	var chars: Dictionary = data.get("comm_characters", {}) as Dictionary
	for char_id in chars.keys():
		if not _registry.has_character(char_id):
			var char_config: Dictionary = chars[char_id] as Dictionary
			_registry.register_character(char_id, char_config, CharacterRegistry.CharacterSource.BUILTIN)
			print("[CommManager] 已加载教程角色: %s" % char_id)

	# 为内置角色设置素材
	_registry.setup_ava()
	_registry.setup_researcher()

	# 加载 AVA 常态对话
	_load_ava_dialogues()

	# 加载教程对话
	var dialogues: Dictionary = data.get("comm_dialogues", {}) as Dictionary
	for dlg_id in dialogues.keys():
		if not _dialogues.has(dlg_id):
			_dialogues[dlg_id] = dialogues[dlg_id]
			print("[CommManager] 已加载教程对话: %s" % dlg_id)

## 通用分层角色设置（向后兼容接口）
func setup_layered_character(char_id: String, sprite_dir: String, config: Dictionary) -> void:
	_registry.setup_layered_character(char_id, sprite_dir, config)

## 加载 AVA 联络员常态对话
func _load_ava_dialogues() -> void:
	var path: String = "res://data/ava_dialogues.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return
	file.close()
	var data: Dictionary = json.data as Dictionary
	if data == null:
		return
	var dialogues: Dictionary = data.get("comm_dialogues", {}) as Dictionary
	for dlg_id in dialogues.keys():
		if not _dialogues.has(dlg_id):
			_dialogues[dlg_id] = dialogues[dlg_id]
			print("[CommManager] 已加载AVA对话: %s" % dlg_id)


## 创建内置默认角色
func _create_default_character() -> void:
	_registry.create_default_character()

## ★ 设置默认角色的静态头像（给只有一张图的情况）
func set_default_portrait(texture: ImageTexture) -> void:
	var ch: CommCharacter = _registry.get_character("op7")
	if ch:
		ch.static_portrait = texture
		ch.sprite_mode = CommCharacter.SpriteMode.STATIC

# ══════════════════════════════════════════
#  对话控制
# ══════════════════════════════════════════
## 触发一段对话
func trigger_dialogue(dialogue_id: String) -> bool:
	print("[CommManager] trigger_dialogue: ", dialogue_id)
	if not _dialogues.has(dialogue_id):
		push_warning("[CommManager] 对话不存在: %s (已有: %s)" % [dialogue_id, str(_dialogues.keys())])
		return false
	# 记录 UI 是否已经在展开状态
	var ui_already_showing: bool = is_active and _ui.is_visible and not _ui._collapsed

	if is_active:
		push_warning("[CommManager] 对话被覆盖: %s" % dialogue_id)
		# ★ silent=true：不发 finished 信号，不触发 UI 隐藏和挂机流程
		_player.stop_dialogue(true)
		if _active_character:
			_active_character.stop_speaking()
			_active_character.clear_all_overrides()
		_pending_choice_id = ""

	var dialogue_data: Dictionary = _dialogues[dialogue_id]

	# ★ 对话前清屏（设置项）
	if _main and _main.settings_mgr and _main.settings_mgr.get_bool("comm.clear_before_dialogue"):
		_main.output_text.text = ""
		if _main.tw:
			_main.tw.clear_queue()

	is_active = true

	# 确定初始角色
	var first_line: Dictionary = {}
	var lines: Array = dialogue_data.get("lines", []) as Array
	if lines.size() > 0:
		first_line = lines[0] as Dictionary

	var first_char_id: String = str(first_line.get("character", "op7"))
	print("[CommManager] 首行角色: ", first_char_id, " 角色库: ", _registry.get_character_ids())
	_set_active_character(first_char_id)

	# 仅在 UI 尚未展开时执行弹出动画
	if ui_already_showing:
		_ui._build_ui()
		_ui._root.visible = true
		_ui._dialog_bar.visible = true
	else:
		_ui.show()

	# 开始播放
	_player.start_dialogue(dialogue_id, dialogue_data)
	print("[CommManager] 对话已启动: ", dialogue_id, " ui.is_visible=", _ui.is_visible)
	return true



## 列出当前可用的通讯频道（供 comm 命令使用）
func get_available_channels() -> Array[Dictionary]:
	var channels: Array[Dictionary] = []
	for dlg_id in _dialogues.keys():
		if dlg_id.begins_with("tutorial_"):
			continue
		var dlg_data: Dictionary = _dialogues[dlg_id]
		var lines: Array = dlg_data.get("lines", []) as Array
		var first_char_id: String = ""
		if lines.size() > 0:
			first_char_id = str((lines[0] as Dictionary).get("character", ""))
		var char_name: String = first_char_id
		var ch: CommCharacter = _registry.get_character(first_char_id)
		if ch:
			char_name = ch.display_name
		channels.append({
			"id": dlg_id,
			"character": char_name,
			"description": str(dlg_data.get("description", "")),
			"repeatable": dlg_data.get("repeatable", false),
		})
	return channels

## 检查对话是否可以触发（未完成或可重复）
func can_trigger(dialogue_id: String) -> bool:
	if not _dialogues.has(dialogue_id):
		return false
	var dlg_data: Dictionary = _dialogues[dialogue_id]
	if dlg_data.get("repeatable", false):
		return true
	return not is_dialogue_completed(dialogue_id)


## 触发对话序列（多段对话按顺序播放）
func trigger_dialogue_sequence(dialogue_ids: Array) -> bool:
	if dialogue_ids.is_empty():
		return false
	_dialogue_queue.clear()
	for i in range(1, dialogue_ids.size()):
		_dialogue_queue.append(str(dialogue_ids[i]))
	return trigger_dialogue(str(dialogue_ids[0]))

## 停止对话（主动中断，如 ESC）
func stop_dialogue() -> void:
	if _ui:
		_ui.flush_history_to_disk()
	_player.stop_dialogue(true)
	if _active_character:
		_active_character.stop_speaking()
		_active_character.clear_all_overrides()
	_ui.clear_cards()
	_ui.hide()
	is_active = false
	_pending_choice_id = ""


## 处理输入（返回 true 表示已消费）
func handle_input(event: InputEvent) -> bool:
	if not is_active:
		return false

	if event is InputEventKey and event.pressed:
		# ESC 跳过（如果允许）
		if event.keycode == KEY_ESCAPE and _player.is_skippable:
			_dialogue_queue.clear()
			var esc_dlg_id: String = _player.current_dialogue_id
			_mark_dialogue_completed(esc_dlg_id)
			var esc_is_dial: bool = _main.dial_mgr != null and _main.dial_mgr.is_active()
			stop_dialogue()
			comm_finished.emit(esc_dlg_id)
			if esc_is_dial:
				if _main and _main.get_tree():
					_main.get_tree().create_timer(1.0).timeout.connect(func():
						if _main.dial_mgr and _main.dial_mgr.is_active():
							_main.dial_mgr.on_voice_call_ended()
					)
			return true


		# ── 选项模式：数字键选择 ──
		if not _pending_choice_id.is_empty():
			var num: int = _keycode_to_number(event.keycode)
			if num >= 1:
				_handle_choice_selection(num)
				return true
			return true

		# 空格/回车：点击继续 或 跳过打字
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			if is_waiting_for_command():
				return false
			_player.on_click()
			return true

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not _pending_choice_id.is_empty():
				return true
			_player.on_click()
			return true

	return false

## 数字键码转数字
func _keycode_to_number(keycode: int) -> int:
	match keycode:
		KEY_1, KEY_KP_1: return 1
		KEY_2, KEY_KP_2: return 2
		KEY_3, KEY_KP_3: return 3
		KEY_4, KEY_KP_4: return 4
		KEY_5, KEY_KP_5: return 5
		KEY_6, KEY_KP_6: return 6
		KEY_7, KEY_KP_7: return 7
		KEY_8, KEY_KP_8: return 8
		KEY_9, KEY_KP_9: return 9
	return -1

# ══════════════════════════════════════════
#  选项系统
# ══════════════════════════════════════════
func _handle_choice_selection(choice_num: int) -> void:
	var choice_id: String = _pending_choice_id
	_pending_choice_id = ""
	match choice_id:
		"tutorial_ask":
			_handle_tutorial_choice(choice_num)
		_:
			_handle_generic_choice(choice_id, choice_num)



func _handle_tutorial_choice(choice_num: int) -> void:
	_player.stop_dialogue(true)
	if _active_character:
		_active_character.stop_speaking()
	_pending_choice_id = ""
	match choice_num:
		1:
			trigger_dialogue("tutorial_main")
		2:
			trigger_dialogue("tutorial_skip")
		_:
			trigger_dialogue("tutorial_ask")


## 处理通用对话选项（非教程）
func _handle_generic_choice(choice_id: String, choice_num: int) -> void:
	_player.stop_dialogue(true)
	if _active_character:
		_active_character.stop_speaking()
	_pending_choice_id = ""

	var base_id: String = choice_id
	var q_pos: int = choice_id.rfind("_q")
	if q_pos >= 0:
		base_id = choice_id.substr(0, q_pos)

	var branch_id: String = base_id + "_a" + str(choice_num)

	var candidates: Array[String] = [
		branch_id,
		base_id + "_" + str(choice_num),
		choice_id + "_" + str(choice_num),
		base_id + "_ready_" + str(choice_num),
	]

	for candidate in candidates:
		if _dialogues.has(candidate):
			trigger_dialogue(candidate)
			return

	if _main:
		var muted: String = _main.theme_manager.muted_hex if _main.theme_manager else "#888888"
		_main.append_output("[color=" + muted + "]（选择了选项 " + str(choice_num) + "，但没有对应的分支对话）[/color]\n", false)

# ══════════════════════════════════════════
#  角色控制（内部，供 dialogue_player 调用）
# ══════════════════════════════════════════
func _set_active_character(char_id: String) -> void:
	if not _registry.has_character(char_id):
		if _registry.has_character("op7"):
			char_id = "op7"
		elif _registry.has_character("ava"):
			char_id = "ava"
		elif _registry.size() > 0:
			char_id = _registry.get_character_ids()[0]
		else:
			return
	_active_character = _registry.get_character(char_id)
	_voice.apply_config(_active_character.voice_config)
	_ui.set_character(_active_character)
	# Meeting 模式下：活跃角色提到最前面
	if _ui._display_mode == "meeting":
		_ui.bring_meeting_to_front(char_id)

func _set_expression(expression: String) -> void:
	if _active_character:
		_active_character.set_expression(expression)

func _play_action(action_id: String) -> void:
	if _active_character:
		_active_character.play_action(action_id)

func _start_speaking() -> void:
	if _active_character:
		_active_character.start_speaking()

func _stop_speaking() -> void:
	if _active_character:
		_active_character.stop_speaking()

func _speak_char(ch: String) -> void:
	if _voice:
		_voice.speak_char(ch)

# ══════════════════════════════════════════
#  图层覆盖 / 服装 / 动画效果（新功能）
# ══════════════════════════════════════════

## 应用图层覆盖（由 dialogue_player 调用）
func _apply_layer_override(layer_changes: Dictionary, duration: float = -1.0) -> void:
	if _active_character and _active_character.animator:
		_active_character.animator.add_layer_override(layer_changes, duration)

## 清除所有图层覆盖
func _clear_layer_overrides() -> void:
	if _active_character and _active_character.animator:
		_active_character.animator.clear_all_overrides()

## 切换服装
func _set_costume(costume_name: String) -> void:
	if _active_character:
		_active_character.set_costume(costume_name)

## 播放预设动画效果
## 格式: "effect_name:duration" 或 "effect_name"
func _play_anim_effect(effect_str: String) -> void:
	if _active_character == null or _active_character.animator == null:
		return
	var parts: PackedStringArray = effect_str.split(":")
	var effect_name: String = parts[0].strip_edges()
	var duration: float = 2.0
	if parts.size() > 1:
		duration = float(parts[1].strip_edges())
	match effect_name:
		"wink_left":
			_active_character.animator.play_wink("L", duration)
		"wink_right":
			_active_character.animator.play_wink("R", duration)
		"eyes_closed":
			_active_character.animator.play_eyes_closed(duration)
		"surprised":
			_active_character.animator.play_surprised(duration)
		_:
			push_warning("[CommManager] 未知动画效果: %s" % effect_name)

# ══════════════════════════════════════════
#  Meeting 模式 API
# ══════════════════════════════════════════

## 切换显示模式: "card" / "meeting"
func set_display_mode(mode: String) -> void:
	_ui.set_display_mode(mode)

## 设置 meeting 模式下角色位置 (slot: "left"/"center"/"right")
func set_meeting_char(char_id: String, slot: String) -> void:
	var character: CommCharacter = _registry.get_character(char_id)
	if character == null:
		return
	_ui.ensure_meeting_char(character, slot)

## 播放 meeting 模式动画
func play_meeting_anim(char_id: String, anim: String) -> void:
	_ui.play_meeting_anim(char_id, anim)

## 隐藏 meeting 模式角色
func hide_meeting_char(char_id: String) -> void:
	_ui.hide_meeting_char(char_id)

## 清除所有 meeting 角色并回到 card 模式
func clear_meeting() -> void:
	_ui.clear_meeting_chars()

## 显示演示模式幻灯片
func show_presentation_slide(config: Dictionary) -> void:
	if _ui:
		_ui.show_presentation_slide(config)

## 隐藏演示模式幻灯片
func hide_presentation_slide(transition: String = "fade") -> void:
	if _ui:
		_ui.hide_presentation_slide(transition)

# ══════════════════════════════════════════
#  条件系统
# ══════════════════════════════════════════

## 外部通知条件满足（由 main/cmd_handler 调用）
func notify_condition(condition_type: String, value: String = "") -> void:
	if not is_active:
		return
	var full_condition: String = condition_type
	if not value.is_empty():
		full_condition = condition_type + ":" + value
	_player.notify_condition_met(full_condition)

## 命令执行通知（支持前缀匹配）
func on_command_executed(cmd_name: String, cmd_args: Array = []) -> void:
	if not is_active:
		return
	notify_condition("command", cmd_name)
	if not cmd_args.is_empty():
		var full_cmd: String = cmd_name
		var str_args: PackedStringArray = PackedStringArray()
		for a in cmd_args:
			str_args.append(str(a))
		full_cmd += " " + " ".join(str_args)
		_player.notify_condition_met("command:" + full_cmd)
	if _ui._auto_collapsed:
		_ui.auto_expand()

## 文件打开通知
func on_file_opened(file_path: String) -> void:
	notify_condition("open_file", file_path)

## 目录进入通知
func on_directory_entered(dir_path: String) -> void:
	notify_condition("enter_dir", dir_path)

# ══════════════════════════════════════════
#  每帧更新
# ══════════════════════════════════════════
func process(delta: float) -> void:
	if _ui:
		_ui.process(delta)
	if _call_handler:
		_call_handler.process(delta)
	if not is_active:
		return
	_player.process(delta)
	if _active_character:
		_active_character.process(delta)
	_ui.update_text(_player.get_displayed_text())


# ══════════════════════════════════════════
#  呼叫处理器回调
# ══════════════════════════════════════════
func _on_call_accepted(dialogue_id: String) -> void:
	trigger_dialogue(dialogue_id)

func _on_call_rejected(dialogue_id: String) -> void:
	var consequence: String = _call_handler.get_pending_reject_consequence() if _call_handler else ""
	if not consequence.is_empty() and _main and _main.trigger_sys:
		_main.trigger_sys.execute_action(consequence)
	print("[CommManager] 来电已拒绝: %s" % dialogue_id)

## 呼叫处理器查询
func is_call_ringing() -> bool:
	return _call_handler != null and _call_handler.is_ringing()

func has_pending_call_answer() -> bool:
	return _call_handler != null and _call_handler.has_pending_answer()

# ══════════════════════════════════════════
#  信号回调
# ══════════════════════════════════════════
func _on_dialogue_started(dialogue_id: String) -> void:
	_ui.set_current_dialogue_id(dialogue_id)
	comm_started.emit(dialogue_id)


func _on_dialogue_finished(dialogue_id: String) -> void:
	_ui.flush_history_to_disk()
	_ui.clear_cards()

	var is_dial_call: bool = _main.dial_mgr != null and _main.dial_mgr.is_active()

	# 清除角色动画状态
	if _active_character:
		_active_character.clear_all_overrides()

	_ui.hide()
	is_active = false
	_mark_dialogue_completed(dialogue_id)
	comm_finished.emit(dialogue_id)

	if is_dial_call:
		if _main and _main.get_tree():
			_main.get_tree().create_timer(1.0).timeout.connect(func():
				if _main.dial_mgr and _main.dial_mgr.is_active():
					_main.dial_mgr.on_voice_call_ended()
			)

	if not _dialogue_queue.is_empty():
		var next_id: String = _dialogue_queue.pop_front()
		if _main:
			_main.get_tree().create_timer(0.3).timeout.connect(func():
				trigger_dialogue(next_id)
			)


func _on_line_started(_line_index: int) -> void:
	_ui.show_continue_prompt(false)
	_ui.hide_wait_prompt()
	_pending_choice_id = ""
	if _ui._collapsed:
		_ui.auto_expand()

func _on_line_finished(_line_index: int) -> void:
	if _active_character and _player:
		var displayed: String = _player.get_displayed_text()
		if not displayed.is_empty():
			_ui.add_history_line(_active_character.display_name, displayed)
	if _player._click_to_continue:
		_ui.show_continue_prompt(true)

func _on_waiting_for_condition(condition: String) -> void:
	if condition.begins_with("choice:"):
		_pending_choice_id = condition.substr(7)
		_ui.show_wait_prompt_custom("按数字键选择 | ESC 跳过")
		return

	if condition.begins_with("command:") or condition.begins_with("open_file:") or condition.begins_with("enter_dir:"):
		_ui.show_wait_prompt(condition)
		_ui.auto_collapse()
		return

	_ui.show_wait_prompt(condition)

	if condition.begins_with("timer:"):
		var seconds: float = float(condition.substr(6))
		if seconds > 0.0 and _main:
			_main.get_tree().create_timer(seconds).timeout.connect(func():
				_player.notify_condition_met(condition)
			)

# ══════════════════════════════════════════
#  完成状态持久化
# ══════════════════════════════════════════

func _mark_dialogue_completed(dialogue_id: String) -> void:
	if dialogue_id.is_empty():
		return
	if dialogue_id == "tutorial_ask":
		return
	_completed_dialogues[dialogue_id] = true
	_save_completed()


func is_dialogue_completed(dialogue_id: String) -> bool:
	return _completed_dialogues.has(dialogue_id)

func reload_user_data() -> void:
	_load_completed()

func _get_save_path() -> String:
	if _main and _main.user_mgr and _main.user_mgr.is_logged_in:
		var username: String = _main.user_mgr.get_username()
		var base_dir: String = ""
		if OS.has_feature("editor"):
			base_dir = ProjectSettings.globalize_path("res://")
		else:
			base_dir = OS.get_executable_path().get_base_dir()
		var user_dir: String = base_dir.path_join("saves").path_join(username)
		if not DirAccess.dir_exists_absolute(user_dir):
			DirAccess.make_dir_recursive_absolute(user_dir)
		return user_dir.path_join("comm_progress.cfg")
	return ""

func _save_completed() -> void:
	var path: String = _get_save_path()
	if path.is_empty():
		return
	var cfg := ConfigFile.new()
	for key in _completed_dialogues:
		cfg.set_value(SAVE_SECTION, str(key), true)
	cfg.save(path)

func _load_completed() -> void:
	_completed_dialogues.clear()
	var path: String = _get_save_path()
	if path.is_empty():
		return
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	if not cfg.has_section(SAVE_SECTION):
		return
	for key in cfg.get_section_keys(SAVE_SECTION):
		_completed_dialogues[key] = true


# ══════════════════════════════════════════
#  磁盘对话加载/卸载
# ══════════════════════════════════════════
var _disc_dialogue_ids: Array[String] = []

func load_disc_dialogues(manifest_data: Dictionary) -> void:
	# 加载磁盘角色（委托给 registry）
	var chars_data: Dictionary = manifest_data.get("comm_characters", {}) as Dictionary
	if not chars_data.is_empty():
		var loaded_ids: Array[String] = _registry.load_disc_characters(chars_data)
		# loaded_ids 由 registry 追踪

	# 加载磁盘对话
	var dialogues_data: Dictionary = manifest_data.get("comm_dialogues", {}) as Dictionary
	for dlg_id in dialogues_data.keys():
		if _dialogues.has(dlg_id):
			print("[CommManager] 磁盘对话覆盖已有对话: ", dlg_id)
		_dialogues[dlg_id] = dialogues_data[dlg_id]
		_disc_dialogue_ids.append(dlg_id)
		print("[CommManager] 磁盘对话已加载: ", dlg_id)


func unload_disc_dialogues() -> void:
	var active_dlg: String = _player.current_dialogue_id if _player else ""
	if is_active and active_dlg in _disc_dialogue_ids:
		stop_dialogue()

	# 移除磁盘对话
	for dlg_id in _disc_dialogue_ids:
		_dialogues.erase(dlg_id)
	_disc_dialogue_ids.clear()

	# 移除磁盘角色（委托给 registry）
	_registry.unload_by_source(CharacterRegistry.CharacterSource.DISC)

	print("[CommManager] 磁盘通讯数据已卸载")



var current_dialogue_id: String:
	get:
		return _player.current_dialogue_id if _player else ""



# ══════════════════════════════════════════
#  教程系统入口
# ══════════════════════════════════════════
func try_trigger_tutorial() -> void:
	reload_user_data()
	var tutorial_done: bool = is_dialogue_completed("tutorial_main") or \
							  is_dialogue_completed("tutorial_skip")
	if not tutorial_done:
		if not _dialogues.has("tutorial_ask"):
			push_warning("[CommManager] tutorial_ask 对话不存在！检查 tutorial.json")
			return
		if _main:
			_main.get_tree().create_timer(1.5).timeout.connect(func():
				trigger_dialogue("tutorial_ask")
			)
	else:
		_try_ava_login_welcome()

func _try_ava_login_welcome() -> void:
	if not _dialogues.has("ava_login_welcome"):
		return
	if _main:
		_main.get_tree().create_timer(2.0).timeout.connect(func():
			if not is_active:
				trigger_dialogue("ava_login_welcome")
		)




# ══════════════════════════════════════════
#  触发系统集成
# ══════════════════════════════════════════

func handle_trigger_action(action: String) -> bool:
	if not action.begins_with("comm:"):
		return false
	# 支持格式: "comm:dialogue_id" 或 "comm:dialogue_id:forced" 或 "comm:dialogue_id:answerable"
	var parts: PackedStringArray = action.substr(5).strip_edges().split(":")
	var dialogue_id: String = parts[0]
	if parts.size() >= 2:
		var call_mode_str: String = parts[1]
		var call_mode: CallHandler.CallMode = CallHandler.parse_call_mode(call_mode_str)
		if call_mode != CallHandler.CallMode.SILENT and _call_handler:
			var caller_name: String = _get_caller_name_for_dialogue(dialogue_id)
			_call_handler.initiate_call(dialogue_id, call_mode, "", caller_name)
			return true
	return trigger_dialogue(dialogue_id)

## 从对话数据中提取来电者名称
func _get_caller_name_for_dialogue(dialogue_id: String) -> String:
	if not _dialogues.has(dialogue_id):
		return "UNKNOWN"
	var dlg: Dictionary = _dialogues[dialogue_id] as Dictionary
	var lines: Array = dlg.get("lines", []) as Array
	if lines.size() > 0:
		var first_char_id: String = str((lines[0] as Dictionary).get("character", "op7"))
		var ch: CommCharacter = _registry.get_character(first_char_id)
		if ch:
			return ch.display_name
	return "UNKNOWN"

func check_auto_triggers(story_manifest: Dictionary) -> void:
	for dlg_id in _dialogues.keys():
		var dlg: Dictionary = _dialogues[dlg_id] as Dictionary
		var trigger: String = str(dlg.get("trigger", ""))
		match trigger:
			"auto_first_boot":
				var played_key: String = "comm_played_" + dlg_id
				var already_played: bool = false
				if _main and _main.pkg_mgr:
					already_played = _main.pkg_mgr._api_load_mod_data("_comm_system", played_key, false)
				if not already_played:
					trigger_dialogue(dlg_id)
					if _main and _main.pkg_mgr:
						_main.pkg_mgr._api_save_mod_data("_comm_system", played_key, true)
			"incoming_call":
				_initiate_incoming_call(dlg_id, dlg)

## 发起来电（根据 call_mode 路由到 CallHandler 或兼容旧逻辑）
func _initiate_incoming_call(dialogue_id: String, dlg_data: Dictionary) -> void:
	if _main == null:
		return
	var lines: Array = dlg_data.get("lines", []) as Array
	var caller_name: String = "UNKNOWN"
	if lines.size() > 0:
		var first_char_id: String = str(lines[0].get("character", "op7"))
		var ch: CommCharacter = _registry.get_character(first_char_id)
		if ch:
			caller_name = ch.display_name

	# 读取 call_mode 字段（默认 "answerable" 以保持向后兼容）
	var call_mode_str: String = str(dlg_data.get("call_mode", "answerable"))
	var call_mode: CallHandler.CallMode = CallHandler.parse_call_mode(call_mode_str)
	var reject_consequence: String = str(dlg_data.get("reject_consequence", ""))

	if _call_handler:
		_call_handler.initiate_call(dialogue_id, call_mode, reject_consequence, caller_name)
	else:
		# 降级：直接显示旧式提示
		_show_incoming_call_legacy(dialogue_id, caller_name)

## 旧式来电提示（无 CallHandler 时的兼容路径）
func _show_incoming_call_legacy(dialogue_id: String, caller_name: String) -> void:
	_pending_incoming_call = dialogue_id
	var c_hex: String = _T.warning_hex if _T else "#ffff00"
	var m_hex: String = _T.muted_hex if _T else "#888888"
	_main.append_output("\n[color=" + c_hex + "]╔══════════════════════════════════╗[/color]\n", false)
	_main.append_output("[color=" + c_hex + "]║  ☎ INCOMING COMM — " + caller_name + "[/color]\n", false)
	_main.append_output("[color=" + m_hex + "]║  输入 [color=" + c_hex + "]comm answer[/color] 接听通讯[/color]\n", false)
	_main.append_output("[color=" + c_hex + "]╚══════════════════════════════════╝[/color]\n\n", false)

var _pending_incoming_call: String = ""

# ══════════════════════════════════════════
#  主动通讯系统（玩家呼叫联络员）
# ══════════════════════════════════════════

func _is_user_callable(dlg_id: String) -> bool:
	if dlg_id.begins_with("tutorial_"):
		return false
	if not _dialogues.has(dlg_id):
		return false
	var dlg: Dictionary = _dialogues[dlg_id] as Dictionary
	if dlg.has("callable") and not dlg.get("callable", true):
		return false
	var has_description: bool = not str(dlg.get("description", "")).is_empty()
	var explicitly_callable: bool = dlg.get("callable", false)
	if has_description or explicitly_callable or dlg_id.begins_with("comm_"):
		return true
	return false


func handle_comm_command(args: Array = []) -> void:
	if _main == null:
		return
	var p: String = _T.primary_hex if _T else "#00ff00"
	var m: String = _T.muted_hex if _T else "#888888"
	var w: String = _T.warning_hex if _T else "#ffaa00"
	var e: String = _T.error_hex if _T else "#ff0000"

	if is_active:
		_main.append_output("[color=" + m + "]通讯频道正在使用中。[/color]\n", false)
		return

	if not args.is_empty():
		var target_id: String = str(args[0]).strip_edges()

		if target_id == "phonebook" or target_id == "pb":
			_show_phonebook()
			return

		if target_id == "answer":
			# 优先通过 CallHandler 接听
			if _call_handler and _call_handler.has_pending_answer():
				_call_handler.accept_call()
			elif not _pending_incoming_call.is_empty():
				var call_id: String = _pending_incoming_call
				_pending_incoming_call = ""
				trigger_dialogue(call_id)
			else:
				_main.append_output("[color=" + m + "]当前没有待接听的通讯。[/color]\n", false)
			return

		if target_id == "reject":
			if _call_handler and _call_handler.has_pending_answer():
				_call_handler.reject_call()
			else:
				_main.append_output("[color=" + m + "]当前没有待拒绝的通讯。[/color]\n", false)
			return

		if target_id == "video" or target_id == "meeting":
			# 支持 comm video <号码> 直接拨号
			if args.size() >= 2:
				var video_number: String = str(args[1]).strip_edges()
				_dial_video_call(video_number)
			else:
				_show_video_channels()
			return

		if _main.dial_mgr != null and _main.dial_mgr.is_number_format(target_id):
			if _main.dial_mgr.is_active():
				_main.append_output("[color=" + m + "]线路忙，请稍后再试。[/color]\n", false)
				return
			_main.dial_mgr.dial(target_id)
			return

		_main.append_output("[color=" + e + "]未知参数: " + target_id + "[/color]\n", false)
		_main.append_output("[color=" + m + "]用法: comm / comm answer / comm reject / comm video / comm video <号码>[/color]\n", false)
		_main.append_output("[color=" + m + "]如需联络，请使用 dial <号码> 拨号呼叫。[/color]\n", false)
		return

	_main.append_output("\n[color=" + p + "]═══════════ 通讯系统 ═══════════[/color]\n\n", false)

	var has_pending: bool = not _pending_incoming_call.is_empty() or (_call_handler and _call_handler.has_pending_answer())
	if has_pending:
		_main.append_output("  [color=" + w + "]★ 待接听来电[/color]  [color=" + m + "]输入 comm answer 接听 / comm reject 拒绝[/color]\n\n", false)

	if _main.dial_mgr:
		var all_numbers: Array[String] = _main.dial_mgr.get_all_numbers()
		if not all_numbers.is_empty():
			_main.append_output("  [color=" + p + "]已知号码:[/color]\n", false)
			var show_count: int = mini(all_numbers.size(), 5)
			for i in range(show_count):
				var num: String = all_numbers[i]
				var resolved: Dictionary = _main.dial_mgr.resolve_number(num)
				var display_label: String = str(resolved.get("label", ""))
				if display_label.is_empty():
					display_label = str(resolved.get("character", "未知"))
				_main.append_output("	[color=" + p + "]" + num + "[/color]  [color=" + m + "]" + display_label + "[/color]\n", false)
			if all_numbers.size() > show_count:
				_main.append_output("	[color=" + m + "]... 共 " + str(all_numbers.size()) + " 个号码，输入 phonebook 查看完整列表[/color]\n", false)
		else:
			_main.append_output("  [color=" + m + "]号码簿为空。[/color]\n", false)
	else:
		_main.append_output("  [color=" + m + "]拨号系统未初始化。[/color]\n", false)


	_main.append_output("\n[color=" + p + "]════════════════════════════════════[/color]\n", false)
	_main.append_output("[color=" + m + "]拨号联络: dial <号码>  (如 dial 1001-0001)[/color]\n", false)
	_main.append_output("[color=" + m + "]视频通讯: comm video  (查看频道列表)[/color]\n", false)
	_main.append_output("[color=" + m + "]视频拨号: comm video <号码>  (如 comm video 1001-0001)[/color]\n", false)
	_main.append_output("[color=" + m + "]查看号码簿: phonebook[/color]\n", false)
	if has_pending:
		_main.append_output("[color=" + m + "]接听来电: comm answer  拒绝: comm reject[/color]\n", false)


# ══════════════════════════════════════════
#  拨号系统集成
# ══════════════════════════════════════════

## 获取所有可用的视频通讯频道
## 返回 Array[Dictionary]，每项: { "dlg_id", "title", "character", "number" }
func _get_video_channels() -> Array[Dictionary]:
	var channels: Array[Dictionary] = []
	for dlg_id in _dialogues.keys():
		var dlg: Dictionary = _dialogues[dlg_id] as Dictionary
		# 标记了 video_call 的对话
		if dlg.get("video_call", false):
			if not _is_user_callable(dlg_id):
				continue
			var title: String = str(dlg.get("title", dlg_id))
			var number: String = str(dlg.get("video_number", ""))
			var lines: Array = dlg.get("lines", []) as Array
			var char_name: String = ""
			if lines.size() > 0:
				var first_cid: String = str((lines[0] as Dictionary).get("character", ""))
				var ch: CommCharacter = _registry.get_character(first_cid)
				if ch:
					char_name = ch.display_name
			channels.append({
				"dlg_id": dlg_id,
				"title": title,
				"character": char_name,
				"number": number,
			})
			continue
		# 兼容：没有 video_call 标记但含 meeting display_mode 的对话
		if not _is_user_callable(dlg_id):
			continue
		var lines2: Array = dlg.get("lines", []) as Array
		for line in lines2:
			if line is Dictionary and str(line.get("display_mode", "")) == "meeting":
				var title2: String = str(dlg.get("title", dlg_id))
				channels.append({
					"dlg_id": dlg_id,
					"title": title2,
					"character": "",
					"number": "",
				})
				break
	return channels

## 显示视频通讯频道列表
func _show_video_channels() -> void:
	var p: String = _T.primary_hex if _T else "#00ff00"
	var m: String = _T.muted_hex if _T else "#888888"
	var w: String = _T.warning_hex if _T else "#ffaa00"

	var channels: Array[Dictionary] = _get_video_channels()
	if channels.is_empty():
		_main.append_output("[color=" + m + "]当前没有可用的视频通讯频道。[/color]\n", false)
		return

	_main.append_output("\n[color=" + p + "]═══════════ 视频通讯频道 ═══════════[/color]\n\n", false)
	for i in range(channels.size()):
		var ch: Dictionary = channels[i]
		var num_str: String = str(ch.get("number", ""))
		var title_str: String = str(ch.get("title", ""))
		var char_str: String = str(ch.get("character", ""))
		var line: String = "  [color=" + p + "]" + str(i + 1) + ".[/color] "
		line += "[color=" + w + "]" + title_str + "[/color]"
		if not char_str.is_empty():
			line += "  [color=" + m + "](" + char_str + ")[/color]"
		if not num_str.is_empty():
			line += "  [color=" + m + "]" + num_str + "[/color]"
		_main.append_output(line + "\n", false)
	_main.append_output("\n[color=" + m + "]拨号连接: [color=" + p + "]comm video <号码>[/color]  或  [color=" + p + "]dial <号码>[/color][/color]\n", false)
	_main.append_output("[color=" + m + "]所有视频通讯均通过拨号系统建立连接。[/color]\n", false)

## 通过拨号系统发起视频通讯
func _dial_video_call(number: String) -> void:
	var p: String = _T.primary_hex if _T else "#00ff00"
	var m: String = _T.muted_hex if _T else "#888888"
	if _main.dial_mgr == null:
		_main.append_output("[color=" + m + "]拨号系统未初始化。[/color]\n", false)
		return
	if _main.dial_mgr.is_active():
		_main.append_output("[color=" + m + "]线路忙，请稍后再试。[/color]\n", false)
		return
	# 验证号码是否有效
	if _main.dial_mgr.is_number_format(number):
		_main.dial_mgr.dial(number)
	else:
		# 尝试匹配视频频道名称或序号
		var channels: Array[Dictionary] = _get_video_channels()
		var idx: int = number.to_int() - 1
		if idx >= 0 and idx < channels.size():
			var ch_number: String = str(channels[idx].get("number", ""))
			if not ch_number.is_empty():
				_main.dial_mgr.dial(ch_number)
			else:
				# 无号码的频道直接触发
				trigger_dialogue(str(channels[idx].get("dlg_id", "")))
		else:
			_main.append_output("[color=" + m + "]无效的频道号码或序号: " + number + "[/color]\n", false)
			_main.append_output("[color=" + m + "]输入 [color=" + p + "]comm video[/color] 查看可用频道列表。[/color]\n", false)

func _show_phonebook() -> void:
	if _main.dial_mgr:
		var text: String = _main.dial_mgr.get_phonebook_text()
		_main.append_output(text, false)
	else:
		var m_str: String = _T.muted_hex if _T else "#888888"
		_main.append_output("[color=" + m_str + "]拨号系统未初始化。[/color]\n", false)

func start_dialogue_from_dial(character_id: String, dialed_number: String = "") -> void:
	var target_dlg_id: String = ""

	# ★ 优先按 video_number 精确匹配（支持视频频道拨号）
	if not dialed_number.is_empty():
		for dlg_id in _dialogues.keys():
			var dlg: Dictionary = _dialogues[dlg_id] as Dictionary
			if str(dlg.get("video_number", "")) == dialed_number:
				target_dlg_id = dlg_id
				break

	# 按角色名模式匹配
	if target_dlg_id.is_empty():
		var candidates: Array[String] = [
			character_id + "_chat",
			character_id + "_greeting",
			character_id + "_main",
			"comm_" + character_id,
		]
		for candidate in candidates:
			if _dialogues.has(candidate):
				target_dlg_id = candidate
				break

	if target_dlg_id.is_empty():
		for dlg_id in _dialogues.keys():
			var dlg: Dictionary = _dialogues[dlg_id] as Dictionary
			var lines: Array = dlg.get("lines", []) as Array
			if lines.size() > 0:
				var first_char: String = str((lines[0] as Dictionary).get("character", ""))
				if first_char == character_id and _is_user_callable(dlg_id):
					target_dlg_id = dlg_id
					break

	if target_dlg_id.is_empty():
		var m_str: String = _T.muted_hex if _T else "#888888"
		_main.append_output("[color=" + m_str + "]联络员 " + character_id + " 当前不可用。[/color]\n", false)
		if _main.dial_mgr:
			_main.dial_mgr.on_voice_call_ended()
		return

	trigger_dialogue(target_dlg_id)

# ══════════════════════════════════════════
#  查询接口
# ══════════════════════════════════════════
func get_character_ids() -> Array[String]:
	return _registry.get_character_ids()

func get_character(char_id: String) -> CommCharacter:
	return _registry.get_character(char_id)

func get_dialogue_ids() -> Array[String]:
	var result: Array[String] = []
	for key in _dialogues.keys():
		result.append(str(key))
	return result

func has_dialogue(dialogue_id: String) -> bool:
	return _dialogues.has(dialogue_id)

func get_dialogue_data(dialogue_id: String) -> Dictionary:
	return _dialogues.get(dialogue_id, {}) as Dictionary

func is_dialogue_active() -> bool:
	return is_active

func is_waiting_for_command() -> bool:
	if _player and _player._waiting:
		var cond: String = _player._wait_condition
		if cond.begins_with("command:") or cond.begins_with("open_file:") or cond.begins_with("enter_dir:"):
			return true
	return false

func is_waiting_for_choice() -> bool:
	return not _pending_choice_id.is_empty()


func get_current_dialogue_id() -> String:
	return _player.current_dialogue_id if _player else ""

# ══════════════════════════════════════════
#  ModAPI 扩展接口
# ══════════════════════════════════════════
func register_mod_character(char_id: String, config: Dictionary) -> bool:
	return _registry.register_mod_character(char_id, config)

func register_mod_dialogue(dialogue_id: String, dialogue_data: Dictionary) -> bool:
	if _dialogues.has(dialogue_id):
		push_warning("[CommManager] 对话已存在: %s" % dialogue_id)
		return false
	_dialogues[dialogue_id] = dialogue_data
	print("[CommManager] 模组注册对话: %s" % dialogue_id)
	return true

func unregister_mod_character(char_id: String) -> void:
	_registry.unregister_mod_character(char_id)

func unregister_mod_dialogue(dialogue_id: String) -> void:
	_dialogues.erase(dialogue_id)

# ══════════════════════════════════════════
#  清理
# ══════════════════════════════════════════
func cleanup() -> void:
	stop_dialogue()
	_dialogue_queue.clear()
	_pending_choice_id = ""
	_pending_incoming_call = ""
	if _call_handler:
		_call_handler.cleanup()
	if _ui:
		_ui.flush_history_to_disk()
		_ui.cleanup()
	_voice.cleanup()
	if _registry:
		_registry.cleanup()
	_active_character = null
	_dialogues.clear()
