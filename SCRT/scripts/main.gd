extends Control
# ============================================================
# 节点引用
# ============================================================
@onready var path_label: Label = $MainContent/StatusFrame/StatusBar/PathLabel
@onready var mail_icon: Label = $MainContent/StatusFrame/StatusBar/MailIcon
@onready var output_text: RichTextLabel = $MainContent/OutputArea/OutputText
@onready var input_field: LineEdit = $MainContent/InputFrame/InputArea/InputField
@onready var scroll_container: ScrollContainer = $MainContent/OutputArea
@onready var status_frame: PanelContainer = $MainContent/StatusFrame
@onready var input_frame: PanelContainer = $MainContent/InputFrame
var background: TextureRect = null  # 由 UIManager 创建
# 模块实例
var save_mgr: SaveManager = SaveManager.new()
var fs: FileSystem = FileSystem.new()
var tw: Typewriter = null
# 主题色快捷引用（在 _ready 中初始化）
var T: ThemeManager.ThemeColors = null
# ============================================================
# 状态变量
# ============================================================
var current_path: String = "/"
var has_new_mail: bool = false
var command_history: Array[String] = []
var history_index: int = -1
var current_input_backup: String = ""
# 桌面/终端模式
var _desktop_mode: bool = true
# ============================================================
# 剧本系统
# ============================================================
var story_loader: StoryLoader = null
var story_manifest: Dictionary = {}
var current_story_path: String = ""
var available_stories: Array[Dictionary] = []
var current_story_index: int = -1
var story_id: String = ""
var read_files: Array[String] = []
var unlocked_passwords: Array[String] = []
# 密码输入弹窗状态
var _password_mode: bool = false
var _password_target_path: String = ""
# 文件密码系统
var _file_password_mode: bool = false
var _file_password_target: String = ""
var _file_password_filename: String = ""
# ============================================================
# 初始化
# ============================================================
func _ready() -> void:
	# 初始化主题系统（必须最先调用）
	ThemeManager.init("phosphor_green")
	T = ThemeManager.current
	# 初始化打字机模块
	tw = Typewriter.new()
	tw.name = "Typewriter"
	add_child(tw)
	save_mgr.ensure_stories_dir()
	save_mgr.ensure_saves_dir()
	var vdisc_dir: String = save_mgr.get_game_root_dir() + "vdisc/"
	_scan_available_stories(vdisc_dir)
	# === UI 初始化（全部委托给 UIManager） ===
	background = UIManager.setup_background(self, save_mgr.get_game_root_dir())
	UIManager.setup_main_content(self, $MainContent)
	UIManager.setup_all_styles(status_frame, path_label, mail_icon, input_frame, input_field, output_text, scroll_container)
	# CRT效果层鼠标穿透
	UIManager.setup_crt_effect($CRTEffect)
	# 自定义CRT风格鼠标光标
	UIManager.setup_custom_cursor(self)
	# 连接超链接信号
	output_text.meta_clicked.connect(_on_meta_clicked)
	# 初始化打字机引用
	tw.setup(output_text, scroll_container)
	# 输入框设置
	input_field.focus_mode = Control.FOCUS_ALL
	input_field.focus_next = input_field.get_path()
	input_field.focus_previous = input_field.get_path()
	input_field.grab_focus()
	_desktop_mode = true
	_update_status_bar()
	_show_desktop_welcome()
# ============================================================
# 复制成功提示（短暂显示后自动消失）
# ============================================================
func _show_copy_toast() -> void:
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	# 在输出区底部临时显示提示
	output_text.append_text("\n[color=" + m + "][已复制到剪贴板][/color]")
	# 1.5秒后移除提示（可选）
	await get_tree().create_timer(1.5).timeout
	# 获取当前文本，移除最后的提示行
	var current_bbcode: String = output_text.text
	var toast_tag: String = "[color=" + m + "][已复制到剪贴板][/color]"
	if current_bbcode.ends_with(toast_tag):
		output_text.text = current_bbcode.substr(0, current_bbcode.length() - toast_tag.length()).rstrip("\n")
# ============================================================
# 输入处理
# ============================================================
func _input(event: InputEvent) -> void:
	# --- 鼠标事件处理 ---
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
				# 右键点击：如果有选中文字则复制到剪贴板
				var selected_text: String = output_text.get_selected_text()
				if not selected_text.is_empty():
					DisplayServer.clipboard_set(selected_text)
					output_text.deselect()
					input_field.grab_focus()
					# 可选：给用户一个复制成功的提示
					_show_copy_toast()
				get_viewport().set_input_as_handled()
				return
			MOUSE_BUTTON_LEFT:
				var mouse_pos: Vector2 = event.position
				var output_rect: Rect2 = output_text.get_global_rect()
				if output_rect.has_point(mouse_pos):
					return
				input_field.grab_focus()
				return
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_pos: Vector2 = event.position
			var output_rect: Rect2 = output_text.get_global_rect()
			if not output_rect.has_point(mouse_pos):
				input_field.grab_focus()
			return
	if not event is InputEventKey or not event.pressed:
		return
	if not input_field.has_focus():
		input_field.grab_focus()
	if tw.is_typing and event.keycode in [KEY_SPACE, KEY_ESCAPE]:
		tw.skip()
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			if tw.is_typing:
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
# 命令提交处理
# ============================================================
func _on_command_submitted(command_text: String) -> void:
	var raw_input: String = command_text.strip_edges()
	input_field.clear()
	if raw_input.is_empty():
		return
	if _file_password_mode:
		_file_password_mode = false
		input_field.placeholder_text = "> 输入命令..."
		while tw.is_typing:
			await get_tree().process_frame
		if output_text.get_parsed_text().length() > 0:
			output_text.append_text("\n")
		output_text.append_text("> " + "*".repeat(raw_input.length()) + "\n")
		if raw_input.to_lower() == "cancel":
			append_output("[color=" + T.muted_hex + "]已取消文件密码输入。[/color]\n", false)
			_file_password_target = ""
			_file_password_filename = ""
			return
		await _verify_file_password(raw_input)
		return
	if _password_mode:
		_password_mode = false
		input_field.placeholder_text = "> 输入命令..."
		while tw.is_typing:
			await get_tree().process_frame
		if output_text.get_parsed_text().length() > 0:
			output_text.append_text("\n")
		output_text.append_text("> " + "*".repeat(raw_input.length()) + "\n")
		if raw_input.to_lower() == "cancel":
			append_output("[color=" + T.muted_hex + "]已取消密码输入。[/color]\n", false)
			return
		_verify_password(raw_input)
		return
	command_history.append(raw_input)
	history_index = -1
	while tw.is_typing:
		await get_tree().process_frame
	if output_text.get_parsed_text().length() > 0:
		output_text.append_text("\n")
	output_text.append_text("> " + raw_input + "\n")
	await _execute_command(raw_input)
