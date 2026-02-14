# disc_manager.gd
# 职责：磁盘扫描、加载、卸载、桌面模式管理
class_name DiscManager
extends RefCounted

var main: Node = null
var fs = null              # FileSystem
var T = null               # ThemeManager.ThemeColors
var tw = null              # Typewriter
var story_loader = null    # StoryLoader
var save_mgr = null        # SaveManager

# 磁盘状态
var available_stories: Array[Dictionary] = []
var current_story_index: int = -1
var story_manifest: Dictionary = {}
var current_story_path: String = ""
var story_id: String = ""

## 初始化
func setup(p_main: Node, p_fs, p_theme, p_tw, p_story_loader, p_save_mgr) -> void:
	main = p_main
	fs = p_fs
	T = p_theme
	tw = p_tw
	story_loader = p_story_loader
	save_mgr = p_save_mgr

## ============================================================
## 获取 vdisc 目录路径
## 编辑器中使用 res://vdisc/，导出后使用可执行文件旁的 vdisc/
## ============================================================
func _get_vdisc_dir() -> String:
	if OS.has_feature("editor"):
		# 编辑器中：使用项目根目录下的 vdisc/
		return ProjectSettings.globalize_path("res://vdisc/")
	else:
		# 导出后：使用可执行文件所在目录下的 vdisc/
		return OS.get_executable_path().get_base_dir() + "/vdisc/"

