class_name SaveManager
extends RefCounted

# ============================================================
# 存档管理器 - 负责存档/读档/目录管理/路径工具
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

# 获取存档文件路径
func get_save_path(story_id: String) -> String:
	return get_game_root_dir() + "saves/save_" + story_id + ".json"

# 自动保存
func auto_save(story_id: String, player_clearance: int, read_files: Array[String],
		unlocked_passwords: Array[String], unlocked_file_passwords: Array[String],
		current_path: String) -> void:
	if story_id.is_empty():
		return

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
