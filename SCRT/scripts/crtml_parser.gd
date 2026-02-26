# ============================================================
# crtml_parser.gd
# 职责：解析 CRT-ML 自定义标记语言，转换为 BBCode
# 支持：标题、粗体、斜体、删除线、分割线、涂黑遮蔽、SCP标记、
#       颜色、速度控制、延迟、清屏、抖动、超链接、居中、引用、
#       代码、表格、黑幕方块、分页标记、原始文本块、强制不可跳过、
#       多媒体内联标记（图片缩略图、音频播放器、视频占位符）
# ============================================================
class_name CrtmlParser
extends RefCounted

var T = null  # ThemeManager.ThemeColors
var fs = null  # FileSystem 引用，用于 display_width 和文件存在性检查
var main_ref = null  # ★ main 引用，用于获取当前路径做相对→绝对路径转换

# ★ 内联图片缓存（placeholder_id → info dict）
var _inline_image_cache: Dictionary = {}

# ★ 原始文本块保护用
var _raw_blocks: Array[String] = []

# ★ 超链接保护用（防止 BBCode 中的 [ 被 _parse_links 误匹配）
var _link_blocks: Array[Dictionary] = []

# ★ 字体路径常量
const FONT_DIR: String = "res://fonts/"
const FONT_REGULAR: String = FONT_DIR + "SarasaMonoSC-Regular.ttf"
const FONT_BOLD: String = FONT_DIR + "SarasaMonoSC-SemiBold.ttf"
const FONT_ITALIC: String = FONT_DIR + "SarasaMonoSC-Italic.ttf"
const FONT_BOLD_ITALIC: String = FONT_DIR + "SarasaMonoSC-SemiBoldItalic.ttf"

# ★ 分页标记常量（供外部 document_viewer / typewriter 识别）
const PAGE_BREAK_TAG: String = "\u0001PAGEBREAK\u0002"

# ★ 字符单位像素换算常量
const CHAR_WIDTH_PX: float = 9.6
const LINE_HEIGHT_PX: float = 22.0

# ★ 图片默认显示宽度（字符单位）
const IMAGE_DEFAULT_CHAR_WIDTH: int = 48

# ============================================================
# 初始化
# ============================================================
func setup(p_theme, p_fs, p_main = null) -> void:
	T = p_theme
	fs = p_fs
	main_ref = p_main

# ============================================================
# ★ 静态工具：为 RichTextLabel 应用完整字体族覆盖
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
	if ResourceLoader.exists(FONT_ITALIC):
		var f: Font = load(FONT_ITALIC)
		if f:
			rtl.add_theme_font_override("italics_font", f)
	if ResourceLoader.exists(FONT_BOLD_ITALIC):
		var f: Font = load(FONT_BOLD_ITALIC)
		if f:
			rtl.add_theme_font_override("bold_italics_font", f)

# ============================================================
# 内联图片 API
# ============================================================

## 获取本次解析生成的内联图片列表
## 返回 Array[Dictionary]，每项包含:
## { "path", "texture", "width", "height", "placeholder", "original_size" }
func get_inline_images() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in _inline_image_cache:
		result.append(_inline_image_cache[key])
	return result

## 清除内联图片缓存
func clear_inline_image_cache() -> void:
	_inline_image_cache.clear()

# ============================================================
# ★ 路径工具：将相对路径转为绝对路径
# ============================================================
func _resolve_media_path(media_path: String) -> String:
	# 已经是绝对路径
	if media_path.begins_with("/"):
		return media_path
	# 通过 main_ref 获取当前目录拼接
	if main_ref != null and main_ref.has_method("get") == false:
		# main_ref 是 main.gd 节点，有 current_path 属性
		var current_dir: String = ""
		if "current_path" in main_ref:
			current_dir = str(main_ref.current_path)
		if not current_dir.is_empty() and fs != null:
			var joined: String = fs.join_path(current_dir, media_path)
			return fs.normalize_path(joined)
	# 无法解析，原样返回
	return media_path

