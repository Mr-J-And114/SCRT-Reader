class_name SaveManager
extends RefCounted

# ============================================================
# 存档管理器 - 负责存档/读档/目录管理/路径工具
# ============================================================

# ── 用户管理器引用（可选，设置后存档路径改为用户目录）──
var _user_mgr = null
func set_user_manager(um) -> void:
	_user_mgr = um

# ============================================================
# 路径与目录
# ============================================================

# 获取游戏根目录（编辑器中为项目目录，导出后为exe所在目录）
func get_game_root_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://")
	else:
		return OS.get_executable_path().get_base_dir() + "/"

# 确保 vdisc 目录存在
func ensure_stories_dir() -> void:
	var vdisc_path: String = get_game_root_dir() + "vdisc/"
	if not DirAccess.dir_exists_absolute(vdisc_path):
		var err := DirAccess.make_dir_absolute(vdisc_path)
		if err == OK:
			print("[SaveManager] 已创建vdisc目录: " + vdisc_path)
		else:
			print("[SaveManager] 创建vdisc目录失败: " + str(err))
	else:
		print("[SaveManager] vdisc目录已存在: " + vdisc_path)

# 确保 saves 目录存在
func ensure_saves_dir() -> void:
	var saves_path: String = get_game_root_dir() + "saves/"
	if not DirAccess.dir_exists_absolute(saves_path):
		var err := DirAccess.make_dir_absolute(saves_path)
		if err == OK:
			print("[SaveManager] 已创建存档目录: " + saves_path)
		else:
			print("[SaveManager] 创建存档目录失败: " + str(err))
	else:
		print("[SaveManager] 存档目录已存在: " + saves_path)

# 获取存档文件路径（优先用户目录）
func get_save_path(story_id: String) -> String:
	var sid: String = _sanitize_story_id(story_id)
	if _user_mgr != null and _user_mgr.is_logged_in:
		return _user_mgr.get_save_path_for_user(_user_mgr.get_username(), sid)
	return get_game_root_dir() + "saves/save_" + sid + ".json"

# ============================================================
# 存档存在性检查
# ============================================================
func has_save(story_id: String) -> bool:
	if story_id.is_empty():
		return false
	var sid: String = _sanitize_story_id(story_id)
	# 登录状态优先检查用户目录；若无则回退检查全局目录
	if _user_mgr != null and _user_mgr.is_logged_in:
		var user_path: String = _user_mgr.get_save_path_for_user(_user_mgr.get_username(), sid)
		if FileAccess.file_exists(user_path):
			return true
		var fallback: String = get_game_root_dir() + "saves/save_" + sid + ".json"
		return FileAccess.file_exists(fallback)
	# 未登录：仅检查全局目录
	return FileAccess.file_exists(get_save_path(sid))

# ============================================================
# 自动保存
# ============================================================
func auto_save(
		story_id: String,
		player_clearance: int,
		read_files: Array[String],
		unlocked_passwords: Array[String],
		unlocked_file_passwords: Array[String],
		current_path: String,
		extra_data: Dictionary = {}
	) -> void:
	if story_id.is_empty():
		return
	var sid: String = _sanitize_story_id(story_id)

	# 用户管理器分支（保存到用户目录）
	if _user_mgr != null and _user_mgr.is_logged_in:
		var save_data: Dictionary = {
			"story_id": sid,
			"player_clearance": player_clearance,
			"read_files": read_files,
			"unlocked_passwords": unlocked_passwords,
			"unlocked_file_passwords": unlocked_file_passwords,
			"current_path": current_path
		}
		# 合并额外数据：触发器、邮件、无线电等
		for key in extra_data.keys():
			save_data[key] = extra_data[key]
		_user_mgr.save_story_progress(sid, save_data)
		return

	# 兜底分支（保存到本地 saves/ 目录）
	ensure_saves_dir()
	var save_data_local: Dictionary = {
		"story_id": sid,
		"player_clearance": player_clearance,
		"read_files": read_files,
		"unlocked_passwords": unlocked_passwords,
		"unlocked_file_passwords": unlocked_file_passwords,
		"current_path": current_path
	}
	# 关键修复：兜底也合并 extra_data，确保 mail_data/trigger_data 被写入
	for key in extra_data.keys():
		save_data_local[key] = extra_data[key]

	var path: String = get_save_path(sid)
	print("[SaveManager] 存档路径: " + path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save_data_local, "\t"))
		f.close()
		print("[SaveManager] 已保存: " + path)

