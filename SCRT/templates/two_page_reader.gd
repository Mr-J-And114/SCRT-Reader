# scripts/two_page_reader.gd
# 双页文档查看器（与现有 DocumentViewer 行为对齐：打字、分页、图片占位符、链接分发）
class_name TwoPageReader
extends RefCounted

# 引用
var main: Control = null
var fs: FileSystem = null
var T: Variant = null

# UI 节点
var overlay: Panel = null
var left_page: RichTextLabel = null
var right_page: RichTextLabel = null
var separator_line: Panel = null
var nav_label: RichTextLabel = null

# 状态
var is_active: bool = false
var pages: Array[Dictionary] = []
var current_page: int = 0
var total_pages: int = 0
var viewer_title: String = ""
var viewer_type: String = ""
var _on_exit_callback: Callable = Callable()

# 缓存终端区可见性与内容
var _cached_input_visible: bool = true
var _cached_prompt_visible: bool = true
var _cached_output_text: String = ""

# 打字状态
var _typing_left: bool = false
var _typing_right: bool = false
var _type_timer: float = 0.0
var _type_speed: float = 0.03
var _left_lines: PackedStringArray = []
var _right_lines: PackedStringArray = []
var _left_line_index: int = 0
var _right_line_index: int = 0

# 连接标志
var _size_changed_connected: bool = false
var _process_connected: bool = false

# 自算 delta
var _last_frame_ms: int = 0

func setup(p_main: Control, p_fs: FileSystem, p_theme: Variant) -> void:
	main = p_main
	fs = p_fs
	T = p_theme

# ─────────────────────────────────────────
# 构建 UI（首次创建后复用）
# ─────────────────────────────────────────
func _ensure_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		return

	overlay = Panel.new()
	overlay.name = "TwoPageReaderOverlay"
	overlay.visible = false
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0)
	overlay.add_theme_stylebox_override("panel", bg_style)

	var root_control: Control = main
	root_control.add_child(overlay)
	var crt_node: Node = root_control.get_node_or_null("CRTEffect")
	if crt_node:
		root_control.move_child(overlay, crt_node.get_index())  # 放在 CRT 效果之上

	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.offset_left = 0
	overlay.offset_top = 0
	overlay.offset_right = 0
	overlay.offset_bottom = 0

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	overlay.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 0)
	vbox.add_child(hbox)

	# 左页
	var left_margin := MarginContainer.new()
	left_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_margin.add_theme_constant_override("margin_left", 8)
	left_margin.add_theme_constant_override("margin_right", 12)
	hbox.add_child(left_margin)
	left_page = _create_page_rtl()
	left_margin.add_child(left_page)

	# 分隔线
	separator_line = Panel.new()
	separator_line.custom_minimum_size = Vector2(1, 0)
	separator_line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vsep_style := StyleBoxFlat.new()
	vsep_style.bg_color = T.muted if T else Color(0.4, 0.4, 0.2, 0.6)
	separator_line.add_theme_stylebox_override("panel", vsep_style)
	hbox.add_child(separator_line)

	# 右页
	var right_margin := MarginContainer.new()
	right_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_margin.add_theme_constant_override("margin_left", 12)
	right_margin.add_theme_constant_override("margin_right", 8)
	hbox.add_child(right_margin)
	right_page = _create_page_rtl()
	right_margin.add_child(right_page)

	# 底部导航
	nav_label = RichTextLabel.new()
	nav_label.bbcode_enabled = true
	nav_label.fit_content = true
	nav_label.scroll_active = false
	nav_label.selection_enabled = false
	nav_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if T:
		nav_label.add_theme_color_override("default_color", T.muted)
	vbox.add_child(nav_label)

	# 首次对齐
	_align_overlay_to_output_area()

	# 窗口尺寸变化时对齐
	var tree: SceneTree = main.get_tree()
	if tree and tree.root and not _size_changed_connected:
		_size_changed_connected = true
		tree.root.size_changed.connect(_align_overlay_to_output_area)

	# 每帧驱动（SceneTree.process_frame 信号）
	if tree and not _process_connected:
		_process_connected = true
		_last_frame_ms = Time.get_ticks_msec()
		tree.process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if not is_active:
		return
	var now_ms: int = Time.get_ticks_msec()
	var delta: float = 0.016
	if _last_frame_ms > 0:
		delta = max(0.001, float(now_ms - _last_frame_ms) / 1000.0)
	_last_frame_ms = now_ms
	process_typing(delta)

