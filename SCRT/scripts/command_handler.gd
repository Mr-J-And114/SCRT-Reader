# ============================================================
# command_handler.gd - 命令解析与执行
# ============================================================
class_name CommandHandler
extends RefCounted

# ══════════════════════════════════════════
#  模块引用
# ══════════════════════════════════════════
var main = null
var fs: FileSystem = null
var T = null
var tw = null
var disc_mgr = null
var user_mgr = null
var crtml = null

# ══════════════════════════════════════════
#  命令历史
# ══════════════════════════════════════════
var command_history: Array[String] = []
var history_index: int = -1
const MAX_HISTORY: int = 50

# ══════════════════════════════════════════
#  命令注册表
# ══════════════════════════════════════════
var desktop_commands: Dictionary = {}
var disc_commands: Dictionary = {}
var global_commands: Dictionary = {}

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(p_main, p_fs, p_theme, p_tw, p_disc_mgr, p_user_mgr, p_crtml) -> void:
	main = p_main
	fs = p_fs
	T = p_theme
	tw = p_tw
	disc_mgr = p_disc_mgr
	user_mgr = p_user_mgr
	crtml = p_crtml
	_register_commands()

func _register_commands() -> void:
	# ── 全局命令（桌面+磁盘都可用）──
	global_commands = {
		"help": _cmd_help,
		"clear": _cmd_clear,
		"cls": _cmd_clear,
		"whoami": _cmd_whoami,
		"status": _cmd_status,
		"mail": _cmd_mail,
		"theme": _cmd_theme,
		"volume": _cmd_volume,
		"vol": _cmd_volume,
		"reboot": _cmd_reboot,
		"exit": _cmd_exit,
		"quit": _cmd_exit,
		"profile": _cmd_profile,
		"logout": _cmd_logout,
		"passwd": _cmd_passwd,
		"birthday": _cmd_birthday,
		"users": _cmd_users,
	}

	# ── 桌面模式专用命令 ──
	desktop_commands = {
		"scan": _cmd_scan,
		"load": _cmd_load,
		"vdisc": _cmd_vdisc,
		"deluser": _cmd_deluser,
	}

	# ── 磁盘模式专用命令 ──
	disc_commands = {
		"ls": _cmd_ls,
		"dir": _cmd_ls,
		"cd": _cmd_cd,
		"back": _cmd_back,
		"open": _cmd_open,
		"read": _cmd_open,
		"cat": _cmd_open,
		"unlock": _cmd_unlock,
		"eject": _cmd_eject,
		"save": _cmd_save,
		"clearsave": _cmd_clearsave,
	}

# ══════════════════════════════════════════
#  命令执行入口
# ══════════════════════════════════════════
func execute(raw: String) -> void:
	var parts: PackedStringArray = raw.strip_edges().split(" ", false)
	if parts.is_empty():
		return

	var cmd: String = parts[0].to_lower()
	var args: Array = []
	for i in range(1, parts.size()):
		args.append(parts[i])

	# 记录历史
	_add_to_history(raw)

	# 查找并执行命令
	var handler = _find_handler(cmd)
	if handler != null:
		await handler.call(args)
	else:
		_cmd_unknown(cmd)

func _find_handler(cmd: String):
	# 全局命令优先
	if global_commands.has(cmd):
		return global_commands[cmd]

	# 根据当前模式查找
	if main._desktop_mode:
		if desktop_commands.has(cmd):
			return desktop_commands[cmd]
	else:
		if disc_commands.has(cmd):
			return disc_commands[cmd]

	return null

func _cmd_unknown(cmd: String) -> void:
	main.append_output("[color=" + T.error_hex + "]未知命令: " + cmd + "[/color]\n", false)
	main.append_output("[color=" + T.muted_hex + "]输入 help 查看可用命令列表。[/color]\n", false)

# ══════════════════════════════════════════
#  命令历史
# ══════════════════════════════════════════
func _add_to_history(cmd: String) -> void:
	if cmd.strip_edges().is_empty():
		return
	if command_history.size() > 0 and command_history[-1] == cmd:
		return
	command_history.append(cmd)
	if command_history.size() > MAX_HISTORY:
		command_history.remove_at(0)
	history_index = command_history.size()

func history_up() -> String:
	if command_history.is_empty():
		return ""
	if history_index > 0:
		history_index -= 1
	return command_history[history_index]

