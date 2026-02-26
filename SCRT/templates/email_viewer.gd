# templates/email_viewer.gd
# 邮件模板全屏查看器（单页滚动，带发件人/收件人信息栏与一寸照片）
class_name EmailViewer
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

# ══════════════════════════════════════════
#  状态
# ══════════════════════════════════════════
var is_active: bool = false
var viewer_title: String = ""
var _on_exit_callback: Callable = Callable()

# 缓存终端区
var _cached_input_visible: bool = true
var _cached_prompt_visible: bool = true
var _cached_output_text: String = ""

# 打字状态
var _typing: bool = false
var _type_timer: float = 0.0
var _type_speed: float = 0.03
var _lines: PackedStringArray = []
var _line_index: int = 0

# 连接标志
var _size_changed_connected: bool = false
var _process_connected: bool = false
var _last_frame_ms: int = 0

# 邮件元数据（从 body 中解析）
var _email_meta: Dictionary = {}
var _email_body: String = ""

# ── 一寸照比例常量（25mm × 35mm） ──
# 照片大小设置，在屏幕上以约 125px × 175px 显示
const PHOTO_WIDTH: int = 200
const PHOTO_HEIGHT: int = 280

func setup(p_main: Control, p_fs: FileSystem, p_theme: Variant) -> void:
	main = p_main
	fs = p_fs
	T = p_theme

# ═════════════════════════════════════════════
# 构建 UI（首次创建后复用）
# ═════════════════════════════════════════════
func _ensure_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		return

	overlay = Panel.new()
	overlay.name = "EmailViewerOverlay"
	overlay.visible = false

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0)
	overlay.add_theme_stylebox_override("panel", bg_style)

	var root_control: Control = main
	root_control.add_child(overlay)

	var crt_node: Node = root_control.get_node_or_null("CRTEffect")
	if crt_node:
		root_control.move_child(overlay, crt_node.get_index())

	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.offset_left = 0
	overlay.offset_top = 0
	overlay.offset_right = 0
	overlay.offset_bottom = 0

	# MarginContainer
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	overlay.add_child(margin)

	# VBox: 内容 + 导航
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	# 主内容 RichTextLabel（可滚动）
	content_rtl = RichTextLabel.new()
	content_rtl.bbcode_enabled = true
	content_rtl.fit_content = false
	content_rtl.scroll_active = true
	content_rtl.scroll_following = false
	content_rtl.selection_enabled = true
	content_rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_rtl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_rtl.mouse_filter = Control.MOUSE_FILTER_STOP

	# 应用字体
	CrtmlParser.apply_fonts(content_rtl)
	UIManager._apply_bold_font(content_rtl)

	if T:
		content_rtl.add_theme_color_override("default_color", T.secondary)
		content_rtl.add_theme_color_override("font_color", T.secondary)
	content_rtl.add_theme_constant_override("table_h_separation", 16)
	content_rtl.add_theme_constant_override("table_v_separation", 4)

	if main != null and main.has_method("_on_meta_clicked"):
		content_rtl.meta_clicked.connect(main._on_meta_clicked)

	vbox.add_child(content_rtl)

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
	var delta: float = 0.016
	if _last_frame_ms > 0:
		delta = max(0.001, float(now_ms - _last_frame_ms) / 1000.0)
	_last_frame_ms = now_ms
	process_typing(delta)

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

# ═════════════════════════════════════════════
# 打开邮件查看器
# ═════════════════════════════════════════════
func open(p_title: String, p_header: Dictionary, p_body: String, p_on_exit: Callable = Callable()) -> void:
	_ensure_overlay()

	viewer_title = p_title
	_on_exit_callback = p_on_exit
	_align_overlay_to_output_area()

	# 解析邮件元数据（从 body 头部提取 "键: 值" 行）
	_parse_email_content(p_header, p_body)

	is_active = true

	# 隐藏终端
	_cached_input_visible = main.input_field.visible
	_cached_prompt_visible = main.prompt_label.visible
	main.input_field.visible = false
	main.prompt_label.visible = false
	_cached_output_text = main.output_text.text
	main.output_text.text = ""

	main.path_label.text = "EMAIL VIEWER | " + viewer_title + " | Q/Esc 退出  ↑↓/PgUp/PgDn 滚动"

	# ★ 确保 overlay 在最顶层接收鼠标事件
	var root_control: Control = main as Control
	root_control.move_child(overlay, root_control.get_child_count() - 1)
	# 把 CRT 效果层保持在最上面（仅渲染，不拦截事件）
	var crt_node: Node = root_control.get_node_or_null("CRTEffect")
	if crt_node:
		root_control.move_child(crt_node, root_control.get_child_count() - 1)

	overlay.visible = true
	_render_email()

