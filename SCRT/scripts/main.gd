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
var pkg_mgr: PackageManager = null

var settings_mgr: SettingsManager = null
## 通讯系统
var comm_mgr: CommManager = null
var dial_mgr: DialManager = null
# 触发器
var trigger_sys: TriggerSystem = null
var mail_sys: MailSystem = null
# ★ 文档查看器
var doc_viewer: DocumentViewer = null
var profile_builder: ProfileBuilder = null
var two_page_viewer: TwoPageReader = null
var email_viewer: EmailViewer = null
var chat_viewer: ChatViewer = null
var article_viewer: ArticleViewer = null
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
var crt_shader = null  # CRTShader 效果控制器引用（crt_shader.gd 实例）
var effect_sys: EffectSystem = null  # 效果编排系统
var effect_settings: EffectSettings = null  # 效果强度与安全设置
var ui_sound: UiSound = null  # 操作音效系统
var boot_sequence: BootSequence = null  # 开关机动画序列
var background: TextureRect = null
var background_base: ColorRect = null      # 纯黑底 Background(ColorRect)
var background_logo: TextureRect = null    # SCP logo BackgroundLogo
@onready var audio_manager: Node = $AudioManager
# ══════════════════════════════════════════
#  状态变量
# ══════════════════════════════════════════
var _desktop_mode: bool = true
var current_path: String = "/"
var read_files: Array[String] = []
var visited_paths: Array[String] = []       # ★ 已访问的目录列表
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
var _register_step: int = 0  # 0=用户名, 1=密码, 2=确认密码, 3=昵称, 4=性别, 5=生日
var _register_username_input: String = ""
var _register_password_input: String = ""
var _register_nickname_input: String = ""
var _register_gender_input: String = ""
var _register_birthday_input: String = ""
var _register_is_wizard: bool = false  # 是否首次注册引导模式
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
# ★ 环境监测系统
var env_monitor: EnvMonitor = null
var env_task_mgr: EnvTaskManager = null
var env_viewer: EnvViewer = null
var _env_viewer_mode: bool = false
var daily_dialogue_mgr: DailyDialogueManager = null
# ★ 监控摄像头系统
var camera_mgr: CameraManager = null
var camera_viewer: CameraViewer = null
var _camera_viewer_mode: bool = false
# ★ 内联音频播放系统
var _inline_audio_path: String = ""
var _inline_audio_timer: float = 0.0
var _inline_audio_active: bool = false
# ★ 内联视频播放系统
var _inline_video_path: String = ""
var _inline_video_timer: float = 0.0
var _inline_video_active: bool = false
var explore_viewer: ExploreViewer = null
# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func _ready() -> void:
	# ★ 窗口关闭时自动保存
	get_tree().auto_accept_quit = false
	# 初始化主题（先设置存储路径，确保主题配置存入 saves/ 目录）
	ThemeManager.setup_save_root(save_mgr.get_game_root_dir() + "saves/")
	ThemeManager.init("phosphor_green")
	T = ThemeManager.current
	# 初始化打字机
	tw = Typewriter.new()
	tw.name = "Typewriter"
	add_child(tw)
	tw.setup(output_text, scroll_container, self)
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
	# ★ 设置系统初始化（在各模块初始化之前，以便模块可以读取设置值）
	settings_mgr = SettingsManager.new()
	settings_mgr.setup(self, fs, T, save_mgr.get_game_root_dir() + "saves/")
	# 注册 apply 回调（各模块值变更时自动同步）
	_register_settings_apply_callbacks()
	crtml = CrtmlParser.new()
	crtml.setup(T, fs, self)
	disc_mgr = DiscManager.new()
	disc_mgr.setup(self, fs, T, tw, story_loader, save_mgr)
	cmd_handler = CommandHandler.new()
	cmd_handler.setup(self, fs, T, tw, disc_mgr, user_mgr, crtml)
	# ★ 软件包管理器初始化
	pkg_mgr = PackageManager.new()
	pkg_mgr.setup(self, fs, T, tw, user_mgr, disc_mgr, cmd_handler, story_loader)
	# ★ 通讯系统初始化（修正：使用 fs 而非 file_system）
	comm_mgr = CommManager.new()
	comm_mgr.setup(self, fs, T)
	# ★ 拨号管理器初始化
	dial_mgr = DialManager.new()
	dial_mgr.setup(self, comm_mgr, audio_manager, T)
	# 注册系统内置号码
	dial_mgr.register_system_voice("1001-0001", "ava", "系统联络员 (AVA)")
	dial_mgr.register_system_voice("1001-0002", "ava", "AVA 设施简报 (演示)")
	dial_mgr.register_system_voice("1002-0001", "researcher", "高级研究员 (Dr. Zhang)")
	dial_mgr.register_system_voice("1000-9999", "ava", "多方视频会议室")

	# ★ 触发器系统
	trigger_sys = TriggerSystem.new()
	trigger_sys.setup(self, fs, T)
