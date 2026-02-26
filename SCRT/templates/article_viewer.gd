# ============================================================
# templates/article_viewer.gd
# 全屏文章阅读模板（单页滚动阅读，适合长篇文章/报告/日志）
# 功能：逐行打字效果、阅读进度条、CRT-ML 兼容、
#       键盘滚动、内联图片/链接、阅读进度百分比
# ============================================================
class_name ArticleViewer
extends RefCounted

# ══════════════════════════════════════════
#  引用
# ══════════════════════════════════════════
var main: Control = null
var fs: FileSystem = null
var T: Variant = null

# ══════════════════════════════════════════
#  UI 节点
# ══════════════════════════════════════════
var overlay: Panel = null
var content_rtl: RichTextLabel = null
var nav_label: RichTextLabel = null
var progress_bar: ColorRect = null       # 顶部细进度条
var progress_bg: ColorRect = null

# ══════════════════════════════════════════
#  状态
# ══════════════════════════════════════════
var is_active: bool = false
var viewer_title: String = ""
var _on_exit_callback: Callable = Callable()

var _cached_input_visible: bool = true
var _cached_prompt_visible: bool = true
var _cached_output_text: String = ""

# ── 打字效果 ──
var _typing: bool = false
var _lines: PackedStringArray = []
var _line_index: int = 0
var _type_timer: float = 0.0
var _type_speed: float = 0.02   # 每行间隔（秒）

# ── 连接标志 ──
var _size_changed_connected: bool = false
var _process_connected: bool = false
var _last_frame_ms: int = 0

# ============================================================
func setup(p_main: Control, p_fs: FileSystem, p_theme: Variant) -> void:
	main = p_main
	fs = p_fs
	T = p_theme

# ============================================================
# UI 构建
# ============================================================
func _ensure_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		return

	overlay = Panel.new()
	overlay.name = "ArticleViewerOverlay"
	overlay.visible = false
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0)
	overlay.add_theme_stylebox_override("panel", bg_style)

	var root_control: Control = main
	root_control.add_child(overlay)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	# ── 顶层容器 ──
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 4)
	overlay.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	# ── 进度条（顶部细线） ──
	var progress_container := Control.new()
	progress_container.custom_minimum_size = Vector2(0, 3)
	progress_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(progress_container)

	progress_bg = ColorRect.new()
	progress_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	progress_bg.color = Color(0.15, 0.15, 0.15, 0.6)
	progress_container.add_child(progress_bg)

	progress_bar = ColorRect.new()
	progress_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	progress_bar.position = Vector2.ZERO
	progress_bar.size = Vector2(0, 3)
	var bar_color: Color = Color(0.4, 1.0, 0.4, 0.8)
	if T:
		bar_color = Color(T.primary.r, T.primary.g, T.primary.b, 0.8)
	progress_bar.color = bar_color
	progress_container.add_child(progress_bar)

	# ── 主内容 ──
	content_rtl = RichTextLabel.new()
	content_rtl.bbcode_enabled = true
	content_rtl.fit_content = false
	content_rtl.scroll_active = true
	content_rtl.scroll_following = false
	content_rtl.selection_enabled = true
	content_rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_rtl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_rtl.mouse_filter = Control.MOUSE_FILTER_STOP

	CrtmlParser.apply_fonts(content_rtl)
	UIManager._apply_bold_font(content_rtl)

	if T:
		content_rtl.add_theme_color_override("default_color", T.secondary)
		content_rtl.add_theme_color_override("font_color", T.secondary)
	content_rtl.add_theme_constant_override("table_h_separation", 16)
	content_rtl.add_theme_constant_override("table_v_separation", 4)

	if main != null and main.has_method("_on_meta_clicked"):
		content_rtl.meta_clicked.connect(main._on_meta_clicked)

	# 滚动事件跟踪进度条
	var v_scroll: VScrollBar = content_rtl.get_v_scroll_bar()
	if v_scroll:
		v_scroll.value_changed.connect(_on_scroll_changed)

	vbox.add_child(content_rtl)

	# ── 底部导航 ──
	nav_label = RichTextLabel.new()
	nav_label.bbcode_enabled = true
	nav_label.fit_content = true
	nav_label.scroll_active = false
	nav_label.selection_enabled = false
	nav_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if T:
		nav_label.add_theme_color_override("default_color", T.muted)
	CrtmlParser.apply_fonts(nav_label)
	vbox.add_child(nav_label)

	_align_overlay_to_output_area()

	var tree: SceneTree = main.get_tree()
	if tree and tree.root and not _size_changed_connected:
		_size_changed_connected = true
		tree.root.size_changed.connect(_align_overlay_to_output_area)
	if tree and not _process_connected:
		_process_connected = true
		_last_frame_ms = Time.get_ticks_msec()
		tree.process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if not is_active:
		return
	var now_ms: int = Time.get_ticks_msec()
	var delta: float = max(0.001, float(now_ms - _last_frame_ms) / 1000.0) if _last_frame_ms > 0 else 0.016
	_last_frame_ms = now_ms
	_process_typing(delta)

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

