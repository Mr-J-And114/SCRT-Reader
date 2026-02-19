# ============================================================
# header_parser.gd
# 职责：解析文档顶部 ---HEADER--- / ---END_HEADER--- 块
# 提取模板类型、标题、密码、样式、打字速度等元数据
# 返回 { "header": Dictionary, "body": String }
# ============================================================
class_name HeaderParser
extends RefCounted

# ══════════════════════════════════════════
#  头文件标记常量
# ══════════════════════════════════════════
const HEADER_START: String = "---HEADER---"
const HEADER_END: String = "---END_HEADER---"

# ══════════════════════════════════════════
#  支持的模板类型（预留扩展）
# ══════════════════════════════════════════
enum Template {
	DOCUMENT,   # 标准文档
	CHAT,       # 聊天记录（阶段B实现）
	EMAIL,      # 邮件（远景）
	REPORT,     # 报告（远景）
	RAW,        # 原始文本，不解析
}

static var template_map: Dictionary = {
	"document": Template.DOCUMENT,
	"chat": Template.CHAT,
	"email": Template.EMAIL,
	"report": Template.REPORT,
	"raw": Template.RAW,
}

# ══════════════════════════════════════════
#  解析结果结构
# ══════════════════════════════════════════
## 解析文档，返回 { "header": Dictionary, "body": String, "has_header": bool }
##
## header 字段说明：
##   template        : String  — 模板名称（小写），默认 "document"
##   template_enum   : int     — Template 枚举值
##   title           : String  — 文档标题（可选）
##   password        : String  — 文件密码（可选，覆盖 manifest 中的配置）
##   typewriter_speed: float   — 打字速度覆盖（字符/秒，0 表示不覆盖）
##   style           : String  — 临时配色方案名称（可选，文档关闭后恢复）
##   date            : String  — 日期（可选，chat/email 模板用）
##   participants    : Array[String] — 参与者列表（chat 模板用）
##   author          : String  — 作者（可选）
##   classification  : String  — 保密等级标记（可选）
##   custom          : Dictionary — 所有未识别的键值对，供自定义模板使用
##
static func parse(raw_text: String) -> Dictionary:
	var result: Dictionary = {
		"header": {},
		"body": raw_text,
		"has_header": false,
	}

	if raw_text.is_empty():
		return result

	# 查找头文件标记
	var text_stripped: String = raw_text.strip_edges(true, false)
	if not text_stripped.begins_with(HEADER_START):
		return result

	var header_end_pos: int = raw_text.find(HEADER_END)
	if header_end_pos == -1:
		# 有起始标记但没有结束标记，视为无头文件
		push_warning("[HeaderParser] 发现 ---HEADER--- 但缺少 ---END_HEADER---")
		return result

	# 提取头文件块内容
	var header_start_pos: int = raw_text.find(HEADER_START)
	var header_block_start: int = header_start_pos + HEADER_START.length()
	var header_content: String = raw_text.substr(header_block_start, header_end_pos - header_block_start)

	# 提取 body（头文件结束标记之后的所有内容）
	var body_start: int = header_end_pos + HEADER_END.length()
	var body: String = raw_text.substr(body_start)
	# 去掉 body 开头的空行（最多去2行）
	var trim_count: int = 0
	while body.begins_with("\n") and trim_count < 2:
		body = body.substr(1)
		trim_count += 1
	while body.begins_with("\r\n") and trim_count < 2:
		body = body.substr(2)
		trim_count += 1

	# 解析键值对
	var header: Dictionary = _parse_header_fields(header_content)

	result["header"] = header
	result["body"] = body
	result["has_header"] = true

	return result

