# ============================================================
# file_system.gd - 虚拟文件系统模块
# 负责：路径操作、节点查询、权限检查、文件密码、文本框构建
# ============================================================
class_name FileSystem
extends RefCounted

# ============================================================
# 节点数据结构
# ============================================================
class FSNode:
	var type: String
	var content: String
	func _init(p_type: String, p_content: String = "") -> void:
		type = p_type
		content = p_content

# ============================================================
# 数据引用（由 main.gd 设置）
# ============================================================
var hidden_dirs: Array[String] = []        # 对用户隐藏的目录列表
var file_system: Dictionary = {}
var story_permissions: Dictionary = {}
var story_file_passwords: Dictionary = {}
var player_clearance: int = 0
var unlocked_file_passwords: Array[String] = []
var ambient_sounds: Dictionary = {}        # 环境音配置 { "/path": { "file": "xxx", "volume": 0.0~1.0 } }

## ★ 新增：路径显示名/元数据 { "/path": { "display_name": "xxx" } }
var path_headers: Dictionary = {}

## ★ 新增：文件描述 { "/dir_path": { "folder_name": "xxx", "folder_description": "xxx", "files": { "name": "desc" } } }
var file_descriptions: Dictionary = {}

# 运行时权限覆盖（触发器 lock/unlock 专用）
var runtime_permissions: Dictionary = {}   # "/path" -> int


## 检查路径是否在隐藏目录中
func is_hidden_path(path: String) -> bool:
	path = normalize_path(path)
	for hidden_dir in hidden_dirs:
		var hidden_path: String = normalize_path("/" + hidden_dir)
		if path == hidden_path or path.begins_with(hidden_path + "/"):
			return true
	return false



# ============================================================
# 路径工具函数
# ============================================================
func join_path(base: String, child: String) -> String:
	if base == "/":
		return "/" + child
	else:
		return base + "/" + child

func get_parent_path(path: String) -> String:
	if path == "/":
		return "/"
	var clean: String = path.rstrip("/")
	var last_slash: int = clean.rfind("/")
	if last_slash <= 0:
		return "/"
	return clean.substr(0, last_slash)

func normalize_path(path: String) -> String:
	if not path.begins_with("/"):
		path = "/" + path
	var parts := path.split("/", false)
	var resolved: Array[String] = []
	for part in parts:
		if part == "..":
			if resolved.size() > 0:
				resolved.pop_back()
		elif part == ".":
			continue
		else:
			resolved.append(part)
	if resolved.is_empty():
		return "/"
	return "/" + "/".join(resolved)

# ============================================================
# 节点查询
# ============================================================
func get_node_at_path(path: String) -> FSNode:
	path = normalize_path(path)
	if path == "/":
		return FSNode.new("folder")
	if file_system.has(path):
		var entry: Dictionary = file_system[path]
		var content: String = entry.get("content", "")
		content = content.replace("\r\n", "\n").replace("\r", "\n")
		return FSNode.new(entry.get("type", "file"), content)
	return null

func get_children_at_path(path: String) -> Array[String]:
	path = normalize_path(path)
	var children: Array[String] = []
	var prefix: String
	if path == "/":
		prefix = "/"
	else:
		prefix = path + "/"
	for key in file_system.keys():
		if key.begins_with(prefix):
			var remainder: String = key.substr(prefix.length())
			if not remainder.contains("/"):
				children.append(remainder)
	children.sort()
	return children

# ============================================================
# 权限检查
# ============================================================
func get_required_clearance(path: String) -> int:
	path = normalize_path(path)
	var highest: int = 0
	# 来自故事包的静态权限
	for perm_path in story_permissions.keys():
		var perm_value: int = int(float(story_permissions[perm_path]))
		var normalized_perm: String = normalize_path(perm_path)
		if path == normalized_perm or path.begins_with(normalized_perm + "/"):
			highest = maxi(highest, perm_value)
	# 运行时覆盖（lock/unlock）
	for perm_path in runtime_permissions.keys():
		var perm_value: int = int(float(runtime_permissions[perm_path]))
		var normalized_perm: String = normalize_path(perm_path)
		if path == normalized_perm or path.begins_with(normalized_perm + "/"):
			highest = maxi(highest, perm_value)
	return highest

func set_required_clearance(path: String, level: int) -> void:
	path = normalize_path(path)
	runtime_permissions[path] = maxi(0, level)


func has_clearance(path: String) -> bool:
	return player_clearance >= get_required_clearance(path)

# ============================================================
# 文件密码
# ============================================================
func get_file_password_key(file_path: String) -> String:
	file_path = normalize_path(file_path)
	for fp_path in story_file_passwords.keys():
		var normalized_fp: String = normalize_path(fp_path)
		if file_path == normalized_fp:
			return fp_path
	return ""

func is_file_password_unlocked(file_path: String) -> bool:
	return unlocked_file_passwords.has(file_path)

# ============================================================
# 显示工具函数
# ============================================================

