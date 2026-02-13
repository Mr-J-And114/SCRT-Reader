extends Control


# ============================================================
# 节点引用 - 通过 @onready 在场景准备好后自动获取节点
# ============================================================
@onready var path_label: Label = $MainContent/StatusFrame/StatusBar/PathLabel
@onready var mail_icon: Label = $MainContent/StatusFrame/StatusBar/MailIcon
@onready var output_text: RichTextLabel = $MainContent/OutputArea/OutputText
@onready var input_field: LineEdit = $MainContent/InputFrame/InputArea/InputField
@onready var scroll_container: ScrollContainer = $MainContent/OutputArea
@onready var status_frame: PanelContainer = $MainContent/StatusFrame
@onready var input_frame: PanelContainer = $MainContent/InputFrame
var background: TextureRect = null  # 由代码动态创建背景


# 模块实例
var save_mgr: SaveManager = SaveManager.new()


# ============================================================
# 状态变量
# ============================================================
var current_path: String = "/"
var has_new_mail: bool = false
var command_history: Array[String] = []
var history_index: int = -1
var current_input_backup: String = ""
var _needs_scroll: bool = false

# 桌面/终端模式
var _desktop_mode: bool = true             # true=桌面模式，false=终端模式（已加载磁盘）

# 打字机效果

var _typewriter_queue: Array[Dictionary] = []  # 待显示的文本队列
var _is_typing: bool = false               # 是否正在打字
var _typewriter_speed: float = 0.008         # 基础速度
var _typewriter_instant: bool = false
var _typewriter_pause_chance: float = 0.08   # 随机停顿概率（0~1）
var _typewriter_pause_duration: float = 0.06 # 停顿时长（秒）
var _typewriter_comma_pause: float = 0.04    # 逗号/分号后的停顿
var _typewriter_period_pause: float = 0.08   # 句号/冒号/换行后的停顿
var _current_char_speed: float = 0.008       # 当前生效的速度（可被文档局部控制）
var _progress_bar_speed: float = 1.0         # 进度条基础速度倍率

# ============================================================
# 虚拟文件系统
# ============================================================
var file_system: Dictionary = {}
var story_loader: StoryLoader = null
var story_manifest: Dictionary = {}
var current_story_path: String = ""
var available_stories: Array[Dictionary] = []  # [{path, title, id}]
var current_story_index: int = -1              # 当前加载的剧本索引

# 权限系统
var player_clearance: int = 0              # 当前权限等级
var story_permissions: Dictionary = {}      # 路径 -> 所需权限等级
var story_id: String = ""                   # 当前剧本唯一ID
var read_files: Array[String] = []          # 已读文件列表
var unlocked_passwords: Array[String] = []  # 已解锁的密码
# 密码输入弹窗状态
var _password_mode: bool = false            # 是否处于密码输入模式（unlock用）
var _password_target_path: String = ""      # 密码输入针对的路径（空表示通用unlock）

# 文件密码系统
var _file_password_mode: bool = false       # 是否处于文件密码输入模式
var _file_password_target: String = ""      # 当前等待密码的文件路径
var _file_password_filename: String = ""    # 当前等待密码的文件名（用于显示）
var story_file_passwords: Dictionary = {}   # 路径 -> {password, hint}
var unlocked_file_passwords: Array[String] = []  # 已解锁的文件路径列表

# ============================================================
# 初始化
# ============================================================
	# 尝试加载剧本，如果失败则用测试数据
func _ready() -> void:
	save_mgr.ensure_stories_dir()
	save_mgr.ensure_saves_dir()

	# 启动时只扫描，不自动加载
	var vdisc_dir: String = save_mgr.get_game_root_dir() + "vdisc/"
	_scan_available_stories(vdisc_dir)

	# === 背景初始化 ===
	_setup_background()
	# 确保主内容在背景之上
	var main_content := $MainContent
	if main_content:
		move_child(main_content, get_child_count() - 1)
	# 让主内容区背景透明以显示底层背景图
	if main_content is Control:
		var transparent_style := StyleBoxFlat.new()
		transparent_style.bg_color = Color(0, 0, 0, 0)
		transparent_style.set_border_width_all(0)
		main_content.add_theme_stylebox_override("panel", transparent_style)


	# === UI 边框样式 ===
	# 状态栏外框（StatusFrame）- 保留外层框，降低发光
	var status_frame_style := StyleBoxFlat.new()
	status_frame_style.bg_color = Color(0.0, 0.04, 0.0, 0.9)
	status_frame_style.border_color = Color(0.2, 0.6, 0.2, 0.4)
	status_frame_style.set_border_width_all(1)
	status_frame_style.content_margin_left = 4
	status_frame_style.content_margin_right = 4
	status_frame_style.content_margin_top = 3
	status_frame_style.content_margin_bottom = 3
	status_frame.add_theme_stylebox_override("panel", status_frame_style)

	# PathLabel - 去掉内框（透明无边框）
	var path_label_style := StyleBoxFlat.new()
	path_label_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	path_label_style.border_color = Color(0.0, 0.0, 0.0, 0.0)
	path_label_style.set_border_width_all(0)
	path_label_style.content_margin_left = 6
	path_label_style.content_margin_right = 6
	path_label_style.content_margin_top = 2
	path_label_style.content_margin_bottom = 2
	path_label.add_theme_stylebox_override("normal", path_label_style)

	# MailIcon - 保留内框，降低发光
	var mail_style := StyleBoxFlat.new()
	mail_style.bg_color = Color(0.0, 0.03, 0.0, 0.6)
	mail_style.border_color = Color(0.2, 0.6, 0.2, 0.35)
	mail_style.set_border_width_all(1)
	mail_style.content_margin_left = 8
	mail_style.content_margin_right = 8
	mail_style.content_margin_top = 2
	mail_style.content_margin_bottom = 2
	mail_icon.add_theme_stylebox_override("normal", mail_style)

	# 输入区外框（InputFrame）- 只保留这一层框，降低发光
	var input_frame_style := StyleBoxFlat.new()
	input_frame_style.bg_color = Color(0.0, 0.04, 0.0, 0.9)
	input_frame_style.border_color = Color(0.2, 0.6, 0.2, 0.4)
	input_frame_style.set_border_width_all(1)
	input_frame_style.content_margin_left = 4
	input_frame_style.content_margin_right = 4
	input_frame_style.content_margin_top = 3
	input_frame_style.content_margin_bottom = 3
	input_frame.add_theme_stylebox_override("panel", input_frame_style)

	# InputField - 去掉内框（透明无边框），只靠外层 InputFrame 提供边框
	var input_no_border := StyleBoxFlat.new()
	input_no_border.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	input_no_border.border_color = Color(0.0, 0.0, 0.0, 0.0)
	input_no_border.set_border_width_all(0)
	input_no_border.content_margin_left = 6
	input_no_border.content_margin_right = 6
	input_no_border.content_margin_top = 2
	input_no_border.content_margin_bottom = 2
	input_field.add_theme_stylebox_override("normal", input_no_border)
	input_field.add_theme_stylebox_override("focus", input_no_border.duplicate())

	output_text.text = ""
	output_text.bbcode_enabled = true
	output_text.selection_enabled = true
	output_text.meta_underlined = true
	output_text.meta_clicked.connect(_on_meta_clicked)

	input_field.focus_mode = Control.FOCUS_ALL
	input_field.focus_next = input_field.get_path()
	input_field.focus_previous = input_field.get_path()
	input_field.grab_focus()

	_desktop_mode = true
	_update_status_bar()
	_show_desktop_welcome()


# ============================================================
# 输入处理 - 处理键盘事件（命令历史等）
# ============================================================
func _input(event: InputEvent) -> void:
	# 鼠标滚轮滚动
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
			MOUSE_BUTTON_LEFT:
				# 点击任意位置聚焦输入框
				input_field.grab_focus()
				return
	
	if not event is InputEventKey or not event.pressed:
		return
	
	# 点击任何键都确保输入框有焦点
	if not input_field.has_focus():
		input_field.grab_focus()

	# 如果正在打字或加载，按空格或ESC跳过动画
	if _is_typing and event.keycode in [KEY_SPACE, KEY_ESCAPE]:
		_typewriter_instant = true
		get_viewport().set_input_as_handled()
		return


	match event.keycode:

		KEY_ENTER, KEY_KP_ENTER:
			# 如果正在打字，忽略回车（防止干扰）
			if _is_typing:
				get_viewport().set_input_as_handled()
			else:
				var command_text: String = input_field.text
				input_field.clear()
				_on_command_submitted(command_text)
				get_viewport().set_input_as_handled()


		KEY_UP:
			_history_previous()
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			_history_next()
			get_viewport().set_input_as_handled()
		KEY_PAGEUP:
			scroll_container.scroll_vertical -= 100
			get_viewport().set_input_as_handled()
		KEY_PAGEDOWN:
			scroll_container.scroll_vertical += 100
			get_viewport().set_input_as_handled()
		KEY_TAB:
			_auto_complete()
			get_viewport().set_input_as_handled()