## 解析头文件块中的键值对
static func _parse_header_fields(content: String) -> Dictionary:
	var header: Dictionary = {
		"template": "document",
		"template_enum": Template.DOCUMENT,
		"title": "",
		"password": "",
		"typewriter_speed": 0.0,
		"style": "",
		"date": "",
		"participants": [] as Array[String],
		"author": "",
		"classification": "",
		"custom": {},
	}

	var lines: PackedStringArray = content.split("\n")
	for line in lines:
		var stripped: String = line.strip_edges()
		if stripped.is_empty():
			continue
		# 跳过注释行
		if stripped.begins_with("#") or stripped.begins_with("//"):
			continue

		# 查找键值分隔符（第一个冒号）
		var colon_pos: int = stripped.find(":")
		if colon_pos == -1:
			continue

		var key: String = stripped.substr(0, colon_pos).strip_edges().to_lower()
		var value: String = stripped.substr(colon_pos + 1).strip_edges()

		# 去除值两端的引号
		value = _unquote(value)

		match key:
			"template":
				var template_lower: String = value.to_lower()
				header["template"] = template_lower
				if template_map.has(template_lower):
					header["template_enum"] = template_map[template_lower]
				else:
					header["template_enum"] = Template.DOCUMENT
					push_warning("[HeaderParser] 未知模板类型: " + value + "，使用默认 document")

			"title":
				header["title"] = value

			"password":
				header["password"] = value

			"typewriter_speed", "tw_speed", "speed":
				if value.is_valid_float():
					header["typewriter_speed"] = value.to_float()

			"style", "theme", "color_scheme":
				header["style"] = value.to_lower()

			"date":
				header["date"] = value

			"participants":
				var parts: PackedStringArray = value.split(",")
				var participants: Array[String] = []
				for part in parts:
					var p: String = part.strip_edges()
					if not p.is_empty():
						participants.append(p)
				header["participants"] = participants

			"author":
				header["author"] = value

			"classification", "clearance":
				header["classification"] = value

			_:
				# 未识别的键值对存入 custom
				header["custom"][key] = value

	return header

## 去除字符串两端的引号（单引号或双引号）
static func _unquote(text: String) -> String:
	if text.length() >= 2:
		if (text.begins_with("\"") and text.ends_with("\"")) or \
		   (text.begins_with("'") and text.ends_with("'")):
			return text.substr(1, text.length() - 2)
	return text

# ══════════════════════════════════════════
#  工具方法
# ══════════════════════════════════════════

## 检查文本是否包含头文件标记（快速判断，不做完整解析）
static func has_header(raw_text: String) -> bool:
	if raw_text.is_empty():
		return false
	var stripped: String = raw_text.strip_edges(true, false)
	return stripped.begins_with(HEADER_START)

## 获取模板枚举值
static func get_template_enum(template_name: String) -> int:
	var lower: String = template_name.to_lower()
	if template_map.has(lower):
		return template_map[lower]
	return Template.DOCUMENT

## 生成文档标题栏 BBCode（供 document 模板在顶部显示标题和元信息）
static func build_title_banner(header: Dictionary, theme_colors) -> String:
	var title: String = str(header.get("title", ""))
	if title.is_empty():
		return ""

	var p: String = theme_colors.primary_hex if theme_colors else "#99FF99"
	var m: String = theme_colors.muted_hex if theme_colors else "#8CAF8C"
	var w: String = theme_colors.warning_hex if theme_colors else "#FFD966"

	var lines: Array[String] = []
	lines.append("[color=" + p + "]" + "═".repeat(50) + "[/color]")

	# 标题
	lines.append("[color=" + p + "][b]  " + title + "[/b][/color]")

	# 元信息行
	var meta_parts: Array[String] = []
	var date: String = str(header.get("date", ""))
	if not date.is_empty():
		meta_parts.append("日期: " + date)
	var author: String = str(header.get("author", ""))
	if not author.is_empty():
		meta_parts.append("作者: " + author)
	var classification: String = str(header.get("classification", ""))
	if not classification.is_empty():
		meta_parts.append("等级: " + classification)

	if not meta_parts.is_empty():
		lines.append("[color=" + m + "]  " + "  |  ".join(meta_parts) + "[/color]")

	lines.append("[color=" + p + "]" + "═".repeat(50) + "[/color]")
	lines.append("")

	return "\n".join(lines)
