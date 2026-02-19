class_name SaveManager
extends RefCounted

# ============================================================
# 存档管理器 - 负责存档/读档/目录管理/路径工具
# ============================================================

# ── 用户管理器引用（可选，设置后存档路径改为用户目录）──
var _user_mgr = null

func set_user_manager(um) -> void:
	_user_mgr = um

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

# 获取存档文件路径（如果有用户管理器且已登录，使用用户目录）
func get_save_path(story_id: String) -> String:
	if _user_mgr != null and _user_mgr.is_logged_in:
		return _user_mgr.get_save_path_for_user(_user_mgr.get_username(), story_id)
	return get_game_root_dir() + "saves/save_" + story_id + ".json"

# 检查是否有存档
func has_save(story_id: String) -> bool:
	if story_id.is_empty():
		return false
	return FileAccess.file_exists(get_save_path(story_id))

# 自动保存
func auto_save(story_id: String, player_clearance: int, read_files: Array[String],
		unlocked_passwords: Array[String], unlocked_file_passwords: Array[String],
		current_path: String) -> void:
	if story_id.is_empty():
		return

	# 如果桥接到用户管理器
	if _user_mgr != null and _user_mgr.is_logged_in:
		var save_data: Dictionary = {
			"story_id": story_id,
			"player_clearance": player_clearance,
			"read_files": read_files,
			"unlocked_passwords": unlocked_passwords,
			"unlocked_file_passwords": unlocked_file_passwords,
			"current_path": current_path
		}
		_user_mgr.save_story_progress(story_id, save_data)
		return

	# 旧版兜底逻辑
	var save_dir: String = get_game_root_dir() + "saves/"
	if not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_absolute(save_dir)

	var save_data: Dictionary = {
		"story_id": story_id,
		"player_clearance": player_clearance,
		"read_files": read_files,
		"unlocked_passwords": unlocked_passwords,
		"unlocked_file_passwords": unlocked_file_passwords,
		"current_path": current_path
	}

	var save_path: String = get_save_path(story_id)
	print("[SaveManager] 存档路径: " + save_path)

	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close()
		print("[SaveManager] 已保存: " + save_path)

# 加载存档，返回 Dictionary 或 null
func load_save(story_id: String) -> Variant:
	# 如果桥接到用户管理器
	if _user_mgr != null and _user_mgr.is_logged_in:



		var data: Dictionary = _user_mgr.load_story_progress(story_id)
		if not data.is_empty():
			print("[SaveManager] 从用户目录加载存档: " + _user_mgr.get_username())
			return data
		print("[SaveManager] 用户目录无存档，使用默认设置")
		return null

	# 旧版兜底逻辑
	var path: String = get_save_path(story_id)
	print("[SaveManager] 尝试加载存档: " + path)

	if not FileAccess.file_exists(path):
		print("[SaveManager] 存档不存在，使用默认设置")
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null

	var json_text: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_text) != OK:
		return null

	var data: Dictionary = json.data
	if data.get("story_id", "") != story_id:
		return null

	print("[SaveManager] 已加载存档: " + path)
	return data

## 删除指定故事的存档
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

## 删除所有存档
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
