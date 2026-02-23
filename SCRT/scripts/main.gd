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
@onready var audio_manager: Node = $AudioManager

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

# 音频示波器
var oscilloscope: Oscilloscope = null
var _oscilloscope_mode: bool = false

# 图片查看器
var image_viewer: ImageViewer = null
var _image_viewer_mode: bool = false

# 视频播放器
var video_player_viewer: VideoPlayerViewer = null
var _video_player_mode: bool = false

# 无线电接收器
var radio_receiver: RadioReceiver = null
var _radio_mode: bool = false

# 密码解码器
var decode_viewer: DecodeViewer = null
var _decode_mode: bool = false

# ★ 内联音频播放系统
var _inline_audio_path: String = ""
var _inline_audio_timer: float = 0.0
var _inline_audio_active: bool = false

# ★ 内联视频播放系统
var _inline_video_path: String = ""
var _inline_video_timer: float = 0.0
var _inline_video_active: bool = false


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
	tw.typing_completed.connect(_on_typing_completed)
	tw.progress_completed.connect(_on_typing_completed)

	# 初始化示波器
	oscilloscope = Oscilloscope.new()
	oscilloscope.setup(self, audio_manager)

	# 初始化图片查看器
	image_viewer = ImageViewer.new()
	image_viewer.setup(self)

	# 初始化视频播放器
	video_player_viewer = VideoPlayerViewer.new()
	video_player_viewer.setup(self, audio_manager)

	# 初始化无线电接收器
	radio_receiver = RadioReceiver.new()
	radio_receiver.setup(self, audio_manager)

	#初始化密码解码器
	decode_viewer = DecodeViewer.new()
	decode_viewer.setup(self)

	# 初始化各模块
	story_loader = StoryLoader.new()
	user_mgr = UserManager.new()
	user_mgr.setup(T, save_mgr)
	save_mgr.set_user_manager(user_mgr)

	crtml = CrtmlParser.new()
	crtml.setup(T, fs, self)

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

	var login_box: String = fs.build_box([
		"SCP FOUNDATION SECURE TERMINAL",
        "SECURE · CONTAIN · PROTECT"
	] as Array[String], p)
	output_text.append_text(login_box + "\n\n")
	output_text.append_text("[color=" + m + "]身份验证系统 v2.0[/color]\n")
	output_text.append_text("[color=" + m + "]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n\n")

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
	if _radio_mode:
		return ""
	if _decode_mode:
		return ""
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
	# ★ 图片查看器模式下不接受终端输入
	if image_viewer and image_viewer.is_active:
		return
	# ★ 视频播放器模式下不接受终端输入
	if video_player_viewer and video_player_viewer.is_active:
		return
	# ★ 无线电接收器模式下不接受终端输入
	if radio_receiver and radio_receiver.is_active:
		return
	# ★ 密码解码器模式下不接受终端输入
	if decode_viewer and decode_viewer.is_active:
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
	# 示波器模式优先处理输入
	if _oscilloscope_mode and oscilloscope and oscilloscope.is_active:
		if oscilloscope.handle_input(event):
			get_viewport().set_input_as_handled()
			return
	# 图片查看器模式优先处理输入
	if _image_viewer_mode and image_viewer and image_viewer.is_active:
		if image_viewer.handle_input(event):
			get_viewport().set_input_as_handled()
			return
	# 视频播放器模式优先处理输入
	if _video_player_mode and video_player_viewer and video_player_viewer.is_active:
		if video_player_viewer.handle_input(event):
			get_viewport().set_input_as_handled()
			return
	# 无线电接收器模式优先处理输入
	if _radio_mode and radio_receiver and radio_receiver.is_active:
		if radio_receiver.handle_input(event):
			get_viewport().set_input_as_handled()
			return
	# ★ 密码解码器模式优先处理输入
	if _decode_mode and decode_viewer and decode_viewer.is_active:
		if decode_viewer.handle_input(event):
			get_viewport().set_input_as_handled()
			return
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
func append_output(text: String, use_typewriter: bool = false, beep: bool = true) -> void:
	if use_typewriter:
		# ★ 打字机模式下，先处理内联图片占位符（分段输出）
		var segments: Array[Dictionary] = _split_inline_image_segments(text)
		if segments.size() <= 1 and (segments.is_empty() or segments[0]["type"] == "text"):
			tw.append(text, true)
		else:
			for seg in segments:
				if seg["type"] == "text":
					tw.append(str(seg["content"]), true)
				elif seg["type"] == "image":
					# 等待打字机完成当前文本
					while tw.is_typing:
						await get_tree().process_frame
					_insert_inline_image(seg)
	else:
		# ★ 即时模式下也处理内联图片
		var segments: Array[Dictionary] = _split_inline_image_segments(text)
		if segments.size() <= 1 and (segments.is_empty() or segments[0]["type"] == "text"):
			output_text.append_text(text)
		else:
			for seg in segments:
				if seg["type"] == "text":
					output_text.append_text(str(seg["content"]))
				elif seg["type"] == "image":
					_insert_inline_image(seg)
		if beep:
			audio_manager.play_beep()
	_request_scroll()