# ═════════════════════════════════════════════
# 关闭
# ═════════════════════════════════════════════
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
	_email_meta.clear()
	_email_body = ""

# ═════════════════════════════════════════════
# 输入
# ═════════════════════════════════════════════
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
				# 空格也用于向下滚动
				_scroll_content(200)
				return true
			KEY_UP:
				_scroll_content(-60)
				return true
			KEY_DOWN:
				_scroll_content(60)
				return true
			KEY_PAGEUP:
				_scroll_content(-300)
				return true
			KEY_PAGEDOWN:
				_scroll_content(300)
				return true
			KEY_HOME:
				content_rtl.scroll_to_line(0)
				return true
			KEY_END:
				content_rtl.scroll_to_line(content_rtl.get_line_count() - 1)
				return true

	# 鼠标滚轮
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

# ═════════════════════════════════════════════
# 解析邮件元数据
# ═════════════════════════════════════════════
func _parse_email_content(header: Dictionary, body: String) -> void:
	_email_meta = {}
	_email_body = ""

	# 从 header 中提取已有字段
	_email_meta["title"] = str(header.get("title", ""))
	_email_meta["date"] = str(header.get("date", ""))
	_email_meta["author"] = str(header.get("author", ""))
	_email_meta["classification"] = str(header.get("classification", ""))

	# 从 body 顶部解析 "键: 值" 格式的邮件头字段
	# 直到遇到 --- 分隔线或空行连续2个
	var lines: PackedStringArray = body.split("\n")
	var meta_end: int = 0
	var empty_count: int = 0

	for i in range(lines.size()):
		var stripped: String = lines[i].strip_edges()

		# 遇到分隔线，元数据结束
		if stripped == "---" or stripped == "===" or stripped.begins_with("---") and stripped.length() >= 3 and stripped.replace("-", "").is_empty():
			meta_end = i + 1
			break

		if stripped.is_empty():
			empty_count += 1
			if empty_count >= 2:
				meta_end = i
				break
			continue
		else:
			empty_count = 0

		# 解析 "键: 值"
		var colon_pos: int = stripped.find(":")
		if colon_pos > 0 and colon_pos < 20:  # 键名不会太长
			var key: String = stripped.substr(0, colon_pos).strip_edges().to_lower()
			var value: String = stripped.substr(colon_pos + 1).strip_edges()
			# 支持中英文键名
			match key:
				"发件人", "from", "sender":
					_email_meta["from"] = value
				"收件人", "to", "recipient":
					_email_meta["to"] = value
				"日期", "date":
					if _email_meta.get("date", "").is_empty():
						_email_meta["date"] = value
				"主题", "subject":
					_email_meta["subject"] = value
				"优先级", "priority":
					_email_meta["priority"] = value
				"抄送", "cc":
					_email_meta["cc"] = value
				"发件人照片", "sender_photo", "from_photo":
					_email_meta["sender_photo"] = value
				"收件人照片", "recipient_photo", "to_photo":
					_email_meta["recipient_photo"] = value
				"附件", "attachment", "attachments":
					_email_meta["attachments"] = value
				"密送", "bcc":
					_email_meta["密送"] = value
				"部门", "department":
					_email_meta["部门"] = value
				"职务", "position":
					_email_meta["职务"] = value
				"工号", "employee_id":
					_email_meta["工号"] = value
				"安全许可", "clearance":
					_email_meta["安全许可"] = value
				"收件方职务", "recipient_position":
					_email_meta["收件方职务"] = value
				"收件方工号", "recipient_id":
					_email_meta["收件方工号"] = value
				"收件方安全许可", "recipient_clearance":
					_email_meta["收件方安全许可"] = value
				_:
					# 未知键也存入 meta（支持自定义字段）
					_email_meta[key] = value
		else:
			# 不是键值对，元数据结束
			meta_end = i
			break

	# 剩余内容为邮件正文
	if meta_end < lines.size():
		var body_lines: PackedStringArray = []
		for j in range(meta_end, lines.size()):
			body_lines.append(lines[j])
		_email_body = "\n".join(body_lines).strip_edges()
	else:
		_email_body = ""

	# 如果 subject 还是空的，用 header title
	if _email_meta.get("subject", "").is_empty() and not _email_meta.get("title", "").is_empty():
		_email_meta["subject"] = _email_meta["title"]