# ============================================================
# 命令提交处理 - 用户按回车后调用
# ============================================================
func _on_command_submitted(command_text: String) -> void:
	var raw_input: String = command_text.strip_edges()
	input_field.clear()
	
	if raw_input.is_empty():
		return


	# 如果处于文件密码输入模式
	if _file_password_mode:
		_file_password_mode = false
		input_field.placeholder_text = "> 输入命令..."
		
		# 等待打字队列完成
		while _is_typing:
			await get_tree().process_frame
		
		# 密码回显用星号
		if output_text.get_parsed_text().length() > 0:
			output_text.append_text("\n")
		output_text.append_text("> " + "*".repeat(raw_input.length()) + "\n")
		
		if raw_input.to_lower() == "cancel":
			append_output("[color=#AAAAAA]已取消文件密码输入。[/color]\n", false)
			_file_password_target = ""
			_file_password_filename = ""
			return
		
		await _verify_file_password(raw_input)
		return


	# 如果处于密码输入模式
	if _password_mode:
		_password_mode = false
		input_field.placeholder_text = "> 输入命令..."
		
		# 等待打字队列完成
		while _is_typing:
			await get_tree().process_frame
		
		# 密码回显用星号
		if output_text.get_parsed_text().length() > 0:
			output_text.append_text("\n")
		output_text.append_text("> " + "*".repeat(raw_input.length()) + "\n")
		
		if raw_input.to_lower() == "cancel":
			append_output("[color=#AAAAAA]已取消密码输入。[/color]\n", false)
			return
		
		_verify_password(raw_input)
		return
	
	command_history.append(raw_input)
	history_index = -1
	
	# 等待打字队列完成
	while _is_typing:
		await get_tree().process_frame
	
	# 命令回显用即时显示（不走打字机）
	if output_text.get_parsed_text().length() > 0:
		output_text.append_text("\n")
	output_text.append_text("> " + raw_input + "\n")
	
	# 执行命令（命令输出走打字机效果）
	await _execute_command(raw_input)




# ============================================================
# 命令解析与执行
# ============================================================
func _execute_command(raw_input: String) -> void:
	_typewriter_instant = false
	
	var parts := raw_input.split(" ", false)
	if parts.is_empty():
		return
	
	var command: String = parts[0].to_lower()
	var args := parts.slice(1)
	
	# 桌面模式：只允许少数命令
	if _desktop_mode:
		match command:
			"load":
				await _cmd_desktop_load(args)
			"scan":
				await _cmd_scan()
			"clear", "cls":
				_cmd_clear()
			"exit", "quit":
				await _cmd_exit()
			"help", "?":
				_cmd_desktop_help()
			"vdisc", "disc", "disk":
				_cmd_story_info()
			"reboot", "restart":
				await _cmd_reboot()
			_:
				append_output("[color=#FF6666][ERROR] 未知指令: " + command + "[/color]\n[color=#AAAAAA]输入 [/color][color=#66FF66]help[/color][color=#AAAAAA] 查看可用命令。[/color]\n", false)
		return
	
	# 终端模式：所有命令可用
	match command:
		"help", "?":
			_cmd_help()
		"ls", "dir":
			_cmd_ls()
		"cd":
			_cmd_cd(args)
		"open", "cat":
			await _cmd_open(args)
		"back":
			_cmd_back()
		"clear", "cls":
			_cmd_clear()
		"status":
			_cmd_status()
		"mail":
			_cmd_mail(args)
		"exit", "quit":
			await _cmd_exit()
		"whoami":
			_cmd_whoami()
		"vdisc", "disc", "disk":
			if args.size() >= 1 and args[0].to_lower() == "load":
				await _cmd_vdisc_load(args.slice(1))
			else:
				_cmd_story_info()
		"unlock":
			_cmd_unlock(args)
		"scan":
			await _cmd_scan()
		"reboot", "restart":
			await _cmd_reboot()
		"eject":
			await _cmd_eject()
		"load":
			append_output("[color=#AAAAAA]磁盘已加载。使用 [/color][color=#66FF66]eject[/color][color=#AAAAAA] 返回桌面后再切换磁盘，或使用 [/color][color=#66FF66]vdisc load <编号>[/color][color=#AAAAAA] 直接切换。[/color]\n", false)
		_:
			append_output("[color=#FF6666][ERROR] 未知指令: " + command + "[/color]\n输入 [color=#66FF66]help[/color] 查看可用命令。\n", false)


# ============================================================
# 各命令的具体实现
# ============================================================
func _cmd_desktop_help() -> void:
	var lines: Array[String] = []
	lines.append("[color=#66FF66]═══════════════ 桌面命令 ═══════════════[/color]")
	lines.append("  [color=#66FF66]load <编号>[/color]   加载指定虚拟磁盘")
	lines.append("  [color=#66FF66]scan[/color]		  重新扫描vdisc目录")
	lines.append("  [color=#66FF66]vdisc[/color]		 查看磁盘列表详情")
	lines.append("  [color=#66FF66]clear[/color]		 清空屏幕")
	lines.append("  [color=#66FF66]reboot[/color]		重启终端")
	lines.append("  [color=#66FF66]exit[/color]		  退出终端")
	lines.append("[color=#66FF66]═══════════════════════════════════════[/color]")
	append_output("\n".join(lines) + "\n", false)



func _cmd_help() -> void:
	var lines: Array[String] = []
	lines.append("[color=#66FF66]═══════════════════ 可用命令 ═══════════════════[/color]")
	lines.append("  [color=#66FF66]help[/color]          显示本帮助信息")
	lines.append("  [color=#66FF66]ls[/color]            列出当前目录下的文件和文件夹")
	lines.append("  [color=#66FF66]cd <路径>[/color]     切换到指定目录")
	lines.append("  [color=#66FF66]back[/color]          返回上一级目录")
	lines.append("  [color=#66FF66]open <文件>[/color]   打开并显示文件内容")
	lines.append("  [color=#66FF66]clear[/color]         清空屏幕")
	lines.append("  [color=#66FF66]status[/color]        查看当前用户状态")
	lines.append("  [color=#66FF66]mail[/color]          查看收件箱")
	lines.append("  [color=#66FF66]whoami[/color]        查看当前用户信息")
	lines.append("  [color=#66FF66]vdisc[/color]         查看虚拟磁盘列表和信息")
	lines.append("  [color=#66FF66]vdisc load <编号>[/color] 切换加载指定磁盘")
	lines.append("  [color=#66FF66]scan[/color]          重新扫描虚拟磁盘")
	lines.append("  [color=#66FF66]unlock[/color]        进入密码认证（或 unlock <密码>）")
	lines.append("  [color=#66FF66]eject[/color]         卸载磁盘，返回桌面")
	lines.append("  [color=#66FF66]reboot[/color]        重启终端")
	lines.append("  [color=#66FF66]exit[/color]          退出终端")
	lines.append("[color=#66FF66]═══════════════════════════════════════════════[/color]")
	lines.append("[color=#AAAAAA]快捷键: ↑↓ 历史命令 | PageUp/Down 滚动 | Tab 自动补全[/color]")
	append_output("\n".join(lines) + "\n", false)

func _cmd_ls() -> void:
	var items := _get_children_at_path(current_path)
	
	if items.is_empty():
		append_output("[color=#AAAAAA]该目录为空。[/color]")
		return
	
	# 拼接所有行到一个字符串中，用换行符分隔
	var lines: Array[String] = []
	lines.append("[color=#66FF66]目录: " + current_path + "[/color]")
	lines.append("")
	
	for item in items:
		var item_path := _join_path(current_path, item)
		var node := _get_node_at_path(item_path)
		if node == null:
			continue
		
		var item_required: int = _get_required_clearance(item_path)
		var is_locked: bool = not _has_clearance(item_path)
		
		if node.type == "folder":
			if is_locked:
				lines.append("  [color=#FF6666][DIR]  " + item + "/  【LOCKED LV." + str(item_required) + "】[/color]")
			else:
				lines.append("  [color=#6699FF][DIR]  " + item + "/[/color]")
		else:
			if is_locked:
				lines.append("  [color=#FF6666][FILE] " + item + "  【LOCKED LV." + str(item_required) + "】[/color]")
			else:
				# 检查是否需要文件密码
				var fp_key: String = _get_file_password_key(item_path)
				if not fp_key.is_empty() and not unlocked_file_passwords.has(item_path):
					lines.append("  [color=#FFB000][FILE] " + item + "  [PASSWORD][/color]")
				else:
					lines.append("  [color=#33FF33][FILE] " + item + "[/color]")


	
	lines.append("")
	
	# 一次性输出，用换行符连接
	append_output("\n".join(lines) + "\n", false)

func _cmd_cd(args: Array) -> void:
	if args.is_empty():
		append_output("[color=#FF6666][ERROR] 用法: cd <目录名>[/color]")
		return
	
	var target: String = args[0]
	var new_path: String
	
	if target == "/":
		new_path = "/"
	elif target == "..":
		new_path = _get_parent_path(current_path)
	elif target.begins_with("/"):
		new_path = target
	else:
		new_path = _join_path(current_path, target)
	
	new_path = _normalize_path(new_path)
	
	var node := _get_node_at_path(new_path)
	if node == null:
		append_output("[color=#FF6666][ERROR] 目录不存在: " + target + "[/color]")
		return
	if node.type != "folder":
	 # 调试输出
		print("[DEBUG] cd 目标: " + new_path + " 需要权限: " + str(_get_required_clearance(new_path)) + " 当前权限: " + str(player_clearance))
		append_output("[color=#FF6666][ERROR] " + target + " 不是一个目录。[/color]")
		return


	# 权限检查
	var required: int = _get_required_clearance(new_path)
	if not _has_clearance(new_path):
		var box: String = _build_box_sectioned([
			["ACCESS DENIED", "权限不足"],
			["需要等级: " + str(required) + "  当前等级: " + str(player_clearance)],
			["输入 unlock 尝试密码认证"]
		], "#FF6666")
		append_output(box + "\n", false)
		return


	current_path = new_path
	_update_status_bar()
	append_output("已切换到: " + current_path + "\n", false)


