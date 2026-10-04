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
#  调试：radio test 注入的临时信号 ID（用于 clean）
# ══════════════════════════════════════════
var _test_radio_ids: Array[String] = []

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
		"nickname": _cmd_nickname,
		"gender": _cmd_gender,
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
		"env": _cmd_env,             # ★ 环境监测系统
		"monitor": _cmd_env,         # ★ 环境监测（别名）
		"camera": _cmd_camera,       # ★ 监控摄像头系统
		"cam": _cmd_camera,          # ★ 监控摄像头（简写）
		"cctv": _cmd_camera,         # ★ 监控摄像头（别名）
		"save": _cmd_save,           # ★ 手动保存进度
		"vdisc": _cmd_vdisc,
		"perf": _cmd_perf,           # ★ 绩效系统
		"performance": _cmd_perf,    # ★ 绩效系统（全称）
		# ★ 调试命令不在此注册（正常游戏不可见），需输入 "debug 114514" 激活
		# "debug": _cmd_debug,
	}

	# ── 桌面模式专用命令 ──
	desktop_commands = {
		"scan": _cmd_scan,
		"load": _cmd_load,
		"download": _cmd_download,
		"deluser": _cmd_deluser,
		"explore": _cmd_explore,
		"install": _cmd_install,
		"radio": _cmd_radio,
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
		"clearsave": _cmd_clearsave,
		"explore": _cmd_explore,
		"cp": _cmd_cp,
		"mv": _cmd_mv,
		"rm": _cmd_rm,
		"mkfile": _cmd_mkfile,
		"submit": _cmd_submit,
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

	# ★ 调试入口：输入 "debug 114514" 激活调试模式（不在 help 中显示，正常游戏不可见）
	if cmd == "debug":
		if args.size() >= 1 and args[0] == "114514":
			var dbg_args: Array = []
			for i in range(1, args.size()):
				dbg_args.append(args[i])
			_add_to_history(raw)
			await _cmd_debug(dbg_args)
		else:
			_cmd_unknown("debug")
		return

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
	var has_trailing_space: bool = current_text.ends_with(" ")
	var parts: PackedStringArray = current_text.split(" ", false)
	if parts.is_empty():
		return [] as Array[String]

	# logical_size：用户已"确认"的 token 数
	# "cd"      → 1  补全命令名
	# "cd "     → 2  补全第一参数（前缀为空）
	# "cd doc"  → 2  补全第一参数（前缀 "doc"）
	# "env r "  → 3  补全第二参数（前缀为空）
	var logical_size: int = parts.size() + (1 if has_trailing_space else 0)
	var results: Array[String] = []

	if logical_size == 1:
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

	elif logical_size == 2:
		# 补全第一个参数
		var cmd: String = parts[0].to_lower()
		var arg_prefix: String = "" if has_trailing_space else parts[1]

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
		elif cmd in ["env", "monitor"]:
			var env_subs: Array[String] = ["status", "view", "tasks", "scan", "check", "read",
				"calibrate", "anomaly", "report", "repair", "sensor", "weather", "events", "help", "history", "details", "retest", "mark"]
			for sub in env_subs:
				if sub.begins_with(arg_prefix.to_lower()):
					results.append(cmd + " " + sub)
		elif cmd in ["camera", "cam", "cctv"]:
			var cam_subs: Array[String] = ["list", "view", "status", "help"]
			for sub in cam_subs:
				if sub.begins_with(arg_prefix.to_lower()):
					results.append(cmd + " " + sub)
		elif cmd == "mail":
			var mail_subs: Array[String] = ["list", "read"]
			for sub in mail_subs:
				if sub.begins_with(arg_prefix.to_lower()):
					results.append(cmd + " " + sub)
		elif cmd == "clearsave":
			if "all".begins_with(arg_prefix.to_lower()):
				results.append(cmd + " all")

	elif logical_size == 3:
		# 补全第二个参数
		var cmd: String = parts[0].to_lower()
		var sub: String = parts[1].to_lower()
		var arg_prefix: String = "" if has_trailing_space else parts[2]

		if cmd in ["env", "monitor"] and sub == "read":
			var categories: Array[String] = ["atmosphere", "ocean", "geophysics", "composition"]
			for cat in categories:
				if cat.begins_with(arg_prefix.to_lower()):
					results.append(cmd + " " + sub + " " + cat)
		elif cmd in ["env", "monitor"] and sub == "sensor":
			if main.env_monitor:
				for sid in main.env_monitor.sensors.keys():
					if str(sid).to_lower().begins_with(arg_prefix.to_lower()):
						results.append(cmd + " " + sub + " " + str(sid))
		elif cmd in ["camera", "cam", "cctv"] and sub in ["view", "v"]:
			if main.camera_mgr:
				var unlocked: Array[SecurityCameraFeed] = main.camera_mgr.get_unlocked_cameras()
				for i in range(unlocked.size()):
					var num_str: String = str(i + 1)
					if num_str.begins_with(arg_prefix):
						results.append(cmd + " " + sub + " " + num_str)
				for cam in unlocked:
					if cam.id.to_lower().begins_with(arg_prefix.to_lower()):
						results.append(cmd + " " + sub + " " + cam.id)

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
		lines.append("  [color=" + p + "]vdisc[/color]         查看磁盘与任务箱")
		lines.append("  [color=" + p + "]download <任务ID>[/color] 下载 Vdisc 任务盘")
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
		lines.append("  [color=" + p + "]nickname[/color]      设置昵称")
		lines.append("  [color=" + p + "]gender[/color]        设置性别 (M/F/X)")
		lines.append("  [color=" + p + "]logout[/color]        注销当前账户")
		lines.append("  [color=" + p + "]deluser <用户名>[/color] 删除指定用户")
		lines.append("")
		lines.append("[color=" + p + "]  ── 系统 ──[/color]")
		lines.append("  [color=" + p + "]status[/color]        查看系统状态")
		lines.append("  [color=" + p + "]mail[/color]          查看邮件")
		lines.append("  [color=" + p + "]mail download <ID>[/color] 领取 Vdisc 附件")
		lines.append("  [color=" + p + "]comm[/color]		  通讯系统状态 / 接听来电")
		lines.append("  [color=" + p + "]dial <号码>[/color]	拨号呼叫")
		lines.append("  [color=" + p + "]phonebook[/color]	  查看号码簿")
		lines.append("  [color=" + p + "]theme <名称>[/color]  切换主题配色")
		lines.append("  [color=" + p + "]settings[/color]      查看/修改终端设置")
		lines.append("  [color=" + p + "]volume[/color]        查看/设置音量")
		lines.append("  [color=" + p + "]clear[/color]         清屏")
		lines.append("  [color=" + p + "]reboot[/color]        重启终端")
		lines.append("  [color=" + p + "]exit[/color]          退出终端")
		lines.append("  [color=" + p + "]save[/color]          手动保存进度")
		lines.append("")
		lines.append("[color=" + p + "]  ── 环境监测 ──[/color]")
		lines.append("  [color=" + p + "]env[/color]           环境监测系统 (env help 查看子命令)")
		lines.append("  [color=" + p + "]camera[/color]        监控摄像头系统 (camera help 查看子命令)")
		lines.append("  [color=" + p + "]radio[/color]         启动无线电接收器")
		lines.append("  [color=" + p + "]perf[/color]          绩效查询 (perf / perf history / perf detail)")
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
		lines.append("  [color=" + p + "]cp/mv/rm/mkfile[/color] 编辑任务磁盘副本")
		lines.append("  [color=" + p + "]submit <号码>[/color] 上交任务磁盘")
		lines.append("  [color=" + p + "]unlock[/color]        尝试密码认证提升权限")
		lines.append("  [color=" + p + "]decode[/color]       [color=" + m + "]密码解码器[/color]")
		lines.append("")
		lines.append("[color=" + p + "]  ── 软件包 ──[/color]")
		lines.append("  [color=" + p + "]packages[/color]	  查看已安装的软件包")
		lines.append("  [color=" + p + "]uninstall <名称>[/color] 卸载已安装的软件包")
		lines.append("")
		lines.append("[color=" + p + "]  ── 磁盘管理 ──[/color]")
		lines.append("  [color=" + p + "]eject[/color]         弹出当前磁盘")
		lines.append("  [color=" + p + "]vdisc[/color]         查看当前任务进度")
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
		lines.append("[color=" + p + "]  ── 环境监测 ──[/color]")
		lines.append("  [color=" + p + "]env[/color]           环境监测系统 (env help 查看子命令)")
		lines.append("  [color=" + p + "]camera[/color]        监控摄像头系统 (camera help 查看子命令)")
		lines.append("  [color=" + p + "]perf[/color]          绩效查询 (perf / perf history / perf detail)")
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

func _cmd_nickname(args: Array = []) -> void:
	if not user_mgr.is_logged_in:
		main.append_output("[color=" + T.error_hex + "]当前未登录。[/color]\n", false)
		return
	if args.is_empty():
		var current_nick: String = user_mgr.get_nickname()
		if current_nick.is_empty():
			main.append_output("[color=" + T.muted_hex + "]昵称未设置。[/color]\n", false)
		else:
			main.append_output("[color=" + T.primary_hex + "]昵称: " + current_nick + "[/color]\n", false)
		main.append_output("[color=" + T.muted_hex + "]用法: nickname <名字>[/color]\n", false)
		return
	var nick: String = " ".join(args)
	var result: Dictionary = user_mgr.set_nickname(nick)
	if result["success"]:
		main.append_output("[color=" + T.success_hex + "]" + str(result["message"]) + "[/color]\n", false)
	else:
		main.append_output("[color=" + T.error_hex + "]" + str(result["message"]) + "[/color]\n", false)

func _cmd_gender(args: Array = []) -> void:
	if not user_mgr.is_logged_in:
		main.append_output("[color=" + T.error_hex + "]当前未登录。[/color]\n", false)
		return
	if args.is_empty():
		var current_gender: String = user_mgr.get_gender()
		if current_gender.is_empty():
			main.append_output("[color=" + T.muted_hex + "]性别未设置。[/color]\n", false)
		else:
			var label: String = {"M": "男", "F": "女", "X": "其他"}.get(current_gender, current_gender)
			main.append_output("[color=" + T.primary_hex + "]性别: " + label + "[/color]\n", false)
		main.append_output("[color=" + T.muted_hex + "]用法: gender M/F/X[/color]\n", false)
		return
	var result: Dictionary = user_mgr.set_gender(str(args[0]))
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

func _cmd_download(args: Array = []) -> void:
	if args.is_empty() or main.vdisc_task_mgr == null:
		main.append_output("用法: download <任务ID>\n", false)
		return
	var result: Dictionary = await main.vdisc_task_mgr.download_task(str(args[0]))
	_print_vdisc_result(result)

func _print_vdisc_result(result: Dictionary) -> void:
	var color: String = T.success_hex if bool(result.get("ok", false)) else T.error_hex
	main.append_output("[color=" + color + "]" + str(result.get("message", "操作失败。")) + "[/color]\n", false)

func _vdisc_path(value: String) -> String:
	return fs.normalize_path(value if value.begins_with("/") else fs.join_path(main.current_path, value))

func _vdisc_edit_allowed(paths: Array) -> bool:
	if main.vdisc_task_mgr == null or main.story_id.is_empty():
		return false
	var task_id: String = main.vdisc_task_mgr.get_task_for_story(main.story_id)
	if task_id.is_empty() or main.vdisc_task_mgr.get_task_status(task_id) != "downloaded":
		return false
	var download: Dictionary = main.vdisc_task_mgr.definitions[task_id].get("download", {})
	if disc_mgr.current_loaded_path != main.vdisc_task_mgr.get_inbox_dir().path_join(str(download.get("filename", ""))):
		return false
	for path in paths:
		if fs.is_hidden_path(path) or not fs.has_clearance(path):
			return false
	return true

func _cmd_cp(args: Array = []) -> void:
	if args.size() < 2:
		main.append_output("用法: cp <源文件> <目标路径>\n", false)
		return
	var source: String = _vdisc_path(str(args[0]))
	var target: String = _vdisc_path(str(args[1]))
	if not _vdisc_edit_allowed([source, target]) or not fs.copy_node(source, target):
		main.append_output("无法复制：请检查任务状态、权限、路径与目标文件。\n", false)
		return
	main.vdisc_task_mgr.record_path_change(main.story_id, target)
	disc_mgr._auto_save()
	main.append_output("文件已复制。\n", false)

func _cmd_mv(args: Array = []) -> void:
	if args.size() < 2:
		main.append_output("用法: mv <源文件> <目标路径>\n", false)
		return
	var source: String = _vdisc_path(str(args[0]))
	var target: String = _vdisc_path(str(args[1]))
	if not _vdisc_edit_allowed([source, target]) or not fs.move_node(source, target):
		main.append_output("无法移动：请检查任务状态、权限、路径与目标文件。\n", false)
		return
	if main.read_files.has(source):
		main.read_files.erase(source)
		main.read_files.append(target)
	main.vdisc_task_mgr.record_path_change(main.story_id, source)
	main.vdisc_task_mgr.record_path_change(main.story_id, target)
	disc_mgr._auto_save()
	main.append_output("文件已移动。\n", false)

func _cmd_rm(args: Array = []) -> void:
	if args.is_empty():
		main.append_output("用法: rm <文件>\n", false)
		return
	var path: String = _vdisc_path(str(args[0]))
	if not _vdisc_edit_allowed([path]) or not fs.delete_node(path):
		main.append_output("无法删除：请检查任务状态、权限与路径。\n", false)
		return
	main.read_files.erase(path)
	main.vdisc_task_mgr.record_path_change(main.story_id, path)
	disc_mgr._auto_save()
	main.append_output("文件已从工作副本移除。\n", false)

func _cmd_mkfile(args: Array = []) -> void:
	if args.is_empty():
		main.append_output("用法: mkfile <路径> [内容]\n", false)
		return
	var path: String = _vdisc_path(str(args[0]))
	var words: PackedStringArray = PackedStringArray()
	for i in range(1, args.size()):
		words.append(str(args[i]))
	var content: String = " ".join(words)
	if not _vdisc_edit_allowed([path]) or not fs.create_file(path, content):
		main.append_output("无法创建：请检查任务状态、权限与目标路径。\n", false)
		return
	main.vdisc_task_mgr.record_path_change(main.story_id, path)
	disc_mgr._auto_save()
	main.append_output("文件已创建。\n", false)

func _cmd_submit(args: Array = []) -> void:
	if args.is_empty() or main.vdisc_task_mgr == null:
		main.append_output("用法: submit <接收方号码>\n", false)
		return
	_print_vdisc_result(main.vdisc_task_mgr.submit(str(args[0])))

func _debug_vdisc(args: Array) -> void:
	if main.vdisc_task_mgr == null:
		return
	if args.is_empty() or str(args[0]) == "list":
		for task in main.vdisc_task_mgr.get_task_list():
			main.append_output("%s  %s  [%s]\n" % [str(task["id"]), str(task["title"]), str(task["status"])], false)
		return
	match str(args[0]):
		"notice":
			main.append_output("5 秒后发送一条后台提示。请现在打开 mail、explore 或其他全屏界面。\n", false)
			_debug_vdisc_notice.call_deferred()
		"mail":
			if args.size() >= 2:
				_debug_deliver_task_mail(str(args[1]))
			elif main.mail_sys:
				main.mail_sys.deliver_inline_mail("MTEST-VDISC", "Vdisc 联调附件", "SYSTEM", "这是一封系统联调邮件。点击下方附件链接获取调查盘；也可输入 mail download MTEST-VDISC。", true)
				main.append_output("联调邮件已投递。\n", false)
		"reset":
			if args.size() < 2:
				main.append_output("用法: debug 114514 vdisc reset <任务ID>\n", false)
				return
			if main.vdisc_task_mgr.debug_reset_task(str(args[1])):
				main.append_output("任务状态已重置：" + str(args[1]) + "\n", false)
			else:
				main.append_output("未知任务：" + str(args[1]) + "\n", false)
		"give":
			if args.size() < 2:
				main.append_output("用法: debug 114514 vdisc give <任务ID>\n", false)
				return
			_print_vdisc_result(await main.vdisc_task_mgr.download_task(str(args[1])))
		"check":
			if main.story_id.is_empty():
				main.append_output("请先加载任务磁盘。\n", false)
				return
			var task_id: String = main.vdisc_task_mgr.get_task_for_story(main.story_id)
			if task_id.is_empty():
				main.append_output("当前磁盘没有任务。\n", false)
				return
			var result: Dictionary = main.vdisc_task_mgr.check_requirements(task_id)
			var reasons: PackedStringArray = PackedStringArray()
			for item in result["missing"]:
				reasons.append(str(item))
			main.append_output("判定: %s  %s\n" % ["通过" if bool(result["passed"]) else "未达标", ", ".join(reasons)], false)
		_:
			main.append_output("用法: debug 114514 vdisc [list|mail [邮件ID]|give <任务ID>|check|reset <任务ID>|notice]\n", false)

func _debug_deliver_task_mail(mail_id: String) -> void:
	if main.mail_sys == null or main.vdisc_task_mgr == null:
		return
	var matched: Dictionary = {}
	for task_id in main.vdisc_task_mgr.definitions.keys():
		var task: Dictionary = main.vdisc_task_mgr.definitions[task_id]
		var download: Dictionary = task.get("download", {}) as Dictionary
		if str(download.get("mail_attachment", "")) == mail_id:
			matched = task
			break
	if matched.is_empty():
		main.append_output("没有任务的附件使用邮件 ID：" + mail_id + "\n", false)
		return
	main.mail_sys.deliver_inline_mail(
		mail_id,
		str(matched.get("mail_subject", matched.get("title", mail_id))),
		"TASK DISPATCH",
		str(matched.get("mail_body", "任务附件已就绪，点击下方链接领取。")),
		true
	)
	main.append_output("任务邮件已投递：" + mail_id + "\n", false)

func _debug_vdisc_notice() -> void:
	await main.get_tree().create_timer(5.0).timeout
	main.append_output("[后台提示测试] Vdisc 通知已到达；这条记录只应出现在普通终端。\n", false)

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

func _cmd_perf(args: Array = []) -> void:
	var pm: PerformanceManager = main.perf_mgr if main.get("perf_mgr") else null
	if pm == null:
		main.append_output("[color=" + T.error_hex + "]绩效系统未初始化。[/color]\n", false)
		return
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var w: String = T.warning_hex
	var e: String = T.error_hex
	var s: String = T.success_hex
	var sub: String = str(args[0]).to_lower().strip_edges() if args.size() > 0 else ""

	if sub == "history":
		_cmd_perf_history(pm, p, m, w, e)
	elif sub == "detail":
		_cmd_perf_detail(pm, p, m, w, s)
	elif sub == "help":
		main.append_output("[color=" + p + "]═══ 绩效系统命令 ═══[/color]\n", false)
		main.append_output("  [color=" + p + "]perf[/color]          当日绩效概览 + 累计总分\n", false)
		main.append_output("  [color=" + p + "]perf detail[/color]   当日得分明细\n", false)
		main.append_output("  [color=" + p + "]perf history[/color]  历史每日得分表\n", false)
	else:
		_cmd_perf_status(pm, p, m, w, e, s)

func _cmd_perf_status(pm: PerformanceManager, p: String, m: String, w: String, e: String, s: String) -> void:
	var day_sum: Dictionary = pm.get_day_summary()
	var career: Dictionary = pm.get_career_summary()
	var day_total: int = int(day_sum.get("total", 0))
	var quota: int = int(day_sum.get("quota", 3))
	var gap: int = int(day_sum.get("overtime_gap", 0))

	main.append_output("\n[color=" + p + "]╔══════════════════════════════════╗[/color]\n", false)
	main.append_output("[color=" + p + "]║      绩效状态                    ║[/color]\n", false)
	main.append_output("[color=" + p + "]╠══════════════════════════════════╣[/color]\n", false)
	# 当日
	var day_col: String = s if day_total >= quota else (w if day_total > 0 else e)
	main.append_output("[color=" + m + "]  当日得分: [/color][color=" + day_col + "]%d / %d[/color]\n" % [day_total, quota], false)
	# 加班缺口
	if gap > 0:
		main.append_output("[color=" + m + "]  绩效缺口: [/color][color=" + e + "]%d 分待补[/color]\n" % gap, false)
	# 累计
	main.append_output("[color=" + p + "]╠══════════════════════════════════╣[/color]\n", false)
	main.append_output("[color=" + m + "]  累计总分: [/color][color=" + p + "]%d[/color]\n" % career.get("total", 0), false)
	main.append_output("[color=" + m + "]  主线:     [/color]%d  [color=" + m + "]每日: [/color]%d  [color=" + m + "]支线: [/color]%d\n" % [
		career.get("main", 0), career.get("daily", 0), career.get("side", 0)], false)
	if int(career.get("overtime", 0)) > 0:
		main.append_output("[color=" + m + "]  加班绩效: [/color][color=" + w + "]%d[/color]\n" % career.get("overtime", 0), false)
	if int(career.get("warnings", 0)) > 0:
		main.append_output("[color=" + m + "]  累计警告: [/color][color=" + e + "]%d 次[/color]\n" % career.get("warnings", 0), false)
	main.append_output("[color=" + m + "]  进度:     [/color]%d / %d 天\n" % [career.get("days_completed", 0), career.get("game_total_days", 28)], false)
	main.append_output("[color=" + p + "]╚══════════════════════════════════╝[/color]\n\n", false)

func _cmd_perf_history(pm: PerformanceManager, p: String, m: String, w: String, e: String) -> void:
	var history: Array[Dictionary] = pm.get_history()
	if history.is_empty():
		main.append_output("[color=" + m + "]暂无历史绩效记录。[/color]\n", false)
		return
	main.append_output("\n[color=" + p + "]═══ 绩效历史 ═══[/color]\n", false)
	main.append_output("[color=" + m + "] Day │ Main │ Daily│ Side │Bonus │ Total│ Quota│ Gap [/color]\n", false)
	main.append_output("[color=" + m + "]─────┼──────┼──────┼──────┼──────┼──────┼──────┼─────[/color]\n", false)
	for record in history:
		var day: int = int(record.get("day", 0))
		var total: int = int(record.get("total", 0))
		var quota: int = int(record.get("quota", 3))
		var gap: int = int(record.get("gap", 0))
		var col: String = p if gap == 0 else (w if gap <= 2 else e)
		main.append_output("[color=" + col + "] %3d │ %4d │ %4d │ %4d │ %4d │ %4d │ %4d │ %3d [/color]\n" % [
			day,
			int(record.get("main", 0)),
			int(record.get("daily", 0)),
			int(record.get("side", 0)),
			int(record.get("bonus", 0)),
			total,
			quota,
			gap,
		], false)
	main.append_output("\n", false)

func _cmd_perf_detail(pm: PerformanceManager, p: String, m: String, w: String, s: String) -> void:
	var day_sum: Dictionary = pm.get_day_summary()
	var scores: Dictionary = day_sum.get("scores", {})
	var quota: int = int(day_sum.get("quota", 3))
	var total: int = int(day_sum.get("total", 0))
	var gap: int = int(day_sum.get("overtime_gap", 0))

	main.append_output("\n[color=" + p + "]═══ 当日绩效明细 ═══[/color]\n", false)
	main.append_output("[color=" + m + "]  主线绩效:   [/color]%+d\n" % int(scores.get("main", 0)), false)
	main.append_output("[color=" + m + "]  每日绩效:   [/color]%+d\n" % int(scores.get("daily", 0)), false)
	main.append_output("[color=" + m + "]  支线绩效:   [/color]%+d\n" % int(scores.get("side", 0)), false)
	main.append_output("[color=" + m + "]  奖励:       [/color]%+d\n" % int(scores.get("bonus", 0)), false)
	var penalty: int = int(scores.get("penalty", 0))
	if penalty != 0:
		main.append_output("[color=" + m + "]  扣减:       [/color][color=" + w + "]%+d[/color]\n" % penalty, false)
	main.append_output("[color=" + m + "]  ────────────────[/color]\n", false)
	var total_col: String = s if total >= quota else w
	main.append_output("[color=" + m + "]  合计:       [/color][color=" + total_col + "]%+d[/color] [color=" + m + "](配额: %d)[/color]\n" % [total, quota], false)
	if gap > 0:
		main.append_output("[color=" + m + "]  历史缺口:   [/color][color=" + w + "]%d 分待补[/color]\n" % gap, false)
	main.append_output("\n", false)

func _cmd_save(_args: Array = []) -> void:
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
	# 从本地 data/radio/ 加载信号
	main.radio_receiver.load_local_signals()
	if not main.radio_receiver.has_signals():
		main.append_output("[color=" + T.muted_hex + "]未检测到可用无线电信号。[/color]\n", false)
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

# ══════════════════════════════════════════
#  ★ 环境监测系统命令
# ══════════════════════════════════════════
func _cmd_env(args: Array = []) -> void:
	if main.env_observation == null:
		return
	var obs: EnvObservation = main.env_observation
	var sub: String = str(args[0]).to_lower() if not args.is_empty() else "view"
	match sub:
		"view", "panel", "v", "map":
			_cmd_env_view()
		"scan", "auto", "collect":
			_cmd_env_view()
			obs.begin_capture()
		"report":
			obs.submit()
			main.append_output(obs.message + "\n", false)
		"retest", "respond":
			obs.retest()
			main.append_output(obs.message + "\n", false)
		"mark":
			obs.mark_issue()
			main.append_output(obs.message + "\n", false)
		"calibrate", "cal":
			obs.calibrate_issue()
			main.append_output(obs.message + "\n", false)
		"read", "anomaly", "anom", "status", "s":
			_cmd_env_view()
		"history":
			_cmd_env_view()
			main.env_viewer.perform_action("history")
		"details":
			_cmd_env_view()
			main.env_viewer.perform_action("details")
		"tasks", "t":
			main.append_output("今日流程：采集 → 查看摘要 → 提交日报。深入复测可选。\n", false)
		"help", "?":
			_cmd_env_help()
		"check":
			_cmd_env_view()
		"repair":
			_cmd_env_repair(main.env_monitor, args.slice(1), {"primary": T.primary_hex, "muted": T.muted_hex, "success": T.success_hex, "warning": T.warning_hex, "error": T.error_hex})
		"sensor":
			_cmd_env_sensor(main.env_monitor, args.slice(1), {"primary": T.primary_hex, "muted": T.muted_hex, "success": T.success_hex, "warning": T.warning_hex, "error": T.error_hex})
		"weather", "wx", "events":
			_cmd_env_view()
		_:
			_cmd_env_help()

func _cmd_env_help() -> void:
	main.append_output("\nENV 环境监视\nenv / env view   打开观测台\nenv scan         短采集（不自动提交）\nenv report       提交日报\nenv history      日报历史\nenv details      详细传感器数据\nenv retest / env mark / env calibrate   核对、关注或校准当前疑点\n观测台内输入 help 查看命令；scan采集 report提交 details详情 history历史 exit退出\n旧 env read / env anomaly 进入观测台查看结果。\n", false)
func _cmd_env_status(em: EnvMonitor, colors: Dictionary) -> void:
	var p: String = str(colors.get("primary", "#00ff00"))
	var m: String = str(colors.get("muted", "#666666"))
	var w: String = str(colors.get("warning", "#ffcc00"))
	var lines: Array = []
	lines.append("[color=%s]═══ 环境状态概览 (%s %s) ═══[/color]" % [p, em.get_day_display(), em.get_current_hour_display()])
	lines.append("[color=%s]天气: %s  风向: %s  云量: %d/8[/color]\n" % [m, em.get_weather_name(), em.get_wind_direction_name(), roundi(em.get_reading("cloud_cover"))])
	# 按分类输出
	var categories: Array = ["atmosphere", "ocean", "geophysics", "composition"]
	var cat_names: Dictionary = {"atmosphere": "大气", "ocean": "海洋", "geophysics": "地球物理", "composition": "大气成分"}
	for cat in categories:
		lines.append("[color=%s]【%s】[/color]" % [p, str(cat_names.get(cat, cat))])
		var sensor_ids: Array = em.get_sensors_by_category(cat)
		for sid in sensor_ids:
			var cfg: Dictionary = em.get_sensor_config(sid)
			var val: float = em.get_reading(sid)
			var status: String = em.sensor_status.get(sid, "online")
			var trend: String = em.get_sensor_trend(sid)
			var name: String = str(cfg.get("name", sid))
			var unit: String = str(cfg.get("unit", ""))
			var val_str: String
			if is_nan(val) or status == "offline":
				val_str = "---"
			elif absf(val) >= 1000:
				val_str = "%d" % roundi(val)
			else:
				val_str = "%.1f" % val
			var trend_sym: String = ""
			match trend:
				"rising": trend_sym = "↑"
				"falling": trend_sym = "↓"
				"stable": trend_sym = "→"
			var status_tag: String = ""
			var col: String = m
			if status == "offline":
				status_tag = " [离线]"
				col = str(colors.get("error", "#ff4444"))
			elif status == "degraded":
				status_tag = " [退化]"
				col = w
			lines.append("[color=%s]  %-12s %s %s %s%s[/color]" % [col, name, val_str, unit, trend_sym, status_tag])
		lines.append("")
	# 事件
	var events: Dictionary = em.get_active_events()
	if events.size() > 0:
		lines.append("[color=%s]活跃事件:[/color]" % w)
		for eid in events.keys():
			var evt: Dictionary = events[eid]
			lines.append("[color=%s]  • %s (至第%d天)[/color]" % [w, str(evt.get("name", eid)), int(evt.get("end_day", 0))])
		lines.append("")
	main.append_output("\n".join(lines) + "\n", false)

func _cmd_env_view() -> void:
	if main.env_viewer:
		main.env_viewer.open()
		main._env_viewer_mode = true

func _cmd_env_tasks(tm: EnvTaskManager, colors: Dictionary) -> void:
	main.append_output("\n" + tm.format_task_checklist(colors) + "\n", false)

func _cmd_env_exec_task(task_id: String, tm: EnvTaskManager, colors: Dictionary) -> void:
	var result: Dictionary = tm.begin_task(task_id)
	if not result.get("success", false):
		main.append_output("[color=" + T.error_hex + "]" + str(result.get("message", "任务执行失败")) + "[/color]\n", false)
		return
	var data: Dictionary = result.get("data", {})
	var tdef: Dictionary = tm.task_definitions.get(task_id, {})
	var task_type: String = str(tdef.get("type", ""))
	# 根据任务类型格式化输出
	match task_type:
		"inspection":
			main.append_output("\n" + tm.format_inspection_result(data, colors) + "\n\n", false)
		"recording":
			main.append_output("\n" + tm.format_recording_result(data, colors) + "\n\n", false)
		"maintenance":
			main.append_output("\n" + tm.format_calibration_result(data, colors) + "\n\n", false)
		"analysis":
			main.append_output("\n" + tm.format_anomaly_result(data, colors) + "\n\n", false)
		"report":
			main.append_output("\n" + tm.format_daily_report(data, colors) + "\n\n", false)
		_:
			main.append_output("[color=" + T.success_hex + "]任务完成: " + str(tdef.get("name", task_id)) + "[/color]\n", false)
	# 检查是否所有任务完成
	if tm.is_all_required_completed():
		main.append_output("[color=" + T.success_hex + "]所有必要任务已完成！关闭终端后再次启动将自动进入下一天。[/color]\n", false)
		# 任务完成后立即保存，防止退出后进度丢失
		if main.disc_mgr:
			main.disc_mgr._auto_save()

func _cmd_env_repair(em: EnvMonitor, sub_args: Array, colors: Dictionary) -> void:
	if sub_args.is_empty():
		# 列出所有非在线传感器
		var offline: Array = []
		for sid in em.sensors.keys():
			if em.sensor_status.get(sid, "online") != "online":
				var cfg: Dictionary = em.get_sensor_config(sid)
				offline.append({"id": sid, "name": str(cfg.get("name", sid)), "status": em.sensor_status[sid]})
		if offline.is_empty():
			main.append_output("[color=" + str(colors.get("success", "")) + "]所有传感器运行正常，无需修复。[/color]\n", false)
		else:
			main.append_output("[color=" + str(colors.get("warning", "")) + "]需要修复的传感器:[/color]\n", false)
			for s in offline:
				main.append_output("[color=" + str(colors.get("muted", "")) + "]  %s (%s) — %s[/color]\n" % [str(s["name"]), str(s["id"]), str(s["status"])], false)
			main.append_output("[color=" + str(colors.get("muted", "")) + "]使用: env repair <传感器id>[/color]\n", false)
		return
	var sid: String = str(sub_args[0])
	if not em.sensors.has(sid):
		main.append_output("[color=" + T.error_hex + "]未知传感器: " + sid + "[/color]\n", false)
		return
	if em.repair_sensor(sid):
		var cfg: Dictionary = em.get_sensor_config(sid)
		main.append_output("[color=" + T.success_hex + "]传感器 " + str(cfg.get("name", sid)) + " 已修复并重新上线。[/color]\n", false)
	else:
		main.append_output("[color=" + T.muted_hex + "]传感器已在线，无需修复。[/color]\n", false)

func _cmd_env_sensor(em: EnvMonitor, sub_args: Array, colors: Dictionary) -> void:
	if sub_args.is_empty():
		main.append_output("[color=" + T.muted_hex + "]用法: env sensor <传感器id>[/color]\n", false)
		main.append_output("[color=" + T.muted_hex + "]可用传感器:[/color]\n", false)
		for sid in em.sensors.keys():
			var cfg: Dictionary = em.get_sensor_config(sid)
			main.append_output("[color=" + T.muted_hex + "]  %-16s %s[/color]\n" % [sid, str(cfg.get("name", ""))], false)
		return
	var sid: String = str(sub_args[0])
	if not em.sensors.has(sid):
		main.append_output("[color=" + T.error_hex + "]未知传感器: " + sid + "[/color]\n", false)
		return
	var cfg: Dictionary = em.get_sensor_config(sid)
	var val: float = em.get_reading(sid)
	var status: String = em.sensor_status.get(sid, "unknown")
	var trend: String = em.get_sensor_trend(sid)
	var offset: float = em.calibration_offsets.get(sid, 0.0)
	var p: String = str(colors.get("primary", ""))
	var m: String = str(colors.get("muted", ""))
	var lines: Array = [
		"[color=%s]── 传感器详情: %s ──[/color]" % [p, str(cfg.get("name", sid))],
		"[color=%s]  ID:       %s[/color]" % [m, sid],
		"[color=%s]  型号:     %s[/color]" % [m, str(cfg.get("description", ""))],
		"[color=%s]  分类:     %s[/color]" % [m, str(cfg.get("category", ""))],
		"[color=%s]  当前值:   %s %s[/color]" % [p, "%.1f" % val if not is_nan(val) else "N/A", str(cfg.get("unit", ""))],
		"[color=%s]  状态:     %s[/color]" % [p if status == "online" else str(colors.get("error", "")), status],
		"[color=%s]  趋势:     %s[/color]" % [m, trend],
		"[color=%s]  校准偏移: %.3f[/color]" % [m, offset],
		"[color=%s]  量程:     %s[/color]" % [m, str(cfg.get("range", []))],
	]
	# 历史
	var history: Array = em.reading_history.get(sid, [])
	if history.size() > 0:
		lines.append("[color=%s]  最近读数:[/color]" % m)
		var show: int = mini(history.size(), 8)
		for i in range(history.size() - show, history.size()):
			var h: Dictionary = history[i]
			lines.append("[color=%s]    %05.1fh → %.1f[/color]" % [m, float(h.get("hour", 0)), float(h.get("value", 0))])
	main.append_output("\n".join(lines) + "\n\n", false)

func _cmd_env_weather(em: EnvMonitor, colors: Dictionary) -> void:
	var p: String = str(colors.get("primary", ""))
	var m: String = str(colors.get("muted", ""))
	var lines: Array = [
		"[color=%s]── 天气状况 ──[/color]" % p,
		"[color=%s]  当前天气: %s[/color]" % [p, em.get_weather_name()],
		"[color=%s]  气温:     %.1f°C[/color]" % [m, em.get_reading("air_temp")],
		"[color=%s]  体感温度: %.1f°C (风寒)[/color]" % [m, _calc_wind_chill(em.get_reading("air_temp"), em.get_reading("wind_speed"))],
		"[color=%s]  湿度:     %.0f%%[/color]" % [m, em.get_reading("humidity")],
		"[color=%s]  气压:     %.1f hPa (%s)[/color]" % [m, em.get_reading("pressure"), em.get_sensor_trend("pressure")],
		"[color=%s]  风速:     %.1f m/s[/color]" % [m, em.get_reading("wind_speed")],
		"[color=%s]  风向:     %s (%.0f°)[/color]" % [m, em.get_wind_direction_name(), em.current_wind_dir],
		"[color=%s]  能见度:   %.1f km[/color]" % [m, em.get_reading("visibility")],
		"[color=%s]  云量:     %d/8[/color]" % [m, roundi(em.get_reading("cloud_cover"))],
		"[color=%s]  降水:     %.1f mm/h[/color]" % [m, em.get_reading("precipitation")],
		"[color=%s]  光照:     %d lux[/color]" % [m, roundi(em.get_reading("light_level"))],
		"[color=%s]  紫外线:   %d[/color]" % [m, roundi(em.get_reading("uv_index"))],
	]
	# 蒲福风级
	var bft: int = _beaufort_scale(em.get_reading("wind_speed"))
	lines.append("[color=%s]  蒲福风级: %d 级[/color]" % [m, bft])
	main.append_output("\n".join(lines) + "\n\n", false)

func _cmd_env_events(em: EnvMonitor, colors: Dictionary) -> void:
	var p: String = str(colors.get("primary", ""))
	var m: String = str(colors.get("muted", ""))
	var w: String = str(colors.get("warning", ""))
	var e: String = str(colors.get("error", ""))
	var lines: Array = ["[color=%s]── 活跃事件 ──[/color]" % p]
	var events: Dictionary = em.get_active_events()
	if events.is_empty():
		lines.append("[color=%s]当前无活跃事件。[/color]" % m)
	else:
		for eid in events.keys():
			var evt: Dictionary = events[eid]
			var col: String = e if evt.get("scp_related", false) else w
			lines.append("[color=%s]  • %s[/color]" % [col, str(evt.get("name", eid))])
			lines.append("[color=%s]    持续: 第%d天 - 第%d天[/color]" % [m, int(evt.get("start_day", 0)), int(evt.get("end_day", 0))])
			if evt.get("scp_related", false):
				lines.append("[color=%s]    [SCP 相关事件][/color]" % e)
	# 待确认异常
	lines.append("\n[color=%s]── 异常记录 ──[/color]" % p)
	var anomalies: Array[Dictionary] = em.get_detected_anomalies()
	var pending: Array[Dictionary] = em.get_pending_anomalies()
	lines.append("[color=%s]  待确认: %d  已记录: %d[/color]" % [m, pending.size(), anomalies.size()])
	if pending.size() > 0:
		lines.append("[color=%s]  使用 env anomaly 进行异常检查。[/color]" % m)
	main.append_output("\n".join(lines) + "\n\n", false)

## 风寒温度计算 (Wind Chill Index)
func _calc_wind_chill(temp: float, wind: float) -> float:
	if temp > 10.0 or wind < 1.3:
		return temp
	var v: float = pow(wind * 3.6, 0.16)  # km/h 转换
	return 13.12 + 0.6215 * temp - 11.37 * v + 0.3965 * temp * v

## 蒲福风级
func _beaufort_scale(wind_speed: float) -> int:
	if wind_speed < 0.3: return 0
	if wind_speed < 1.6: return 1
	if wind_speed < 3.4: return 2
	if wind_speed < 5.5: return 3
	if wind_speed < 8.0: return 4
	if wind_speed < 10.8: return 5
	if wind_speed < 13.9: return 6
	if wind_speed < 17.2: return 7
	if wind_speed < 20.8: return 8
	if wind_speed < 24.5: return 9
	if wind_speed < 28.5: return 10
	if wind_speed < 32.7: return 11
	return 12

# ══════════════════════════════════════════
#  ★ 监控摄像头命令
# ══════════════════════════════════════════
func _cmd_camera(args: Array = []) -> void:
	if main.camera_mgr == null:
		main.append_output("[color=" + T.error_hex + "]监控摄像头系统未初始化。[/color]\n", false)
		return
	var cm: CameraManager = main.camera_mgr
	if not cm.has_cameras():
		main.append_output("[color=" + T.muted_hex + "]当前没有可用的摄像头。[/color]\n", false)
		return
	if args.is_empty():
		_cmd_camera_help()
		return
	var sub: String = str(args[0]).to_lower()
	var sub_args: Array = args.slice(1)
	match sub:
		"help", "?":
			_cmd_camera_help()
		"list", "ls":
			_cmd_camera_list(cm)
		"view", "v":
			_cmd_camera_view(cm, sub_args)
		"status", "s":
			_cmd_camera_status(cm)
		_:
			# 无子命令时尝试直接打开（camera view 简写）
			_cmd_camera_view(cm, args)

func _cmd_camera_help() -> void:
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var s: String = T.success_hex
	main.append_output("[color=" + p + "]════ CCTV 监控系统 ════[/color]\n", false)
	main.append_output("[color=" + s + "]camera list[/color]          [color=" + m + "]列出所有已解锁摄像头[/color]\n", false)
	main.append_output("[color=" + s + "]camera view [编号|ID][/color] [color=" + m + "]打开摄像头查看器[/color]\n", false)
	main.append_output("[color=" + s + "]camera status[/color]        [color=" + m + "]显示所有摄像头状态[/color]\n", false)
	main.append_output("[color=" + m + "]别名: cam, cctv[/color]\n", false)

func _cmd_camera_list(cm: CameraManager) -> void:
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var s: String = T.success_hex
	var e: String = T.error_hex
	var unlocked: Array[SecurityCameraFeed] = cm.get_unlocked_cameras()
	if unlocked.is_empty():
		main.append_output("[color=" + m + "]没有已解锁的摄像头。[/color]\n", false)
		return
	main.append_output("[color=" + p + "]════ 已解锁摄像头 (" + str(unlocked.size()) + ") ════[/color]\n", false)
	for i in range(unlocked.size()):
		var cam: SecurityCameraFeed = unlocked[i]
		var status_col: String = s if cam.online else e
		var status_icon: String = "●" if cam.online else "○"
		var status_word: String = "ONLINE" if cam.online else "OFFLINE"
		var sig: String = "  [" + str(int(cam.signal_quality * 100)) + "%]" if cam.online else ""
		var line: String = \
			"  [color=" + s + "]" + str(i + 1) + ".[/color]" \
			+ "  [b]" + cam.cam_name + "[/b]" \
			+ "  [color=" + m + "]" + cam.location + "[/color]" \
			+ "  [color=" + status_col + "]" + status_icon + " " + status_word + sig + "[/color]\n"
		main.append_output(line, false)
	main.append_output("[color=" + m + "]输入 camera view <编号> 打开查看器。[/color]\n", false)

func _cmd_camera_view(cm: CameraManager, sub_args: Array) -> void:
	var unlocked: Array[SecurityCameraFeed] = cm.get_unlocked_cameras()
	if unlocked.is_empty():
		main.append_output("[color=" + T.muted_hex + "]没有已解锁的摄像头。[/color]\n", false)
		return
	var target_id: String = ""
	if not sub_args.is_empty():
		var arg: String = str(sub_args[0])
		# 尝试编号
		if arg.is_valid_int():
			var idx: int = int(arg) - 1
			if idx >= 0 and idx < unlocked.size():
				target_id = unlocked[idx].id
			else:
				main.append_output("[color=" + T.error_hex + "]编号超出范围。可用: 1-%d[/color]\n" % unlocked.size(), false)
				return
		else:
			# 尝试 ID
			target_id = arg
	if main.camera_viewer:
		main.camera_viewer.open(target_id)
		main._camera_viewer_mode = true

func _cmd_camera_status(cm: CameraManager) -> void:
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var s: String = T.success_hex
	var e: String = T.error_hex
	var w: String = T.warning_hex
	var all_cams: Array[SecurityCameraFeed] = cm.get_all_cameras()
	main.append_output("[color=" + p + "]════ 摄像头系统状态 ════[/color]\n", false)
	main.append_output("[color=" + m + "]总计: %d  已解锁: %d[/color]\n" % [cm.get_camera_count(), cm.get_unlocked_count()], false)
	for cam in all_cams:
		var lock_str: String = "" if cam.unlocked else " [LOCKED]"
		var status_color: String = s if cam.online else e
		var status_text: String = "ONLINE" if cam.online else "OFFLINE"
		var anom_str: String = " [color=" + w + "]! ANOMALY[/color]" if cam.is_anomaly_active() else ""
		main.append_output("  [color=" + status_color + "]%s[/color] %s [color=" + m + "]%s[/color]%s%s\n" % [
			status_text, cam.cam_name, cam.location, lock_str, anom_str
		], false)


# ══════════════════════════════════════════
#  调试命令组（debug <子命令>）
# ══════════════════════════════════════════

func _cmd_debug(args: Array = []) -> void:
	var e: String = T.error_hex
	var w: String = T.warning_hex
	if args.is_empty():
		_debug_print_help()
		return
	var sub: String = args[0].to_lower()
	var rest: Array = []
	for i in range(1, args.size()):
		rest.append(args[i])
	match sub:
		# ── 登录/用户 ──
		"skip_login":     _debug_skip_login()
		"logout":         _debug_logout()
		"users":          _debug_users()
		"deluser":        _debug_dispatch1(rest, "deluser <name>", _debug_deluser)
		# ── 剧情/对话 ──
		"jump_day0":      _debug_jump_day0()
		"reset_progress": _debug_reset_progress()
		"list_dialogues": _debug_list_dialogues()
		"dlg_status":     _debug_dispatch1(rest, "dlg_status <id>", _debug_dialogue_status)
		"trigger":        _debug_dispatch1(rest, "trigger <id>", _debug_trigger_dialogue)
		"trigger_call":   _debug_dispatch1(rest, "trigger_call <id> (forced/answerable)", _debug_trigger_call)
		"complete_dlg":   _debug_dispatch1(rest, "complete_dlg <id>", _debug_complete_dialogue)
		"reset_dlg":      _debug_dispatch1(rest, "reset_dlg <id>", _debug_reset_dialogue)
		# ── 剧情变量 ──
		"set_flag":       _debug_dispatch2(rest, "set_flag <name> <value>", _debug_set_flag)
		"get_flag":       _debug_dispatch1(rest, "get_flag <name>", _debug_get_flag)
		"list_flags":     _debug_list_flags()
		"reset_flags":    _debug_reset_flags()
		"set_choice":     _debug_dispatch2(rest, "set_choice <id> <value>", _debug_set_choice)
		"get_choice":     _debug_dispatch1(rest, "get_choice <id>", _debug_get_choice)
		# ── 环境/任务 ──
		"complete_env":   _debug_complete_env()
		"complete_task":  _debug_dispatch1(rest, "complete_task <task_id>", _debug_complete_task)
		"advance_day":    _debug_advance_day()
		"set_reading":    _debug_dispatch2(rest, "set_reading <sensor_id> <value>", _debug_set_reading)
		"force_event":    _debug_dispatch1(rest, "force_event <event_id>", _debug_force_event)
		"set_anomaly":    _debug_dispatch2(rest, "set_anomaly <id> <level 0-4>", _debug_set_anomaly_int)
		"env_status":     _debug_env_status()
		"env":            _debug_env_preview(rest)
		# ── 邮件 ──
		"deliver":        _debug_dispatch1(rest, "deliver <mail_id>", _debug_deliver_mail)
		"clear_mail":     _debug_clear_mail()
		"list_mail":      _debug_list_mail()
		# ── 绩效 ──
		"perf_add":       _debug_dispatch2(rest, "perf_add <main|daily|side> <n>", _debug_perf_add_str)
		"perf_status":    _debug_perf_status()
		"perf_settle":    _debug_perf_settle()
		# ── 摄像头 ──
		"unlock_cam":     _debug_dispatch1(rest, "unlock_cam <cam_id>", _debug_unlock_cam)
		"lock_cam":       _debug_dispatch1(rest, "lock_cam <cam_id>", _debug_lock_cam)
		"list_cameras":   _debug_list_cameras()
		"cam_anomaly":    _debug_dispatch2(rest, "cam_anomaly <cam_id> <anomaly_id>", _debug_cam_anomaly)
		# ── 特效 ──
		"glitch":         _debug_glitch(rest)
		"shake":          _debug_shake(rest)
		"tear":           _debug_tear(rest)
		"noise":          _debug_noise(rest)
		"blackout":       _debug_blackout(rest)
		"reboot_fx":      _debug_reboot_fx()
		"reset_fx":       _debug_reset_fx()
		# ── 无线电 ──
		"radio":          _debug_radio(rest)
		"vdisc":          await _debug_vdisc(rest)
		"voice":          _debug_voice()
		"voice_meeting":  _debug_voice_meeting(rest)
		# ── 系统 ──
		"skip_boot":      _debug_skip_boot()
		"status":         _debug_status()
		"saves":          _debug_saves()
		"delsave":        _debug_dispatch1(rest, "delsave <story_id>", _debug_delsave)
		"set":            _debug_dispatch2(rest, "set <key> <value>", _debug_settings_set)
		"get":            _debug_dispatch1(rest, "get <key>", _debug_settings_get)
		_:
			main.append_output("[color=" + e + "]未知 debug 子命令: %s[/color]\n" % sub, false)
			_debug_print_help()

func _debug_dispatch1(rest: Array, usage: String, fn: Callable) -> void:
	if rest.size() >= 1:
		fn.call(rest[0])
	else:
		_debug_err("用法: debug %s" % usage)

func _debug_dispatch2(rest: Array, usage: String, fn: Callable) -> void:
	if rest.size() >= 2:
		fn.call(rest[0], rest[1])
	else:
		_debug_err("用法: debug %s" % usage)

func _debug_set_anomaly_int(anomaly_id: String, level_str: String) -> void:
	_debug_set_anomaly(anomaly_id, int(level_str))

func _debug_perf_add_str(ptype: String, amount_str: String) -> void:
	_debug_perf_add(ptype, int(amount_str))

func _debug_print_help() -> void:
	var h: String = T.primary_hex
	var m: String = T.muted_hex
	main.append_output("[color=" + h + "]════ 调试模式（debug 114514 已激活）════[/color]\n", false)
	main.append_output("[color=" + m + "]格式: debug 114514 <子命令> [参数...]（以下省略前缀）[/color]\n", false)
	var groups: Array = [
		["登录/用户", [
			["skip_login",       "自动创建/登录 test 用户并进入桌面"],
			["logout",            "登出当前用户"],
			["users",             "列出所有用户"],
			["deluser <name>",    "删除用户"],
		]],
		["剧情/对话", [
			["jump_day0",         "触发 Day0 教程流程"],
			["reset_progress",    "清空剧情进度（对话/选择/标记）"],
			["list_dialogues",    "列出所有对话及完成状态"],
			["dlg_status <id>",   "查看指定对话状态"],
			["trigger <id>",       "静默触发对话"],
			["trigger_call <id>",  "以来电方式触发（forced/answerable）"],
			["complete_dlg <id>", "标记对话完成"],
			["reset_dlg <id>",    "清除对话完成标记"],
		]],
		["剧情变量", [
			["set_flag <n> <v>",  "设置标记（支持 int/float/bool/str）"],
			["get_flag <n>",      "查看标记"],
			["list_flags",        "列出所有标记"],
			["reset_flags",       "清空所有标记"],
			["set_choice <n> <v>","设置选择"],
			["get_choice <n>",    "查看选择"],
		]],
		["环境/任务", [
			["complete_env",      "所有任务完成 + 提交日报"],
			["complete_task <id>","标记指定任务完成"],
			["advance_day",       "推进一天"],
			["set_reading <s> <v>","设置传感器读数"],
			["force_event <id>",  "强制启动事件"],
			["set_anomaly <id> <l>","设置异常等级(0-4)"],
			["env_status",        "环境系统状态"],
			["env normal/device/mystery/sea/clear", "观测台隔离预览（不保存、不计分）"],
		]],
		["邮件", [
			["deliver <id>",      "投递邮件"],
			["clear_mail",        "清空收件箱"],
			["list_mail",         "列出邮件"],
		]],
		["Vdisc", [
			["vdisc list",        "列出任务状态"],
			["vdisc mail",        "投递联调附件邮件"],
			["vdisc give <id>",   "领取任务盘"],
			["vdisc check",       "检查当前盘上交条件"],
		]],
		["绩效", [
			["perf_add <t> <n>",  "加分(main/daily/side)"],
			["perf_status",       "绩效状态"],
			["perf_settle",       "结算当日"],
		]],
		["摄像头", [
			["unlock_cam <id>",   "解锁摄像头"],
			["lock_cam <id>",     "锁定摄像头"],
			["list_cameras",      "列出摄像头"],
			["cam_anomaly <c> <a>","触发摄像头异常"],
		]],
		["特效", [
			["glitch [i] [d]",    "故障效果"],
			["shake [i] [d]",     "抖屏"],
			["tear [s] [d]",      "撕裂"],
			["noise [i] [d]",     "噪点"],
			["blackout [d]",      "黑屏"],
			["reboot_fx",         "重启动画"],
			["reset_fx",          "清除所有特效"],
		]],
		["无线电", [
			["radio test",        "进入无线电演示模式（注入全套测试信号）"],
			["radio clean",       "移除测试信号（恢复真实信号）"],
			["radio list",        "列出当前所有信号"],
		]],
		["系统", [
			["voice",             "打开角色实时调音面板（编辑器）"],
			["voice_meeting [角色ID...]", "自动播放多人会议音色演示"],
			["skip_boot",         "跳过开机动画"],
			["status",            "调试系统状态总览"],
			["saves",             "列出存档"],
			["delsave <id>",      "删除存档"],
			["set <key> <val>",   "设置项"],
			["get <key>",         "读取设置项"],
		]],
	]
	for grp in groups:
		var gname: String = grp[0]
		var cmds: Array = grp[1]
		main.append_output("[color=" + h + "]【%s】[/color]\n" % gname, false)
		for c in cmds:
			main.append_output("[color=" + m + "]  %-20s %s[/color]\n" % [c[0], c[1]], false)

func _debug_err(msg: String) -> void:
	main.append_output("[color=" + T.error_hex + "]%s[/color]\n" % msg, false)

func _debug_ok(msg: String) -> void:
	main.append_output("[color=" + T.success_hex + "]%s[/color]\n" % msg, false)

# ── 登录/用户 ──

func _debug_skip_login() -> void:
	if not main or not main.user_mgr:
		_debug_err("user_mgr 未就绪"); return
	if main.user_mgr.is_logged_in:
		_debug_ok("已登录: %s" % main.user_mgr.get_username()); return
	var uname: String = "test"
	var pwd: String = "test"
	if not main.user_mgr.user_exists(uname):
		var extra := {"nickname": "Test", "gender": "1", "birthday": "2000-01-01"}
		var r: Dictionary = main.user_mgr.register(uname, pwd, extra)
		if not r.get("success", false):
			_debug_err("创建失败: %s" % str(r.get("message", ""))); return
		_debug_ok("已创建测试用户: %s" % uname)
	var r2: Dictionary = main.user_mgr.login(uname, pwd)
	if r2.get("success", false):
		_debug_ok("已登录: %s" % uname)
		main._enter_desktop_after_login("调试登录完成")
	else:
		_debug_err("登录失败: %s" % str(r2.get("message", "")))

func _debug_logout() -> void:
	if main and main.user_mgr and main.user_mgr.is_logged_in:
		main.perform_logout()
		_debug_ok("已登出")
	else:
		_debug_err("未登录")

func _debug_users() -> void:
	if not main or not main.user_mgr:
		_debug_err("user_mgr 未就绪"); return
	var users: Array[String] = main.user_mgr.get_all_users()
	var m: String = T.muted_hex
	main.append_output("[color=" + T.primary_hex + "]════ 用户列表 ════[/color]\n", false)
	if users.is_empty():
		main.append_output("[color=" + m + "]  (无)[/color]\n", false)
	for u in users:
		var cur: String = " ← 当前" if (main.user_mgr.is_logged_in and main.user_mgr.get_username() == u) else ""
		main.append_output("[color=" + m + "]  %s%s[/color]\n" % [u, cur], false)

func _debug_deluser(name: String) -> void:
	if not main or not main.user_mgr:
		_debug_err("user_mgr 未就绪"); return
	var r: Dictionary = main.user_mgr.delete_user(name)
	if r.get("success", false):
		_debug_ok("已删除用户: %s" % name)
	else:
		_debug_err(str(r.get("message", "删除失败")))

# ── 剧情/对话 ──

func _debug_jump_day0() -> void:
	if not main or not main.user_mgr or not main.user_mgr.is_logged_in:
		_debug_err("需先登录（debug skip_login）"); return
	if main.daily_dialogue_mgr:
		main.daily_dialogue_mgr.trigger_day_start(0)
		_debug_ok("Day0 教程已触发")
	else:
		_debug_err("daily_dialogue_mgr 未就绪")

func _debug_reset_progress() -> void:
	if not main or not main.daily_dialogue_mgr:
		_debug_err("daily_dialogue_mgr 未就绪"); return
	var dm = main.daily_dialogue_mgr
	dm._completed_dialogues.clear()
	dm._story_choices.clear()
	dm._story_flags.clear()
	dm._ensure_default_flags()
	dm.save_story_save()
	_debug_ok("剧情进度已重置（对话/选择/标记）")

func _debug_list_dialogues() -> void:
	if not main or not main.comm_mgr:
		_debug_err("comm_mgr 未就绪"); return
	var ids: Array[String] = main.comm_mgr.get_dialogue_ids()
	var m: String = T.muted_hex
	var s: String = T.success_hex
	var w: String = T.warning_hex
	main.append_output("[color=" + T.primary_hex + "]════ 对话列表 (%d) ════[/color]\n" % ids.size(), false)
	for id in ids:
		var done: bool = main.comm_mgr.is_dialogue_completed(id)
		var mark: String = "[color=" + s + "]✓[/color]" if done else "[color=" + w + "]○[/color]"
		var data: Dictionary = main.comm_mgr.get_dialogue_data(id)
		var title: String = str(data.get("title", ""))
		var callable: bool = bool(data.get("callable", false))
		var call_tag: String = " [拨号]" if callable else ""
		var cm: String = str(data.get("call_mode", ""))
		var cm_tag: String = " [" + cm + "]" if not cm.is_empty() and cm != "silent" else ""
		main.append_output("[color=" + m + "]  %s %-18s %s%s%s[/color]\n" % [mark, id, title, call_tag, cm_tag], false)

func _debug_dialogue_status(id: String) -> void:
	if not main or not main.comm_mgr:
		_debug_err("comm_mgr 未就绪"); return
	if not main.comm_mgr.has_dialogue(id):
		_debug_err("对话不存在: %s" % id); return
	var data: Dictionary = main.comm_mgr.get_dialogue_data(id)
	var done: bool = main.comm_mgr.is_dialogue_completed(id)
	var m: String = T.muted_hex
	main.append_output("[color=" + T.primary_hex + "]对话: %s[/color]\n" % id, false)
	main.append_output("[color=" + m + "]  标题: %s[/color]\n" % str(data.get("title", "")), false)
	main.append_output("[color=" + m + "]  完成: %s[/color]\n" % ("是" if done else "否"), false)
	main.append_output("[color=" + m + "]  可拨号: %s[/color]\n" % str(data.get("callable", false)), false)
	main.append_output("[color=" + m + "]  来电模式: %s[/color]\n" % str(data.get("call_mode", "silent")), false)
	main.append_output("[color=" + m + "]  可重复: %s[/color]\n" % str(data.get("repeatable", false)), false)
	if data.has("requires_flag"):
		main.append_output("[color=" + m + "]  requires_flag: %s[/color]\n" % str(data["requires_flag"]), false)
	if data.has("requires_tasks"):
		main.append_output("[color=" + m + "]  requires_tasks: %s[/color]\n" % str(data["requires_tasks"]), false)
	if data.has("next"):
		main.append_output("[color=" + m + "]  next: %s[/color]\n" % str(data["next"]), false)
	var lines: Array = data.get("lines", [])
	main.append_output("[color=" + m + "]  行数: %d[/color]\n" % lines.size(), false)

func _debug_trigger_dialogue(id: String) -> void:
	if not main or not main.comm_mgr:
		_debug_err("comm_mgr 未就绪"); return
	if not main.comm_mgr._dialogues.has(id):
		_debug_err("对话不存在: %s" % id); return
	main.comm_mgr.trigger_dialogue(id, true)
	_debug_ok("已触发对话: %s" % id)

func _debug_trigger_call(id: String) -> void:
	if not main or not main.comm_mgr:
		_debug_err("comm_mgr 未就绪"); return
	var mode: String = "forced"
	if id.find(":") > 0:
		var parts: PackedStringArray = id.split(":", false)
		id = parts[0]
		if parts.size() > 1:
			mode = parts[1]
	var action: String = "comm:%s:%s" % [id, mode]
	if main.comm_mgr.handle_trigger_action(action):
		_debug_ok("已触发来电: %s (mode=%s)" % [id, mode])
	else:
		_debug_err("触发失败（对话不存在或模式无效）: %s" % action)

func _debug_complete_dialogue(id: String) -> void:
	if not main or not main.daily_dialogue_mgr:
		_debug_err("daily_dialogue_mgr 未就绪"); return
	main.daily_dialogue_mgr.mark_dialogue_completed(id)
	if main.comm_mgr and main.comm_mgr._completed_dialogues != null:
		main.comm_mgr._completed_dialogues[id] = true
	_debug_ok("已标记对话完成: %s" % id)

func _debug_reset_dialogue(id: String) -> void:
	if not main or not main.daily_dialogue_mgr:
		_debug_err("daily_dialogue_mgr 未就绪"); return
	main.daily_dialogue_mgr._completed_dialogues.erase(id)
	if main.comm_mgr and main.comm_mgr._completed_dialogues != null:
		main.comm_mgr._completed_dialogues.erase(id)
	_debug_ok("已清除对话完成标记: %s" % id)

# ── 剧情变量 ──

func _debug_parse_value(value: String) -> Variant:
	if value.is_valid_int():
		return int(value)
	elif value.is_valid_float():
		return float(value)
	elif value.to_lower() == "true":
		return true
	elif value.to_lower() == "false":
		return false
	return value

func _debug_set_flag(name: String, value: String) -> void:
	if not main or not main.daily_dialogue_mgr:
		_debug_err("daily_dialogue_mgr 未就绪"); return
	var v: Variant = _debug_parse_value(value)
	main.daily_dialogue_mgr.set_flag(name, v)
	_debug_ok("flag %s = %s" % [name, str(v)])

func _debug_get_flag(name: String) -> void:
	if not main or not main.daily_dialogue_mgr:
		_debug_err("daily_dialogue_mgr 未就绪"); return
	var val = main.daily_dialogue_mgr.get_flag(name, "未设置")
	main.append_output("[color=" + T.primary_hex + "]flag %s = %s[/color]\n" % [name, str(val)], false)

func _debug_list_flags() -> void:
	if not main or not main.daily_dialogue_mgr:
		_debug_err("daily_dialogue_mgr 未就绪"); return
	var flags: Dictionary = main.daily_dialogue_mgr._story_flags
	var m: String = T.muted_hex
	main.append_output("[color=" + T.primary_hex + "]════ 剧情标记 (%d) ════[/color]\n" % flags.size(), false)
	if flags.is_empty():
		main.append_output("[color=" + m + "]  (无)[/color]\n", false)
	for k in flags.keys():
		main.append_output("[color=" + m + "]  %-24s = %s[/color]\n" % [k, str(flags[k])], false)

func _debug_reset_flags() -> void:
	if not main or not main.daily_dialogue_mgr:
		_debug_err("daily_dialogue_mgr 未就绪"); return
	main.daily_dialogue_mgr._story_flags.clear()
	main.daily_dialogue_mgr._ensure_default_flags()
	main.daily_dialogue_mgr.save_story_save()
	_debug_ok("所有标记已重置为初始值")

func _debug_set_choice(id: String, value: String) -> void:
	if not main or not main.daily_dialogue_mgr:
		_debug_err("daily_dialogue_mgr 未就绪"); return
	main.daily_dialogue_mgr.record_choice(id, value)
	_debug_ok("choice %s = %s" % [id, value])

func _debug_get_choice(id: String) -> void:
	if not main or not main.daily_dialogue_mgr:
		_debug_err("daily_dialogue_mgr 未就绪"); return
	if main.daily_dialogue_mgr.has_choice(id):
		var val: String = main.daily_dialogue_mgr.get_choice(id)
		main.append_output("[color=" + T.primary_hex + "]choice %s = %s[/color]\n" % [id, val], false)
	else:
		main.append_output("[color=" + T.warning_hex + "]choice %s 未设置[/color]\n" % id, false)

# ── 环境/任务 ──

func _debug_complete_env() -> void:
	if not main or not main.env_task_mgr:
		_debug_err("env_task_mgr 未就绪"); return
	var tm = main.env_task_mgr
	for tid in tm.task_definitions.keys():
		tm.task_status[tid] = "completed"
	tm.report_submitted = true
	_debug_ok("所有环境任务完成 + 日报已提交")

func _debug_complete_task(task_id: String) -> void:
	if not main or not main.env_task_mgr:
		_debug_err("env_task_mgr 未就绪"); return
	if not main.env_task_mgr.task_definitions.has(task_id):
		_debug_err("任务不存在: %s" % task_id); return
	main.env_task_mgr.complete_task(task_id, {})
	_debug_ok("任务完成: %s" % task_id)

func _debug_advance_day() -> void:
	if not main or not main.env_monitor:
		_debug_err("env_monitor 未就绪"); return
	main.env_monitor.advance_day()
	if main.env_task_mgr:
		main.env_task_mgr.reset_for_new_day()
	_debug_ok("已推进一天 (day=%d)" % main.env_monitor.current_day)

func _debug_set_reading(sensor_id: String, value: String) -> void:
	if not main or not main.env_monitor:
		_debug_err("env_monitor 未就绪"); return
	var v: float = float(value)
	main.env_monitor.current_readings[sensor_id] = v
	_debug_ok("传感器 %s = %s" % [sensor_id, str(v)])

func _debug_force_event(event_id: String) -> void:
	if not main or not main.env_monitor:
		_debug_err("env_monitor 未就绪"); return
	main.env_monitor.force_start_event(event_id)
	_debug_ok("已强制启动事件: %s" % event_id)

func _debug_set_anomaly(anomaly_id: String, level: int) -> void:
	if not main or not main.env_monitor:
		_debug_err("env_monitor 未就绪"); return
	main.env_monitor.set_anomaly_level(anomaly_id, level)
	_debug_ok("异常 %s 等级 = %d" % [anomaly_id, level])

func _debug_env_preview(rest: Array) -> void:
	var scenario: String = str(rest[0]).to_lower() if not rest.is_empty() else "normal"
	if scenario not in ["normal", "device", "mystery", "sea", "clear"]:
		_debug_err("用法：debug 114514 env normal/device/mystery/sea/clear")
		return
	main.env_observation.set_preview(scenario)
	_cmd_env_view()
	if scenario == "sea":
		main.env_viewer.perform_action("sea")

func _debug_env_status() -> void:
	if not main or not main.env_monitor:
		_debug_err("env_monitor 未就绪"); return
	var em = main.env_monitor
	var m: String = T.muted_hex
	main.append_output("[color=" + T.primary_hex + "]════ 环境状态 ════[/color]\n", false)
	main.append_output("[color=" + m + "]  当前天数: %d[/color]\n" % em.current_day, false)
	main.append_output("[color=" + m + "]  当前时间: %s[/color]\n" % em.get_current_hour_display(), false)
	main.append_output("[color=" + m + "]  天气: %s[/color]\n" % em.get_weather_name(), false)
	if main.env_task_mgr:
		var tm = main.env_task_mgr
		main.append_output("[color=" + m + "]  必做任务完成: %s[/color]\n" % ("是" if tm.is_all_required_completed() else "否"), false)
		main.append_output("[color=" + m + "]  日报提交: %s[/color]\n" % ("是" if tm.report_submitted else "否"), false)
		var progress: Dictionary = tm.get_progress()
		main.append_output("[color=" + m + "]  任务进度: %d/%d[/color]\n" % [int(progress.get("completed", 0)), int(progress.get("total", 0))], false)

# ── 邮件 ──

func _debug_deliver_mail(mail_id: String) -> void:
	if not main or not main.mail_sys:
		_debug_err("mail_sys 未就绪"); return
	main.mail_sys.deliver_mail(mail_id)
	_debug_ok("已投递邮件: %s" % mail_id)

func _debug_clear_mail() -> void:
	if not main or not main.mail_sys:
		_debug_err("mail_sys 未就绪"); return
	main.mail_sys.clear_all()
	_debug_ok("收件箱已清空")

func _debug_list_mail() -> void:
	if not main or not main.mail_sys:
		_debug_err("mail_sys 未就绪"); return
	var ms = main.mail_sys
	var m: String = T.muted_hex
	var total: int = ms.get_total_count()
	var unread: int = ms.get_unread_count()
	main.append_output("[color=" + T.primary_hex + "]════ 邮件 (%d 封, %d 未读) ════[/color]\n" % [total, unread], false)
	var inbox: Array = []
	if ms.get("_merged_inbox") != null:
		inbox = ms._merged_inbox
	for i in range(inbox.size()):
		var mail: Dictionary = inbox[i] if inbox[i] is Dictionary else {}
		var tag: String = "[T]" if not bool(mail.get("persistent", false)) else "[G]"
		var rd: String = "" if bool(mail.get("read", false)) else " *"
		main.append_output("[color=" + m + "]  %s %s %s%s[/color]\n" % [tag, str(mail.get("id", "?")), str(mail.get("title", "")), rd], false)

# ── 绩效 ──

func _debug_perf_add(ptype: String, amount: int) -> void:
	if not main or not main.perf_mgr:
		_debug_err("perf_mgr 未就绪"); return
	match ptype.to_lower():
		"main":   main.perf_mgr.add_score(amount, "main")
		"daily":  main.perf_mgr.add_score(amount, "daily")
		"side":   main.perf_mgr.add_score(amount, "side")
		_: _debug_err("类型需为 main/daily/side"); return
	_debug_ok("绩效 %s +%d" % [ptype, amount])

func _debug_perf_status() -> void:
	if not main or not main.perf_mgr:
		_debug_err("perf_mgr 未就绪"); return
	var pm = main.perf_mgr
	var m: String = T.muted_hex
	var summary: Dictionary = pm.get_career_summary()
	main.append_output("[color=" + T.primary_hex + "]════ 绩效状态 ════[/color]\n", false)
	main.append_output("[color=" + m + "]  生涯总分: %d[/color]\n" % int(summary.get("total", pm.career_total)), false)
	main.append_output("[color=" + m + "]  主线: %d  日常: %d  支线: %d[/color]\n" % [pm.career_main, pm.career_daily, pm.career_side], false)
	main.append_output("[color=" + m + "]  当日配额: %d[/color]\n" % pm.daily_quota, false)
	var day_sum: Dictionary = pm.get_day_summary()
	main.append_output("[color=" + m + "]  当日得分: %s[/color]\n" % str(day_sum), false)
	main.append_output("[color=" + m + "]  警告次数: %d  连续缺口: %d[/color]\n" % [pm.warnings_issued, pm.consecutive_low_days], false)

func _debug_perf_settle() -> void:
	if not main or not main.perf_mgr:
		_debug_err("perf_mgr 未就绪"); return
	var day: int = main.env_monitor.current_day if main.env_monitor else 0
	main.perf_mgr.settle_day(day)
	_debug_ok("已结算第 %d 天绩效" % day)

# ── 摄像头 ──

func _debug_unlock_cam(cam_id: String) -> void:
	if not main or not main.camera_mgr:
		_debug_err("camera_mgr 未就绪"); return
	main.camera_mgr.unlock_camera(cam_id)
	_debug_ok("已解锁摄像头: %s" % cam_id)

func _debug_lock_cam(cam_id: String) -> void:
	if not main or not main.camera_mgr:
		_debug_err("camera_mgr 未就绪"); return
	main.camera_mgr.lock_camera(cam_id)
	_debug_ok("已锁定摄像头: %s" % cam_id)

func _debug_list_cameras() -> void:
	if not main or not main.camera_mgr:
		_debug_err("camera_mgr 未就绪"); return
	var cm = main.camera_mgr
	var m: String = T.muted_hex
	var cams: Array = cm.get_all_cameras()
	main.append_output("[color=" + T.primary_hex + "]════ 摄像头 (%d, 已解锁 %d) ════[/color]\n" % [cm.get_camera_count(), cm.get_unlocked_count()], false)
	for cam in cams:
		var lock: String = " [LOCKED]" if not cam.unlocked else ""
		var st: String = "ONLINE" if cam.online else "OFFLINE"
		main.append_output("[color=" + m + "]  %s  %s  %s%s[/color]\n" % [st, cam.cam_name, cam.location, lock], false)

func _debug_cam_anomaly(cam_id: String, anomaly_id: String) -> void:
	if not main or not main.camera_mgr:
		_debug_err("camera_mgr 未就绪"); return
	main.camera_mgr.trigger_anomaly(cam_id, anomaly_id)
	_debug_ok("已触发摄像头异常: %s -> %s" % [cam_id, anomaly_id])

# ── 特效 ──

func _debug_glitch(args: Array) -> void:
	if not main: return
	var intensity: float = float(args[0]) if args.size() > 0 and args[0].is_valid_float() else 0.5
	var duration: float = float(args[1]) if args.size() > 1 and args[1].is_valid_float() else 1.0
	main.trigger_glitch(intensity, duration)
	_debug_ok("glitch(%.2f, %.2f)" % [intensity, duration])

func _debug_shake(args: Array) -> void:
	if not main: return
	var intensity: float = float(args[0]) if args.size() > 0 and args[0].is_valid_float() else 0.01
	var duration: float = float(args[1]) if args.size() > 1 and args[1].is_valid_float() else 0.5
	main.trigger_shake(intensity, duration)
	_debug_ok("shake(%.3f, %.2f)" % [intensity, duration])

func _debug_tear(args: Array) -> void:
	if not main: return
	var strength: float = float(args[0]) if args.size() > 0 and args[0].is_valid_float() else 0.08
	var duration: float = float(args[1]) if args.size() > 1 and args[1].is_valid_float() else 0.5
	main.trigger_tear(strength, duration)
	_debug_ok("tear(%.3f, %.2f)" % [strength, duration])

func _debug_noise(args: Array) -> void:
	if not main: return
	var intensity: float = float(args[0]) if args.size() > 0 and args[0].is_valid_float() else 0.8
	var duration: float = float(args[1]) if args.size() > 1 and args[1].is_valid_float() else 0.3
	main.trigger_noise_burst(intensity, duration)
	_debug_ok("noise(%.2f, %.2f)" % [intensity, duration])

func _debug_blackout(args: Array) -> void:
	if not main: return
	var duration: float = float(args[0]) if args.size() > 0 and args[0].is_valid_float() else 2.0
	main.trigger_screen_off(duration)
	_debug_ok("blackout(%.2f)" % duration)

func _debug_reboot_fx() -> void:
	if not main or not main.crt_shader: return
	main.crt_shader.play_reboot()
	_debug_ok("重启动画播放中")

func _debug_reset_fx() -> void:
	if not main or not main.crt_shader: return
	main.crt_shader.reset_all_effects()
	_debug_ok("所有特效已清除")

# ── 无线电 ──

func _debug_radio(args: Array) -> void:
	if args.is_empty():
		_debug_err("用法: debug radio <test|clean|list>")
		return
	match str(args[0]).to_lower():
		"test":  _debug_radio_test()
		"clean": _debug_radio_clean()
		"list":  _debug_radio_list()
		_: _debug_err("未知 radio 子命令: %s（可用: test / clean / list）" % str(args[0]))

## 从 res:// 读取二进制素材
func _debug_radio_read_bytes(res_path: String) -> PackedByteArray:
	if not FileAccess.file_exists(res_path):
		return PackedByteArray()
	var fa := FileAccess.open(res_path, FileAccess.READ)
	if fa == null:
		return PackedByteArray()
	var bytes: PackedByteArray = fa.get_buffer(fa.get_length())
	fa.close()
	return bytes

## 构造测试信号
func _debug_radio_make_signal(id: String, type: String, band: String, freq: float,
		label: String, hint: String, opts: Dictionary = {}) -> RadioConfigParser.RadioSignal:
	var sig := RadioConfigParser.RadioSignal.new()
	sig.id = id
	sig.type = type
	sig.band = band
	sig.frequency = freq
	sig.label = label
	sig.hint = hint
	sig.azimuth = float(opts.get("azimuth", 0.0))
	sig.elevation = float(opts.get("elevation", 15.0))
	sig.tolerance_freq = float(opts.get("tolerance_freq", 0.05))
	sig.tolerance_dir = int(opts.get("tolerance_dir", 45))
	sig.proximity_range = float(opts.get("proximity_range", 0.15))
	sig.loop = bool(opts.get("loop", true))
	sig.speed_wpm = int(opts.get("speed_wpm", 15))
	sig.hidden = bool(opts.get("hidden", false))
	if opts.has("content_text"): sig.content_text = str(opts["content_text"])
	if opts.has("character_set"): sig.character_set = str(opts["character_set"])
	if opts.has("group_size"): sig.group_size = int(opts["group_size"])
	if opts.has("group_pause_ms"): sig.group_pause_ms = float(opts["group_pause_ms"])
	if opts.has("repeat_count"): sig.repeat_count = int(opts["repeat_count"])
	if opts.has("beacon_id"): sig.beacon_id = str(opts["beacon_id"])
	if opts.has("cipher_type"): sig.cipher_type = str(opts["cipher_type"])
	if opts.has("sstv_mode"): sig.sstv_mode = str(opts["sstv_mode"])
	if opts.has("transmit_duration"): sig.transmit_duration = float(opts["transmit_duration"])
	if opts.has("content_file"): sig.content_file = str(opts["content_file"])
	if opts.has("content_image"): sig.content_image = opts["content_image"]
	if opts.has("content_audio"): sig.content_audio = opts["content_audio"]
	return sig

## 进入无线电演示模式：注入全套测试信号并打开界面
func _debug_radio_test() -> void:
	if not main or not main.radio_receiver:
		_debug_err("radio_receiver 未就绪"); return
	if not main._desktop_mode:
		_debug_err("需在桌面模式（radio 仅桌面模式可用）"); return
	var rr = main.radio_receiver
	var mgr = rr.signal_mgr
	if mgr == null:
		_debug_err("signal_mgr 未就绪"); return

	# 1) 清理旧测试信号（幂等，可反复执行）
	_debug_radio_clean(true)
	# 2) 载入真实信号（保留 S-00 等）
	rr.load_local_signals()
	# 3) 准备素材
	var sstv_img: PackedByteArray = _debug_radio_read_bytes("res://data/main/cameras/camera_test_main.jpg")
	var audio_bytes: PackedByteArray = _debug_radio_read_bytes("res://audio/startup.mp3")

	# 4) 测试信号定义：[id, type, band, freq, label, hint, opts]
	var defs: Array = [
		["_test_morse_std", "morse", "HF", 7.100, "[测试] 标准摩斯电码",
			"清晰的电键声，像有人在反复呼号",
			{"content_text": "CQ CQ CQ DE SCRT READER TEST SIGNAL", "speed_wpm": 15}],
		["_test_morse_num", "morse", "HF", 5.200, "[测试] 数字电台",
			"机械的数字播报，五码一组，间隔均匀",
			{"content_text": "31415 92653 58979 32384 62643", "character_set": "numbers", "speed_wpm": 12}],
		["_test_beacon", "morse", "HF", 14.100, "[测试] 信标电台",
			"持续重复的呼号，按 L 查看信标日志",
			{"content_text": "VVV DE SCRT TEST BEACON", "beacon_id": "VVV DE SCRT", "speed_wpm": 10}],
		["_test_hidden", "morse", "HF", 9.800, "[测试] 隐藏信号",
			"不在雷达/标尺/瀑布图上标注，需手动调谐寻找",
			{"content_text": "YOU FOUND THE HIDDEN SIGNAL", "hidden": true}],
		["_test_cipher", "morse", "HF", 10.500, "[测试] 加密信号",
			"内容经过加密，界面会显示 KEY 标记",
			{"content_text": "WKH TXLFN EURZQ IRA MXPSV RYHU WKH ODCB GRJ", "cipher_type": "caesar"}],
		["_test_lf", "morse", "LF", 0.300, "[测试] 低频段电台",
			"低沉的信号，来自很远的地方",
			{"content_text": "LF BAND TEST", "speed_wpm": 12}],
		["_test_uhf", "morse", "UHF", 450.000, "[测试] 超高频电台",
			"短促的高频脉冲",
			{"content_text": "UHF BAND TEST", "speed_wpm": 18}],
		["_test_sstv", "sstv", "VHF", 145.800, "[测试] SSTV 图像电台",
			"锁定 3 秒后按空格接收图像，接收完按 P 保存",
			{"sstv_mode": "Martin M1", "transmit_duration": 20.0}],
		["_test_audio", "audio", "VHF", 162.550, "[测试] 音频广播电台",
			"调准后自动播放，音量随接近度上升",
			{"content_file": "startup.mp3"}],
	]

	var injected: int = 0
	for d in defs:
		var opts: Dictionary = d[6]
		if str(d[1]) == "sstv":
			opts["content_image"] = sstv_img
		elif str(d[1]) == "audio":
			opts["content_audio"] = audio_bytes
		var sig := _debug_radio_make_signal(str(d[0]), str(d[1]), str(d[2]), float(d[3]), str(d[4]), str(d[5]), opts)
		mgr.add_signal(sig)
		_test_radio_ids.append(str(d[0]))
		injected += 1

	# 5) 输出指引
	_debug_radio_print_guide(injected, sstv_img.is_empty(), audio_bytes.is_empty())

	# 6) 打开无线电界面
	main.append_output("[color=" + T.muted_hex + "]正在启动无线电演示模式...[/color]\n", false)
	main.open_radio_receiver()

## 输出测试指引
func _debug_radio_print_guide(count: int, sstv_missing: bool, audio_missing: bool) -> void:
	var h: String = T.primary_hex
	var m: String = T.muted_hex
	var w: String = T.warning_hex
	main.append_output("[color=" + h + "]════ 无线电演示模式 ════[/color]\n", false)
	main.append_output("[color=" + m + "]已注入 %d 个测试信号（3 种类型 / 4 个频段），原信号保留[/color]\n" % count, false)
	main.append_output("[color=" + m + "]  [MORSE] HF 7.100 标准码 / HF 5.200 数字台 / HF 14.100 信标[/color]\n", false)
	main.append_output("[color=" + m + "]          HF 9.800 隐藏 / HF 10.500 加密 / LF 0.300 / UHF 450.000[/color]\n", false)
	main.append_output("[color=" + m + "]  [SSTV ] VHF 145.800 图像接收（锁定后按空格，P 保存）[/color]\n", false)
	main.append_output("[color=" + m + "]  [AUDIO] VHF 162.550 自动播放广播[/color]\n", false)
	if sstv_missing:
		main.append_output("[color=" + w + "]  [!] SSTV 图片素材缺失，图像接收将不可用[/color]\n", false)
	if audio_missing:
		main.append_output("[color=" + w + "]  [!] 音频素材缺失，音频电台将不可用[/color]\n", false)
	main.append_output("[color=" + m + "]操作: ←→调频 ↑↓方位 <>仰角 | 1-4频段 Tab模式 S扫描 B书签[/color]\n", false)
	main.append_output("[color=" + m + "]      L信标日志 | 空格SSTV接收 P存图 | Q/Esc退出[/color]\n", false)
	main.append_output("[color=" + w + "]提示: 质量≥0.5 且持续3秒才完全锁定；退出后测试信号保留，[/color]\n", false)
	main.append_output("[color=" + w + "]      用 debug radio clean 清除，或用 debug radio test 重新进入[/color]\n", false)

## 移除测试信号
func _debug_radio_clean(silent: bool = false) -> void:
	if not main or not main.radio_receiver:
		if not silent: _debug_err("radio_receiver 未就绪")
		return
	var mgr = main.radio_receiver.signal_mgr
	if mgr == null:
		if not silent: _debug_err("signal_mgr 未就绪")
		return
	var removed: int = _test_radio_ids.size()
	for id in _test_radio_ids:
		mgr.remove_signal(id)
	_test_radio_ids.clear()
	if not silent:
		_debug_ok("已移除 %d 个测试信号（重新打开 radio 将恢复真实信号）" % removed)

## 列出当前所有信号
func _debug_radio_list() -> void:
	if not main or not main.radio_receiver:
		_debug_err("radio_receiver 未就绪"); return
	var mgr = main.radio_receiver.signal_mgr
	if mgr == null:
		_debug_err("signal_mgr 未就绪"); return
	var h: String = T.primary_hex
	var m: String = T.muted_hex
	main.append_output("[color=" + h + "]════ 无线电信号 (%d) ════[/color]\n" % mgr.get_signal_count(), false)
	for sig_raw in mgr.signals:
		var s = sig_raw as RadioConfigParser.RadioSignal
		if s == null:
			continue
		var tags: String = ""
		if s.id.begins_with("_test_"): tags += " [测试]"
		if s.hidden: tags += " [隐藏]"
		if not s.beacon_id.is_empty(): tags += " [信标]"
		if not s.cipher_type.is_empty(): tags += " [加密]"
		main.append_output("[color=" + m + "]  %-4s %9.3f MHz  %-6s %s%s[/color]\n" % [s.band, s.frequency, s.type, s.label, tags], false)

# ── 系统 ──

func _debug_skip_boot() -> void:
	if not main or not main.boot_sequence: return
	if main.boot_sequence.is_active():
		main.boot_sequence.skip()
		_debug_ok("开机动画已跳过")
	else:
		_debug_err("开机动画未在播放")

func _debug_voice() -> void:
	if not OS.has_feature("editor"):
		_debug_err("角色调音面板只在 Godot 编辑器运行时开放")
		return
	if not main or not main.comm_mgr:
		_debug_err("通讯系统未就绪")
		return
	if main.comm_mgr.is_active:
		_debug_err("请先结束当前对话，再打开调音面板")
		return
	for cid in VoiceTuner.CHARACTER_IDS:
		if not main.comm_mgr.get_registry().has_character(cid):
			_debug_err("调音角色未加载: " + cid)
			return
	main.comm_mgr.open_voice_tuner()

func _debug_voice_meeting(args: Array) -> void:
	if not main or not main.comm_mgr:
		_debug_err("通讯系统未就绪")
		return
	var file := FileAccess.open("res://comm_system/meeting_voice_demo.json", FileAccess.READ)
	if file == null:
		_debug_err("无法读取 meeting_voice_demo.json")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or not parsed.get("participants") is Array:
		_debug_err("会议测试配置无效：participants 必须为数组")
		return
	var scene: Dictionary = parsed
	if not args.is_empty():
		var original: Array = scene["participants"]
		var selected: Array = []
		var slots: Array[String] = ["left", "center", "right"]
		for index in range(args.size()):
			var cid: String = str(args[index])
			var entry: Dictionary = {"id": cid, "slot": slots[index % slots.size()]}
			for candidate in original:
				if candidate is Dictionary and str(candidate.get("id", "")) == cid:
					entry["intro"] = candidate.get("intro", "")
			selected.append(entry)
		scene["participants"] = selected
	if main.comm_mgr.start_voice_meeting_demo(scene):
		_debug_ok("会议音色演示已开始：自动轮流发言，Esc 结束；可重复运行此命令")
	else:
		_debug_err("无法开始：请结束当前通讯/调音，确认角色 ID 已注册且不重复、slot 为 left/center/right")

func _debug_status() -> void:
	if not main: return
	var m: String = T.muted_hex
	main.append_output("[color=" + T.primary_hex + "]════ 调试状态总览 ════[/color]\n", false)
	if main.user_mgr:
		var logged: String = main.user_mgr.get_username() if main.user_mgr.is_logged_in else "(未登录)"
		main.append_output("[color=" + m + "]  用户: %s[/color]\n" % logged, false)
	if main.env_monitor:
		main.append_output("[color=" + m + "]  天数: %d  时间: %s  天气: %s[/color]\n" % [main.env_monitor.current_day, main.env_monitor.get_current_hour_display(), main.env_monitor.get_weather_name()], false)
	if main.env_task_mgr:
		main.append_output("[color=" + m + "]  环境: 必做完成=%s 日报=%s[/color]\n" % ["是" if main.env_task_mgr.is_all_required_completed() else "否", "是" if main.env_task_mgr.report_submitted else "否"], false)
	if main.comm_mgr:
		main.append_output("[color=" + m + "]  对话: %d 个  当前: %s[/color]\n" % [main.comm_mgr.get_dialogue_ids().size(), main.comm_mgr.get_current_dialogue_id()], false)
	if main.daily_dialogue_mgr:
		main.append_output("[color=" + m + "]  标记: %d  选择: %d  已完成对话: %d[/color]\n" % [main.daily_dialogue_mgr._story_flags.size(), main.daily_dialogue_mgr._story_choices.size(), main.daily_dialogue_mgr._completed_dialogues.size()], false)
	if main.perf_mgr:
		main.append_output("[color=" + m + "]  绩效: 生涯=%d  当日配额=%d[/color]\n" % [main.perf_mgr.career_total, main.perf_mgr.daily_quota], false)
	if main.mail_sys:
		main.append_output("[color=" + m + "]  邮件: %d 封 (%d 未读)[/color]\n" % [main.mail_sys.get_total_count(), main.mail_sys.get_unread_count()], false)
	if main.camera_mgr:
		main.append_output("[color=" + m + "]  摄像头: %d/%d 解锁[/color]\n" % [main.camera_mgr.get_unlocked_count(), main.camera_mgr.get_camera_count()], false)

func _debug_saves() -> void:
	if not main or not main.save_mgr or not main.user_mgr:
		_debug_err("save_mgr/user_mgr 未就绪"); return
	var m: String = T.muted_hex
	main.append_output("[color=" + T.primary_hex + "]════ 存档列表 ════[/color]\n", false)
	if main.user_mgr.is_logged_in:
		var sid: String = main.story_id if main.story_id else "(main)"
		var has: bool = main.save_mgr.has_save(main.story_id) if not main.story_id.is_empty() else false
		main.append_output("[color=" + m + "]  当前故事: %s  存档: %s[/color]\n" % [sid, "有" if has else "无"], false)
	var users: Array[String] = main.user_mgr.get_all_users()
	for u in users:
		var stories: Array[String] = []
		var save_dir: String = main.save_mgr.get_game_root_dir() + "saves/" + u + "/"
		var dir := DirAccess.open(save_dir)
		if dir:
			dir.list_dir_begin()
			var f: String = dir.get_next()
			while not f.is_empty():
				if f.ends_with(".json"):
					stories.append(f.get_basename())
				f = dir.get_next()
			dir.list_dir_end()
		main.append_output("[color=" + m + "]  %s: %s[/color]\n" % [u, str(stories) if not stories.is_empty() else "(无存档)"], false)

func _debug_delsave(story_id: String) -> void:
	if not main or not main.save_mgr:
		_debug_err("save_mgr 未就绪"); return
	if main.save_mgr.delete_save(story_id):
		_debug_ok("已删除存档: %s" % story_id)
	else:
		_debug_err("存档不存在或删除失败: %s" % story_id)

func _debug_settings_set(key: String, value: String) -> void:
	if not main or not main.settings_mgr:
		_debug_err("settings_mgr 未就绪"); return
	var v: Variant = _debug_parse_value(value)
	var r: Dictionary = main.settings_mgr.set_value(key, v)
	if r.get("success", false):
		_debug_ok("设置 %s = %s" % [key, str(v)])
	else:
		_debug_err(str(r.get("message", "设置失败")))

func _debug_settings_get(key: String) -> void:
	if not main or not main.settings_mgr:
		_debug_err("settings_mgr 未就绪"); return
	var val: Variant = main.settings_mgr.get_value(key)
	main.append_output("[color=" + T.primary_hex + "]%s = %s[/color]\n" % [key, str(val)], false)
