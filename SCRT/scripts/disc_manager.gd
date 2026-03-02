# ============================================================
# disc_manager.gd - 虚拟磁盘管理器
# 负责：扫描/加载/弹出故事包，存档恢复，桌面欢迎界面
# ============================================================
class_name DiscManager
extends RefCounted
# ══════════════════════════════════════════
#  模块引用
# ══════════════════════════════════════════
var main = null
var fs: FileSystem = null
var T = null
var tw = null
var story_loader = null
var save_mgr = null
var loading_screen: LoadingScreen = null

## ★ 当前加载的外部模组实例（磁盘弹出时清理）
var _loaded_external_mod: ModBase = null
var _loaded_external_mod_id: String = ""

# ══════════════════════════════════════════
#  磁盘数据
# ══════════════════════════════════════════
var available_stories: Array[Dictionary] = []
var vdisc_dir: String = ""
# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(p_main, p_fs, p_theme, p_tw, p_story_loader, p_save_mgr) -> void:
	main = p_main
	fs = p_fs
	T = p_theme
	tw = p_tw
	story_loader = p_story_loader
	save_mgr = p_save_mgr
	# 初始化载入画面系统
	loading_screen = LoadingScreen.new()
	var crt = main.crt_shader if "crt_shader" in main else null
	loading_screen.setup(main, fs, T, main.audio_manager if "audio_manager" in main else null, crt)
	if OS.has_feature("editor"):
		vdisc_dir = ProjectSettings.globalize_path("res://") + "vdisc/"
	else:
		vdisc_dir = OS.get_executable_path().get_base_dir() + "/vdisc/"
	if not DirAccess.dir_exists_absolute(vdisc_dir):
		DirAccess.make_dir_recursive_absolute(vdisc_dir)
		print("[DiscManager] 已创建 vdisc 目录: ", vdisc_dir)
# ══════════════════════════════════════════
#  重置所有状态
# ══════════════════════════════════════════
func reset_all() -> void:
	# ★ 清理外部模组
	_unload_external_mod()

	fs.clear_all()
	main._desktop_mode = true
	main.current_path = "/"
	main.read_files.clear()
	main.unlocked_passwords.clear()
	main.story_id = ""
	main.story_manifest = {}
	main.current_story_index = -1
	main.audio_manager.stop_ambient(0.5)
	# 关闭无线电接收器
	if main.radio_receiver != null and main.radio_receiver.is_active:
		main.radio_receiver.close()
	if "_radio_mode" in main:
		main._radio_mode = false
	# 重置触发器系统
	if main.trigger_sys and main.trigger_sys.has_method("reset"):
		main.trigger_sys.reset()
	# ★ 清理磁盘通讯对话
	if main.comm_mgr:
		main.comm_mgr.unload_disc_dialogues()
	# ★ 清理故事包号码簿
	if main.dial_mgr:
		main.dial_mgr.clear_story_directory()
	# 重置邮件系统
	if main.mail_sys and main.mail_sys.has_method("reset"):
		main.mail_sys.reset()
	main.has_new_mail = false

# ══════════════════════════════════════════
#  外部模组加载/卸载
# ══════════════════════════════════════════

## 卸载当前已加载的外部模组
func _unload_external_mod() -> void:
	if _loaded_external_mod != null:
		_loaded_external_mod._on_disable()
		_loaded_external_mod._on_uninstall()
		# 注销该模组注册的所有命令
		if main.pkg_mgr:
			main.pkg_mgr._unregister_all_commands_for_mod(_loaded_external_mod_id)
			main.pkg_mgr.active_mods.erase(_loaded_external_mod_id)
			main.pkg_mgr.mod_pack_files.erase(_loaded_external_mod_id)
			main.pkg_mgr._process_mods.erase(_loaded_external_mod_id)
			# 释放输入捕获
			if not main.pkg_mgr._input_capture.is_empty():
				if str(main.pkg_mgr._input_capture.get("mod_id", "")) == _loaded_external_mod_id:
					main.pkg_mgr._input_capture.clear()
					if main.input_field:
						main.input_field.editable = true
		print("[DiscManager] 已卸载外部模组: %s" % _loaded_external_mod_id)
		_loaded_external_mod = null
		_loaded_external_mod_id = ""