# ============================================================
# 主解析函数：将 CRT-ML 转换为 BBCode
# ============================================================
func parse(raw_text: String) -> String:
	if raw_text.is_empty():
		return ""

	# 清除上次解析的缓存
	_inline_image_cache.clear()

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

	# 3. ★ 多媒体内联标记 ![type|params](path)（必须在超链接之前）
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
# ★ 黑幕方块 ████ — CRT 发光效果
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
				result += "[color=" + dim + "]" + block_buffer + "[/color]"
				block_buffer = ""
				in_blocks = false
			result += text[i]
		i += 1

	if in_blocks:
		result += "[color=" + dim + "]" + block_buffer + "[/color]"
	return result

# ============================================================
# ★ 纯黑标记 {blackout}内容{/blackout}
# ============================================================
func _parse_blackout(text: String) -> String:
	var result: String = text
	result = result.replace("{blackout}", "[color=#050505]")
	result = result.replace("{/blackout}", "[/color]")
	return result

# ============================================================
# ★ 多媒体内联标记 ![type|params](path)
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
					var type_params: String = text.substr(i + 2, bracket_end - i - 2).strip_edges()
					var media_path: String = text.substr(bracket_end + 2, paren_end - bracket_end - 2).strip_edges()
					var media_type: String = ""
					var params: String = ""
					var pipe_pos: int = type_params.find("|")
					if pipe_pos != -1:
						media_type = type_params.substr(0, pipe_pos).strip_edges().to_lower()
						params = type_params.substr(pipe_pos + 1).strip_edges()
					else:
						media_type = type_params.to_lower()

					if media_type in ["image", "audio", "video"] and not media_path.is_empty():
						result += _build_media_replacement(media_type, media_path, params)
						i = paren_end + 1
						continue
		result += text[i]
		i += 1
	return result

# ============================================================
# ★ 构建多媒体标记的 BBCode 替换文本
# ============================================================
func _build_media_replacement(media_type: String, media_path: String, params: String) -> String:
	var e: String = _get_error_hex()

	# ★ 将相对路径转为绝对路径
	var resolved_path: String = _resolve_media_path(media_path)

	# 检查文件是否存在于虚拟文件系统中
	var file_exists: bool = false
	if fs != null:
		var node = fs.get_node_at_path(resolved_path)
		if node != null:
			file_exists = true

	if not file_exists:
		return "[color=" + e + "][lb]MISSING FILE: " + media_path + "[rb][/color]"

	match media_type:
		"image":
			return _build_image_inline(resolved_path, params)
		"audio":
			return _build_audio_inline(resolved_path, params)
		"video":
			return _build_video_placeholder(resolved_path, params)
	return ""

# ============================================================
# ★ 图片内联渲染
# ============================================================
func _build_image_inline(media_path: String, params: String) -> String:
	var p: String = _get_primary_hex()
	var m: String = _get_muted_hex()
	var info_c: String = _get_info_hex()
	var file_name: String = media_path.get_file()

	# 解析尺寸参数
	var size_info: Dictionary = _parse_size_params(params)

	# 尝试加载图片
	var img_data: PackedByteArray = PackedByteArray()
	var original_size: Vector2 = Vector2.ZERO
	var loaded_texture: ImageTexture = null

	if fs != null and fs.has_method("get_binary_data"):
		img_data = fs.get_binary_data(media_path)
		if not img_data.is_empty():
			var img := Image.new()
			var ext: String = media_path.get_extension().to_lower()
			var err: Error = ERR_FILE_UNRECOGNIZED
			match ext:
				"png": err = img.load_png_from_buffer(img_data)
				"jpg", "jpeg": err = img.load_jpg_from_buffer(img_data)
				"bmp": err = img.load_bmp_from_buffer(img_data)
				"webp": err = img.load_webp_from_buffer(img_data)
				"tga": err = img.load_tga_from_buffer(img_data)
			if err == OK:
				original_size = Vector2(img.get_width(), img.get_height())
				loaded_texture = ImageTexture.create_from_image(img)

	# 计算目标像素尺寸
	var target_px: Vector2 = _calculate_image_pixel_size(size_info, original_size)

	# 构建输出
	var lines: Array[String] = []

	if loaded_texture != null:
		# ★ 缓存纹理信息
		var placeholder_id: String = "INLINE_IMG_" + str(_inline_image_cache.size())
		_inline_image_cache[placeholder_id] = {
			"path": media_path,
			"texture": loaded_texture,
			"width": int(target_px.x),
			"height": int(target_px.y),
			"placeholder": placeholder_id,
			"original_size": original_size,
		}

		# ★ 占位符标记（调用方识别并用 add_image() 替代）
		lines.append("\u0001IMG:" + placeholder_id + "\u0002")

		# 图片下方：文件名 + 查看大图链接
		var size_str: String = str(int(original_size.x)) + "x" + str(int(original_size.y))
		lines.append("[color=" + m + "]  " + file_name + " (" + size_str + ")[/color]  [url=cmd://open " + media_path + "][color=" + info_c + "][ 点击查看大图 ][/color][/url]")
	else:
		# 无法加载图片，显示文本链接
		lines.append("[color=" + m + "][lb]IMG[rb] [/color][url=cmd://open " + media_path + "][color=" + p + "]" + file_name + "[/color][/url][color=" + m + "] (IMAGE)[/color]")

	return "\n".join(lines)

