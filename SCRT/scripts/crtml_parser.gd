# ============================================================
# crtml_parser.gd
# 职责：解析 CRT-ML 自定义标记语言，转换为 BBCode
# 支持：标题、粗体、斜体、删除线、分割线、涂黑遮蔽、SCP标记、
#       颜色、速度控制、延迟、清屏、抖动、超链接、居中、引用、
#       代码、表格、黑幕方块、分页标记、原始文本块、强制不可跳过、
#       多媒体内联标记（图片、音频、视频）
# ============================================================
class_name CrtmlParser
extends RefCounted

var T = null  # ThemeManager.ThemeColors
var fs = null  # FileSystem 引用，用于 display_width 和文件存在性检查

# ★ 原始文本块保护用
var _raw_blocks: Array[String] = []

# ★ 字体路径常量
const FONT_DIR: String = "res://fonts/"
const FONT_REGULAR: String = FONT_DIR + "SarasaMonoSC-Regular.ttf"
const FONT_BOLD: String = FONT_DIR + "SarasaMonoSC-SemiBold.ttf"
const FONT_ITALIC: String = FONT_DIR + "SarasaMonoSC-Italic.ttf"
const FONT_BOLD_ITALIC: String = FONT_DIR + "SarasaMonoSC-SemiBoldItalic.ttf"

# ★ 分页标记常量（供外部 document_viewer / typewriter 识别）
const PAGE_BREAK_TAG: String = "\u0001PAGEBREAK\u0002"

# ============================================================
# 初始化
# ============================================================
func setup(p_theme, p_fs = null) -> void:
	T = p_theme
	fs = p_fs

# ============================================================
# ★ 静态工具：为 RichTextLabel 应用完整字体族覆盖
# 在 ui_manager.gd 和 document_viewer.gd 中调用
# ============================================================
static func apply_fonts(rtl: RichTextLabel) -> void:
	if ResourceLoader.exists(FONT_REGULAR):
		var f: Font = load(FONT_REGULAR)
		if f:
			rtl.add_theme_font_override("normal_font", f)
	if ResourceLoader.exists(FONT_BOLD):
		var f: Font = load(FONT_BOLD)
		if f:
			rtl.add_theme_font_override("bold_font", f)
	# ★ 关键修复：指定真正的斜体字体，避免 Godot 回退到伪粗斜体
	if ResourceLoader.exists(FONT_ITALIC):
		var f: Font = load(FONT_ITALIC)
		if f:
			rtl.add_theme_font_override("italics_font", f)
	if ResourceLoader.exists(FONT_BOLD_ITALIC):
		var f: Font = load(FONT_BOLD_ITALIC)
		if f:
			rtl.add_theme_font_override("bold_italics_font", f)

# ============================================================
# 主解析函数：将 CRT-ML 转换为 BBCode
# ============================================================
func parse(raw_text: String) -> String:
	if raw_text.is_empty():
		return ""

	# 第0步：保护 @@...@@ 原始文本块
	_raw_blocks.clear()
	var protected_text: String = _protect_raw_blocks(raw_text)

	var lines: PackedStringArray = protected_text.split("\n")
	var result_lines: Array[String] = []
	var in_table: bool = false
	var table_rows: Array[Array] = []

	var i: int = 0
	while i < lines.size():
		var line: String = lines[i]
		var stripped: String = line.strip_edges()

		# ── 空行 ──
		if stripped.is_empty():
			if in_table:
				result_lines.append(_render_table(table_rows))
				table_rows.clear()
				in_table = false
			result_lines.append("")
			i += 1
			continue

		# ── 分页标记（★ 必须在分割线检测之前！）──
		if stripped == "---PAGE---":
			if in_table:
				result_lines.append(_render_table(table_rows))
				table_rows.clear()
				in_table = false
			result_lines.append(_make_page_break())
			i += 1
			continue

		# ── 分割线 ──
		if _is_separator(stripped):
			if in_table:
				result_lines.append(_render_table(table_rows))
				table_rows.clear()
				in_table = false
			result_lines.append(_make_separator())
			i += 1
			continue

		# ── 表格行 ──
		if stripped.begins_with("|") and stripped.ends_with("|"):
			if _is_table_separator(stripped):
				i += 1
				continue
			var cells: Array[String] = _parse_table_row(stripped)
			if not cells.is_empty():
				in_table = true
				table_rows.append(cells)
			i += 1
			continue

		# 结束表格
		if in_table:
			result_lines.append(_render_table(table_rows))
			table_rows.clear()
			in_table = false

		# ── 标题 ──
		if stripped.begins_with("###"):
			var title_text: String = stripped.substr(3).strip_edges()
			result_lines.append(_make_heading(title_text, 3))
			i += 1
			continue
		elif stripped.begins_with("##"):
			var title_text: String = stripped.substr(2).strip_edges()
			result_lines.append(_make_heading(title_text, 2))
			i += 1
			continue
		elif stripped.begins_with("# ") or stripped == "#":
			var title_text: String = stripped.substr(1).strip_edges()
			if title_text.is_empty():
				title_text = " "
			result_lines.append(_make_heading(title_text, 1))
			i += 1
			continue

		# ── 引用块 ──
		if stripped.begins_with("> ") or stripped == ">":
			var quote_text: String = stripped.substr(1).strip_edges()
			result_lines.append(_make_quote(quote_text))
			i += 1
			continue

		# ── 普通行 ──
		var processed_line: String = _process_inline(line)
		result_lines.append(processed_line)
		i += 1

	if in_table and not table_rows.is_empty():
		result_lines.append(_render_table(table_rows))

	var final_text: String = "\n".join(result_lines)
	final_text = _restore_raw_blocks(final_text)
	return final_text

