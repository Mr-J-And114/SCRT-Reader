# command_handler.gd
# 职责：命令解析、分发、历史记录管理
class_name CommandHandler
extends RefCounted

signal command_executed(cmd_name: String, args: Array)

var main: Node = null
var fs = null
var T = null
var tw = null
var disc_mgr = null
var user_mgr = null
var crtml = null

# 命令历史
var command_history: Array[String] = []
var history_index: int = -1
const MAX_HISTORY: int = 50

# 命令注册表
var _commands: Dictionary = {}

func setup(p_main: Node, p_fs, p_theme, p_tw, p_disc_mgr, p_user_mgr, p_crtml) -> void:
	main = p_main
	fs = p_fs
	T = p_theme
	tw = p_tw
	disc_mgr = p_disc_mgr
	user_mgr = p_user_mgr
	crtml = p_crtml
	_register_commands()

func _register_commands() -> void:
	# ══════════════════════════════════════
	# 通用命令（所有模式可用）
	# ══════════════════════════════════════
	_commands["help"] = { "method": "_cmd_help", "min_args": 0, "help": "显示帮助信息" }
	_commands["clear"] = { "method": "_cmd_clear", "min_args": 0, "help": "清空屏幕" }
	_commands["cls"] = { "method": "_cmd_clear", "min_args": 0, "help": "清空屏幕（别名）" }
	_commands["exit"] = { "method": "_cmd_exit", "min_args": 0, "help": "退出终端" }
	_commands["quit"] = { "method": "_cmd_exit", "min_args": 0, "help": "退出终端（别名）" }
	_commands["scan"] = { "method": "_cmd_scan", "min_args": 0, "help": "重新扫描磁盘" }
	_commands["theme"] = { "method": "_cmd_theme", "min_args": 0, "help": "切换主题" }
	_commands["reboot"] = { "method": "_cmd_reboot", "min_args": 0, "help": "重启终端" }
	_commands["restart"] = { "method": "_cmd_reboot", "min_args": 0, "help": "重启终端（别名）" }
	_commands["vdisc"] = { "method": "_cmd_vdisc", "min_args": 0, "help": "查看虚拟磁盘列表" }
	_commands["clearsave"] = { "method": "_cmd_clearsave", "min_args": 0, "help": "清除存档 (clearsave / clearsave all)" }

	# ══════════════════════════════════════
	# 桌面模式专用命令
	# ══════════════════════════════════════
	_commands["load"] = { "method": "_cmd_load", "min_args": 1, "help": "加载磁盘 (load <编号>)", "desktop_only": true }

	# ══════════════════════════════════════
	# 磁盘模式专用命令
	# ══════════════════════════════════════
	_commands["ls"] = { "method": "_cmd_ls", "min_args": 0, "help": "列出目录内容", "disc_only": true }
	_commands["dir"] = { "method": "_cmd_ls", "min_args": 0, "help": "列出目录内容（别名）", "disc_only": true }
	_commands["cd"] = { "method": "_cmd_cd", "min_args": 1, "help": "切换目录 (cd <路径>)", "disc_only": true }
	_commands["back"] = { "method": "_cmd_back", "min_args": 0, "help": "返回上一级目录", "disc_only": true }
	_commands["open"] = { "method": "_cmd_open", "min_args": 1, "help": "打开文件 (open <文件名>)", "disc_only": true }
	_commands["cat"] = { "method": "_cmd_open", "min_args": 1, "help": "打开文件（别名）", "disc_only": true }
	_commands["status"] = { "method": "_cmd_status", "min_args": 0, "help": "查看用户状态", "disc_only": true }
	_commands["whoami"] = { "method": "_cmd_whoami", "min_args": 0, "help": "查看当前用户", "disc_only": true }
	_commands["mail"] = { "method": "_cmd_mail", "min_args": 0, "help": "查看收件箱", "disc_only": true }
	_commands["unlock"] = { "method": "_cmd_unlock", "min_args": 0, "help": "密码认证 (unlock [密码])", "disc_only": true }
	_commands["eject"] = { "method": "_cmd_eject", "min_args": 0, "help": "卸载磁盘，返回桌面", "disc_only": true }
	_commands["save"] = { "method": "_cmd_save", "min_args": 0, "help": "保存进度", "disc_only": true }