## 判断一个 Unicode 码点在等宽字体中是否占2列宽度
## SarasaMonoSC 中 Box Drawing / Block Elements 等为半角（1列）
static func _is_wide_char(code: int) -> bool:
	# CJK 统一汉字基本区
	if code >= 0x4E00 and code <= 0x9FFF:
		return true
	# CJK 统一汉字扩展A
	if code >= 0x3400 and code <= 0x4DBF:
		return true
	# CJK 统一汉字扩展B-F (辅助平面)
	if code >= 0x20000 and code <= 0x2FA1F:
		return true
	# CJK 兼容汉字
	if code >= 0xF900 and code <= 0xFAFF:
		return true
	# CJK 标点符号（包括全角空格 U+3000）
	if code >= 0x3000 and code <= 0x303F:
		return true
	# 全角 ASCII / 全角标点
	if code >= 0xFF01 and code <= 0xFF60:
		return true
	# 全角半角转换区的全角部分
	if code >= 0xFFE0 and code <= 0xFFE6:
		return true
	# 日文平假名
	if code >= 0x3040 and code <= 0x309F:
		return true
	# 日文片假名
	if code >= 0x30A0 and code <= 0x30FF:
		return true
	# 韩文音节
	if code >= 0xAC00 and code <= 0xD7AF:
		return true
	# 韩文兼容字母
	if code >= 0x3130 and code <= 0x318F:
		return true
	# 注音符号
	if code >= 0x3100 and code <= 0x312F:
		return true
	# 中文竖排标点
	if code >= 0xFE10 and code <= 0xFE19:
		return true
	# CJK 兼容标点
	if code >= 0xFE30 and code <= 0xFE4F:
		return true
	# 中文小写标点
	if code >= 0xFE50 and code <= 0xFE6F:
		return true
	# Enclosed CJK / 带圈数字
	if code >= 0x3200 and code <= 0x32FF:
		return true
	# Emoji 相关（辅助平面）
	if code >= 0x1F000 and code <= 0x1FAFF:
		return true
	# Box Drawing, Block Elements, 几何形状, 箭头等 → 半角，不处理
	return false

## 计算字符串的显示宽度（中文/宽字符=2，英文/窄字符=1）
## 自动跳过 BBCode 标签，只计算可见文本宽度
func display_width(text: String) -> int:
	var width: int = 0
	var i: int = 0
	var length: int = text.length()

	while i < length:
		if text[i] == "[":
			var close_bracket: int = text.find("]", i)
			if close_bracket != -1:
				var tag_content: String = text.substr(i + 1, close_bracket - i - 1)
				# 更严格的 BBCode 标签检测
				if _is_bbcode_tag(tag_content):
					i = close_bracket + 1
					continue
		var code: int = text[i].unicode_at(0)
		if _is_wide_char(code):
			width += 2
		else:
			width += 1
		i += 1
	return width

## 检查方括号内的内容是否是 BBCode 标签
func _is_bbcode_tag(tag_content: String) -> bool:
	if tag_content.is_empty():
		return false
	# 闭合标签 [/xxx]
	if tag_content[0] == "/":
		return true
	# 已知的 BBCode 标签前缀
	var known_tags: Array[String] = [
		"color", "bgcolor", "fgcolor",
		"b", "i", "u", "s",
		"url", "font", "font_size",
		"img", "cell", "table",
		"center", "right", "left", "fill",
		"indent", "ol", "ul", "li",
		"p", "code",
		"wave", "shake", "rainbow", "tornado", "fade", "pulse",
		"hint",
	]
	for tag in known_tags:
		if tag_content == tag or tag_content.begins_with(tag + "=") or tag_content.begins_with(tag + " "):
			return true
	return false

## 生成自适应宽度的居中文本框
func build_box(lines_data: Array[String], color: String) -> String:
	var max_width: int = 0
	for line in lines_data:
		var w: int = display_width(line)
		if w > max_width:
			max_width = w

	# 内部宽度 = 最宽行 + 左右各2空格 padding
	var inner_width: int = max_width + 4

	var border_h: String = "═".repeat(inner_width)
	var result: String = ""

	result += "[color=" + color + "]╔" + border_h + "╗[/color]\n"

	for line in lines_data:
		var line_width: int = display_width(line)
		var pad_total: int = inner_width - line_width
		if pad_total < 0:
			pad_total = 0
		@warning_ignore("integer_division")
		var pad_left: int = pad_total / 2
		var pad_right: int = pad_total - pad_left
		result += "[color=" + color + "]║[/color]" + " ".repeat(pad_left) + line + " ".repeat(pad_right) + "[color=" + color + "]║[/color]\n"

	result += "[color=" + color + "]╚" + border_h + "╝[/color]"
	return result