func history_down() -> String:
	if command_history.is_empty():
		return ""
	if history_index < command_history.size() - 1:
		history_index += 1
		return command_history[history_index]
	else:
		history_index = command_history.size()
		return ""

# ══════════════════════════════════════════
#  工具函数：判断文件是否为音频描述文件
# ══════════════════════════════════════════
func _is_audio_desc_file(item_name: String, dir_path: String) -> bool:
	if item_name.get_extension().to_lower() != "txt":
		return false
	var base_name: String = item_name.get_basename()
	var audio_exts: Array[String] = ["mp3", "ogg", "wav"]
	for aext in audio_exts:
		var audio_name: String = base_name + "." + aext
		var audio_path: String = fs.join_path(dir_path, audio_name)
		if fs.get_node_at_path(audio_path) != null:
			return true
	return false

## 判断文件是否为图片描述文件（与音频描述文件同理）
func _is_image_desc_file(item_name: String, dir_path: String) -> bool:
	if item_name.get_extension().to_lower() != "txt":
		return false
	var base_name: String = item_name.get_basename()
	var image_exts: Array[String] = ["png", "jpg", "jpeg", "bmp", "webp", "tga"]
	for iext in image_exts:
		var image_name: String = base_name + "." + iext
		var image_path: String = fs.join_path(dir_path, image_name)
		if fs.get_node_at_path(image_path) != null:
			return true
	return false

## ★ 统一判断：文件是否为任意媒体类型的描述文件
func _is_media_desc_file(item_name: String, dir_path: String) -> bool:
	return _is_audio_desc_file(item_name, dir_path) or _is_image_desc_file(item_name, dir_path)

# ══════════════════════════════════════════
#  Tab 自动补全
# ══════════════════════════════════════════
func get_completions(current_text: String) -> Array[String]:
	var parts: PackedStringArray = current_text.split(" ", false)
	if parts.is_empty():
		return [] as Array[String]

	var results: Array[String] = []

	if parts.size() == 1:
		# 补全命令名
		var prefix: String = parts[0].to_lower()
		var all_cmds: Array[String] = []
		for k in global_commands.keys():
			all_cmds.append(k)
		if main._desktop_mode:
			for k in desktop_commands.keys():
				all_cmds.append(k)
		else:
			for k in disc_commands.keys():
				all_cmds.append(k)
		for cmd_name in all_cmds:
			if cmd_name.begins_with(prefix) and cmd_name != prefix:
				results.append(cmd_name)

	elif parts.size() == 2:
		# 补全参数
		var cmd: String = parts[0].to_lower()
		var arg_prefix: String = parts[1]

		if cmd in ["cd", "open", "read", "cat"]:
			var items: Array[String] = fs.get_children_at_path(main.current_path)
			for item in items:
				# ★ 过滤隐藏目录和所有媒体描述文件（音频+图片）
				var item_path: String = fs.join_path(main.current_path, item)
				if fs.is_hidden_path(item_path):
					continue
				if _is_media_desc_file(item, main.current_path):
					continue
				if item.to_lower().begins_with(arg_prefix.to_lower()):
					results.append(cmd + " " + item)
		elif cmd == "load":
			for i in range(disc_mgr.available_stories.size()):
				var idx_str: String = str(i + 1)
				if idx_str.begins_with(arg_prefix):
					results.append(cmd + " " + idx_str)
		elif cmd == "theme":
			var themes: Array[String] = ThemeManager.get_available_themes()
			for t_name in themes:
				if t_name.begins_with(arg_prefix.to_lower()):
					results.append(cmd + " " + t_name)
		elif cmd == "volume" or cmd == "vol":
			var channels: Array[String] = ["master", "ambient", "sfx", "media"]
			for ch in channels:
				if ch.begins_with(arg_prefix.to_lower()):
					results.append(cmd + " " + ch)
		elif cmd == "profile":
			for page in ["1", "2"]:
				if page.begins_with(arg_prefix):
					results.append(cmd + " " + page)
		elif cmd == "deluser":
			var all_users: Array[String] = user_mgr.get_all_users()
			for u in all_users:
				if u.to_lower().begins_with(arg_prefix.to_lower()):
					results.append(cmd + " " + u)

	return results

