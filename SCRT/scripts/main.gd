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

# ★ 文档查看器
var doc_viewer: DocumentViewer = null
var profile_builder: ProfileBuilder = null

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
@onready var prompt_label: Label = $MainContent/InputFrame/InputArea/Prompt
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
var _theme_confirm_mode: bool = false

# ★ 用户系统交互模式标志
var _login_mode: bool = false
var _login_step: int = 0  # 0=用户名, 1=密码
var _login_username_input: String = ""

var _register_mode: bool = false
var _register_step: int = 0  # 0=用户名, 1=密码, 2=确认密码
var _register_username_input: String = ""
var _register_password_input: String = ""

var _passwd_mode: bool = false
var _passwd_step: int = 0  # 0=旧密码, 1=新密码, 2=确认新密码
var _passwd_old: String = ""
var _passwd_new: String = ""

var _delete_user_mode: bool = false
var _delete_user_target: String = ""

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
	user_mgr.setup(T, save_mgr)

	save_mgr.set_user_manager(user_mgr)

	crtml = CrtmlParser.new()
	crtml.setup(T, fs)

	disc_mgr = DiscManager.new()
	disc_mgr.setup(self, fs, T, tw, story_loader, save_mgr)

	cmd_handler = CommandHandler.new()
	cmd_handler.setup(self, fs, T, tw, disc_mgr, user_mgr, crtml)

	# ★ 文档查看器初始化
	doc_viewer = DocumentViewer.new()
	doc_viewer.setup(self, fs, T)

	profile_builder = ProfileBuilder.new()
	profile_builder.setup(self, fs, T, doc_viewer, user_mgr)

	# UI 初始化
	background = UIManager.setup_background(self, save_mgr.get_game_root_dir())
	UIManager.setup_main_content(self, $MainContent)
	UIManager.setup_all_styles(status_frame, path_label, mail_icon,
		input_frame, input_field, output_text, scroll_container)
	UIManager.setup_crt_effect($CRTEffect)
	UIManager.setup_custom_cursor(self)

	# 提示符颜色跟随主题
	prompt_label.add_theme_color_override("font_color", T.primary)

	# 输入框设置
	input_field.context_menu_enabled = false
	input_field.focus_mode = Control.FOCUS_ALL
	input_field.focus_next = input_field.get_path()
	input_field.focus_previous = input_field.get_path()
	input_field.caret_blink = true
	input_field.caret_blink_interval = 0.5
	input_field.add_theme_constant_override("caret_width", 8)

	# 信号连接
	input_field.text_submitted.connect(_on_input_submitted)
	output_text.meta_clicked.connect(_on_meta_clicked)
	input_field.focus_entered.connect(_on_input_focus_entered)
	input_field.focus_exited.connect(_on_input_focus_exited)

	# 初始 placeholder
	input_field.placeholder_text = ""
	mail_icon.text = "[Mail]"

	# 应用主题到所有 Shader
	ThemeManager._refresh_all_ui(self)

	# 启动登录流程
	_start_login_flow()
	input_field.grab_focus()

# ══════════════════════════════════════════
#  登录流程
# ══════════════════════════════════════════
func _start_login_flow() -> void:
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var w: String = T.warning_hex

	# ★ 使用 build_box 自动居中自适应宽度
	var login_box: String = fs.build_box([
		"SCP FOUNDATION SECURE TERMINAL",
        "SECURE · CONTAIN · PROTECT"
	] as Array[String], p)
	output_text.append_text(login_box + "\n\n")

	output_text.append_text("[color=" + m + "]身份验证系统 v2.0[/color]\n")
	output_text.append_text("[color=" + m + "]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n\n")

	# 显示已有用户列表
	var users: Array[String] = user_mgr.get_all_users()
	if users.size() > 0:
		output_text.append_text("[color=" + m + "]已注册操作员:[/color]\n")
		for u in users:
			var marker: String = ""
			if u == user_mgr.get_last_login_user():
				marker = " [color=" + w + "](上次登录)[/color]"
			output_text.append_text("  [color=" + p + "]" + u + "[/color]" + marker + "\n")
		output_text.append_text("\n")
	else:
		output_text.append_text("[color=" + m + "]未检测到已注册操作员。[/color]\n\n")

	output_text.append_text("[color=" + m + "]输入用户名登录，或输入 [/color][color=" + p + "]register[/color][color=" + m + "] 注册新账户。[/color]\n\n")

	var last_user: String = user_mgr.get_last_login_user()
	if not last_user.is_empty():
		output_text.append_text("[color=" + p + "]操作员代号 [" + last_user + "]: [/color]")
	else:
		output_text.append_text("[color=" + p + "]操作员代号: [/color]")

	_login_mode = true
	_login_step = 0
	_login_username_input = ""
	_update_status_bar_login()
	_request_scroll()