## ============================================================
## 扫描 vdisc/ 目录中的可用故事磁盘
## ============================================================
func scan_stories(silent: bool = false) -> void:
	available_stories.clear()
	var vdisc_dir: String = _get_vdisc_dir()
	
	print("[DiscManager] 扫描路径: " + vdisc_dir)
	print("[DiscManager] 目录是否存在: " + str(DirAccess.dir_exists_absolute(vdisc_dir)))
	
	if not DirAccess.dir_exists_absolute(vdisc_dir):
		DirAccess.make_dir_recursive_absolute(vdisc_dir)
		print("[DiscManager] 已创建 vdisc 目录: " + vdisc_dir)
	
	var dir: DirAccess = DirAccess.open(vdisc_dir)
	if dir == null:
		var err_code: int = DirAccess.get_open_error()
		print("[DiscManager] 无法打开目录，错误码: " + str(err_code))
		if not silent:
			main.append_output("[color=" + str(T.warning_hex) + "]vdisc/ 目录无法访问。[/color]\n", false)
		return
	
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and (file_name.ends_with(".scp") or file_name.ends_with(".zip")):
			var full_path: String = vdisc_dir + file_name
			print("[DiscManager] 发现磁盘文件: " + full_path)
			var info: Dictionary = _peek_story_info(full_path)
			if not info.is_empty():
				info["filename"] = file_name
				info["full_path"] = full_path
				available_stories.append(info)
				print("[DiscManager] 读取成功: " + info.get("title", "未知"))
			else:
				print("[DiscManager] 无法读取磁盘信息: " + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	
	# 只在非静默模式下输出扫描结果
	if not silent:
		if available_stories.is_empty():
			main.append_output("[color=" + str(T.warning_hex) + "]vdisc/ 目录为空，未找到 .scp 或 .zip 文件。[/color]\n", true)
		else:
			main.append_output("[color=" + str(T.primary_hex) + "]扫描完成，发现 " + str(available_stories.size()) + " 个虚拟磁盘。[/color]\n", true)
	
	print("[DiscManager] 扫描完成，共 " + str(available_stories.size()) + " 个磁盘")




## ============================================================
## 快速预览 .scp/.zip 中的 manifest 信息（不完全加载）
## 这个方法原本在 main.gd 中，现在搬到 DiscManager
## ============================================================
func _peek_story_info(path: String) -> Dictionary:
	var info: Dictionary = {"title": "未知剧本", "id": "", "author": "未知"}

	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		print("[DiscManager] 无法打开ZIP: " + path)
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
					var stripped_line: String = line.strip_edges()
					if stripped_line.begins_with("title="):
						info["title"] = stripped_line.substr(6).strip_edges()
					elif stripped_line.begins_with("id="):
						info["id"] = stripped_line.substr(3).strip_edges()
					elif stripped_line.begins_with("author="):
						info["author"] = stripped_line.substr(7).strip_edges()
			break

	reader.close()
	return info

## ============================================================
## 加载指定编号的磁盘
## ============================================================
func load_story(args: Array) -> void:
	if args.is_empty():
		main.append_output("[color=" + str(T.error_hex) + "][ERROR] 用法: load <编号>[/color]", false)
		if available_stories.size() > 0:
			main.append_output("[color=" + str(T.muted_hex) + "]可用磁盘: 1-" + str(available_stories.size()) + "[/color]\n", false)
		return

	var index_str: String = str(args[0])
	if not index_str.is_valid_int():
		main.append_output("[color=" + str(T.error_hex) + "][ERROR] 请输入有效的编号数字。[/color]\n", false)
		return

	var index: int = index_str.to_int() - 1
	if index < 0 or index >= available_stories.size():
		main.append_output("[color=" + str(T.error_hex) + "][ERROR] 编号超出范围。可用范围: 1-" + str(available_stories.size()) + "[/color]\n", false)
		return

	main.append_output("[color=" + str(T.muted_hex) + "]正在加载虚拟磁盘...[/color]", false)
	while tw.is_typing:
		await main.get_tree().process_frame
	await tw.show_progress_bar(800)
	await main.get_tree().create_timer(0.3).timeout

	if _load_story_by_index(index):
		main._desktop_mode = false
		current_story_index = index
		main.output_text.text = ""
		tw.clear_queue()
		main._update_status_bar()
		main._show_welcome_message()
	else:
		main.append_output("[color=" + str(T.error_hex) + "][ERROR] 磁盘加载失败。[/color]\n", false)

## ============================================================
## 内部：按索引加载磁盘
## ============================================================
func _load_story_by_index(index: int) -> bool:
	var info: Dictionary = available_stories[index]
	var full_path: String = str(info["full_path"])

	# 通过 story_loader 解析 ZIP
	if not story_loader.load_story(full_path):
		print("[DiscManager] 加载失败: " + story_loader.error_message)
		return false

	fs.file_system = story_loader.file_system
	story_manifest = story_loader.manifest
	current_story_path = full_path

	# 获取 story ID
	if story_manifest.has("story") and story_manifest["story"].has("id"):
		story_id = story_manifest["story"]["id"]
	else:
		story_id = str(full_path.get_file().hash())

	# 加载权限表
	fs.story_permissions.clear()
	if story_manifest.has("permissions"):
		var perms: Dictionary = story_manifest["permissions"]
		for perm_path in perms.keys():
			fs.story_permissions[perm_path] = int(perms[perm_path])
		print("[DiscManager] 权限表: " + str(fs.story_permissions.size()) + " 条")

	# 加载文件密码表
	fs.story_file_passwords.clear()
	if story_manifest.has("file_passwords"):
		var fps: Dictionary = story_manifest["file_passwords"]
		for fp_path in fps.keys():
			fs.story_file_passwords[fp_path] = fps[fp_path]
		print("[DiscManager] 文件密码表: " + str(fs.story_file_passwords.size()) + " 条")

	# 应用设置
	var start_clearance: int = 0
	if story_manifest.has("settings"):
		var settings: Dictionary = story_manifest["settings"]
		if settings.has("start_path"):
			main.current_path = settings["start_path"]
		if settings.has("typing_speed"):
			tw.base_speed = float(settings["typing_speed"])
		if settings.has("start_clearance"):
			start_clearance = int(settings["start_clearance"])

	# 尝试加载存档
	var save_data = save_mgr.load_save(story_id)
	if save_data != null:
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
		# 无论存档记录了什么路径，始终从根目录开始
		main.current_path = "/"
		print("[DiscManager] 存档已恢复，权限: " + str(fs.player_clearance))
	else:
		fs.player_clearance = start_clearance
		main.read_files.clear()
		main.unlocked_passwords.clear()
		main.current_path = "/"

	# 同步状态到 main
	main.story_id = story_id
	main.story_manifest = story_manifest
	main.current_story_index = current_story_index

	var title: String = story_manifest.get("story", {}).get("title", "未知")
	print("[DiscManager] 加载成功: " + title + " | 文件: " + str(fs.file_system.size()))
	return true

## ============================================================
## 卸载当前磁盘
## ============================================================
func eject_story() -> void:
	if main._desktop_mode:
		main.append_output("[color=" + str(T.muted_hex) + "]当前已在桌面模式。[/color]\n", false)
		return

	save_mgr.auto_save(story_id, fs.player_clearance, main.read_files, main.unlocked_passwords, fs.unlocked_file_passwords, main.current_path)
	main.append_output("[color=" + str(T.muted_hex) + "]正在卸载磁盘...[/color]", false)
	while tw.is_typing:
		await main.get_tree().process_frame
	await main.get_tree().create_timer(0.5).timeout

	fs.clear_all()
	story_manifest.clear()
	current_story_path = ""
	story_id = ""
	main.story_id = ""
	main.current_path = "/"
	main.read_files.clear()
	main.unlocked_passwords.clear()
	current_story_index = -1
	main.story_manifest.clear()

	main._desktop_mode = true
	main.output_text.text = ""
	tw.clear_queue()
	main._update_status_bar()
	show_desktop_welcome()

## ============================================================
## 桌面欢迎界面
## ============================================================
func show_desktop_welcome() -> void:
	# 先清空，防止之前的 scan 输出和欢迎信息混叠
	main.output_text.text = ""
	tw.clear_queue()
	var p: String = str(T.primary_hex)
	var w: String = str(T.warning_hex)
	var m: String = str(T.muted_hex)

	var title: String = "SCP FOUNDATION TERMINAL v0.1"
	var subtitle: String = "SECURE - CONTAIN - PROTECT"
	var box: String = fs.build_box([title, subtitle] as Array[String], p)
	main.output_text.append_text(box + "\n\n")

	if available_stories.is_empty():
		main.output_text.append_text("[color=" + w + "]未检测到虚拟磁盘。[/color]\n")
		main.output_text.append_text("[color=" + m + "]请将 .scp 文件放入 vdisc/ 目录后输入 scan 重新扫描。[/color]\n\n")
	else:
		main.output_text.append_text("[color=" + p + "]检测到 " + str(available_stories.size()) + " 个虚拟磁盘:[/color]\n\n")
		for i in range(available_stories.size()):
			var info: Dictionary = available_stories[i]
			main.output_text.append_text("  [color=" + w + "]" + str(i + 1) + ".[/color] [color=" + p + "]" + str(info.get("title", "未知")) + "[/color]\n")
			main.output_text.append_text("   [color=" + m + "]" + str(info.get("author", "未知")) + " | " + str(info.get("filename", "")) + "[/color]\n")
		main.output_text.append_text("\n")

	main.output_text.append_text("[color=" + m + "]可用命令:[/color]\n")
	main.output_text.append_text("  [color=" + p + "]load <编号>[/color]   加载指定磁盘\n")
	main.output_text.append_text("  [color=" + p + "]scan[/color]          重新扫描磁盘目录\n")
	main.output_text.append_text("  [color=" + p + "]clear[/color]         清空屏幕\n")
	main.output_text.append_text("  [color=" + p + "]exit[/color]          退出终端\n")

## ============================================================
## 显示磁盘详情
## ============================================================
func show_story_info() -> void:
	var p: String = str(T.primary_hex)
	var s: String = str(T.success_hex)
	var w: String = str(T.warning_hex)
	var m: String = str(T.muted_hex)

	if story_manifest.is_empty() and available_stories.is_empty():
		main.append_output("[color=" + m + "]未检测到外部虚拟磁盘，当前运行于内置诊断模式。[/color]\n", false)
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
			lines.append("  [color=" + w + "]" + str(i + 1) + ".[/color] " + str(info.get("title", "未知")) + " [color=" + m + "](" + str(info.get("filename", "")) + ")[/color]" + marker)
			lines.append("     作者: [color=" + m + "]" + str(info.get("author", "未知")) + "[/color]")
		lines.append("")

	lines.append("[color=" + p + "]════════════════════════════════════════════[/color]")
	main.append_output("\n".join(lines) + "\n", false)




## 重置所有状态（reboot/restart 时调用）
## 注意：这是静默重置，不包含动画和 await，不会调用 eject_story()
func reset_all() -> void:
	# 如果有磁盘在用，先静默保存
	if story_id != "" and main.story_id != "":
		save_mgr.auto_save(story_id, fs.player_clearance, main.read_files,
			main.unlocked_passwords, fs.unlocked_file_passwords, main.current_path)
	
	# 重置文件系统
	fs.clear_all()
	
	# 重置磁盘管理器自身状态
	story_manifest.clear()
	current_story_path = ""
	story_id = ""
	current_story_index = -1
	
	# 重置主控状态
	main.current_path = "/"
	main.read_files.clear()
	main.unlocked_passwords.clear()
	main.story_id = ""
	main.story_manifest = {}
	main.current_story_index = -1
	main.has_new_mail = false
	main._desktop_mode = true
	main._password_mode = false
	main._file_password_mode = false
	main._file_password_target = ""
	main._file_password_filename = ""
	main._command_running = false
	
	# 清空输出
	main.output_text.text = ""
	tw.clear_queue()
	
	# 重新扫描磁盘
	scan_stories()
	main._update_status_bar()
