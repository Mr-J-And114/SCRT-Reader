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
@warning_ignore("unused_private_class_variable")
var _password_target_path: String = ""
var _file_password_mode: bool = false
var _file_password_target: String = ""
var _file_password_filename: String = ""
var _command_running: bool = false

# 滚动控制（用帧计数代替 await，避免协程堆积）
var _scroll_pending_frames: int = 0

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func _ready() -> void:
	# 初始化主题
	ThemeManager.init("phosphor_green")
	T = ThemeManager.current

	# 初始化打字机
	tw = Typewriter.new()
	tw.name = "Typewriter"
	add_child(tw)
	tw.setup(output_text, scroll_container)

	# 初始化各模块
	story_loader = StoryLoader.new()
	user_mgr = UserManager.new()
	user_mgr.setup(T)
	crtml = CrtmlParser.new()
	crtml.setup(T)
	disc_mgr = DiscManager.new()
	disc_mgr.setup(self, fs, T, tw, story_loader, save_mgr)
	cmd_handler = CommandHandler.new()
	cmd_handler.setup(self, fs, T, tw, disc_mgr, user_mgr, crtml)

	# UI 初始化
	background = UIManager.setup_background(self, save_mgr.get_game_root_dir())
	UIManager.setup_main_content(self, $MainContent)
	UIManager.setup_all_styles(status_frame, path_label, mail_icon,
		input_frame, input_field, output_text, scroll_container)
	UIManager.setup_crt_effect($CRTEffect)
	UIManager.setup_custom_cursor(self)

	# 输入框设置
	input_field.context_menu_enabled = false
	input_field.focus_mode = Control.FOCUS_ALL
	input_field.focus_next = input_field.get_path()
	input_field.focus_previous = input_field.get_path()

	# 闪烁光标
	input_field.caret_blink = true
	input_field.caret_blink_interval = 0.5
	# 方块光标：通过主题覆盖加大光标宽度
	input_field.add_theme_constant_override("caret_width", 8)

	# 注意：不设置 clear_on_text_submitted，该属性在 Godot 4.6 中不存在，清空逻辑已在 _on_input_submitted 中手动处理

	# 信号连接（只连接一次！）
	input_field.text_submitted.connect(_on_input_submitted)
	output_text.meta_clicked.connect(_on_meta_clicked)
	input_field.focus_entered.connect(_on_input_focus_entered)
	input_field.focus_exited.connect(_on_input_focus_exited)

	# 初始 placeholder（启动时输入框尚未获得焦点）
	input_field.placeholder_text = "按 Enter 输入命令..."

	# 初始状态
	mail_icon.text = "[Mail]"
	disc_mgr.scan_stories(true)  # 静默扫描，不输出文字（由 show_desktop_welcome 统一显示）
	_desktop_mode = true
	_update_status_bar()
	disc_mgr.show_desktop_welcome()
	input_field.grab_focus()

# ══════════════════════════════════════════
#  输入框焦点控制 placeholder 显示
# ══════════════════════════════════════════
func _on_input_focus_entered() -> void:
	# 获得焦点时隐藏提示文字，只显示光标
	input_field.placeholder_text = ""

func _on_input_focus_exited() -> void:
	# 失去焦点时根据当前模式恢复提示文字
	if _password_mode:
		input_field.placeholder_text = "请输入密码..."
	elif _file_password_mode:
		input_field.placeholder_text = "请输入文件密码..."
	else:
		input_field.placeholder_text = "按 Enter 输入命令..."

## 获取当前模式下应显示的 placeholder（供外部调用）
func _get_default_placeholder() -> String:
	if _password_mode:
		return "请输入密码..."
	elif _file_password_mode:
		return "请输入文件密码..."
	else:
		return "按 Enter 输入命令..."

# ══════════════════════════════════════════
#  回车提交（由 text_submitted 信号触发，仅此一处）
# ══════════════════════════════════════════
func _on_input_submitted(_text: String) -> void:
	# 立刻取出文本并清空
	var raw: String = input_field.text.strip_edges()
	input_field.text = ""
	input_field.clear()
	input_field.grab_focus()

	if raw.is_empty():
		return
	if _command_running:
		return

	# 打字机正在打字时，跳过打字而不是执行命令
	if tw.is_typing:
		tw.skip()
		return

	# 密码模式处理
	if _password_mode:
		_password_mode = false
		# 焦点在输入框上，placeholder 为空（由 focus_entered 控制）
		output_text.append_text("> " + "*".repeat(raw.length()) + "\n")
		if raw.to_lower() == "cancel":
			append_output("[color=" + T.muted_hex + "]已取消密码输入。[/color]\n", false)
			return
		cmd_handler._verify_password(raw)
		_request_scroll()
		return

	# 文件密码模式处理
	if _file_password_mode:
		_file_password_mode = false
		# 焦点在输入框上，placeholder 为空（由 focus_entered 控制）
		output_text.append_text("> " + "*".repeat(raw.length()) + "\n")
		if raw.to_lower() == "cancel":
			append_output("[color=" + T.muted_hex + "]已取消文件密码输入。[/color]\n", false)
			_file_password_target = ""
			_file_password_filename = ""
			return
		await cmd_handler.verify_file_password(raw)
		_request_scroll()
		return

	# 正常命令执行
	append_output("> " + raw + "\n", false)
	_request_scroll()
	_run_command(raw)