# ═════════════════════════════════════════════
# 渲染邮件
# ═════════════════════════════════════════════
func _render_email() -> void:
	content_rtl.text = ""
	_typing = false
	_lines = []
	_line_index = 0

	var full_bbcode: String = _build_email_bbcode()
	_lines = full_bbcode.split("\n")
	_typing = true
	_type_timer = 0.0

	# 导航栏
	nav_label.text = ""
	nav_label.append_text(_build_nav_text())

func _build_email_bbcode() -> String:
	var p: String = T.primary_hex if T else "#A0FFA0"
	var m: String = T.muted_hex if T else "#888888"
	var w: String = T.warning_hex if T else "#FFFF80"
	var s: String = T.secondary_hex if T else "#C0C0C0"
	var e: String = T.error_hex if T else "#FF6666"

	var lines: Array[String] = []

	# ═══════════════════════════════════════
	# 顶部装饰线
	# ═══════════════════════════════════════
	lines.append("[color=" + p + "]" + "=".repeat(60) + "[/color]")
	lines.append("[color=" + p + "][b] MAIL SYSTEM[/b][/color]")
	lines.append("[color=" + p + "]" + "=".repeat(60) + "[/color]")
	lines.append("")

	# ═══════════════════════════════════════
	# 发件人信息栏（照片在左，信息在右）
	# ═══════════════════════════════════════
	var sender_name: String = _email_meta.get("from", "")
	if not sender_name.is_empty():
		var sender_photo_path: String = str(_email_meta.get("sender_photo", ""))
		var sender_texture: ImageTexture = _load_photo(sender_photo_path)

		if sender_texture != null:
			lines.append("[table=2]")
			lines.append("[cell]" + _make_photo_placeholder("SENDER_PHOTO") + "[/cell]")
			lines.append("[cell]" + _build_sender_info_block() + "[/cell]")
			lines.append("[/table]")
		else:
			lines.append(_build_sender_info_block())

		lines.append("[color=" + m + "]" + "-".repeat(60) + "[/color]")
		lines.append("")

	# ═══════════════════════════════════════
	# 邮件正文
	# ═══════════════════════════════════════
	if not _email_body.is_empty():
		var parsed: String = _email_body
		if main.crtml != null:
			parsed = main.crtml.parse(_email_body)
		if main.user_mgr != null and main.user_mgr.is_logged_in:
			parsed = parsed.replace("{username}", main.user_mgr.get_username())
		lines.append(parsed)
	lines.append("")

	# ═══════════════════════════════════════
	# 附件区域
	# ═══════════════════════════════════════
	var attachments_str: String = str(_email_meta.get("attachments", ""))
	if not attachments_str.is_empty():
		lines.append("[color=" + m + "]" + "-".repeat(60) + "[/color]")
		lines.append("[color=" + m + "]  [ATTACHMENTS][/color]")
		var att_list: PackedStringArray = attachments_str.split(",")
		for att in att_list:
			var att_trimmed: String = att.strip_edges()
			if not att_trimmed.is_empty():
				lines.append("  [url=cmd://open " + att_trimmed + "][color=" + p + "]> " + att_trimmed.get_file() + "[/color][/url]")
		lines.append("")

	# ═══════════════════════════════════════
	# 收件人信息栏（照片在左，信息在右）
	# ═══════════════════════════════════════
	var recipient_name: String = _email_meta.get("to", "")
	if not recipient_name.is_empty():
		lines.append("[color=" + m + "]" + "-".repeat(60) + "[/color]")
		lines.append("")

		var recipient_photo_path: String = str(_email_meta.get("recipient_photo", ""))
		var recipient_texture: ImageTexture = _load_photo(recipient_photo_path)

		if recipient_texture != null:
			lines.append("[table=2]")
			lines.append("[cell]" + _make_photo_placeholder("RECIPIENT_PHOTO") + "[/cell]")
			lines.append("[cell]" + _build_recipient_info_block() + "[/cell]")
			lines.append("[/table]")
		else:
			lines.append(_build_recipient_info_block())

	# ═══════════════════════════════════════
	# 底部装饰
	# ═══════════════════════════════════════
	lines.append("")
	lines.append("[color=" + p + "]" + "=".repeat(60) + "[/color]")
	lines.append("[color=" + m + "]  [END OF MESSAGE][/color]")
	lines.append("[color=" + p + "]" + "=".repeat(60) + "[/color]")

	return "\n".join(lines)