# ============================================================
# 原始文本块保护：@@内容@@ → 占位符
# ============================================================
func _protect_raw_blocks(text: String) -> String:
	var result: String = ""
	var i: int = 0
	while i < text.length():
		if i + 1 < text.length() and text[i] == "@" and text[i + 1] == "@":
			var end_pos: int = text.find("@@", i + 2)
			if end_pos != -1:
				var inner: String = text.substr(i + 2, end_pos - i - 2)
				var idx: int = _raw_blocks.size()
				_raw_blocks.append(inner)
				result += "\u0001RAW:" + str(idx) + "\u0002"
				i = end_pos + 2
				continue
		result += text[i]
		i += 1
	return result

func _restore_raw_blocks(text: String) -> String:
	var m: String = _get_muted_hex()
	for idx in range(_raw_blocks.size()):
		var placeholder: String = "\u0001RAW:" + str(idx) + "\u0002"
		var escaped: String = _raw_blocks[idx]
		escaped = escaped.replace("[", "[lb]")
		text = text.replace(placeholder, "[color=" + m + "]" + escaped + "[/color]")
	_raw_blocks.clear()
	return text

# ============================================================
# 行内标记处理（按优先级顺序）
# ============================================================
func _process_inline(text: String) -> String:
	var result: String = text

	# 1. CRT-ML 效果标记 {tag}
	result = _parse_effect_tags(result)

	# 2. SCP 特殊标记（移到链接之前，避免 [REDACTED] 被链接解析干扰）
	result = _parse_scp_markers(result)

	# 3. ★ 多媒体内联标记 ![type](path)（必须在超链接之前，因为 ![ 需要优先匹配）
	result = _parse_media_tags(result)

	# 4. 超链接 [文本](url)
	result = _parse_links(result)

	# 5. 涂黑遮蔽 ||文本||
	result = _parse_spoiler(result)

	# 6. ★ 纯黑标记 {blackout}████{/blackout}（纯黑不发光，保留备用）
	result = _parse_blackout(result)

	# 7. ★ 黑幕方块 ████（CRT 发光效果）
	result = _parse_black_blocks(result)

	# 8. 粗体 **文本**
	result = _parse_bold(result)

	# 9. 斜体 *文本*
	result = _parse_italic(result)

	# 10. 删除线 ~~文本~~
	result = _parse_strikethrough(result)

	# 11. 行内代码 `代码`
	result = _parse_inline_code(result)

	return result

# ============================================================
# 标题
# ============================================================
func _make_heading(text: String, level: int) -> String:
	var p: String = _get_primary_hex()
	var processed_text: String = _process_inline(text)
	match level:
		1:
			var line_char: String = "═"
			var border: String = "[color=" + p + "]" + line_char.repeat(40) + "[/color]"
			return border + "\n[color=" + p + "][b]  " + processed_text + "[/b][/color]\n" + border
		2:
			var border: String = "[color=" + p + "]" + "─".repeat(30) + "[/color]"
			return "[color=" + p + "][b]" + processed_text + "[/b][/color]\n" + border
		3:
			return "[color=" + p + "][b]" + processed_text + "[/b][/color]"
		_:
			return "[color=" + p + "]" + processed_text + "[/color]"