# ============================================================
# 命令解析与执行
# ============================================================
func _execute_command(raw_input: String) -> void:
	tw.instant = false
	var parts := raw_input.split(" ", false)
	if parts.is_empty():
		return
	var command: String = parts[0].to_lower()
	var args := parts.slice(1)
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
				append_output("[color=" + T.error_hex + "][ERROR] 未知指令: " + command + "[/color]\n[color=" + T.muted_hex + "]输入 [/color][color=" + T.primary_hex + "]help[/color][color=" + T.muted_hex + "] 查看可用命令。[/color]\n", false)
		return
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
			append_output("[color=" + T.muted_hex + "]磁盘已加载。使用 [/color][color=" + T.primary_hex + "]eject[/color][color=" + T.muted_hex + "] 返回桌面后再切换磁盘，或使用 [/color][color=" + T.primary_hex + "]vdisc load <编号>[/color][color=" + T.muted_hex + "] 直接切换。[/color]\n", false)
		_:
			append_output("[color=" + T.error_hex + "][ERROR] 未知指令: " + command + "[/color]\n输入 [color=" + T.primary_hex + "]help[/color] 查看可用命令。\n", false)
# ============================================================
# 各命令的具体实现
# ============================================================
func _cmd_desktop_help() -> void:
	var p: String = T.primary_hex
	var lines: Array[String] = []
	lines.append("[color=" + p + "]═══════════════ 桌面命令 ═══════════════[/color]")
	lines.append("  [color=" + p + "]load <编号>[/color]   加载指定虚拟磁盘")
	lines.append("  [color=" + p + "]scan[/color]   重新扫描vdisc目录")
	lines.append("  [color=" + p + "]vdisc[/color] 查看磁盘列表详情")
	lines.append("  [color=" + p + "]clear[/color] 清空屏幕")
	lines.append("  [color=" + p + "]reboot[/color] 重启终端")
	lines.append("  [color=" + p + "]exit[/color]   退出终端")
	lines.append("[color=" + p + "]═══════════════════════════════════════[/color]")
	append_output("\n".join(lines) + "\n", false)

func _cmd_help() -> void:
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var lines: Array[String] = []
	lines.append("[color=" + p + "]═══════════════════ 可用命令 ═══════════════════[/color]")
	lines.append("  [color=" + p + "]help[/color]   显示本帮助信息")
	lines.append("  [color=" + p + "]ls[/color] 列出当前目录下的文件和文件夹")
	lines.append("  [color=" + p + "]cd <路径>[/color] 切换到指定目录")
	lines.append("  [color=" + p + "]back[/color]   返回上一级目录")
	lines.append("  [color=" + p + "]open <文件>[/color]   打开并显示文件内容")
	lines.append("  [color=" + p + "]clear[/color] 清空屏幕")
	lines.append("  [color=" + p + "]status[/color] 查看当前用户状态")
	lines.append("  [color=" + p + "]mail[/color]   查看收件箱")
	lines.append("  [color=" + p + "]whoami[/color] 查看当前用户信息")
	lines.append("  [color=" + p + "]vdisc[/color] 查看虚拟磁盘列表和信息")
	lines.append("  [color=" + p + "]vdisc load <编号>[/color] 切换加载指定磁盘")
	lines.append("  [color=" + p + "]scan[/color]   重新扫描虚拟磁盘")
	lines.append("  [color=" + p + "]unlock[/color] 进入密码认证（或 unlock <密码>）")
	lines.append("  [color=" + p + "]eject[/color] 卸载磁盘，返回桌面")
	lines.append("  [color=" + p + "]reboot[/color] 重启终端")
	lines.append("  [color=" + p + "]exit[/color]   退出终端")
	lines.append("[color=" + p + "]═══════════════════════════════════════════════[/color]")
	lines.append("[color=" + m + "]快捷键: ↑↓ 历史命令 | PageUp/Down 滚动 | Tab 自动补全[/color]")
	append_output("\n".join(lines) + "\n", false)