# ══════════════════════════════════════════════════════════════
#  全局命令
# ══════════════════════════════════════════════════════════════
func _cmd_help(_args: Array = []) -> void:
	var p: String = T.primary_hex
	var m: String = T.muted_hex

	var lines: Array[String] = []

	if main._desktop_mode:
		lines.append("[color=" + p + "]═══════════════════════════════════════════════[/color]")
		lines.append("[color=" + p + "] SCP TERMINAL — 桌面模式命令列表[/color]")
		lines.append("[color=" + p + "]═══════════════════════════════════════════════[/color]")
		lines.append("")
		lines.append("[color=" + p + "]  ── 磁盘操作 ──[/color]")
		lines.append("  [color=" + p + "]scan[/color]          扫描可用虚拟磁盘")
		lines.append("  [color=" + p + "]load <编号>[/color]   加载指定磁盘")
		lines.append("  [color=" + p + "]vdisc[/color]         查看磁盘信息")
		lines.append("")
		lines.append("[color=" + p + "]  ── 用户管理 ──[/color]")
		lines.append("  [color=" + p + "]profile [1|2][/color] 查看个人档案 (第1/2页)")
		lines.append("  [color=" + p + "]whoami[/color]        显示当前用户信息")
		lines.append("  [color=" + p + "]users[/color]         列出所有用户")
		lines.append("  [color=" + p + "]passwd[/color]        修改密码")
		lines.append("  [color=" + p + "]birthday[/color]      设置出生日期 (YYYY-MM-DD)")
		lines.append("  [color=" + p + "]logout[/color]        注销当前账户")
		lines.append("  [color=" + p + "]deluser <用户名>[/color] 删除指定用户")
		lines.append("")
		lines.append("[color=" + p + "]  ── 系统 ──[/color]")
		lines.append("  [color=" + p + "]status[/color]        查看系统状态")
		lines.append("  [color=" + p + "]mail[/color]          查看邮件")
		lines.append("  [color=" + p + "]theme <名称>[/color]  切换主题配色")
		lines.append("  [color=" + p + "]volume[/color]        查看/设置音量")
		lines.append("  [color=" + p + "]clear[/color]         清屏")
		lines.append("  [color=" + p + "]reboot[/color]        重启终端")
		lines.append("  [color=" + p + "]exit[/color]          退出终端")
		lines.append("[color=" + p + "]═══════════════════════════════════════════════[/color]")
		lines.append("[color=" + m + "]快捷键: ↑↓ 历史命令 | PageUp/Down 滚动 | Tab 补全[/color]")
	else:
		lines.append("[color=" + p + "]═══════════════════════════════════════════════[/color]")
		lines.append("[color=" + p + "] SCP TERMINAL — 磁盘模式命令列表[/color]")
		lines.append("[color=" + p + "]═══════════════════════════════════════════════[/color]")
		lines.append("")
		lines.append("[color=" + p + "]  ── 文件操作 ──[/color]")
		lines.append("  [color=" + p + "]ls[/color]            列出当前目录文件")
		lines.append("  [color=" + p + "]cd <路径>[/color]     切换目录")
		lines.append("  [color=" + p + "]back[/color]          返回上级目录")
		lines.append("  [color=" + p + "]open <文件名>[/color] 打开文件")
		lines.append("  [color=" + p + "]unlock[/color]        尝试密码认证提升权限")
		lines.append("")
		lines.append("[color=" + p + "]  ── 磁盘管理 ──[/color]")
		lines.append("  [color=" + p + "]eject[/color]         弹出当前磁盘")
		lines.append("  [color=" + p + "]save[/color]          手动保存进度")
		lines.append("  [color=" + p + "]clearsave[/color]     清除当前磁盘存档 (all=全部)")
		lines.append("")
		lines.append("[color=" + p + "]  ── 用户信息 ──[/color]")
		lines.append("  [color=" + p + "]profile [1|2][/color] 查看个人档案")
		lines.append("  [color=" + p + "]whoami[/color]        显示当前用户信息")
		lines.append("  [color=" + p + "]passwd[/color]        修改密码")
		lines.append("  [color=" + p + "]logout[/color]        注销当前账户")
		lines.append("")
		lines.append("[color=" + p + "]  ── 系统 ──[/color]")
		lines.append("  [color=" + p + "]status[/color]        查看系统状态")
		lines.append("  [color=" + p + "]mail[/color]          查看邮件")
		lines.append("  [color=" + p + "]theme <名称>[/color]  切换主题配色")
		lines.append("  [color=" + p + "]volume[/color]        查看/设置音量")
		lines.append("  [color=" + p + "]clear[/color]         清屏")
		lines.append("  [color=" + p + "]reboot[/color]        重启终端")
		lines.append("  [color=" + p + "]exit[/color]          退出终端")
		lines.append("[color=" + p + "]═══════════════════════════════════════════════[/color]")
		lines.append("[color=" + m + "]快捷键: ↑↓ 历史命令 | PageUp/Down 滚动 | Tab 补全[/color]")

	main.append_output("\n".join(lines) + "\n", false)