## ══════════════════════════════════════════
## 解析并执行命令
## ══════════════════════════════════════════
func execute(raw_input: String) -> void:
	var trimmed: String = raw_input.strip_edges()
	if trimmed.is_empty():
		return

	_add_to_history(trimmed)

	var parts: PackedStringArray = trimmed.split(" ", false)
	var cmd_name: String = parts[0].to_lower()
	var args: Array = []
	for i in range(1, parts.size()):
		args.append(parts[i])

	# 查找命令
	if not _commands.has(cmd_name):
		main.append_output("[color=" + T.error_hex + "][ERROR] 未知命令: " + cmd_name + "。输入 help 查看可用命令。[/color]\n", false)
		return

	var cmd_info: Dictionary = _commands[cmd_name]

	# 模式检查
	if cmd_info.get("desktop_only", false) and not main._desktop_mode:
		main.append_output("[color=" + T.error_hex + "][ERROR] 此命令仅在桌面模式下可用。[/color]\n", false)
		return
	if cmd_info.get("disc_only", false) and main._desktop_mode:
		main.append_output("[color=" + T.error_hex + "][ERROR] 请先加载磁盘。[/color]\n", false)
		return

	# 参数数量检查
	if args.size() < cmd_info["min_args"]:
		main.append_output("[color=" + T.error_hex + "][ERROR] 参数不足。[/color]\n", false)
		return

	# 通过方法名字符串调用
	var method_name: String = cmd_info["method"]
	if has_method(method_name):
		await call(method_name, args)
	else:
		main.append_output("[color=" + T.error_hex + "][ERROR] 内部错误：方法 " + method_name + " 不存在。[/color]\n", false)

	command_executed.emit(cmd_name, args)

## ══════════════════════════════════════════
## Tab 自动补全
## ══════════════════════════════════════════
func get_completions(partial: String) -> Array[String]:
	var results: Array[String] = []
	var parts: PackedStringArray = partial.split(" ", false)
	var ends_with_space: bool = partial.ends_with(" ")

	if parts.size() == 0:
		return results

	if parts.size() == 1 and not ends_with_space:
		# 补全命令名
		var prefix: String = parts[0].to_lower()
		for cmd_key in _commands:
			if cmd_key.begins_with(prefix):
				var cmd_info: Dictionary = _commands[cmd_key]
				if cmd_info.get("desktop_only", false) and not main._desktop_mode:
					continue
				if cmd_info.get("disc_only", false) and main._desktop_mode:
					continue
				results.append(cmd_key)

	elif parts.size() == 1 and ends_with_space:
		# 输入了命令+空格，列出所有可选子参数
		var cmd: String = parts[0].to_lower()
		if cmd in ["cd", "open", "cat"]:
			var children: Array = fs.get_children_at_path(main.current_path)
			for child in children:
				var child_str: String = str(child)
				var child_path: String = fs.join_path(main.current_path, child_str)
				var node = fs.get_node_at_path(child_path)
				if node == null:
					continue
				if cmd == "cd" and node.type == "folder":
					results.append(cmd + " " + child_str)
				elif cmd in ["open", "cat"] and node.type == "file":
					results.append(cmd + " " + child_str)
		elif cmd == "theme":
			# ★ 这里是修复点：theme + 空格时列出所有主题名
			var themes: Array[String] = ThemeManager.get_available_themes()
			for theme_name in themes:
				results.append(cmd + " " + theme_name)

	elif parts.size() >= 2:
		# 补全子参数（部分输入）
		var cmd: String = parts[0].to_lower()
		var partial_name: String = parts[-1]
		if cmd == "theme":
			# ★ theme 放在最前面，避免被 cd/open/cat 的兜底逻辑截获
			var themes: Array[String] = ThemeManager.get_available_themes()
			for theme_name in themes:
				if theme_name.to_lower().begins_with(partial_name.to_lower()):
					results.append(cmd + " " + theme_name)
		elif cmd in ["cd", "open", "cat"]:
			var items: Array = fs.get_children_at_path(main.current_path)
			for item in items:
				var item_str: String = str(item)
				if item_str.to_lower().begins_with(partial_name.to_lower()):
					var item_path: String = fs.join_path(main.current_path, item_str)
					var node = fs.get_node_at_path(item_path)
					if node == null:
						continue
					if cmd == "cd" and node.type == "folder":
						results.append(cmd + " " + item_str)
					elif cmd in ["open", "cat"] and node.type == "file":
						results.append(cmd + " " + item_str)
					elif cmd not in ["cd"]:
						results.append(cmd + " " + item_str)

	return results