func _cmd_ls() -> void:
	var items := fs.get_children_at_path(current_path)
	if items.is_empty():
		append_output("[color=" + T.muted_hex + "]该目录为空。[/color]")
		return
	var lines: Array[String] = []
	lines.append("[color=" + T.primary_hex + "]目录: " + current_path + "[/color]")
	lines.append("")
	for item in items:
		var item_path := fs.join_path(current_path, item)
		var node := fs.get_node_at_path(item_path)
		if node == null:
			continue
		var item_required: int = fs.get_required_clearance(item_path)
		var is_locked: bool = not fs.has_clearance(item_path)
		if node.type == "folder":
			if is_locked:
				lines.append("  [color=" + T.error_hex + "][DIR]  " + item + "/  【LOCKED LV." + str(item_required) + "】[/color]")
			else:
				lines.append("  [color=" + T.info_hex + "][DIR]  " + item + "/[/color]")
		else:
			if is_locked:
				lines.append("  [color=" + T.error_hex + "][FILE] " + item + "  【LOCKED LV." + str(item_required) + "】[/color]")
			else:
				var fp_key: String = fs.get_file_password_key(item_path)
				if not fp_key.is_empty() and not fs.is_file_password_unlocked(item_path):
					lines.append("  [color=" + T.warning_hex + "][FILE] " + item + "  [PASSWORD][/color]")
				else:
					lines.append("  [color=" + T.success_hex + "][FILE] " + item + "[/color]")
	lines.append("")
	append_output("\n".join(lines) + "\n", false)

func _cmd_cd(args: Array) -> void:
	if args.is_empty():
		append_output("[color=" + T.error_hex + "][ERROR] 用法: cd <目录名>[/color]")
		return
	var target: String = args[0]
	var new_path: String
	if target == "/":
		new_path = "/"
	elif target == "..":
		new_path = fs.get_parent_path(current_path)
	elif target.begins_with("/"):
		new_path = target
	else:
		new_path = fs.join_path(current_path, target)
	new_path = fs.normalize_path(new_path)
	var node := fs.get_node_at_path(new_path)
	if node == null:
		append_output("[color=" + T.error_hex + "][ERROR] 目录不存在: " + target + "[/color]")
		return
	if node.type != "folder":
		append_output("[color=" + T.error_hex + "][ERROR] " + target + " 不是一个目录。[/color]")
		return
	var required: int = fs.get_required_clearance(new_path)
	if not fs.has_clearance(new_path):
		var box: String = fs.build_box_sectioned([
			["ACCESS DENIED", "权限不足"],
			["需要等级: " + str(required) + "  当前等级: " + str(fs.player_clearance)],
			["输入 unlock 尝试密码认证"]
		], T.error_hex)
		append_output(box + "\n", false)
		return
	current_path = new_path
	_update_status_bar()
	append_output("已切换到: " + current_path + "\n", false)

func _cmd_open(args: Array) -> void:
	if args.is_empty():
		append_output("[color=" + T.error_hex + "][ERROR] 用法: open <文件名>[/color]")
		return
	var filename: String = args[0]
	var file_path: String
	if filename.begins_with("/"):
		file_path = filename
	else:
		file_path = fs.join_path(current_path, filename)
	file_path = fs.normalize_path(file_path)
	var node := fs.get_node_at_path(file_path)
	if node == null:
		append_output("[color=" + T.error_hex + "][ERROR] 文件不存在: " + filename + "[/color]")
		return
	if node.type != "file":
		append_output("[color=" + T.error_hex + "][ERROR] " + filename + " 是一个目录，请使用 cd 命令进入。[/color]")
		return
	var required: int = fs.get_required_clearance(file_path)
	if not fs.has_clearance(file_path):
		var box: String = fs.build_box_sectioned([
			["ACCESS DENIED", "权限不足"],
			["需要等级: " + str(required) + "  当前等级: " + str(fs.player_clearance)],
			["输入 unlock 尝试密码认证"]
		], T.error_hex)
		append_output(box + "\n", false)
		return
	var fp_key: String = fs.get_file_password_key(file_path)
	if not fp_key.is_empty() and not fs.is_file_password_unlocked(file_path):
		var fp_info: Dictionary = fs.story_file_passwords[fp_key]
		var hint_text: String = fp_info.get("hint", "")
		var box_lines: Array = [["FILE PASSWORD REQUIRED", "此文件需要输入密码"]]
		if not hint_text.is_empty():
			box_lines.append(["提示: " + hint_text])
		box_lines.append(["请输入密码:", "(输入 cancel 取消)"])
		var box: String = fs.build_box_sectioned(box_lines, T.warning_hex)
		append_output(box + "\n", false)
		_file_password_mode = true
		_file_password_target = file_path
		_file_password_filename = filename
		input_field.placeholder_text = "输入文件密码..."
		return
	while tw.is_typing:
		await get_tree().process_frame
	var content_size: int = node.content.length()
	await tw.show_progress_bar(content_size)
	await get_tree().create_timer(0.5).timeout
	output_text.text = ""
	tw.clear_queue()
	var header: String = "[color=" + T.primary_hex + "]══════════ " + filename + " ══════════[/color]"
	output_text.append_text(header + "\n\n")
	if not read_files.has(file_path):
		read_files.append(file_path)
		save_mgr.auto_save(story_id, fs.player_clearance, read_files, unlocked_passwords, fs.unlocked_file_passwords, current_path)
	var clean_content: String = node.content.strip_edges()
	clean_content = clean_content.replace("\r\n", "\n").replace("\r", "\n")
	append_output(clean_content, false)
	append_output("\n[color=" + T.primary_hex + "]══════════ 文件结束 ══════════[/color]\n[color=" + T.muted_hex + "]输入任意命令返回终端。[/color]\n", false)
	