func _cmd_clear(_args: Array = []) -> void:
	main.output_text.text = ""
	tw.clear_queue()

func _cmd_whoami(_args: Array = []) -> void:
	main.append_output(user_mgr.get_whoami_text() + "\n", false)

func _cmd_status(_args: Array = []) -> void:
	var p: String = T.primary_hex
	var w: String = T.warning_hex
	var m: String = T.muted_hex

	var lines: Array[String] = []
	lines.append("[color=" + p + "]═══════════ 系统状态 ═══════════[/color]")
	lines.append("  操作员:     [color=" + p + "]" + user_mgr.get_display_name() + "[/color]")

	if not main._desktop_mode:
		lines.append("  权限等级:   [color=" + w + "]" + str(fs.player_clearance) + "[/color]")
		lines.append("  当前路径:   [color=" + p + "]" + main.current_path + "[/color]")
		lines.append("  已读文件:   [color=" + p + "]" + str(main.read_files.size()) + "[/color]")
		lines.append("  已获取密码: [color=" + p + "]" + str(main.unlocked_passwords.size()) + "[/color]")
		lines.append("  已解锁文件: [color=" + p + "]" + str(fs.unlocked_file_passwords.size()) + "[/color]")
		if not main.story_id.is_empty():
			lines.append("  磁盘ID:     [color=" + m + "]" + main.story_id + "[/color]")
	else:
		lines.append("  模式:       [color=" + p + "]桌面模式[/color]")
		lines.append("  可用磁盘:   [color=" + p + "]" + str(disc_mgr.available_stories.size()) + "[/color]")

	var cmd_count: int = 0
	if user_mgr.current_user is Dictionary:
		cmd_count = int(user_mgr.current_user.get("command_count", 0))
	lines.append("  命令计数:   [color=" + m + "]" + str(cmd_count) + "[/color]")
	lines.append("[color=" + p + "]════════════════════════════════[/color]")

	main.append_output("\n".join(lines) + "\n", false)

func _cmd_mail(_args: Array = []) -> void:
	main.append_output("[color=" + T.muted_hex + "]收件箱为空。\n(邮件系统将在后续版本中实现)[/color]\n", false)

