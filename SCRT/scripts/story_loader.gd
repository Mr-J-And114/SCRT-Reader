# ============================================================
# story_loader.gd - 剧本加载器
# 负责：从 .scp (ZIP) 文件读取并解析剧本内容
# 支持：UTF-8 / GBK 编码的中文文件名自动识别
# 支持：检测非 ZIP 格式并给出提示
# ============================================================
class_name StoryLoader
extends RefCounted

# 加载结果
var file_system: Dictionary = {}
var manifest: Dictionary = {}
var error_message: String = ""

# GBK 映射表
var _gbk_table: Dictionary = {}
var _gbk_table_loaded: bool = false

# ★ 白名单策略：只有这些扩展名才当作文本文件处理
# 其他所有未知格式一律当作二进制，从根本上杜绝解析崩溃
const TEXT_EXTENSIONS: Array[String] = [
	"txt", "crtml", "cfg", "json", "md", "ini",
	"csv", "xml", "html", "htm", "yaml", "yml",
	"log", "bat", "sh", "py", "gd", "toml",
]

# ============================================================
# 主入口：加载剧本
# ============================================================
func load_story(path: String) -> bool:
	file_system.clear()
	manifest.clear()
	error_message = ""

	# ★ 第0步：检测文件格式
	var format: String = _detect_file_format(path)
	if format == "unknown":
		error_message = "无法识别的文件格式。请确保文件是有效的 ZIP 压缩包。"
		return false
	if format == "rar":
		error_message = "不支持 RAR 格式。请使用 7-Zip 将其转换为 ZIP 格式后重试。\n转换命令: 解压RAR后执行 7z a -mcu=on output.scp *"
		return false
	if format == "7z":
		error_message = "不支持 7z 格式。请使用 7-Zip 将其转换为 ZIP 格式后重试。\n转换命令: 7z e input.7z -o./temp && cd temp && 7z a -mcu=on ../output.scp *"
		return false
	if format != "zip":
		error_message = "不支持的压缩格式: " + format + "。请转换为 ZIP 格式。"
		return false

	# ★ 第1步：手动解析 ZIP 中央目录，获取原始文件名字节
	var raw_entries: Array[Dictionary] = _parse_zip_central_directory(path)

	# ★ 第2步：用 Godot 的 ZIPReader 读取文件内容
	var reader := ZIPReader.new()
	var err := reader.open(path)
	if err != OK:
		error_message = "无法打开文件: " + path
		return false
	var godot_files := reader.get_files()

	# ★ 第3步：构建映射 godot路径 → 修复后路径
	var path_map: Dictionary = {}
	var is_dir_map: Dictionary = {}

	if raw_entries.size() > 0 and raw_entries.size() == godot_files.size():
		print("[StoryLoader] 使用中央目录原始字节解析文件名")
		for i in range(raw_entries.size()):
			var entry: Dictionary = raw_entries[i]
			var godot_path: String = godot_files[i]
			path_map[godot_path] = entry["fixed_path"]
			is_dir_map[godot_path] = entry["is_directory"]
			if godot_path != entry["fixed_path"]:
				print("[StoryLoader]   编码修复: [", godot_path, "] -> [", entry["fixed_path"], "]")
	else:
		print("[StoryLoader] 中央目录解析未完全匹配(", raw_entries.size(), " vs ", godot_files.size(), ")，使用回退方案")
		for f in godot_files:
			path_map[f] = _try_fix_encoding(f)
			is_dir_map[f] = f.ends_with("/")

	# 调试输出
	print("[StoryLoader] ZIP 内文件数量: ", godot_files.size())
	for f in godot_files:
		var display: String = path_map.get(f, f)
		var dir_mark: String = " (dir)" if is_dir_map.get(f, false) else ""
		print("[StoryLoader]   [", display, "]", dir_mark)

	# ★ 第4步：构建虚拟文件系统
	var folders: Dictionary = {}
	folders["/"] = true

	for godot_path in godot_files:
		if godot_path.strip_edges().is_empty():
			continue
		var display_raw: String = path_map.get(godot_path, godot_path)
		var clean_path: String = _clean_zip_path(display_raw)

		# 收集所有父级文件夹
		var parts := clean_path.split("/", false)
		var current := ""
		for i in range(parts.size() - 1):
			current += "/" + parts[i]
			folders[current] = true

		if is_dir_map.get(godot_path, godot_path.ends_with("/")):
			var folder_key: String = clean_path.rstrip("/")
			if not folder_key.is_empty() and folder_key != "/":
				folders[folder_key] = true

	for folder_path in folders.keys():
		if folder_path == "/":
			continue
		file_system[folder_path] = { "type": "folder" }

	# 读取所有文件内容
	for godot_path in godot_files:
		if godot_path.strip_edges().is_empty():
			continue
		if is_dir_map.get(godot_path, godot_path.ends_with("/")):
			continue

		var display_raw: String = path_map.get(godot_path, godot_path)
		var display_path: String = _clean_zip_path(display_raw)
		var content_bytes := reader.read_file(godot_path)
		if content_bytes == null:
			print("[StoryLoader] 警告: 无法读取 [", godot_path, "]")
			continue

		var filename: String = display_path.get_file()
		var ext: String = filename.get_extension().to_lower()

		# ★ 核心修复：使用白名单策略判断文本文件
		# 只有已知的文本扩展名才做 UTF-8 解析
		# 其他一律当作二进制，彻底避免未知格式导致的解析崩溃
		var is_text_file: bool = ext in TEXT_EXTENSIONS

		# manifest 文件无论扩展名都当文本处理
		var is_manifest: bool = (filename == "manifest.json" or filename == "manifest.cfg")
		if is_manifest:
			is_text_file = true

		if not is_text_file:
			# 二进制文件：保存原始字节数据，不做文本解码
			file_system[display_path] = {
				"type": "file",
				"content": "",
				"binary": content_bytes
			}
			print("[StoryLoader]   二进制文件: ", display_path, " (", content_bytes.size(), " bytes)")
			continue

		# 文本文件：解码内容
		var content: String = _decode_text_content(content_bytes)

		if filename == "manifest.json":
			_parse_manifest_json(content)
			continue
		if filename == "manifest.cfg":
			_parse_manifest(content)
			continue

		file_system[display_path] = {
			"type": "file",
			"content": content
		}

	# 去除多余的顶层文件夹前缀
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

	print("[StoryLoader] 最终文件系统路径:")
	for key in file_system.keys():
		var entry: Dictionary = file_system[key]
		var type_str: String = entry.get("type", "?")
		var extra: String = ""
		if entry.has("binary"):
			extra = " [binary: " + str((entry["binary"] as PackedByteArray).size()) + " bytes]"
		print("[StoryLoader]   ", key, " (", type_str, ")", extra)

	return true