func _cmd_back() -> void:
	if current_path == "/":
		append_output("[color=" + T.muted_hex + "]已经在根目录了。[/color]")
		return
	current_path = fs.get_parent_path(current_path)
	_update_status_bar()
	append_output("已返回: " + current_path + "\n", false)

func _cmd_clear() -> void:
	output_text.text = ""
	tw.clear_queue()

func _cmd_status() -> void:
	var p: String = T.primary_hex
	var w: String = T.warning_hex
	var m: String = T.muted_hex
	var lines: Array[String] = []
	lines.append("[color=" + p + "]═══════════ 用户状态 ═══════════[/color]")
	lines.append("  用户名: [color=" + p + "]未登录[/color]")
	lines.append("  权限等级:   [color=" + w + "]" + str(fs.player_clearance) + "[/color]")
	lines.append("  当前路径:   [color=" + p + "]" + current_path + "[/color]")
	lines.append("  已读文件:   [color=" + p + "]" + str(read_files.size()) + "[/color]")
	lines.append("  已获取密码: [color=" + p + "]" + str(unlocked_passwords.size()) + "[/color]")
	lines.append("  已解锁文件: [color=" + p + "]" + str(fs.unlocked_file_passwords.size()) + "[/color]")
	if not story_id.is_empty():
		lines.append("  盘ID: [color=" + m + "]" + story_id + "[/color]")
	lines.append("[color=" + p + "]════════════════════════════════[/color]")
	append_output("\n".join(lines) + "\n", false)

func _cmd_mail(args: Array) -> void:
	append_output("[color=" + T.muted_hex + "]收件箱为空。\n(邮件系统将在后续版本中实现)[/color]\n", false)

func _cmd_exit() -> void:
	append_output("[color=" + T.muted_hex + "]正在断开连接...[/color]")
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()

func _cmd_whoami() -> void:
	append_output("[color=" + T.primary_hex + "]未登录用户[/color]\n[color=" + T.muted_hex + "](用户系统将在后续版本中实现)[/color]\n", false)

func _cmd_story_info() -> void:
	var p: String = T.primary_hex
	var s: String = T.success_hex
	var w: String = T.warning_hex
	var m: String = T.muted_hex
	if story_manifest.is_empty() and available_stories.is_empty():
		append_output("[color=" + m + "]未检测到外部虚拟磁盘，当前运行于内置诊断模式。\n将 .scp 或 .zip 文件放入 vdisc/ 目录后输入 scan 重新扫描。[/color]\n", false)
		return
	var lines: Array[String] = []
	lines.append("[color=" + p + "]═══════════════ 虚拟磁盘管理 ═══════════════[/color]")
	if available_stories.size() > 0:
		lines.append("")
		lines.append("  已发现 [color=" + p + "]" + str(available_stories.size()) + "[/color] 个虚拟磁盘:")
		lines.append("")
		for i in range(available_stories.size()):
			var info: Dictionary = available_stories[i]
			var marker: String = ""
			if i == current_story_index:
				marker = " [color=" + s + "]<< 当前[/color]"
			lines.append("  [color=" + w + "]" + str(i + 1) + ".[/color] " + info.get("title", "未知") + " [color=" + m + "](" + info.get("filename", "") + ")[/color]" + marker)
			lines.append("	 作者: [color=" + m + "]" + info.get("author", "未知") + "[/color]")
		lines.append("")
		lines.append("[color=" + m + "]  使用 [/color][color=" + p + "]vdisc load <编号>[/color][color=" + m + "] 切换磁盘[/color]")
		lines.append("[color=" + m + "]  使用 [/color][color=" + p + "]scan[/color][color=" + m + "] 重新扫描目录[/color]")
	if story_manifest.has("story"):
		lines.append("")
		lines.append("[color=" + p + "]─────────── 当前磁盘详情 ───────────[/color]")
		var info: Dictionary = story_manifest["story"]
		lines.append("  磁盘标签: [color=" + p + "]" + info.get("title", "未知") + "[/color]")
		lines.append("  制作者:   [color=" + p + "]" + info.get("author", "未知") + "[/color]")
		lines.append("  版本: [color=" + p + "]" + info.get("version", "未知") + "[/color]")
		if info.has("description"):
			lines.append("  描述: [color=" + m + "]" + info["description"] + "[/color]")
		lines.append("  文件总数: [color=" + p + "]" + str(fs.file_system.size()) + "[/color]")
		lines.append("  磁盘来源: [color=" + m + "]" + current_story_path.get_file() + "[/color]")
		lines.append("  磁盘状态: [color=" + s + "]已挂载[/color]")
	lines.append("[color=" + p + "]═══════════════════════════════════════════[/color]")
	append_output("\n".join(lines) + "\n", false)

