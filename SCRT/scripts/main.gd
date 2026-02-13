# main.gd
extends Control

# ══════════════════════════════════════════
#  模块引用
# ══════════════════════════════════════════
var fs: FileSystem = FileSystem.new()
var save_mgr: SaveManager = SaveManager.new()
var tw: Typewriter = null
var T = null
var story_loader = null
var cmd_handler = null
var disc_mgr = null
var user_mgr = null
var crtml = null

# ══════════════════════════════════════════
#  UI 节点
# ══════════════════════════════════════════
@onready var output_text: RichTextLabel = $MainContent/OutputArea/OutputText
@onready var scroll_container: ScrollContainer = $MainContent/OutputArea
@onready var input_field: LineEdit = $MainContent/InputFrame/InputArea/InputField
@onready var path_label: Label = $MainContent/StatusFrame/StatusBar/PathLabel
@onready var mail_icon: Label = $MainContent/StatusFrame/StatusBar/MailIcon
@onready var status_frame: PanelContainer = $MainContent/StatusFrame
@onready var input_frame: PanelContainer = $MainContent/InputFrame
var background: TextureRect = null

# ══════════════════════════════════════════
#  状态变量
# ══════════════════════════════════════════
var _desktop_mode: bool = true
var current_path: String = "/"
var read_files: Array[String] = []
var unlocked_passwords: Array[String] = []
var story_id: String = ""
var story_manifest: Dictionary = {}
var current_story_index: int = -1
var has_new_mail: bool = false

var _password_mode: bool = false
var _password_target_path: String = ""
var _file_password_mode: bool = false
var _file_password_target: String = ""
var _file_password_filename: String = ""

var _command_running: bool = false

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func _ready() -> void:
	ThemeManager.init("phosphor_green")
	T = ThemeManager.current
	tw = Typewriter.new()
	tw.name = "Typewriter"
	add_child(tw)
	tw.setup(output_text, scroll_container)
	story_loader = StoryLoader.new()
	user_mgr = UserManager.new()
	user_mgr.setup(T)
	crtml = CrtmlParser.new()
	crtml.setup(T)
	disc_mgr = DiscManager.new()
	disc_mgr.setup(self, fs, T, tw, story_loader, save_mgr)
	cmd_handler = CommandHandler.new()
	cmd_handler.setup(self, fs, T, tw, disc_mgr, user_mgr, crtml)
	background = UIManager.setup_background(self, save_mgr.get_game_root_dir())
	UIManager.setup_main_content(self, $MainContent)
	UIManager.setup_all_styles(status_frame, path_label, mail_icon,
		input_frame, input_field, output_text, scroll_container)
	UIManager.setup_crt_effect($CRTEffect)
	UIManager.setup_custom_cursor(self)
	input_field.context_menu_enabled = false
	output_text.meta_clicked.connect(_on_meta_clicked)
	mail_icon.text = "[Mail]"
	input_field.text_submitted.connect(_on_input_submitted)
	disc_mgr.scan_stories()
	disc_mgr.show_desktop_welcome()
	_update_status_bar()
	input_field.grab_focus()

# ══════════════════════════════════════════
#  输入提交
# ══════════════════════════════════════════
func _on_input_submitted(text: String) -> void:
	var raw: String = text.strip_edges()
	if raw.is_empty():
		return
	if _command_running:
		return
	append_output("> " + raw + "\n", false)
	input_field.text = ""
	input_field.grab_focus()
	# 直接调用，不 await。_run_command 自己管理异步。
	_run_command(raw)




func _run_command(raw: String) -> void:
	_command_running = true
	await cmd_handler.execute(raw)
	_command_running = false
	# 恢复焦点：不用 await，用 call_deferred 确保在帧末执行
	_refocus_input.call_deferred()

func _refocus_input() -> void:
	input_field.grab_focus()



# ══════════════════════════════════════════
#  输入事件处理
# ══════════════════════════════════════════
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				scroll_container.scroll_vertical -= 60
				get_viewport().set_input_as_handled()
				return
			MOUSE_BUTTON_WHEEL_DOWN:
				scroll_container.scroll_vertical += 60
				get_viewport().set_input_as_handled()
				return
			MOUSE_BUTTON_RIGHT:
				var selected_text: String = output_text.get_selected_text()
				if not selected_text.is_empty():
					DisplayServer.clipboard_set(selected_text)
					output_text.deselect()
					_show_copy_toast()
				input_field.grab_focus()
				get_viewport().set_input_as_handled()
				return
			MOUSE_BUTTON_LEFT:
				var mouse_pos: Vector2 = event.position
				var output_rect: Rect2 = output_text.get_global_rect()
				if not output_rect.has_point(mouse_pos):
					input_field.grab_focus()
				return
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_pos: Vector2 = event.position
			var output_rect: Rect2 = output_text.get_global_rect()
			if not output_rect.has_point(mouse_pos):
				input_field.grab_focus()
			return
	# --- 键盘事件 ---
	if not event is InputEventKey or not event.pressed:
		return
	# 命令执行中：只允许打字机跳过，其他一律放行（不拦截回车）
	if _command_running:
		if tw.is_typing and event.keycode in [KEY_SPACE, KEY_ESCAPE]:
			tw.skip()
			get_viewport().set_input_as_handled()
			return
		# 不 return！让回车等按键正常传递给 LineEdit
		# 但 _on_input_submitted 中有 _command_running 检查，不会重复执行
	# 确保输入框有焦点
	if not input_field.has_focus():
		input_field.grab_focus()
	# 打字机跳过
	if tw.is_typing and event.keycode in [KEY_SPACE, KEY_ESCAPE]:
		tw.skip()
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_UP:
			input_field.text = cmd_handler.history_up()
			input_field.caret_column = input_field.text.length()
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			input_field.text = cmd_handler.history_down()
			input_field.caret_column = input_field.text.length()
			get_viewport().set_input_as_handled()
		KEY_TAB:
			_handle_tab_completion()
			get_viewport().set_input_as_handled()
		KEY_PAGEUP:
			scroll_container.scroll_vertical -= 100
			get_viewport().set_input_as_handled()
		KEY_PAGEDOWN:
			scroll_container.scroll_vertical += 100
			get_viewport().set_input_as_handled()