## ══════════════════════════════════════════
## 历史命令导航
## ══════════════════════════════════════════
func history_up() -> String:
	if command_history.is_empty():
		return ""
	if history_index < command_history.size() - 1:
		history_index += 1
	return command_history[-(history_index + 1)]

func history_down() -> String:
	if history_index > 0:
		history_index -= 1
		return command_history[-(history_index + 1)]
	history_index = -1
	return ""

func _add_to_history(cmd: String) -> void:
	if command_history.is_empty() or command_history[-1] != cmd:
		command_history.append(cmd)
		if command_history.size() > MAX_HISTORY:
			command_history.pop_front()
	history_index = -1

## ══════════════════════════════════════════
## 具体命令实现
## 所有方法统一签名: func _cmd_xxx(args: Array) -> void
## ══════════════════════════════════════════

func _cmd_clear(_args: Array = []) -> void:
	main.output_text.text = ""
	tw.clear_queue()

func _cmd_exit(_args: Array = []) -> void:
	main.append_output("[color=" + T.muted_hex + "]正在断开连接...[/color]\n", false)
	await main.get_tree().create_timer(1.0).timeout
	main.get_tree().quit()


func _cmd_reboot(_args: Array = []) -> void:
	main.append_output("[color=" + T.muted_hex + "]正在重启终端...[/color]\n", false)
	while tw.is_typing:
		await main.get_tree().process_frame
	await main.get_tree().create_timer(0.5).timeout

	command_history.clear()
	history_index = -1
	disc_mgr.reset_all()

	main.output_text.append_text("[color=" + T.muted_hex + "]...[/color]\n")
	await main.get_tree().create_timer(0.3).timeout
	main.output_text.append_text("[color=" + T.muted_hex + "]终端系统重新初始化中...[/color]\n")
	await main.get_tree().create_timer(0.5).timeout

	main.output_text.text = ""
	disc_mgr.show_desktop_welcome()
	main.input_field.grab_focus()

	# ★ 重启后刷新所有 Shader，确保主题完全生效
	ThemeManager._refresh_all_ui(main)