func _cmd_open(args: Array) -> void:
	if args.is_empty():
		append_output("[color=#FF6666][ERROR] 用法: open <文件名>[/color]")
		return
	
	var filename: String = args[0]
	var file_path: String
	
	if filename.begins_with("/"):
		file_path = filename
	else:
		file_path = _join_path(current_path, filename)
	
	file_path = _normalize_path(file_path)
	
	var node := _get_node_at_path(file_path)
	if node == null:
		append_output("[color=#FF6666][ERROR] 文件不存在: " + filename + "[/color]")
		return
	if node.type != "file":
		# 调试输出
		print("[DEBUG] open 目标: " + file_path + " 需要权限: " + str(_get_required_clearance(file_path)) + " 当前权限: " + str(player_clearance))
		append_output("[color=#FF6666][ERROR] " + filename + " 是一个目录，请使用 cd 命令进入。[/color]")
		return


	# 权限检查
	var required: int = _get_required_clearance(file_path)
	if not _has_clearance(file_path):
		var box: String = _build_box_sectioned([
			["ACCESS DENIED", "权限不足"],
			["需要等级: " + str(required) + "  当前等级: " + str(player_clearance)],
			["输入 unlock 尝试密码认证"]
		], "#FF6666")
		append_output(box + "\n", false)
		return


	# 文件密码检查（独立于权限等级）
	var fp_key: String = _get_file_password_key(file_path)
	if not fp_key.is_empty() and not unlocked_file_passwords.has(file_path):
		# 需要文件密码且尚未解锁
		var fp_info: Dictionary = story_file_passwords[fp_key]
		var hint_text: String = fp_info.get("hint", "")
		var box_lines: Array = [["FILE PASSWORD REQUIRED", "此文件需要输入密码"]]
		if not hint_text.is_empty():
			box_lines.append(["提示: " + hint_text])
		box_lines.append(["请输入密码:", "(输入 cancel 取消)"])
		var box: String = _build_box_sectioned(box_lines, "#FFB000")
		append_output(box + "\n", false)
		
		# 进入文件密码输入模式
		_file_password_mode = true
		_file_password_target = file_path
		_file_password_filename = filename
		input_field.placeholder_text = "输入文件密码..."
		return


	# 先等待打字队列全部完成
	while _is_typing:
		await get_tree().process_frame
	
	# 显示进度条（直接操作output_text，不走打字队列）
	var content_size: int = node.content.length()
	await _show_progress_bar(content_size)
	
	# 进度条完成后等待一小会
	await get_tree().create_timer(0.5).timeout
	
	# 清屏进入阅读模式
	output_text.text = ""
	_typewriter_queue.clear()
	_is_typing = false
	_typewriter_instant = false
	
	# 显示文件头
	var header: String = "[color=#66FF66]══════════ " + filename + " ══════════[/color]"
	output_text.append_text(header + "\n\n")

	# 记录已读
	if not read_files.has(file_path):
		read_files.append(file_path)
		save_mgr.auto_save(story_id, player_clearance, read_files, unlocked_passwords, unlocked_file_passwords, current_path)

	# 显示文件内容（走打字机，不加额外空行）
	# 清理内容：去除首尾空白，统一换行符为\n
	var clean_content: String = node.content.strip_edges()
	clean_content = clean_content.replace("\r\n", "\n").replace("\r", "\n")
	append_output(clean_content, false)
	
	# 文件尾放入队列，等内容打完后显示
	append_output("\n[color=#66FF66]══════════ 文件结束 ══════════[/color]\n[color=#AAAAAA]输入任意命令返回终端。[/color]\n", false)


func _cmd_back() -> void:
	if current_path == "/":
		append_output("[color=#AAAAAA]已经在根目录了。[/color]")
		return
	
	current_path = _get_parent_path(current_path)
	_update_status_bar()
	append_output("已返回: " + current_path + "\n", false)


func _cmd_clear() -> void:
	output_text.text = ""
	_typewriter_queue.clear()
	_is_typing = false
	_typewriter_instant = false


func _cmd_status() -> void:
	var lines: Array[String] = []
	lines.append("[color=#66FF66]═══════════ 用户状态 ═══════════[/color]")
	lines.append("  用户名:	 [color=#66FF66]未登录[/color]")
	lines.append("  权限等级:   [color=#FFB000]" + str(player_clearance) + "[/color]")
	lines.append("  当前路径:   [color=#66FF66]" + current_path + "[/color]")
	lines.append("  已读文件:   [color=#66FF66]" + str(read_files.size()) + "[/color]")
	lines.append("  已获取密码: [color=#66FF66]" + str(unlocked_passwords.size()) + "[/color]")
	lines.append("  已解锁文件: [color=#66FF66]" + str(unlocked_file_passwords.size()) + "[/color]")
	if not story_id.is_empty():
		lines.append("  盘ID:	[color=#AAAAAA]" + story_id + "[/color]")
	lines.append("[color=#66FF66]════════════════════════════════[/color]")
	append_output("\n".join(lines) + "\n", false)


func _cmd_mail(args: Array) -> void:
	append_output("[color=#AAAAAA]收件箱为空。\n(邮件系统将在后续版本中实现)[/color]\n", false)


func _cmd_exit() -> void:
	append_output("[color=#AAAAAA]正在断开连接...[/color]")
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()


func _cmd_whoami() -> void:
	append_output("[color=#66FF66]未登录用户[/color]\n[color=#AAAAAA](用户系统将在后续版本中实现)[/color]\n", false)

func _cmd_story_info() -> void:
	if story_manifest.is_empty() and available_stories.is_empty():
		append_output("[color=#AAAAAA]未检测到外部虚拟磁盘，当前运行于内置诊断模式。\n将 .scp 或 .zip 文件放入 vdisc/ 目录后输入 scan 重新扫描。[/color]\n", false)
		return
	
	var lines: Array[String] = []
	lines.append("[color=#66FF66]═══════════════ 虚拟磁盘管理 ═══════════════[/color]")
	
	if available_stories.size() > 0:
		lines.append("")
		lines.append("  已发现 [color=#66FF66]" + str(available_stories.size()) + "[/color] 个虚拟磁盘:")
		lines.append("")
		
		for i in range(available_stories.size()):
			var info: Dictionary = available_stories[i]
			var marker: String = ""
			if i == current_story_index:
				marker = " [color=#33FF33]<< 当前[/color]"
			lines.append("  [color=#FFB000]" + str(i + 1) + ".[/color] " + info.get("title", "未知") + " [color=#AAAAAA](" + info.get("filename", "") + ")[/color]" + marker)
			lines.append("	 作者: [color=#AAAAAA]" + info.get("author", "未知") + "[/color]")
		
		lines.append("")
		lines.append("[color=#AAAAAA]  使用 [/color][color=#66FF66]vdisc load <编号>[/color][color=#AAAAAA] 切换磁盘[/color]")
		lines.append("[color=#AAAAAA]  使用 [/color][color=#66FF66]scan[/color][color=#AAAAAA] 重新扫描目录[/color]")
	
	# 当前加载的磁盘详细信息
	if story_manifest.has("story"):
		lines.append("")
		lines.append("[color=#66FF66]─────────── 当前磁盘详情 ───────────[/color]")
		var info: Dictionary = story_manifest["story"]
		lines.append("  磁盘标签: [color=#66FF66]" + info.get("title", "未知") + "[/color]")
		lines.append("  制作者:   [color=#66FF66]" + info.get("author", "未知") + "[/color]")
		lines.append("  版本:	 [color=#66FF66]" + info.get("version", "未知") + "[/color]")
		if info.has("description"):
			lines.append("  描述:	 [color=#AAAAAA]" + info["description"] + "[/color]")
		lines.append("  文件总数: [color=#66FF66]" + str(file_system.size()) + "[/color]")
		lines.append("  磁盘来源: [color=#AAAAAA]" + current_story_path.get_file() + "[/color]")
		lines.append("  磁盘状态: [color=#33FF33]已挂载[/color]")
	
	lines.append("[color=#66FF66]═══════════════════════════════════════════[/color]")
	append_output("\n".join(lines) + "\n", false)


