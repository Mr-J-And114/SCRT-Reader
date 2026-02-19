# ============================================================
# document_viewer.gd - 全屏分页文档查看器（节点布局版）
# 通过动态创建 UI 节点实现真正的双栏布局
# ============================================================
class_name DocumentViewer
extends RefCounted

# ══════════════════════════════════════════
#  模块引用
# ══════════════════════════════════════════
var main = null
var fs: FileSystem = null
var T = null

# ══════════════════════════════════════════
#  查看器状态
# ══════════════════════════════════════════
var is_active: bool = false
var pages: Array[Dictionary] = []
var current_page: int = 0
var total_pages: int = 0
var viewer_title: String = ""
var viewer_type: String = ""
var _on_exit_callback: Callable = Callable()

# ══════════════════════════════════════════
#  UI 节点引用
# ══════════════════════════════════════════
var overlay: Panel = null
var title_label: RichTextLabel = null
var left_page: RichTextLabel = null
var right_page: RichTextLabel = null
var separator_line: Panel = null
var nav_label: RichTextLabel = null

# 缓存
var _cached_input_visible: bool = true
var _cached_prompt_visible: bool = true
var _cached_output_text: String = ""

var _typing_left: bool = false
var _typing_right: bool = false
var _type_timer: float = 0.0
var _type_speed: float = 0.03  # 每行的间隔（秒）
var _left_lines: PackedStringArray = []
var _right_lines: PackedStringArray = []
var _left_line_index: int = 0
var _right_line_index: int = 0

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(p_main, p_fs, p_theme) -> void:
	main = p_main
	fs = p_fs
	T = p_theme

# ══════════════════════════════════════════
#  构建 UI 节点（首次调用时创建，之后复用）
# ══════════════════════════════════════════
func _ensure_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		return

	var theme_colors = ThemeManager.current

	# ════════════════════════════════════
	#  最外层：Panel，挂到 Main（根 Control）上
	# ════════════════════════════════════
	overlay = Panel.new()
	overlay.name = "DocumentViewerOverlay"
	overlay.visible = false

	# 透明背景（不需要遮挡，因为我们会清空 output_text）
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0)
	overlay.add_theme_stylebox_override("panel", bg_style)

	# ★ 挂到 Main（根节点）
	var root_control: Control = main as Control
	root_control.add_child(overlay)

	# ★ 把 overlay 移到 CRTEffect 之前
	var crt_node: Node = root_control.get_node_or_null("CRTEffect")
	if crt_node:
		root_control.move_child(overlay, crt_node.get_index())

	# 初始设为全屏，后续在 open() 中对齐到 OutputArea
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.offset_left = 0
	overlay.offset_top = 0
	overlay.offset_right = 0
	overlay.offset_bottom = 0

	# ════════════════════════════════════
	#  MarginContainer 提供内边距
	# ════════════════════════════════════
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 0
	margin.offset_top = 0
	margin.offset_right = 0
	margin.offset_bottom = 0
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	overlay.add_child(margin)

	# ════════════════════════════════════
	#  VBoxContainer 垂直布局
	# ════════════════════════════════════
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# ════════════════════════════════════
	#  中间内容区：HBoxContainer
	# ════════════════════════════════════
	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 0)
	vbox.add_child(hbox)

	# ── 左页（带 margin 包裹）──
	var left_margin := MarginContainer.new()
	left_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_margin.add_theme_constant_override("margin_left", 8)
	left_margin.add_theme_constant_override("margin_right", 12)
	left_margin.add_theme_constant_override("margin_top", 0)
	left_margin.add_theme_constant_override("margin_bottom", 0)
	hbox.add_child(left_margin)

	left_page = _create_page_rtl(theme_colors)
	left_margin.add_child(left_page)

	# ── 竖直分隔线 ──
	separator_line = Panel.new()
	separator_line.custom_minimum_size = Vector2(1, 0)
	separator_line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vsep_style := StyleBoxFlat.new()
	if theme_colors:
		vsep_style.bg_color = theme_colors.muted
	else:
		vsep_style.bg_color = Color(0.4, 0.4, 0.2, 0.6)
	vsep_style.content_margin_left = 0
	vsep_style.content_margin_right = 0
	separator_line.add_theme_stylebox_override("panel", vsep_style)
	hbox.add_child(separator_line)

	# ── 右页（带 margin 包裹）──
	var right_margin := MarginContainer.new()
	right_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_margin.add_theme_constant_override("margin_left", 12)
	right_margin.add_theme_constant_override("margin_right", 8)
	right_margin.add_theme_constant_override("margin_top", 0)
	right_margin.add_theme_constant_override("margin_bottom", 0)
	hbox.add_child(right_margin)

	right_page = _create_page_rtl(theme_colors)
	right_margin.add_child(right_page)

	# ════════════════════════════════════
	#  底部导航栏
	# ════════════════════════════════════
	nav_label = RichTextLabel.new()
	nav_label.bbcode_enabled = true
	nav_label.fit_content = true
	nav_label.scroll_active = false
	nav_label.selection_enabled = false
	nav_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if theme_colors:
		nav_label.add_theme_color_override("default_color", theme_colors.muted)
	vbox.add_child(nav_label)