func _cmd_help(_args: Array = []) -> void:
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var lines: Array[String] = []

	if main._desktop_mode:
		lines.append("[color=" + p + "]═══════════════ 桌面命令 ═══════════════[/color]")
		lines.append("  [color=" + p + "]load <编号>[/color]   加载指定虚拟磁盘")
		lines.append("  [color=" + p + "]scan[/color]          重新扫描vdisc目录")
		lines.append("  [color=" + p + "]vdisc[/color]         查看磁盘列表详情")
		lines.append("  [color=" + p + "]theme[/color]         查看/切换主题")
		lines.append("  [color=" + p + "]clear/cls[/color]     清空屏幕")
		lines.append("  [color=" + p + "]reboot[/color]        重启终端")
		lines.append("  [color=" + p + "]clearsave[/color]     清除存档")
		lines.append("  [color=" + p + "]exit[/color]          退出终端")
		lines.append("[color=" + p + "]═══════════════════════════════════════[/color]")
	else:
		lines.append("[color=" + p + "]═══════════════════ 可用命令 ═══════════════════[/color]")
		lines.append("  [color=" + p + "]help[/color]          显示本帮助信息")
		lines.append("  [color=" + p + "]ls[/color]            列出当前目录下的文件和文件夹")
		lines.append("  [color=" + p + "]cd <路径>[/color]     切换到指定目录")
		lines.append("  [color=" + p + "]back[/color]          返回上一级目录")
		lines.append("  [color=" + p + "]open <文件>[/color]   打开并显示文件内容")
		lines.append("  [color=" + p + "]clear[/color]         清空屏幕")
		lines.append("  [color=" + p + "]status[/color]        查看当前用户状态")
		lines.append("  [color=" + p + "]mail[/color]          查看收件箱")
		lines.append("  [color=" + p + "]whoami[/color]        查看当前用户信息")
		lines.append("  [color=" + p + "]vdisc[/color]         查看虚拟磁盘列表和信息")
		lines.append("  [color=" + p + "]scan[/color]          重新扫描虚拟磁盘")
		lines.append("  [color=" + p + "]theme[/color]         查看/切换主题")
		lines.append("  [color=" + p + "]unlock[/color]        进入密码认证(或 unlock <密码>)")
		lines.append("  [color=" + p + "]eject[/color]         卸载磁盘，返回桌面")
		lines.append("  [color=" + p + "]save[/color]          保存进度")
		lines.append("  [color=" + p + "]clearsave[/color]     清除存档 (clearsave / clearsave all)")
		lines.append("  [color=" + p + "]reboot[/color]        重启终端")
		lines.append("  [color=" + p + "]exit[/color]          退出终端")
		lines.append("[color=" + p + "]═══════════════════════════════════════════════[/color]")
	lines.append("[color=" + m + "]快捷键: ↑↓ 历史命令 | PageUp/Down 滚动 | Tab 自动补全[/color]")

	main.append_output("\n".join(lines) + "\n", false)

func _cmd_ls(_args: Array = []) -> void:
	var items: Array = fs.get_children_at_path(main.current_path)
	if items.is_empty():
		main.append_output("[color=" + T.muted_hex + "]该目录为空。[/color]\n", false)
		return

	var lines: Array[String] = []
	lines.append("[color=" + T.primary_hex + "]目录: " + main.current_path + "[/color]")
	lines.append("")

	for item in items:
		var item_str: String = str(item)
		var item_path: String = fs.join_path(main.current_path, item_str)
		var node = fs.get_node_at_path(item_path)
		if node == null:
			continue

		var item_required: int = fs.get_required_clearance(item_path)
		var is_locked: bool = not fs.has_clearance(item_path)

		if node.type == "folder":
			if is_locked:
				lines.append("  [color=" + T.error_hex + "][DIR]  " + item_str + "/  【LOCKED LV." + str(item_required) + "】[/color]")
			else:
				lines.append("  [color=" + T.info_hex + "][DIR]  " + item_str + "/[/color]")
		else:
			if is_locked:
				lines.append("  [color=" + T.error_hex + "][FILE] " + item_str + "  【LOCKED LV." + str(item_required) + "】[/color]")
			else:
				var fp_key: String = fs.get_file_password_key(item_path)
				if not fp_key.is_empty() and not fs.is_file_password_unlocked(item_path):
					lines.append("  [color=" + T.warning_hex + "][FILE] " + item_str + "  [PASSWORD][/color]")
				else:
					lines.append("  [color=" + T.success_hex + "][FILE] " + item_str + "[/color]")

	lines.append("")
	main.append_output("\n".join(lines) + "\n", false)

func _cmd_cd(args: Array = []) -> void:
	if args.is_empty():
		main.append_output("[color=" + T.error_hex + "][ERROR] 用法: cd <路径>[/color]\n", false)
		return

	var target: String = str(args[0])
	var new_path: String

	if target == "/":
		new_path = "/"
	elif target == "..":
		new_path = fs.get_parent_path(main.current_path)
	elif target.begins_with("/"):
		new_path = target
	else:
		new_path = fs.join_path(main.current_path, target)

	new_path = fs.normalize_path(new_path)

	var node = fs.get_node_at_path(new_path)
	if node == null:
		main.append_output("[color=" + T.error_hex + "][ERROR] 目录不存在: " + target + "[/color]\n", false)
		return
	if node.type != "folder":
		main.append_output("[color=" + T.error_hex + "][ERROR] " + target + " 不是一个目录。[/color]\n", false)
		return

	var required: int = fs.get_required_clearance(new_path)
	if not fs.has_clearance(new_path):
		var box: String = fs.build_box_sectioned([
			["ACCESS DENIED", "权限不足"],
			["需要等级: " + str(required) + "  当前等级: " + str(fs.player_clearance)],
			["输入 unlock 尝试密码认证"]
		], T.error_hex)
		main.append_output(box + "\n", true)
		return

	main.current_path = new_path
	main._update_status_bar()
	main.append_output("已切换到: " + main.current_path + "\n", false)