func _cmd_vdisc_load(args: Array) -> void:
	if args.is_empty():
		append_output("[color=" + T.error_hex + "][ERROR] 用法: vdisc load <编号>[/color]\n[color=" + T.muted_hex + "]输入 vdisc 查看可用磁盘列表。[/color]\n", false)
		return
	var index_str: String = args[0]
	if not index_str.is_valid_int():
		append_output("[color=" + T.error_hex + "][ERROR] 请输入有效的编号数字。[/color]\n", false)
		return
	var index: int = index_str.to_int() - 1
	if index < 0 or index >= available_stories.size():
		append_output("[color=" + T.error_hex + "][ERROR] 编号超出范围。可用范围: 1-" + str(available_stories.size()) + "[/color]\n", false)
		return
	if index == current_story_index:
		append_output("[color=" + T.muted_hex + "]该磁盘已经是当前加载的磁盘。[/color]\n", false)
		return
	save_mgr.auto_save(story_id, fs.player_clearance, read_files, unlocked_passwords, fs.unlocked_file_passwords, current_path)
	append_output("[color=" + T.muted_hex + "]正在卸载当前磁盘...[/color]", false)
	while tw.is_typing:
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	fs.clear_all()
	story_manifest.clear()
	current_story_path = ""
	story_id = ""
	current_path = "/"
	read_files.clear()
	unlocked_passwords.clear()
	await tw.show_progress_bar(800)
	await get_tree().create_timer(0.3).timeout
	if _load_story_by_index(index):
		var title: String = available_stories[index].get("title", "未知")
		var box: String = fs.build_box_sectioned([
			["DISC LOADED", "磁盘加载完成"],
			[title]
		], T.success_hex)
		append_output(box + "\n", false)
		_update_status_bar()
		append_output("[color=" + T.muted_hex + "]文件数量: " + str(fs.file_system.size()) + "  权限规则: " + str(fs.story_permissions.size()) + " 条[/color]\n", false)
		append_output("[color=" + T.muted_hex + "]当前路径: " + current_path + "  权限等级: " + str(fs.player_clearance) + "[/color]\n", false)
	else:
		append_output("[color=" + T.error_hex + "][ERROR] 磁盘加载失败。[/color]\n", false)
		fs.init_test_file_system()
		_update_status_bar()

func _cmd_unlock(args: Array) -> void:
	if not args.is_empty():
		_verify_password(args[0])
		return
	_enter_password_mode()

func _enter_password_mode(target_path: String = "") -> void:
	_password_mode = true
	_password_target_path = target_path
	var box: String = fs.build_box_sectioned([
		["SECURITY AUTHENTICATION", "安全认证系统"],
		["请输入访问密码:", "(输入 cancel 取消)"]
	], T.warning_hex)
	append_output(box + "\n", false)
	input_field.placeholder_text = "输入密码..."

func _verify_password(password: String) -> void:
	if not story_manifest.has("passwords"):
		append_output("[color=" + T.error_hex + "][ERROR] 当前剧本未配置密码系统。[/color]\n", false)
		return
	var passwords: Dictionary = story_manifest["passwords"]
	if passwords.has(password):
		var pwd_info: Dictionary = passwords[password]
		var grant_level: int = int(float(pwd_info.get("grants_clearance", 0)))
		if unlocked_passwords.has(password):
			append_output("[color=" + T.muted_hex + "]该密码已使用过。当前权限等级: " + str(fs.player_clearance) + "[/color]\n", false)
			return
		if grant_level <= fs.player_clearance:
			append_output("[color=" + T.muted_hex + "]该密码对应的权限等级不高于当前等级。当前: " + str(fs.player_clearance) + "[/color]\n", false)
			return
		unlocked_passwords.append(password)
		var old_level: int = fs.player_clearance
		fs.player_clearance = grant_level
		save_mgr.auto_save(story_id, fs.player_clearance, read_files, unlocked_passwords, fs.unlocked_file_passwords, current_path)
		var box: String = fs.build_box_sectioned([
			["ACCESS GRANTED", "权限认证通过"],
			["权限等级: " + str(old_level) + " -> " + str(fs.player_clearance)]
		], T.success_hex)
		append_output(box + "\n", false)
		if pwd_info.has("message"):
			append_output("[color=" + T.muted_hex + "]" + str(pwd_info["message"]) + "[/color]\n", false)
	else:
		var box: String = fs.build_box(["ACCESS DENIED", "密码验证失败"] as Array[String], T.error_hex)
		append_output(box + "\n", false)

func _verify_file_password(input_password: String) -> void:
	var fp_key: String = fs.get_file_password_key(_file_password_target)
	if fp_key.is_empty():
		append_output("[color=" + T.error_hex + "][ERROR] 内部错误：未找到文件密码配置。[/color]\n", false)
		return
	var fp_info: Dictionary = fs.story_file_passwords[fp_key]
	var correct_password: String = str(fp_info.get("password", ""))
	if input_password == correct_password:
		fs.unlocked_file_passwords.append(_file_password_target)
		save_mgr.auto_save(story_id, fs.player_clearance, read_files, unlocked_passwords, fs.unlocked_file_passwords, current_path)
		var box: String = fs.build_box(["PASSWORD ACCEPTED", "文件密码验证通过"] as Array[String], T.success_hex)
		append_output(box + "\n", false)
		while tw.is_typing:
			await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout
		await _cmd_open([_file_password_filename])
	else:
		var box: String = fs.build_box(["PASSWORD REJECTED", "文件密码错误"] as Array[String], T.error_hex)
		append_output(box + "\n", false)