## ★ 分割文本为 text 和 image 段
## 修复：按文本中占位符出现的顺序逐个查找，而非按 images 数组顺序遍历
func _split_inline_image_segments(text: String) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []

	if crtml == null:
		segments.append({"type": "text", "content": text})
		return segments

	var images: Array[Dictionary] = crtml.get_inline_images()
	if images.is_empty():
		segments.append({"type": "text", "content": text})
		return segments

	# ★ 修复：从 remaining 中找最早出现的占位符，而非按数组顺序遍历
	var remaining: String = text
	while true:
		var earliest_pos: int = -1
		var earliest_img: Dictionary = {}
		var earliest_tag: String = ""

		for img_info in images:
			var pid: String = str(img_info.get("placeholder", ""))
			var tag: String = "\u0001IMG:" + pid + "\u0002"
			var pos: int = remaining.find(tag)
			if pos != -1 and (earliest_pos == -1 or pos < earliest_pos):
				earliest_pos = pos
				earliest_img = img_info
				earliest_tag = tag

		if earliest_pos == -1:
			break

		# 占位符前面的文本
		if earliest_pos > 0:
			segments.append({"type": "text", "content": remaining.substr(0, earliest_pos)})

		# 图片段
		segments.append({
			"type": "image",
			"texture": earliest_img.get("texture"),
			"width": earliest_img.get("width", 200),
			"height": earliest_img.get("height", 150),
			"path": earliest_img.get("path", ""),
		})
		remaining = remaining.substr(earliest_pos + earliest_tag.length())

	if not remaining.is_empty():
		segments.append({"type": "text", "content": remaining})

	if segments.is_empty():
		segments.append({"type": "text", "content": text})
	return segments

## ★ 向 output_text 插入内联图片纹理
func _insert_inline_image(seg: Dictionary) -> void:
	var texture = seg.get("texture")
	if texture == null or not (texture is ImageTexture):
		output_text.append_text("[IMG]")
		return
	var w: int = int(seg.get("width", 200))
	var h: int = int(seg.get("height", 150))
	output_text.newline()
	output_text.add_image(texture as Texture2D, w, h, Color.WHITE, 5, Rect2(), null, false, "", false)
	output_text.newline()

## 打字机完成一段输出后的回调
func _on_typing_completed() -> void:
	audio_manager.play_beep()

## 图片查看器关闭后的回调
func _on_image_viewer_closed() -> void:
	_image_viewer_mode = false
	input_field.editable = true

## 用图片文件打开图片查看器
func open_image_viewer_with_file(file_path: String, file_name: String, data: PackedByteArray) -> void:
	_image_viewer_mode = true
	input_field.editable = false
	image_viewer.open_with_file(file_path, file_name, data)

## 示波器关闭后的回调
func _on_oscilloscope_closed() -> void:
	_oscilloscope_mode = false
	input_field.editable = true

## 用音频文件打开示波器
func open_oscilloscope_with_file(file_path: String, file_name: String, stream: AudioStream) -> void:
	_oscilloscope_mode = true
	input_field.editable = false
	oscilloscope.open_with_file(file_path, file_name, stream)

## 视频播放器关闭回调
func _on_video_player_closed() -> void:
	_video_player_mode = false
	input_field.editable = true
	# ★ 清除内联视频状态
	if _inline_video_active:
		var file_name: String = _inline_video_path.get_file()
		_inline_video_active = false
		_inline_video_path = ""
		_media_status_output("[color=" + T.muted_hex + "]⏹ 视频播放结束: " + file_name + "[/color]\n")
	_update_status_bar()


## 无线电接收器关闭回调
func _on_radio_closed() -> void:
	_radio_mode = false
	input_field.editable = true

## 打开无线电接收器
func open_radio_receiver() -> void:
	if radio_receiver == null:
		return
	_radio_mode = true
	input_field.editable = false
	radio_receiver.open()


## decode_viewer 关闭回调
func _on_decode_viewer_closed() -> void:
	_decode_mode = false
	input_field.editable = true
	_update_status_bar()