## 将 overlay 对齐到 OutputArea 的位置和大小
func _align_overlay_to_output_area() -> void:
	if overlay == null or not is_instance_valid(overlay):
		return
	var output_area: ScrollContainer = main.scroll_container
	var rect: Rect2 = output_area.get_global_rect()
	overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	overlay.position = rect.position
	overlay.size = rect.size

## 创建一个页面用的 RichTextLabel
func _create_page_rtl(theme_colors) -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = false
	rtl.scroll_active = true
	rtl.scroll_following = false
	rtl.selection_enabled = true
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rtl.size_flags_stretch_ratio = 1.0
	rtl.mouse_filter = Control.MOUSE_FILTER_STOP

	CrtmlParser.apply_fonts(rtl)
	UIManager._apply_bold_font(rtl)

	# ★ 表格间距
	rtl.add_theme_constant_override("table_h_separation", 16)
	rtl.add_theme_constant_override("table_v_separation", 4)

	if theme_colors:
		rtl.add_theme_color_override("default_color", theme_colors.secondary)
		rtl.add_theme_color_override("font_color", theme_colors.secondary)

	# ★ 连接 meta_clicked 信号到 main 的统一处理函数
	if main != null and main.has_method("_on_meta_clicked"):
		rtl.meta_clicked.connect(main._on_meta_clicked)

	return rtl

# ══════════════════════════════════════════
#  打开查看器
# ══════════════════════════════════════════
func open(p_type: String, p_pages: Array[Dictionary], p_title: String = "", p_on_exit: Callable = Callable()) -> void:
	if p_pages.is_empty():
		return

	_ensure_overlay()

	viewer_type = p_type
	viewer_title = p_title

	# ★ 先对齐 overlay 尺寸（自动分页需要知道可视区域大小）
	_align_overlay_to_output_area()

	# ★ 自动分页处理
	pages = _auto_paginate(p_pages)
	current_page = 0
	total_pages = pages.size()
	_on_exit_callback = p_on_exit

	is_active = true

	# 缓存并隐藏终端元素
	_cached_input_visible = main.input_field.visible
	_cached_prompt_visible = main.prompt_label.visible
	main.input_field.visible = false
	main.prompt_label.visible = false

	# ★ 缓存并清空 output_text，这样背景logo就能正确显示，不会有文字穿透
	_cached_output_text = main.output_text.text
	main.output_text.text = ""

	# 更新状态栏
	main.path_label.text = "DOCUMENT VIEWER | " + p_title + " | Q/Esc 退出"

	# 显示覆盖层
	overlay.visible = true

	# 渲染
	_render_current_page()