func _cmd_volume(args: Array = []) -> void:
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var s: String = T.success_hex
	var e: String = T.error_hex
	var am = main.audio_manager

	if args.is_empty():
		var lines: Array[String] = []
		lines.append("[color=" + p + "]═══════════ 音量设置 ═══════════[/color]")
		lines.append("")
		lines.append("  [color=" + m + "]主音量:[/color] [color=" + p + "]" + str(snapped(db_to_linear(am.master_volume_db) * 100, 1)) + "%[/color]")
		lines.append("  [color=" + m + "]环境音:[/color] [color=" + p + "]" + str(snapped(db_to_linear(am.ambient_volume_db) * 100, 1)) + "%[/color]")
		lines.append("  [color=" + m + "]音效:[/color]   [color=" + p + "]" + str(snapped(db_to_linear(am.sfx_volume_db) * 100, 1)) + "%[/color]")
		lines.append("  [color=" + m + "]媒体:[/color]   [color=" + p + "]" + str(snapped(db_to_linear(am.media_volume_db) * 100, 1)) + "%[/color]")
		lines.append("")
		lines.append("  [color=" + m + "]环境音状态:[/color]  [color=" + p + "]" + ("播放中" if am.is_ambient_playing() else "无") + "[/color]")
		lines.append("")
		lines.append("[color=" + p + "]════════════════════════════════[/color]")
		lines.append("[color=" + m + "]用法: volume <通道> <数值>[/color]")
		lines.append("[color=" + m + "]通道: master / ambient / sfx / media[/color]")
		lines.append("[color=" + m + "]数值: 0-100 (百分比)[/color]")
		lines.append("[color=" + m + "]示例: volume ambient 50[/color]")
		main.append_output("\n".join(lines) + "\n", false)
		return

	if args.size() < 2:
		main.append_output("[color=" + e + "]用法: volume <通道> <数值>[/color]\n", false)
		main.append_output("[color=" + m + "]通道: master / ambient / sfx / media[/color]\n", false)
		return

	var channel: String = str(args[0]).to_lower()
	var value_str: String = str(args[1])

	if not value_str.is_valid_float():
		main.append_output("[color=" + e + "]请输入有效数值 (0-100)。[/color]\n", false)
		return

	var value: float = clampf(value_str.to_float(), 0.0, 100.0) / 100.0

	match channel:
		"master", "main", "all":
			am.set_master_volume(value)
			main.append_output("[color=" + s + "]主音量已设置为 " + str(snapped(value * 100, 1)) + "%[/color]\n", false)
		"ambient", "amb", "bg":
			am.set_ambient_volume(value)
			main.append_output("[color=" + s + "]环境音音量已设置为 " + str(snapped(value * 100, 1)) + "%[/color]\n", false)
		"sfx", "sound", "fx":
			am.set_sfx_volume(value)
			main.append_output("[color=" + s + "]音效音量已设置为 " + str(snapped(value * 100, 1)) + "%[/color]\n", false)
		"media", "music":
			am.set_media_volume(value)
			main.append_output("[color=" + s + "]媒体音量已设置为 " + str(snapped(value * 100, 1)) + "%[/color]\n", false)
		_:
			main.append_output("[color=" + e + "]未知通道: " + channel + "[/color]\n", false)
			main.append_output("[color=" + m + "]可用通道: master / ambient / sfx / media[/color]\n", false)

func _cmd_theme(args: Array = []) -> void:
	if args.is_empty():
		ThemeManager.show_themes(main)
		return
	var theme_name: String = str(args[0]).to_lower()
	ThemeManager.request_theme_change(theme_name, main)

func _cmd_reboot(_args: Array = []) -> void:
	main.append_output("[color=" + T.muted_hex + "]正在重启终端...[/color]\n", false)
	if user_mgr.is_logged_in:
		user_mgr._save_current_profile()
	await main.get_tree().create_timer(0.5).timeout
	main.output_text.text = ""
	tw.clear_queue()
	command_history.clear()
	history_index = -1
	disc_mgr.reset_all()
	await main.get_tree().create_timer(0.3).timeout
	main._start_login_flow()

func _cmd_exit(_args: Array = []) -> void:
	main.append_output("[color=" + T.muted_hex + "]正在关闭终端...[/color]\n", false)
	if user_mgr.is_logged_in:
		user_mgr.logout()
	await main.get_tree().create_timer(0.5).timeout
	main.get_tree().quit()

# ══════════════════════════════════════════════════════════════
#  用户系统命令
# ══════════════════════════════════════════════════════════════
func _cmd_profile(args: Array = []) -> void:
	if not user_mgr.is_logged_in:
		main.append_output("[color=" + T.error_hex + "]请先登录。[/color]\n", false)
		return

	if main.profile_builder != null and main.doc_viewer != null:
		var page_num: int = 0
		if args.size() > 0:
			var page_str: String = str(args[0])
			if page_str == "1":
				page_num = 1
			elif page_str == "2":
				page_num = 2
		main.profile_builder.open_profile(page_num)
	else:
		var page: int = 1
		if args.size() > 0 and str(args[0]) == "2":
			page = 2
		if page == 1:
			main.append_output(user_mgr.get_profile_page1(), false)
		else:
			main.append_output(user_mgr.get_profile_page2(), false)

func _cmd_logout(_args: Array = []) -> void:
	if not user_mgr.is_logged_in:
		main.append_output("[color=" + T.error_hex + "]当前未登录。[/color]\n", false)
		return
	if not main._desktop_mode:
		disc_mgr._auto_save()
		main._desktop_mode = true
		main.current_path = "/"
		main.story_id = ""
	await main.perform_logout()