func _cmd_vdisc_load(args: Array) -> void:
	if args.is_empty():
		append_output("[color=#FF6666][ERROR] 用法: vdisc load <编号>[/color]\n[color=#AAAAAA]输入 vdisc 查看可用磁盘列表。[/color]\n", false)
		return
	
	var index_str: String = args[0]
	if not index_str.is_valid_int():
		append_output("[color=#FF6666][ERROR] 请输入有效的编号数字。[/color]\n", false)
		return
	
	var index: int = index_str.to_int() - 1  # 用户输入从1开始
	
	if index < 0 or index >= available_stories.size():
		append_output("[color=#FF6666][ERROR] 编号超出范围。可用范围: 1-" + str(available_stories.size()) + "[/color]\n", false)
		return
	
	if index == current_story_index:
		append_output("[color=#AAAAAA]该磁盘已经是当前加载的磁盘。[/color]\n", false)
		return
	
	# 保存当前剧本存档
	save_mgr.auto_save(story_id, player_clearance, read_files, unlocked_passwords, unlocked_file_passwords, current_path)
	
	append_output("[color=#AAAAAA]正在卸载当前磁盘...[/color]", false)
	
	# 等待打字完成
	while _is_typing:
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	
	# 重置状态
	file_system.clear()
	story_manifest.clear()
	story_permissions.clear()
	story_file_passwords.clear()
	current_story_path = ""
	story_id = ""
	current_path = "/"
	player_clearance = 0
	read_files.clear()
	unlocked_passwords.clear()
	unlocked_file_passwords.clear()
	
	# 显示加载进度条
	await _show_progress_bar(800)
	await get_tree().create_timer(0.3).timeout
	
	# 加载新剧本
	if _load_story_by_index(index):
		var title: String = available_stories[index].get("title", "未知")
		
		var box: String = _build_box_sectioned([
			["DISC LOADED", "磁盘加载完成"],
			[title]
		], "#33FF33")
		append_output(box + "\n", false)
		
		_update_status_bar()
		append_output("[color=#AAAAAA]文件数量: " + str(file_system.size()) + "  权限规则: " + str(story_permissions.size()) + " 条[/color]\n", false)
		append_output("[color=#AAAAAA]当前路径: " + current_path + "  权限等级: " + str(player_clearance) + "[/color]\n", false)
	else:
		append_output("[color=#FF6666][ERROR] 磁盘加载失败。[/color]\n", false)
		_init_test_file_system()
		_update_status_bar()


func _cmd_unlock(args: Array) -> void:
	# 如果带了参数，直接验证（兼容旧用法）
	if not args.is_empty():
		_verify_password(args[0])
		return
	
	# 无参数，进入密码输入模式
	_enter_password_mode()

func _enter_password_mode(target_path: String = "") -> void:
	_password_mode = true
	_password_target_path = target_path


	var box: String = _build_box_sectioned([
		["SECURITY AUTHENTICATION", "安全认证系统"],
		["请输入访问密码:", "(输入 cancel 取消)"]
	], "#FFB000")
	append_output(box + "\n", false)


	# 修改输入框提示
	input_field.placeholder_text = "输入密码..."

func _verify_password(password: String) -> void:
	# 从manifest中查找密码
	if not story_manifest.has("passwords"):
		append_output("[color=#FF6666][ERROR] 当前剧本未配置密码系统。[/color]\n", false)
		return
	
	var passwords: Dictionary = story_manifest["passwords"]
	
	if passwords.has(password):
		var pwd_info: Dictionary = passwords[password]
		var grant_level: int = int(float(pwd_info.get("grants_clearance", 0)))
		
		if unlocked_passwords.has(password):
			append_output("[color=#AAAAAA]该密码已使用过。当前权限等级: " + str(player_clearance) + "[/color]\n", false)
			return
		
		if grant_level <= player_clearance:
			append_output("[color=#AAAAAA]该密码对应的权限等级不高于当前等级。当前: " + str(player_clearance) + "[/color]\n", false)
			return
		
		# 解锁成功
		unlocked_passwords.append(password)
		var old_level: int = player_clearance
		player_clearance = grant_level
		save_mgr.auto_save(story_id, player_clearance, read_files, unlocked_passwords, unlocked_file_passwords, current_path)


		# 成功动画
		var box: String = _build_box_sectioned([
			["ACCESS GRANTED", "权限认证通过"],
			["权限等级: " + str(old_level) + " -> " + str(player_clearance)]
		], "#33FF33")
		append_output(box + "\n", false)


		# 显示提示信息（如果有）
		if pwd_info.has("message"):
			append_output("[color=#AAAAAA]" + str(pwd_info["message"]) + "[/color]\n", false)
	else:
		var box: String = _build_box(["ACCESS DENIED", "密码验证失败"] as Array[String], "#FF6666")
		append_output(box + "\n", false)



func _cmd_scan() -> void:
	append_output("[color=#AAAAAA]正在扫描vdisc目录...[/color]", false)
	
	# 等待打字完成
	while _is_typing:
		await get_tree().process_frame
	
	# 显示扫描进度条
	await _show_progress_bar(500)
	await get_tree().create_timer(0.3).timeout
	
	# 保存旧状态用于对比
	var old_story_path: String = current_story_path
	var old_manifest: Dictionary = story_manifest.duplicate()


	# 重置文件系统和权限
	file_system.clear()
	story_manifest.clear()
	story_permissions.clear()
	current_story_path = ""
	story_id = ""
	player_clearance = 0
	read_files.clear()
	unlocked_passwords.clear()
	unlocked_file_passwords.clear()
	story_file_passwords.clear()
	available_stories.clear()
	current_story_index = -1


	# 重新扫描
	var vdisc_dir: String = save_mgr.get_game_root_dir() + "vdisc/"
	_scan_available_stories(vdisc_dir)
	if _desktop_mode:
	# 桌面模式：只扫描，不自动加载
		if available_stories.is_empty():
			append_output("[color=#FFB000][WARN] 未找到虚拟磁盘文件。[/color]", false)
			append_output("[color=#AAAAAA]请将 .scp 文件放入 vdisc/ 目录后重新扫描。[/color]\n", false)
		else:
			var scan_lines: Array[String] = []
			scan_lines.append("[color=#33FF33][OK] 扫描完成，发现 " + str(available_stories.size()) + " 个虚拟磁盘。[/color]")
			scan_lines.append("")
			for i in range(available_stories.size()):
				var info: Dictionary = available_stories[i]
				scan_lines.append("  [color=#FFB000]" + str(i + 1) + ".[/color] " + info.get("title", "未知") + " [color=#AAAAAA](" + info.get("filename", "") + ")[/color]")
			scan_lines.append("")
			scan_lines.append("[color=#AAAAAA]输入 [/color][color=#66FF66]load <编号>[/color][color=#AAAAAA] 加载磁盘。[/color]")
			append_output("\n".join(scan_lines) + "\n", false)
		_update_status_bar()
	else:
		# 终端模式：重新加载当前磁盘
		if available_stories.is_empty():
			_desktop_mode = true
			_init_test_file_system()
			current_path = "/"
			_update_status_bar()
			append_output("[color=#FFB000][WARN] 未找到剧本文件，已返回桌面。[/color]\n", false)
		elif _load_story_by_index(0):
			var title: String = "未知"
			if story_manifest.has("story") and story_manifest["story"].has("title"):
				title = story_manifest["story"]["title"]
			append_output("[color=#33FF33][OK] 已重新加载剧本: " + title + "[/color]", false)
			append_output("[color=#AAAAAA]文件数量: " + str(file_system.size()) + "  权限规则: " + str(story_permissions.size()) + " 条[/color]\n", false)
			if story_manifest.has("settings") and story_manifest["settings"].has("start_path"):
				current_path = story_manifest["settings"]["start_path"]
			else:
				current_path = "/"
			_update_status_bar()
		else:
			append_output("[color=#FF6666][ERROR] 重新加载失败。[/color]\n", false)


func _cmd_reboot() -> void:
	append_output("[color=#AAAAAA]正在重启终端...[/color]", false)
	
	# 等待打字完成
	while _is_typing:
		await get_tree().process_frame
	
	await get_tree().create_timer(0.5).timeout


	# 清空所有状态
	output_text.text = ""
	_typewriter_queue.clear()
	_is_typing = false
	_typewriter_instant = false
	command_history.clear()
	history_index = -1
	file_system.clear()
	story_manifest.clear()
	story_permissions.clear()
	current_story_path = ""
	story_id = ""
	current_path = "/"
	has_new_mail = false
	player_clearance = 0
	read_files.clear()
	unlocked_passwords.clear()
	unlocked_file_passwords.clear()
	story_file_passwords.clear()
	available_stories.clear()
	current_story_index = -1


	# 重新加载
	save_mgr.ensure_stories_dir()
	var vdisc_dir: String = save_mgr.get_game_root_dir() + "vdisc/"
	_scan_available_stories(vdisc_dir)
	
	# 模拟重启效果
	output_text.append_text("[color=#AAAAAA]...[/color]\n")
	await get_tree().create_timer(0.3).timeout
	output_text.append_text("[color=#AAAAAA]终端系统重新初始化中...[/color]\n")
	await get_tree().create_timer(0.5).timeout
	output_text.text = ""
	
	# 回到桌面
	_desktop_mode = true
	_update_status_bar()
	_show_desktop_welcome()
	input_field.grab_focus()




# ============================================================
# 命令历史导航
# ============================================================
func _history_previous() -> void:
	if command_history.is_empty():
		return
	
	if history_index == -1:
		current_input_backup = input_field.text
		history_index = command_history.size() - 1
	elif history_index > 0:
		history_index -= 1
	
	input_field.text = command_history[history_index]
	input_field.caret_column = input_field.text.length()


func _history_next() -> void:
	if command_history.is_empty() or history_index == -1:
		return
	
	if history_index < command_history.size() - 1:
		history_index += 1
		input_field.text = command_history[history_index]
	else:
		history_index = -1
		input_field.text = current_input_backup
	
	input_field.caret_column = input_field.text.length()


