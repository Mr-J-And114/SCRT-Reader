# ============================================================
# comm_manager.gd — 通讯系统主管理器
# 调度角色、对话、UI、语音、触发条件
# ── 新增：教程系统、选项分支、完成状态持久化
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

# 角色库 { "ava": CommCharacter, ... }
var _characters: Dictionary = {}
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

	_ui = CommUI.new()
	_ui.setup(main, theme)

	_player = CommDialoguePlayer.new()
	_player.setup(main, self)

	_voice = CommVoice.new()
	_voice.setup(main)

	# 信号连接
	_player.dialogue_started.connect(_on_dialogue_started)
	_player.dialogue_finished.connect(_on_dialogue_finished)
	_player.line_started.connect(_on_line_started)
	_player.line_finished.connect(_on_line_finished)
	_player.waiting_for_condition.connect(_on_waiting_for_condition)

	# 加载内置教程数据
	_load_tutorial_json()

## 从 manifest 加载通讯数据
func load_from_manifest(manifest: Dictionary) -> void:
	# 加载角色
	var chars: Dictionary = manifest.get("comm_characters", {}) as Dictionary
	for char_id in chars.keys():
		var char_config: Dictionary = chars[char_id] as Dictionary
		char_config["id"] = char_id
		var character := CommCharacter.new()
		character.load_from_config(char_config, _fs)
		_characters[char_id] = character
		print("[CommManager] 已加载角色: %s (%s)" % [char_id, character.display_name])

	# 如果没有角色，创建默认角色
	if _characters.is_empty():
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
		if not _characters.has(char_id):
			var char_config: Dictionary = chars[char_id] as Dictionary
			char_config["id"] = char_id
			var character := CommCharacter.new()
			character.load_from_config(char_config, null)
			_characters[char_id] = character
			print("[CommManager] 已加载教程角色: %s" % char_id)

	# 为 AVA 角色设置静态头像（从 res:// 加载）
	_setup_ava_portrait()
	_setup_researcher_portrait()     # ★ 新增
	# 加载 AVA 常态对话
	_load_ava_dialogues()

	# 加载教程对话
	var dialogues: Dictionary = data.get("comm_dialogues", {}) as Dictionary
	for dlg_id in dialogues.keys():
		if not _dialogues.has(dlg_id):
			_dialogues[dlg_id] = dialogues[dlg_id]
			print("[CommManager] 已加载教程对话: %s" % dlg_id)

## 为 AVA 角色加载 res:// 静态头像
func _setup_ava_portrait() -> void:
	if not _characters.has("ava"):
		return
	var tex_path: String = "res://images/character/ava-tmp.png"
	if not ResourceLoader.exists(tex_path):
		push_warning("[CommManager] AVA 头像不存在: " + tex_path)
		return
	var tex = load(tex_path)
	if tex is Texture2D:
		var ch: CommCharacter = _characters["ava"]
		# 将 Texture2D 转为 ImageTexture（如果需要）
		if tex is ImageTexture:
			ch.static_portrait = tex
		else:
			# CompressedTexture2D → ImageTexture
			var img: Image = tex.get_image()
			if img:
				ch.static_portrait = ImageTexture.create_from_image(img)
		ch.sprite_mode = CommCharacter.SpriteMode.STATIC
		print("[CommManager] AVA 头像已加载")

## 为 researcher 角色加载 res:// 静态头像
func _setup_researcher_portrait() -> void:
	if not _characters.has("researcher"):
		return
	var tex_path: String = "res://images/character/researcher-tmp.png"
	if not ResourceLoader.exists(tex_path):
		return
	var tex = load(tex_path)
	if tex is Texture2D:
		var ch: CommCharacter = _characters["researcher"]
		var img: Image = tex.get_image()
		if img:
			ch.static_portrait = ImageTexture.create_from_image(img)
		ch.sprite_mode = CommCharacter.SpriteMode.STATIC
		print("[CommManager] Researcher 头像已加载")

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
	# 加载对话（不覆盖已有的）
	var dialogues: Dictionary = data.get("comm_dialogues", {}) as Dictionary
	for dlg_id in dialogues.keys():
		if not _dialogues.has(dlg_id):
			_dialogues[dlg_id] = dialogues[dlg_id]
			print("[CommManager] 已加载AVA对话: %s" % dlg_id)