func _build_sender_info_block() -> String:
	var p: String = T.primary_hex if T else "#A0FFA0"
	var m: String = T.muted_hex if T else "#888888"
	var w: String = T.warning_hex if T else "#FFFF80"
	var e: String = T.error_hex if T else "#FF6666"

	var info: Array[String] = []

	var from_val: String = _email_meta.get("from", "")
	if not from_val.is_empty():
		info.append("[color=" + m + "]发件人:[/color] [color=" + p + "][b]" + from_val + "[/b][/color]")

	var position_val: String = _email_meta.get("职务", _email_meta.get("position", ""))
	if not position_val.is_empty():
		info.append("[color=" + m + "]职  务:[/color] [color=" + p + "]" + position_val + "[/color]")

	var emp_id: String = _email_meta.get("工号", _email_meta.get("employee_id", ""))
	if not emp_id.is_empty():
		info.append("[color=" + m + "]工  号:[/color] [color=" + p + "]" + emp_id + "[/color]")

	var dept_val: String = _email_meta.get("部门", _email_meta.get("department", ""))
	if not dept_val.is_empty():
		info.append("[color=" + m + "]部  门:[/color] [color=" + p + "]" + dept_val + "[/color]")

	var clearance_val: String = _email_meta.get("安全许可", _email_meta.get("clearance", ""))
	if not clearance_val.is_empty():
		info.append("[color=" + m + "]许  可:[/color] [color=" + w + "]" + clearance_val + "[/color]")

	var to_val: String = _email_meta.get("to", "")
	if not to_val.is_empty():
		info.append("[color=" + m + "]收件人:[/color] [color=" + p + "]" + to_val + "[/color]")

	var cc_val: String = _email_meta.get("cc", _email_meta.get("抄送", ""))
	if not cc_val.is_empty():
		info.append("[color=" + m + "]抄  送:[/color] [color=" + p + "]" + cc_val + "[/color]")

	var bcc_val: String = _email_meta.get("密送", _email_meta.get("bcc", ""))
	if not bcc_val.is_empty():
		info.append("[color=" + m + "]密  送:[/color] [color=" + p + "]" + bcc_val + "[/color]")

	var date_val: String = _email_meta.get("date", "")
	if not date_val.is_empty():
		info.append("[color=" + m + "]日  期:[/color] [color=" + p + "]" + date_val + "[/color]")

	var subject_val: String = _email_meta.get("subject", "")
	if not subject_val.is_empty():
		info.append("[color=" + m + "]主  题:[/color] [color=" + w + "][b]" + subject_val + "[/b][/color]")

	var priority_val: String = _email_meta.get("priority", _email_meta.get("优先级", ""))
	if not priority_val.is_empty():
		var pri_color: String = m
		var pri_lower: String = priority_val.to_lower()
		if pri_lower in ["high", "高", "urgent", "紧急"]:
			pri_color = e
		elif pri_lower in ["medium", "中", "normal", "普通"]:
			pri_color = w
		info.append("[color=" + m + "]优先级:[/color] [color=" + pri_color + "]" + priority_val + "[/color]")

	var classification_val: String = _email_meta.get("classification", "")
	if not classification_val.is_empty():
		info.append("[color=" + m + "]密  级:[/color] [color=" + e + "]" + classification_val + "[/color]")

	# 替换 {username}
	if main.user_mgr != null and main.user_mgr.is_logged_in:
		var uname: String = main.user_mgr.get_username()
		for idx in range(info.size()):
			info[idx] = info[idx].replace("{username}", uname)

	return "\n".join(info)


func _build_recipient_info_block() -> String:
	var p: String = T.primary_hex if T else "#A0FFA0"
	var m: String = T.muted_hex if T else "#888888"
	var w: String = T.warning_hex if T else "#FFFF80"

	var info: Array[String] = []

	var to_val: String = _email_meta.get("to", "")
	if not to_val.is_empty():
		info.append("[color=" + m + "]收件人:[/color] [color=" + p + "][b]" + to_val + "[/b][/color]")

	var r_position: String = _email_meta.get("收件方职务", _email_meta.get("recipient_position", ""))
	if not r_position.is_empty():
		info.append("[color=" + m + "]职  务:[/color] [color=" + p + "]" + r_position + "[/color]")

	var r_id: String = _email_meta.get("收件方工号", _email_meta.get("recipient_id", ""))
	if not r_id.is_empty():
		info.append("[color=" + m + "]工  号:[/color] [color=" + p + "]" + r_id + "[/color]")

	var r_clearance: String = _email_meta.get("收件方安全许可", _email_meta.get("recipient_clearance", ""))
	if not r_clearance.is_empty():
		info.append("[color=" + m + "]许  可:[/color] [color=" + w + "]" + r_clearance + "[/color]")

	# 替换 {username}
	if main.user_mgr != null and main.user_mgr.is_logged_in:
		var uname: String = main.user_mgr.get_username()
		for idx in range(info.size()):
			info[idx] = info[idx].replace("{username}", uname)

	return "\n".join(info)