# ★ 邮件系统
	mail_sys = MailSystem.new()
	mail_sys.setup(self, fs, T)
	# 互相注入
	trigger_sys.set_mail_system(mail_sys)
	mail_sys.set_trigger_system(trigger_sys)
	# ★ 文档查看器初始化
	doc_viewer = DocumentViewer.new()
	doc_viewer.setup(self, fs, T)
	profile_builder = ProfileBuilder.new()
	profile_builder.setup(self, fs, T, doc_viewer, user_mgr)
	# 双页阅读器模板初始化
	two_page_viewer = TwoPageReader.new()
	two_page_viewer.setup(self, fs, T)
	# ★ 探索进度查看器
	explore_viewer = ExploreViewer.new()
	explore_viewer.setup(self, fs, T)
	# 邮件查看器初始化
	email_viewer = EmailViewer.new()
	email_viewer.setup(self, fs, T)
	chat_viewer = ChatViewer.new()
	chat_viewer.setup(self, fs, T)
	article_viewer = ArticleViewer.new()
	article_viewer.setup(self, fs, T)
	# UI 初始化
	background = UIManager.setup_background(self, save_mgr.get_game_root_dir())
	
		# 获取背景相关节点引用
	background_base = $Background as ColorRect if has_node("Background") else null
	if has_node("Background/CenterContainer/BackgroundLogo"):
		background_logo = $Background/CenterContainer/BackgroundLogo as TextureRect
	
	UIManager.setup_main_content(self, $MainContent)
	UIManager.setup_all_styles(status_frame, path_label, mail_icon,
		input_frame, input_field, output_text, scroll_container)
	UIManager.setup_crt_effect($CRTEffect)
	
	# 缓存 CRT Shader 控制器引用
	var crt_node: Node = $CRTEffect
	if crt_node:
		for child in crt_node.get_children():
			if child.has_method("play_glitch"):
				crt_shader = child
				break
	if crt_shader == null:
		push_warning("[Main] 未找到 crt_shader.gd 控制器节点")
	# 初始化效果强度设置
	effect_settings = EffectSettings.new()
	effect_settings.setup_save_root(save_mgr.get_game_root_dir() + "saves/")
	effect_settings.load_settings()
	# 初始化操作音效系统
	ui_sound = UiSound.new()
	ui_sound.setup(get_tree())
	boot_sequence = BootSequence.new()
	boot_sequence.setup(self, audio_manager, crt_shader)
	# 初始化效果编排系统
	effect_sys = EffectSystem.new()
	effect_sys.setup(self, fs, T, audio_manager, crt_shader)
	print("[Main] 效果编排系统已初始化")
	# ★ 环境监测系统初始化
	env_monitor = EnvMonitor.new()
	env_monitor.setup(self, T)
	env_task_mgr = EnvTaskManager.new()
	env_task_mgr.setup(self, env_monitor, T)
	env_viewer = EnvViewer.new()
	env_viewer.setup(self, env_monitor, T)
	env_monitor.start_new_game()
	env_task_mgr.reset_for_new_day()
	daily_dialogue_mgr = DailyDialogueManager.new()
	daily_dialogue_mgr.setup(self)
	print("[Main] 环境监测系统已初始化")
	# ★ 初始化监控摄像头系统
	camera_mgr = CameraManager.new()
	camera_mgr.setup(self)
	camera_viewer = CameraViewer.new()
	camera_viewer.setup(self, camera_mgr)
	print("[Main] 监控摄像头系统已初始化")
	
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
	input_field.text_changed.connect(_on_input_text_changed)
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
var _boot_count: int = 0  # 开机次数计数器（0=首次，1+=后续）

# ══════════════════════════════════════════
#  设置系统 apply 回调注册
# ══════════════════════════════════════════
func _register_settings_apply_callbacks() -> void:
	if settings_mgr == null:
		return

	# ── display ──
	# display.theme 的 apply 不在这里注册，主题切换走特殊确认流程
	settings_mgr.register_apply("display.cursor_blink_speed", func(value):
		if input_field:
			input_field.caret_blink_interval = float(value)
	)

	# ── audio ──
	settings_mgr.register_apply("audio.master_volume", func(value):
		if audio_manager and audio_manager.has_method("set_master_volume"):
			audio_manager.set_master_volume(float(value))
	)
	settings_mgr.register_apply("audio.ambient_volume", func(value):
		if audio_manager and audio_manager.has_method("set_ambient_volume"):
			audio_manager.set_ambient_volume(float(value))
	)
	settings_mgr.register_apply("audio.sfx_volume", func(value):
		if audio_manager and audio_manager.has_method("set_sfx_volume"):
			audio_manager.set_sfx_volume(float(value))
	)
	settings_mgr.register_apply("audio.media_volume", func(value):
		if audio_manager and audio_manager.has_method("set_media_volume"):
			audio_manager.set_media_volume(float(value))
	)
	settings_mgr.register_apply("audio.sound_enabled", func(value):
		if ui_sound:
			ui_sound.enabled = bool(value)
	)

	# ── effect ──
	settings_mgr.register_apply("effect.level", func(value):
		if effect_settings:
			match str(value):
				"full":
					effect_settings.set_level(EffectSettings.Level.FULL)
				"mild":
					effect_settings.set_level(EffectSettings.Level.MILD)
				"off":
					effect_settings.set_level(EffectSettings.Level.OFF)
	)
	settings_mgr.register_apply("effect.photosensitive", func(value):
		if effect_settings:
			effect_settings.set_photosensitive(bool(value))
	)

	# ── terminal ──
	settings_mgr.register_apply("terminal.typing_speed", func(value):
		if tw:
			tw.base_speed = float(value)
	)
	settings_mgr.register_apply("terminal.typing_pause_chance", func(value):
		if tw:
			tw.pause_chance = float(value)
	)
	settings_mgr.register_apply("terminal.progress_speed", func(value):
		if tw:
			tw.progress_speed_multiplier = float(value)
	)


func _start_login_flow() -> void:
	# 每次都播放开机动画
	if boot_sequence:
		_boot_count += 1
		_play_boot_then_login()
		return
	_show_login_prompt()

func _play_boot_then_login() -> void:
	# 开机前：通过 shader uniform 隐藏背景和 logo
	_set_background_shader_value("brightness", 0.0)
	_set_background_shader_value("alpha", 0.0)
	_set_logo_shader_value("brightness", 0.0)
	_set_logo_shader_value("alpha", 0.0)
	# 隐藏输入相关UI
	input_field.editable = false
	input_field.visible = false
	status_frame.visible = false
	input_frame.visible = false
	output_text.text = ""
	# 告诉 boot_sequence 是否可跳过
	boot_sequence.skippable = (_boot_count > 1)
	# 连接完成信号
	if not boot_sequence.boot_completed.is_connected(_on_boot_sequence_done):
		boot_sequence.boot_completed.connect(_on_boot_sequence_done, CONNECT_ONE_SHOT)
	# 延迟两帧确保 deferred 节点就绪
	await get_tree().process_frame
	await get_tree().process_frame
	boot_sequence.play_boot()

func _on_boot_sequence_done() -> void:
	# 恢复UI
	status_frame.visible = true
	input_frame.visible = true
	input_field.visible = true
	input_field.editable = true
	# 恢复背景和logo到正常状态（通过shader uniform）
	_set_background_shader_value("brightness", 0.688)
	_set_background_shader_value("alpha", 0.5)
	_set_logo_shader_value("brightness", 0.0)  # logo 默认 brightness=0
	_set_logo_shader_value("alpha", 0.4)
	await get_tree().create_timer(0.3).timeout
	output_text.text = ""
	if audio_manager and audio_manager.has_method("play_beep"):
		audio_manager.play_beep()
	_show_login_prompt()