func _run_command(raw: String) -> void:
	_command_running = true
	await cmd_handler.execute(raw)
	_command_running = false
	_refocus_input.call_deferred()

func _refocus_input() -> void:
	input_field.grab_focus()

# ══════════════════════════════════════════
#  输入事件处理（不处理回车！）
# ══════════════════════════════════════════
func _input(event: InputEvent) -> void:
	# --- 鼠标按下事件 ---
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

	# --- 鼠标释放事件 ---
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

	if not input_field.has_focus():
		input_field.grab_focus()

	# 打字机播放中：空格或ESC跳过
	if tw.is_typing and event.keycode in [KEY_SPACE, KEY_ESCAPE]:
		tw.skip()
		get_viewport().set_input_as_handled()
		return

	# ★ 不处理 KEY_ENTER，回车完全由 text_submitted 信号处理
	match event.keycode:
		KEY_UP:
			var prev_cmd: String = cmd_handler.history_up()
			if not prev_cmd.is_empty():
				input_field.text = prev_cmd
				input_field.caret_column = input_field.text.length()
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			var next_cmd: String = cmd_handler.history_down()
			input_field.text = next_cmd
			input_field.caret_column = input_field.text.length()
			get_viewport().set_input_as_handled()
		KEY_PAGEUP:
			scroll_container.scroll_vertical -= 100
			get_viewport().set_input_as_handled()
		KEY_PAGEDOWN:
			scroll_container.scroll_vertical += 100
			get_viewport().set_input_as_handled()
		KEY_TAB:
			_handle_tab_complete()
			get_viewport().set_input_as_handled()

# ══════════════════════════════════════════
#  Tab 自动补全
# ══════════════════════════════════════════
func _handle_tab_complete() -> void:
	var current_text: String = input_field.text
	if current_text.strip_edges().is_empty():
		return

	var completions: Array[String] = cmd_handler.get_completions(current_text)
	if completions.is_empty():
		return

	if completions.size() == 1:
		input_field.text = completions[0] + " "
		input_field.caret_column = input_field.text.length()
	else:
		var display_items: Array[String] = []
		for c in completions:
			var parts: PackedStringArray = c.split(" ", false)
			if parts.size() > 0:
				display_items.append(parts[-1])
			else:
				display_items.append(c)
		var hint_text: String = "\n[color=" + T.muted_hex + "]可选项: " + " | ".join(display_items) + "[/color]"
		output_text.append_text(hint_text)
		_request_scroll()
		var common: String = _find_common_prefix(completions)
		if common.length() > current_text.length():
			input_field.text = common
			input_field.caret_column = input_field.text.length()

func _find_common_prefix(strings: Array[String]) -> String:
	if strings.is_empty():
		return ""
	if strings.size() == 1:
		return strings[0]
	var prefix: String = strings[0]
	for i in range(1, strings.size()):
		while not strings[i].to_lower().begins_with(prefix.to_lower()):
			prefix = prefix.substr(0, prefix.length() - 1)
			if prefix.is_empty():
				return ""
	return prefix

# ══════════════════════════════════════════
#  输出工具
# ══════════════════════════════════════════
func append_output(text: String, use_typewriter: bool = false) -> void:
	if use_typewriter:
		tw.append(text, true)
	else:
		output_text.append_text(text)
	_request_scroll()

# ══════════════════════════════════════════
#  滚动控制（基于帧计数，不用 await，不会堆积协程）
# ══════════════════════════════════════════
func _request_scroll() -> void:
	# 请求滚动，延迟3帧执行（等待 RichTextLabel 布局完成）
	_scroll_pending_frames = 3

func _do_scroll_to_bottom() -> void:
	var v_scroll: VScrollBar = scroll_container.get_v_scroll_bar()
	if v_scroll:
		scroll_container.scroll_vertical = int(v_scroll.max_value)

# ══════════════════════════════════════════
#  每帧处理
# ══════════════════════════════════════════
func _process(_delta: float) -> void:
	tw.process_scroll()
	# 打字机打字时持续请求滚动
	if tw.is_typing:
		_request_scroll()
	# 帧计数滚动：倒数到0时执行实际滚动
	if _scroll_pending_frames > 0:
		_scroll_pending_frames -= 1
		if _scroll_pending_frames == 0:
			_do_scroll_to_bottom()

# ══════════════════════════════════════════
#  复制提示
# ══════════════════════════════════════════
func _show_copy_toast() -> void:
	output_text.append_text("[color=" + T.muted_hex + "][已复制到剪贴板][/color]\n")
	_request_scroll()

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
#  欢迎信息（磁盘加载后调用）
# ══════════════════════════════════════════
func _show_welcome_message() -> void:
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var story_dict: Dictionary = story_manifest.get("story", {}) as Dictionary
	var title: String = str(story_dict.get("title", "未知"))
	var box: String = fs.build_box(["ACCESS GRANTED", title] as Array[String], p)
	append_output(box + "\n", false)
	append_output("[color=" + m + "]输入 help 查看可用命令。[/color]\n\n", false)