func _cmd_scan() -> void:
	append_output("[color=" + T.muted_hex + "]正在扫描vdisc目录...[/color]", false)
	while tw.is_typing:
		await get_tree().process_frame
	await tw.show_progress_bar(500)
	await get_tree().create_timer(0.3).timeout
	var old_story_path: String = current_story_path
	fs.clear_all()
	story_manifest.clear()
	current_story_path = ""
	story_id = ""
	read_files.clear()
	unlocked_passwords.clear()
	available_stories.clear()
	current_story_index = -1
	var vdisc_dir: String = save_mgr.get_game_root_dir() + "vdisc/"
	_scan_available_stories(vdisc_dir)
	if _desktop_mode:
		if available_stories.is_empty():
			append_output("[color=" + T.warning_hex + "][WARN] 未找到虚拟磁盘文件。[/color]", false)
			append_output("[color=" + T.muted_hex + "]请将 .scp 文件放入 vdisc/ 目录后重新扫描。[/color]\n", false)
		else:
			var scan_lines: Array[String] = []
			scan_lines.append("[color=" + T.success_hex + "][OK] 扫描完成，发现 " + str(available_stories.size()) + " 个虚拟磁盘。[/color]")
			scan_lines.append("")
			for i in range(available_stories.size()):
				var info: Dictionary = available_stories[i]
				scan_lines.append("  [color=" + T.warning_hex + "]" + str(i + 1) + ".[/color] " + info.get("title", "未知") + " [color=" + T.muted_hex + "](" + info.get("filename", "") + ")[/color]")
			scan_lines.append("")
			scan_lines.append("[color=" + T.muted_hex + "]输入 [/color][color=" + T.primary_hex + "]load <编号>[/color][color=" + T.muted_hex + "] 加载磁盘。[/color]")
			append_output("\n".join(scan_lines) + "\n", false)
		_update_status_bar()
	else:
		if available_stories.is_empty():
			_desktop_mode = true
			fs.init_test_file_system()
			current_path = "/"
			_update_status_bar()
			append_output("[color=" + T.warning_hex + "][WARN] 未找到剧本文件，已返回桌面。[/color]\n", false)
		elif _load_story_by_index(0):
			var title: String = "未知"
			if story_manifest.has("story") and story_manifest["story"].has("title"):
				title = story_manifest["story"]["title"]
			append_output("[color=" + T.success_hex + "][OK] 已重新加载剧本: " + title + "[/color]", false)
			append_output("[color=" + T.muted_hex + "]文件数量: " + str(fs.file_system.size()) + "  权限规则: " + str(fs.story_permissions.size()) + " 条[/color]\n", false)
			if story_manifest.has("settings") and story_manifest["settings"].has("start_path"):
				current_path = story_manifest["settings"]["start_path"]
			else:
				current_path = "/"
			_update_status_bar()
		else:
			append_output("[color=" + T.error_hex + "][ERROR] 重新加载失败。[/color]\n", false)

func _cmd_reboot() -> void:
	append_output("[color=" + T.muted_hex + "]正在重启终端...[/color]", false)
	while tw.is_typing:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	output_text.text = ""
	tw.clear_queue()
	command_history.clear()
	history_index = -1
	fs.clear_all()
	story_manifest.clear()
	current_story_path = ""
	story_id = ""
	current_path = "/"
	has_new_mail = false
	read_files.clear()
	unlocked_passwords.clear()
	available_stories.clear()
	current_story_index = -1
	save_mgr.ensure_stories_dir()
	var vdisc_dir: String = save_mgr.get_game_root_dir() + "vdisc/"
	_scan_available_stories(vdisc_dir)
	output_text.append_text("[color=" + T.muted_hex + "]...[/color]\n")
	await get_tree().create_timer(0.3).timeout
	output_text.append_text("[color=" + T.muted_hex + "]终端系统重新初始化中...[/color]\n")
	await get_tree().create_timer(0.5).timeout
	output_text.text = ""
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
# 自动补全
# ============================================================
func _auto_complete() -> void:
	var current_text: String = input_field.text
	if current_text.strip_edges().is_empty():
		return
	var parts := current_text.split(" ", false)
	if parts.size() == 1:
		if current_text.ends_with(" "):
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
					if display.size() > 0:
						output_text.append_text("\n[color=" + T.muted_hex + "]可选项: " + " | ".join(display) + "[/color]")
						tw._do_scroll()
		else:
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
				output_text.append_text("\n[color=" + T.muted_hex + "]可选命令: " + " | ".join(matches) + "[/color]")
				tw._do_scroll()
	elif parts.size() == 2:
		var cmd: String = parts[0].to_lower()
		var partial_name: String = parts[1]
		if cmd in ["cd", "open", "cat"]:
			var children := fs.get_children_at_path(current_path)
			var matches: Array[String] = []
			for child in children:
				if child.to_lower().begins_with(partial_name.to_lower()):
					var child_path := fs.join_path(current_path, child)
					var node := fs.get_node_at_path(child_path)
					if node == null:
						continue
					if cmd == "cd" and node.type == "folder":
						matches.append(child)
					elif cmd in ["open", "cat"] and node.type == "file":
						matches.append(child)
			if matches.size() == 1:
				input_field.text = cmd + " " + matches[0]
				input_field.caret_column = input_field.text.length()
			elif matches.size() > 1:
				var common: String = _find_common_prefix(matches)
				if common.length() > partial_name.length():
					input_field.text = cmd + " " + common
					input_field.caret_column = input_field.text.length()
				output_text.append_text("\n[color=" + T.muted_hex + "]可选项: " + " | ".join(matches) + "[/color]")
				tw._do_scroll()

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
# 输出工具（转发到打字机模块）
# ============================================================
func append_output(text: String, extra_newline: bool = true) -> void:
	tw.append(text, extra_newline)