# ============================================================
# ★ 音频内联播放器
# ============================================================
func _build_audio_inline(media_path: String, params: String) -> String:
	var p: String = _get_primary_hex()
	var m: String = _get_muted_hex()
	var info_c: String = _get_info_hex()
	var s: String = _get_success_hex()
	var w: String = _get_warning_hex()
	var file_name: String = media_path.get_file()
	var is_compact: bool = params.to_lower() == "compact"

	# ★ 三种 URL scheme：
	# audio://toggle/ — 播放/暂停切换（如果正在播放同一文件则暂停，否则开始播放）
	# audio://stop	— 停止播放
	# cmd://open	  — 跳转示波器（全功能播放器）
	var cmd_toggle: String = "audio://toggle/" + media_path
	var cmd_stop: String = "audio://stop"
	var cmd_scope: String = "cmd://open " + media_path

	if is_compact:
		# 紧凑模式：▶ filename ⏹ ⟫
		return "[url=" + cmd_toggle + "][color=" + s + "]▶/⏸[/color][/url] [color=" + m + "]" + file_name + "[/color]  [url=" + cmd_stop + "][color=" + w + "]⏹[/color][/url]  [url=" + cmd_scope + "][color=" + info_c + "]⟫ 示波器[/color][/url]"

	# 标准模式：带进度条样式的播放器条
	var bar: String = "░".repeat(20)
	var lines: Array[String] = []

	# 顶部：文件名
	lines.append("[color=" + m + "]┌─ [/color][color=" + p + "]♫ " + file_name + "[/color]")

	# 播放器控制行
	var player_line: String = "[color=" + m + "]│ [/color]"
	player_line += "[url=" + cmd_toggle + "][color=" + s + "] ▶/⏸ [/color][/url]"
	player_line += "[url=" + cmd_stop + "][color=" + w + "] ⏹ [/color][/url]"
	player_line += " [color=" + m + "]" + bar + "[/color]"
	player_line += " [color=" + m + "]--:--/--:--[/color]"
	lines.append(player_line)

	# 底部：提示
	lines.append("[color=" + m + "]└─ [/color][url=" + cmd_scope + "][color=" + info_c + "]⟫ 在示波器中打开[/color][/url][color=" + m + "] (实时波形+完整控制)[/color]")

	return "\n".join(lines)