# ══════════════════════════════════════════
#  注册流程
# ══════════════════════════════════════════
func _start_register_flow() -> void:
	var p: String = T.primary_hex
	var m: String = T.muted_hex

	output_text.append_text("\n[color=" + m + "]━━━ 新操作员注册 ━━━[/color]\n\n")
	output_text.append_text("[color=" + m + "]用户名规则: " + str(UserManager.MIN_USERNAME_LENGTH) + "-" + str(UserManager.MAX_USERNAME_LENGTH) + " 字符，不含特殊字符和空格[/color]\n")
	output_text.append_text("[color=" + m + "]输入 cancel 可取消注册。[/color]\n\n")
	output_text.append_text("[color=" + p + "]请输入新操作员代号: [/color]")

	_register_mode = true
	_register_step = 0
	_register_username_input = ""
	_register_password_input = ""
	_request_scroll()

# ══════════════════════════════════════════
#  登录完成后进入桌面
# ══════════════════════════════════════════
func _enter_desktop_after_login(message: String) -> void:
	var m: String = T.muted_hex
	output_text.append_text("\n[color=" + m + "]" + message + "[/color]\n")
	output_text.append_text("[color=" + m + "]正在初始化终端...[/color]\n")
	_request_scroll()

	await get_tree().create_timer(0.8).timeout

	output_text.text = ""
	_desktop_mode = true

	# ★ 修复：只扫描一次
	disc_mgr.scan_stories(true)
	_update_status_bar()
	disc_mgr.show_desktop_welcome(true)
	_request_scroll()

# ══════════════════════════════════════════
#  输入框焦点控制 placeholder 显示
# ══════════════════════════════════════════
func _on_input_focus_entered() -> void:
	input_field.placeholder_text = ""

func _on_input_focus_exited() -> void:
	input_field.placeholder_text = _get_default_placeholder()

func _get_default_placeholder() -> String:
	if _login_mode:
		return "输入用户名..." if _login_step == 0 else "输入密码..."
	if _register_mode:
		match _register_step:
			0: return "输入新用户名..."
			1: return "设置密码..."
			2: return "再次输入密码..."
	if _passwd_mode:
		match _passwd_step:
			0: return "输入旧密码..."
			1: return "输入新密码..."
			2: return "确认新密码..."
	if _password_mode:
		return "请输入密码..."
	if _file_password_mode:
		return "请输入文件密码..."
	if _theme_confirm_mode:
		return "输入 Y 确认，其它取消..."
	if _delete_user_mode:
		return "输入 Y 确认删除..."
	return "按 Enter 输入命令..."