func _show_login_prompt() -> void:
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var w: String = T.warning_hex
	# ★ 首次启动检测：没有非管理员用户时自动进入注册引导
	if not user_mgr.has_non_admin_users():
		_start_register_flow(true)  # true = 引导模式
		input_field.grab_focus()
		_update_status_bar_login()
		return
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
	input_field.grab_focus()
	_update_status_bar_login()
	_request_scroll()


# ══════════════════════════════════════════
#  注册流程
# ══════════════════════════════════════════
func _start_register_flow(is_wizard: bool = false) -> void:
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var w: String = T.warning_hex
	_register_is_wizard = is_wizard
	if is_wizard:
		# 首次注册引导 — 更友好的欢迎界面
		var wizard_box: String = fs.build_box([
			"NEW OPERATOR REGISTRATION",
			"新操作员注册引导"
		] as Array[String], p)
		output_text.append_text("\n" + wizard_box + "\n\n")
		output_text.append_text("[color=" + m + "]欢迎来到 SCP 基金会安全终端。[/color]\n")
		output_text.append_text("[color=" + m + "]系统检测到尚无已注册操作员，请完成注册引导以建立您的档案。[/color]\n\n")
		output_text.append_text("[color=" + w + "]注册流程: 代号 → 密码 → 个人信息[/color]\n")
		output_text.append_text("[color=" + m + "]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n\n")
	else:
		output_text.append_text("\n[color=" + m + "]━━━ 新操作员注册 ━━━[/color]\n\n")
	output_text.append_text("[color=" + m + "]用户名规则: " + str(UserManager.MIN_USERNAME_LENGTH) + "-" + str(UserManager.MAX_USERNAME_LENGTH) + " 字符，不含特殊字符和空格[/color]\n")
	if not is_wizard:
		output_text.append_text("[color=" + m + "]输入 cancel 可取消注册。[/color]\n\n")
	else:
		output_text.append_text("\n")
	output_text.append_text("[color=" + p + "]请输入新操作员代号: [/color]")
	_register_mode = true
	_register_step = 0
	_register_username_input = ""
	_register_password_input = ""
	_register_nickname_input = ""
	_register_gender_input = ""
	_register_birthday_input = ""
	_request_scroll()
	


## ★ 完整 UI 刷新（主题切换后调用）
func _full_ui_refresh() -> void:
	ThemeManager._refresh_all_ui(self)


# ══════════════════════════════════════════
#  登录完成后进入桌面
# ══════════════════════════════════════════
func _enter_desktop_after_login(message: String) -> void:
	var m: String = T.muted_hex
	output_text.append_text("\n[color=" + m + "]" + message + "[/color]\n")
	# 加载用户自定义开机配置
	if boot_sequence and user_mgr.is_logged_in:
		boot_sequence.load_user_override(user_mgr.get_username())
	output_text.append_text("[color=" + m + "]正在初始化终端...[/color]\n")
	_request_scroll()
	await get_tree().create_timer(0.8).timeout
	output_text.text = ""
	_desktop_mode = true
	# ★ 登录后加载用户设置
	if settings_mgr and user_mgr.is_logged_in:
		settings_mgr.on_user_login(user_mgr.get_username())
		# 主题可能随用户变化，需要检查是否需要静默切换
		var user_theme: String = settings_mgr.get_string("display.theme")
		if not user_theme.is_empty() and user_theme != ThemeManager.current_theme_name:
			# 用户保存了不同的主题，静默应用（不走确认流程）
			ThemeManager.init(user_theme)
			T = ThemeManager.current
			settings_mgr.T = T
			_full_ui_refresh()
	# ★ 登录后加载用户全局收件箱
	if mail_sys != null:
		mail_sys.load_global_inbox()
	# ★ 登录后恢复已安装的模组
	if pkg_mgr:
		pkg_mgr.load_installed_mods()
	disc_mgr.scan_stories(true)
	_update_status_bar()
	disc_mgr.show_desktop_welcome(true)
	# ★ NEW: 分发用户登录钩子
	if pkg_mgr and user_mgr.is_logged_in:
		pkg_mgr.dispatch_user_login(user_mgr.get_username())
	# ★ 新用户教程触发
	if comm_mgr:
		comm_mgr.try_trigger_tutorial()
	# ★ 确保 COMM UI 已构建
	if comm_mgr and comm_mgr._ui:
		comm_mgr._ui._build_ui()
		if comm_mgr._ui._root:
			comm_mgr._ui._root.visible = true
	# ★ 登录后加载主线存档并触发每日剧情对话
	if daily_dialogue_mgr:
		daily_dialogue_mgr.load_main_storyline()  # 先加载主线剧情配置
		daily_dialogue_mgr.load_story_save()
	# ★ 登录后加载全局邮箱（必须在 trigger_day_start 之前，否则 delivered_ids 为空导致重复投递）
	if mail_sys:
		mail_sys.load_global_inbox()
	# ★ 加载玩家专属环境监测进度（覆盖 _ready 中的 start_new_game 初始状态）
	if env_monitor:
		if not env_monitor.load_env_progress():
			env_monitor.save_env_progress()  # 新玩家：写入初始存档
	if env_task_mgr:
		if not env_task_mgr.load_task_progress():
			env_task_mgr.reset_for_new_day()  # 新玩家：初始化当日任务
			env_task_mgr.save_task_progress()
		elif env_task_mgr.can_advance_day() and env_monitor:
			# 上次会话任务已全部完成，自动推进到下一天
			env_monitor.advance_day()
			env_task_mgr.reset_for_new_day()
			env_monitor.save_env_progress()
			env_task_mgr.save_task_progress()
			print("[Main] 自动推进至第 %d 天" % env_monitor.current_day)
	if daily_dialogue_mgr and env_monitor:
		daily_dialogue_mgr.trigger_day_start(env_monitor.current_day)
	# ★ 登录后加载主线剧情摄像头（只加载一次，不受故事包影响）
	if camera_mgr:
		camera_mgr.load_main_storyline_cameras()
	_request_scroll()