func _create_page_rtl() -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = false
	rtl.scroll_active = true
	rtl.scroll_following = false
	rtl.selection_enabled = true
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rtl.mouse_filter = Control.MOUSE_FILTER_STOP

	# ★ 应用字体（与 document_viewer 一致）
	CrtmlParser.apply_fonts(rtl)
	UIManager._apply_bold_font(rtl)

	if T:
		rtl.add_theme_color_override("default_color", T.secondary)
		rtl.add_theme_color_override("font_color", T.secondary)

	rtl.add_theme_constant_override("table_h_separation", 16)
	rtl.add_theme_constant_override("table_v_separation", 4)

	if main != null and main.has_method("_on_meta_clicked"):
		rtl.meta_clicked.connect(main._on_meta_clicked)

	return rtl

func _align_overlay_to_output_area() -> void:
	if overlay == null or not is_instance_valid(overlay):
		return
	var output_area: ScrollContainer = main.scroll_container
	if output_area == null:
		return
	var rect: Rect2 = output_area.get_global_rect()
	overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	overlay.position = rect.position
	overlay.size = rect.size

# ─────────────────────────────────────────
# 开关
# ─────────────────────────────────────────
func open(p_type: String, p_pages: Array[Dictionary], p_title: String = "", p_on_exit: Callable = Callable()) -> void:
	if p_pages.is_empty():
		return
	_ensure_overlay()
	viewer_type = p_type
	viewer_title = p_title

	_align_overlay_to_output_area()
	pages = _auto_paginate(p_pages)
	current_page = 0
	total_pages = pages.size()
	_on_exit_callback = p_on_exit
	is_active = true

	# 隐藏终端输入区，缓存内容
	_cached_input_visible = main.input_field.visible
	_cached_prompt_visible = main.prompt_label.visible
	main.input_field.visible = false
	main.prompt_label.visible = false

	_cached_output_text = main.output_text.text
	main.output_text.text = ""

	main.path_label.text = "DOCUMENT VIEWER | " + p_title + " | Q/Esc 退出"
	
	var root_control: Control = main as Control
	root_control.move_child(overlay, root_control.get_child_count() - 1)
	var crt_node: Node = root_control.get_node_or_null("CRTEffect")
	if crt_node:
		root_control.move_child(crt_node, root_control.get_child_count() - 1)
	
	overlay.visible = true

	_render_current_page()

func close() -> void:
	if not is_active:
		return
	is_active = false

	if overlay and is_instance_valid(overlay):
		overlay.visible = false

	# 恢复 output_text 内容与输入区可见性
	main.output_text.text = ""
	main.output_text.append_text(_cached_output_text)
	_cached_output_text = ""
	main.input_field.visible = _cached_input_visible
	main.prompt_label.visible = _cached_prompt_visible
	main._update_status_bar()
	main.input_field.grab_focus()

	if _on_exit_callback.is_valid():
		_on_exit_callback.call()

	pages.clear()
	current_page = 0
	total_pages = 0
	viewer_type = ""
	viewer_title = ""

# ─────────────────────────────────────────
# 输入
# ─────────────────────────────────────────
func handle_input(event: InputEvent) -> bool:
	if not is_active:
		return false
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE, KEY_Q:
				close(); return true
			KEY_LEFT, KEY_A, KEY_PAGEUP:
				prev_page(); return true
			KEY_RIGHT, KEY_D, KEY_PAGEDOWN, KEY_SPACE:
				if _typing_left or _typing_right:
					_skip_typing(); return true
				next_page(); return true
			KEY_HOME:
				go_to_page(0); return true
			KEY_END:
				go_to_page(total_pages - 1); return true
	return false

# ─────────────────────────────────────────
# 翻页
# ─────────────────────────────────────────
func next_page() -> void:
	if total_pages >= 2:
		if current_page + 2 < total_pages:
			current_page += 2
			_render_current_page()
		elif current_page < total_pages - 1:
			current_page += 1
			_render_current_page()

func prev_page() -> void:
	if total_pages >= 2:
		if current_page >= 2:
			current_page -= 2
			_render_current_page()
		elif current_page > 0:
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