# ============================================================
# 自动补全（命令和文件名）
# ============================================================
func _auto_complete() -> void:
	var current_text: String = input_field.text
	if current_text.strip_edges().is_empty():
		return
	
	var parts := current_text.split(" ", false)
	
	# 只输入了一个词：补全命令
	if parts.size() == 1:
		# 检查是否已经是完整命令，后面有空格表示要补全参数
		if current_text.ends_with(" "):
			# 命令已输入完，补全文件名（无前缀匹配，列出所有）
			var cmd: String = parts[0].to_lower()
			if cmd in ["cd", "open", "cat"]:
				var children := _get_children_at_path(current_path)
				if children.size() > 0:
					var display: Array[String] = []
					for child in children:
						var child_path := _join_path(current_path, child)
						var node := _get_node_at_path(child_path)
						if node == null:
							continue
						# cd只补全文件夹，open/cat只补全文件
						if cmd == "cd" and node.type == "folder":
							display.append(child + "/")
						elif cmd in ["open", "cat"] and node.type == "file":
							display.append(child)
						elif cmd not in ["cd"]:
							display.append(child)
					if display.size() > 0:
						output_text.append_text("\n[color=#AAAAAA]可选项: " + " | ".join(display) + "[/color]")
						_do_scroll()
		else:
			# 补全命令名
			var partial_cmd: String = parts[0].to_lower()
			var commands: Array
			if _desktop_mode:
				commands = ["help", "load", "scan", "vdisc", "clear", "cls", "exit", "quit", "reboot", "restart"]
			else:
				commands = ["help", "ls", "dir", "cd", "open", "cat", "back",
					"clear", "cls", "status", "mail", "whoami", "exit", "quit", "vdisc",
					"scan", "reboot", "restart", "unlock", "eject"]
			var matches: Array[String] = []
			for cmd in commands:
				if cmd.begins_with(partial_cmd):
					matches.append(cmd)
			
			if matches.size() == 1:
				input_field.text = matches[0] + " "
				input_field.caret_column = input_field.text.length()
			elif matches.size() > 1:
				output_text.append_text("\n[color=#AAAAAA]可选命令: " + " | ".join(matches) + "[/color]")
				_do_scroll()
	
	# 两个词：命令 + 部分文件名
	elif parts.size() == 2:
		var cmd: String = parts[0].to_lower()
		var partial_name: String = parts[1]
		
		if cmd in ["cd", "open", "cat"]:
			var children := _get_children_at_path(current_path)
			var matches: Array[String] = []
			for child in children:
				if child.to_lower().begins_with(partial_name.to_lower()):
					var child_path := _join_path(current_path, child)
					var node := _get_node_at_path(child_path)
					if node == null:
						continue
					# cd只匹配文件夹，open/cat只匹配文件
					if cmd == "cd" and node.type == "folder":
						matches.append(child)
					elif cmd in ["open", "cat"] and node.type == "file":
						matches.append(child)
			
			if matches.size() == 1:
				input_field.text = cmd + " " + matches[0]
				input_field.caret_column = input_field.text.length()
			elif matches.size() > 1:
				# 找公共前缀，补全到最长公共部分
				var common: String = _find_common_prefix(matches)
				if common.length() > partial_name.length():
					input_field.text = cmd + " " + common
					input_field.caret_column = input_field.text.length()
				output_text.append_text("\n[color=#AAAAAA]可选项: " + " | ".join(matches) + "[/color]")
				_do_scroll()

# 查找多个字符串的最长公共前缀
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



# ============================================================
# 输出工具函数
# ============================================================
func append_output(text: String, extra_newline: bool = true) -> void:
	_typewriter_queue.append({"text": text, "extra_newline": extra_newline})
	if not _is_typing:
		_process_typewriter_queue()


func _process_typewriter_queue() -> void:
	if _typewriter_queue.is_empty():
		_is_typing = false
		return
	
	_is_typing = true
	var entry = _typewriter_queue.pop_front()
	var text: String = entry["text"]
	var extra_newline: bool = entry["extra_newline"]

	if _typewriter_instant:
		output_text.append_text(text)

	if extra_newline:
		output_text.append_text("\n")
		_do_scroll()
		_process_typewriter_queue()
	else:
		_typewrite_text(text, extra_newline)



func _typewrite_text(text: String, extra_newline: bool = true) -> void:
	var i: int = 0
	var length: int = text.length()
	_current_char_speed = _typewriter_speed
	
	while i < length:
		# 如果中途切换为即时模式，把剩余文本一次性输出
		if _typewriter_instant:
			output_text.append_text(text.substr(i))
			break
		
		# 检查是否是BBCode标签
		if text[i] == "[":
			var close_bracket: int = text.find("]", i)
			if close_bracket != -1:
				var tag: String = text.substr(i, close_bracket - i + 1)
				# 检查是否是自定义速度标签 [speed=0.05]
				if tag.begins_with("[speed="):
					var speed_str: String = tag.substr(7, tag.length() - 8)
					_current_char_speed = speed_str.to_float()
					i = close_bracket + 1
					continue
				elif tag == "[/speed]":
					_current_char_speed = _typewriter_speed
					i = close_bracket + 1
					continue
				elif tag.begins_with("[pause="):
					# 自定义暂停标签 [pause=0.5]
					var pause_str: String = tag.substr(7, tag.length() - 8)
					var pause_time: float = pause_str.to_float()
					await get_tree().create_timer(pause_time).timeout
					i = close_bracket + 1
					continue
				# 判断是否是合法的BBCode标签（以字母或/开头）
				var tag_inner: String = tag.substr(1, tag.length() - 2)
				if tag_inner.length() > 0 and (tag_inner[0] == "/" or tag_inner[0].unicode_at(0) >= 65 and tag_inner[0].unicode_at(0) <= 122):
					# 看起来像BBCode标签，整体添加
					output_text.append_text(tag)
					i = close_bracket + 1
					continue
				# 不是BBCode标签，转义方括号后逐字输出
				output_text.append_text("[lb]")
				i += 1
				continue

				
				# 检查是否是自定义速度标签 [speed=0.05]
				if tag.begins_with("[speed="):
					var speed_str: String = tag.substr(7, tag.length() - 8)
					_current_char_speed = speed_str.to_float()
					i = close_bracket + 1
					continue
				elif tag == "[/speed]":
					_current_char_speed = _typewriter_speed
					i = close_bracket + 1
					continue
				elif tag.begins_with("[pause="):
					# 自定义暂停标签 [pause=0.5]
					var pause_str: String = tag.substr(7, tag.length() - 8)
					var pause_time: float = pause_str.to_float()
					await get_tree().create_timer(pause_time).timeout
					i = close_bracket + 1
					continue
				
				# 普通BBCode标签，整体添加
				output_text.append_text(tag)
				i = close_bracket + 1
				continue

		# 普通字符
		var ch: String = text[i]
		# 换行符不单独append，而是收集连续的换行一次性输出
		if ch == "\n":
			var newlines: String = "\n"
			i += 1
			while i < length and text[i] == "\n":
				newlines += "\n"
				i += 1
			output_text.append_text(newlines)
			# 换行后的停顿
			if not _typewriter_instant:
				await get_tree().create_timer(_typewriter_period_pause).timeout
			_do_scroll()
			continue
		output_text.append_text(ch)
		i += 1

		# 根据字符类型决定延迟
		var delay: float = _current_char_speed
		# 标点符号额外停顿（制造顿挫感）
		if ch in ["，", "。", "；", "：", "！", "？", ",", ".", ";", ":", "!", "?"]:
			delay += _typewriter_period_pause
		elif ch in ["、", "—", "-", "…"]:
			delay += _typewriter_comma_pause
		else:


			# 随机顿挫：有一定概率额外停顿
			if randf() < _typewriter_pause_chance:
				delay += _typewriter_pause_duration
		
		await get_tree().create_timer(delay).timeout
		
		# 每隔几个字符滚动一次
		if i % 8 == 0:
			_do_scroll()
	
	# 当前文本打完
	if extra_newline:
		output_text.append_text("\n")
	_do_scroll()
	
	# 继续处理队列
	_process_typewriter_queue()	


func _do_scroll() -> void:
	_needs_scroll = true

func _process(_delta: float) -> void:
	if _needs_scroll:
		var v_scroll: VScrollBar = scroll_container.get_v_scroll_bar()
		scroll_container.scroll_vertical = int(v_scroll.max_value)
		_needs_scroll = false



# 显示文件加载进度条
# file_size: 文件内容长度，影响进度条速度
# speed_override: 速度倍率覆盖，-1表示用默认
func _show_progress_bar(file_size: int, speed_override: float = -1.0) -> void:
	var bar_width: int = 30  # 进度条总长度（字符数）
	var speed: float = _progress_bar_speed
	if speed_override > 0.0:
		speed = speed_override
	
	# 文件越大，每格停顿越长（但有上下限）
	var base_delay: float = clamp(float(file_size) / 5000.0, 0.01, 0.08)
	base_delay /= speed
	
	# 起始行
	if output_text.get_parsed_text().length() > 0:
		output_text.append_text("\n")
	output_text.append_text("[color=#66FF66]加载中 [[/color]")
	
	for i in range(bar_width):
		if _typewriter_instant:
			# 跳过动画，直接填满
			var remaining: int = bar_width - i
			output_text.append_text("[color=#33FF33]" + "█".repeat(remaining) + "[/color]")
			break
		
		output_text.append_text("[color=#33FF33]█[/color]")
		_do_scroll()
		
		# 随机波动让进度条不匀速，更真实
		var jitter: float = randf_range(0.7, 1.5)
		await get_tree().create_timer(base_delay * jitter).timeout
	
	output_text.append_text("[color=#66FF66]] 完成[/color]\n")
	_do_scroll()