## 创建内置默认角色
func _create_default_character() -> void:
	var default_config: Dictionary = {
		"id": "op7",
		"name": "OPERATOR-7",
		"title": "Liaison Officer",
		"sprite_mode": "minimal",
		"default_expression": "neutral",
		"voice": {
			"tone": "square",
			"base_pitch": 0.9,
			"pitch_variance": 0.12,
			"speed": "normal",
		}
	}
	var character := CommCharacter.new()
	character.load_from_config(default_config, _fs)
	_characters["op7"] = character

## ★ 设置默认角色的静态头像（给只有一张图的情况）
func set_default_portrait(texture: ImageTexture) -> void:
	if _characters.has("op7"):
		var ch: CommCharacter = _characters["op7"]
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
		_pending_choice_id = ""

	var dialogue_data: Dictionary = _dialogues[dialogue_id]
	is_active = true

	# 确定初始角色
	var first_line: Dictionary = {}
	var lines: Array = dialogue_data.get("lines", []) as Array
	if lines.size() > 0:
		first_line = lines[0] as Dictionary

	var first_char_id: String = str(first_line.get("character", "op7"))
	print("[CommManager] 首行角色: ", first_char_id, " 角色库: ", _characters.keys())
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
		# 跳过教程相关的内部对话
		if dlg_id.begins_with("tutorial_"):
			continue
		var dlg_data: Dictionary = _dialogues[dlg_id]
		var lines: Array = dlg_data.get("lines", []) as Array
		# 从首行获取角色信息
		var first_char_id: String = ""
		if lines.size() > 0:
			first_char_id = str((lines[0] as Dictionary).get("character", ""))
		var char_name: String = first_char_id
		if _characters.has(first_char_id):
			char_name = _characters[first_char_id].display_name
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
	# ★ 主动停止不发 finished 信号（因为下面手动处理了清理）
	_player.stop_dialogue(true)
	if _active_character:
		_active_character.stop_speaking()
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
			# ★ 检查是否为拨号通话
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
			# 选项模式下屏蔽其他按键
			return true

		# 空格/回车：点击继续 或 跳过打字
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			# ★ 等待命令执行时：放行所有按键给终端
			if is_waiting_for_command():
				return false
			_player.on_click()
			return true

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not _pending_choice_id.is_empty():
				return true  # 选项模式不响应鼠标点击推进
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
## 处理选项选择
func _handle_choice_selection(choice_num: int) -> void:
	var choice_id: String = _pending_choice_id
	_pending_choice_id = ""
	match choice_id:
		"tutorial_ask":
			_handle_tutorial_choice(choice_num)
		_:
			_handle_generic_choice(choice_id, choice_num)



func _handle_tutorial_choice(choice_num: int) -> void:
	# ★ silent 停止：不触发 finished 流程
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
## 处理通用对话选项（非教程）
func _handle_generic_choice(choice_id: String, choice_num: int) -> void:
	# ★ 与 _handle_tutorial_choice 同策略：只停止播放器，不隐藏 UI
	_player.stop_dialogue(true)
	if _active_character:
		_active_character.stop_speaking()
	_pending_choice_id = ""
	# is_active 保持 true，UI 保持展开，实现无缝衔接

	# 构造分支对话 ID
	var base_id: String = choice_id
	var q_pos: int = choice_id.rfind("_q")
	if q_pos >= 0:
		base_id = choice_id.substr(0, q_pos)

	var branch_id: String = base_id + "_a" + str(choice_num)

	# 尝试多种命名约定
	var candidates: Array[String] = [
		branch_id,									# test_choice_a1
		base_id + "_" + str(choice_num),			  # test_choice_1
		choice_id + "_" + str(choice_num),			# test_choice_q1_1
		base_id + "_ready_" + str(choice_num),		# test_all_ready_1
	]

	for candidate in candidates:
		if _dialogues.has(candidate):
			trigger_dialogue(candidate)
			return

	# 没找到分支对话，输出提示
	if _main:
		var muted: String = _main.theme_manager.muted_hex if _main.theme_manager else "#888888"
		_main.append_output("[color=" + muted + "]（选择了选项 " + str(choice_num) + "，但没有对应的分支对话）[/color]\n", false)