# ============================================================
# ★ 视频占位符（预留接口）
# ============================================================
# ============================================================
# ★ 视频内联播放器（方案C：信息块 + 控制按钮 + 全屏播放器）
# ============================================================
func _build_video_placeholder(media_path: String, params: String) -> String:
	var p: String = _get_primary_hex()
	var m: String = _get_muted_hex()
	var info_c: String = _get_info_hex()
	var s: String = _get_success_hex()
	var w: String = _get_warning_hex()
	var file_name: String = media_path.get_file()
	var ext: String = media_path.get_extension().to_upper()
	var is_compact: bool = params.to_lower() == "compact"

	# ★ URL scheme 定义：
	# video://play/   — 在全屏视频播放器中打开（主要操作）
	# video://stop	 — 停止当前视频播放并返回
	# cmd://open	   — 等价于 video://play（兼容 open 命令）
	var cmd_play: String = "video://play/" + media_path
	var cmd_stop: String = "video://stop"
	var cmd_open: String = "cmd://open " + media_path

	if is_compact:
		# 紧凑模式：▶ filename [OGV] ⟫
		return "[url=" + cmd_play + "][color=" + s + "]▶ 播放[/color][/url] [color=" + m + "]" + file_name + " [" + ext + "][/color]  [url=" + cmd_stop + "][color=" + w + "]⏹[/color][/url]"

	# 标准模式：带边框的视频信息块
	var lines: Array[String] = []

	# 顶部：文件名 + 格式标签
	lines.append("[color=" + m + "]┌─ [/color][color=" + p + "]▶ VIDEO: " + file_name + "[/color][color=" + m + "]  [" + ext + "][/color]")

	# 控制行：播放 | 停止 | ASCII 进度条占位
	var ctrl_line: String = "[color=" + m + "]│ [/color]"
	ctrl_line += "[url=" + cmd_play + "][color=" + s + "] ▶ 播放 [/color][/url]"
	ctrl_line += "[url=" + cmd_stop + "][color=" + w + "] ⏹ 停止 [/color][/url]"
	ctrl_line += " [color=" + m + "]░░░░░░░░░░░░░░░░░░░░[/color]"
	ctrl_line += " [color=" + m + "]--:--/--:--[/color]"
	lines.append(ctrl_line)

	# 操作提示行
	var hint_line: String = "[color=" + m + "]│ [/color]"
	hint_line += "[color=" + m + "]Space:暂停  ←→:快退/快进  ↑↓:音量  Q/Esc:退出[/color]"
	lines.append(hint_line)

	# 底部：打开全屏播放器链接
	lines.append("[color=" + m + "]└─ [/color][url=" + cmd_open + "][color=" + info_c + "]⟫ 在全屏播放器中打开[/color][/url][color=" + m + "] (CRT效果 + 完整控制)[/color]")

	return "\n".join(lines)


# ============================================================
# ★ 尺寸参数解析
# ============================================================
func _parse_size_params(params: String) -> Dictionary:
	var result: Dictionary = {
		"width_chars": 0,
		"height_lines": 0,
		"mode": "default",
	}
	if params.is_empty():
		return result

	var lower: String = params.to_lower().strip_edges()

	if lower == "compact":
		result["mode"] = "compact"
		return result

	if lower.begins_with("x") and lower.substr(1).is_valid_int():
		result["height_lines"] = lower.substr(1).to_int()
		result["mode"] = "height_only"
		return result

	if lower.contains("x"):
		var parts: PackedStringArray = lower.split("x")
		if parts.size() == 2:
			var w_str: String = parts[0].strip_edges()
			var h_str: String = parts[1].strip_edges()
			if w_str.is_valid_int() and h_str.is_valid_int():
				result["width_chars"] = w_str.to_int()
				result["height_lines"] = h_str.to_int()
				result["mode"] = "exact"
				return result

	if lower.is_valid_int():
		result["width_chars"] = lower.to_int()
		result["mode"] = "width_only"
		return result

	return result

# ============================================================
# ★ 计算图片目标像素尺寸
# ============================================================
func _calculate_image_pixel_size(size_info: Dictionary, original_size: Vector2) -> Vector2:
	var mode: String = str(size_info.get("mode", "default"))
	var w_chars: int = int(size_info.get("width_chars", 0))
	var h_lines: int = int(size_info.get("height_lines", 0))

	if mode == "default":
		w_chars = IMAGE_DEFAULT_CHAR_WIDTH

	var target_w: float = 0.0
	var target_h: float = 0.0

	match mode:
		"default", "width_only":
			if w_chars <= 0:
				w_chars = IMAGE_DEFAULT_CHAR_WIDTH
			target_w = float(w_chars) * CHAR_WIDTH_PX
			if original_size.x > 0 and original_size.y > 0:
				target_h = target_w * (original_size.y / original_size.x)
			else:
				target_h = target_w * 0.75
		"height_only":
			if h_lines <= 0:
				h_lines = 16
			target_h = float(h_lines) * LINE_HEIGHT_PX
			if original_size.x > 0 and original_size.y > 0:
				target_w = target_h * (original_size.x / original_size.y)
			else:
				target_w = target_h * 1.333
		"exact":
			if w_chars <= 0:
				w_chars = IMAGE_DEFAULT_CHAR_WIDTH
			if h_lines <= 0:
				h_lines = 16
			target_w = float(w_chars) * CHAR_WIDTH_PX
			target_h = float(h_lines) * LINE_HEIGHT_PX
		_:
			target_w = float(IMAGE_DEFAULT_CHAR_WIDTH) * CHAR_WIDTH_PX
			if original_size.x > 0 and original_size.y > 0:
				target_h = target_w * (original_size.y / original_size.x)
			else:
				target_h = target_w * 0.75

	# 不超过原始尺寸（防止放大模糊）
	if original_size.x > 0 and original_size.y > 0:
		if target_w > original_size.x:
			var scale_down: float = original_size.x / target_w
			target_w = original_size.x
			target_h *= scale_down

	target_w = maxf(target_w, 32.0)
	target_h = maxf(target_h, 22.0)
	return Vector2(target_w, target_h)