# ============================================================
# 分割线检测与生成
# ============================================================
func _is_separator(line: String) -> bool:
	if line.length() < 3:
		return false
	# ★ 排除分页标记
	if line == "---PAGE---":
		return false
	var first_char: String = line[0]
	if first_char not in ["-", "=", "─", "═", "━"]:
		return false
	for ch in line:
		if ch != first_char:
			return false
	return true

func _make_separator() -> String:
	var p: String = _get_primary_hex()
	return "[color=" + p + "]" + "─".repeat(50) + "[/color]"

# ============================================================
# ★ 分页标记（使用特殊占位符，供 document_viewer 分页）
# ============================================================
func _make_page_break() -> String:
	var m: String = _get_muted_hex()
	var p: String = _get_primary_hex()
	var visual: String = "\n[color=" + p + "]" + "═".repeat(20) + "[/color] [color=" + m + "][ PAGE BREAK ][/color] [color=" + p + "]" + "═".repeat(20) + "[/color]\n"
	return PAGE_BREAK_TAG + visual

# ============================================================
# 引用块
# ============================================================
func _make_quote(text: String) -> String:
	var m: String = _get_muted_hex()
	var processed: String = _process_inline(text)
	return "[color=" + m + "]  ┃ " + processed + "[/color]"

# ============================================================
# 粗体 **文本**
# ============================================================
func _parse_bold(text: String) -> String:
	var result: String = ""
	var i: int = 0
	while i < text.length():
		if i + 1 < text.length() and text[i] == "*" and text[i + 1] == "*":
			var end_pos: int = text.find("**", i + 2)
			if end_pos != -1:
				var inner: String = text.substr(i + 2, end_pos - i - 2)
				result += "[b]" + inner + "[/b]"
				i = end_pos + 2
				continue
		result += text[i]
		i += 1
	return result

# ============================================================
# 斜体 *文本*（单个星号，不和粗体冲突）
# ============================================================
func _parse_italic(text: String) -> String:
	var result: String = ""
	var i: int = 0
	while i < text.length():
		if text[i] == "*":
			if i + 1 < text.length() and text[i + 1] == "*":
				result += text[i]
				i += 1
				continue
			var end_pos: int = _find_single_star(text, i + 1)
			if end_pos != -1:
				var inner: String = text.substr(i + 1, end_pos - i - 1)
				result += "[i]" + inner + "[/i]"
				i = end_pos + 1
				continue
		result += text[i]
		i += 1
	return result

func _find_single_star(text: String, from: int) -> int:
	var j: int = from
	while j < text.length():
		if text[j] == "*":
			if j + 1 < text.length() and text[j + 1] == "*":
				j += 2
				continue
			return j
		j += 1
	return -1

# ============================================================
# ★ 删除线 ~~文本~~（加粗增加可见度）
# ============================================================
func _parse_strikethrough(text: String) -> String:
	var result: String = ""
	var i: int = 0
	var dim: String = _get_dim_hex()
	while i < text.length():
		if i + 1 < text.length() and text[i] == "~" and text[i + 1] == "~":
			var end_pos: int = text.find("~~", i + 2)
			if end_pos != -1:
				var inner: String = text.substr(i + 2, end_pos - i - 2)
				# ★ dim 色 + 粗体删除线，让线条更清晰可见
				result += "[color=" + dim + "][s][b]" + inner + "[/b][/s][/color]"
				i = end_pos + 2
				continue
		result += text[i]
		i += 1
	return result

# ============================================================
# 行内代码 `代码`
# ============================================================
func _parse_inline_code(text: String) -> String:
	var result: String = ""
	var i: int = 0
	while i < text.length():
		if text[i] == "`":
			var end_pos: int = text.find("`", i + 1)
			if end_pos != -1:
				var inner: String = text.substr(i + 1, end_pos - i - 1)
				var m_hex: String = _get_muted_hex()
				result += "[code][color=" + m_hex + "]" + inner + "[/color][/code]"
				i = end_pos + 1
				continue
		result += text[i]
		i += 1
	return result