# ══════════════════════════════════════════
#  输入框文本变化 → 按键音效
# ══════════════════════════════════════════
var _last_input_length: int = 0  # 追踪输入长度变化方向
func _on_input_text_changed(new_text: String) -> void:
	if ui_sound == null:
		return
	var new_len: int = new_text.length()
	if new_len > _last_input_length:
		# 文本变长 → 输入字符
		ui_sound.play_keystroke()
	elif new_len < _last_input_length:
		# 文本变短 → 退格删除
		ui_sound.play_backspace()
	_last_input_length = new_len

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
			3: return "输入昵称 (skip 跳过)..."
			4: return "M / F / X (skip 跳过)..."
			5: return "YYYY-MM-DD (skip 跳过)..."
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
	_last_input_length = 0  # 重置长度追踪，避免下次输入触发误判
	input_field.grab_focus()
	if disc_mgr and disc_mgr.loading_screen and disc_mgr.loading_screen.is_active():
		return
	# ★ 全屏文章模式下不接受终端输入
	if article_viewer and article_viewer.is_active:
		return
	# ★ 聊天查看器模式下不接受终端输入
	if chat_viewer and chat_viewer.is_active:
		return
	# ★ 邮件查看器模式下不接受终端输入
	if email_viewer and email_viewer.is_active:
		return
	# ★ 双页查看器模式下不接受终端输入
	if two_page_viewer and two_page_viewer.is_active:
		return
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
	# ★ 通讯对话框活动时：根据等待状态决定阻断还是放行
	if comm_mgr and comm_mgr.is_active:
		if comm_mgr.is_waiting_for_command():
			pass  # 等待命令：完全放行，让命令正常执行
		elif comm_mgr.is_waiting_for_choice():
			return  # 等待选项：阻断（由数字键处理）
		else:
			# 普通对话推进
			comm_mgr._player.on_click()
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
			# ★ 通知设置系统主题已确认
			if settings_mgr:
				settings_mgr.on_theme_confirmed(ThemeManager.current_theme_name)
				settings_mgr.T = T
		else:
			ThemeManager.cancel_theme_change(self)
			# ★ 通知设置系统主题取消
			if settings_mgr:
				settings_mgr.on_theme_cancelled()
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
	# ★ 任何输入都重置空闲计时器
	if trigger_sys:
		trigger_sys.reset_idle()
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
				output_text.append_text(raw + "\n")
				_perform_shutdown()
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
	var w: String = T.warning_hex
	# 首次引导模式下不允许取消（必须完成注册）
	if raw.to_lower() == "cancel" and not _register_is_wizard:
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
			# 密码确认成功 → 进入个人信息收集阶段
			output_text.append_text("\n[color=" + m + "]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n")
			output_text.append_text("[color=" + w + "]个人信息登记[/color]\n")
			output_text.append_text("[color=" + m + "]以下信息将用于游戏内角色对话和剧情适配。[/color]\n")
			output_text.append_text("[color=" + m + "]输入 skip 可跳过当前项。[/color]\n\n")
			output_text.append_text("[color=" + p + "]该怎么称呼你？(昵称): [/color]")
			_register_step = 3
			_request_scroll()
		3:  # 昵称
			output_text.append_text(raw + "\n")
			if raw.to_lower() == "skip" or raw.is_empty():
				_register_nickname_input = ""
				output_text.append_text("[color=" + m + "](已跳过)[/color]\n\n")
			else:
				if raw.length() > 20:
					output_text.append_text("[color=" + e + "]昵称不能超过 20 个字符。[/color]\n")
					output_text.append_text("[color=" + p + "]该怎么称呼你？(昵称): [/color]")
					_request_scroll()
					return
				_register_nickname_input = raw
				output_text.append_text("[color=" + m + "]好的，" + raw + "。[/color]\n\n")
			output_text.append_text("[color=" + p + "]性别 [M=男 / F=女 / X=其他]: [/color]")
			_register_step = 4
			_request_scroll()
		4:  # 性别
			output_text.append_text(raw + "\n")
			if raw.to_lower() == "skip" or raw.is_empty():
				_register_gender_input = ""
				output_text.append_text("[color=" + m + "](已跳过)[/color]\n\n")
			else:
				var g: String = raw.to_upper().strip_edges()
				if g not in ["M", "F", "X"]:
					output_text.append_text("[color=" + e + "]请输入 M(男) / F(女) / X(其他)，或输入 skip 跳过。[/color]\n")
					output_text.append_text("[color=" + p + "]性别 [M=男 / F=女 / X=其他]: [/color]")
					_request_scroll()
					return
				_register_gender_input = g
				var gender_label: String = {"M": "男", "F": "女", "X": "其他"}.get(g, g)
				output_text.append_text("[color=" + m + "]已记录: " + gender_label + "[/color]\n\n")
			output_text.append_text("[color=" + p + "]出生日期 (格式 YYYY-MM-DD): [/color]")
			_register_step = 5
			_request_scroll()
		5:  # 生日
			output_text.append_text(raw + "\n")
			if raw.to_lower() == "skip" or raw.is_empty():
				_register_birthday_input = ""
				output_text.append_text("[color=" + m + "](已跳过)[/color]\n\n")
			else:
				# 验证日期格式
				var parts: PackedStringArray = raw.split("-")
				var valid: bool = parts.size() == 3
				if valid:
					for part_str in parts:
						if not part_str.is_valid_int():
							valid = false
							break
				if valid:
					var year: int = int(parts[0])
					var month: int = int(parts[1])
					var day: int = int(parts[2])
					if year < 1900 or year > 2100 or month < 1 or month > 12 or day < 1 or day > 31:
						valid = false
				if not valid:
					output_text.append_text("[color=" + e + "]日期格式错误，请使用 YYYY-MM-DD 格式（如 2000-01-15）。[/color]\n")
					output_text.append_text("[color=" + p + "]出生日期 (格式 YYYY-MM-DD): [/color]")
					_request_scroll()
					return
				_register_birthday_input = raw
				output_text.append_text("[color=" + m + "]已记录: " + raw + "[/color]\n\n")
			# 收集完毕 → 执行注册
			_finish_register()