# ============================================================
# 检测文件格式（通过魔数/文件头）
# ============================================================
func _detect_file_format(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "unknown"
	if file.get_length() < 4:
		file.close()
		return "unknown"
	var header: PackedByteArray = file.get_buffer(8)
	file.close()
	if header.size() < 4:
		return "unknown"

	if header[0] == 0x50 and header[1] == 0x4B:
		if (header[2] == 0x03 and header[3] == 0x04) or (header[2] == 0x05 and header[3] == 0x06):
			return "zip"

	if (header.size() >= 7 and header[0] == 0x52 and header[1] == 0x61
		and header[2] == 0x72 and header[3] == 0x21
		and header[4] == 0x1A and header[5] == 0x07):
		return "rar"

	if (header.size() >= 6 and header[0] == 0x37 and header[1] == 0x7A
		and header[2] == 0xBC and header[3] == 0xAF
		and header[4] == 0x27 and header[5] == 0x1C):
		return "7z"

	if header[0] == 0x1F and header[1] == 0x8B:
		return "gzip"
	if header[0] == 0x42 and header[1] == 0x5A:
		return "bzip2"

	return "unknown"

# ============================================================
# 手动解析 ZIP 中央目录
# ============================================================
func _parse_zip_central_directory(zip_path: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var file := FileAccess.open(zip_path, FileAccess.READ)
	if file == null:
		return results

	var file_size: int = file.get_length()
	if file_size < 22:
		file.close()
		return results

	var search_start: int = max(0, file_size - 65557)
	var search_len: int = file_size - search_start
	file.seek(search_start)
	var search_buf: PackedByteArray = file.get_buffer(search_len)

	var eocd_offset: int = -1
	for i in range(search_buf.size() - 4, -1, -1):
		if (search_buf[i] == 0x50 and search_buf[i + 1] == 0x4B
			and search_buf[i + 2] == 0x05 and search_buf[i + 3] == 0x06):
			eocd_offset = search_start + i
			break

	if eocd_offset < 0:
		print("[StoryLoader] 未找到 EOCD")
		file.close()
		return results

	file.seek(eocd_offset + 8)
	var _entries_this_disk: int = file.get_16()
	var total_entries: int = file.get_16()
	var cd_size: int = file.get_32()
	var cd_offset: int = file.get_32()

	if cd_offset + cd_size > file_size:
		print("[StoryLoader] 中央目录偏移无效")
		file.close()
		return results

	file.seek(cd_offset)
	var cd_buf: PackedByteArray = file.get_buffer(cd_size)
	file.close()

	# 确保 GBK 表已加载
	_ensure_gbk_table()

	var pos: int = 0
	var count: int = 0
	while pos + 46 <= cd_buf.size() and count < total_entries:
		if not (cd_buf[pos] == 0x50 and cd_buf[pos + 1] == 0x4B
			and cd_buf[pos + 2] == 0x01 and cd_buf[pos + 3] == 0x02):
			break

		var general_flags: int = cd_buf[pos + 8] | (cd_buf[pos + 9] << 8)
		var is_utf8_flag: bool = (general_flags & 0x0800) != 0

		var filename_len: int = cd_buf[pos + 28] | (cd_buf[pos + 29] << 8)
		var extra_len: int = cd_buf[pos + 30] | (cd_buf[pos + 31] << 8)
		var comment_len: int = cd_buf[pos + 32] | (cd_buf[pos + 33] << 8)
		var external_attr: int = (cd_buf[pos + 38] | (cd_buf[pos + 39] << 8)
			| (cd_buf[pos + 40] << 16) | (cd_buf[pos + 41] << 24))

		var name_start: int = pos + 46
		var name_end: int = name_start + filename_len
		if name_end > cd_buf.size():
			break

		var name_bytes: PackedByteArray = cd_buf.slice(name_start, name_end)

		var is_directory: bool = false
		if name_bytes.size() > 0 and name_bytes[-1] == 0x2F:
			is_directory = true
		if (external_attr & 0x10) != 0:
			is_directory = true

		var fixed_name: String = _decode_filename(name_bytes, is_utf8_flag)
		results.append({
			"fixed_path": fixed_name,
			"is_directory": is_directory
		})

		pos = name_end + extra_len + comment_len
		count += 1

	print("[StoryLoader] 中央目录解析完成: ", results.size(), " / ", total_entries)
	return results

# ============================================================
# 解码文件名：先尝试 UTF-8，失败则尝试 GBK
# ============================================================
func _decode_filename(name_bytes: PackedByteArray, force_utf8: bool) -> String:
	if name_bytes.is_empty():
		return ""
	if force_utf8:
		var result: String = name_bytes.get_string_from_utf8()
		if not result.is_empty():
			return result
	# 检查是否全是 ASCII
	var all_ascii: bool = true
	for b in name_bytes:
		if b > 127:
			all_ascii = false
			break
	if all_ascii:
		return name_bytes.get_string_from_ascii()
	# 尝试 UTF-8
	var utf8_result: String = name_bytes.get_string_from_utf8()
	if _is_valid_decoded(utf8_result, name_bytes):
		return utf8_result
	# UTF-8 失败，尝试 GBK
	var gbk_result: String = _decode_gbk_bytes(name_bytes)
	if not gbk_result.is_empty() and gbk_result.find("?") == -1:
		return gbk_result
	# 都失败了，用 UTF-8 结果
	if not utf8_result.is_empty():
		return utf8_result
	return name_bytes.get_string_from_ascii()

# ============================================================
# 解码文本内容（文件正文）
# ============================================================
func _decode_text_content(bytes: PackedByteArray) -> String:
	if bytes.is_empty():
		return ""
	# 检测 BOM
	if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
		return bytes.slice(3).get_string_from_utf8()
	if bytes.size() >= 2 and bytes[0] == 0xFF and bytes[1] == 0xFE:
		return bytes.slice(2).get_string_from_utf16()
	if bytes.size() >= 2 and bytes[0] == 0xFE and bytes[1] == 0xFF:
		var source: PackedByteArray = bytes.slice(2)
		var swapped: PackedByteArray = PackedByteArray()
		swapped.resize(source.size())
		var idx: int = 0
		while idx + 1 < source.size():
			swapped[idx] = source[idx + 1]
			swapped[idx + 1] = source[idx]
			idx += 2
		return swapped.get_string_from_utf16()
	# 尝试 UTF-8
	var utf8_result: String = bytes.get_string_from_utf8()
	if _is_valid_decoded(utf8_result, bytes):
		return utf8_result
	# 尝试 GBK
	var gbk_result: String = _decode_gbk_bytes(bytes)
	if not gbk_result.is_empty() and gbk_result.find("?") == -1:
		return gbk_result
	if not utf8_result.is_empty():
		return utf8_result
	return bytes.get_string_from_ascii()

# ============================================================
# 验证 UTF-8 解码结果是否有效
# ============================================================
func _is_valid_decoded(decoded: String, original_bytes: PackedByteArray) -> bool:
	if decoded.is_empty() and original_bytes.size() > 0:
		return false
	for i in range(decoded.length()):
		if decoded.unicode_at(i) == 0xFFFD:
			return false
	var has_high: bool = false
	for b in original_bytes:
		if b > 127:
			has_high = true
			break
	if has_high:
		var has_non_ascii: bool = false
		for i in range(decoded.length()):
			if decoded.unicode_at(i) > 127:
				has_non_ascii = true
				break
		if not has_non_ascii:
			return false
	return true

# ============================================================
# GBK 解码
# ============================================================
func _decode_gbk_bytes(bytes: PackedByteArray) -> String:
	_ensure_gbk_table()
	if _gbk_table.is_empty():
		return ""
	var result: String = ""
	var i: int = 0
	while i < bytes.size():
		var b1: int = bytes[i]
		if b1 < 0x80:
			result += String.chr(b1)
			i += 1
		elif b1 >= 0x81 and b1 <= 0xFE:
			if i + 1 >= bytes.size():
				result += "?"
				i += 1
				continue
			var b2: int = bytes[i + 1]
			if b2 < 0x40 or b2 == 0x7F or b2 > 0xFE:
				result += "?"
				i += 1
				continue
			var gbk_code: int = (b1 << 8) | b2
			if _gbk_table.has(gbk_code):
				result += String.chr(_gbk_table[gbk_code])
			else:
				result += "?"
			i += 2
		else:
			result += "?"
			i += 1
	return result

# ============================================================
# 加载 GBK 映射表（兼容编辑器和导出后）
# ============================================================
func _ensure_gbk_table() -> void:
	if _gbk_table_loaded:
		return
	_gbk_table_loaded = true

	var search_paths: Array[String] = []
	search_paths.append("res://gbk_unicode.bin")
	if not OS.has_feature("editor"):
		var exe_dir: String = OS.get_executable_path().get_base_dir()
		search_paths.append(exe_dir + "/gbk_unicode.bin")
	search_paths.append("user://gbk_unicode.bin")

	for bin_path in search_paths:
		print("[StoryLoader] 尝试加载 GBK 表: ", bin_path)
		if not FileAccess.file_exists(bin_path):
			print("[StoryLoader]   文件不存在")
			continue
		var file := FileAccess.open(bin_path, FileAccess.READ)
		if file == null:
			print("[StoryLoader]   无法打开: ", FileAccess.get_open_error())
			continue
		var magic: PackedByteArray = file.get_buffer(4)
		if magic.size() < 4 or magic.get_string_from_ascii() != "GBK1":
			print("[StoryLoader]   魔数不匹配")
			file.close()
			continue
		var entry_count: int = file.get_32()
		print("[StoryLoader]   条目数: ", entry_count)
		for idx in range(entry_count):
			if file.get_position() + 4 > file.get_length():
				break
			var gbk_code: int = file.get_16()
			var unicode_cp: int = file.get_16()
			_gbk_table[gbk_code] = unicode_cp
		file.close()
		print("[StoryLoader] GBK 映射表已加载: ", _gbk_table.size(), " 条目 (从 ", bin_path, ")")
		return

	print("[StoryLoader] 未找到 gbk_unicode.bin，使用内嵌常用字符子集")
	_build_builtin_gbk_subset()

# ============================================================
# 内嵌的 GBK 常用子集
# ============================================================
func _build_builtin_gbk_subset() -> void:
	_gbk_table[0xA1A1] = 0x3000
	_gbk_table[0xA1A2] = 0x3001
	_gbk_table[0xA1A3] = 0x3002
	_gbk_table[0xA1A4] = 0x00B7
	_gbk_table[0xA1AA] = 0x2014
	_gbk_table[0xA1AD] = 0x2026
	_gbk_table[0xA1AE] = 0x2018
	_gbk_table[0xA1AF] = 0x2019
	_gbk_table[0xA1B0] = 0x201C
	_gbk_table[0xA1B1] = 0x201D
	_gbk_table[0xA1B6] = 0x3008
	_gbk_table[0xA1B7] = 0x3009
	_gbk_table[0xA1B8] = 0x300C
	_gbk_table[0xA1B9] = 0x300D
	_gbk_table[0xA1BA] = 0x300E
	_gbk_table[0xA1BB] = 0x300F
	_gbk_table[0xA1BC] = 0x3010
	_gbk_table[0xA1BD] = 0x3011
	_gbk_table[0xA1BE] = 0x300A
	_gbk_table[0xA1BF] = 0x300B
	_gbk_table[0xA3A1] = 0xFF01
	_gbk_table[0xA3A8] = 0xFF08
	_gbk_table[0xA3A9] = 0xFF09
	_gbk_table[0xA3AC] = 0xFF0C
	_gbk_table[0xA3AD] = 0xFF0D
	_gbk_table[0xA3AE] = 0xFF0E
	_gbk_table[0xA3BA] = 0xFF1A
	_gbk_table[0xA3BB] = 0xFF1B
	_gbk_table[0xA3BF] = 0xFF1F
	for i in range(10):
		_gbk_table[0xA3B0 + i] = 0xFF10 + i
	for i in range(26):
		_gbk_table[0xA3C1 + i] = 0xFF21 + i
	for i in range(26):
		_gbk_table[0xA3E1 + i] = 0xFF41 + i
	print("[StoryLoader] 内嵌GBK子集: ", _gbk_table.size(), " 条目（仅标点+符号）")
	print("[StoryLoader] ★ 如需完整中文支持，请将 gbk_unicode.bin 放入项目根目录")

# ============================================================
# 旧版回退修复
# ============================================================
func _try_fix_encoding(raw_path: String) -> String:
	var has_high_byte: bool = false
	for i in range(raw_path.length()):
		if raw_path.unicode_at(i) > 127:
			has_high_byte = true
			break
	if not has_high_byte:
		return raw_path
	for i in range(raw_path.length()):
		var code: int = raw_path.unicode_at(i)
		if code >= 0x4E00 and code <= 0x9FFF:
			return raw_path
	var bytes: PackedByteArray = PackedByteArray()
	for i in range(raw_path.length()):
		var code: int = raw_path.unicode_at(i)
		if code < 256:
			bytes.append(code)
		else:
			return raw_path
	var utf8_str: String = bytes.get_string_from_utf8()
	if _is_valid_decoded(utf8_str, bytes):
		return utf8_str
	var gbk_str: String = _decode_gbk_bytes(bytes)
	if not gbk_str.is_empty() and gbk_str.find("?") == -1:
		return gbk_str
	return raw_path

# ============================================================
# 清理ZIP路径
# ============================================================
func _clean_zip_path(zip_path: String) -> String:
	var path_str: String = zip_path
	if path_str.begins_with("./"):
		path_str = path_str.substr(2)
	path_str = path_str.rstrip("/")
	if not path_str.begins_with("/"):
		path_str = "/" + path_str
	return path_str

# ============================================================
# 检测顶层文件夹前缀
# ============================================================
func _detect_root_prefix() -> String:
	if file_system.is_empty():
		return ""
	var first_parts: Dictionary = {}
	for key in file_system.keys():
		var parts: PackedStringArray = str(key).split("/", false)
		if parts.size() > 0:
			first_parts[parts[0]] = true
	if first_parts.size() == 1:
		var prefix_name: String = first_parts.keys()[0]
		var prefix_path: String = "/" + prefix_name
		if file_system.has(prefix_path) and file_system[prefix_path].get("type", "") == "folder":
			return prefix_path
	return ""

# ============================================================
# 解析 manifest.json
# ============================================================
func _parse_manifest_json(content: String) -> void:
	var json := JSON.new()
	var parse_err := json.parse(content)
	if parse_err != OK:
		error_message = "manifest.json 解析失败: 第" + str(json.get_error_line()) + "行 " + json.get_error_message()
		print("[StoryLoader] " + error_message)
		return
	if json.data is Dictionary:
		manifest = json.data
		# ★ 标准化密码表格式（兼容新旧两种写法）
		if manifest.has("passwords"):
			manifest["passwords"] = _normalize_passwords(manifest["passwords"])
		print("[StoryLoader] manifest.json 已加载，字段: ", manifest.keys())
	else:
		error_message = "manifest.json 格式错误"
		print("[StoryLoader] " + error_message)

## ★ 新增：标准化密码表
## 新格式: { "password_string": { "grants_clearance": N, "message": "..." } }
## 旧格式: { "level_number": "password_string" } → 自动转换为新格式
func _normalize_passwords(raw: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in raw.keys():
		var value = raw[key]
		if value is Dictionary:
			# 已经是新格式，直接保留
			result[key] = value
		elif value is String:
			# 旧格式: key 是等级数字字符串, value 是密码字符串
			# 转换: 密码作为 key → { grants_clearance, message }
			result[str(value)] = {
				"grants_clearance": int(float(key)),
				"message": "权限等级已提升至 " + str(key) + "。"
			}
		else:
			push_warning("[StoryLoader] 未知的密码表条目格式: ", key)
	return result



# ============================================================
# 解析 manifest.cfg
# ============================================================
func _parse_manifest(content: String) -> void:
	var current_section: String = ""
	for line in content.split("\n"):
		line = line.strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with(";"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			current_section = line.substr(1, line.length() - 2)
			if not manifest.has(current_section):
				manifest[current_section] = {}
			continue
		var eq_pos: int = line.find("=")
		if eq_pos > 0 and not current_section.is_empty():
			var key: String = line.substr(0, eq_pos).strip_edges()
			var value: String = line.substr(eq_pos + 1).strip_edges()
			manifest[current_section][key] = value