# ============================================================
# 打开
# ============================================================
func open(p_title: String, p_header: Dictionary, p_body: String, p_on_exit: Callable = Callable()) -> void:
	_ensure_overlay()
	viewer_title = p_title
	_on_exit_callback = p_on_exit
	_align_overlay_to_output_area()

	is_active = true

	# 隐藏终端
	_cached_input_visible = main.input_field.visible
	_cached_prompt_visible = main.prompt_label.visible
	main.input_field.visible = false
	main.prompt_label.visible = false
	_cached_output_text = main.output_text.text
	main.output_text.text = ""
	main.path_label.text = "READER | " + viewer_title + " | Q/Esc 退出"

	# overlay 置顶
	var root_control: Control = main as Control
	root_control.move_child(overlay, root_control.get_child_count() - 1)
	var crt_node: Node = root_control.get_node_or_null("CRTEffect")
	if crt_node:
		root_control.move_child(crt_node, root_control.get_child_count() - 1)

	overlay.visible = true
	content_rtl.text = ""

	# CRT-ML 解析
	var parsed: String = p_body
	if main.crtml != null:
		parsed = main.crtml.parse(p_body)
	if main.user_mgr != null and main.user_mgr.is_logged_in:
		parsed = parsed.replace("{username}", main.user_mgr.get_username())

	# 去除分页标记（文章模板使用连续滚动）
	parsed = parsed.replace(CrtmlParser.PAGE_BREAK_TAG, "\n")
	parsed = parsed.replace("---PAGE---", "\n")

	# 打字速度
	var speed_str: String = str(p_header.get("typewriter_speed", "50"))
	var speed_val: int = max(1, speed_str.to_int())
	_type_speed = 1.0 / float(speed_val)

	# 启动逐行打字
	_lines = parsed.split("\n")
	_line_index = 0
	_type_timer = 0.0
	_typing = true

	_update_nav()
	_update_progress()

# ============================================================
# 关闭
# ============================================================
func close() -> void:
	if not is_active:
		return
	is_active = false
	if overlay and is_instance_valid(overlay):
		overlay.visible = false

	main.output_text.text = ""
	main.output_text.append_text(_cached_output_text)
	_cached_output_text = ""
	main.input_field.visible = _cached_input_visible
	main.prompt_label.visible = _cached_prompt_visible
	main._update_status_bar()
	main.input_field.grab_focus()

	if _on_exit_callback.is_valid():
		_on_exit_callback.call()

	viewer_title = ""
	_lines = []
	_line_index = 0

# ============================================================
# 输入
# ============================================================
func handle_input(event: InputEvent) -> bool:
	if not is_active:
		return false

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE, KEY_Q:
				close()
				return true
			KEY_SPACE:
				if _typing:
					_skip_typing()
					return true
				_scroll_content(250)
				return true
			KEY_UP:
				_scroll_content(-60)
				return true
			KEY_DOWN:
				_scroll_content(60)
				return true
			KEY_PAGEUP:
				_scroll_content(-350)
				return true
			KEY_PAGEDOWN:
				_scroll_content(350)
				return true
			KEY_HOME:
				content_rtl.scroll_to_line(0)
				_update_progress()
				return true
			KEY_END:
				content_rtl.scroll_to_line(content_rtl.get_line_count() - 1)
				_update_progress()
				return true

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_scroll_content(-60)
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_content(60)
				return true

	return false