# ══════════════════════════════════════════
#  角色控制（内部，供 dialogue_player 调用）
# ══════════════════════════════════════════
func _set_active_character(char_id: String) -> void:
	if not _characters.has(char_id):
		if _characters.has("op7"):
			char_id = "op7"
		elif _characters.has("ava"):
			char_id = "ava"
		elif _characters.size() > 0:
			char_id = _characters.keys()[0]
		else:
			return
	_active_character = _characters[char_id]
	_voice.apply_config(_active_character.voice_config)
	_ui.set_character(_active_character)

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
	# 精确匹配
	notify_condition("command", cmd_name)
	# 前缀匹配
	if not cmd_args.is_empty():
		var full_cmd: String = cmd_name
		var str_args: PackedStringArray = PackedStringArray()
		for a in cmd_args:
			str_args.append(str(a))
		full_cmd += " " + " ".join(str_args)
		_player.notify_condition_met("command:" + full_cmd)
	# ★ 命令执行后，如果对话框是自动收起的，自动展开
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
	# ★ 始终驱动 UI（即使对话未激活，按钮位置也需要更新）
	if _ui:
		_ui.process(delta)
	if not is_active:
		return
	_player.process(delta)
	if _active_character:
		_active_character.process(delta)
	_ui.update_text(_player.get_displayed_text())


# ══════════════════════════════════════════
#  信号回调
# ══════════════════════════════════════════
func _on_dialogue_started(dialogue_id: String) -> void:
	# ★ 设置当前对话 ID，用于历史分组
	_ui.set_current_dialogue_id(dialogue_id)
	comm_started.emit(dialogue_id)


func _on_dialogue_finished(dialogue_id: String) -> void:
	# 对话自然结束时将历史写入磁盘
	_ui.flush_history_to_disk()
	_ui.clear_cards()

	# ★ 记录是否为拨号通话（在 is_active 置 false 之前判断）
	var is_dial_call: bool = _main.dial_mgr != null and _main.dial_mgr.is_active()

	_ui.hide()
	is_active = false
	_mark_dialogue_completed(dialogue_id)
	comm_finished.emit(dialogue_id)

	if is_dial_call:
		# ★ 延迟 1.0 秒，等对话框收起动画完全结束后再播放挂机音
		if _main and _main.get_tree():
			_main.get_tree().create_timer(1.0).timeout.connect(func():
				if _main.dial_mgr and _main.dial_mgr.is_active():
					_main.dial_mgr.on_voice_call_ended()
			)

	# 检查队列中的后续对话
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
	# ★ 新行开始时确保对话框展开
	if _ui._collapsed:
		_ui.auto_expand()

func _on_line_finished(_line_index: int) -> void:
	# ★ 记录历史对话
	if _active_character and _player:
		var displayed: String = _player.get_displayed_text()
		if not displayed.is_empty():
			_ui.add_history_line(_active_character.display_name, displayed)
	if _player._click_to_continue:
		_ui.show_continue_prompt(true)

func _on_waiting_for_condition(condition: String) -> void:
	# ── 选项条件 ──
	if condition.begins_with("choice:"):
		_pending_choice_id = condition.substr(7)
		_ui.show_wait_prompt_custom("按数字键选择 | ESC 跳过")
		return

	# ── 需要用户操作的条件：自动收起对话框 ──
	if condition.begins_with("command:") or condition.begins_with("open_file:") or condition.begins_with("enter_dir:"):
		_ui.show_wait_prompt(condition)
		_ui.auto_collapse()
		return

	_ui.show_wait_prompt(condition)

	# timer 自动定时器
	if condition.begins_with("timer:"):
		var seconds: float = float(condition.substr(6))
		if seconds > 0.0 and _main:
			_main.get_tree().create_timer(seconds).timeout.connect(func():
				_player.notify_condition_met(condition)
			)

# ══════════════════════════════════════════
#  完成状态持久化
# ══════════════════════════════════════════

## 标记对话为已完成
func _mark_dialogue_completed(dialogue_id: String) -> void:
	if dialogue_id.is_empty():
		return
	# ★ tutorial_ask 只是询问，不标记为完成
	if dialogue_id == "tutorial_ask":
		return
	_completed_dialogues[dialogue_id] = true
	_save_completed()


## 查询对话是否已完成
func is_dialogue_completed(dialogue_id: String) -> bool:
	return _completed_dialogues.has(dialogue_id)

## 登录后重新加载完成状态
func reload_user_data() -> void:
	_load_completed()