func _cmd_passwd(_args: Array = []) -> void:
	if not user_mgr.is_logged_in:
		main.append_output("[color=" + T.error_hex + "]当前未登录。[/color]\n", false)
		return
	main.start_passwd_flow()

func _cmd_birthday(args: Array = []) -> void:
	if not user_mgr.is_logged_in:
		main.append_output("[color=" + T.error_hex + "]当前未登录。[/color]\n", false)
		return
	if args.is_empty():
		var current_birthday: String = str(user_mgr.current_user.get("birthday", ""))
		if current_birthday.is_empty():
			main.append_output("[color=" + T.muted_hex + "]出生日期未设置。[/color]\n", false)
		else:
			main.append_output("[color=" + T.primary_hex + "]出生日期: " + current_birthday + "[/color]\n", false)
		main.append_output("[color=" + T.muted_hex + "]用法: birthday YYYY-MM-DD[/color]\n", false)
		return
	var date_str: String = str(args[0])
	var result: Dictionary = user_mgr.set_birthday(date_str)
	if result["success"]:
		main.append_output("[color=" + T.success_hex + "]" + str(result["message"]) + "[/color]\n", false)
	else:
		main.append_output("[color=" + T.error_hex + "]" + str(result["message"]) + "[/color]\n", false)

func _cmd_users(_args: Array = []) -> void:
	var all_users: Array[String] = user_mgr.get_all_users()
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var s: String = T.success_hex

	if all_users.is_empty():
		main.append_output("[color=" + m + "]无已注册用户。[/color]\n", false)
		return

	var lines: Array[String] = []
	lines.append("[color=" + p + "]═══════════ 已注册操作员 ═══════════[/color]")
	lines.append("")

	for username in all_users:
		var marker: String = ""
		if user_mgr.is_logged_in and user_mgr.get_username() == username:
			marker = " [color=" + s + "]◄ 当前[/color]"
		var profile_path: String = user_mgr._get_profile_path(username)
		var role_str: String = "标准操作员"
		if FileAccess.file_exists(profile_path):
			var file := FileAccess.open(profile_path, FileAccess.READ)
			if file:
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
					var role: String = str(json.data.get("role", "user"))
					match role:
						"admin": role_str = "系统管理员"
						"user": role_str = "标准操作员"
						_: role_str = role
				file.close()
		lines.append("  [color=" + p + "]" + username + "[/color]  [color=" + m + "](" + role_str + ")[/color]" + marker)

	lines.append("")
	lines.append("[color=" + p + "]════════════════════════════════════[/color]")
	lines.append("[color=" + m + "]共 " + str(all_users.size()) + " 个账户[/color]")
	main.append_output("\n".join(lines) + "\n", false)

func _cmd_deluser(args: Array = []) -> void:
	if args.is_empty():
		main.append_output("[color=" + T.error_hex + "]用法: deluser <用户名>[/color]\n", false)
		return
	var target: String = str(args[0])
	if user_mgr.is_logged_in:
		var is_admin: bool = user_mgr.get_role() == "admin"
		var is_self: bool = user_mgr.get_username() == target
		if not is_admin and not is_self:
			main.append_output("[color=" + T.error_hex + "]权限不足。只有管理员可以删除其他用户。[/color]\n", false)
			return
	if target == UserManager.ADMIN_USERNAME:
		main.append_output("[color=" + T.error_hex + "]管理员账户不可删除。[/color]\n", false)
		return
	if not user_mgr.user_exists(target):
		main.append_output("[color=" + T.error_hex + "]用户 \"" + target + "\" 不存在。[/color]\n", false)
		return
	main.start_delete_user_flow(target)

# ══════════════════════════════════════════════════════════════
#  桌面模式命令
# ══════════════════════════════════════════════════════════════
func _cmd_scan(_args: Array = []) -> void:
	await disc_mgr.scan_stories()

func _cmd_load(args: Array = []) -> void:
	await disc_mgr.load_story(args)

func _cmd_vdisc(_args: Array = []) -> void:
	disc_mgr.show_story_info()

# ══════════════════════════════════════════════════════════════
#  磁盘模式命令
# ══════════════════════════════════════════════════════════════
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

		# 跳过隐藏目录
		if fs.is_hidden_path(item_path):
			continue

		# ★ 跳过所有媒体描述文件（音频+图片）
		if _is_media_desc_file(item_str, main.current_path):
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

	# 阻止进入隐藏目录
	if fs.is_hidden_path(new_path):
		main.append_output("[color=" + T.error_hex + "][ERROR] 目录不存在: " + target + "[/color]\n", false)
		return

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
		main.append_output(box + "\n", false)
		return

	main.current_path = new_path
	main._update_status_bar()
	main.append_output("已切换到: " + main.current_path + "\n", false)
	main.update_ambient_sound()