# ══════════════════════════════════════════
#  关闭查看器
# ══════════════════════════════════════════
func close() -> void:
	if not is_active:
		return
	is_active = false

	# 隐藏覆盖层
	if overlay and is_instance_valid(overlay):
		overlay.visible = false

	# ★ 恢复 output_text 内容
	main.output_text.text = ""
	main.output_text.append_text(_cached_output_text)
	_cached_output_text = ""

	# 恢复终端
	main.input_field.visible = _cached_input_visible
	main.prompt_label.visible = _cached_prompt_visible
	main._update_status_bar()
	main.input_field.grab_focus()

	# 回调
	if _on_exit_callback.is_valid():
		_on_exit_callback.call()

	# 清理数据（不销毁节点，下次复用）
	pages.clear()
	current_page = 0
	total_pages = 0
	viewer_type = ""
	viewer_title = ""

# ══════════════════════════════════════════
#  ★ 获取当前活动的页面 RichTextLabel
#  供外部追加音频状态信息等
# ══════════════════════════════════════════
func get_active_page_rtl() -> RichTextLabel:
	if not is_active:
		return null
	# 优先返回左页（当前正在显示的主页面）
	if left_page != null and is_instance_valid(left_page) and left_page.visible:
		return left_page
	if right_page != null and is_instance_valid(right_page) and right_page.visible:
		return right_page
	return null

# ══════════════════════════════════════════
#  键盘输入处理
# ══════════════════════════════════════════
func handle_input(event: InputEvent) -> bool:
	if not is_active:
		return false

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE, KEY_Q:
				close()
				return true
			KEY_LEFT, KEY_A, KEY_PAGEUP:
				prev_page()
				return true
			KEY_RIGHT, KEY_D, KEY_PAGEDOWN, KEY_SPACE:
				if _typing_left or _typing_right:
					_skip_typing()
					return true
				next_page()
				return true
			KEY_HOME:
				go_to_page(0)
				return true
			KEY_END:
				go_to_page(total_pages - 1)
				return true

	return false

# ══════════════════════════════════════════
#  翻页
# ══════════════════════════════════════════
func next_page() -> void:
	if total_pages >= 2:
		if current_page + 2 < total_pages:
			current_page += 2
			_render_current_page()
	else:
		if current_page < total_pages - 1:
			current_page += 1
			_render_current_page()

func prev_page() -> void:
	if total_pages >= 2:
		if current_page >= 2:
			current_page -= 2
			_render_current_page()
	else:
		if current_page > 0:
			current_page -= 1
			_render_current_page()

func go_to_page(page_index: int) -> void:
	if total_pages >= 2:
		@warning_ignore("integer_division")
		page_index = (page_index / 2) * 2
	page_index = clampi(page_index, 0, total_pages - 1)
	if page_index != current_page:
		current_page = page_index
		_render_current_page()

# ══════════════════════════════════════════
#  渲染当前页
# ══════════════════════════════════════════
func _render_current_page() -> void:
	if pages.is_empty():
		return

	_typing_left = false
	_typing_right = false

	# ── 左页 ──
	left_page.text = ""
	_left_lines = []
	_left_line_index = 0
	if current_page < pages.size():
		var content: String = _get_page_content(current_page)
		_left_lines = content.split("\n")
		_typing_left = true

	# ── 右页 ──
	var right_idx: int = current_page + 1
	right_page.text = ""
	_right_lines = []
	_right_line_index = 0
	if total_pages >= 2 and right_idx < pages.size():
		var content: String = _get_page_content(right_idx)
		_right_lines = content.split("\n")
		separator_line.visible = true
		right_page.visible = true
		_typing_right = true
	else:
		separator_line.visible = false
		right_page.visible = false

	# ── 导航栏 ──
	nav_label.text = ""
	nav_label.append_text(_build_nav_text())

	_type_timer = 0.0