# ============================================================
# 加载存档，返回 Dictionary 或 null
# ============================================================
func load_save(story_id: String) -> Variant:
	var sid: String = _sanitize_story_id(story_id)

	# 登录状态：优先用户目录，若无则回退读取全局并迁移
	if _user_mgr != null and _user_mgr.is_logged_in:
		var data_user: Dictionary = _user_mgr.load_story_progress(sid)
		if not data_user.is_empty():
			print("[SaveManager] 从用户目录加载存档: " + _user_mgr.get_username())
			return data_user

		# 回退读取全局存档并迁移
		var fallback_path: String = get_game_root_dir() + "saves/save_" + sid + ".json"
		print("[SaveManager] 用户目录无存档，尝试读取全局存档: " + fallback_path)
		if FileAccess.file_exists(fallback_path):
			var f := FileAccess.open(fallback_path, FileAccess.READ)
			if f != null:
				var json := JSON.new()
				if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
					var fb: Dictionary = json.data
					f.close()
					# 迁移到用户目录
					_user_mgr.save_story_progress(sid, fb)
					print("[SaveManager] 已迁移全局存档到用户目录。")
					return fb
				f.close()
		print("[SaveManager] 用户目录与全局目录均无存档，使用默认设置")
		return null

	# 未登录：旧版兜底逻辑（全局目录）
	var path: String = get_save_path(sid)
	print("[SaveManager] 尝试加载存档: " + path)
	if not FileAccess.file_exists(path):
		print("[SaveManager] 存档不存在，使用默认设置")
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		return null
	var data: Dictionary = json.data if json.data is Dictionary else {}
	# 容忍旧存档里 story_id 还带引号
	var saved_sid: String = _sanitize_story_id(str(data.get("story_id", "")))
	if saved_sid != sid:
		print("[SaveManager] 警告: 存档 story_id 不匹配（已忽略）: ", saved_sid, " vs ", sid)
	print("[SaveManager] 已加载存档: " + path)
	return data

# ============================================================
# 删除存档
# ============================================================
func delete_save(p_story_id: String) -> bool:
	var path: String = get_save_path(p_story_id)
	if FileAccess.file_exists(path):
		var err := DirAccess.remove_absolute(path)
		if err == OK:
			print("[SaveManager] 已删除存档: " + path)
			return true
		else:
			print("[SaveManager] 删除存档失败: " + str(err))
			return false
	print("[SaveManager] 存档不存在: " + path)
	return false

# 删除所有（全局）存档文件（不含用户子目录）
func delete_all_saves() -> int:
	var saves_dir: String = get_game_root_dir() + "saves/"
	var count: int = 0
	if not DirAccess.dir_exists_absolute(saves_dir):
		return 0
	var dir := DirAccess.open(saves_dir)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.begins_with("save_") and file_name.ends_with(".json"):
			var err := DirAccess.remove_absolute(saves_dir + file_name)
			if err == OK:
				count += 1
		file_name = dir.get_next()
	dir.list_dir_end()
	print("[SaveManager] 已删除 " + str(count) + " 个存档")
	return count

# ============================================================
# 工具：清洗 story_id（去首尾引号与空白）
# ============================================================
func _sanitize_story_id(s: String) -> String:
	var sid: String = s.strip_edges()
	if (sid.begins_with("\"") and sid.ends_with("\"")) or (sid.begins_with("'") and sid.ends_with("'")):
		sid = sid.substr(1, sid.length() - 2)
	return sid
	
	
	
	
	