func _cmd_back(_args: Array = []) -> void:
	if main.current_path == "/":
		main.append_output("[color=" + T.muted_hex + "]已在根目录。[/color]\n", false)
		return
	var parent_path: String = fs.get_parent_path(main.current_path)
	main.current_path = parent_path
	main._update_status_bar()
	main.append_output("已返回: " + main.current_path + "\n", false)
	main.update_ambient_sound()

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

	if node.type == "folder":
		main.append_output("[color=" + T.error_hex + "][ERROR] " + filename + " 是一个目录，请使用 cd 命令。[/color]\n", false)
		return

	# 阻止打开隐藏目录中的文件
	if fs.is_hidden_path(file_path):
		main.append_output("[color=" + T.error_hex + "][ERROR] 文件不存在: " + filename + "[/color]\n", false)
		return

	# ★ 阻止直接打开所有媒体描述文件（音频+图片）
	var dir_path: String = fs.get_parent_path(file_path)
	var base_filename: String = file_path.get_file()
	if _is_media_desc_file(base_filename, dir_path):
		main.append_output("[color=" + T.error_hex + "][ERROR] 文件不存在: " + filename + "[/color]\n", false)
		return

	# 权限检查
	var required: int = fs.get_required_clearance(file_path)
	if not fs.has_clearance(file_path):
		var box: String = fs.build_box_sectioned([
			["ACCESS DENIED"],
			["需要等级: " + str(required) + "  当前等级: " + str(fs.player_clearance)]
		], T.error_hex)
		main.append_output(box + "\n", false)
		return

	# 文件密码检查
	var fp_key: String = fs.get_file_password_key(file_path)
	if not fp_key.is_empty() and not fs.is_file_password_unlocked(file_path):
		main.append_output("[color=" + T.warning_hex + "]此文件需要密码才能访问。[/color]\n", false)
		main.append_output("[color=" + T.primary_hex + "]请输入文件密码 (输入 cancel 取消): [/color]", false)
		main._file_password_mode = true
		main._file_password_target = file_path
		main._file_password_filename = filename
		return

	# 检查是否是音频文件
	var ext: String = filename.get_extension().to_lower()
	var audio_extensions: Array[String] = ["ogg", "wav", "mp3"]
	if ext in audio_extensions:
		var audio_data: PackedByteArray = fs.get_binary_data(file_path)
		if audio_data.is_empty():
			main.append_output("[color=" + T.error_hex + "]无法读取音频数据。[/color]\n", false)
			return
		var stream: AudioStream = main.audio_manager.load_audio_from_bytes(file_path, audio_data)
		if stream == null:
			main.append_output("[color=" + T.error_hex + "]无法解析音频文件。[/color]\n", false)
			return
		main.append_output("[color=" + T.muted_hex + "]正在打开音频播放器...[/color]\n", false)
		main.open_oscilloscope_with_file(file_path, filename, stream)
		return

	# 检查是否是图片文件
	var image_extensions: Array[String] = ["png", "jpg", "jpeg", "bmp", "webp", "tga"]
	if ext in image_extensions:
		var image_data: PackedByteArray = fs.get_binary_data(file_path)
		if image_data.is_empty():
			main.append_output("[color=" + T.error_hex + "]无法读取图片数据。[/color]\n", false)
			return
		main.append_output("[color=" + T.muted_hex + "]正在打开图片查看器...[/color]\n", false)
		main.open_image_viewer_with_file(file_path, filename, image_data)
		return

	# 打开文本文件
	await _display_file(file_path, filename, node.content)