## 每帧调用，驱动打字效果
func process_typing(delta: float) -> void:
	if not is_active:
		return
	if not _typing_left and not _typing_right:
		return

	_type_timer += delta
	var lines_this_frame: int = maxi(1, int(_type_timer / _type_speed))
	_type_timer = fmod(_type_timer, _type_speed)

	if _typing_left:
		for i in range(lines_this_frame):
			if _left_line_index >= _left_lines.size():
				_typing_left = false
				left_page.scroll_to_line(0)
				break
			var line: String = _left_lines[_left_line_index]
			if _left_line_index > 0:
				left_page.append_text("\n")
			# ★ 检测内联图片占位符
			if line.contains("\u0001IMG:") and line.contains("\u0002"):
				_append_line_with_images(left_page, line)
			else:
				left_page.append_text(line)
			_left_line_index += 1

	if _typing_right:
		for i in range(lines_this_frame):
			if _right_line_index >= _right_lines.size():
				_typing_right = false
				right_page.scroll_to_line(0)
				break
			var line: String = _right_lines[_right_line_index]
			if _right_line_index > 0:
				right_page.append_text("\n")
			# ★ 检测内联图片占位符
			if line.contains("\u0001IMG:") and line.contains("\u0002"):
				_append_line_with_images(right_page, line)
			else:
				right_page.append_text(line)
			_right_line_index += 1

## ★ 修复：跳过打字效果（消除重复代码 bug）
func _skip_typing() -> void:
	if _typing_left:
		left_page.text = ""
		_append_lines_with_images(left_page, _left_lines)
		left_page.scroll_to_line(0)
		_typing_left = false

	if _typing_right:
		right_page.text = ""
		_append_lines_with_images(right_page, _right_lines)
		right_page.scroll_to_line(0)
		_typing_right = false

func _get_page_content(page_idx: int) -> String:
	if page_idx < 0 or page_idx >= pages.size():
		return ""
	var page: Dictionary = pages[page_idx]
	if page.has("content"):
		return str(page["content"])
	if page.has("left"):
		return str(page["left"])
	return ""

## 对原始页面数组进行自动分页处理
## 支持 ---PAGE--- 手动分页标记
func _auto_paginate(raw_pages: Array[Dictionary]) -> Array[Dictionary]:
	# 先合并所有内容，用 ---PAGE--- 做手动分页点
	var all_sections: Array[String] = []
	for page in raw_pages:
		var content: String = ""
		if page.has("content"):
			content = str(page["content"])
		elif page.has("left"):
			content = str(page["left"])
		all_sections.append(content)

	# 把所有 section 合并，用 ---PAGE--- 连接（保留原有手动分页）
	var full_text: String = "\n---PAGE---\n".join(all_sections)

	# ★ 同时识别原始 ---PAGE--- 和 CRT-ML 解析后的 PAGE_BREAK_TAG
	var normalized: String = full_text.replace(CrtmlParser.PAGE_BREAK_TAG, "---PAGE---")
	var manual_sections: PackedStringArray = normalized.split("---PAGE---")

	# 对每个 manual section 再按行高自动分页
	var result: Array[Dictionary] = []

	# 估算可用行数：用 overlay 的高度和行高估算
	var available_height: float = _get_content_height()
	var line_height: float = _estimate_line_height()
	var max_lines: int = maxi(5, int(available_height / line_height) - 2)  # 留2行余量

	for section in manual_sections:
		var trimmed: String = section.strip_edges()
		if trimmed.is_empty():
			continue

		var lines: PackedStringArray = trimmed.split("\n")
		var current_lines: PackedStringArray = []
		var current_count: int = 0

		for line in lines:
			current_lines.append(line)
			current_count += 1
			if current_count >= max_lines:
				result.append({"content": "\n".join(current_lines)})
				current_lines = []
				current_count = 0

		# 剩余行
		if current_lines.size() > 0:
			result.append({"content": "\n".join(current_lines)})

	if result.is_empty():
		result.append({"content": ""})

	return result

func _get_content_height() -> float:
	if overlay and is_instance_valid(overlay):
		# overlay 高度减去导航栏和边距
		return overlay.size.y - 60.0  # 导航栏 + margin 大约 60px
	return 400.0

