# ============================================================
# crtml_parser.gd
# 职责：解析 CRT-ML 自定义标记语言，转换为 BBCode
# 支持：标题、粗体、斜体、删除线、分割线、涂黑遮蔽、SCP标记、
#       颜色、速度控制、延迟、清屏、抖动、超链接、居中、引用、
#       代码、表格、黑幕方块、分页标记
# ============================================================
class_name CrtmlParser
extends RefCounted

var T = null  # ThemeManager.ThemeColors

# ============================================================
# 初始化
# ============================================================
func setup(p_theme) -> void:
	T = p_theme

# ============================================================
# 主解析函数：将 CRT-ML 转换为 BBCode
# 按优先级顺序处理各种标记
# ============================================================
func parse(raw_text: String) -> String:
	if raw_text.is_empty():
		return ""

	var lines: PackedStringArray = raw_text.split("\n")
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
				# 表格结束
				result_lines.append(_render_table(table_rows))
				table_rows.clear()
				in_table = false
			result_lines.append("")
			i += 1
			continue

		# ── 分页标记 ──
		if stripped == "---PAGE---":
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
			# 检查是否是分隔行（如 |---|---|）
			if _is_table_separator(stripped):
				i += 1
				continue
			var cells: Array[String] = _parse_table_row(stripped)
			if not cells.is_empty():
				in_table = true
				table_rows.append(cells)
			i += 1
			continue

		# 如果之前在表格中，但当前行不是表格行，结束表格
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

		# ── 普通行：处理行内标记 ──
		var processed_line: String = _process_inline(line)
		result_lines.append(processed_line)
		i += 1

	# 循环结束后，如果还有未渲染的表格
	if in_table and not table_rows.is_empty():
		result_lines.append(_render_table(table_rows))

	return "\n".join(result_lines)

# ============================================================
# 行内标记处理（按优先级顺序）
# ============================================================
func _process_inline(text: String) -> String:
	var result: String = text

	# 1. CRT-ML 效果标记 {tag} → 转换为 Typewriter 可识别的标签
	result = _parse_effect_tags(result)

	# 2. 超链接 [文本](url)
	result = _parse_links(result)

	# 3. SCP 特殊标记
	result = _parse_scp_markers(result)

	# 4. 涂黑遮蔽 ||文本||
	result = _parse_spoiler(result)

	# 5. 黑幕方块 ████ 自动着色
	result = _parse_black_blocks(result)

	# 6. 粗体 **文本**（必须在斜体之前）
	result = _parse_bold(result)

	# 7. 斜体 *文本*
	result = _parse_italic(result)

	# 8. 删除线 ~~文本~~
	result = _parse_strikethrough(result)

	# 9. 行内代码 `代码`
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
			# 一级标题：上下双线 + 大字
			var line_char: String = "═"
			var border: String = "[color=" + p + "]" + line_char.repeat(40) + "[/color]"
			return border + "\n[color=" + p + "][b]  " + processed_text + "[/b][/color]\n" + border
		2:
			# 二级标题：下划线 + 粗体
			var border: String = "[color=" + p + "]" + "─".repeat(30) + "[/color]"
			return "[color=" + p + "][b]" + processed_text + "[/b][/color]\n" + border
		3:
			# 三级标题：粗体 + 主色
			return "[color=" + p + "][b]" + processed_text + "[/b][/color]"
		_:
			return "[color=" + p + "]" + processed_text + "[/color]"

# ============================================================
# 分割线检测与生成
# ============================================================
func _is_separator(line: String) -> bool:
	# 至少3个连续的 - 或 = 或 ─ 或 ═
	if line.length() < 3:
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
# 分页标记
# ============================================================
func _make_page_break() -> String:
	var m: String = _get_muted_hex()
	var p: String = _get_primary_hex()
	return "\n[color=" + p + "]" + "═".repeat(20) + "[/color] [color=" + m + "][ 下一页 ][/color] [color=" + p + "]" + "═".repeat(20) + "[/color]\n"

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
			# 找到 ** 开始，寻找结束的 **
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
# 斜体 *文本*（单个星号，注意不要和粗体冲突）
# ============================================================
func _parse_italic(text: String) -> String:
	var result: String = ""
	var i: int = 0
	while i < text.length():
		if text[i] == "*":
			# 确保不是 ** （粗体已经处理过了，[b] 标签中不含 *）
			if i + 1 < text.length() and text[i + 1] == "*":
				result += text[i]
				i += 1
				continue
			# 单个 *，寻找匹配的结束 *
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
			# 确保不是 **
			if j + 1 < text.length() and text[j + 1] == "*":
				j += 2
				continue
			return j
		j += 1
	return -1