# ============================================================
# 状态栏更新
# ============================================================
func _update_status_bar() -> void:
	if _desktop_mode:
		path_label.text = "[DESKTOP]  " + str(available_stories.size()) + " disc(s) found"
		mail_icon.text = "[Mail]"
		return
	
	var disc_name: String = ""
	if current_story_index >= 0 and current_story_index < available_stories.size():
		disc_name = available_stories[current_story_index].get("title", "")
	
	if disc_name.is_empty():
		path_label.text = "[" + current_path + "]  LV:" + str(player_clearance)
	else:
		path_label.text = "[" + current_path + "]  LV:" + str(player_clearance) + "  DISC:" + disc_name
	
	if has_new_mail:
		mail_icon.text = "[Mail NEW]"
	else:
		mail_icon.text = "[Mail]"



# ============================================================
# 超链接处理
# ============================================================
# 处理RichTextLabel中的超链接点击
func _on_meta_clicked(meta: Variant) -> void:
	var meta_str: String = str(meta)
	
	# 如果是命令链接，直接执行
	if meta_str.begins_with("cmd://"):
		var cmd: String = meta_str.substr(6)
		if output_text.get_parsed_text().length() > 0:
			output_text.append_text("\n")
		output_text.append_text("> " + cmd)
		output_text.append_text("\n")
		_execute_command(cmd)
		return
	
	# 如果是文件链接，打开文件
	if meta_str.begins_with("file://"):
		var file_path: String = meta_str.substr(7)
		if output_text.get_parsed_text().length() > 0:
			output_text.append_text("\n")
		output_text.append_text("> open " + file_path)
		output_text.append_text("\n")
		await _cmd_open([file_path])
		return
	
	print("[Terminal] 未知链接: " + meta_str)



# ============================================================
# 桌面模式
# ============================================================
func _show_desktop_welcome() -> void:
	var title: String = "SCP FOUNDATION TERMINAL v0.1"
	var subtitle: String = "SECURE - CONTAIN - PROTECT"
	
	var box: String = _build_box([title, subtitle] as Array[String], "#66FF66")
	output_text.append_text(box + "\n\n")
	
	# 显示磁盘列表
	if available_stories.is_empty():
		output_text.append_text("[color=#FFB000]未检测到虚拟磁盘。[/color]\n")
		output_text.append_text("[color=#AAAAAA]请将 .scp 文件放入 vdisc/ 目录后输入 scan 重新扫描。[/color]\n\n")
	else:
		output_text.append_text("[color=#66FF66]检测到 " + str(available_stories.size()) + " 个虚拟磁盘:[/color]\n\n")
		for i in range(available_stories.size()):
			var info: Dictionary = available_stories[i]
			output_text.append_text("  [color=#FFB000]" + str(i + 1) + ".[/color] [color=#66FF66]" + info.get("title", "未知") + "[/color]\n")
			output_text.append_text("	 [color=#AAAAAA]" + info.get("author", "未知") + " | " + info.get("filename", "") + "[/color]\n")
		output_text.append_text("\n")
	
	output_text.append_text("[color=#AAAAAA]可用命令:[/color]\n")
	output_text.append_text("  [color=#66FF66]load <编号>[/color]   加载指定磁盘\n")
	output_text.append_text("  [color=#66FF66]scan[/color]		  重新扫描磁盘目录\n")
	output_text.append_text("  [color=#66FF66]clear[/color]		 清空屏幕\n")
	output_text.append_text("  [color=#66FF66]exit[/color]		  退出终端\n")

func _cmd_desktop_load(args: Array) -> void:
	if args.is_empty():
		append_output("[color=#FF6666][ERROR] 用法: load <编号>[/color]", false)
		if available_stories.size() > 0:
			append_output("[color=#AAAAAA]可用磁盘: 1-" + str(available_stories.size()) + "[/color]\n", false)
		return
	
	var index_str: String = args[0]
	if not index_str.is_valid_int():
		append_output("[color=#FF6666][ERROR] 请输入有效的编号数字。[/color]\n", false)
		return
	
	var index: int = index_str.to_int() - 1
	
	if index < 0 or index >= available_stories.size():
		append_output("[color=#FF6666][ERROR] 编号超出范围。可用范围: 1-" + str(available_stories.size()) + "[/color]\n", false)
		return
	
	append_output("[color=#AAAAAA]正在加载虚拟磁盘...[/color]", false)
	
	# 等待打字完成
	while _is_typing:
		await get_tree().process_frame
	
	# 显示加载进度条
	await _show_progress_bar(800)
	await get_tree().create_timer(0.3).timeout
	
	# 加载剧本
	if _load_story_by_index(index):
		_desktop_mode = false
		var title: String = available_stories[index].get("title", "未知")
		
		# 清屏并显示终端欢迎
		output_text.text = ""
		_typewriter_queue.clear()
		_is_typing = false
		_typewriter_instant = false
		
		_update_status_bar()
		_show_welcome_message()
	else:
		append_output("[color=#FF6666][ERROR] 磁盘加载失败。[/color]\n", false)

func _cmd_eject() -> void:
	if _desktop_mode:
		append_output("[color=#AAAAAA]当前已在桌面模式。[/color]\n", false)
		return
	
	# 保存当前剧本存档
	save_mgr.auto_save(story_id, player_clearance, read_files, unlocked_passwords, unlocked_file_passwords, current_path)
	
	append_output("[color=#AAAAAA]正在卸载磁盘...[/color]", false)
	
	# 等待打字完成
	while _is_typing:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	
	# 重置终端状态
	file_system.clear()
	story_manifest.clear()
	story_permissions.clear()
	story_file_passwords.clear()
	current_story_path = ""
	story_id = ""
	current_path = "/"
	player_clearance = 0
	read_files.clear()
	unlocked_passwords.clear()
	unlocked_file_passwords.clear()
	current_story_index = -1
	
	# 切换到桌面模式
	_desktop_mode = true
	output_text.text = ""
	_typewriter_queue.clear()
	_is_typing = false
	_typewriter_instant = false
	
	_update_status_bar()
	_show_desktop_welcome()




# ============================================================
# 欢迎信息
# ============================================================
func _show_welcome_message() -> void:
	var title: String = "SCP FOUNDATION TERMINAL v0.1"
	var subtitle: String = "SECURE - CONTAIN - PROTECT"
	
	if story_manifest.has("story"):
		var story_info: Dictionary = story_manifest["story"]
		if story_info.has("title"):
			subtitle = story_info["title"]
	
	# 计算框的宽度：取较长的那行，两侧各留3个空格
	var max_len: int = max(title.length(), subtitle.length())
	# 中英文混排时，中文字符占2个宽度，英文占1个
	var title_display_len: int = _display_width(title)
	var subtitle_display_len: int = _display_width(subtitle)
	var inner_width: int = max(title_display_len, subtitle_display_len) + 6
	
	# 居中填充
	var title_pad_total: int = inner_width - title_display_len
	var title_pad_left: int = title_pad_total / 2
	var title_pad_right: int = title_pad_total - title_pad_left
	
	var subtitle_pad_total: int = inner_width - subtitle_display_len
	var subtitle_pad_left: int = subtitle_pad_total / 2
	var subtitle_pad_right: int = subtitle_pad_total - subtitle_pad_left
	
	var border_h: String = "═".repeat(inner_width)
	
	var welcome: String = ""
	welcome += "[color=#66FF66]╔" + border_h + "╗\n"
	welcome += "║" + " ".repeat(title_pad_left) + title + " ".repeat(title_pad_right) + "║\n"
	welcome += "║" + " ".repeat(subtitle_pad_left) + subtitle + " ".repeat(subtitle_pad_right) + "║\n"
	welcome += "╚" + border_h + "╝[/color]\n"
	welcome += "\n"
	welcome += "[color=#AAAAAA]终端系统已启动。\n"
	welcome += "输入 [/color][color=#66FF66]help[/color][color=#AAAAAA] 查看可用命令。[/color]\n"
	
	output_text.append_text(welcome)

# 计算字符串的显示宽度（中文=2，英文/符号=1）
func _display_width(text: String) -> int:
	var width: int = 0
	for ch in text:
		var code: int = ch.unicode_at(0)
		if code >= 0x4E00 and code <= 0x9FFF:
			width += 2  # CJK统一汉字
		elif code >= 0x3000 and code <= 0x303F:
			width += 2  # CJK标点
		elif code >= 0xFF00 and code <= 0xFFEF:
			width += 2  # 全角字符
		else:
			width += 1
	return width