# ============================================================
# 涂黑遮蔽 ||文本||（点击可显示）
# ============================================================
func _parse_spoiler(text: String) -> String:
	var result: String = ""
	var i: int = 0
	while i < text.length():
		if i + 1 < text.length() and text[i] == "|" and text[i + 1] == "|":
			var end_pos: int = text.find("||", i + 2)
			if end_pos != -1:
				var inner: String = text.substr(i + 2, end_pos - i - 2)
				var block_len: int = inner.length()
				var blocks: String = "█".repeat(block_len)
				result += "[color=#111111][url=spoiler://" + inner.uri_encode() + "]" + blocks + "[/url][/color]"
				i = end_pos + 2
				continue
		result += text[i]
		i += 1
	return result

# ============================================================
# SCP 特殊标记
# ============================================================
func _parse_scp_markers(text: String) -> String:
	var e: String = _get_error_hex()
	var w: String = _get_warning_hex()
	var result: String = text

	# ★ 使用 [lb] [rb] 转义确保方括号在 BBCode 中正确渲染
	result = result.replace("[REDACTED]", "[color=" + e + "][b][lb] REDACTED [rb][/b][/color]")
	result = result.replace("[redacted]", "[color=" + e + "][b][lb] REDACTED [rb][/b][/color]")
	result = result.replace("[DATA EXPUNGED]", "[color=" + e + "][b][lb] DATA EXPUNGED [rb][/b][/color]")
	result = result.replace("[data expunged]", "[color=" + e + "][b][lb] DATA EXPUNGED [rb][/b][/color]")
	result = result.replace("[CLASSIFIED]", "[color=" + w + "][b][lb] CLASSIFIED [rb][/b][/color]")
	result = result.replace("[classified]", "[color=" + w + "][b][lb] CLASSIFIED [rb][/b][/color]")
	result = result.replace("[ACCESS DENIED]", "[color=" + e + "][b][lb]X[rb] ACCESS DENIED [lb]X[rb][/b][/color]")

	for level in range(0, 6):
		var marker: String = "[LEVEL " + str(level) + " CLEARANCE REQUIRED]"
		var replacement: String = "[color=" + w + "][b]/!\\ LEVEL " + str(level) + " CLEARANCE REQUIRED /!\\[/b][/color]"
		result = result.replace(marker, replacement)

	return result

# ============================================================
# ★ 黑幕方块 ████ — CRT 发光效果（正常文字渲染）
# 在 CRT 显示器上 █ 是正常发光的文字块
# ============================================================
func _parse_black_blocks(text: String) -> String:
	var result: String = ""
	var i: int = 0
	var in_blocks: bool = false
	var block_buffer: String = ""
	var dim: String = _get_dim_hex()

	while i < text.length():
		if text[i] == "█":
			if not in_blocks:
				in_blocks = true
				block_buffer = ""
			block_buffer += "█"
		else:
			if in_blocks:
				# ★ dim 主题色发光方块
				result += "[color=" + dim + "]" + block_buffer + "[/color]"
				block_buffer = ""
				in_blocks = false
			result += text[i]
		i += 1

	if in_blocks:
		result += "[color=" + dim + "]" + block_buffer + "[/color]"

	return result

# ============================================================
# ★ 纯黑标记 {blackout}内容{/blackout} — 真正纯黑不发光
# ============================================================
func _parse_blackout(text: String) -> String:
	var result: String = text
	result = result.replace("{blackout}", "[color=#050505]")
	result = result.replace("{/blackout}", "[/color]")
	return result

# ============================================================
# ★ 多媒体内联标记 ![type](path)
# 语法：![image](path) ![audio](path) ![video](path)
# 检查文件是否存在于虚拟文件系统中，不存在则显示占位符
# 存在则生成可点击的 cmd:// 链接，点击后执行 open 命令
# ============================================================
func _parse_media_tags(text: String) -> String:
	var result: String = ""
	var i: int = 0

	while i < text.length():
		# 检测 ![ 起始
		if i + 1 < text.length() and text[i] == "!" and text[i + 1] == "[":
			var bracket_end: int = text.find("]", i + 2)
			if bracket_end != -1 and bracket_end + 1 < text.length() and text[bracket_end + 1] == "(":
				var paren_end: int = text.find(")", bracket_end + 2)
				if paren_end != -1:
					var media_type: String = text.substr(i + 2, bracket_end - i - 2).strip_edges().to_lower()
					var media_path: String = text.substr(bracket_end + 2, paren_end - bracket_end - 2).strip_edges()

					# 验证 media_type 是否合法
					if media_type in ["image", "audio", "video"] and not media_path.is_empty():
						result += _build_media_replacement(media_type, media_path)
						i = paren_end + 1
						continue

		result += text[i]
		i += 1

	return result