# ══════════════════════════════════════════
#  回车提交
# ══════════════════════════════════════════
func _on_input_submitted(_text: String) -> void:
	var raw: String = input_field.text.strip_edges()
	input_field.text = ""
	input_field.clear()
	input_field.grab_focus()

	# ★ 文档查看器模式下不接受终端输入
	if doc_viewer and doc_viewer.is_active:
		return

	if raw.is_empty():
		if _login_mode and _login_step == 0:
			var last_user: String = user_mgr.get_last_login_user()
			if not last_user.is_empty():
				raw = last_user
			else:
				return
		else:
			return

	if _command_running:
		return

	if tw.is_typing:
		tw.skip()
		return

	# 登录模式
	if _login_mode:
		_handle_login_input(raw)
		return

	# 注册模式
	if _register_mode:
		_handle_register_input(raw)
		return

	# 改密码模式
	if _passwd_mode:
		_handle_passwd_input(raw)
		return

	# 删除账户确认
	if _delete_user_mode:
		_handle_delete_user_confirm(raw)
		return

	# 主题确认模式
	if _theme_confirm_mode:
		_theme_confirm_mode = false
		output_text.append_text("> " + raw + "\n")
		if raw.to_lower() == "y":
			ThemeManager.confirm_and_apply(self)
			await get_tree().create_timer(0.8).timeout
			output_text.text = ""
			tw.clear_queue()
			cmd_handler.command_history.clear()
			cmd_handler.history_index = -1
			disc_mgr.reset_all()
			output_text.append_text("[color=" + T.muted_hex + "]...[/color]\n")
			await get_tree().create_timer(0.3).timeout
			output_text.append_text("[color=" + T.muted_hex + "]终端系统重新初始化中...[/color]\n")
			await get_tree().create_timer(0.5).timeout
			output_text.text = ""
			ThemeManager._refresh_all_ui(self)
			disc_mgr.scan_stories(true)
			disc_mgr.show_desktop_welcome(true)
			input_field.grab_focus()
		else:
			ThemeManager.cancel_theme_change(self)
		_request_scroll()
		return

	# 密码模式
	if _password_mode:
		_password_mode = false
		output_text.append_text("> " + "*".repeat(raw.length()) + "\n")
		if raw.to_lower() == "cancel":
			append_output("[color=" + T.muted_hex + "]已取消密码输入。[/color]\n", false)
			return
		cmd_handler._verify_password(raw)
		_request_scroll()
		return

	# 文件密码模式
	if _file_password_mode:
		_file_password_mode = false
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

	if user_mgr.is_logged_in:
		user_mgr.increment_command_count()

	_run_command(raw)

# ══════════════════════════════════════════
#  登录交互处理
# ══════════════════════════════════════════
func _handle_login_input(raw: String) -> void:
	var p: String = T.primary_hex
	var e: String = T.error_hex

	match _login_step:
		0:  # 用户名
			output_text.append_text(raw + "\n")

			if raw.to_lower() == "register":
				_login_mode = false
				_start_register_flow()
				return

			if raw.to_lower() == "exit" or raw.to_lower() == "quit":
				get_tree().quit()
				return

			if not user_mgr.user_exists(raw):
				output_text.append_text("[color=" + e + "]未找到用户 \"" + raw + "\"。[/color]\n")
				output_text.append_text("[color=" + T.muted_hex + "]输入 register 注册新账户。[/color]\n\n")
				var last_user: String = user_mgr.get_last_login_user()
				if not last_user.is_empty():
					output_text.append_text("[color=" + p + "]操作员代号 [" + last_user + "]: [/color]")
				else:
					output_text.append_text("[color=" + p + "]操作员代号: [/color]")
				_request_scroll()
				return

			_login_username_input = raw
			output_text.append_text("[color=" + p + "]访问密码: [/color]")
			_login_step = 1
			input_field.secret = true
			_request_scroll()

		1:  # 密码
			output_text.append_text("*".repeat(raw.length()) + "\n")
			input_field.secret = false

			var result: Dictionary = user_mgr.login(_login_username_input, raw)
			if result["success"]:
				_login_mode = false
				_enter_desktop_after_login(str(result["message"]))
			else:
				output_text.append_text("\n[color=" + e + "]" + str(result["message"]) + "[/color]\n\n")
				var last_user: String = user_mgr.get_last_login_user()
				if not last_user.is_empty():
					output_text.append_text("[color=" + p + "]操作员代号 [" + last_user + "]: [/color]")
				else:
					output_text.append_text("[color=" + p + "]操作员代号: [/color]")
				_login_step = 0
				_login_username_input = ""
			_request_scroll()