# ============================================================
# 超链接 [文本](url)
# ★ 修复：跳过已经是 BBCode 标签的 [ 开头
# ============================================================
func _parse_links(text: String) -> String:
	var result: String = ""
	var i: int = 0

	while i < text.length():
		if text[i] == "[":
			# ★ 先检测是否是 BBCode 标签（[color=, [b], [/b], [url=, [lb], [rb] 等）
			# 如果 [ 后面跟的是 BBCode 关键字或 /，则不是 CRT-ML 超链接
			if _is_bbcode_tag_start(text, i):
				# 原样保留，找到匹配的 ] 并跳过
				var close_b: int = text.find("]", i + 1)
				if close_b != -1:
					result += text.substr(i, close_b - i + 1)
					i = close_b + 1
					continue
				else:
					result += text[i]
					i += 1
					continue

			# 尝试匹配 [text](url) 格式
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

## ★ 检测 text[pos] 处的 [ 是否是 BBCode 标签的开始
func _is_bbcode_tag_start(text: String, pos: int) -> bool:
	if pos + 1 >= text.length():
		return false

	var close_bracket: int = text.find("]", pos + 1)
	if close_bracket == -1:
		return false

	var tag_content: String = text.substr(pos + 1, close_bracket - pos - 1)
	if tag_content.is_empty():
		return false

	# 关闭标签 [/xxx]
	if tag_content.begins_with("/"):
		return true

	# [lb] [rb] 转义
	if tag_content == "lb" or tag_content == "rb":
		return true

	# 已知 BBCode 标签前缀
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