## 尝试从已加载的磁盘包中编译并启动外部模组
func _try_load_external_mod(path: String, manifest: Dictionary) -> void:
	if main.pkg_mgr == null:
		return

	var pkg_info: Dictionary = manifest.get("package", {}) as Dictionary
	if pkg_info.is_empty():
		return

	var pkg_type: String = str(pkg_info.get("type", "")).to_lower()
	if pkg_type != "external":
		return

	var mod_id: String = str(pkg_info.get("id", ""))
	if mod_id.is_empty():
		return

	var entry_script: String = str(pkg_info.get("entry_script", "mod_main.gd"))

	# 读取包内所有文件
	var pack_files: Dictionary = main.pkg_mgr._read_all_pack_files(path)
	if pack_files.is_empty():
		push_warning("[DiscManager] 外部模组 %s 包文件为空" % mod_id)
		return

	if not pack_files.has(entry_script):
		# 没有入口脚本，纯故事包，不需要模组加载
		print("[DiscManager] 包 %s 无入口脚本 %s，按普通磁盘处理" % [mod_id, entry_script])
		return

	# 编译并实例化
	var mod_instance: ModBase = main.pkg_mgr._compile_and_instantiate(mod_id, pack_files, entry_script)
	if mod_instance == null:
		push_warning("[DiscManager] 外部模组 %s 编译失败" % mod_id)
		main.append_output("[color=" + T.warning_hex + "]外部模组脚本编译失败，将以普通磁盘模式运行。[/color]\n", false)
		return

	# 注册到 PackageManager（不写入持久化，磁盘弹出就消失）
	main.pkg_mgr.active_mods[mod_id] = mod_instance
	main.pkg_mgr.mod_pack_files[mod_id] = pack_files
	main.pkg_mgr._process_mods.append(mod_id)

	_loaded_external_mod = mod_instance
	_loaded_external_mod_id = mod_id

	# 调用生命周期
	mod_instance._register_commands()
	mod_instance._on_install()
	mod_instance._on_enable()

	print("[DiscManager] 外部模组已加载: %s" % mod_id)