# ══════════════════════════════════════════
#  注册交互处理
# ══════════════════════════════════════════
func _handle_register_input(raw: String) -> void:
	var p: String = T.primary_hex
	var e: String = T.error_hex
	var m: String = T.muted_hex

	if raw.to_lower() == "cancel":
		_register_mode = false
		input_field.secret = false
		output_text.append_text(raw + "\n")
		output_text.append_text("[color=" + m + "]已取消注册。[/color]\n\n")
		_start_login_flow()
		return

	match _register_step:
		0:  # 用户名
			output_text.append_text(raw + "\n")

			if user_mgr.user_exists(raw):
				output_text.append_text("[color=" + e + "]用户名已存在，请选择其它名称。[/color]\n")
				output_text.append_text("[color=" + p + "]请输入新操作员代号: [/color]")
				_request_scroll()
				return

			if raw.length() < UserManager.MIN_USERNAME_LENGTH or raw.length() > UserManager.MAX_USERNAME_LENGTH:
				output_text.append_text("[color=" + e + "]用户名长度需在 " + str(UserManager.MIN_USERNAME_LENGTH) + "-" + str(UserManager.MAX_USERNAME_LENGTH) + " 字符之间。[/color]\n")
				output_text.append_text("[color=" + p + "]请输入新操作员代号: [/color]")
				_request_scroll()
				return

			_register_username_input = raw
			output_text.append_text("[color=" + p + "]设置访问密码 (至少" + str(UserManager.MIN_PASSWORD_LENGTH) + "位): [/color]")
			_register_step = 1
			input_field.secret = true
			_request_scroll()

		1:  # 密码
			output_text.append_text("*".repeat(raw.length()) + "\n")

			if raw.length() < UserManager.MIN_PASSWORD_LENGTH:
				output_text.append_text("[color=" + e + "]密码太短，至少需要 " + str(UserManager.MIN_PASSWORD_LENGTH) + " 个字符。[/color]\n")
				output_text.append_text("[color=" + p + "]设置访问密码: [/color]")
				_request_scroll()
				return

			_register_password_input = raw
			output_text.append_text("[color=" + p + "]确认访问密码: [/color]")
			_register_step = 2
			_request_scroll()

		2:  # 确认密码
			output_text.append_text("*".repeat(raw.length()) + "\n")
			input_field.secret = false

			if raw != _register_password_input:
				output_text.append_text("[color=" + e + "]两次输入的密码不一致，请重新设置。[/color]\n")
				output_text.append_text("[color=" + p + "]设置访问密码: [/color]")
				_register_step = 1
				input_field.secret = true
				_request_scroll()
				return

			var result: Dictionary = user_mgr.register(_register_username_input, _register_password_input)
			_register_mode = false

			if result["success"]:
				output_text.append_text("\n[color=" + p + "]" + str(result["message"]) + "[/color]\n")
				_enter_desktop_after_login(str(result["message"]))
			else:
				output_text.append_text("\n[color=" + e + "]" + str(result["message"]) + "[/color]\n\n")
				_start_login_flow()
			_request_scroll()