func _finish_register() -> void:
	var p: String = T.primary_hex
	var e: String = T.error_hex
	var m: String = T.muted_hex
	var extra: Dictionary = {}
	if not _register_nickname_input.is_empty():
		extra["nickname"] = _register_nickname_input
	if not _register_gender_input.is_empty():
		extra["gender"] = _register_gender_input
	if not _register_birthday_input.is_empty():
		extra["birthday"] = _register_birthday_input
	var result: Dictionary = user_mgr.register(_register_username_input, _register_password_input, extra)
	_register_mode = false
	if result["success"]:
		if _register_is_wizard:
			output_text.append_text("[color=" + m + "]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n")
			output_text.append_text("[color=" + p + "]" + str(result["message"]) + "[/color]\n")
			output_text.append_text("[color=" + m + "]注册引导已完成。正在进入系统...[/color]\n")
		else:
			output_text.append_text("[color=" + p + "]" + str(result["message"]) + "[/color]\n")
		_enter_desktop_after_login(str(result["message"]))
	else:
		output_text.append_text("\n[color=" + e + "]" + str(result["message"]) + "[/color]\n\n")
		_start_login_flow()
	_register_is_wizard = false
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
## 窗口关闭事件 —— 直接关窗口时也保存进度
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if disc_mgr:
			disc_mgr._auto_save()
		get_tree().quit()

## 统一关机流程（登录界面和桌面命令都可调用）
func _perform_shutdown() -> void:
	# ★ 关机前保存所有进度（必须在 logout 前执行）
	if disc_mgr:
		disc_mgr._auto_save()
	# ★ NEW: 分发用户注销钩子
	if pkg_mgr and user_mgr.is_logged_in:
		pkg_mgr.dispatch_user_logout(user_mgr.get_username())
	# ★ 关机前关闭所有模组
	if pkg_mgr:
		pkg_mgr._shutdown_all_mods()
	# ★ 关机前清理通讯系统
	if comm_mgr:
		comm_mgr.cleanup()
	# ★ 关机前清理拨号系统
	if dial_mgr:
		dial_mgr.cleanup()
	if user_mgr.is_logged_in:
		user_mgr.logout()
	if boot_sequence:
		await get_tree().create_timer(0.3).timeout
		output_text.text = ""
		boot_sequence.play_shutdown()
	else:
		await get_tree().create_timer(0.5).timeout
		get_tree().quit()

func perform_logout() -> void:
	var m: String = T.muted_hex
	# ★ 注销前保存玩家进度（必须在 logout 前执行）
	if disc_mgr:
		disc_mgr._auto_save()
	# ★ NEW: 分发用户注销钩子
	if pkg_mgr and user_mgr.is_logged_in:
		pkg_mgr.dispatch_user_logout(user_mgr.get_username())
	# ★ 注销前关闭所有模组
	if pkg_mgr:
		pkg_mgr._shutdown_all_mods()
	# ★ 注销前清理通讯系统
	if comm_mgr:
		comm_mgr.cleanup()
	# ★ 注销前清理拨号系统
	if dial_mgr:
		dial_mgr.cleanup()
	# ★ 注销前保存并回退设置
	if settings_mgr:
		settings_mgr.on_user_logout()
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
	# ★ NEW: 提取命令名和参数，分发前置钩子
	var parts: PackedStringArray = raw.strip_edges().split(" ", false)
	var cmd_name: String = parts[0].to_lower() if parts.size() > 0 else ""
	var cmd_args: Array = []
	for i in range(1, parts.size()):
		cmd_args.append(parts[i])
	if pkg_mgr and not cmd_name.is_empty():
		var blocked: bool = pkg_mgr.dispatch_before_command(cmd_name, cmd_args)
		if blocked:
			_command_running = false
			_refocus_input.call_deferred()
			return
	await cmd_handler.execute(raw)
	# ★ NEW: 分发后置钩子
	if pkg_mgr and not cmd_name.is_empty():
		pkg_mgr.dispatch_after_command(cmd_name, cmd_args)
	# ★ 通知通讯系统命令已执行（传入参数以支持前缀匹配）
	if comm_mgr and comm_mgr.is_active:
		comm_mgr.on_command_executed(cmd_name, cmd_args)
	# ★ 通知每日剧情系统命令已执行（触发 on_command 类型对话）
	# 仅在磁盘含有 env_config（主线剧情模式）或桌面模式时触发
	var _disc_uses_env: bool = not _desktop_mode and story_manifest.has("env_config")
	if daily_dialogue_mgr and env_monitor and not cmd_name.is_empty() and (_desktop_mode or _disc_uses_env):
		daily_dialogue_mgr.trigger_command(env_monitor.current_day, cmd_name)
	_command_running = false
	_refocus_input.call_deferred()

func _refocus_input() -> void:
	input_field.grab_focus()
