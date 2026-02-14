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
var file_system: Dictionary = {}
var story_permissions: Dictionary = {}
var story_file_passwords: Dictionary = {}
var player_clearance: int = 0
var unlocked_file_passwords: Array[String] = []

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
	var clean_path: String = path.rstrip("/")
	var last_slash: int = clean_path.rfind("/")
	if last_slash <= 0:
		return "/"
	return clean_path.substr(0, last_slash)

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
		# 统一换行符，防止\r\n导致双倍行距
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
	for perm_path in story_permissions.keys():
		var perm_value: int = int(float(story_permissions[perm_path]))
		var normalized_perm: String = normalize_path(perm_path)
		if path == normalized_perm:
			highest = max(highest, perm_value)
			continue
		var dir_prefix: String = normalized_perm + "/"
		if path.begins_with(dir_prefix):
			highest = max(highest, perm_value)
	return highest

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
## ★ 关键修复：Box Drawing、Block Elements、几何形状、箭头等符号
##   在 SarasaMonoSC 等宽字体中是 半角（1列），不是宽字符
## 只有 CJK 汉字、CJK 标点、全角 ASCII、日文假名、韩文等才是宽字符
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
	
	# ══════════════════════════════════════════════════════
	# ★ 以下这些在 SarasaMonoSC 等宽字体中都是【半角/1列】
	#   不能标记为宽字符，否则 build_box 宽度计算会出错
	# ══════════════════════════════════════════════════════
	# Box Drawing (U+2500-U+257F): ═║╔╗╚╝╠╣╦╩╬─│ 等 → 半角
	# Block Elements (U+2580-U+259F): █▓▒░ 等 → 半角
	# 几何形状 (U+25A0-U+25FF): ■□● 等 → 半角
	# 箭头 (U+2190-U+21FF): ←→↑↓ 等 → 半角
	# 杂项符号 (U+2600-U+26FF) → 半角
	# Dingbats (U+2700-U+27BF) → 半角
	# 带圈字母数字 (U+2460-U+24FF) → 半角
	
	return false


## 计算字符串的显示宽度（中文/宽字符=2，英文/窄字符=1）
## 自动跳过 BBCode 标签，只计算可见文本宽度
func display_width(text: String) -> int:
	var width: int = 0
	var i: int = 0
	var length: int = text.length()

	while i < length:
		# 跳过 BBCode 标签 [color=...]...[/color] 等
		if text[i] == "[":
			var close_bracket: int = text.find("]", i)
			if close_bracket != -1:
				# 检查是否像 BBCode 标签
				var tag_content: String = text.substr(i + 1, close_bracket - i - 1)
				if tag_content.length() > 0 and (
					tag_content[0] == "/" or
					tag_content.begins_with("color") or
					tag_content.begins_with("b") or
					tag_content.begins_with("i") or
					tag_content.begins_with("u") or
					tag_content.begins_with("s") or
					tag_content.begins_with("url") or
					tag_content.begins_with("font") or
					tag_content.begins_with("img") or
					tag_content.begins_with("cell") or
					tag_content.begins_with("table") or
					tag_content.begins_with("center") or
					tag_content.begins_with("right") or
					tag_content.begins_with("wave") or
					tag_content.begins_with("shake") or
					tag_content.begins_with("rainbow") or
					tag_content.begins_with("tornado") or
					tag_content.begins_with("fade") or
					tag_content.begins_with("pulse")
				):
					i = close_bracket + 1
					continue

		var code: int = text[i].unicode_at(0)
		if _is_wide_char(code):
			width += 2
		else:
			width += 1
		i += 1

	return width


## 生成自适应宽度的文本框
## ★ 修复后版本：由于 Box Drawing 字符（═║╔╗╚╝）现在正确地被识别为
##   半角（1列），所有计算都使用统一的 display_width，逻辑自然自洽
func build_box(lines_data: Array[String], color: String) -> String:
	var max_width: int = 0
	for line in lines_data:
		var w: int = display_width(line)
		if w > max_width:
			max_width = w

	# 内部宽度 = 最宽行 + 左右各2空格padding
	var inner_width: int = max_width + 4

	# 现在 ║ 的 display_width = 1（半角），═ 也是 1
	# 内容行总宽 = ║(1) + inner_width个空格(inner_width) + ║(1) = inner_width + 2
	# 上边框总宽 = ╔(1) + N个═(N) + ╗(1) = N + 2
	# 要对齐：N + 2 = inner_width + 2  →  N = inner_width
	var border_h: String = "═".repeat(inner_width)

	var result: String = ""
	result += "[color=" + color + "]╔" + border_h + "╗[/color]\n"

	for i in range(lines_data.size()):
		var line: String = lines_data[i]
		var line_width: int = display_width(line)
		var pad_total: int = inner_width - line_width
		if pad_total < 0:
			pad_total = 0
		@warning_ignore("integer_division")
		var pad_left: int = pad_total / 2
		var pad_right: int = pad_total - pad_left
		result += "[color=" + color + "]║" + " ".repeat(pad_left) + line + " ".repeat(pad_right) + "║[/color]\n"

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
			result += "[color=" + color + "]║" + " ".repeat(pad_left) + line_str + " ".repeat(pad_right) + "║[/color]\n"
		if s_idx < sections.size() - 1:
			result += "[color=" + color + "]╠" + border_h + "╣[/color]\n"

	result += "[color=" + color + "]╚" + border_h + "╝[/color]"
	return result


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