# ============================================================
# 删除线 ~~文本~~
# ============================================================
func _parse_strikethrough(text: String) -> String:
	var result: String = ""
	var i: int = 0
	while i < text.length():
		if i + 1 < text.length() and text[i] == "~" and text[i + 1] == "~":
			var end_pos: int = text.find("~~", i + 2)
			if end_pos != -1:
				var inner: String = text.substr(i + 2, end_pos - i - 2)
				result += "[s]" + inner + "[/s]"
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
				var m: String = _get_muted_hex()
				result += "[code][color=" + m + "]" + inner + "[/color][/code]"
				i = end_pos + 1
				continue
		result += text[i]
		i += 1
	return result

# ============================================================
# 涂黑遮蔽 ||文本||
# 实现方式：默认显示为黑色方块，通过 [url] 标签包裹
# 点击后可通过 meta_clicked 信号显示原文
# ============================================================
func _parse_spoiler(text: String) -> String:
	var result: String = ""
	var i: int = 0
	while i < text.length():
		if i + 1 < text.length() and text[i] == "|" and text[i + 1] == "|":
			var end_pos: int = text.find("||", i + 2)
			if end_pos != -1:
				var inner: String = text.substr(i + 2, end_pos - i - 2)
				# 生成等长的遮蔽方块，用 url 标签包裹以支持点击显示
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
# [REDACTED] → 红色高亮
# [DATA EXPUNGED] → 红色高亮
# [CLASSIFIED] → 红色高亮
# [ACCESS DENIED] → 红色高亮
# ============================================================
func _parse_scp_markers(text: String) -> String:
	var e: String = _get_error_hex()
	var w: String = _get_warning_hex()
	var result: String = text

	# [REDACTED] 系列
	result = result.replace("[REDACTED]", "[color=" + e + "][b]█ REDACTED █[/b][/color]")
	result = result.replace("[redacted]", "[color=" + e + "][b]█ REDACTED █[/b][/color]")

	# [DATA EXPUNGED] 系列
	result = result.replace("[DATA EXPUNGED]", "[color=" + e + "][b]█ DATA EXPUNGED █[/b][/color]")
	result = result.replace("[data expunged]", "[color=" + e + "][b]█ DATA EXPUNGED █[/b][/color]")

	# [CLASSIFIED]
	result = result.replace("[CLASSIFIED]", "[color=" + w + "][b]◆ CLASSIFIED ◆[/b][/color]")
	result = result.replace("[classified]", "[color=" + w + "][b]◆ CLASSIFIED ◆[/b][/color]")

	# [ACCESS DENIED]
	result = result.replace("[ACCESS DENIED]", "[color=" + e + "][b]⛔ ACCESS DENIED ⛔[/b][/color]")

	# [LEVEL X CLEARANCE REQUIRED]
	for level in range(0, 6):
		var marker: String = "[LEVEL " + str(level) + " CLEARANCE REQUIRED]"
		var replacement: String = "[color=" + w + "][b]⚠ LEVEL " + str(level) + " CLEARANCE REQUIRED ⚠[/b][/color]"
		result = result.replace(marker, replacement)

	return result

# ============================================================
# 黑幕方块 ████ 自动着色（用暗色显示，融入背景）
# ============================================================
func _parse_black_blocks(text: String) -> String:
	# 将连续的 █ 字符用深色包裹
	var result: String = ""
	var i: int = 0
	var in_blocks: bool = false
	var block_buffer: String = ""

	while i < text.length():
		if text[i] == "█":
			if not in_blocks:
				in_blocks = true
				block_buffer = ""
			block_buffer += "█"
		else:
			if in_blocks:
				result += "[color=#222222]" + block_buffer + "[/color]"
				block_buffer = ""
				in_blocks = false
			result += text[i]
		i += 1

	if in_blocks:
		result += "[color=#222222]" + block_buffer + "[/color]"

	return result