# 生成自适应宽度的文本框
# lines_data: 每行文本内容（纯文本，不含颜色标签）
# color: 框的颜色代码（如 #33FF33）
# 返回带BBCode的完整框字符串
func _build_box(lines_data: Array[String], color: String) -> String:
	# 计算最宽行的显示宽度
	var max_width: int = 0
	for line in lines_data:
		var w: int = _display_width(line)
		if w > max_width:
			max_width = w
	
	# 内部宽度 = 最宽行 + 左右各2个空格padding
	var inner_width: int = max_width + 4
	var border_h: String = "═".repeat(inner_width)
	
	var result: String = ""
	result += "[color=" + color + "]╔" + border_h + "╗[/color]\n"
	
	for i in range(lines_data.size()):
		var line: String = lines_data[i]
		var line_width: int = _display_width(line)
		var pad_total: int = inner_width - line_width
		var pad_left: int = pad_total / 2
		var pad_right: int = pad_total - pad_left
		result += "[color=" + color + "]║" + " ".repeat(pad_left) + line + " ".repeat(pad_right) + "║[/color]\n"
		
		# 如果不是最后一行，且下一行是分隔线标记，插入中间分隔
		# 用特殊标记 "---" 表示需要插入分隔线
	
	result += "[color=" + color + "]╚" + border_h + "╝[/color]"
	return result

# 生成带中间分隔线的自适应方框
# sections: 二维数组，每个元素是一组行文本，组之间用分隔线隔开
func _build_box_sectioned(sections: Array, color: String) -> String:
	# 计算所有行中最宽的显示宽度
	var max_width: int = 0
	for section in sections:
		for line in section:
			var w: int = _display_width(str(line))
			if w > max_width:
				max_width = w
	
	var inner_width: int = max_width + 4
	var border_h: String = "═".repeat(inner_width)
	var divider_h: String = "═".repeat(inner_width)
	
	var result: String = ""
	result += "[color=" + color + "]╔" + border_h + "╗[/color]\n"
	
	for s_idx in range(sections.size()):
		var section: Array = sections[s_idx]
		for line in section:
			var line_str: String = str(line)
			var line_width: int = _display_width(line_str)
			var pad_total: int = inner_width - line_width
			var pad_left: int = pad_total / 2
			var pad_right: int = pad_total - pad_left
			result += "[color=" + color + "]║" + " ".repeat(pad_left) + line_str + " ".repeat(pad_right) + "║[/color]\n"
		
		# 在 section 之间插入分隔线（最后一组不加）
		if s_idx < sections.size() - 1:
			result += "[color=" + color + "]╠" + divider_h + "╣[/color]\n"
	
	result += "[color=" + color + "]╚" + border_h + "╝[/color]"
	return result



# ============================================================
# 虚拟文件系统 - 路径工具函数
# ============================================================
func _join_path(base: String, child: String) -> String:
	if base == "/":
		return "/" + child
	else:
		return base + "/" + child


func _get_parent_path(path: String) -> String:
	if path == "/":
		return "/"
	
	var clean_path: String = path.rstrip("/")
	var last_slash: int = clean_path.rfind("/")
	
	if last_slash <= 0:
		return "/"
	
	return clean_path.substr(0, last_slash)


func _normalize_path(path: String) -> String:
	if not path.begins_with("/"):
		path = "/" + path
	
	var parts := path.split("/", false)
	var resolved: Array[String] = []
	
	for part in parts:
		if part == "..":
			if resolved.size() > 0:
				resolved.pop_back()
		elif part == ".":
			continue
		else:
			resolved.append(part)
	
	if resolved.is_empty():
		return "/"
	
	return "/" + "/".join(resolved)


# ============================================================
# 虚拟文件系统 - 节点数据结构
# ============================================================
class FSNode:
	var type: String
	var content: String
	
	func _init(p_type: String, p_content: String = "") -> void:
		type = p_type
		content = p_content


# 检查路径是否需要权限，返回所需等级（0表示无需权限）
func _get_required_clearance(path: String) -> int:
	path = _normalize_path(path)
	var highest: int = 0
	
	
	for perm_path in story_permissions.keys():
		var perm_value: int = int(float(story_permissions[perm_path]))
		var normalized_perm: String = _normalize_path(perm_path)
		
		# 精确匹配
		if path == normalized_perm:
			highest = max(highest, perm_value)
			continue
		
		# 目录前缀匹配：检查path是否在该目录下
		var dir_prefix: String = normalized_perm + "/"
		if path.begins_with(dir_prefix):
			highest = max(highest, perm_value)
	
	return highest


# 检查玩家是否有权限访问该路径
func _has_clearance(path: String) -> bool:
	return player_clearance >= _get_required_clearance(path)


# 检查文件是否需要密码，返回对应的密码表key（空字符串表示不需要）
func _get_file_password_key(file_path: String) -> String:
	file_path = _normalize_path(file_path)
	# 精确匹配
	for fp_path in story_file_passwords.keys():
		var normalized_fp: String = _normalize_path(fp_path)
		if file_path == normalized_fp:
			return fp_path
	return ""

# 验证文件密码
func _verify_file_password(input_password: String) -> void:
	var fp_key: String = _get_file_password_key(_file_password_target)
	if fp_key.is_empty():
		append_output("[color=#FF6666][ERROR] 内部错误：未找到文件密码配置。[/color]\n", false)
		return
	
	var fp_info: Dictionary = story_file_passwords[fp_key]
	var correct_password: String = str(fp_info.get("password", ""))
	
	if input_password == correct_password:
		# 密码正确
		unlocked_file_passwords.append(_file_password_target)
		save_mgr.auto_save(story_id, player_clearance, read_files, unlocked_passwords, unlocked_file_passwords, current_path)
		
		var box: String = _build_box(["PASSWORD ACCEPTED", "文件密码验证通过"] as Array[String], "#33FF33")
		append_output(box + "\n", false)
		
		# 等打字完成后自动打开文件
		while _is_typing:
			await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout
		
		# 重新执行打开文件
		await _cmd_open([_file_password_filename])
	else:
		var box: String = _build_box(["PASSWORD REJECTED", "文件密码错误"] as Array[String], "#FF6666")
		append_output(box + "\n", false)


func _get_node_at_path(path: String) -> FSNode:
	path = _normalize_path(path)
	if path == "/":
		return FSNode.new("folder")
	if file_system.has(path):
		var entry: Dictionary = file_system[path]
		var content: String = entry.get("content", "")
		# 统一换行符，防止\r\n导致双倍行距
		content = content.replace("\r\n", "\n").replace("\r", "\n")
		return FSNode.new(entry.get("type", "file"), content)
	return null



func _get_children_at_path(path: String) -> Array[String]:
	path = _normalize_path(path)
	var children: Array[String] = []
	
	var prefix: String
	if path == "/":
		prefix = "/"
	else:
		prefix = path + "/"
	
	for key in file_system.keys():
		if key.begins_with(prefix):
			var remainder: String = key.substr(prefix.length())
			if not remainder.contains("/"):
				children.append(remainder)
	
	children.sort()
	return children



func _setup_background() -> void:
	# 动态创建 Background 节点（不依赖场景树中预设的节点）
	background = TextureRect.new()
	background.name = "Background"
	add_child(background)
	# 移到最底层，确保不遮挡其他UI
	move_child(background, 0)
	
	# 铺满整个窗口
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 尝试从外部加载背景图，没有就用纯色
	var bg_path: String = save_mgr.get_game_root_dir() + "background.png"
	var tex: Texture2D = null
	
	if FileAccess.file_exists(bg_path):
		var image := Image.new()
		var err := image.load(bg_path)
		if err == OK:
			tex = ImageTexture.create_from_image(image)
			print("[UI] 已加载外部背景图: " + bg_path)
		else:
			print("[UI] 背景图加载失败: " + str(err))
	
	if tex == null:
		# 没有外部背景图，生成纯深色背景
		var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
		image.fill(Color(0.02, 0.04, 0.02, 1.0))
		tex = ImageTexture.create_from_image(image)
		print("[UI] 使用默认深色背景")
	
	background.texture = tex
	
	# 加载 Shader
	var shader_path: String = "res://background_vignette.gdshader"
	if ResourceLoader.exists(shader_path):
		var shader: Shader = load(shader_path)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("vignette_strength", 0.8)
		mat.set_shader_parameter("vignette_radius", 0.9)
		mat.set_shader_parameter("glow_strength", 0.08)
		mat.set_shader_parameter("glow_radius", 0.4)
		mat.set_shader_parameter("brightness", 0.7)
		mat.set_shader_parameter("tint_color", Color(0.1, 0.3, 0.1, 0.15))
		background.material = mat
		print("[UI] 背景Shader已应用")
	else:
		print("[UI] 未找到背景Shader文件: " + shader_path)


# 尝试从 vdisc 目录加载第一个 .scp 文件
func _try_load_story() -> bool:
	var vdisc_dir: String = save_mgr.get_game_root_dir() + "vdisc/"
	print("[StoryLoader] 搜索目录: " + vdisc_dir)
	_scan_available_stories(vdisc_dir)
	# 不再自动加载，由桌面模式的 load 命令触发
	return not available_stories.is_empty()



# 扫描 vdisc 目录下所有可用的 .scp/.zip 文件
func _scan_available_stories(vdisc_dir: String) -> void:
	available_stories.clear()
	
	if not DirAccess.dir_exists_absolute(vdisc_dir):
		return
	
	var dir := DirAccess.open(vdisc_dir)
	if dir == null:
		return
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".scp") or file_name.ends_with(".zip"):
			var full_path: String = vdisc_dir + file_name
			# 快速预读 manifest 获取标题和ID
			var info: Dictionary = _peek_story_info(full_path)
			info["path"] = full_path
			info["filename"] = file_name
			available_stories.append(info)
			print("[StoryLoader] 发现剧本: " + file_name + " -> " + info.get("title", "未知"))
		file_name = dir.get_next()
	
	print("[StoryLoader] 共发现 " + str(available_stories.size()) + " 个剧本文件")