# ══════════════════════════════════════════
#  输入事件处理
# ══════════════════════════════════════════
func _input(event: InputEvent) -> void:
	# ★ 模组输入捕获优先处理
	if pkg_mgr and pkg_mgr.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	# ★ 呼叫处理器：铃声/等待接听状态下拦截输入
	if comm_mgr and comm_mgr.is_call_ringing():
		# 铃声播放中，吞掉所有按键
		if event is InputEventKey and event.pressed:
			get_viewport().set_input_as_handled()
			return
	# ★ 通讯系统输入处理（模组之后，viewer 之前）
	if comm_mgr and comm_mgr.is_active:
		# 等待命令/文件操作时，放行键盘事件给终端
		if comm_mgr.is_waiting_for_command() and event is InputEventKey:
			pass  # 放行
		elif comm_mgr.handle_input(event):
			get_viewport().set_input_as_handled()
			return
	
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
	# ★ 环境监测查看器模式优先处理输入
	if _env_viewer_mode and env_viewer and env_viewer.is_active:
		if env_viewer.handle_input(event):
			_env_viewer_mode = false if not env_viewer.is_active else true
			get_viewport().set_input_as_handled()
			return
	# ★ 监控摄像头模式
	if _camera_viewer_mode and camera_viewer and camera_viewer.is_active:
		if camera_viewer.handle_input(event):
			_camera_viewer_mode = false if not camera_viewer.is_active else true
			get_viewport().set_input_as_handled()
			return
	# ★ 密码解码器模式优先处理输入
	if _decode_mode and decode_viewer and decode_viewer.is_active:
		if decode_viewer.handle_input(event):
			get_viewport().set_input_as_handled()
			return
	# ★ 全屏模板模式优先处理输入
	if article_viewer and article_viewer.is_active:
		if article_viewer.handle_input(event):
			get_viewport().set_input_as_handled()
			return
	# ★ 聊天模板模式优先处理输入
	if chat_viewer and chat_viewer.is_active:
		if chat_viewer.handle_input(event):
			get_viewport().set_input_as_handled()
			return
	# ★ 邮件查看器模式优先处理输入
	if email_viewer and email_viewer.is_active:
		if email_viewer.handle_input(event):
			get_viewport().set_input_as_handled()
			return
	# ★ 双页查看器模式优先处理输入
	if two_page_viewer and two_page_viewer.is_active:
		if two_page_viewer.handle_input(event):
			get_viewport().set_input_as_handled()
			return
	# ★ 文档查看器优先处理输入
	if doc_viewer and doc_viewer.is_active:
		if doc_viewer.handle_input(event):
			get_viewport().set_input_as_handled()
			return
	# ★ 探索进度查看器
	if explore_viewer and explore_viewer.is_active:
		if explore_viewer.handle_input(event):
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
				# ★ 检测邮件图标点击
				if mail_icon != null and mail_icon.get_global_rect().has_point(mouse_pos):
					if user_mgr != null and user_mgr.is_logged_in and mail_sys != null:
						mail_sys.handle_mail_command([])
					get_viewport().set_input_as_handled()
					return
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
	# 开关机序列中：按任意键跳过
	if boot_sequence and boot_sequence.is_active():
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]:
			boot_sequence.skip()
			get_viewport().set_input_as_handled()
			return
# 载入画面跳过（按任意键）
	if disc_mgr and disc_mgr.loading_screen and disc_mgr.loading_screen.is_active():
		if event is InputEventKey and event.pressed:
			disc_mgr.loading_screen.skip()
			get_viewport().set_input_as_handled()
		return
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
			# ★ 磁盘模式下空输入 Tab 切换探索视图
			if not _desktop_mode and input_field.text.strip_edges().is_empty():
				if explore_viewer:
					explore_viewer.toggle()
				if ui_sound:
					ui_sound.play_click()
				get_viewport().set_input_as_handled()
			else:
				if ui_sound:
					ui_sound.play_click()
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
			var tab_parts: PackedStringArray = c.split(" ", false)
			if tab_parts.size() > 0:
				display_items.append(tab_parts[-1])
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

## 通讯对话框文本滚动到底部（由 comm_ui 延迟调用）
func _comm_scroll_to_bottom() -> void:
	if comm_mgr and comm_mgr._ui and comm_mgr._ui._text_scroll:
		var v_bar: VScrollBar = comm_mgr._ui._text_scroll.get_v_scroll_bar()
		if v_bar:
			comm_mgr._ui._text_scroll.scroll_vertical = int(v_bar.max_value)


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
	# ★ 双页模板更新
	if two_page_viewer and two_page_viewer.is_active:
		two_page_viewer.process_typing(delta)
	# 开关机序列驱动
	if boot_sequence and boot_sequence.is_active():
		boot_sequence.process(delta)
	# ★ 载入画面驱动
	if disc_mgr and disc_mgr.loading_screen and disc_mgr.loading_screen.is_active():
		disc_mgr.loading_screen.process(delta)
	# ★ 模组系统每帧更新
	if pkg_mgr:
		pkg_mgr.process(delta)
	# ★ 通讯系统更新（始终更新，含按钮位置）
	if comm_mgr:
		comm_mgr.process(delta)
	# ★ 拨号管理器更新
	if dial_mgr:
		dial_mgr.process(delta)
	# 效果系统每帧驱动
	if effect_sys:
		effect_sys.process(delta)
	# ★ 触发器和邮件系统每帧更新
	if trigger_sys:
		trigger_sys.process(delta)
	if mail_sys:
		mail_sys.process(delta)
	# ★ 邮件模板更新
	if email_viewer and email_viewer.is_active:
		email_viewer.process_typing(delta)
	# ★ 环境监测系统每帧更新
	if env_monitor:
		env_monitor.process(delta)
	if env_viewer and env_viewer.is_active:
		env_viewer.process(delta)
	# ★ 监控摄像头系统
	if camera_mgr:
		camera_mgr.process(delta)
	if camera_viewer and camera_viewer.is_active:
		camera_viewer.process(delta)

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
	# ★ 命令链接：执行前关闭活动 viewer（two_page/doc）
	if meta_str.begins_with("cmd://"):
		var cmd: String = meta_str.substr(6)
		if email_viewer and email_viewer.is_active:
			email_viewer.close()
		if chat_viewer and chat_viewer.is_active:
			chat_viewer.close()
		if two_page_viewer and two_page_viewer.is_active:
			two_page_viewer.close()
		if doc_viewer and doc_viewer.is_active:
			doc_viewer.close()
		if article_viewer and article_viewer.is_active:
			article_viewer.close()
		output_text.append_text("\n> " + cmd + "\n")
		_run_command(cmd)
		return
	# ★ 剧透文本（在任何模式下都追加到当前输出目标）
	if meta_str.begins_with("spoiler://"):
		var decoded_text: String = meta_str.substr(10).uri_decode()
		_audio_status_output("\n[color=" + T.muted_hex + "][已揭示] " + decoded_text + "[/color]\n")
		_request_scroll()
		return
	# ★ 文件链接：执行前关闭活动 viewer（two_page/doc）
	if meta_str.begins_with("file://"):
		var file_path: String = meta_str.substr(7)
		if email_viewer and email_viewer.is_active:
			email_viewer.close()
		if chat_viewer and chat_viewer.is_active:
			chat_viewer.close()
		if two_page_viewer and two_page_viewer.is_active:
			two_page_viewer.close()
		if doc_viewer and doc_viewer.is_active:
			doc_viewer.close()
		if article_viewer and article_viewer.is_active:
			article_viewer.close()
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
	if email_viewer != null and email_viewer.is_active:
		var rtl: RichTextLabel = email_viewer.get_active_page_rtl()
		if rtl != null:
			rtl.append_text("\n" + text)
		return
	if chat_viewer != null and chat_viewer.is_active and chat_viewer.has_method("get_active_page_rtl"):
		var rtl: RichTextLabel = chat_viewer.get_active_page_rtl()
		if rtl != null:
			rtl.append_text("\n" + text)
		return
	if article_viewer != null and article_viewer.is_active and article_viewer.has_method("get_active_page_rtl"):
		var rtl: RichTextLabel = article_viewer.get_active_page_rtl()
		if rtl != null:
			rtl.append_text("\n" + text)
		return
	if two_page_viewer != null and two_page_viewer.is_active and two_page_viewer.has_method("get_active_page_rtl"):
		var rtl: RichTextLabel = two_page_viewer.get_active_page_rtl()
		if rtl != null:
			rtl.append_text("\n" + text)
		return
	if doc_viewer != null and doc_viewer.is_active:
		var active_rtl: RichTextLabel = doc_viewer.get_active_page_rtl()
		if active_rtl != null:
			active_rtl.append_text("\n" + text)
		return
	# 终端模式
	append_output(text, false, false)