# ============================================================
# 超链接
# [显示文本](cmd://命令)  → 执行命令
# [显示文本](file://路径) → 打开文件
# [显示文本](url://网址)  → 外部链接（暂不实现跳转，仅显示）
# ============================================================
func _parse_links(text: String) -> String:
	var result: String = ""
	var i: int = 0

	while i < text.length():
		# 寻找 [ 开始
		if text[i] == "[":
			var bracket_end: int = text.find("]", i + 1)
			if bracket_end != -1 and bracket_end + 1 < text.length() and text[bracket_end + 1] == "(":
				var paren_end: int = text.find(")", bracket_end + 2)
				if paren_end != -1:
					var display_text: String = text.substr(i + 1, bracket_end - i - 1)
					var link_url: String = text.substr(bracket_end + 2, paren_end - bracket_end - 2)

					# 检查是否是 SCP 标记（以 [ 开头但不是链接语法）
					# 如果 display_text 包含已知的 SCP 标记关键词，跳过
					if not link_url.is_empty():
						var p: String = _get_primary_hex()
						var info: String = _get_info_hex()
						if link_url.begins_with("cmd://") or link_url.begins_with("file://"):
							result += "[color=" + p + "][url=" + link_url + "]▸ " + display_text + "[/url][/color]"
						else:
							result += "[color=" + info + "][url=" + link_url + "]" + display_text + "[/url][/color]"
						i = paren_end + 1
						continue

		result += text[i]
		i += 1

	return result

# ============================================================
# 效果标记 {tag} 系列
# 这些标记会被转换为 Typewriter 能识别的 BBCode 标签
# ============================================================
func _parse_effect_tags(text: String) -> String:
	var result: String = text

	# {speed=X} → [speed=X]（Typewriter 已支持）
	var speed_regex := RegEx.new()
	speed_regex.compile("\\{speed=(\\d+\\.?\\d*)\\}")
	result = speed_regex.sub(result, "[speed=$1]", true)
	result = result.replace("{/speed}", "[/speed]")

	# {delay=X} → [pause=X]（Typewriter 已支持 pause）
	var delay_regex := RegEx.new()
	delay_regex.compile("\\{delay=(\\d+)\\}")
	result = delay_regex.sub(result, "[pause=$1]", true)

	# {pause=X} → [pause=X]（直接映射）
	var pause_regex := RegEx.new()
	pause_regex.compile("\\{pause=(\\d+)\\}")
	result = pause_regex.sub(result, "[pause=$1]", true)

	# {clear} → [clear]（Typewriter 需要支持）
	result = result.replace("{clear}", "[clear]")

	# {shake}文本{/shake} → [shake rate=X level=X]文本[/shake]
	result = result.replace("{shake}", "[shake rate=20.0 level=5]")
	result = result.replace("{/shake}", "[/shake]")

	# {wave}文本{/wave} → [wave amp=X freq=X]文本[/wave]
	result = result.replace("{wave}", "[wave amp=30.0 freq=5.0 connected=1]")
	result = result.replace("{/wave}", "[/wave]")

	# {rainbow}文本{/rainbow} → [rainbow]文本[/rainbow]
	result = result.replace("{rainbow}", "[rainbow freq=1.0 sat=0.8 val=0.8]")
	result = result.replace("{/rainbow}", "[/rainbow]")

	# {fade}文本{/fade} → [fade]文本[/fade]
	result = result.replace("{fade}", "[fade start=0 length=10]")
	result = result.replace("{/fade}", "[/fade]")

	# {center}文本{/center} → [center]文本[/center]
	result = result.replace("{center}", "[center]")
	result = result.replace("{/center}", "[/center]")

	# {right}文本{/right} → [right]文本[/right]
	result = result.replace("{right}", "[right]")
	result = result.replace("{/right}", "[/right]")

	# {color:颜色名/hex}文本{/color}
	var color_regex := RegEx.new()
	color_regex.compile("\\{color:([^}]+)\\}")
	var color_matches: Array[RegExMatch] = color_regex.search_all(result)
	# 从后往前替换，避免位置偏移
	for j in range(color_matches.size() - 1, -1, -1):
		var m: RegExMatch = color_matches[j]
		var color_value: String = m.get_string(1)
		var full_match: String = m.get_string(0)
		var color_hex: String = _resolve_color_name(color_value)
		result = result.replace(full_match, "[color=" + color_hex + "]")
	result = result.replace("{/color}", "[/color]")

	# {b}文本{/b} → [b]文本[/b]
	result = result.replace("{b}", "[b]")
	result = result.replace("{/b}", "[/b]")

	# {i}文本{/i} → [i]文本[/i]
	result = result.replace("{i}", "[i]")
	result = result.replace("{/i}", "[/i]")

	# {u}文本{/u} → [u]文本[/u]
	result = result.replace("{u}", "[u]")
	result = result.replace("{/u}", "[/u]")

	# {s}文本{/s} → [s]文本[/s]
	result = result.replace("{s}", "[s]")
	result = result.replace("{/s}", "[/s]")

	# {img=路径} → 图片标记（预留，阶段三实装）
	# {audio=路径} → 音频标记（预留，阶段三实装）
	# {video=路径} → 视频标记（预留，阶段三实装）

	return result