# ══════════════════════════════════════════
#  Tab 补全
# ══════════════════════════════════════════
func _handle_tab_completion() -> void:
	var current_text: String = input_field.text
	if current_text.strip_edges().is_empty():
		return
	var ends_with_space: bool = current_text.ends_with(" ")
	var parts := current_text.split(" ", false)
	if parts.size() == 1 and ends_with_space:
		var cmd: String = parts[0].to_lower()
		if cmd in ["cd", "open", "cat"]:
			var children := fs.get_children_at_path(current_path)
			if children.size() > 0:
				var display: Array[String] = []
				for child in children:
					var child_path := fs.join_path(current_path, child)
					var node := fs.get_node_at_path(child_path)
					if node == null:
						continue
					if cmd == "cd" and node.type == "folder":
						display.append(child + "/")
					elif cmd in ["open", "cat"] and node.type == "file":
						display.append(child)
					elif cmd not in ["cd"]:
						display.append(child)
				if display.size() == 1:
					input_field.text = cmd + " " + display[0]
					input_field.caret_column = input_field.text.length()
				elif display.size() > 0:
					append_output("[color=" + T.muted_hex + "]可选项: " + " | ".join(display) + "[/color]\n", false)
		return
	var completions: Array[String] = cmd_handler.get_completions(current_text)
	if completions.size() == 1:
		input_field.text = completions[0]
		if not input_field.text.ends_with(" "):
			input_field.text += " "
		input_field.caret_column = input_field.text.length()
	elif completions.size() > 1:
		append_output("[color=" + T.muted_hex + "]" + "  ".join(completions) + "[/color]\n", false)

# ══════════════════════════════════════════
#  输出工具
# ══════════════════════════════════════════
func append_output(text: String, use_typewriter: bool = false) -> void:
	if use_typewriter:
		tw.append(text, true)
	else:
		output_text.append_text(text)
	_scroll_to_bottom.call_deferred()


func _scroll_to_bottom() -> void:
	# 优先用 scroll_container 的滚动条（因为 output_text 在其内部）
	var sc_vscroll := scroll_container.get_v_scroll_bar()
	if sc_vscroll:
		scroll_container.scroll_vertical = int(sc_vscroll.max_value)
	# 备用：也操作 output_text 自身的滚动条
	var rt_vscroll := output_text.get_v_scroll_bar()
	if rt_vscroll:
		rt_vscroll.value = rt_vscroll.max_value



# ══════════════════════════════════════════
#  每帧处理
# ══════════════════════════════════════════
func _process(_delta: float) -> void:
	tw.process_scroll()
	if tw.is_typing:
		_scroll_to_bottom()


# ══════════════════════════════════════════
#  复制提示
# ══════════════════════════════════════════
func _show_copy_toast() -> void:
	output_text.append_text("[color=" + T.muted_hex + "][已复制到剪贴板][/color]\n")
	_scroll_to_bottom.call_deferred()



# ══════════════════════════════════════════
#  超链接处理
# ══════════════════════════════════════════
func _on_meta_clicked(meta: Variant) -> void:
	var meta_str: String = str(meta)
	if meta_str.begins_with("cmd://"):
		var cmd: String = meta_str.substr(6)
		output_text.append_text("\n> " + cmd + "\n")
		_run_command(cmd)
		return
	if meta_str.begins_with("file://"):
		var file_path: String = meta_str.substr(7)
		output_text.append_text("\n> open " + file_path + "\n")
		_run_command("open " + file_path)
		return

# ══════════════════════════════════════════
#  状态栏
# ══════════════════════════════════════════
func _update_status_bar() -> void:
	if _desktop_mode:
		path_label.text = "SCP TERMINAL | 桌面模式 | 磁盘: " + str(disc_mgr.available_stories.size())
	else:
		var story_dict: Dictionary = story_manifest.get("story", {}) as Dictionary
		var title: String = str(story_dict.get("title", "未知"))
		path_label.text = "磁盘: " + title + " | 路径: " + current_path + " | 等级: " + str(fs.player_clearance)
	if has_new_mail:
		mail_icon.text = "[Mail NEW]"
	else:
		mail_icon.text = "[Mail]"

# ══════════════════════════════════════════
#  欢迎信息
# ══════════════════════════════════════════
func _show_welcome_message() -> void:
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var story_dict: Dictionary = story_manifest.get("story", {}) as Dictionary
	var title: String = str(story_dict.get("title", "未知"))
	var box: String = fs.build_box(["ACCESS GRANTED", title] as Array[String], p)
	append_output(box + "\n", false)
	append_output("[color=" + m + "]输入 help 查看可用命令。[/color]\n\n", false)