# ══════════════════════════════════════════
#  扫描可用故事包
# ══════════════════════════════════════════
func scan_stories(silent: bool = false) -> void:
	available_stories.clear()
	var dir := DirAccess.open(vdisc_dir)
	if dir == null:
		if not silent:
			main.append_output("[color=" + T.error_hex + "]无法访问 vdisc 目录。[/color]\n", false)
		return
	dir.list_dir_begin()
	var filename: String = dir.get_next()
	while not filename.is_empty():
		if not dir.current_is_dir() and filename.get_extension().to_lower() == "scp":
			var full_path: String = vdisc_dir + filename
			var info: Dictionary = _quick_read_manifest(full_path)
			info["filename"] = filename
			info["path"] = full_path
			# ★ 标记是否为软件包
			if PackageManager.is_package_manifest(info):
				info["_is_package"] = true
				info["_package_type"] = PackageManager.get_package_type(info)
			else:
				info["_is_package"] = false
				info["_package_type"] = ""
			available_stories.append(info)
		filename = dir.get_next()
	dir.list_dir_end()
	# 非静默模式：显示扫描进度条和结果
	if not silent:
		main.append_output("[color=" + str(T.muted_hex) + "]正在扫描 vdisc/ 目录...[/color]\n", false)
		# 使用 typewriter 内置的进度条动画
		var scan_size: int = maxi(available_stories.size() * 200, 300)
		await tw.show_progress_bar(scan_size)
		var p: String = T.primary_hex
		var m: String = T.muted_hex
		var w: String = T.warning_hex
		if available_stories.is_empty():
			main.append_output("[color=" + m + "]未检测到虚拟磁盘。[/color]\n", false)
			main.append_output("[color=" + m + "]请将 .scp 文件放入 vdisc/ 目录。[/color]\n", false)
		else:
			main.append_output("\n[color=" + p + "]═══════════ 虚拟磁盘扫描结果 ═══════════[/color]\n\n", false)
			for i in range(available_stories.size()):
				var story: Dictionary = available_stories[i]
				var filename_str: String = str(story.get("filename", ""))
				# ★ 已安装的内部包不再显示
				if main.pkg_mgr and main.pkg_mgr.is_hidden_package(filename_str):
					continue
				var story_info: Dictionary = story.get("story", {}) as Dictionary
				var pkg_info: Dictionary = story.get("package", {}) as Dictionary
				var is_pkg: bool = story.get("_is_package", false)
				var pkg_type_str: String = str(story.get("_package_type", ""))
				# 标题/作者/ID 来源：包优先，否则 story
				var title: String = ""
				var author: String = ""
				var sid: String = ""
				if is_pkg and not pkg_info.is_empty():
					title = str(pkg_info.get("title", "未知"))
					author = str(pkg_info.get("author", "未知"))
					sid = str(pkg_info.get("id", ""))
				else:
					title = str(story_info.get("title", "未知"))
					author = str(story_info.get("author", "未知"))
					sid = str(story_info.get("id", ""))
				var has_save: bool = false
				if not is_pkg and save_mgr.has_method("has_save"):
					has_save = save_mgr.has_save(sid)
				var save_marker: String = ""
				if has_save:
					save_marker = " [color=" + w + "][存档][/color]"
				# ★ 包类型标记
				var type_marker: String = ""
				if is_pkg:
					if pkg_type_str == "internal":
						type_marker = " [color=" + T.warning_hex + "][内部软件][/color]"
					elif pkg_type_str == "external":
						type_marker = " [color=" + T.primary_hex + "][外部软件][/color]"
				main.append_output("  [color=" + p + "][" + str(i + 1) + "][/color] " + title + save_marker + type_marker + "\n", false)
				main.append_output("	  [color=" + m + "]作者: " + author + "  |  ID: " + sid + "[/color]\n", false)
				main.append_output("	  [color=" + m + "]文件: " + filename_str + "[/color]\n\n", false)

			main.append_output("[color=" + p + "]════════════════════════════════════════════[/color]\n", false)
			main.append_output("[color=" + m + "]输入 load <编号> 加载磁盘/外部软件包。[/color]\n", false)
			main.append_output("[color=" + m + "]输入 install <编号> 安装内部软件包。[/color]\n", false)
# ══════════════════════════════════════════
#  快速读取 manifest（不加载完整文件系统）
#  ★ 兼容顶层文件夹包裹
# ══════════════════════════════════════════
func _quick_read_manifest(path: String) -> Dictionary:
	var reader := ZIPReader.new()
	var err := reader.open(path)
	if err != OK:
		return { "story": { "title": "读取失败", "id": "" } }
	var manifest: Dictionary = {}
	var files: PackedStringArray = reader.get_files()
	for f in files:
		# ★ 兼容任意深度的 manifest.json（包括被文件夹包裹的情况）
		if f.get_file() == "manifest.json":
			var data: PackedByteArray = reader.read_file(f)
			var json := JSON.new()
			if json.parse(data.get_string_from_utf8()) == OK:
				if json.data is Dictionary:
					manifest = json.data
			break
	reader.close()
	return manifest