func _cmd_back(_args: Array = []) -> void:
	if main.current_path == "/":
		main.append_output("[color=" + T.muted_hex + "]已在根目录。[/color]\n", false)
		return

	var parent_path: String = fs.get_parent_path(main.current_path)
	main.current_path = parent_path
	main._update_status_bar()
	main.append_output("已返回: " + main.current_path + "\n", false)

func _cmd_open(args: Array = []) -> void:
	if args.is_empty():
		main.append_output("[color=" + T.error_hex + "][ERROR] 用法: open <文件名>[/color]\n", false)
		return

	var filename: String = str(args[0])
	var file_path: String

	if filename.begins_with("/"):
		file_path = filename
	else:
		file_path = fs.join_path(main.current_path, filename)

	file_path = fs.normalize_path(file_path)

	var node = fs.get_node_at_path(file_path)
	if node == null:
		main.append_output("[color=" + T.error_hex + "][ERROR] 文件不存在: " + filename + "[/color]\n", false)
		return
	if node.type != "file":
		main.append_output("[color=" + T.error_hex + "][ERROR] " + filename + " 是一个目录，请使用 cd 命令进入。[/color]\n", false)
		return

	# 权限检查
	var required: int = fs.get_required_clearance(file_path)
	if not fs.has_clearance(file_path):
		var box: String = fs.build_box_sectioned([
			["ACCESS DENIED", "权限不足"],
			["需要等级: " + str(required) + "  当前等级: " + str(fs.player_clearance)],
			["输入 unlock 尝试密码认证"]
		], T.error_hex)
		main.append_output(box + "\n", true)
		return

	# 文件密码检查
	var fp_key: String = fs.get_file_password_key(file_path)
	if not fp_key.is_empty() and not fs.is_file_password_unlocked(file_path):
		var fp_info: Dictionary = fs.story_file_passwords[fp_key]
		var hint_text: String = str(fp_info.get("hint", ""))
		var box_lines: Array = [["FILE PASSWORD REQUIRED", "此文件需要输入密码"]]
		if not hint_text.is_empty():
			box_lines.append(["提示: " + hint_text])
		box_lines.append(["请输入密码:", "(输入 cancel 取消)"])
		var box: String = fs.build_box_sectioned(box_lines, T.warning_hex)
		main.append_output(box + "\n", false)
		main._file_password_mode = true
		main._file_password_target = file_path
		main._file_password_filename = filename
		# 进入文件密码模式，placeholder 由焦点事件管理
		if main.input_field.has_focus():
			main.input_field.placeholder_text = ""
		return

	# 等待打字机完成当前任务
	while tw.is_typing:
		await main.get_tree().process_frame

	# 进度条
	var content_size: int = node.content.length()
	await tw.show_progress_bar(content_size)
	await main.get_tree().create_timer(0.5).timeout

	# 清屏显示文件内容
	main.output_text.text = ""
	tw.clear_queue()

	var header: String = "[color=" + T.primary_hex + "]══════════ " + filename + " ══════════[/color]"
	main.output_text.append_text(header + "\n\n")

	# 记录已读文件
	if not main.read_files.has(file_path):
		main.read_files.append(file_path)
		main.save_mgr.auto_save(main.story_id, fs.player_clearance, main.read_files,
			main.unlocked_passwords, fs.unlocked_file_passwords, main.current_path)

	# 获取并处理文件内容
	var clean_content: String = node.content.strip_edges()
	clean_content = clean_content.replace("\r\n", "\n").replace("\r", "\n")

	# 使用 CRTML 解析器处理特殊标记
	if crtml != null:
		clean_content = crtml.parse(clean_content)

	# 使用打字机效果显示文件内容
	main.append_output(clean_content + "\n", true)

	# 等待打字机完成后显示结束标记
	while tw.is_typing:
		await main.get_tree().process_frame

	main.append_output("\n[color=" + T.primary_hex + "]══════════ 文件结束 ══════════[/color]\n", false)
	main.append_output("[color=" + T.muted_hex + "]输入任意命令返回终端。[/color]\n", false)