## 构建多媒体标记的 BBCode 替换文本
func _build_media_replacement(media_type: String, media_path: String) -> String:
	var p: String = _get_primary_hex()
	var m: String = _get_muted_hex()
	var e: String = _get_error_hex()

	# 检查文件是否存在于虚拟文件系统中
	var file_exists: bool = false
	if fs != null:
		var node = fs.get_node_at_path(media_path)
		if node != null:
			file_exists = true

	if not file_exists:
		# 文件不存在：显示缺失占位符
		return "[color=" + e + "][lb]MISSING FILE: " + media_path + "[rb][/color]"

	# 根据类型选择图标文字（不使用 emoji）
	var icon_text: String = ""
	var type_label: String = ""
	match media_type:
		"image":
			icon_text = "[IMG]"
			type_label = "IMAGE"
		"audio":
			icon_text = "[AUD]"
			type_label = "AUDIO"
		"video":
			icon_text = "[VID]"
			type_label = "VIDEO"

	# 生成可点击链接，点击后通过 cmd:// 协议执行 open 命令
	var file_name: String = media_path.get_file()
	var cmd_url: String = "cmd://open " + media_path

	return "[color=" + m + "]" + icon_text + " [/color][url=" + cmd_url + "][color=" + p + "]" + file_name + "[/color][/url][color=" + m + "] (" + type_label + ")[/color]"

# ============================================================
# 超链接
# ============================================================
func _parse_links(text: String) -> String:
	var result: String = ""
	var i: int = 0

	while i < text.length():
		if text[i] == "[":
			# ★ 跳过已被多媒体标记消费后残留的 BBCode 标签
			# BBCode 标签以 [/ 或 [已知标签名 开头，不应被当作超链接
			var bracket_end: int = text.find("]", i + 1)
			if bracket_end != -1 and bracket_end + 1 < text.length() and text[bracket_end + 1] == "(":
				var paren_end: int = text.find(")", bracket_end + 2)
				if paren_end != -1:
					var display_text: String = text.substr(i + 1, bracket_end - i - 1)
					var link_url: String = text.substr(bracket_end + 2, paren_end - bracket_end - 2)
					if not link_url.is_empty():
						var p: String = _get_primary_hex()
						var info: String = _get_info_hex()
						if link_url.begins_with("cmd://") or link_url.begins_with("file://"):
							result += "[color=" + p + "][url=" + link_url + "] > " + display_text + "[/url][/color]"
						else:
							result += "[color=" + info + "][url=" + link_url + "]" + display_text + "[/url][/color]"
						i = paren_end + 1
						continue
		result += text[i]
		i += 1
	return result

# ============================================================
# 效果标记 {tag} 系列
# ★ speed/pause/delay/clear/noskip 转为不可见占位符
# ============================================================
const _TW_PREFIX: String = "\u0001"
const _TW_SUFFIX: String = "\u0002"

static func make_tw_tag(tag_name: String, value: String = "") -> String:
	if value.is_empty():
		return _TW_PREFIX + "TW:" + tag_name + _TW_SUFFIX
	return _TW_PREFIX + "TW:" + tag_name + "=" + value + _TW_SUFFIX

static func has_tw_tags(text: String) -> bool:
	return text.contains(_TW_PREFIX + "TW:")

static func strip_tw_tags(text: String) -> String:
	var result: String = ""
	var i: int = 0
	while i < text.length():
		if text[i] == _TW_PREFIX:
			var end_pos: int = text.find(_TW_SUFFIX, i)
			if end_pos != -1:
				i = end_pos + 1
				continue
		result += text[i]
		i += 1
	return result