# ============================================================
# 每帧处理（滚动）
# ============================================================
func _process(_delta: float) -> void:
	tw.process_scroll()
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
		path_label.text = "[" + current_path + "]  LV:" + str(fs.player_clearance)
	else:
		path_label.text = "[" + current_path + "]  LV:" + str(fs.player_clearance) + "  DISC:" + disc_name
	if has_new_mail:
		mail_icon.text = "[Mail NEW]"
	else:
		mail_icon.text = "[Mail]"
# ============================================================
# 超链接处理
# ============================================================
func _on_meta_clicked(meta: Variant) -> void:
	var meta_str: String = str(meta)
	if meta_str.begins_with("cmd://"):
		var cmd: String = meta_str.substr(6)
		if output_text.get_parsed_text().length() > 0:
			output_text.append_text("\n")
		output_text.append_text("> " + cmd)
		output_text.append_text("\n")
		_execute_command(cmd)
		return
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
	var p: String = T.primary_hex
	var w: String = T.warning_hex
	var m: String = T.muted_hex
	var title: String = "SCP FOUNDATION TERMINAL v0.1"
	var subtitle: String = "SECURE - CONTAIN - PROTECT"
	var box: String = fs.build_box([title, subtitle] as Array[String], p)
	output_text.append_text(box + "\n\n")
	if available_stories.is_empty():
		output_text.append_text("[color=" + w + "]未检测到虚拟磁盘。[/color]\n")
		output_text.append_text("[color=" + m + "]请将 .scp 文件放入 vdisc/ 目录后输入 scan 重新扫描。[/color]\n\n")
	else:
		output_text.append_text("[color=" + p + "]检测到 " + str(available_stories.size()) + " 个虚拟磁盘:[/color]\n\n")
		for i in range(available_stories.size()):
			var info: Dictionary = available_stories[i]
			output_text.append_text("  [color=" + w + "]" + str(i + 1) + ".[/color] [color=" + p + "]" + info.get("title", "未知") + "[/color]\n")
			output_text.append_text("	 [color=" + m + "]" + info.get("author", "未知") + " | " + info.get("filename", "") + "[/color]\n")
		output_text.append_text("\n")
	output_text.append_text("[color=" + m + "]可用命令:[/color]\n")
	output_text.append_text("  [color=" + p + "]load <编号>[/color]   加载指定磁盘\n")
	output_text.append_text("  [color=" + p + "]scan[/color]   重新扫描磁盘目录\n")
	output_text.append_text("  [color=" + p + "]clear[/color] 清空屏幕\n")
	output_text.append_text("  [color=" + p + "]exit[/color]   退出终端\n")

func _cmd_desktop_load(args: Array) -> void:
	if args.is_empty():
		append_output("[color=" + T.error_hex + "][ERROR] 用法: load <编号>[/color]", false)
		if available_stories.size() > 0:
			append_output("[color=" + T.muted_hex + "]可用磁盘: 1-" + str(available_stories.size()) + "[/color]\n", false)
		return
	var index_str: String = args[0]
	if not index_str.is_valid_int():
		append_output("[color=" + T.error_hex + "][ERROR] 请输入有效的编号数字。[/color]\n", false)
		return
	var index: int = index_str.to_int() - 1
	if index < 0 or index >= available_stories.size():
		append_output("[color=" + T.error_hex + "][ERROR] 编号超出范围。可用范围: 1-" + str(available_stories.size()) + "[/color]\n", false)
		return
	append_output("[color=" + T.muted_hex + "]正在加载虚拟磁盘...[/color]", false)
	while tw.is_typing:
		await get_tree().process_frame
	await tw.show_progress_bar(800)
	await get_tree().create_timer(0.3).timeout
	if _load_story_by_index(index):
		_desktop_mode = false
		var title: String = available_stories[index].get("title", "未知")
		output_text.text = ""
		tw.clear_queue()
		_update_status_bar()
		_show_welcome_message()
	else:
		append_output("[color=" + T.error_hex + "][ERROR] 磁盘加载失败。[/color]\n", false)

func _cmd_eject() -> void:
	if _desktop_mode:
		append_output("[color=" + T.muted_hex + "]当前已在桌面模式。[/color]\n", false)
		return
	save_mgr.auto_save(story_id, fs.player_clearance, read_files, unlocked_passwords, fs.unlocked_file_passwords, current_path)
	append_output("[color=" + T.muted_hex + "]正在卸载磁盘...[/color]", false)
	while tw.is_typing:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	fs.clear_all()
	story_manifest.clear()
	current_story_path = ""
	story_id = ""
	current_path = "/"
	read_files.clear()
	unlocked_passwords.clear()
	current_story_index = -1
	_desktop_mode = true
	output_text.text = ""
	tw.clear_queue()
	_update_status_bar()
	_show_desktop_welcome()