## 生成带中间分隔线的自适应方框
func build_box_sectioned(sections: Array, color: String) -> String:
	var max_width: int = 0
	for section in sections:
		for line in section:
			var w: int = display_width(str(line))
			if w > max_width:
				max_width = w

	var inner_width: int = max_width + 4
	var border_h: String = "═".repeat(inner_width)
	var result: String = ""

	result += "[color=" + color + "]╔" + border_h + "╗[/color]\n"

	for s_idx in range(sections.size()):
		var section: Array = sections[s_idx]
		for line in section:
			var line_str: String = str(line)
			var line_width: int = display_width(line_str)
			var pad_total: int = inner_width - line_width
			if pad_total < 0:
				pad_total = 0
			@warning_ignore("integer_division")
			var pad_left: int = pad_total / 2
			var pad_right: int = pad_total - pad_left
			result += "[color=" + color + "]║[/color]" + " ".repeat(pad_left) + line_str + " ".repeat(pad_right) + "[color=" + color + "]║[/color]\n"
		if s_idx < sections.size() - 1:
			result += "[color=" + color + "]╠" + border_h + "╣[/color]\n"

	result += "[color=" + color + "]╚" + border_h + "╝[/color]"
	return result



# ============================================================
# ★ 新增：路径元数据查询
# ============================================================

## 获取路径的显示名称（如果在 manifest.headers 中配置了）
func get_display_name(path: String) -> String:
	path = normalize_path(path)
	if path_headers.has(path):
		return str(path_headers[path].get("display_name", ""))
	return ""

## 获取文件的描述文本
## dir_path: 文件所在目录的路径
## filename: 文件名
func get_file_description(dir_path: String, filename: String) -> String:
	dir_path = normalize_path(dir_path)
	if file_descriptions.has(dir_path):
		var desc_block: Dictionary = file_descriptions[dir_path]
		var files_dict: Dictionary = desc_block.get("files", {}) as Dictionary
		if files_dict.has(filename):
			return str(files_dict[filename])
	return ""

## 获取目录的描述信息
## 返回 { "name": "xxx", "description": "xxx" }，没有则返回空字典
func get_folder_description(dir_path: String) -> Dictionary:
	dir_path = normalize_path(dir_path)
	if file_descriptions.has(dir_path):
		var desc_block: Dictionary = file_descriptions[dir_path]
		return {
			"name": str(desc_block.get("folder_name", "")),
			"description": str(desc_block.get("folder_description", "")),
		}
	return {}




# ============================================================
# 环境音查询
# ============================================================

## 根据当前路径查找应该播放的环境音
## 从当前目录开始向上查找，返回最近的环境音配置
## 返回 { "path": "/目录路径", "file": "音频文件名", "volume": 0.0~1.0 } 或空字典
func get_ambient_for_path(path: String) -> Dictionary:
	path = normalize_path(path)
	
	var check_path: String = path
	while true:
		if ambient_sounds.has(check_path):
			var cfg: Dictionary = ambient_sounds[check_path]
			return {
				"path": check_path,
				"file": cfg.get("file", ""),
				"volume": cfg.get("volume", 1.0)
			}
		
		if check_path == "/":
			break
		
		check_path = get_parent_path(check_path)
	
	return {}



## 获取文件的二进制数据（用于音频、图片等非文本文件）
## 返回 PackedByteArray，如果不存在则返回空数组
func get_binary_data(path: String) -> PackedByteArray:
	path = normalize_path(path)
	if file_system.has(path):
		var entry: Dictionary = file_system[path]
		if entry.has("binary"):
			return entry["binary"] as PackedByteArray
	return PackedByteArray()



# ============================================================
# 内置诊断文件系统（彩蛋 / 无磁盘时的回退）
# ============================================================
func init_test_file_system() -> void:
	file_system = {
		"/welcome.txt": {
			"type": "file",
			"content": "欢迎接入 SCP 基金会安全终端。\n当前无虚拟磁盘载入，系统运行于诊断模式。\n请将 .scp 文件放入 vdisc/ 目录后输入 scan。"
		},
		"/.hidden": { "type": "folder" },
		"/.hidden/note.txt": {
			"type": "file",
			"content": "你找到了隐藏的诊断分区。\n\n[DATA EXPUNGED]\n\n如果你正在阅读这条消息，\n说明你的好奇心已经引起了我们的注意。\n\n不用担心，这不一定是坏事。\n\n- O5-██"
		}
	}

# ============================================================
# 数据重置
# ============================================================
func clear_all() -> void:
	file_system.clear()
	story_permissions.clear()
	story_file_passwords.clear()
	player_clearance = 0
	unlocked_file_passwords.clear()
	ambient_sounds.clear()
	path_headers.clear()
	file_descriptions.clear()
	runtime_permissions.clear()

## 读取指定路径文件的文本内容（供 trigger_system / mail_system 等调用）
func read_text(path: String) -> String:
	var node = get_node_at_path(path)
	if node == null:
		return ""
	if node is Dictionary:
		return str(node.get("content", ""))
	if "content" in node:
		return str(node.content)
	return ""



	