func _cmd_status(_args: Array = []) -> void:
	var p: String = T.primary_hex
	var w: String = T.warning_hex
	var m: String = T.muted_hex

	var lines: Array[String] = []
	lines.append("[color=" + p + "]═══════════ 用户状态 ═══════════[/color]")
	lines.append("  用户名:     [color=" + p + "]" + user_mgr.get_display_name() + "[/color]")
	lines.append("  权限等级:   [color=" + w + "]" + str(fs.player_clearance) + "[/color]")
	lines.append("  当前路径:   [color=" + p + "]" + main.current_path + "[/color]")
	lines.append("  已读文件:   [color=" + p + "]" + str(main.read_files.size()) + "[/color]")
	lines.append("  已获取密码: [color=" + p + "]" + str(main.unlocked_passwords.size()) + "[/color]")
	lines.append("  已解锁文件: [color=" + p + "]" + str(fs.unlocked_file_passwords.size()) + "[/color]")
	if not main.story_id.is_empty():
		lines.append("  磁盘ID:     [color=" + m + "]" + main.story_id + "[/color]")
	lines.append("[color=" + p + "]════════════════════════════════[/color]")
	main.append_output("\n".join(lines) + "\n", true)

func _cmd_whoami(_args: Array = []) -> void:
	main.append_output(user_mgr.get_whoami_text() + "\n", false)

func _cmd_mail(_args: Array = []) -> void:
	main.append_output("[color=" + T.muted_hex + "]收件箱为空。\n(邮件系统将在后续版本中实现)[/color]\n", false)

func _cmd_scan(_args: Array = []) -> void:
	main.append_output("[color=" + T.muted_hex + "]正在扫描 vdisc/ 目录...[/color]\n", true)
	while tw.is_typing:
		await main.get_tree().process_frame
	await tw.show_progress_bar(400)
	await main.get_tree().create_timer(0.3).timeout
	disc_mgr.scan_stories(false)  # 非静默，显示扫描结果
	main._update_status_bar()

func _cmd_load(args: Array = []) -> void:
	await disc_mgr.load_story(args)

func _cmd_eject(_args: Array = []) -> void:
	await disc_mgr.eject_story()

func _cmd_vdisc(_args: Array = []) -> void:
	disc_mgr.show_story_info()

func _cmd_unlock(args: Array = []) -> void:
	if args.is_empty():
		# 进入密码输入模式
		var box: String = fs.build_box_sectioned([
			["SECURITY AUTHENTICATION", "安全认证系统"],
			["请输入访问密码:", "(输入 cancel 取消)"]
		], T.warning_hex)
		main.append_output(box + "\n", false)
		main._password_mode = true
		# 进入密码模式，placeholder 由焦点事件管理
		if main.input_field.has_focus():
			main.input_field.placeholder_text = ""
		return

	# 有参数时直接验证密码
	var password: String = str(args[0])
	_verify_password(password)