# ══════════════════════════════════════════
#  加载故事包
# ══════════════════════════════════════════
func load_story(args: Array) -> void:
	if args.is_empty():
		main.append_output("[color=" + T.error_hex + "]用法: load <编号>[/color]\n", false)
		main.append_output("[color=" + T.muted_hex + "]输入 scan 查看可用磁盘列表。[/color]\n", false)
		return
	var index_str: String = str(args[0])
	if not index_str.is_valid_int():
		main.append_output("[color=" + T.error_hex + "]请输入有效的磁盘编号。[/color]\n", false)
		return
	var index: int = int(index_str) - 1
	if index < 0 or index >= available_stories.size():
		main.append_output("[color=" + T.error_hex + "]磁盘编号超出范围。可用: 1-" + str(available_stories.size()) + "[/color]\n", false)
		return
	if not main.story_id.is_empty():
		_auto_save()
		# ★ 卸载之前的外部模组
		_unload_external_mod()
		fs.clear_all()
	var story_data: Dictionary = available_stories[index]

	# ★ 检查是否为内部软件包（不可通过 load 加载，需要 install）
	var is_pkg: bool = story_data.get("_is_package", false)
	var pkg_type_str: String = str(story_data.get("_package_type", ""))
	if is_pkg and pkg_type_str == "internal":
		main.append_output("[color=" + T.warning_hex + "]这是一个内部软件包，不能使用 load 命令。[/color]\n", false)
		main.append_output("[color=" + T.muted_hex + "]请使用 install " + str(index + 1) + " 来安装它。[/color]\n", false)
		return

	var path: String = str(story_data.get("path", ""))
	# ★ 先加载故事包（获取 manifest 后才能读取 loading_screen 配置）
	main.append_output("\n[color=" + T.muted_hex + "]Reading disc...[/color]\n", false)
	if not story_loader.load_story(path):
		main.append_output("[color=" + T.error_hex + "]磁盘加载失败: " + story_loader.error_message + "[/color]\n", false)
		return
	# 设置文件系统（loading_screen 的 sound 动作需要访问虚拟FS）
	fs.file_system = story_loader.file_system
	main.story_manifest = story_loader.manifest
	main.current_story_index = index
	var story_dict: Dictionary = main.story_manifest.get("story", {}) as Dictionary
	# ★ 注入磁盘信息到载入画面
	loading_screen.set_disc_info({
		"title": str(story_dict.get("title", "Unknown Disc")),
		"author": str(story_dict.get("author", "Unknown")),
		"version": str(story_dict.get("version", "")),
		"description": str(story_dict.get("description", "")),
		"id": str(story_dict.get("id", "")),
	})
	# ★ 播放自定义载入画面（或内置默认）
	if main.story_manifest.has("loading_screen") and main.story_manifest["loading_screen"] is Dictionary:
		loading_screen.play(main.story_manifest["loading_screen"] as Dictionary)
	else:
		loading_screen.play_default()
	# ★ 等待载入画面完成
	await loading_screen.loading_completed
	var settings_dict: Dictionary = main.story_manifest.get("settings", {}) as Dictionary
	var story_id: String = str(story_dict.get("id", ""))
	main.story_id = story_id
	# start_clearance: 优先 settings，回退 story（旧版兼容）
	var start_clearance: int = 0
	if settings_dict.has("start_clearance"):
		start_clearance = int(settings_dict.get("start_clearance", 0))
	elif story_dict.has("start_clearance"):
		start_clearance = int(story_dict.get("start_clearance", 0))
	# ── 加载隐藏目录配置 ──
	fs.hidden_dirs.clear()
	if main.story_manifest.has("hidden_dirs"):
		var dirs = main.story_manifest["hidden_dirs"]
		if dirs is Array:
			for d in dirs:
				fs.hidden_dirs.append(str(d))
	print("[DiscManager] 隐藏目录: " + str(fs.hidden_dirs.size()) + " 个")
	# ── 加载权限表（支持顶层 permissions 和旧版 story.permissions）──
	fs.story_permissions.clear()
	if main.story_manifest.has("permissions"):
		var perms = main.story_manifest["permissions"]
		if perms is Dictionary:
			fs.story_permissions = perms
	elif story_dict.has("permissions"):
		var perms = story_dict["permissions"]
		if perms is Dictionary:
			fs.story_permissions = perms
	# ── 加载密码表（已被 story_loader 标准化为新格式）──
	# 新格式: { "password_string": { "grants_clearance": N, "message": "..." } }
	# 支持顶层 passwords 和旧版 story.passwords
	# （无需额外处理，_verify_password 中适配新格式即可）
	# ── 加载文件密码表 ──
	fs.story_file_passwords.clear()
	if main.story_manifest.has("file_passwords"):
		var fps = main.story_manifest["file_passwords"]
		if fps is Dictionary:
			for fp_path in fps.keys():
				fs.story_file_passwords[fp_path] = fps[fp_path]
	elif story_dict.has("file_passwords"):
		var fps = story_dict["file_passwords"]
		if fps is Dictionary:
			for fp_path in fps.keys():
				fs.story_file_passwords[fp_path] = fps[fp_path]
	print("[DiscManager] 文件密码表: " + str(fs.story_file_passwords.size()) + " 条")
	# ── 加载环境音配置 ──
	fs.ambient_sounds.clear()
	if main.story_manifest.has("ambient"):
		var ambient_cfg = main.story_manifest["ambient"]
		if ambient_cfg is Dictionary:
			for dir_path in ambient_cfg.keys():
				var normalized: String = fs.normalize_path(str(dir_path))
				var value = ambient_cfg[dir_path]
				if value is String:
					fs.ambient_sounds[normalized] = { "file": value, "volume": 1.0 }
				elif value is Dictionary:
					fs.ambient_sounds[normalized] = {
						"file": str(value.get("file", "")),
						"volume": float(value.get("volume", 1.0))
					}
	print("[DiscManager] 环境音配置: " + str(fs.ambient_sounds.size()) + " 条")
	# ── ★ 新增：加载路径元数据 (headers) ──
	fs.path_headers.clear()
	if main.story_manifest.has("headers"):
		var headers_cfg = main.story_manifest["headers"]
		if headers_cfg is Dictionary:
			for h_path in headers_cfg.keys():
				var normalized: String = fs.normalize_path(str(h_path))
				var value = headers_cfg[h_path]
				if value is Dictionary:
					fs.path_headers[normalized] = value
				elif value is String:
					fs.path_headers[normalized] = { "display_name": value }
	print("[DiscManager] 路径元数据: " + str(fs.path_headers.size()) + " 条")
	# ── ★ 新增：加载文件描述 (file_descriptions) ──
	fs.file_descriptions.clear()
	if main.story_manifest.has("file_descriptions"):
		var fd_cfg = main.story_manifest["file_descriptions"]
		if fd_cfg is Dictionary:
			for fd_path in fd_cfg.keys():
				var normalized: String = fs.normalize_path(str(fd_path))
				fs.file_descriptions[normalized] = fd_cfg[fd_path]
	print("[DiscManager] 文件描述: " + str(fs.file_descriptions.size()) + " 个目录")
	# ── 加载无线电信号（优先 manifest 中的 radio_signals，回退旧版 signals.cfg）──
	if main.radio_receiver != null:
		if main.story_manifest.has("radio_signals"):
			main.radio_receiver.load_signals_from_manifest(main.story_manifest, fs)
		else:
			main.radio_receiver.load_signals_from_fs(fs)
		if main.radio_receiver.has_signals():
			print("[DiscManager] 无线电信号源已加载: " + str(main.radio_receiver.signal_mgr.signals.size()) + " 个")

	# ── 尝试加载存档 ──
	var save_result = save_mgr.load_save(story_id)
	var save_data: Dictionary = save_result if save_result is Dictionary else {}
	if not save_data.is_empty():
		fs.player_clearance = int(save_data.get("player_clearance", 0))
		main.read_files.clear()
		if save_data.has("read_files"):
			for f in save_data["read_files"]:
				main.read_files.append(str(f))
		main.unlocked_passwords.clear()
		if save_data.has("unlocked_passwords"):
			for pwd in save_data["unlocked_passwords"]:
				main.unlocked_passwords.append(str(pwd))
		fs.unlocked_file_passwords.clear()
		if save_data.has("unlocked_file_passwords"):
			for fp in save_data["unlocked_file_passwords"]:
				fs.unlocked_file_passwords.append(str(fp))
		# 恢复当前路径
		if save_data.has("current_path"):
			var saved_path: String = str(save_data["current_path"])
			if fs.has_clearance(saved_path):
				main.current_path = saved_path
			else:
				main.current_path = "/"
		# 恢复无线电信号状态
		if save_data.has("radio_data"):
			if main.radio_receiver and main.radio_receiver.signal_mgr:
				main.radio_receiver.signal_mgr.load_save_data(save_data["radio_data"])
	else:
		fs.player_clearance = start_clearance
		main.read_files.clear()
		main.unlocked_passwords.clear()
		main.current_path = "/"
	# 清屏，切换到磁盘模式
	main.output_text.text = ""
	tw.clear_queue()
	main._desktop_mode = false
	if main.has_method("load_effects_from_manifest"):
		main.load_effects_from_manifest(main.story_manifest)

	# ── 加载触发器配置 ──
	if main.trigger_sys:
		main.trigger_sys.load_from_manifest(main.story_manifest)
		# ★ 在 load_from_manifest 之后恢复存档（避免被清空）
		if not save_data.is_empty() and save_data.has("trigger_data"):
			main.trigger_sys.load_save_data(save_data["trigger_data"])
		print("[DiscManager] 触发器已加载")
	# ── 加载磁盘内通讯对话 ──
	if main.comm_mgr:
		if main.story_manifest.has("comm_characters") or main.story_manifest.has("comm_dialogues"):
			main.comm_mgr.load_disc_dialogues(main.story_manifest)
			print("[DiscManager] 磁盘通讯对话已加载")
	# ── ★ 加载故事包号码簿到拨号管理器 ──
	if main.dial_mgr:
		if main.story_manifest.has("dial_directory"):
			main.dial_mgr.load_story_directory(main.story_manifest["dial_directory"] as Dictionary)
			print("[DiscManager] 拨号号码簿已加载")
	# ── 加载邮件系统配置 ──
	if main.mail_sys:
		# 先加载全局邮箱索引（仅登录状态有效）
		if main.user_mgr != null and main.user_mgr.is_logged_in:
			main.mail_sys.load_global_inbox()
		# 清空本故事会话的临时状态（不清 delivered_ids）
		main.mail_sys.load_from_manifest(main.story_manifest)
		# 再恢复本故事的 mail_data（临时邮件 + delivered_ids）
		if not save_data.is_empty() and save_data.has("mail_data"):
			main.mail_sys.load_save_data(save_data["mail_data"])
		print("[DiscManager] 邮件系统已加载")

	main._update_status_bar()
	main._show_welcome_message()
	main.update_ambient_sound()
	if main.user_mgr.is_logged_in:
		main.user_mgr.inject_story_notes(main.story_manifest)
		main.user_mgr._increment_stat("discs_loaded_count")
		main.user_mgr._save_current_profile()

	# ★ 外部模组包：加载完故事后尝试编译并启动模组脚本
	_try_load_external_mod(path, main.story_manifest)