# ============================================================
# 表格解析
# ============================================================
func _is_table_separator(line: String) -> bool:
	# 检查是否是 |---|---| 格式的分隔行
	var inner: String = line.substr(1, line.length() - 2)
	var cells: PackedStringArray = inner.split("|")
	for cell in cells:
		var stripped: String = cell.strip_edges()
		# 分隔行的单元格应该只包含 - 和 :
		var is_sep: bool = true
		for ch in stripped:
			if ch != "-" and ch != ":":
				is_sep = false
				break
		if not is_sep:
			return false
	return true

func _parse_table_row(line: String) -> Array[String]:
	# 去掉首尾 |，按 | 分割
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
	var m: String = _get_muted_hex()

	# 计算每列最大宽度
	var col_count: int = 0
	for row in rows:
		if row.size() > col_count:
			col_count = row.size()

	var col_widths: Array[int] = []
	for c in range(col_count):
		col_widths.append(0)

	for row in rows:
		for c in range(row.size()):
			var cell_text: String = str(row[c])
			# 粗略计算可见字符宽度（不含 BBCode）
			var visible_len: int = _strip_bbcode(cell_text).length()
			if visible_len > col_widths[c]:
				col_widths[c] = visible_len

	# 确保最小宽度
	for c in range(col_widths.size()):
		if col_widths[c] < 4:
			col_widths[c] = 4

	# 构建表格输出
	var lines: Array[String] = []

	# 顶部边框
	var top_border: String = "┌"
	for c in range(col_count):
		top_border += "─".repeat(col_widths[c] + 2)
		if c < col_count - 1:
			top_border += "┬"
	top_border += "┐"
	lines.append("[color=" + p + "]" + top_border + "[/color]")

	for r in range(rows.size()):
		var row: Array = rows[r]
		var row_str: String = "[color=" + p + "]│[/color]"
		for c in range(col_count):
			var cell_text: String = ""
			if c < row.size():
				cell_text = str(row[c])
			var visible_len: int = _strip_bbcode(cell_text).length()
			var padding: int = col_widths[c] - visible_len
			var processed_cell: String = _process_inline(cell_text)

			if r == 0:
				# 表头加粗
				row_str += " [b]" + processed_cell + "[/b]" + " ".repeat(maxi(padding, 0)) + " "
			else:
				row_str += " " + processed_cell + " ".repeat(maxi(padding, 0)) + " "

			row_str += "[color=" + p + "]│[/color]"
		lines.append(row_str)

		# 表头后加分隔线
		if r == 0:
			var mid_border: String = "├"
			for c2 in range(col_count):
				mid_border += "─".repeat(col_widths[c2] + 2)
				if c2 < col_count - 1:
					mid_border += "┼"
			mid_border += "┤"
			lines.append("[color=" + p + "]" + mid_border + "[/color]")

	# 底部边框
	var bottom_border: String = "└"
	for c in range(col_count):
		bottom_border += "─".repeat(col_widths[c] + 2)
		if c < col_count - 1:
			bottom_border += "┴"
	bottom_border += "┘"
	lines.append("[color=" + p + "]" + bottom_border + "[/color]")

	return "\n".join(lines)

# ============================================================
# 辅助：剥离 BBCode 标签，获取纯文本长度
# ============================================================
func _strip_bbcode(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\[/?[^\\]]*\\]")
	return regex.sub(text, "", true)

# ============================================================
# 辅助：颜色名称到 hex 转换
# ============================================================
func _resolve_color_name(name_or_hex: String) -> String:
	var lower: String = name_or_hex.to_lower().strip_edges()

	# 如果已经是 hex 格式，直接返回
	if lower.begins_with("#"):
		return name_or_hex

	# 主题色引用
	match lower:
		"primary": return _get_primary_hex()
		"secondary": return _get_secondary_hex()
		"success": return _get_success_hex()
		"warning": return _get_warning_hex()
		"error": return _get_error_hex()
		"info": return _get_info_hex()
		"muted": return _get_muted_hex()
		"dim": return _get_dim_hex()

	# 常用颜色名
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

	# 无法识别，返回白色
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