# ============================================================
# 欢迎信息
# ============================================================
func _show_welcome_message() -> void:
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var title: String = "SCP FOUNDATION TERMINAL v0.1"
	var subtitle: String = "SECURE - CONTAIN - PROTECT"
	if story_manifest.has("story"):
		var story_info: Dictionary = story_manifest["story"]
		if story_info.has("title"):
			subtitle = story_info["title"]
	var title_display_len: int = fs.display_width(title)
	var subtitle_display_len: int = fs.display_width(subtitle)
	var inner_width: int = max(title_display_len, subtitle_display_len) + 6
	var title_pad_total: int = inner_width - title_display_len
	var title_pad_left: int = title_pad_total / 2
	var title_pad_right: int = title_pad_total - title_pad_left
	var subtitle_pad_total: int = inner_width - subtitle_display_len
	var subtitle_pad_left: int = subtitle_pad_total / 2
	var subtitle_pad_right: int = subtitle_pad_total - subtitle_pad_left
	var border_h: String = "═".repeat(inner_width)
	var welcome: String = ""
	welcome += "[color=" + p + "]╔" + border_h + "╗\n"
	welcome += "║" + " ".repeat(title_pad_left) + title + " ".repeat(title_pad_right) + "║\n"
	welcome += "║" + " ".repeat(subtitle_pad_left) + subtitle + " ".repeat(subtitle_pad_right) + "║\n"
	welcome += "╚" + border_h + "╝[/color]\n"
	welcome += "\n"
	welcome += "[color=" + m + "]终端系统已启动。\n"
	welcome += "输入 [/color][color=" + p + "]help[/color][color=" + m + "] 查看可用命令。[/color]\n"
	output_text.append_text(welcome)
# ============================================================
# 剧本加载系统
# ============================================================
func _try_load_story() -> bool:
	var vdisc_dir: String = save_mgr.get_game_root_dir() + "vdisc/"
	print("[StoryLoader] 搜索目录: " + vdisc_dir)
	_scan_available_stories(vdisc_dir)
	return not available_stories.is_empty()

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
			var info: Dictionary = _peek_story_info(full_path)
			info["path"] = full_path
			info["filename"] = file_name
			available_stories.append(info)
			print("[StoryLoader] 发现剧本: " + file_name + " -> " + info.get("title", "未知"))
		file_name = dir.get_next()
	print("[StoryLoader] 共发现 " + str(available_stories.size()) + " 个剧本文件")

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
	fs.file_system = story_loader.file_system
	story_manifest = story_loader.manifest
	current_story_path = path
	if story_manifest.has("story") and story_manifest["story"].has("id"):
		story_id = story_manifest["story"]["id"]
	else:
		story_id = str(path.get_file().hash())
	fs.story_permissions.clear()
	if story_manifest.has("permissions"):
		var perms: Dictionary = story_manifest["permissions"]
		for perm_path in perms.keys():
			fs.story_permissions[perm_path] = int(perms[perm_path])
		print("[StoryLoader] 权限表已加载，共 " + str(fs.story_permissions.size()) + " 条规则")
	else:
		print("[StoryLoader] 警告: manifest中未找到permissions字段")
	if story_manifest.has("passwords"):
		print("[StoryLoader] 密码表已加载，共 " + str(story_manifest["passwords"].size()) + " 个密码")
	else:
		print("[StoryLoader] 警告: manifest中未找到passwords字段")
	# 读取文件密码表
	fs.story_file_passwords.clear()
	if story_manifest.has("file_passwords"):
		var fps: Dictionary = story_manifest["file_passwords"]
		for fp_path in fps.keys():
			fs.story_file_passwords[fp_path] = fps[fp_path]
		print("[StoryLoader] 文件密码表已加载，共 " + str(fs.story_file_passwords.size()) + " 条")
	else:
		print("[StoryLoader] 未配置文件密码表（file_passwords）")
	# 应用 manifest 中的设置
	var start_clearance: int = 0
	if story_manifest.has("settings"):
		var settings: Dictionary = story_manifest["settings"]
		if settings.has("start_path"):
			current_path = settings["start_path"]
		if settings.has("typing_speed"):
			tw.base_speed = settings["typing_speed"].to_float()
		if settings.has("start_clearance"):
			start_clearance = int(settings["start_clearance"])
	# 尝试加载该剧本的存档
	var save_data = save_mgr.load_save(story_id)
	if save_data != null:
		fs.player_clearance = int(save_data.get("player_clearance", 0))
		read_files.clear()
		if save_data.has("read_files"):
			for f in save_data["read_files"]:
				read_files.append(str(f))
		unlocked_passwords.clear()
		if save_data.has("unlocked_passwords"):
			for pwd in save_data["unlocked_passwords"]:
				unlocked_passwords.append(str(pwd))
		fs.unlocked_file_passwords.clear()
		if save_data.has("unlocked_file_passwords"):
			for fp in save_data["unlocked_file_passwords"]:
				fs.unlocked_file_passwords.append(str(fp))
		if save_data.has("current_path"):
			var saved_path: String = save_data["current_path"]
			if fs.has_clearance(saved_path):
				current_path = saved_path
			else:
				current_path = "/"
				if story_manifest.has("settings") and story_manifest["settings"].has("start_path"):
					current_path = story_manifest["settings"]["start_path"]
		print("[Save] 权限等级: " + str(fs.player_clearance))
	else:
		# 没有存档，用初始权限
		fs.player_clearance = start_clearance
		read_files.clear()
		unlocked_passwords.clear()
	var title: String = "未知剧本"
	if story_manifest.has("story") and story_manifest["story"].has("title"):
		title = story_manifest["story"]["title"]
	print("[StoryLoader] 成功加载: " + title)
	print("[StoryLoader] 盘ID: " + story_id)
	print("[StoryLoader] 文件数量: " + str(fs.file_system.size()))
	print("[StoryLoader] 权限等级: " + str(fs.player_clearance))
	print("[StoryLoader] story_permissions 内容: " + str(fs.story_permissions))
	print("[StoryLoader] passwords 存在: " + str(story_manifest.has("passwords")))
	return true