# 快速预读 .scp 文件的 manifest，只提取标题和ID
func _peek_story_info(path: String) -> Dictionary:
	var info: Dictionary = {"title": "未知剧本", "id": "", "author": "未知"}
	
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return info
	
	var files := reader.get_files()
	for file_path in files:
		var filename: String = file_path.get_file()
		if filename == "manifest.json":
			var content_bytes := reader.read_file(file_path)
			if content_bytes != null:
				var content: String = content_bytes.get_string_from_utf8()
				var json := JSON.new()
				if json.parse(content) == OK and json.data is Dictionary:
					var data: Dictionary = json.data
					if data.has("story"):
						var story_info: Dictionary = data["story"]
						info["title"] = story_info.get("title", "未知剧本")
						info["id"] = story_info.get("id", "")
						info["author"] = story_info.get("author", "未知")
			break
		elif filename == "manifest.cfg":
			var content_bytes := reader.read_file(file_path)
			if content_bytes != null:
				var content: String = content_bytes.get_string_from_utf8()
				# 简单解析 cfg 获取标题
				for line in content.split("\n"):
					line = line.strip_edges()
					if line.begins_with("title="):
						info["title"] = line.substr(6).strip_edges()
					elif line.begins_with("id="):
						info["id"] = line.substr(3).strip_edges()
					elif line.begins_with("author="):
						info["author"] = line.substr(7).strip_edges()
			break
	
	reader.close()
	return info

# 按索引加载指定剧本
func _load_story_by_index(index: int) -> bool:
	if index < 0 or index >= available_stories.size():
		return false
	
	var story_info: Dictionary = available_stories[index]
	var path: String = story_info["path"]
	
	if _load_story_file(path):
		current_story_index = index
		return true
	return false



func _load_story_file(path: String) -> bool:
	story_loader = StoryLoader.new()
	if not story_loader.load_story(path):
		print("[StoryLoader] 加载失败: " + story_loader.error_message)
		return false
	
	# 应用加载的数据
	file_system = story_loader.file_system
	story_manifest = story_loader.manifest
	current_story_path = path
	
	# 读取盘ID
	if story_manifest.has("story") and story_manifest["story"].has("id"):
		story_id = story_manifest["story"]["id"]
	else:
		# 没有id就用文件名的哈希作为id
		story_id = str(path.get_file().hash())
	


	# 读取权限表
	story_permissions.clear()
	if story_manifest.has("permissions"):
		var perms: Dictionary = story_manifest["permissions"]
		for perm_path in perms.keys():
			story_permissions[perm_path] = int(perms[perm_path])
		print("[StoryLoader] 权限表已加载，共 " + str(story_permissions.size()) + " 条规则")
	else:
		print("[StoryLoader] 警告: manifest中未找到permissions字段")


	if story_manifest.has("passwords"):
		print("[StoryLoader] 密码表已加载，共 " + str(story_manifest["passwords"].size()) + " 个密码")
	else:
		print("[StoryLoader] 警告: manifest中未找到passwords字段")
	# 读取文件密码表
	story_file_passwords.clear()
	if story_manifest.has("file_passwords"):
		var fps: Dictionary = story_manifest["file_passwords"]
		for fp_path in fps.keys():
			story_file_passwords[fp_path] = fps[fp_path]
		print("[StoryLoader] 文件密码表已加载，共 " + str(story_file_passwords.size()) + " 条")
	else:
		print("[StoryLoader] 未配置文件密码表（file_passwords）")


	
	# 应用 manifest 中的设置
	var start_clearance: int = 0
	if story_manifest.has("settings"):
		var settings: Dictionary = story_manifest["settings"]
		if settings.has("start_path"):
			current_path = settings["start_path"]
		if settings.has("typing_speed"):
			_typewriter_speed = settings["typing_speed"].to_float()
		if settings.has("start_clearance"):
			start_clearance = int(settings["start_clearance"])
	
	# 尝试加载该剧本的存档
	var save_data = save_mgr.load_save(story_id)
	if save_data != null:
		player_clearance = int(save_data.get("player_clearance", 0))
		read_files.clear()
		if save_data.has("read_files"):
			for f in save_data["read_files"]:
				read_files.append(str(f))
		unlocked_passwords.clear()
		if save_data.has("unlocked_passwords"):
			for p in save_data["unlocked_passwords"]:
				unlocked_passwords.append(str(p))
		unlocked_file_passwords.clear()
		if save_data.has("unlocked_file_passwords"):
			for p in save_data["unlocked_file_passwords"]:
				unlocked_file_passwords.append(str(p))
		if save_data.has("current_path"):
			var saved_path: String = save_data["current_path"]
			if _has_clearance(saved_path):
				current_path = saved_path
			else:
				current_path = "/"
				if story_manifest.has("settings") and story_manifest["settings"].has("start_path"):
					current_path = story_manifest["settings"]["start_path"]
		print("[Save] 权限等级: " + str(player_clearance))
	else:
		# 没有存档，用初始权限
		player_clearance = start_clearance
		read_files.clear()
		unlocked_passwords.clear()

	
	var title: String = "未知剧本"
	if story_manifest.has("story") and story_manifest["story"].has("title"):
		title = story_manifest["story"]["title"]
	
	print("[StoryLoader] 成功加载: " + title)
	print("[StoryLoader] 盘ID: " + story_id)
	print("[StoryLoader] 文件数量: " + str(file_system.size()))
	print("[StoryLoader] 权限等级: " + str(player_clearance))
	print("[StoryLoader] story_permissions 内容: " + str(story_permissions))
	print("[StoryLoader] passwords 存在: " + str(story_manifest.has("passwords")))
	return true



func _init_test_file_system() -> void:
	file_system = {
		"/reports": {
			"type": "folder"
		},
		"/personnel": {
			"type": "folder"
		},
		"/comms": {
			"type": "folder"
		},
		"/welcome.txt": {
			"type": "file",
			"content": """欢迎接入SCP基金会安全终端系统。

本系统用于查阅基金会内部文件档案。
您的一切操作都将被记录和监控。

请遵守信息安全协议，不要尝试访问
超出您权限等级的文件。

- 基金会信息安全部门"""
		},
		"/notice.txt": {
			"type": "file",
			"content": """[通知] 2024-01-15

所有站点人员注意：

由于近期发生的安全事故，
所有B区以上的文件访问权限已被临时冻结。

如需紧急访问，请联系您的直属主管。

- Site-19 管理层"""
		},
		"/reports/scp_001.txt": {
			"type": "file",
			"content": """项目编号: SCP-001

项目等级: [DATA EXPUNGED]

特殊收容措施:
████████████████████████████████
████████████████████████████████
[本文件需要O5级权限才能查阅完整内容]

描述:
SCP-001的真实性质属于最高机密。
目前已知的信息表明 ██████████████
████████████████████████████████"""
		},
		"/reports/scp_173.txt": {
			"type": "file",
			"content": """项目编号: SCP-173

项目等级: Euclid

特殊收容措施:
项目SCP-173应被收容在一个锁闭的房间中。
当人员必须进入SCP-173的收容室时，
不得少于3人进入，且门在重新锁闭后，
应始终保持与SCP-173的视觉接触。

描述:
SCP-173是一个混凝土和钢筋结构的雕塑，
上面有Krylon牌喷漆的痕迹。
SCP-173具有生命，且极端敌意。"""
		},
		"/reports/incident_log.txt": {
			"type": "file",
			"content": """事故日志 #2024-0117

日期: 2024年1月17日
地点: Site-19, B区走廊
涉及人员: Dr.████, Agent ████

事故描述:
在例行巡查中，B区走廊的照明系统突然失效。
持续时间约为4.7秒。
在照明恢复后，发现 ████████████████
████████████████████████████████

后续处理:
所有涉及人员已被施行A级记忆删除。
B区已被临时封锁。"""
		},
		"/personnel/dr_bright.txt": {
			"type": "file",
			"content": """人员档案: Dr. Bright

安全等级: 4级
职位: 高级研究员
当前站点: Site-19

备注:
Dr. Bright目前佩戴SCP-963。
有关Dr. Bright不被允许做的事情，
请参阅文件 bright_restrictions.txt

[警告: Dr. Bright的个人请求不应被认真对待]"""
		},
		"/personnel/agent_a.txt": {
			"type": "file",
			"content": """人员档案: Agent A

安全等级: 2级
职位: 外勤特工
当前站点: Site-19

状态: [color=#FF6666]失联[/color]

最后已知位置: Site-19 B区
最后联络时间: 2024-01-17 03:42

备注:
Agent A在事故#2024-0117后失去联络。
搜索行动正在进行中。"""
		},
		"/comms/radio_log.txt": {
			"type": "file",
			"content": """无线电通讯记录
频道: SITE-19-SECURE-7
日期: 2024-01-17

[03:38] 控制室: Alpha小组，报告状态。
[03:38] Agent A: 控制室，Alpha已到达B区入口。一切正常。
[03:39] Agent A: 开始例行巡查。
[03:41] Agent A: 控制室......这里的灯......
[03:41] 控制室: Alpha，请重复。
[03:42] Agent A: ......不对......这里有什么东西在......
[03:42] [信号中断]
[03:42] 控制室: Alpha? Alpha请回复!
[03:45] 控制室: Alpha小组失联。启动应急预案。"""
		}
	}