## ★ 修复：strip_tw_tags 只剥离 TW: 前缀的占位符，保留 IMG: / RAW: / PAGEBREAK 等
static func strip_tw_tags(text: String) -> String:
	var result: String = ""
	var i: int = 0
	while i < text.length():
		if text[i] == _TW_PREFIX:
			# 检查是否是 TW: 占位符
			var check_str: String = text.substr(i, 4)  # "\u0001TW:"
			if check_str == _TW_PREFIX + "TW:":
				var end_pos: int = text.find(_TW_SUFFIX, i)
				if end_pos != -1:
					i = end_pos + 1
					continue
			# 不是 TW: 开头的占位符，原样保留
			result += text[i]
		else:
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

	# ★ 强制不可跳过
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

	# {color:颜色名/hex}
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


	# ══════════════════════════════════════════════════════════
	# ★ 第五阶段：CRT Shader 内联效果标记
	# ══════════════════════════════════════════════════════════

	# --- {glitch} / {glitch=强度或预设} ... {/glitch} ---
	var glitch_regex := RegEx.new()
	glitch_regex.compile("\\{glitch(?:=([^}]*))?\\}")
	var glitch_matches: Array[RegExMatch] = glitch_regex.search_all(result)
	for j in range(glitch_matches.size() - 1, -1, -1):
		var gm: RegExMatch = glitch_matches[j]
		var gval: String = gm.get_string(1) if gm.get_string(1) else "0.5"
		result = result.substr(0, gm.get_start()) + make_tw_tag("fx_glitch", gval) + result.substr(gm.get_end())
	result = result.replace("{/glitch}", make_tw_tag("fx_glitch_end"))

	# --- {screen_shake} / {screen_shake=强度} ... {/screen_shake} ---
	var shake_regex := RegEx.new()
	shake_regex.compile("\\{screen_shake(?:=([^}]*))?\\}")
	var shake_matches: Array[RegExMatch] = shake_regex.search_all(result)
	for j in range(shake_matches.size() - 1, -1, -1):
		var skm: RegExMatch = shake_matches[j]
		var skval: String = skm.get_string(1) if skm.get_string(1) else "0.01"
		result = result.substr(0, skm.get_start()) + make_tw_tag("fx_shake", skval) + result.substr(skm.get_end())
	result = result.replace("{/screen_shake}", make_tw_tag("fx_shake_end"))

	# --- {tear} / {tear=强度} ... {/tear} ---
	var tear_regex := RegEx.new()
	tear_regex.compile("\\{tear(?:=([^}]*))?\\}")
	var tear_matches: Array[RegExMatch] = tear_regex.search_all(result)
	for j in range(tear_matches.size() - 1, -1, -1):
		var tm: RegExMatch = tear_matches[j]
		var tval: String = tm.get_string(1) if tm.get_string(1) else "0.08"
		result = result.substr(0, tm.get_start()) + make_tw_tag("fx_tear", tval) + result.substr(tm.get_end())
	result = result.replace("{/tear}", make_tw_tag("fx_tear_end"))

	# --- {noise} / {noise=强度} ... {/noise} ---
	var noise_regex := RegEx.new()
	noise_regex.compile("\\{noise(?:=([^}]*))?\\}")
	var noise_matches: Array[RegExMatch] = noise_regex.search_all(result)
	for j in range(noise_matches.size() - 1, -1, -1):
		var nm: RegExMatch = noise_matches[j]
		var nval: String = nm.get_string(1) if nm.get_string(1) else "0.8"
		result = result.substr(0, nm.get_start()) + make_tw_tag("fx_noise", nval) + result.substr(nm.get_end())
	result = result.replace("{/noise}", make_tw_tag("fx_noise_end"))

	# --- {effect=effect_id} 触发效果序列（瞬时） ---
	var effect_regex := RegEx.new()
	effect_regex.compile("\\{effect=([^}]+)\\}")
	var effect_matches: Array[RegExMatch] = effect_regex.search_all(result)
	for j in range(effect_matches.size() - 1, -1, -1):
		var em: RegExMatch = effect_matches[j]
		var eid: String = em.get_string(1)
		result = result.substr(0, em.get_start()) + make_tw_tag("fx_effect", eid) + result.substr(em.get_end())

	# --- {preset=预设名} 触发内置预设（瞬时） ---
	var preset_regex := RegEx.new()
	preset_regex.compile("\\{preset=([^}]+)\\}")
	var preset_matches: Array[RegExMatch] = preset_regex.search_all(result)
	for j in range(preset_matches.size() - 1, -1, -1):
		var prm: RegExMatch = preset_matches[j]
		var prname: String = prm.get_string(1)
		result = result.substr(0, prm.get_start()) + make_tw_tag("fx_preset", prname) + result.substr(prm.get_end())

	# --- {blackscreen=毫秒} 黑屏（瞬时触发） ---
	var bs_regex := RegEx.new()
	bs_regex.compile("\\{blackscreen=(\\d+)\\}")
	var bs_matches: Array[RegExMatch] = bs_regex.search_all(result)
	for j in range(bs_matches.size() - 1, -1, -1):
		var bsm: RegExMatch = bs_matches[j]
		var bsval: String = bsm.get_string(1)
		result = result.substr(0, bsm.get_start()) + make_tw_tag("fx_blackscreen", bsval) + result.substr(bsm.get_end())

	# --- {reboot} 重启效果（瞬时触发） ---
	result = result.replace("{reboot}", make_tw_tag("fx_reboot"))

	# --- {sound=路径} 播放音效（瞬时触发） ---
	var sound_regex := RegEx.new()
	sound_regex.compile("\\{sound=([^}]+)\\}")
	var sound_matches: Array[RegExMatch] = sound_regex.search_all(result)
	for j in range(sound_matches.size() - 1, -1, -1):
		var snm: RegExMatch = sound_matches[j]
		var snpath: String = snm.get_string(1)
		result = result.substr(0, snm.get_start()) + make_tw_tag("fx_sound", snpath) + result.substr(snm.get_end())


	return result

# ============================================================
# ★ 表格解析 — 使用 Godot 原生 [table] BBCode
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
	var col_count: int = 0
	for row in rows:
		if row.size() > col_count:
			col_count = row.size()

	var result: String = "\n[table=" + str(col_count) + "]"
	for r in range(rows.size()):
		var row: Array = rows[r]
		for c in range(col_count):
			var cell_text: String = ""
			if c < row.size():
				cell_text = str(row[c])
			var processed_cell: String = _process_inline(cell_text)
			if r == 0:
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