## 打开密码解码器
func open_decode_viewer(args: Array = []) -> void:
	if decode_viewer == null:
		return
	_decode_mode = true
	input_field.editable = false
	decode_viewer.open(args)


## 打开视频播放器
func open_video_player_with_file(file_path: String, file_name: String, data: PackedByteArray) -> void:
	_video_player_mode = true
	input_field.editable = false
	video_player_viewer.open_with_file(file_path, file_name, data)

## 检查并更新环境音（在 cd/back 切换目录后调用）
func update_ambient_sound() -> void:
	var ambient_info: Dictionary = fs.get_ambient_for_path(current_path)
	if ambient_info.is_empty():
		audio_manager.stop_ambient()
		return

	var ambient_file: String = ambient_info["file"]
	var ambient_dir: String = ambient_info["path"]
	var ambient_volume: float = ambient_info["volume"]
	var ambient_id: String = ambient_dir + ":" + ambient_file

	if ambient_id == audio_manager.current_ambient_id:
		return

	var audio_path: String = ambient_file
	if not audio_path.begins_with("/"):
		audio_path = fs.join_path(ambient_dir, audio_path)
	audio_path = fs.normalize_path(audio_path)

	var audio_data: PackedByteArray = fs.get_binary_data(audio_path)
	if audio_data.is_empty():
		push_warning("[Main] 环境音文件不存在或无数据: " + audio_path)
		return

	var stream: AudioStream = audio_manager.load_audio_from_bytes(audio_path, audio_data)
	if stream == null:
		push_warning("[Main] 无法解析环境音: " + audio_path)
		return

	var volume_db: float = -80.0
	if ambient_volume > 0.0:
		volume_db = linear_to_db(ambient_volume)
	audio_manager.play_ambient(ambient_id, stream, volume_db)
	print("[Main] 环境音已切换: ", ambient_id, " 音量: ", ambient_volume)

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
	# ★ 修复：函数名一致
	_update_inline_audio_status(delta)
	# 视频每帧更新
	if video_player_viewer and video_player_viewer.is_active:
		video_player_viewer.process_frame(delta)
	# ★ 视频播放器状态栏进度更新
	_update_inline_video_status(delta)




# ══════════════════════════════════════════
#  超链接处理
# ══════════════════════════════════════════
func _on_meta_clicked(meta: Variant) -> void:
	var meta_str: String = str(meta)

	# ★ 内联音频：播放/暂停切换
	if meta_str.begins_with("audio://toggle/"):
		var audio_path: String = meta_str.substr(15)
		_toggle_inline_audio(audio_path)
		return

	# ★ 内联音频：停止
	if meta_str.begins_with("audio://stop"):
		_stop_inline_audio()
		return

	# ★ 内联视频：在全屏播放器中打开
	if meta_str.begins_with("video://play/"):
		var video_path: String = meta_str.substr(13)
		_play_inline_video(video_path)
		return

	# ★ 内联视频：停止（如果全屏播放器正在运行）
	if meta_str.begins_with("video://stop"):
		_stop_inline_video()
		return

	if meta_str.begins_with("cmd://"):
		var cmd: String = meta_str.substr(6)
		# ★ 如果在文档查看器中点击了 cmd:// 链接，先关闭文档查看器再执行
		if doc_viewer and doc_viewer.is_active:
			doc_viewer.close()
		output_text.append_text("\n> " + cmd + "\n")
		_run_command(cmd)
		return

	if meta_str.begins_with("spoiler://"):
		var decoded_text: String = meta_str.substr(10).uri_decode()
		# ★ spoiler 在文档查看器中也要正确显示
		_audio_status_output("\n[color=" + T.muted_hex + "][已揭示] " + decoded_text + "[/color]\n")
		_request_scroll()
		return

	if meta_str.begins_with("file://"):
		var file_path: String = meta_str.substr(7)
		if doc_viewer and doc_viewer.is_active:
			doc_viewer.close()
		output_text.append_text("\n> open " + file_path + "\n")
		_run_command("open " + file_path)
		return



# ============================================================
# ★ 内联音频播放系统
# ============================================================