# ══════════════════════════════════════════
#  弹出磁盘
# ══════════════════════════════════════════
func eject_story() -> void:
	if main._desktop_mode:
		main.append_output("[color=" + str(T.muted_hex) + "]当前已在桌面模式。[/color]\n", false)
		return
	_auto_save()

	var story_dict: Dictionary = main.story_manifest.get("story", {}) as Dictionary
	var title: String = str(story_dict.get("title", "未知"))
	reset_all()
	main.audio_manager.stop_ambient()
	main.output_text.text = ""
	tw.clear_queue()
	main.append_output("[color=" + str(T.muted_hex) + "]磁盘 \"" + title + "\" 已弹出。[/color]\n\n", false)
	scan_stories(true)
	main._update_status_bar()
	show_desktop_welcome()
# ══════════════════════════════════════════
#  自动保存
# ══════════════════════════════════════════
func _auto_save() -> void:
	if main.story_id.is_empty():
		return
	# ★ 收集额外存档数据
	var extra: Dictionary = {}
	if main.trigger_sys and main.trigger_sys.has_method("get_save_data"):
		extra["trigger_data"] = main.trigger_sys.get_save_data()
	if main.mail_sys and main.mail_sys.has_method("get_save_data"):
		extra["mail_data"] = main.mail_sys.get_save_data()
	# 无线电信号状态
	if main.radio_receiver and main.radio_receiver.signal_mgr:
		extra["radio_data"] = main.radio_receiver.signal_mgr.get_save_data()
	save_mgr.auto_save(
		main.story_id,
		fs.player_clearance,
		main.read_files,
		main.unlocked_passwords,
		fs.unlocked_file_passwords,
		main.current_path,
		extra
	)