func _estimate_line_height() -> float:
	# RichTextLabel 默认字体行高，通常 16-22px
	if left_page and is_instance_valid(left_page):
		var font: Font = left_page.get_theme_font("normal_font")
		var font_size: int = left_page.get_theme_font_size("normal_font_size")
		if font:
			return font.get_height(font_size) + 2.0
	return 20.0

func _build_nav_text() -> String:
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var w: String = T.warning_hex

	var left_num: int = current_page + 1
	var right_num: int = current_page + 2

	var page_display: String = ""
	if total_pages >= 2:
		if right_num <= total_pages:
			page_display = str(left_num) + "-" + str(right_num) + "/" + str(total_pages)
		else:
			page_display = str(left_num) + "/" + str(total_pages)
	else:
		page_display = "1/1"

	var parts: Array[String] = []
	if total_pages > 2:
		if current_page > 0:
			parts.append("[color=" + p + "]← A/←/PgUp[/color]")
		else:
			parts.append("[color=" + m + "]← A/←/PgUp[/color]")

		parts.append("  [color=" + w + "]" + page_display + "[/color]  ")

		if current_page + 2 < total_pages:
			parts.append("[color=" + p + "]D/→/PgDn →[/color]")
		else:
			parts.append("[color=" + m + "]D/→/PgDn →[/color]")
	else:
		parts.append("[color=" + w + "]" + page_display + "[/color]")

	parts.append("    [color=" + m + "][Q/Esc 退出][/color]")
	return "  ".join(parts)

## ★ 修复：局部变量名避免遮蔽类成员 pages
func _split_pages_by_tag(content: String) -> PackedStringArray:
	# 按 PAGE_BREAK_TAG 分割
	var raw_splits: PackedStringArray = content.split(CrtmlParser.PAGE_BREAK_TAG)
	var result_pages: PackedStringArray = PackedStringArray()
	for pg in raw_splits:
		var trimmed: String = pg.strip_edges()
		if not trimmed.is_empty():
			result_pages.append(trimmed)
	if result_pages.is_empty():
		result_pages.append(content)
	return result_pages

## ★ 批量追加多行（含图片检测）
func _append_lines_with_images(rtl: RichTextLabel, lines: PackedStringArray) -> void:
	for idx in range(lines.size()):
		if idx > 0:
			rtl.append_text("\n")
		var line: String = lines[idx]
		if line.contains("\u0001IMG:") and line.contains("\u0002"):
			_append_line_with_images(rtl, line)
		else:
			rtl.append_text(line)

## ★ 处理包含内联图片占位符的单行
func _append_line_with_images(rtl: RichTextLabel, line: String) -> void:
	var crtml_ref = null
	if main != null and main.crtml != null:
		crtml_ref = main.crtml

	if crtml_ref == null:
		rtl.append_text(line)
		return

	var images: Array[Dictionary] = crtml_ref.get_inline_images()

	var remaining: String = line
	while true:
		var start_pos: int = remaining.find("\u0001IMG:")
		if start_pos == -1:
			break
		var end_pos: int = remaining.find("\u0002", start_pos)
		if end_pos == -1:
			break

		# 占位符前的文本
		if start_pos > 0:
			rtl.append_text(remaining.substr(0, start_pos))

		# 提取占位符ID
		var placeholder_id: String = remaining.substr(start_pos + 5, end_pos - start_pos - 5)

		# 查找对应的图片
		var found: bool = false
		for img_info in images:
			if str(img_info.get("placeholder", "")) == placeholder_id:
				var texture = img_info.get("texture")
				if texture != null and texture is ImageTexture:
					var w: int = int(img_info.get("width", 200))
					var h: int = int(img_info.get("height", 150))
					rtl.newline()
					rtl.add_image(texture as Texture2D, w, h)
					rtl.newline()
				else:
					rtl.append_text("[IMG]")
				found = true
				break

		if not found:
			rtl.append_text("[IMG]")

		remaining = remaining.substr(end_pos + 1)

	if not remaining.is_empty():
		rtl.append_text(remaining)