static func find_next_tw_tag(text: String, from: int = 0) -> Dictionary:
	var start: int = text.find(_TW_PREFIX + "TW:", from)
	if start == -1:
		return {}
	var end: int = text.find(_TW_SUFFIX, start)
	if end == -1:
		return {}
	var inner: String = text.substr(start + 4, end - start - 4)
	var tag_name: String = inner
	var tag_value: String = ""
	var eq_pos: int = inner.find("=")
	if eq_pos != -1:
		tag_name = inner.substr(0, eq_pos)
		tag_value = inner.substr(eq_pos + 1)
	return {
		"tag": tag_name,
		"value": tag_value,
		"start": start,
		"end": end + 1
	}

func _parse_effect_tags(text: String) -> String:
	var result: String = text

	# speed
	var speed_regex := RegEx.new()
	speed_regex.compile("\\{speed=(\\d+\\.?\\d*)\\}")
	var speed_matches: Array[RegExMatch] = speed_regex.search_all(result)
	for j in range(speed_matches.size() - 1, -1, -1):
		var sm: RegExMatch = speed_matches[j]
		var speed_val: String = sm.get_string(1)
		result = result.substr(0, sm.get_start()) + make_tw_tag("speed", speed_val) + result.substr(sm.get_end())
	result = result.replace("{/speed}", make_tw_tag("speed_end"))

	# delay
	var delay_regex := RegEx.new()
	delay_regex.compile("\\{delay=(\\d+)\\}")
	var delay_matches: Array[RegExMatch] = delay_regex.search_all(result)
	for j in range(delay_matches.size() - 1, -1, -1):
		var dm: RegExMatch = delay_matches[j]
		var delay_val: String = dm.get_string(1)
		result = result.substr(0, dm.get_start()) + make_tw_tag("pause", delay_val) + result.substr(dm.get_end())

	# pause
	var pause_regex := RegEx.new()
	pause_regex.compile("\\{pause=(\\d+)\\}")
	var pause_matches: Array[RegExMatch] = pause_regex.search_all(result)
	for j in range(pause_matches.size() - 1, -1, -1):
		var pm: RegExMatch = pause_matches[j]
		var pause_val: String = pm.get_string(1)
		result = result.substr(0, pm.get_start()) + make_tw_tag("pause", pause_val) + result.substr(pm.get_end())

	result = result.replace("{clear}", make_tw_tag("clear"))

	# ★ 强制不可跳过 {noskip} / {/noskip}
	result = result.replace("{noskip}", make_tw_tag("noskip"))
	result = result.replace("{/noskip}", make_tw_tag("noskip_end"))

	# RichTextLabel 原生 BBCode 效果
	result = result.replace("{shake}", "[shake rate=20.0 level=5]")
	result = result.replace("{/shake}", "[/shake]")
	result = result.replace("{wave}", "[wave amp=30.0 freq=5.0 connected=1]")
	result = result.replace("{/wave}", "[/wave]")
	result = result.replace("{rainbow}", "[rainbow freq=1.0 sat=0.8 val=0.8]")
	result = result.replace("{/rainbow}", "[/rainbow]")
	result = result.replace("{fade}", "[fade start=0 length=10]")
	result = result.replace("{/fade}", "[/fade]")
	result = result.replace("{center}", "[center]")
	result = result.replace("{/center}", "[/center]")
	result = result.replace("{right}", "[right]")
	result = result.replace("{/right}", "[/right]")

	# {color:颜色名/hex}文本{/color}
	var color_regex := RegEx.new()
	color_regex.compile("\\{color:([^}]+)\\}")
	var color_matches: Array[RegExMatch] = color_regex.search_all(result)
	for j in range(color_matches.size() - 1, -1, -1):
		var cm: RegExMatch = color_matches[j]
		var color_value: String = cm.get_string(1)
		var color_hex: String = _resolve_color_name(color_value)
		result = result.substr(0, cm.get_start()) + "[color=" + color_hex + "]" + result.substr(cm.get_end())
	result = result.replace("{/color}", "[/color]")

	# {b} {i} {u} {s}
	result = result.replace("{b}", "[b]")
	result = result.replace("{/b}", "[/b]")
	result = result.replace("{i}", "[i]")
	result = result.replace("{/i}", "[/i]")
	result = result.replace("{u}", "[u]")
	result = result.replace("{/u}", "[/u]")
	result = result.replace("{s}", "[s]")
	result = result.replace("{/s}", "[/s]")

	return result

