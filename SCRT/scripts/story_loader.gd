class_name StoryLoader
extends RefCounted

# 加载结果
var file_system: Dictionary = {}
var manifest: Dictionary = {}
var error_message: String = ""

# 从 .scp (ZIP) 文件加载剧本
func load_story(path: String) -> bool:
	file_system.clear()
	manifest.clear()
	error_message = ""
	
	# 打开ZIP文件
	var reader := ZIPReader.new()
	var err := reader.open(path)
	if err != OK:
		error_message = "无法打开文件: " + path
		return false
	
	# 获取ZIP内所有文件路径
	var files := reader.get_files()
	
	# 第一遍：收集所有文件夹路径
	var folders: Dictionary = {}
	folders["/"] = true
	
	for file_path in files:
		# 跳过空路径
		if file_path.strip_edges().is_empty():
			continue
		
		# 标准化路径：确保以 / 开头
		var clean_path: String = _clean_zip_path(file_path)
		
		# 收集所有父级文件夹
		var parts := clean_path.split("/", false)
		var current := ""
		for i in range(parts.size() - 1):
			current += "/" + parts[i]
			folders[current] = true
		
		# 如果路径本身以 / 结尾，它是文件夹
		if file_path.ends_with("/"):
			folders[clean_path.rstrip("/")] = true
	
	# 注册所有文件夹
	for folder_path in folders.keys():
		if folder_path == "/":
			continue
		file_system[folder_path] = {
			"type": "folder"
		}
	
	# 第二遍：读取所有文件内容
	for file_path in files:
		if file_path.strip_edges().is_empty():
			continue
		if file_path.ends_with("/"):
			continue
		
		var clean_path: String = _clean_zip_path(file_path)
		
		# 读取文件内容
		var content_bytes := reader.read_file(file_path)
		if content_bytes == null:
			continue
		
		var content: String = content_bytes.get_string_from_utf8()

		# 检查是否是 manifest 文件
		var filename: String = clean_path.get_file()
		if filename == "manifest.json":
			_parse_manifest_json(content)
			continue
		if filename == "manifest.cfg":
			_parse_manifest(content)
			continue


		# 注册为文件
		file_system[clean_path] = {
			"type": "file",
			"content": content
		}

	# 检测并去除多余的顶层文件夹前缀
	# 如果所有路径都以同一个文件夹开头，且该文件夹下有manifest，则去除它
	var common_prefix: String = _detect_root_prefix()
	if not common_prefix.is_empty():
		print("[StoryLoader] 检测到顶层文件夹前缀: " + common_prefix + "，自动去除")
		var new_fs: Dictionary = {}
		for key in file_system.keys():
			var new_key: String = key.substr(common_prefix.length())
			if new_key.is_empty():
				continue
			if not new_key.begins_with("/"):
				new_key = "/" + new_key
			new_fs[new_key] = file_system[key]
		file_system = new_fs

	reader.close()
	return true


# 清理ZIP内部路径，统一为 /开头 的格式
func _clean_zip_path(zip_path: String) -> String:
	var path: String = zip_path
	# 去除开头的 ./
	if path.begins_with("./"):
		path = path.substr(2)
	# 去除末尾的 /
	path = path.rstrip("/")
	# 确保以 / 开头
	if not path.begins_with("/"):
		path = "/" + path
	return path


# 检测是否所有文件都在同一个顶层文件夹下
func _detect_root_prefix() -> String:
	if file_system.is_empty():
		return ""
	
	# 收集所有顶层名称
	var first_parts: Dictionary = {}
	for key in file_system.keys():
		var key_str: String = str(key)
		var parts: PackedStringArray = key_str.split("/", false)
		if parts.size() > 0:
			first_parts[parts[0]] = true
	
	# 如果只有一个顶层文件夹，且它在file_system中是folder类型
	if first_parts.size() == 1:
		var prefix_name: String = first_parts.keys()[0]
		var prefix_path: String = "/" + prefix_name
		if file_system.has(prefix_path) and file_system[prefix_path].get("type", "") == "folder":
			return prefix_path
	
	return ""


# 解析 manifest.json
func _parse_manifest_json(content: String) -> void:
	var json := JSON.new()
	var err := json.parse(content)
	if err != OK:
		error_message = "manifest.json 解析失败: 第" + str(json.get_error_line()) + "行 " + json.get_error_message()
		print("[StoryLoader] " + error_message)
		return
	
	if json.data is Dictionary:
		manifest = json.data
		print("[StoryLoader] manifest.json 已加载")
		print("[StoryLoader] 包含字段: " + str(manifest.keys()))
	else:
		error_message = "manifest.json 格式错误"
		print("[StoryLoader] " + error_message)


# 解析 manifest.cfg
func _parse_manifest(content: String) -> void:
	var current_section: String = ""
	
	for line in content.split("\n"):
		line = line.strip_edges()
		
		# 跳过空行和注释
		if line.is_empty() or line.begins_with("#") or line.begins_with(";"):
			continue
		
		# 段落标记 [section]
		if line.begins_with("[") and line.ends_with("]"):
			current_section = line.substr(1, line.length() - 2)
			if not manifest.has(current_section):
				manifest[current_section] = {}
			continue
		
		# 键值对 key=value
		var eq_pos: int = line.find("=")
		if eq_pos > 0 and not current_section.is_empty():
			var key: String = line.substr(0, eq_pos).strip_edges()
			var value: String = line.substr(eq_pos + 1).strip_edges()
			manifest[current_section][key] = value