# ══════════════════════════════════════════
#  改密码交互处理
# ══════════════════════════════════════════
func _handle_passwd_input(raw: String) -> void:
	var p: String = T.primary_hex
	var e: String = T.error_hex
	var m: String = T.muted_hex

	if raw.to_lower() == "cancel":
		_passwd_mode = false
		input_field.secret = false
		output_text.append_text(raw + "\n")
		output_text.append_text("[color=" + m + "]已取消修改密码。[/color]\n")
		_request_scroll()
		return

	match _passwd_step:
		0:  # 旧密码
			output_text.append_text("*".repeat(raw.length()) + "\n")
			_passwd_old = raw
			output_text.append_text("[color=" + p + "]输入新密码: [/color]")
			_passwd_step = 1
			_request_scroll()

		1:  # 新密码
			output_text.append_text("*".repeat(raw.length()) + "\n")
			if raw.length() < UserManager.MIN_PASSWORD_LENGTH:
				output_text.append_text("[color=" + e + "]密码太短，至少需要 " + str(UserManager.MIN_PASSWORD_LENGTH) + " 个字符。[/color]\n")
				output_text.append_text("[color=" + p + "]输入新密码: [/color]")
				_request_scroll()
				return
			_passwd_new = raw
			output_text.append_text("[color=" + p + "]确认新密码: [/color]")
			_passwd_step = 2
			_request_scroll()

		2:  # 确认新密码
			output_text.append_text("*".repeat(raw.length()) + "\n")
			input_field.secret = false

			if raw != _passwd_new:
				output_text.append_text("[color=" + e + "]两次输入不一致，请重新设置。[/color]\n")
				output_text.append_text("[color=" + p + "]输入新密码: [/color]")
				_passwd_step = 1
				input_field.secret = true
				_request_scroll()
				return

			var result: Dictionary = user_mgr.change_password(_passwd_old, _passwd_new)
			_passwd_mode = false

			if result["success"]:
				output_text.append_text("[color=" + T.success_hex + "]" + str(result["message"]) + "[/color]\n")
			else:
				output_text.append_text("[color=" + e + "]" + str(result["message"]) + "[/color]\n")
			_request_scroll()

# ══════════════════════════════════════════
#  删除账户确认处理
# ══════════════════════════════════════════
func _handle_delete_user_confirm(raw: String) -> void:
	var e: String = T.error_hex
	var m: String = T.muted_hex

	output_text.append_text("> " + raw + "\n")
	_delete_user_mode = false

	if raw.to_lower() == "y":
		var target: String = _delete_user_target
		var is_self: bool = user_mgr.is_logged_in and user_mgr.get_username() == target
		var result: Dictionary = user_mgr.delete_user(target)
		if result["success"]:
			output_text.append_text("[color=" + e + "]" + str(result["message"]) + "[/color]\n")
			if is_self:
				await get_tree().create_timer(0.5).timeout
				output_text.text = ""
				_start_login_flow()
		else:
			output_text.append_text("[color=" + e + "]" + str(result["message"]) + "[/color]\n")
	else:
		output_text.append_text("[color=" + m + "]已取消。[/color]\n")

	_delete_user_target = ""
	_request_scroll()

# ══════════════════════════════════════════
#  公共方法（供 command_handler 调用）
# ══════════════════════════════════════════
func start_passwd_flow() -> void:
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	output_text.append_text("[color=" + m + "]修改访问密码 (输入 cancel 取消)[/color]\n")
	output_text.append_text("[color=" + p + "]输入当前密码: [/color]")
	_passwd_mode = true
	_passwd_step = 0
	_passwd_old = ""
	_passwd_new = ""
	input_field.secret = true
	_request_scroll()

func start_delete_user_flow(username: String) -> void:
	var e: String = T.error_hex
	output_text.append_text("[color=" + e + "]警告: 即将永久删除用户 \"" + username + "\" 及其所有存档数据![/color]\n")
	output_text.append_text("[color=" + e + "]输入 Y 确认删除，其它取消: [/color]")
	_delete_user_mode = true
	_delete_user_target = username
	_request_scroll()

func perform_logout() -> void:
	var m: String = T.muted_hex
	user_mgr.logout()
	output_text.append_text("[color=" + m + "]正在注销当前会话...[/color]\n")
	_request_scroll()
	await get_tree().create_timer(0.5).timeout
	output_text.text = ""
	_desktop_mode = true
	_start_login_flow()

# ══════════════════════════════════════════
#  命令执行
# ══════════════════════════════════════════
func _run_command(raw: String) -> void:
	_command_running = true
	await cmd_handler.execute(raw)
	_command_running = false
	_refocus_input.call_deferred()