## 验证密码（供 unlock 命令和密码输入模式共用）
func _verify_password(password: String) -> void:
	if not disc_mgr.story_manifest.has("passwords"):
		main.append_output("[color=" + T.error_hex + "][ERROR] 当前剧本未配置密码系统。[/color]\n", false)
		return

	var passwords: Dictionary = disc_mgr.story_manifest["passwords"]

	if passwords.has(password):
		var pwd_info: Dictionary = passwords[password]
		var grant_level: int = int(float(pwd_info.get("grants_clearance", 0)))

		if main.unlocked_passwords.has(password):
			main.append_output("[color=" + T.muted_hex + "]该密码已使用过。当前权限等级: " + str(fs.player_clearance) + "[/color]\n", false)
			return

		if grant_level <= fs.player_clearance:
			main.append_output("[color=" + T.muted_hex + "]该密码对应的权限等级不高于当前等级。当前: " + str(fs.player_clearance) + "[/color]\n", false)
			return

		main.unlocked_passwords.append(password)
		var old_level: int = fs.player_clearance
		fs.player_clearance = grant_level

		main.save_mgr.auto_save(main.story_id, fs.player_clearance, main.read_files,
			main.unlocked_passwords, fs.unlocked_file_passwords, main.current_path)

		var box: String = fs.build_box_sectioned([
			["ACCESS GRANTED", "权限认证通过"],
			["权限等级: " + str(old_level) + " -> " + str(fs.player_clearance)]
		], T.success_hex)
		main.append_output(box + "\n", true)

		if pwd_info.has("message"):
			main.append_output("[color=" + T.muted_hex + "]" + str(pwd_info["message"]) + "[/color]\n", false)

		main._update_status_bar()
	else:
		var box: String = fs.build_box(["ACCESS DENIED", "密码验证失败"] as Array[String], T.error_hex)
		main.append_output(box + "\n", false)

## 验证文件密码（供 main.gd 的文件密码模式调用）
func verify_file_password(input_password: String) -> void:
	var fp_key: String = fs.get_file_password_key(main._file_password_target)
	if fp_key.is_empty():
		main.append_output("[color=" + T.error_hex + "][ERROR] 内部错误：未找到文件密码配置。[/color]\n", false)
		return

	var fp_info: Dictionary = fs.story_file_passwords[fp_key]
	var correct_password: String = str(fp_info.get("password", ""))

	if input_password == correct_password:
		fs.unlocked_file_passwords.append(main._file_password_target)
		main.save_mgr.auto_save(main.story_id, fs.player_clearance, main.read_files,
			main.unlocked_passwords, fs.unlocked_file_passwords, main.current_path)

		var box: String = fs.build_box(["PASSWORD ACCEPTED", "文件密码验证通过"] as Array[String], T.success_hex)
		main.append_output(box + "\n", false)

		while tw.is_typing:
			await main.get_tree().process_frame
		await main.get_tree().create_timer(0.5).timeout

		# 密码验证通过后自动打开文件
		await _cmd_open([main._file_password_filename])
	else:
		var box: String = fs.build_box(["PASSWORD REJECTED", "文件密码错误"] as Array[String], T.error_hex)
		main.append_output(box + "\n", false)

func _cmd_save(_args: Array = []) -> void:
	main.save_mgr.auto_save(main.story_id, fs.player_clearance, main.read_files,
		main.unlocked_passwords, fs.unlocked_file_passwords, main.current_path)
	main.append_output("[color=" + T.success_hex + "]进度已保存。[/color]\n", false)

func _cmd_clearsave(args: Array = []) -> void:
	if args.size() > 0 and str(args[0]).to_lower() == "all":
		var count: int = main.save_mgr.delete_all_saves()
		main.append_output("[color=" + T.primary_hex + "]已清除全部存档（共 " + str(count) + " 个）。[/color]\n", true)
	elif main.story_id != "":
		var success: bool = main.save_mgr.delete_save(main.story_id)
		if success:
			main.append_output("[color=" + T.primary_hex + "]已清除当前磁盘存档。[/color]\n", true)
			main.read_files.clear()
			main.unlocked_passwords.clear()
			fs.unlocked_file_passwords.clear()
		else:
			main.append_output("[color=" + T.error_hex + "]清除存档失败或存档不存在。[/color]\n", false)
	else:
		main.append_output("[color=" + T.muted_hex + "]用法:\n  clearsave      清除当前磁盘存档\n  clearsave all  清除全部存档[/color]\n", false)

func _cmd_theme(args: Array = []) -> void:
	if args.is_empty():
		ThemeManager.show_themes(main)
	else:
		ThemeManager.request_theme_change(str(args[0]), main)