func _get_save_path() -> String:
	if _main and _main.user_mgr and _main.user_mgr.is_logged_in:
		var username: String = _main.user_mgr.get_username()
		# ★ 保存到 saves/用户名/ 目录下，与其他存档一致
		if _main.save_mgr:
			var user_dir: String = _main.save_mgr.get_game_root_dir() + "/" + username
			# 确保目录存在
			if not DirAccess.dir_exists_absolute(user_dir):
				DirAccess.make_dir_recursive_absolute(user_dir)
			return user_dir + "/comm_progress.cfg"
		# 回退：使用 user:// 
		return "user://comm_" + username + ".cfg"
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
## 从磁盘 manifest 加载通讯角色和对话（不覆盖教程数据）
var _disc_dialogue_ids: Array[String] = []
var _disc_character_ids: Array[String] = []

func load_disc_dialogues(manifest_data: Dictionary) -> void:
	# 加载磁盘角色
	var chars_data: Dictionary = manifest_data.get("comm_characters", {}) as Dictionary
	for char_id in chars_data.keys():
		if _characters.has(char_id):
			print("[CommManager] 磁盘角色覆盖已有角色: ", char_id)
		var char_dict: Dictionary = chars_data[char_id] as Dictionary
		char_dict["id"] = char_id
		var character := CommCharacter.new()
		character.load_from_config(char_dict, null)
		# 加载头像（从虚拟文件系统中查找）
		_load_character_portrait(character, char_dict)
		_characters[char_id] = character
		_disc_character_ids.append(char_id)
		print("[CommManager] 磁盘角色已加载: ", char_id)
	
	# 加载磁盘对话
	var dialogues_data: Dictionary = manifest_data.get("comm_dialogues", {}) as Dictionary
	for dlg_id in dialogues_data.keys():
		if _dialogues.has(dlg_id):
			print("[CommManager] 磁盘对话覆盖已有对话: ", dlg_id)
		_dialogues[dlg_id] = dialogues_data[dlg_id]
		_disc_dialogue_ids.append(dlg_id)
		print("[CommManager] 磁盘对话已加载: ", dlg_id)

## 从虚拟文件系统或资源路径加载角色头像
func _load_character_portrait(character: CommCharacter, char_dict: Dictionary) -> void:
	var portrait_path: String = str(char_dict.get("portrait", ""))
	if portrait_path.is_empty():
		return
	
	# 尝试从虚拟文件系统加载（磁盘内资源）
	if _main and _main.fs:
		var normalized: String = _main.fs.normalize_path(portrait_path)
		var binary: PackedByteArray = _main.fs.get_binary_data(normalized)
		if not binary.is_empty():
			var img := Image.new()
			var ext: String = portrait_path.get_extension().to_lower()
			var err: Error = ERR_FILE_UNRECOGNIZED
			match ext:
				"png":
					err = img.load_png_from_buffer(binary)
				"jpg", "jpeg":
					err = img.load_jpg_from_buffer(binary)
				"webp":
					err = img.load_webp_from_buffer(binary)
			if err == OK:
				character.static_portrait = ImageTexture.create_from_image(img)
				print("[CommManager] 磁盘角色头像已加载: ", character.id)
				return
	
	# 尝试从 res:// 路径加载
	if portrait_path.begins_with("res://") and ResourceLoader.exists(portrait_path):
		var tex = load(portrait_path)
		if tex is Texture2D:
			character.static_portrait = tex
			print("[CommManager] 角色头像已加载(res): ", character.id)


## 卸载磁盘对话数据（弹出磁盘时调用）
func unload_disc_dialogues() -> void:
	# 如果当前正在播放磁盘对话，先停止
	var active_dlg: String = _player.current_dialogue_id if _player else ""
	if is_active and active_dlg in _disc_dialogue_ids:
		stop_dialogue()
	
	# 移除磁盘对话
	for dlg_id in _disc_dialogue_ids:
		_dialogues.erase(dlg_id)
	_disc_dialogue_ids.clear()
	
	# 移除磁盘角色
	for char_id in _disc_character_ids:
		_characters.erase(char_id)
	_disc_character_ids.clear()
	
	print("[CommManager] 磁盘通讯数据已卸载")



## 获取当前对话 ID（供外部查询）
var current_dialogue_id: String:
	get:
		return _player.current_dialogue_id if _player else ""



# ══════════════════════════════════════════
#  教程系统入口
# ══════════════════════════════════════════
func try_trigger_tutorial() -> void:
	reload_user_data()
	# 检查教程是否完成
	var tutorial_done: bool = is_dialogue_completed("tutorial_main") or \
							  is_dialogue_completed("tutorial_skip")
	if not tutorial_done:
		# 教程未完成，触发教程
		if not _dialogues.has("tutorial_ask"):
			push_warning("[CommManager] tutorial_ask 对话不存在！检查 tutorial.json")
			return
		if _main:
			_main.get_tree().create_timer(1.5).timeout.connect(func():
				trigger_dialogue("tutorial_ask")
			)
	else:
		# 教程已完成，触发 AVA 登录欢迎
		_try_ava_login_welcome()