# ─────────────────────────────────────────
# 渲染 + 打字
# ─────────────────────────────────────────
func _render_current_page() -> void:
	if pages.is_empty():
		return
	_typing_left = false
	_typing_right = false

	# 左
	left_page.text = ""
	_left_lines = []
	_left_line_index = 0
	if current_page < pages.size():
		var content_l: String = _get_page_content(current_page)
		_left_lines = content_l.split("\n")
		_typing_left = true

	# 右
	var right_idx: int = current_page + 1
	right_page.text = ""
	_right_lines = []
	_right_line_index = 0
	if total_pages >= 2 and right_idx < pages.size():
		var content_r: String = _get_page_content(right_idx)
		_right_lines = content_r.split("\n")
		separator_line.visible = true
		right_page.visible = true
		_typing_right = true
	else:
		separator_line.visible = false
		right_page.visible = false

	# 导航
	nav_label.text = ""
	nav_label.append_text(_build_nav_text())
	_type_timer = 0.0

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
			var line_l: String = _left_lines[_left_line_index]
			if _left_line_index > 0:
				left_page.append_text("\n")
			if line_l.contains("\u0001IMG:") and line_l.contains("\u0002"):
				_append_line_with_images(left_page, line_l)
			else:
				left_page.append_text(line_l)
			_left_line_index += 1

	if _typing_right:
		for j in range(lines_this_frame):
			if _right_line_index >= _right_lines.size():
				_typing_right = false
				right_page.scroll_to_line(0)
				break
			var line_r: String = _right_lines[_right_line_index]
			if _right_line_index > 0:
				right_page.append_text("\n")
			if line_r.contains("\u0001IMG:") and line_r.contains("\u0002"):
				_append_line_with_images(right_page, line_r)
			else:
				right_page.append_text(line_r)
			_right_line_index += 1

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

# ─────────────────────────────────────────
# 自动分页（支持 ---PAGE--- 与 PAGE_BREAK_TAG）
# ─────────────────────────────────────────
func _auto_paginate(raw_pages: Array[Dictionary]) -> Array[Dictionary]:
	var all_sections: Array[String] = []
	for page in raw_pages:
		var content: String = ""
		if page.has("content"):
			content = str(page["content"])
		elif page.has("left"):
			content = str(page["left"])
		all_sections.append(content)

	var full_text: String = "\n---PAGE---\n".join(all_sections)
	var normalized: String = full_text.replace(CrtmlParser.PAGE_BREAK_TAG, "---PAGE---")

	# ★ 清除分页视觉装饰（═══ [ PAGE BREAK ] ═══）
	var page_break_visual := RegEx.new()
	page_break_visual.compile("\\n?\\[color=[^\\]]*\\]═+\\[/color\\]\\s*\\[color=[^\\]]*\\]\\[\\s*PAGE BREAK\\s*\\]\\[/color\\]\\s*\\[color=[^\\]]*\\]═+\\[/color\\]\\n?")
	normalized = page_break_visual.sub(normalized, "", true)

	var manual_sections: PackedStringArray = normalized.split("---PAGE---")

	var result: Array[Dictionary] = []
	var available_height: float = _get_content_height()
	var line_height: float = _estimate_line_height()
	var max_lines: int = maxi(5, int(available_height / line_height) - 2)

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
		if current_lines.size() > 0:
			result.append({"content": "\n".join(current_lines)})

	if result.is_empty():
		result.append({"content": ""})
	return result

func _get_content_height() -> float:
	if overlay and is_instance_valid(overlay):
		return overlay.size.y - 60.0
	return 400.0

func _estimate_line_height() -> float:
	if left_page and is_instance_valid(left_page):
		var font: Font = left_page.get_theme_font("normal_font")
		var font_size: int = left_page.get_theme_font_size("normal_font_size")
		if font:
			return font.get_height(font_size) + 2.0
	return 20.0

func _build_nav_text() -> String:
	var p: String = T.primary_hex if T != null else "#A0FFA0"
	var m: String = T.muted_hex if T != null else "#888888"
	var w: String = T.warning_hex if T != null else "#FFFF80"
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

# ─────────────────────────────────────────
# 图片占位符处理（与现有 viewer 一致）
# ─────────────────────────────────────────
func _append_lines_with_images(rtl: RichTextLabel, lines: PackedStringArray) -> void:
	for idx in range(lines.size()):
		if idx > 0:
			rtl.append_text("\n")
		var line: String = lines[idx]
		if line.contains("\u0001IMG:") and line.contains("\u0002"):
			_append_line_with_images(rtl, line)
		else:
			rtl.append_text(line)

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
		if start_pos > 0:
			rtl.append_text(remaining.substr(0, start_pos))
		var placeholder_id: String = remaining.substr(start_pos + 5, end_pos - start_pos - 5)
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


# TwoPageReader.gd 内部
func get_active_page_rtl() -> RichTextLabel:
	return left_page  # 或根据 current_page/right_page 可见性返回合适的页




	
	