# ══════════════════════════════════════════
#  桌面欢迎界面
# ══════════════════════════════════════════
func show_desktop_welcome(clear_screen: bool = false) -> void:
	if clear_screen:
		main.output_text.text = ""
		tw.clear_queue()
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	# 用户欢迎
	var user_greeting: String = ""
	if main.user_mgr and main.user_mgr.is_logged_in:
		user_greeting = "操作员: " + main.user_mgr.get_display_name()
	else:
		user_greeting = "未登录"
	var box: String = fs.build_box([
		"SCP FOUNDATION",
		"SECURE TERMINAL SYSTEM",
		user_greeting
	] as Array[String], p)
	main.append_output(box + "\n\n", false)
	if available_stories.size() > 0:
		main.append_output("[color=" + m + "]检测到 " + str(available_stories.size()) + " 个虚拟磁盘。输入 scan 查看列表。[/color]\n", false)
	else:
		main.append_output("[color=" + m + "]未检测到虚拟磁盘。请将 .scp 文件放入 vdisc/ 目录。[/color]\n", false)
	main.append_output("[color=" + m + "]输入 help 查看可用命令。[/color]\n\n", false)
# ══════════════════════════════════════════
#  磁盘信息（vdisc 命令）
# ══════════════════════════════════════════
func show_story_info() -> void:
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	if main._desktop_mode:
		main.append_output("[color=" + p + "]vdisc 目录: [/color][color=" + m + "]" + vdisc_dir + "[/color]\n", false)
		main.append_output("[color=" + p + "]磁盘数量: [/color][color=" + m + "]" + str(available_stories.size()) + "[/color]\n", false)
		if available_stories.size() > 0:
			main.append_output("[color=" + m + "]输入 scan 查看详细列表。[/color]\n", false)
		return
	# 磁盘模式显示当前加载的磁盘详情
	var w: String = T.warning_hex
	var story_dict: Dictionary = main.story_manifest.get("story", {}) as Dictionary
	var title: String = str(story_dict.get("title", "未知"))
	var author: String = str(story_dict.get("author", "未知"))
	var version: String = str(story_dict.get("version", "未知"))
	var desc: String = str(story_dict.get("description", "无描述"))
	var sid: String = str(story_dict.get("id", ""))
	var lines: Array[String] = []
	lines.append("[color=" + p + "]═══════════ 当前磁盘信息 ═══════════[/color]")
	lines.append("")
	lines.append("  [color=" + m + "]标题:[/color]    [color=" + p + "]" + title + "[/color]")
	lines.append("  [color=" + m + "]作者:[/color]    [color=" + p + "]" + author + "[/color]")
	lines.append("  [color=" + m + "]版本:[/color]    [color=" + p + "]" + version + "[/color]")
	lines.append("  [color=" + m + "]ID:[/color]      [color=" + p + "]" + sid + "[/color]")
	lines.append("  [color=" + m + "]描述:[/color]    [color=" + p + "]" + desc + "[/color]")
	lines.append("")
	lines.append("  [color=" + m + "]权限等级:[/color]  [color=" + w + "]" + str(fs.player_clearance) + "[/color]")
	lines.append("  [color=" + m + "]已读文件:[/color]  [color=" + p + "]" + str(main.read_files.size()) + "[/color]")
	lines.append("  [color=" + m + "]当前路径:[/color]  [color=" + p + "]" + main.current_path + "[/color]")

	# ★ 显示外部模组信息
	if _loaded_external_mod != null:
		lines.append("")
		lines.append("  [color=" + T.success_hex + "]▶ 外部模组已激活: " + _loaded_external_mod_id + "[/color]")

	lines.append("")
	lines.append("[color=" + p + "]════════════════════════════════════════[/color]")
	main.append_output("\n".join(lines) + "\n", false)