## ★ 输出音频状态信息（自动判断输出目标：two_page / document / 终端）
func _audio_status_output(text: String) -> void:
	# email_viewer 模式
	if email_viewer != null and email_viewer.is_active:
		var rtl: RichTextLabel = email_viewer.get_active_page_rtl()
		if rtl != null:
			rtl.append_text("\n" + text)
			return
	# chat_viewer 模式
	if chat_viewer != null and chat_viewer.is_active and chat_viewer.has_method("get_active_page_rtl"):
		var rtl: RichTextLabel = chat_viewer.get_active_page_rtl()
		if rtl != null:
			rtl.append_text("\n" + text)
			return
	# article_viewer 模式
	if article_viewer != null and article_viewer.is_active and article_viewer.has_method("get_active_page_rtl"):
		var rtl: RichTextLabel = article_viewer.get_active_page_rtl()
		if rtl != null:
			rtl.append_text("\n" + text)
			return
	# two_page_viewer 模式
	if two_page_viewer != null and two_page_viewer.is_active and two_page_viewer.has_method("get_active_page_rtl"):
		var rtl_b: RichTextLabel = two_page_viewer.get_active_page_rtl()
		if rtl_b != null:
			rtl_b.append_text("\n" + text)
			return
	# document_viewer 模式
	if doc_viewer != null and doc_viewer.is_active:
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
	# 邮件图标：始终显示 [Mail]，有未读邮件时由 mail_sys._tick_blink 控制闪烁（透明度）
	if mail_icon != null:
		mail_icon.text = "[Mail]"
		# 确保在非闪烁状态下透明度为1
		if mail_sys == null or not mail_sys._blink_active:
			mail_icon.modulate = Color(1, 1, 1, 1)
func _update_status_bar_login() -> void:
	path_label.text = "SCP TERMINAL | 身份验证"
	mail_icon.text = ""

## 加载故事包时同步初始化效果系统（由 disc_manager 调用）
func load_effects_from_manifest(manifest: Dictionary) -> void:
	if effect_sys:
		effect_sys.load_from_manifest(manifest)
		# 更新效果系统的主题引用
		effect_sys.T = T
		effect_sys.crt_shader = crt_shader

## 效果强度设置命令处理
## 用法: fx_level [full|mild|off]
## 用法: fx_safe [on|off]
func handle_fx_command(cmd: String, args: Array) -> bool:
	if effect_settings == null:
		return false
	match cmd:
		"fx_level":
			if args.is_empty():
				var current: String = effect_settings.get_level_name()
				append_output("[color=" + T.primary_hex + "]当前效果等级: " + current + "[/color]\n", false)
				append_output("[color=" + T.muted_hex + "]可选: full (完整) | mild (温和) | off (关闭)[/color]\n", false)
				return true
			var level_str: String = str(args[0]).to_lower()
			match level_str:
				"full":
					effect_settings.set_level(EffectSettings.Level.FULL)
					append_output("[color=" + T.success_hex + "]效果等级已设为: 完整[/color]\n", false)
				"mild":
					effect_settings.set_level(EffectSettings.Level.MILD)
					append_output("[color=" + T.warning_hex + "]效果等级已设为: 温和 (强度降低50%)[/color]\n", false)
				"off":
					effect_settings.set_level(EffectSettings.Level.OFF)
					append_output("[color=" + T.muted_hex + "]所有动态效果已关闭[/color]\n", false)
				_:
					append_output("[color=" + T.error_hex + "]无效选项: " + level_str + " (可选: full/mild/off)[/color]\n", false)
			return true
		"fx_safe":
			if args.is_empty():
				var status: String = "开启" if effect_settings.photosensitive_mode else "关闭"
				append_output("[color=" + T.primary_hex + "]光敏安全模式: " + status + "[/color]\n", false)
				append_output("[color=" + T.muted_hex + "]用法: fx_safe on/off[/color]\n", false)
				return true
			var val: String = str(args[0]).to_lower()
			if val == "on" or val == "true" or val == "1":
				effect_settings.set_photosensitive(true)
				append_output("[color=" + T.success_hex + "]光敏安全模式已开启 — 已禁用闪烁、强故障、jumpscare[/color]\n", false)
			else:
				effect_settings.set_photosensitive(false)
				append_output("[color=" + T.warning_hex + "]光敏安全模式已关闭[/color]\n", false)
			return true
	return false

# ── Shader uniform 辅助方法 ──
## 设置背景图(TextureRect)的 shader uniform
func _set_background_shader_value(uniform_name: String, value: float) -> void:
	if background == null:
		return
	var mat: ShaderMaterial = background.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter(uniform_name, value)
## 设置 logo(TextureRect)的 shader uniform
func _set_logo_shader_value(uniform_name: String, value: float) -> void:
	if background_logo == null:
		return
	var mat: ShaderMaterial = background_logo.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter(uniform_name, value)