# ═════════════════════════════════════════════
# 照片加载
# ═════════════════════════════════════════════
func _load_photo(photo_path: String) -> ImageTexture:
	if photo_path.is_empty():
		return null
	if fs == null:
		return null

	var normalized: String = fs.normalize_path(photo_path)
	var data: PackedByteArray = fs.get_binary_data(normalized)
	if data.is_empty():
		return null

	var image := Image.new()
	var err: Error = ERR_FILE_UNRECOGNIZED
	var ext: String = photo_path.get_extension().to_lower()

	match ext:
		"png":
			err = image.load_png_from_buffer(data)
		"jpg", "jpeg":
			err = image.load_jpg_from_buffer(data)
		"bmp":
			err = image.load_bmp_from_buffer(data)
		"webp":
			err = image.load_webp_from_buffer(data)

	if err != OK:
		return null

	# 缩放到一寸照大小
	image.resize(PHOTO_WIDTH, PHOTO_HEIGHT, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)

func _make_photo_placeholder(id: String) -> String:
	return "\u0001EMAILPHOTO:" + id + "\u0002"

# ═════════════════════════════════════════════
# 打字效果
# ═════════════════════════════════════════════
func process_typing(delta: float) -> void:
	if not is_active or not _typing:
		return

	_type_timer += delta
	var lines_this_frame: int = maxi(1, int(_type_timer / _type_speed))
	_type_timer = fmod(_type_timer, _type_speed)

	for i in range(lines_this_frame):
		if _line_index >= _lines.size():
			_typing = false
			content_rtl.scroll_to_line(0)
			break

		var line: String = _lines[_line_index]
		if _line_index > 0:
			content_rtl.append_text("\n")

		# 检查照片占位符
		if line.contains("\u0001EMAILPHOTO:") and line.contains("\u0002"):
			_append_line_with_photos(content_rtl, line)
		# 检查内联图片占位符
		elif line.contains("\u0001IMG:") and line.contains("\u0002"):
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
		if line.contains("\u0001EMAILPHOTO:") and line.contains("\u0002"):
			_append_line_with_photos(content_rtl, line)
		elif line.contains("\u0001IMG:") and line.contains("\u0002"):
			_append_line_with_images(content_rtl, line)
		else:
			content_rtl.append_text(line)
	content_rtl.scroll_to_line(0)
	_typing = false

# ═════════════════════════════════════════════
# 照片占位符处理
# ═════════════════════════════════════════════
func _append_line_with_photos(rtl: RichTextLabel, line: String) -> void:
	var remaining: String = line
	while true:
		var start_pos: int = remaining.find("\u0001EMAILPHOTO:")
		if start_pos == -1:
			break
		var end_pos: int = remaining.find("\u0002", start_pos)
		if end_pos == -1:
			break

		if start_pos > 0:
			rtl.append_text(remaining.substr(0, start_pos))

		var photo_id: String = remaining.substr(start_pos + 12, end_pos - start_pos - 12)

		var texture: ImageTexture = null
		if photo_id == "SENDER_PHOTO":
			texture = _load_photo(str(_email_meta.get("sender_photo", "")))
		elif photo_id == "RECIPIENT_PHOTO":
			texture = _load_photo(str(_email_meta.get("recipient_photo", "")))

		if texture != null:
			rtl.add_image(texture as Texture2D, PHOTO_WIDTH, PHOTO_HEIGHT)
		else:
			# 绘制占位框
			var p_hex: String = T.muted_hex if T else "#888888"
			rtl.append_text("[color=" + p_hex + "][PHOTO][/color]")

		remaining = remaining.substr(end_pos + 1)

	if not remaining.is_empty():
		rtl.append_text(remaining)

# ═════════════════════════════════════════════
# 内联图片处理（与 document_viewer 一致）
# ═════════════════════════════════════════════
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

# ═════════════════════════════════════════════
# 导航栏
# ═════════════════════════════════════════════
func _build_nav_text() -> String:
	var p: String = T.primary_hex if T != null else "#A0FFA0"
	var m: String = T.muted_hex if T != null else "#888888"
	var parts: Array[String] = []
	parts.append("[color=" + p + "]↑↓/PgUp/PgDn 滚动[/color]")
	parts.append("    [color=" + m + "][Q/Esc 退出][/color]")
	return "  ".join(parts)

# ═════════════════════════════════════════════
# 供外部调用
# ═════════════════════════════════════════════
func get_active_page_rtl() -> RichTextLabel:
	if is_active and content_rtl != null and is_instance_valid(content_rtl):
		return content_rtl
	return null