## ★ 播放/暂停切换
func _toggle_inline_audio(audio_path: String) -> void:
	var normalized_path: String = fs.normalize_path(audio_path)

	# 如果正在播放同一文件 → 切换暂停/恢复
	if _inline_audio_active and _inline_audio_path == normalized_path:
		# ★ 修复：先记录当前状态再调用 toggle，然后根据新状态输出提示
		var was_paused: bool = audio_manager.is_media_paused()
		audio_manager.pause_media()
		if was_paused:
			# 之前是暂停的，现在恢复播放
			_audio_status_output("[color=" + T.success_hex + "]▶ 继续播放[/color]\n")
		else:
			# 之前在播放，现在暂停
			_audio_status_output("[color=" + T.muted_hex + "]⏸ 已暂停[/color]\n")
		return

	# 否则：加载并播放新文件（或重新播放同一文件）
	var audio_data: PackedByteArray = fs.get_binary_data(normalized_path)
	if audio_data.is_empty():
		_audio_status_output("[color=" + T.error_hex + "][ERROR] 无法读取音频数据。[/color]\n")
		return

	var stream: AudioStream = audio_manager.load_audio_from_bytes(normalized_path, audio_data)
	if stream == null:
		_audio_status_output("[color=" + T.error_hex + "][ERROR] 无法解析音频文件。[/color]\n")
		return

	# 播放
	audio_manager.play_media(stream)
	_inline_audio_path = normalized_path
	_inline_audio_active = true

	var file_name: String = audio_path.get_file()
	var duration: float = audio_manager.get_media_length()
	var dur_str: String = _format_audio_time(duration)
	_audio_status_output("[color=" + T.success_hex + "]▶ 正在播放: " + file_name + " [" + dur_str + "][/color]\n")

	# 连接播放完成信号（如果尚未连接）
	if audio_manager.has_signal("media_playback_finished"):
		if not audio_manager.media_playback_finished.is_connected(_on_inline_audio_finished):
			audio_manager.media_playback_finished.connect(_on_inline_audio_finished)

## ★ 停止内联播放
func _stop_inline_audio() -> void:
	if _inline_audio_active:
		audio_manager.stop_media()
		_inline_audio_active = false
		_inline_audio_path = ""
		_audio_status_output("[color=" + T.muted_hex + "]⏹ 已停止播放[/color]\n")
	else:
		_audio_status_output("[color=" + T.muted_hex + "]当前没有正在播放的音频。[/color]\n")
	_update_status_bar()

## ★ 播放完成回调
func _on_inline_audio_finished() -> void:
	if _inline_audio_active:
		_inline_audio_active = false
		var file_name: String = _inline_audio_path.get_file()
		_inline_audio_path = ""
		_audio_status_output("[color=" + T.muted_hex + "]⏹ 播放结束: " + file_name + "[/color]\n")
		_update_status_bar()


# ============================================================
# ★ 内联视频播放系统
# ============================================================

## ★ 在全屏视频播放器中打开视频
func _play_inline_video(video_path: String) -> void:
	var normalized_path: String = fs.normalize_path(video_path)

	# 如果视频播放器已经在播放同一文件，忽略
	if _video_player_mode and video_player_viewer and video_player_viewer.is_active:
		if _inline_video_path == normalized_path:
			_media_status_output("[color=" + T.muted_hex + "]视频已在播放中。[/color]\n")
			return

	# 检查文件是否支持
	var file_name: String = video_path.get_file()
	if not VideoPlayerViewer.is_supported_video(file_name):
		_media_status_output("[color=" + T.error_hex + "][ERROR] 不支持的视频格式: " + file_name + "[/color]\n")
		return

	# 获取视频二进制数据
	var video_data: PackedByteArray = fs.get_binary_data(normalized_path)
	if video_data.is_empty():
		_media_status_output("[color=" + T.error_hex + "][ERROR] 无法读取视频数据。[/color]\n")
		return

	# 记录状态
	_inline_video_path = normalized_path
	_inline_video_active = true

	var ext_tag: String = file_name.get_extension().to_upper()
	_media_status_output("[color=" + T.success_hex + "]▶ 正在加载视频 [" + ext_tag + "]: " + file_name + "...[/color]\n")

	# 打开全屏视频播放器
	open_video_player_with_file(normalized_path, file_name, video_data)

## ★ 停止视频播放
func _stop_inline_video() -> void:
	if _video_player_mode and video_player_viewer and video_player_viewer.is_active:
		video_player_viewer.close()
		# close 会触发 _on_video_player_closed 回调
		_media_status_output("[color=" + T.muted_hex + "]⏹ 视频已停止[/color]\n")
	elif _inline_video_active:
		_inline_video_active = false
		_inline_video_path = ""
		_media_status_output("[color=" + T.muted_hex + "]⏹ 视频已停止[/color]\n")
	else:
		_media_status_output("[color=" + T.muted_hex + "]当前没有正在播放的视频。[/color]\n")

## ★ 输出媒体状态信息（通用：自动判断输出目标）
func _media_status_output(text: String) -> void:
	if doc_viewer != null and doc_viewer.is_active:
		var active_rtl: RichTextLabel = doc_viewer.get_active_page_rtl()
		if active_rtl != null:
			active_rtl.append_text("\n" + text)
		return
	# 终端模式
	append_output(text, false, false)