func _refocus_input() -> void:
	input_field.grab_focus()

# ══════════════════════════════════════════
#  输入事件处理
# ══════════════════════════════════════════
func _input(event: InputEvent) -> void:
	# ★ 文档查看器优先处理输入
	if doc_viewer and doc_viewer.is_active:
		if doc_viewer.handle_input(event):
			get_viewport().set_input_as_handled()
			return

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
	if _login_mode or _register_mode or _passwd_mode or _password_mode or _file_password_mode:
		return

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

		var hint_text: String = "\n[color=" + T.muted_hex + "]可选项: " + " | ".join(display_items) + "[/color]\n"
		output_text.append_text(hint_text)
		_request_scroll()

		var common: String = _find_common_prefix(completions)
		if common.length() > current_text.length():
			input_field.text = common
			input_field.caret_column = input_field.text.length()

# ══════════════════════════════════════════
#  复制提示
# ══════════════════════════════════════════
func _show_copy_toast() -> void:
	output_text.append_text("\n[color=" + T.muted_hex + "][已复制到剪贴板][/color]\n")
	_request_scroll()

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
#  滚动控制
# ══════════════════════════════════════════
func _request_scroll() -> void:
	_scroll_pending_frames = 3

func _do_scroll_to_bottom() -> void:
	var v_scroll: VScrollBar = scroll_container.get_v_scroll_bar()
	if v_scroll:
		scroll_container.scroll_vertical = int(v_scroll.max_value)

# ══════════════════════════════════════════
#  每帧处理
# ══════════════════════════════════════════
func _process(delta: float) -> void:
	tw.process_scroll()
	if tw.is_typing:
		_request_scroll()
	if _scroll_pending_frames > 0:
		_scroll_pending_frames -= 1
		if _scroll_pending_frames == 0:
			_do_scroll_to_bottom()
	if doc_viewer and doc_viewer.is_active:
		doc_viewer.process_typing(delta)

	
	
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

	if meta_str.begins_with("spoiler://"):
		var decoded_text: String = meta_str.substr(10).uri_decode()
		output_text.append_text("\n[color=" + T.muted_hex + "][已揭示] " + decoded_text + "[/color]\n")
		_request_scroll()
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
		var user_str: String = ""
		if user_mgr and user_mgr.is_logged_in:
			user_str = " | 操作员: " + user_mgr.get_username()
		path_label.text = "SCP TERMINAL | 桌面模式 | 磁盘: " + str(disc_mgr.available_stories.size()) + user_str
	else:
		var story_dict: Dictionary = story_manifest.get("story", {}) as Dictionary
		var title: String = str(story_dict.get("title", "未知"))
		path_label.text = "磁盘: " + title + " | 路径: " + current_path + " | 等级: " + str(fs.player_clearance)

	if has_new_mail:
		mail_icon.text = "[Mail NEW]"
	else:
		mail_icon.text = "[Mail]"

func _update_status_bar_login() -> void:
	path_label.text = "SCP TERMINAL | 身份验证"
	mail_icon.text = ""

# ══════════════════════════════════════════
#  欢迎信息（磁盘加载后调用）
# ══════════════════════════════════════════
func _show_welcome_message() -> void:
	var p: String = T.primary_hex
	var m: String = T.muted_hex

	var story_dict: Dictionary = story_manifest.get("story", {}) as Dictionary
	var title: String = str(story_dict.get("title", "未知"))

	var welcome_title: String = "ACCESS GRANTED"
	if user_mgr.is_logged_in:
		welcome_title = "ACCESS GRANTED"

	# ★ 使用 build_box 自动居中自适应（已在 file_system.gd 中修复）
	var box: String = fs.build_box([welcome_title, title] as Array[String], p)
	append_output(box + "\n\n", false)

	append_output("[color=" + m + "]输入 help 查看可用命令。[/color]\n\n", false)