## Tween 方式渐变 shader uniform
func _tween_background_shader(uniform_name: String, from: float, to: float, duration: float) -> Tween:
	if background == null:
		return null
	var mat: ShaderMaterial = background.material as ShaderMaterial
	if mat == null:
		return null
	mat.set_shader_parameter(uniform_name, from)
	var tw_shader: Tween = create_tween()
	tw_shader.tween_method(func(v: float): mat.set_shader_parameter(uniform_name, v), from, to, duration)
	return tw_shader
func _tween_logo_shader(uniform_name: String, from: float, to: float, duration: float) -> Tween:
	if background_logo == null:
		return null
	var mat: ShaderMaterial = background_logo.material as ShaderMaterial
	if mat == null:
		return null
	mat.set_shader_parameter(uniform_name, from)
	var tw_shader: Tween = create_tween()
	tw_shader.tween_method(func(v: float): mat.set_shader_parameter(uniform_name, v), from, to, duration)
	return tw_shader


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
	# ★ 环境监测日提示（仅当磁盘包含 env_config 配置时才显示）
	var disc_uses_env: bool = env_monitor != null and story_manifest.has("env_config")
	if disc_uses_env:
		append_output("[color=%s]═══════════════════════════════════════[/color]\n" % p, false)
		append_output("[color=%s]  %s 开始  —  %s[/color]\n" % [p, env_monitor.get_day_display(), env_monitor.get_weather_name()], false)
		append_output("[color=%s]═══════════════════════════════════════[/color]\n" % p, false)
		append_output("[color=%s]今日天气: %s，风向 %s，气温 %.1f°C[/color]\n" % [
			m, env_monitor.get_weather_name(), env_monitor.get_wind_direction_name(), env_monitor.get_reading("air_temp")], false)
		# 活跃事件提醒
		var events: Dictionary = env_monitor.get_active_events()
		if events.size() > 0:
			for eid in events.keys():
				var evt: Dictionary = events[eid]
				var col: String = T.error_hex if evt.get("scp_related", false) else T.warning_hex
				append_output("[color=" + col + "]! 事件进行中: %s[/color]\n" % str(evt.get("name", eid)), false)
		append_output("[color=%s]输入 env scan 执行自动检测，或 env help 查看所有命令。[/color]\n\n" % m, false)
	else:
		append_output("[color=" + m + "]输入 help 查看可用命令。[/color]\n\n", false)

# ============================================================
# 触发器系统动作接口（由 trigger_system.gd / typewriter.gd 调用）
# ★ 所有效果都经过 effect_settings 强度衰减
# ============================================================
func trigger_glitch(intensity: float = 0.5, duration: float = 1.0, preset: String = "custom") -> void:
	if effect_settings and effect_settings.is_off():
		return
	if effect_settings:
		intensity = effect_settings.apply_intensity(intensity)
		if duration < 90.0:
			duration = effect_settings.apply_duration(duration)
		preset = effect_settings.downgrade_preset(preset)
	if crt_shader and crt_shader.has_method("play_glitch"):
		crt_shader.play_glitch(intensity, duration, preset)
func trigger_screen_off(duration: float = 2.0) -> void:
	if effect_settings and not effect_settings.is_effect_allowed("blackout"):
		return
	if effect_settings and effect_settings.is_mild():
		duration = duration * 0.5  # 温和模式缩短黑屏
	if crt_shader and crt_shader.has_method("play_blackout"):
		crt_shader.play_blackout(duration)
func trigger_reboot() -> void:
	if effect_settings and effect_settings.is_off():
		output_text.text = ""
		_show_welcome_message()
		return
	if crt_shader and crt_shader.has_method("play_reboot"):
		output_text.text = ""
		if not crt_shader.boot_completed.is_connected(_on_reboot_boot_done):
			crt_shader.boot_completed.connect(_on_reboot_boot_done, CONNECT_ONE_SHOT)
		crt_shader.play_reboot()
	else:
		output_text.text = ""
		_show_welcome_message()
func _on_reboot_boot_done() -> void:
	_show_welcome_message()
func trigger_shake(intensity: float = 0.01, duration: float = 0.5) -> void:
	if effect_settings:
		intensity = effect_settings.apply_shake_intensity(intensity)
		if duration < 90.0:
			duration = effect_settings.apply_duration(duration)
	if intensity <= 0.001:
		if crt_shader and crt_shader.has_method("play_shake"):
			crt_shader.play_shake(0.0, 0.05)
		return
	if crt_shader and crt_shader.has_method("play_shake"):
		crt_shader.play_shake(intensity, duration)
func trigger_tear(strength: float = 0.08, duration: float = 0.5) -> void:
	if effect_settings:
		strength = effect_settings.apply_intensity(strength)
		if duration < 90.0:
			duration = effect_settings.apply_duration(duration)
	if strength <= 0.001:
		if crt_shader and crt_shader.has_method("play_tear"):
			crt_shader.play_tear(0.0, -1.0, 0.05)
		return
	if crt_shader and crt_shader.has_method("play_tear"):
		crt_shader.play_tear(strength, -1.0, duration)
func trigger_noise_burst(intensity: float = 0.8, duration: float = 0.3) -> void:
	if effect_settings and not effect_settings.is_effect_allowed("noise_burst"):
		return
	if effect_settings:
		intensity = effect_settings.apply_intensity(intensity)
		if duration < 90.0:
			duration = effect_settings.apply_duration(duration)
	if crt_shader and crt_shader.has_method("play_noise_burst"):
		crt_shader.play_noise_burst(intensity, duration)
func trigger_effect(effect_id: String) -> void:
	if effect_settings and effect_settings.is_off():
		return
	if effect_sys:
		effect_sys.play(effect_id)
func trigger_preset_effect(preset_name: String, duration: float = 2.0) -> void:
	if effect_settings and not effect_settings.is_effect_allowed(preset_name):
		# 被光敏模式阻止的预设降级为温和效果
		if effect_settings.is_effect_allowed("disturb"):
			preset_name = "unease"
		else:
			return
	if effect_settings:
		duration = effect_settings.apply_duration(duration)
	if effect_sys == null:
		return
	match preset_name:
		"unease":
			effect_sys.play_unease(duration)
		"disturb":
			effect_sys.play_disturb(duration)
		"jumpscare":
			effect_sys.play_jumpscare_base(duration)
		"crash":
			effect_sys.play_system_crash(duration)
		_:
			push_warning("[Main] 未知预设效果: " + preset_name)
