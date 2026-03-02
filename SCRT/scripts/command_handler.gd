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
		"decode": _cmd_decode,
		"fx_level": _cmd_fx_level,
		"fx_safe": _cmd_fx_safe,
		"sound": _cmd_sound,
		"packages": _cmd_packages,
		"pkg": _cmd_packages,
		"uninstall": _cmd_uninstall,
		"comm": _cmd_comm,		   # ★ 通讯系统
		"dial": _cmd_dial,		   # ★ 拨号命令
		"phonebook": _cmd_phonebook, # ★ 号码簿（独立命令）
		"pb": _cmd_phonebook,		# ★ 号码簿（简写）
		"settings": _cmd_settings,   # ★ 设置系统
		"set": _cmd_settings,        # ★ 设置系统（简写）
	}

	# ── 桌面模式专用命令 ──
	desktop_commands = {
		"scan": _cmd_scan,
		"load": _cmd_load,
		"vdisc": _cmd_vdisc,
		"deluser": _cmd_deluser,
		"explore": _cmd_explore,
		"install": _cmd_install,
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
		"radio": _cmd_radio,
		"decode": _cmd_decode,
		"explore": _cmd_explore,
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

	# ★ 触发 on_command
	if main.trigger_sys:
		main.trigger_sys.on_command(cmd)

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


## ★ 判断文件是否为视频描述文件
func _is_video_desc_file(item_name: String, dir_path: String) -> bool:
	if item_name.get_extension().to_lower() != "txt":
		return false
	var base_name: String = item_name.get_basename()
	var video_exts: Array[String] = ["ogv", "webm"]
	for vext in video_exts:
		var video_name: String = base_name + "." + vext
		var video_path: String = fs.join_path(dir_path, video_name)
		if fs.get_node_at_path(video_path) != null:
			return true
	return false


## ★ 统一判断：文件是否为任意媒体类型的描述文件
func _is_media_desc_file(item_name: String, dir_path: String) -> bool:
	return _is_audio_desc_file(item_name, dir_path) or _is_image_desc_file(item_name, dir_path) or _is_video_desc_file(item_name, dir_path)


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
				if item == ".meta.cfg" or item.ends_with(".meta.cfg"):
					continue
				if item.to_lower().begins_with(arg_prefix.to_lower()):
					results.append(cmd + " " + item)
		elif cmd == "load":
			for i in range(disc_mgr.available_stories.size()):
				var idx_str: String = str(i + 1)
				if idx_str.begins_with(arg_prefix):
					results.append(cmd + " " + idx_str)
		elif cmd == "install":
			for i in range(disc_mgr.available_stories.size()):
				var idx_str: String = str(i + 1)
				if idx_str.begins_with(arg_prefix):
					results.append(cmd + " " + idx_str)
		elif cmd == "uninstall":
			if main.pkg_mgr:
				for pkg_id in main.pkg_mgr.installed_mods.keys():
					if str(pkg_id).to_lower().begins_with(arg_prefix.to_lower()):
						results.append(cmd + " " + pkg_id)
		elif cmd == "comm":
			# comm 只补全子命令
			var comm_options: Array[String] = ["answer", "phonebook", "pb"]
			for opt in comm_options:
				if opt.to_lower().begins_with(arg_prefix.to_lower()):
					results.append(cmd + " " + opt)
		elif cmd == "dial":
			# dial 补全号码簿中的号码
			if main.dial_mgr:
				var all_numbers: Array[String] = main.dial_mgr.get_all_numbers()
				for num in all_numbers:
					if num.begins_with(arg_prefix):
						results.append(cmd + " " + num)



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
		elif cmd == "fx_level":
			var fx_options: Array[String] = ["full", "mild", "off"]
			for opt in fx_options:
				if opt.begins_with(arg_prefix.to_lower()):
					results.append(cmd + " " + opt)
		elif cmd == "fx_safe":
			var safe_options: Array[String] = ["on", "off"]
			for opt in safe_options:
				if opt.begins_with(arg_prefix.to_lower()):
					results.append(cmd + " " + opt)

		elif cmd == "settings" or cmd == "set":
			# 补全设置键名和子命令
			if main.settings_mgr and main.settings_mgr.has_method("get_all_keys"):
				var all_keys: Array[String] = main.settings_mgr.get_all_keys()
				for skey in all_keys:
					if skey.to_lower().begins_with(arg_prefix.to_lower()):
						results.append(cmd + " " + skey)
			# 也补全 "list" 和 "reset" 子命令
			for sub_cmd in ["list", "reset"]:
				if sub_cmd.begins_with(arg_prefix.to_lower()):
					results.append(cmd + " " + sub_cmd)


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
		lines.append("  [color=" + p + "]explore[/color]       查看探索进度")
		lines.append("")
		lines.append("[color=" + p + "]  ── 软件包管理 ──[/color]")
		lines.append("  [color=" + p + "]install <编号>[/color] 安装内部软件包")
		lines.append("  [color=" + p + "]uninstall <名称>[/color] 卸载已安装的软件包")
		lines.append("  [color=" + p + "]packages[/color]	  查看已安装的软件包")
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
		lines.append("  [color=" + p + "]comm[/color]		  通讯系统状态 / 接听来电")
		lines.append("  [color=" + p + "]dial <号码>[/color]	拨号呼叫")
		lines.append("  [color=" + p + "]phonebook[/color]	  查看号码簿")
		lines.append("  [color=" + p + "]theme <名称>[/color]  切换主题配色")
		lines.append("  [color=" + p + "]settings[/color]      查看/修改终端设置")
		lines.append("  [color=" + p + "]volume[/color]        查看/设置音量")
		lines.append("  [color=" + p + "]clear[/color]         清屏")
		lines.append("  [color=" + p + "]reboot[/color]        重启终端")
		lines.append("  [color=" + p + "]exit[/color]          退出终端")
		lines.append("")
		lines.append("[color=" + p + "]  ── 效果设置 ──[/color]")
		lines.append("  [color=" + p + "]fx_level[/color]	  设置效果强度 (full/mild/off)")
		lines.append("  [color=" + p + "]fx_safe[/color]	   光敏安全模式 (on/off)")
		lines.append("[color=" + p + "]═══════════════════════════════════════════════[/color]")
		# ★ 显示已安装软件包提供的动态命令
		if main.pkg_mgr and not main.pkg_mgr.mod_commands.is_empty():
			lines.append("")
			lines.append("[color=" + p + "]  ── 软件包命令 ──[/color]")
			var shown_pkgs: Dictionary = {}
			for dyn_cmd_name in main.pkg_mgr.mod_commands.keys():
				var dyn_info: Dictionary = main.pkg_mgr.mod_commands[dyn_cmd_name]
				var dyn_desc: String = str(dyn_info.get("description", ""))
				var dyn_mod_id: String = str(dyn_info.get("mod_id", ""))
				var dyn_pkg_title: String = dyn_mod_id
				if main.pkg_mgr.installed_mods.has(dyn_mod_id):
					dyn_pkg_title = str(main.pkg_mgr.installed_mods[dyn_mod_id].get("title", dyn_mod_id))
				if not shown_pkgs.has(dyn_pkg_title):
					shown_pkgs[dyn_pkg_title] = true
					lines.append("  [color=" + m + "][ " + dyn_pkg_title + " ][/color]")
				lines.append("  [color=" + p + "]" + dyn_cmd_name + "[/color]" + "  ".repeat(maxi(1, 12 - dyn_cmd_name.length())) + "[color=" + m + "]" + dyn_desc + "[/color]")
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
		lines.append("  [color=" + p + "]radio[/color]         打开无线电接收器")
		lines.append("  [color=" + p + "]decode[/color]       [color=" + m + "]密码解码器[/color]")
		lines.append("")
		lines.append("[color=" + p + "]  ── 软件包 ──[/color]")
		lines.append("  [color=" + p + "]packages[/color]	  查看已安装的软件包")
		lines.append("  [color=" + p + "]uninstall <名称>[/color] 卸载已安装的软件包")
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
		lines.append("  [color=" + p + "]mail[/color]		  查看邮件")
		lines.append("  [color=" + p + "]comm[/color]		  通讯系统状态 / 接听来电")
		lines.append("  [color=" + p + "]dial <号码>[/color]	拨号呼叫")
		lines.append("  [color=" + p + "]phonebook[/color]	  查看号码簿")
		lines.append("  [color=" + p + "]theme <名称>[/color]  切换主题配色")
		lines.append("  [color=" + p + "]settings[/color]      查看/修改终端设置")
		lines.append("  [color=" + p + "]volume[/color]        查看/设置音量")
		lines.append("  [color=" + p + "]clear[/color]         清屏")
		lines.append("  [color=" + p + "]reboot[/color]        重启终端")
		lines.append("  [color=" + p + "]exit[/color]          退出终端")
		lines.append("")
		lines.append("[color=" + p + "]  ── 效果设置 ──[/color]")
		lines.append("  [color=" + p + "]fx_level[/color]	  设置效果强度 (full/mild/off)")
		lines.append("  [color=" + p + "]fx_safe[/color]	   光敏安全模式 (on/off)")
		lines.append("[color=" + p + "]═══════════════════════════════════════════════[/color]")
		# ★ 显示已安装软件包提供的动态命令
		if main.pkg_mgr and not main.pkg_mgr.mod_commands.is_empty():
			lines.append("")
			lines.append("[color=" + p + "]  ── 软件包命令 ──[/color]")
			var shown_pkgs: Dictionary = {}
			for dyn_cmd_name in main.pkg_mgr.mod_commands.keys():
				var dyn_info: Dictionary = main.pkg_mgr.mod_commands[dyn_cmd_name]
				var dyn_desc: String = str(dyn_info.get("description", ""))
				var dyn_mod_id: String = str(dyn_info.get("mod_id", ""))
				var dyn_pkg_title: String = dyn_mod_id
				if main.pkg_mgr.installed_mods.has(dyn_mod_id):
					dyn_pkg_title = str(main.pkg_mgr.installed_mods[dyn_mod_id].get("title", dyn_mod_id))
				if not shown_pkgs.has(dyn_pkg_title):
					shown_pkgs[dyn_pkg_title] = true
					lines.append("  [color=" + m + "][ " + dyn_pkg_title + " ][/color]")
				lines.append("  [color=" + p + "]" + dyn_cmd_name + "[/color]" + "  ".repeat(maxi(1, 12 - dyn_cmd_name.length())) + "[color=" + m + "]" + dyn_desc + "[/color]")
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


func _cmd_settings(args: Array = []) -> void:
	if main.settings_mgr == null:
		main.append_output("[color=" + T.error_hex + "]设置系统未初始化。[/color]\n", false)
		return
	main.settings_mgr.handle_command(args)


func _cmd_phonebook(_args: Array = []) -> void:
	if main.dial_mgr:
		var text: String = main.dial_mgr.get_phonebook_text()
		main.append_output(text, false)
	else:
		main.append_output("[color=" + T.muted_hex + "]拨号系统未初始化。[/color]\n", false)


func _cmd_dial(args: Array = []) -> void:
	if main.dial_mgr == null:
		main.append_output("[color=" + T.error_hex + "]拨号系统未初始化。[/color]\n", false)
		return
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var e: String = T.error_hex
	if args.is_empty():
		main.append_output("[color=" + e + "]用法: dial <号码>[/color]\n", false)
		main.append_output("[color=" + m + "]示例: dial 1001-0001[/color]\n", false)
		main.append_output("[color=" + m + "]输入 phonebook 查看已知号码。[/color]\n", false)
		return
	var number: String = str(args[0]).strip_edges()
	# 检查通讯系统是否忙
	if main.comm_mgr and main.comm_mgr.is_active:
		main.append_output("[color=" + m + "]通讯频道正在使用中，请稍后再试。[/color]\n", false)
		return
	if main.dial_mgr.is_active():
		main.append_output("[color=" + m + "]线路忙，请稍后再试。[/color]\n", false)
		return
	# 验证号码格式
	if not main.dial_mgr.is_number_format(number):
		main.append_output("[color=" + e + "]无效的号码格式: " + number + "[/color]\n", false)
		main.append_output("[color=" + m + "]号码格式: 数字和连字符组成 (如 1001-0001)[/color]\n", false)
		return
	main.dial_mgr.dial(number)

func _cmd_comm(args: Array = []) -> void:
	if main.comm_mgr == null:
		main.append_output("[color=" + T.error_hex + "]通讯系统未初始化。[/color]\n", false)
		return
	main.comm_mgr.handle_comm_command(args)

func _cmd_mail(args: Array = []) -> void:
	if not user_mgr.is_logged_in:
		main.append_output("[color=" + T.error_hex + "]请先登录。[/color]\n", false)
		return
	if main.mail_sys != null:
		await main.mail_sys.handle_mail_command(args)
	else:
		main.append_output("[color=" + T.muted_hex + "]邮件系统未初始化。[/color]\n", false)


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
	# ★ 使用 CRT shader 重启效果（如果可用）
	if main.has_method("trigger_reboot"):
		# trigger_reboot 会处理关机动画 → 清屏 → 开机动画 → 欢迎消息
		# 但我们还需要重置命令历史和磁盘状态
		command_history.clear()
		history_index = -1
		disc_mgr.reset_all()
		tw.clear_queue()
		main.trigger_reboot()
	else:
		# 回退：无 shader 效果的普通重启
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
	main._perform_shutdown()


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

func _cmd_explore(args: Array = []) -> void:
	if not main.explore_viewer:
		return
	# 桌面模式下可以指定磁盘编号: explore 1
	if main._desktop_mode and not args.is_empty():
		var idx: int = str(args[0]).to_int()
		if idx > 0 and idx <= disc_mgr.available_stories.size():
			# 临时加载指定磁盘的存档数据来显示进度
			main.explore_viewer.open_for_story(idx - 1)
			return
		else:
			main.append_output("[color=" + T.error_hex + "]无效的磁盘编号。用法: explore <编号>[/color]\n", false)
			return
	if main._desktop_mode and args.is_empty():
		# 桌面模式无参数时提示
		main.append_output("[color=" + T.muted_hex + "]用法: explore <磁盘编号>  (查看指定磁盘的探索进度)[/color]\n", false)
		if disc_mgr.available_stories.size() > 0:
			main.append_output("[color=" + T.muted_hex + "]可用磁盘:[/color]\n", false)
			for i in range(disc_mgr.available_stories.size()):
				var info: Dictionary = disc_mgr.available_stories[i]
				var title: String = str(info.get("title", "未知"))
				main.append_output("  [color=" + T.primary_hex + "]" + str(i + 1) + "[/color]  " + title + "\n", false)
		return
	# 磁盘模式下直接切换
	main.explore_viewer.toggle()

func _cmd_install(args: Array = []) -> void:
	if main.pkg_mgr == null:
		main.append_output("[color=" + T.error_hex + "]软件包管理器未初始化。[/color]\n", false)
		return

	if args.is_empty():
		main.append_output("[color=" + T.error_hex + "]用法: install <磁盘编号>[/color]\n", false)
		main.append_output("[color=" + T.muted_hex + "]输入 scan 查看可安装的软件包。[/color]\n", false)
		return

	var index_str: String = str(args[0])
	if not index_str.is_valid_int():
		main.append_output("[color=" + T.error_hex + "]请输入有效的编号。[/color]\n", false)
		return

	var index: int = int(index_str) - 1
	if index < 0 or index >= disc_mgr.available_stories.size():
		main.append_output("[color=" + T.error_hex + "]编号超出范围。可用: 1-" + str(disc_mgr.available_stories.size()) + "[/color]\n", false)
		return

	# 显示安装进度
	main.append_output("[color=" + T.muted_hex + "]正在安装软件包...[/color]\n", false)
	await tw.show_progress_bar(500)

	var result: Dictionary = main.pkg_mgr.install_package(index)
	if result["success"]:
		main.append_output("[color=" + T.success_hex + "]" + str(result["message"]) + "[/color]\n", false)
	else:
		main.append_output("[color=" + T.error_hex + "]" + str(result["message"]) + "[/color]\n", false)

func _cmd_uninstall(args: Array = []) -> void:
	if main.pkg_mgr == null:
		main.append_output("[color=" + T.error_hex + "]软件包管理器未初始化。[/color]\n", false)
		return

	if args.is_empty():
		main.append_output("[color=" + T.error_hex + "]用法: uninstall <包名或ID>[/color]\n", false)
		main.append_output("[color=" + T.muted_hex + "]输入 packages 查看已安装的软件包。[/color]\n", false)
		return

	# 支持多个单词组成的包名
	var pkg_name: String = " ".join(args)

	main.append_output("[color=" + T.muted_hex + "]正在卸载...[/color]\n", false)
	await tw.show_progress_bar(300)

	var result: Dictionary = main.pkg_mgr.uninstall_package(pkg_name)
	if result["success"]:
		main.append_output("[color=" + T.success_hex + "]" + str(result["message"]) + "[/color]\n", false)
	else:
		main.append_output("[color=" + T.error_hex + "]" + str(result["message"]) + "[/color]\n", false)

func _cmd_packages(_args: Array = []) -> void:
	if main.pkg_mgr == null:
		main.append_output("[color=" + T.error_hex + "]软件包管理器未初始化。[/color]\n", false)
		return
	main.append_output(main.pkg_mgr.get_installed_list_text(), false)


# ══════════════════════════════════════════════════════════════
#  磁盘模式命令
# ══════════════════════════════════════════════════════════════
func _cmd_ls(args: Array = []) -> void:
	var target_path: String = main.current_path
	if args.size() > 0:
		var arg: String = str(args[0])
		if arg.begins_with("/"):
			target_path = fs.normalize_path(arg)
		else:
			target_path = fs.normalize_path(fs.join_path(main.current_path, arg))

	var node = fs.get_node_at_path(target_path)
	if node == null or node.type != "folder":
		main.append_output("[color=" + T.error_hex + "]目录不存在: " + target_path + "[/color]\n", false)
		return

	if not fs.has_clearance(target_path):
		var required: int = fs.get_required_clearance(target_path)
		main.append_output("[color=" + T.error_hex + "]权限不足。需要等级 " + str(required) + " 的安全许可。[/color]\n", false)
		return

	var children: Array[String] = fs.get_children_at_path(target_path)
	if children.is_empty():
		main.append_output("[color=" + T.muted_hex + "]（空目录）[/color]\n", false)
		return

	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var w: String = T.warning_hex
	var e: String = T.error_hex

	# ★ 显示目录描述（如果在 manifest.file_descriptions 中配置了）
	var folder_desc: Dictionary = fs.get_folder_description(target_path)
	if not folder_desc.is_empty():
		var fname: String = str(folder_desc.get("name", ""))
		var fdesc: String = str(folder_desc.get("description", ""))
		if not fname.is_empty():
			main.append_output("[color=" + p + "]" + fname + "[/color]\n", false)
		if not fdesc.is_empty():
			main.append_output("[color=" + m + "]" + fdesc + "[/color]\n", false)
		main.append_output("\n", false)

	for child_name in children:
		var child_path: String = fs.join_path(target_path, child_name)
		var child_node = fs.get_node_at_path(child_path)
		if child_node == null:
			continue

		# ★ 跳过隐藏目录中的内容（替代旧的 _headers.cfg / .meta.cfg 硬编码过滤）
		if fs.is_hidden_path(child_path):
			continue

		# ★ 跳过旧版配置文件（过渡期兼容，防止残留文件显示在列表中）
		if child_name in ["_headers.cfg", ".meta.cfg", "signals.cfg"]:
			continue

		var required_clearance: int = fs.get_required_clearance(child_path)
		var has_access: bool = fs.player_clearance >= required_clearance

		# ★ 获取显示名和文件描述
		var display_name: String = fs.get_display_name(child_path)
		var file_desc: String = fs.get_file_description(target_path, child_name)

		if child_node.type == "folder":
			var dir_display: String = child_name + "/"
			if not display_name.is_empty():
				dir_display = child_name + "/  [color=" + m + "]" + display_name + "[/color]"

			if not has_access:
				main.append_output("  [color=" + e + "]" + child_name + "/  [LOCKED - 等级 " + str(required_clearance) + "][/color]\n", false)
			else:
				main.append_output("  [color=" + p + "]" + dir_display + "[/color]\n", false)
		else:
			# 检查是否已读
			var read_marker: String = ""
			if main.read_files.has(child_path):
				read_marker = " [color=" + m + "]✓[/color]"

			# 检查文件密码
			var fp_key: String = fs.get_file_password_key(child_path)
			var fp_locked: bool = not fp_key.is_empty() and not fs.is_file_password_unlocked(child_path)

			# ★ 构建显示名：display_name 优先，其次 file_description
			var name_display: String = child_name
			if not display_name.is_empty():
				name_display = child_name + "  [color=" + m + "]" + display_name + "[/color]"
			elif not file_desc.is_empty():
				name_display = child_name + "  [color=" + m + "]— " + file_desc + "[/color]"

			if not has_access:
				main.append_output("  [color=" + e + "]" + child_name + "  [LOCKED - 等级 " + str(required_clearance) + "][/color]\n", false)
			elif fp_locked:
				main.append_output("  [color=" + w + "]" + child_name + "  [需要文件密码][/color]" + read_marker + "\n", false)
			else:
				main.append_output("  [color=" + p + "]" + name_display + "[/color]" + read_marker + "\n", false)


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

	if main.ui_sound:
		main.ui_sound.play_click()

	main.current_path = new_path
	main._update_status_bar()
	
	
	main.append_output("已切换到: " + main.current_path + "\n", false)
	main.update_ambient_sound()
	# ★ 触发 on_enter / on_first_enter
	if main.trigger_sys:
		main.trigger_sys.on_enter_directory(new_path)
	# ★ 记录已访问目录
	if not main.visited_paths.has(new_path):
		main.visited_paths.append(new_path)

func _cmd_back(_args: Array = []) -> void:
	if main.current_path == "/":
		main.append_output("[color=" + T.muted_hex + "]已在根目录。[/color]\n", false)
		return
	var parent_path: String = fs.get_parent_path(main.current_path)
	main.current_path = parent_path
	main._update_status_bar()
	main.append_output("已返回: " + main.current_path + "\n", false)
	main.update_ambient_sound()
	# ★ 触发 on_enter
	if main.trigger_sys:
		main.trigger_sys.on_enter_directory(parent_path)
	if not main.visited_paths.has(parent_path):
		main.visited_paths.append(parent_path)

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
	# ★ 阻止直接打开 .meta.cfg
	if base_filename == ".meta.cfg":
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

	if VideoPlayerViewer.is_supported_video(filename):
		var video_data: PackedByteArray = fs.get_binary_data(file_path)
		if video_data.is_empty():
			main.append_output("[color=" + T.error_hex + "]无法读取视频数据。[/color]\n", false)
			return
		var ext_tag: String = filename.get_extension().to_upper()
		main.append_output("[color=" + T.muted_hex + "]正在加载视频 [" + ext_tag + "]: " + filename + "...[/color]\n", false)
		main.open_video_player_with_file(file_path, filename, video_data)
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
	if main.ui_sound:
		main.ui_sound.play_click()
	var m: String = T.muted_hex

	# ★ 头文件解析
	var header_result: Dictionary = HeaderParser.parse(content)
	var header: Dictionary = header_result["header"]
	var body: String = header_result["body"]
	var has_header: bool = header_result["has_header"]

	# ★ 根据头文件中的 title 字段，优先用头文件标题
	var display_title: String = filename
	if has_header:
		var header_title: String = str(header.get("title", ""))
		if not header_title.is_empty():
			display_title = header_title

	# ★ 检查模板类型，决定用哪个查看器
	var template_name: String = str(header.get("template", "document")).to_lower()

	if template_name == "two_page" and main.two_page_viewer != null:
		# ── 双页阅读器模式 ──
		var parsed_content: String = body
		if crtml != null:
			parsed_content = crtml.parse(body)
		if user_mgr.is_logged_in:
			parsed_content = parsed_content.replace("{username}", user_mgr.get_username())

		var page_data: Array[Dictionary] = [{"content": parsed_content}]
		main.two_page_viewer.open("two_page", page_data, display_title, Callable())

		# 记录已读
		if not main.read_files.has(file_path):
			main.read_files.append(file_path)
			
		# ★ 触发 on_open_file 和 on_read_complete
		if main.trigger_sys:
			main.trigger_sys.on_open_file(file_path)
			main.trigger_sys.on_read_complete(file_path)
		
		if user_mgr.is_logged_in:
			user_mgr.increment_files_read()
		disc_mgr._auto_save()
		return

	if template_name == "email" and main.email_viewer != null:
		# ── 邮件查看器模式 ──
		var parsed_content: String = body
		if crtml != null:
			parsed_content = crtml.parse(body)
		if user_mgr.is_logged_in:
			parsed_content = parsed_content.replace("{username}", user_mgr.get_username())
		main.email_viewer.open(display_title, header, parsed_content, Callable())
		if not main.read_files.has(file_path):
			main.read_files.append(file_path)
		# ★ 触发 on_open_file 和 on_read_complete
		if main.trigger_sys:
			main.trigger_sys.on_open_file(file_path)
			main.trigger_sys.on_read_complete(file_path)
		if user_mgr.is_logged_in:
			user_mgr.increment_files_read()
		disc_mgr._auto_save()
		return


		# 聊天记录模板
	if template_name == "chat" and main.chat_viewer != null:
		main.chat_viewer.open(display_title, header, body, Callable())
		if not main.read_files.has(file_path):
			main.read_files.append(file_path)
		# ★ 触发 on_open_file 和 on_read_complete
		if main.trigger_sys:
			main.trigger_sys.on_open_file(file_path)
			main.trigger_sys.on_read_complete(file_path)
		if user_mgr.is_logged_in:
			user_mgr.increment_files_read()
		disc_mgr._auto_save()
		return


		# 文章模板
	if template_name == "article" and main.article_viewer != null:
		main.article_viewer.open(display_title, header, body, Callable())
		if not main.read_files.has(file_path):
			main.read_files.append(file_path)
		# ★ 触发 on_open_file 和 on_read_complete
		if main.trigger_sys:
			main.trigger_sys.on_open_file(file_path)
			main.trigger_sys.on_read_complete(file_path)
		if user_mgr.is_logged_in:
			user_mgr.increment_files_read()
		disc_mgr._auto_save()
		return


	# ── 默认终端模式（原有逻辑） ──
	main.append_output("\n[color=" + p + "]══════════ " + display_title + " ══════════[/color]\n\n", false)

	# ★ 如果有头文件，显示标题横幅
	if has_header:
		var banner: String = HeaderParser.build_title_banner(header, T)
		if not banner.is_empty():
			main.append_output(banner + "\n", false)

		# CRT-ML 解析
		var parsed_content: String = body
		if crtml != null:
			parsed_content = crtml.parse(body)

		# 替换 {username} 变量
		if user_mgr.is_logged_in:
			parsed_content = parsed_content.replace("{username}", user_mgr.get_username())

		parsed_content = _replace_inline_image_placeholders(parsed_content)

		main.append_output(parsed_content + "\n", true)

		# 记录已读
		if not main.read_files.has(file_path):
			main.read_files.append(file_path)

		# ★ 触发 on_open_file 和 on_read_complete
		if main.trigger_sys:
			main.trigger_sys.on_open_file(file_path)
			main.trigger_sys.on_read_complete(file_path)

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

	else:
		# 无头文件：直接显示原始内容
		var parsed_content: String = body
		if crtml != null:
			parsed_content = crtml.parse(body)
		if user_mgr.is_logged_in:
			parsed_content = parsed_content.replace("{username}", user_mgr.get_username())
		
		parsed_content = _replace_inline_image_placeholders(parsed_content)
		
		main.append_output(parsed_content + "\n", true)
		
		# 记录已读
		if not main.read_files.has(file_path):
			main.read_files.append(file_path)
		# ★ 触发
		if main.trigger_sys:
			main.trigger_sys.on_open_file(file_path)
			main.trigger_sys.on_read_complete(file_path)
		if user_mgr.is_logged_in:
			user_mgr.increment_files_read()
		disc_mgr._auto_save()
		while tw.is_typing:
			await main.get_tree().process_frame
		main.append_output("\n[color=" + p + "]══════════ 文件结束 ══════════[/color]\n", false)
		main.append_output("[color=" + m + "]输入任意命令返回终端。[/color]\n", false)



## ★ 替换内联图片占位符为纯文本链接（终端模式下不嵌入真实图片）
func _replace_inline_image_placeholders(text: String) -> String:
	if crtml == null:
		return text
	var result: String = text
	var images: Array[Dictionary] = crtml.get_inline_images()
	for img_info in images:
		var placeholder_id: String = str(img_info.get("placeholder", ""))
		var img_path: String = str(img_info.get("path", ""))
		var original_size: Vector2 = img_info.get("original_size", Vector2.ZERO) as Vector2
		var placeholder_tag: String = "\u0001IMG:" + placeholder_id + "\u0002"

		if result.contains(placeholder_tag):
			var file_name: String = img_path.get_file()
			var size_str: String = ""
			if original_size.x > 0:
				size_str = " (" + str(int(original_size.x)) + "x" + str(int(original_size.y)) + ")"
			var info_c: String = T.info_hex
			var m_c: String = T.muted_hex
			var replacement: String = "[color=" + m_c + "][IMG] " + file_name + size_str + "[/color]  [url=cmd://open " + img_path + "][color=" + info_c + "][ 查看图片 ][/color][/url]"
			result = result.replace(placeholder_tag, replacement)
	return result


func _cmd_unlock(args: Array = []) -> void:
	if args.is_empty():
		main.append_output("[color=" + T.primary_hex + "]请输入认证密码 (输入 cancel 取消): [/color]", false)
		main._password_mode = true
		main._password_target_path = main.current_path
		return
	_verify_password(str(args[0]))

func _verify_password(password: String) -> void:
	var passwords: Dictionary = {}

	# ★ 统一从 manifest 顶层读取（story_loader 已标准化为新格式）
	if main.story_manifest.has("passwords"):
		passwords = main.story_manifest.get("passwords", {}) as Dictionary
	else:
		# 旧版兼容：从 story 区块读取
		var story_dict: Dictionary = main.story_manifest.get("story", {}) as Dictionary
		if story_dict.has("passwords"):
			passwords = story_dict.get("passwords", {}) as Dictionary

	# 新格式: { "password_string": { "grants_clearance": N, "message": "..." } }
	if passwords.has(password):
		var entry = passwords[password]
		if entry is Dictionary:
			var level: int = int(entry.get("grants_clearance", 0))
			var msg: String = str(entry.get("message", "权限等级已提升至 " + str(level) + "。"))
			if fs.player_clearance < level:
				fs.player_clearance = level
				if not main.unlocked_passwords.has(password):
					main.unlocked_passwords.append(password)
				var box: String = fs.build_box(
					["ACCESS GRANTED", msg] as Array[String],
					T.success_hex
				)
				main.append_output(box + "\n", false)
				disc_mgr._auto_save()
				main._update_status_bar()
					# ★ 触发权限变化
				if main.trigger_sys:
					main.trigger_sys.on_level_change(level)

				return
			else:
				main.append_output("[color=" + T.warning_hex + "]当前等级已达到或超过该密码对应的等级。[/color]\n", false)
				return

	# 旧格式兜底: { "level_number": "password_string" }
	# (如果 story_loader 的标准化没有覆盖到，例如 manifest.cfg 旧格式)
	for level_str in passwords.keys():
		var pwd_value = passwords[level_str]
		if pwd_value is String and password == pwd_value:
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
				# ★ 触发权限变化
				if main.trigger_sys:
					main.trigger_sys.on_level_change(level)

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

	var fp_value = fs.story_file_passwords.get(fp_key, "")
	var expected_password: String = ""
	if fp_value is Dictionary:
		expected_password = str(fp_value.get("password", ""))
	else:
		expected_password = str(fp_value)
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


func _cmd_radio(_args: Array = []) -> void:
	if main.radio_receiver == null:
		main.append_output("[color=" + T.error_hex + "]无线电模块未初始化。[/color]\n", false)
		return
	if not main.radio_receiver.has_signals():
		main.append_output("[color=" + T.muted_hex + "]当前磁盘未包含无线电信号配置。[/color]\n", false)
		return
	main.append_output("[color=" + T.muted_hex + "]正在启动无线电接收器...[/color]\n", false)
	main.open_radio_receiver()


# ══════════════════════════════════════════
#  效果强度设置命令
# ══════════════════════════════════════════
func _cmd_fx_level(args: Array = []) -> void:
	if main.effect_settings == null:
		main.append_output("[color=" + T.error_hex + "]效果设置模块未初始化。[/color]\n", false)
		return
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var s: String = T.success_hex
	var w: String = T.warning_hex
	var e: String = T.error_hex
	if args.is_empty():
		var current: String = main.effect_settings.get_level_name()
		var lines: Array[String] = []
		lines.append("[color=" + p + "]═══════════ 效果强度设置 ═══════════[/color]")
		lines.append("")
		lines.append("  当前等级: [color=" + p + "]" + current + "[/color]")
		lines.append("")
		lines.append("  [color=" + p + "]full[/color]   完整效果（默认）")
		lines.append("  [color=" + w + "]mild[/color]   温和效果（强度降低50%，持续时间缩短）")
		lines.append("  [color=" + m + "]off[/color]	关闭所有动态视觉效果")
		lines.append("")
		lines.append("[color=" + p + "]════════════════════════════════════[/color]")
		lines.append("[color=" + m + "]用法: fx_level <full|mild|off>[/color]")
		main.append_output("\n".join(lines) + "\n", false)
		return
	var level_str: String = str(args[0]).to_lower()
	match level_str:
		"full":
			main.effect_settings.set_level(EffectSettings.Level.FULL)
			main.append_output("[color=" + s + "]效果等级已设为: 完整 (FULL)[/color]\n", false)
		"mild":
			main.effect_settings.set_level(EffectSettings.Level.MILD)
			main.append_output("[color=" + w + "]效果等级已设为: 温和 (MILD) — 强度降低50%[/color]\n", false)
		"off":
			main.effect_settings.set_level(EffectSettings.Level.OFF)
			main.append_output("[color=" + m + "]所有动态视觉效果已关闭[/color]\n", false)
		_:
			main.append_output("[color=" + e + "]无效选项: " + level_str + "[/color]\n", false)
			main.append_output("[color=" + m + "]可选: full / mild / off[/color]\n", false)

func _cmd_fx_safe(args: Array = []) -> void:
	if main.effect_settings == null:
		main.append_output("[color=" + T.error_hex + "]效果设置模块未初始化。[/color]\n", false)
		return
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var s: String = T.success_hex
	var w: String = T.warning_hex
	if args.is_empty():
		var status: String = "开启" if main.effect_settings.photosensitive_mode else "关闭"
		var status_color: String = s if main.effect_settings.photosensitive_mode else m
		var lines: Array[String] = []
		lines.append("[color=" + p + "]═══════════ 光敏安全模式 ═══════════[/color]")
		lines.append("")
		lines.append("  当前状态: [color=" + status_color + "]" + status + "[/color]")
		lines.append("")
		lines.append("  开启后将禁用以下效果:")
		lines.append("  [color=" + m + "]· 快速闪烁 / 高强度故障效果[/color]")
		lines.append("  [color=" + m + "]· Jumpscare 闪屏[/color]")
		lines.append("  [color=" + m + "]· 突然黑屏[/color]")
		lines.append("  [color=" + m + "]· 高强度噪点爆发[/color]")
		lines.append("")
		lines.append("[color=" + p + "]════════════════════════════════════[/color]")
		lines.append("[color=" + m + "]用法: fx_safe <on|off>[/color]")
		main.append_output("\n".join(lines) + "\n", false)
		return
	var val: String = str(args[0]).to_lower()
	if val in ["on", "true", "1", "yes"]:
		main.effect_settings.set_photosensitive(true)
		main.append_output("[color=" + s + "]光敏安全模式已开启[/color]\n", false)
		main.append_output("[color=" + m + "]已禁用: 快速闪烁、强故障、jumpscare、突然黑屏[/color]\n", false)
	elif val in ["off", "false", "0", "no"]:
		main.effect_settings.set_photosensitive(false)
		main.append_output("[color=" + w + "]光敏安全模式已关闭[/color]\n", false)
	else:
		main.append_output("[color=" + T.error_hex + "]无效选项: " + val + "[/color]\n", false)
		main.append_output("[color=" + m + "]用法: fx_safe on / fx_safe off[/color]\n", false)


func _cmd_sound(args: Array = []) -> void:
	if main.ui_sound == null:
		main.append_output("[color=" + T.error_hex + "]音效系统未初始化。[/color]\n", false)
		return
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var s: String = T.success_hex
	if args.is_empty():
		var status: String = "开启" if main.ui_sound.enabled else "关闭"
		var lines: Array[String] = []
		lines.append("[color=" + p + "]═══════════ 操作音效 ═══════════[/color]")
		lines.append("")
		lines.append("  状态: [color=" + p + "]" + status + "[/color]")
		lines.append("")
		lines.append("[color=" + p + "]════════════════════════════════[/color]")
		lines.append("[color=" + m + "]用法: sound <on|off>[/color]")
		main.append_output("\n".join(lines) + "\n", false)
		return
	var val: String = str(args[0]).to_lower()
	if val in ["on", "true", "1"]:
		main.ui_sound.set_enabled(true)
		main.append_output("[color=" + s + "]操作音效已开启[/color]\n", false)
	elif val in ["off", "false", "0"]:
		main.ui_sound.set_enabled(false)
		main.append_output("[color=" + m + "]操作音效已关闭[/color]\n", false)
	else:
		main.append_output("[color=" + T.error_hex + "]用法: sound on / sound off[/color]\n", false)



# ══════════════════════════════════════════
#  decode 命令 —— 密码解码器
# ══════════════════════════════════════════
func _cmd_decode(args: Array = []) -> void:
	# 检查 decode_viewer 是否已初始化
	if main.decode_viewer == null:
		main.append_output("[color=" + T.error_hex + "]解码器模块未初始化。[/color]\n", false)
		return

	if args.is_empty():
		# 无参数：打开交互式选择界面
		main.append_output("[color=" + T.muted_hex + "]正在启动密码解码器...[/color]\n", false)
		main.open_decode_viewer([])
		return

	# 有参数：decode <method> [key]
	var method: String = str(args[0]).to_lower()

	# 帮助信息
	if method == "help" or method == "?":
		var p: String = T.primary_hex
		var m: String = T.muted_hex
		var lines: Array[String] = []
		lines.append("[color=" + p + "]═══════════ 密码解码器 ═══════════[/color]")
		lines.append("")
		lines.append("  [color=" + p + "]decode[/color]			  [color=" + m + "]打开交互式解码界面[/color]")
		lines.append("  [color=" + p + "]decode <方法>[/color]	   [color=" + m + "]指定解码方法后输入密文[/color]")
		lines.append("  [color=" + p + "]decode <方法> <密钥>[/color] [color=" + m + "]同时指定密钥[/color]")
		lines.append("  [color=" + p + "]decode help[/color]		 [color=" + m + "]显示此帮助[/color]")
		lines.append("")
		lines.append("[color=" + m + "]可用方法:[/color]")
		lines.append("  [color=" + p + "]caesar[/color]   [color=" + m + "]凯撒密码 (key=偏移量, 留空自动检测)[/color]")
		lines.append("  [color=" + p + "]vigenere[/color] [color=" + m + "]维吉尼亚密码 (需要密钥单词)[/color]")
		lines.append("  [color=" + p + "]rot13[/color]	[color=" + m + "]ROT13[/color]")
		lines.append("  [color=" + p + "]atbash[/color]   [color=" + m + "]Atbash 镜像密码[/color]")
		lines.append("  [color=" + p + "]sub[/color]	  [color=" + m + "]替换密码 (需要26位密钥)[/color]")
		lines.append("  [color=" + p + "]base64[/color]   [color=" + m + "]Base64 解码[/color]")
		lines.append("  [color=" + p + "]morse[/color]	[color=" + m + "]摩斯电码解码[/color]")
		lines.append("  [color=" + p + "]reverse[/color]  [color=" + m + "]字符串反转[/color]")
		lines.append("")
		lines.append("[color=" + p + "]════════════════════════════════════[/color]")
		main.append_output("\n".join(lines) + "\n", false)
		return

	# 验证方法是否有效
	var valid_methods: Array[String] = [
		"caesar", "vigenere", "rot13", "atbash",
		"sub", "substitution", "base64", "b64",
		"morse", "reverse", "rev"
	]
	if method not in valid_methods:
		main.append_output("[color=" + T.error_hex + "]未知的解码方法: " + method + "[/color]\n", false)
		main.append_output("[color=" + T.muted_hex + "]输入 decode help 查看可用方法。[/color]\n", false)
		return

	# 传递参数给 decode_viewer 打开
	main.append_output("[color=" + T.muted_hex + "]正在启动密码解码器...[/color]\n", false)
	main.open_decode_viewer(args)