## ★ 输出音频状态信息（自动判断输出目标：终端 or 文档查看器）
func _audio_status_output(text: String) -> void:
	if doc_viewer != null and doc_viewer.is_active:
		# 文档查看器模式：在当前活动页面追加
		var active_rtl: RichTextLabel = doc_viewer.get_active_page_rtl()
		if active_rtl != null:
			active_rtl.append_text("\n" + text)
			return
	# 终端模式
	append_output(text, false, false)

## ★ 格式化时间 秒 → MM:SS
func _format_audio_time(seconds: float) -> String:
	if seconds <= 0:
		return "--:--"
	var total_sec: int = int(seconds)
	var mins: int = total_sec / 60
	var secs: int = total_sec % 60
	return "%02d:%02d" % [mins, secs]

## ★ 更新状态栏中的内联音频播放进度
func _update_inline_audio_status(delta: float) -> void:
	if not _inline_audio_active:
		return

	_inline_audio_timer += delta
	if _inline_audio_timer < 0.5:
		return
	_inline_audio_timer = 0.0

	# ★ 修复：安全检查 audio_manager 方法是否存在
	if not audio_manager.has_method("is_media_playing"):
		return

	var is_playing: bool = audio_manager.is_media_playing()
	var is_paused: bool = audio_manager.is_media_paused() if audio_manager.has_method("is_media_paused") else false

	if not is_playing and not is_paused:
		# ★ 播放已自然结束（没有通过信号通知的情况）
		if _inline_audio_active:
			_inline_audio_active = false
			var file_name: String = _inline_audio_path.get_file()
			_inline_audio_path = ""
			_audio_status_output("[color=" + T.muted_hex + "]⏹ 播放结束: " + file_name + "[/color]\n")
			_update_status_bar()
		return

	var current_pos: float = audio_manager.get_media_playback_position()
	var total_len: float = audio_manager.get_media_length()
	var cur_str: String = _format_audio_time(current_pos)
	var tot_str: String = _format_audio_time(total_len)

	# 构建 ASCII 进度条
	var bar_width: int = 20
	var progress: float = 0.0
	if total_len > 0:
		progress = clampf(current_pos / total_len, 0.0, 1.0)
	var filled: int = int(progress * bar_width)
	var empty_count: int = bar_width - filled
	var bar: String = "█".repeat(filled) + "░".repeat(empty_count)

	var status_icon: String = "▶" if not is_paused else "⏸"
	var file_name: String = _inline_audio_path.get_file()

	# 更新状态栏
	var base_path_text: String = ""
	if _desktop_mode:
		base_path_text = "DESKTOP"
	else:
		base_path_text = current_path

	path_label.text = base_path_text + "  │  " + status_icon + " " + bar + " " + cur_str + "/" + tot_str + " " + file_name


## ★ 更新状态栏中的内联视频播放进度
func _update_inline_video_status(delta: float) -> void:
	if not _inline_video_active:
		return
	if not _video_player_mode or video_player_viewer == null or not video_player_viewer.is_active:
		return

	_inline_video_timer += delta
	if _inline_video_timer < 0.25:
		return
	_inline_video_timer = 0.0

	# 从 video_player_viewer 获取播放状态
	if not video_player_viewer.has_method("get_playback_position"):
		return

	var current_pos: float = video_player_viewer.get_playback_position()
	var total_len: float = video_player_viewer.get_video_length()
	var is_paused: bool = video_player_viewer.is_paused()
	var cur_str: String = _format_audio_time(current_pos)
	var tot_str: String = _format_audio_time(total_len)

	# 构建 ASCII 进度条
	var bar_width: int = 20
	var progress: float = 0.0
	if total_len > 0:
		progress = clampf(current_pos / total_len, 0.0, 1.0)
	var filled: int = int(progress * bar_width)
	var empty_count: int = bar_width - filled
	var bar: String = "█".repeat(filled) + "░".repeat(empty_count)
	var status_icon: String = "▶" if not is_paused else "⏸"
	var file_name: String = _inline_video_path.get_file()

	# 更新状态栏（视频播放器已经有自己的状态栏，这里更新 main 的）
	path_label.text = "VIDEO PLAYER | " + status_icon + " " + bar + " " + cur_str + "/" + tot_str + " " + file_name


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

	var box: String = fs.build_box([welcome_title, title] as Array[String], p)
	append_output(box + "\n\n", false)
	append_output("[color=" + m + "]输入 help 查看可用命令。[/color]\n\n", false)