## 教程完成后触发 AVA 登录欢迎（每次登录一次）
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

## 处理 trigger 动作字符串 "comm:dialogue_id"
func handle_trigger_action(action: String) -> bool:
	if not action.begins_with("comm:"):
		return false
	var dialogue_id: String = action.substr(5).strip_edges()
	return trigger_dialogue(dialogue_id)

## 检查自动触发的对话（首次启动等）
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
				_show_incoming_call(dlg_id, dlg)

## 来电提示
func _show_incoming_call(dialogue_id: String, dlg_data: Dictionary) -> void:
	if _main == null:
		return
	_pending_incoming_call = dialogue_id
	var lines: Array = dlg_data.get("lines", []) as Array
	var caller_name: String = "UNKNOWN"
	if lines.size() > 0:
		var first_char_id: String = str(lines[0].get("character", "op7"))
		if _characters.has(first_char_id):
			caller_name = _characters[first_char_id].display_name
	var c_hex: String = _T.warning_hex if _T else "#ffff00"
	var m_hex: String = _T.muted_hex if _T else "#888888"
	_main.append_output("\n[color=" + c_hex + "]╔══════════════════════════════════╗[/color]\n", false)
	_main.append_output("[color=" + c_hex + "]║  ☎ INCOMING COMM — " + caller_name + "[/color]\n", false)
	_main.append_output("[color=" + m_hex + "]║  输入 [color=" + c_hex + "]comm answer[/color] 接听通讯[/color]\n", false)
	_main.append_output("[color=" + c_hex + "]╚══════════════════════════════════╝[/color]\n\n", false)

## 来电等待 ID
var _pending_incoming_call: String = ""

# ══════════════════════════════════════════
#  主动通讯系统（玩家呼叫联络员）
# ══════════════════════════════════════════

## 判断对话是否可被用户通过 comm 命令触发
## 规则：排除教程内部对话和选项分支对话，其余均可调用
func _is_user_callable(dlg_id: String) -> bool:
	# 教程内部对话不可手动调用
	if dlg_id.begins_with("tutorial_"):
		return false
	# 检查对话数据是否存在
	if not _dialogues.has(dlg_id):
		return false
	var dlg: Dictionary = _dialogues[dlg_id] as Dictionary
	# 明确标记为不可调用的对话
	if dlg.has("callable") and not dlg.get("callable", true):
		return false
	# 没有 description 且没有 callable=true 的对话视为分支/内部对话
	# （分支对话通常只有 lines，没有 description）
	var has_description: bool = not str(dlg.get("description", "")).is_empty()
	var explicitly_callable: bool = dlg.get("callable", false)
	# 有描述 或 明确标记callable 或 以comm_开头 → 可调用
	if has_description or explicitly_callable or dlg_id.begins_with("comm_"):
		return true
	return false


## comm 命令入口
## 用法: comm			→ 列出通讯状态与号码簿摘要
##	   comm answer	 → 接听来电
##	   comm phonebook  → 查看号码簿
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

	# ── 有参数 ──
	if not args.is_empty():
		var target_id: String = str(args[0]).strip_edges()

		# comm phonebook / pb → 号码簿
		if target_id == "phonebook" or target_id == "pb":
			_show_phonebook()
			return

		# comm answer → 接听来电
		if target_id == "answer":
			if _pending_incoming_call.is_empty():
				_main.append_output("[color=" + m + "]当前没有待接听的通讯。[/color]\n", false)
			else:
				var call_id: String = _pending_incoming_call
				_pending_incoming_call = ""
				trigger_dialogue(call_id)
			return

		# comm <号码格式> → 通过 dial_manager 拨号
		if _main.dial_mgr != null and _main.dial_mgr.is_number_format(target_id):
			if _main.dial_mgr.is_active():
				_main.append_output("[color=" + m + "]线路忙，请稍后再试。[/color]\n", false)
				return
			_main.dial_mgr.dial(target_id)
			return

		# 其他参数 → 提示使用 dial 命令
		_main.append_output("[color=" + e + "]未知参数: " + target_id + "[/color]\n", false)
		_main.append_output("[color=" + m + "]用法: comm / comm answer / comm phonebook[/color]\n", false)
		_main.append_output("[color=" + m + "]如需联络，请使用 dial <号码> 拨号呼叫。[/color]\n", false)
		return

	# ── 无参数：显示通讯系统概览 ──
	_main.append_output("\n[color=" + p + "]═══════════ 通讯系统 ═══════════[/color]\n\n", false)

	# 待接听来电
	if not _pending_incoming_call.is_empty():
		_main.append_output("  [color=" + w + "]★ 待接听来电[/color]  [color=" + m + "]输入 comm answer 接听[/color]\n\n", false)

	# 显示号码簿摘要
	if _main.dial_mgr:
		var all_numbers: Array[String] = _main.dial_mgr.get_all_numbers()
		if not all_numbers.is_empty():
			_main.append_output("  [color=" + p + "]已知号码:[/color]\n", false)
			# 最多显示 5 个，超出提示查看号码簿
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
	_main.append_output("[color=" + m + "]查看号码簿: phonebook[/color]\n", false)
	if not _pending_incoming_call.is_empty():
		_main.append_output("[color=" + m + "]接听来电: comm answer[/color]\n", false)