# ============================================================
# ★ 表格解析 — 使用 Godot 原生 [table] BBCode，完全自动
# ============================================================
func _is_table_separator(line: String) -> bool:
	var inner: String = line.substr(1, line.length() - 2)
	var cells: PackedStringArray = inner.split("|")
	for cell in cells:
		var stripped: String = cell.strip_edges()
		if stripped.is_empty():
			continue
		var is_sep: bool = true
		for ch in stripped:
			if ch != "-" and ch != ":":
				is_sep = false
				break
		if not is_sep:
			return false
	return true

func _parse_table_row(line: String) -> Array[String]:
	var inner: String = line.substr(1, line.length() - 2)
	var cells: PackedStringArray = inner.split("|")
	var result: Array[String] = []
	for cell in cells:
		result.append(cell.strip_edges())
	return result

func _render_table(rows: Array[Array]) -> String:
	if rows.is_empty():
		return ""

	var p: String = _get_primary_hex()

	# 计算最大列数
	var col_count: int = 0
	for row in rows:
		if row.size() > col_count:
			col_count = row.size()

	# ★ 使用 Godot 原生 [table=N] BBCode
	var result: String = "\n[table=" + str(col_count) + "]"
	for r in range(rows.size()):
		var row: Array = rows[r]
		for c in range(col_count):
			var cell_text: String = ""
			if c < row.size():
				cell_text = str(row[c])
			var processed_cell: String = _process_inline(cell_text)
			if r == 0:
				# 表头：主色加粗
				result += "[cell][color=" + p + "][b] " + processed_cell + " [/b][/color][/cell]"
			else:
				result += "[cell] " + processed_cell + " [/cell]"
	result += "[/table]\n"
	return result

# ============================================================
# 辅助函数
# ============================================================
func _strip_bbcode(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\[/?[^\\]]*\\]")
	return regex.sub(text, "", true)

func _display_width(text: String) -> int:
	if fs != null and fs.has_method("display_width"):
		return fs.display_width(text)
	var w: int = 0
	for ch_idx in range(text.length()):
		var code: int = text.unicode_at(ch_idx)
		if code > 0x7F:
			if (code >= 0x2E80 and code <= 0x9FFF) or \
			   (code >= 0xF900 and code <= 0xFAFF) or \
			   (code >= 0xFE30 and code <= 0xFE4F) or \
			   (code >= 0xFF01 and code <= 0xFF60) or \
			   (code >= 0xFFE0 and code <= 0xFFE6) or \
			   (code >= 0x20000 and code <= 0x2FA1F):
				w += 2
			else:
				w += 1
		else:
			w += 1
	return w

func _resolve_color_name(name_or_hex: String) -> String:
	var lower: String = name_or_hex.to_lower().strip_edges()
	if lower.begins_with("#"):
		return name_or_hex
	match lower:
		"primary": return _get_primary_hex()
		"secondary": return _get_secondary_hex()
		"success": return _get_success_hex()
		"warning": return _get_warning_hex()
		"error": return _get_error_hex()
		"info": return _get_info_hex()
		"muted": return _get_muted_hex()
		"dim": return _get_dim_hex()
	match lower:
		"red": return "#FF4444"
		"green": return "#44FF44"
		"blue": return "#4488FF"
		"yellow": return "#FFFF44"
		"orange": return "#FF8844"
		"purple": return "#AA44FF"
		"cyan": return "#44FFFF"
		"white": return "#FFFFFF"
		"black": return "#000000"
		"gray", "grey": return "#888888"
		"pink": return "#FF88AA"
		"gold": return "#FFD700"
		"silver": return "#C0C0C0"
	return "#FFFFFF"

# ============================================================
# 主题色安全访问
# ============================================================
func _get_primary_hex() -> String:
	return T.primary_hex if T != null else "#99FF99"

func _get_secondary_hex() -> String:
	return T.secondary_hex if T != null else "#66CC66"

func _get_dim_hex() -> String:
	return T.dim_hex if T != null else "#408040"

func _get_success_hex() -> String:
	return T.success_hex if T != null else "#88FF88"

func _get_warning_hex() -> String:
	return T.warning_hex if T != null else "#FFD966"

func _get_error_hex() -> String:
	return T.error_hex if T != null else "#FF7777"

func _get_info_hex() -> String:
	return T.info_hex if T != null else "#88BBFF"

func _get_muted_hex() -> String:
	return T.muted_hex if T != null else "#8CAF8C"