func _scroll_content(amount: int) -> void:
	if content_rtl == null or not is_instance_valid(content_rtl):
		return
	var v_scroll: VScrollBar = content_rtl.get_v_scroll_bar()
	if v_scroll:
		v_scroll.value += amount
	_update_progress()

func _on_scroll_changed(_value: float) -> void:
	_update_progress()

# ============================================================
# 打字效果
# ============================================================
func _process_typing(delta: float) -> void:
	if not is_active or not _typing:
		return

	_type_timer += delta
	var lines_this_frame: int = maxi(1, int(_type_timer / _type_speed))
	_type_timer = fmod(_type_timer, _type_speed)

	for _i in range(lines_this_frame):
		if _line_index >= _lines.size():
			_typing = false
			_update_nav()
			_update_progress()
			break

		var line: String = _lines[_line_index]
		if _line_index > 0:
			content_rtl.append_text("\n")

		# 内联图片占位符处理
		if line.contains("\u0001IMG:") and line.contains("\u0002"):
			_append_line_with_images(content_rtl, line)
		else:
			content_rtl.append_text(line)

		_line_index += 1

func _skip_typing() -> void:
	if not _typing:
		return
	content_rtl.text = ""
	for idx in range(_lines.size()):
		if idx > 0:
			content_rtl.append_text("\n")
		var line: String = _lines[idx]
		if line.contains("\u0001IMG:") and line.contains("\u0002"):
			_append_line_with_images(content_rtl, line)
		else:
			content_rtl.append_text(line)
	content_rtl.scroll_to_line(0)
	_typing = false
	_update_nav()
	_update_progress()

# ============================================================
# 内联图片处理（与 document_viewer 一致）
# ============================================================
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

# ============================================================
# 进度条
# ============================================================
func _update_progress() -> void:
	if progress_bar == null or progress_bg == null:
		return
	if content_rtl == null or not is_instance_valid(content_rtl):
		return

	var v_scroll: VScrollBar = content_rtl.get_v_scroll_bar()
	if v_scroll == null:
		return

	var max_val: float = v_scroll.max_value - v_scroll.page
	var ratio: float = 0.0
	if max_val > 0:
		ratio = clampf(v_scroll.value / max_val, 0.0, 1.0)
	elif not _typing:
		ratio = 1.0  # 内容不超过一屏，视为已读完

	# 打字中且没滚动过，按打字进度算
	if _typing and v_scroll.value <= 0:
		ratio = float(_line_index) / max(1.0, float(_lines.size()))

	var bg_width: float = progress_bg.size.x
	progress_bar.size.x = bg_width * ratio

	_update_nav_with_progress(ratio)

func _update_nav_with_progress(ratio: float) -> void:
	if nav_label == null:
		return
	nav_label.text = ""
	var p: String = T.primary_hex if T != null else "#A0FFA0"
	var m: String = T.muted_hex if T != null else "#888888"
	var pct: int = int(ratio * 100)
	var parts: Array[String] = []
	parts.append("[color=" + p + "]" + str(pct) + "%[/color]")
	if _typing:
		parts.append("[color=" + m + "]Space=skip typing[/color]")
	else:
		parts.append("[color=" + m + "]Up/Dn/PgUp/PgDn=scroll[/color]")
	parts.append("[color=" + m + "][Q/Esc 退出][/color]")
	nav_label.append_text("  ".join(parts))

func _update_nav() -> void:
	_update_progress()

# ============================================================
# 供外部调用
# ============================================================
func get_active_page_rtl() -> RichTextLabel:
	if is_active and content_rtl != null and is_instance_valid(content_rtl):
		return content_rtl
	return null