# ══════════════════════════════════════════
#  拨号系统集成
# ══════════════════════════════════════════

## ★ 显示号码簿
func _show_phonebook() -> void:
	if _main.dial_mgr:
		var text: String = _main.dial_mgr.get_phonebook_text()
		_main.append_output(text, false)
	else:
		var m: String = _T.muted_hex if _T else "#888888"
		_main.append_output("[color=" + m + "]拨号系统未初始化。[/color]\n", false)

## ★ 由 DialManager 调用：拨号流程接通后启动语音对话（跳过拨号动画）
func start_dialogue_from_dial(character_id: String) -> void:
	# 查找该角色的可用对话
	var target_dlg_id: String = ""

	# 策略1：查找以角色名为前缀的对话（如 ava_chat, ava_greeting）
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

	# 策略2：查找首行角色匹配的对话
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
		var m: String = _T.muted_hex if _T else "#888888"
		_main.append_output("[color=" + m + "]联络员 " + character_id + " 当前不可用。[/color]\n", false)
		if _main.dial_mgr:
			_main.dial_mgr.on_voice_call_ended()
		return

	trigger_dialogue(target_dlg_id)

# ══════════════════════════════════════════
#  查询接口
# ══════════════════════════════════════════
func get_character_ids() -> Array[String]:
	var result: Array[String] = []
	for key in _characters.keys():
		result.append(str(key))
	return result

func get_character(char_id: String) -> CommCharacter:
	return _characters.get(char_id) as CommCharacter

func get_dialogue_ids() -> Array[String]:
	var result: Array[String] = []
	for key in _dialogues.keys():
		result.append(str(key))
	return result

func is_dialogue_active() -> bool:
	return is_active

## 查询是否正在等待用户执行操作（命令/打开文件/进入目录），不应阻断终端输入
func is_waiting_for_command() -> bool:
	if _player and _player._waiting:
		var cond: String = _player._wait_condition
		if cond.begins_with("command:") or cond.begins_with("open_file:") or cond.begins_with("enter_dir:"):
			return true
	return false

## 查询是否正在等待选项选择
func is_waiting_for_choice() -> bool:
	return not _pending_choice_id.is_empty()


func get_current_dialogue_id() -> String:
	return _player.current_dialogue_id if _player else ""

# ══════════════════════════════════════════
#  ModAPI 扩展接口
# ══════════════════════════════════════════
func register_mod_character(char_id: String, config: Dictionary) -> bool:
	if _characters.has(char_id):
		push_warning("[CommManager] 角色已存在: %s" % char_id)
		return false
	config["id"] = char_id
	var character := CommCharacter.new()
	character.load_from_config(config, _fs)
	_characters[char_id] = character
	print("[CommManager] 模组注册角色: %s" % char_id)
	return true

func register_mod_dialogue(dialogue_id: String, dialogue_data: Dictionary) -> bool:
	if _dialogues.has(dialogue_id):
		push_warning("[CommManager] 对话已存在: %s" % dialogue_id)
		return false
	_dialogues[dialogue_id] = dialogue_data
	print("[CommManager] 模组注册对话: %s" % dialogue_id)
	return true

func unregister_mod_character(char_id: String) -> void:
	_characters.erase(char_id)

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
	if _ui:
		_ui.flush_history_to_disk()
		_ui.cleanup()
	_voice.cleanup()
	_characters.clear()
	_dialogues.clear()
	_active_character = null