func _display_file(file_path: String, filename: String, content: String) -> void:
	var p: String = T.primary_hex
	var m: String = T.muted_hex

	main.append_output("\n[color=" + p + "]══════════ " + filename + " ══════════[/color]\n\n", false)

	# CRT-ML 解析
	var parsed_content: String = content
	if crtml != null:
		parsed_content = crtml.parse(content)

	# 替换 {username} 变量
	if user_mgr.is_logged_in:
		parsed_content = parsed_content.replace("{username}", user_mgr.get_username())

	main.append_output(parsed_content + "\n", true)

	# 记录已读
	if not main.read_files.has(file_path):
		main.read_files.append(file_path)

	# 统计文件阅读数
	if user_mgr.is_logged_in:
		user_mgr.increment_files_read()

	# 自动保存
	disc_mgr._auto_save()

	# 等待打字机完成
	while tw.is_typing:
		await main.get_tree().process_frame

	main.append_output("\n[color=" + p + "]══════════ 文件结束 ══════════[/color]\n", false)
	main.append_output("[color=" + m + "]输入任意命令返回终端。[/color]\n", false)

func _cmd_unlock(args: Array = []) -> void:
	if args.is_empty():
		main.append_output("[color=" + T.primary_hex + "]请输入认证密码 (输入 cancel 取消): [/color]", false)
		main._password_mode = true
		main._password_target_path = main.current_path
		return
	_verify_password(str(args[0]))

func _verify_password(password: String) -> void:
	var passwords: Dictionary = {}
	var story_dict: Dictionary = main.story_manifest.get("story", {}) as Dictionary
	if story_dict.has("passwords"):
		passwords = story_dict.get("passwords", {}) as Dictionary
	elif main.story_manifest.has("passwords"):
		passwords = main.story_manifest.get("passwords", {}) as Dictionary

	for level_str in passwords.keys():
		var pwd_value: String = str(passwords[level_str])
		if password == pwd_value:
			var level: int = int(float(level_str))
			if fs.player_clearance < level:
				fs.player_clearance = level
				if not main.unlocked_passwords.has(password):
					main.unlocked_passwords.append(password)
				var box: String = fs.build_box(
					["ACCESS GRANTED", "权限等级已提升至: " + str(level)] as Array[String],
					T.success_hex
				)
				main.append_output(box + "\n", false)
				disc_mgr._auto_save()
				main._update_status_bar()
				return
			else:
				main.append_output("[color=" + T.warning_hex + "]当前等级已达到或超过该密码对应的等级。[/color]\n", false)
				return

	main.append_output("[color=" + T.error_hex + "]密码无效。[/color]\n", false)

func verify_file_password(password: String) -> void:
	var file_path: String = main._file_password_target
	var filename: String = main._file_password_filename

	if file_path.is_empty():
		return

	var fp_key: String = fs.get_file_password_key(file_path)
	if fp_key.is_empty():
		main._file_password_target = ""
		main._file_password_filename = ""
		return

	var expected_password: String = str(fs.story_file_passwords.get(fp_key, {}).get("password", ""))
	if password == expected_password:
		fs.unlocked_file_passwords.append(file_path)
		main.append_output("[color=" + T.success_hex + "]文件密码正确，已解锁。[/color]\n", false)
		disc_mgr._auto_save()
		var node = fs.get_node_at_path(file_path)
		if node:
			await _display_file(file_path, filename, node.content)
	else:
		main.append_output("[color=" + T.error_hex + "]文件密码错误。[/color]\n", false)

	main._file_password_target = ""
	main._file_password_filename = ""

func _cmd_eject(_args: Array = []) -> void:
	await disc_mgr.eject_story()

func _cmd_save(_args: Array = []) -> void:
	if main.story_id.is_empty():
		main.append_output("[color=" + T.error_hex + "]当前未加载磁盘。[/color]\n", false)
		return
	disc_mgr._auto_save()
	main.append_output("[color=" + T.success_hex + "]进度已保存。[/color]\n", false)

func _cmd_clearsave(args: Array = []) -> void:
	var m: String = T.muted_hex
	var e: String = T.error_hex
	if args.size() > 0 and str(args[0]).to_lower() == "all":
		var count: int = main.save_mgr.delete_all_saves()
		main.append_output("[color=" + e + "]已清除 " + str(count) + " 个存档。[/color]\n", false)
		return
	if main.story_id.is_empty():
		main.append_output("[color=" + e + "]当前未加载磁盘。[/color]\n", false)
		main.append_output("[color=" + m + "]用法: clearsave [all][/color]\n", false)
		return
	main.save_mgr.delete_save(main.story_id)
	main.append_output("[color=" + e + "]当前磁盘存档已清除。[/color]\n", false)
