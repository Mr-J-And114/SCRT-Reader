# ============================================================
# image_viewer.gd - CRT 风格图片查看器
# 参考 oscilloscope.gd 的 overlay 方案
# 继承 RefCounted，动态创建 overlay 挂到 Main 根节点
# 功能：图片加载显示、CRT 效果覆盖、缩放/平移、逐行扫描加载动画
# ============================================================
class_name ImageViewer
extends RefCounted

# ══════════════════════════════════════════
#  模块引用
# ══════════════════════════════════════════
var main = null
var T = null

# ══════════════════════════════════════════
#  状态
# ══════════════════════════════════════════
var is_active: bool = false
var current_file_path: String = ""
var current_file_name: String = ""

# ══════════════════════════════════════════
#  图片数据
# ══════════════════════════════════════════
var texture: ImageTexture = null        # 加载后的图片纹理
var image_size: Vector2 = Vector2.ZERO  # 原始图片尺寸

# ══════════════════════════════════════════
#  视图控制
# ══════════════════════════════════════════
var zoom: float = 1.0                   # 当前缩放倍率
var zoom_min: float = 0.1
var zoom_max: float = 10.0
var zoom_step: float = 0.15             # 每次缩放增量（乘法）
var pan_offset: Vector2 = Vector2.ZERO  # 平移偏移（像素）
var pan_speed: float = 40.0             # 方向键平移速度（像素/次）
var fit_mode: bool = true               # 是否处于适应屏幕模式

# ══════════════════════════════════════════
#  逐行扫描加载动画
# ══════════════════════════════════════════
var scan_active: bool = false           # 是否正在执行扫描动画
var scan_progress: float = 0.0          # 扫描进度 0.0 ~ 1.0
var scan_speed: float = 1.5             # 扫描速度（每秒完成的比例）
var scan_line_glow: float = 0.0         # 扫描线发光亮度

# ══════════════════════════════════════════
#  UI 节点引用
# ══════════════════════════════════════════
var overlay: Panel = null
var image_canvas: Control = null        # 自定义绘制画布
var nav_label: RichTextLabel = null     # 底部导航栏
var info_label: RichTextLabel = null    # 顶部信息栏

# ══════════════════════════════════════════
#  缓存
# ══════════════════════════════════════════
var _cached_input_visible: bool = true
var _cached_prompt_visible: bool = true
var _cached_output_text: String = ""

# ══════════════════════════════════════════
#  绘制参数
# ══════════════════════════════════════════
var draw_color: Color = Color(0.2, 1.0, 0.3, 1.0)
var draw_color_dim: Color = Color(0.1, 0.5, 0.15, 0.6)
var grid_color: Color = Color(0.1, 0.3, 0.1, 0.15)
var background_color: Color = Color(0.0, 0.02, 0.0, 0.95)
var scan_line_color: Color = Color(0.3, 1.0, 0.4, 0.8)

# ══════════════════════════════════════════
#  鼠标拖拽
# ══════════════════════════════════════════
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _pan_start: Vector2 = Vector2.ZERO

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(p_main) -> void:
	main = p_main
	T = ThemeManager.current
	_update_colors()

func _update_colors() -> void:
	if T == null:
		return
	draw_color = T.primary
	draw_color.a = 1.0
	draw_color_dim = T.primary
	draw_color_dim.a = 0.4
	grid_color = T.primary
	grid_color.a = 0.1
	background_color = T.bg
	background_color.a = 0.95
	scan_line_color = T.primary
	scan_line_color.a = 0.8
	scan_line_color = scan_line_color.lightened(0.3)

# ══════════════════════════════════════════
#  构建 UI 节点
# ══════════════════════════════════════════
func _ensure_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		return

	# 最外层 Panel
	overlay = Panel.new()
	overlay.name = "ImageViewerOverlay"
	overlay.visible = false

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0)
	overlay.add_theme_stylebox_override("panel", bg_style)

	var root_control: Control = main as Control
	root_control.add_child(overlay)

	# 移到 CRTEffect 之前
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
	margin.offset_left = 0
	margin.offset_top = 0
	margin.offset_right = 0
	margin.offset_bottom = 0
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	overlay.add_child(margin)

	# VBoxContainer
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	# 顶部信息栏
	info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.fit_content = true
	info_label.scroll_active = false
	info_label.selection_enabled = false
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if T:
		info_label.add_theme_color_override("default_color", T.muted)
	vbox.add_child(info_label)

	# 图片画布
	image_canvas = _ImageCanvas.new()
	image_canvas.name = "ImageCanvas"
	image_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(image_canvas as _ImageCanvas).viewer = self
	image_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_child(image_canvas)

	# 底部导航栏
	nav_label = RichTextLabel.new()
	nav_label.bbcode_enabled = true
	nav_label.fit_content = true
	nav_label.scroll_active = false
	nav_label.selection_enabled = false
	nav_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if T:
		nav_label.add_theme_color_override("default_color", T.muted)
	vbox.add_child(nav_label)

func _align_overlay_to_output_area() -> void:
	if overlay == null or not is_instance_valid(overlay):
		return
	var output_area: ScrollContainer = main.scroll_container
	var rect: Rect2 = output_area.get_global_rect()
	overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	overlay.position = rect.position
	overlay.size = rect.size

# ══════════════════════════════════════════
#  从字节数据加载图片
# ══════════════════════════════════════════
func _load_image_from_bytes(file_path: String, data: PackedByteArray) -> bool:
	if data.is_empty():
		return false

	var img := Image.new()
	var ext: String = file_path.get_extension().to_lower()
	var err: Error = ERR_FILE_UNRECOGNIZED

	match ext:
		"png":
			err = img.load_png_from_buffer(data)
		"jpg", "jpeg":
			err = img.load_jpg_from_buffer(data)
		"bmp":
			err = img.load_bmp_from_buffer(data)
		"webp":
			err = img.load_webp_from_buffer(data)
		"tga":
			err = img.load_tga_from_buffer(data)
		_:
			push_warning("[ImageViewer] 不支持的图片格式: ", ext)
			return false

	if err != OK:
		push_warning("[ImageViewer] 图片加载失败: ", file_path, " 错误: ", err)
		return false

	texture = ImageTexture.create_from_image(img)
	image_size = Vector2(img.get_width(), img.get_height())
	print("[ImageViewer] 图片已加载: ", file_path, " 尺寸: ", image_size)
	return true

# ══════════════════════════════════════════
#  打开 / 关闭
# ══════════════════════════════════════════
func open_with_file(file_path: String, file_name: String, data: PackedByteArray) -> void:
	_ensure_overlay()

	T = ThemeManager.current
	_update_colors()
	_align_overlay_to_output_area()

	# 加载图片
	if not _load_image_from_bytes(file_path, data):
		main.append_output("[color=" + T.error_hex + "]无法加载图片: " + file_name + "[/color]\n", false)
		return

	current_file_path = file_path
	current_file_name = file_name
	is_active = true

	# 重置视图
	zoom = 1.0
	pan_offset = Vector2.ZERO
	fit_mode = true
	_dragging = false

	# 启动扫描动画
	scan_active = true
	scan_progress = 0.0
	scan_line_glow = 1.0

	# 缓存并隐藏终端元素
	_cached_input_visible = main.input_field.visible
	_cached_prompt_visible = main.prompt_label.visible
	main.input_field.visible = false
	main.prompt_label.visible = false
	_cached_output_text = main.output_text.text
	main.output_text.text = ""

	# 更新状态栏
	main.path_label.text = "IMAGE VIEWER | " + file_name + " | Q/Esc 退出"

	# ★ 隐藏 COMM 按钮（避免遮挡）
	if main.comm_mgr and main.comm_mgr._ui and main.comm_mgr._ui._toggle_btn:
		main.comm_mgr._ui._toggle_btn.visible = false

	# 显示
	overlay.visible = true
	image_canvas.set_process(true)
	_update_info()
	_update_nav()

func close() -> void:
	if not is_active:
		return

	is_active = false
	scan_active = false
	texture = null

	if overlay and is_instance_valid(overlay):
		overlay.visible = false
	if image_canvas:
		image_canvas.set_process(false)

	current_file_path = ""
	current_file_name = ""

	# 恢复终端
	main.output_text.clear()
	main.output_text.append_text(_cached_output_text)
	_cached_output_text = ""
	main.input_field.visible = _cached_input_visible
	main.prompt_label.visible = _cached_prompt_visible
	main._update_status_bar()

	# ★ 恢复 COMM 按钮
	if main.comm_mgr and main.comm_mgr._ui and main.comm_mgr._ui._toggle_btn:
		main.comm_mgr._ui._toggle_btn.visible = true

	main.input_field.grab_focus()

	# 通知 main
	if main.has_method("_on_image_viewer_closed"):
		main._on_image_viewer_closed()

# ══════════════════════════════════════════
#  输入处理
# ══════════════════════════════════════════
func handle_input(event: InputEvent) -> bool:
	if not is_active:
		return false

	# 键盘事件
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_Q, KEY_ESCAPE:
				close()
				return true
			KEY_EQUAL, KEY_KP_ADD:  # + 放大
				_zoom_in()
				return true
			KEY_MINUS, KEY_KP_SUBTRACT:  # - 缩小
				_zoom_out()
				return true
			KEY_0, KEY_KP_0:  # 0 适应屏幕
				_fit_to_screen()
				return true
			KEY_1:  # 1 原始尺寸 (1:1)
				_zoom_to_actual()
				return true
			KEY_LEFT:
				pan_offset.x += pan_speed
				fit_mode = false
				_update_info()
				return true
			KEY_RIGHT:
				pan_offset.x -= pan_speed
				fit_mode = false
				_update_info()
				return true
			KEY_UP:
				pan_offset.y += pan_speed
				fit_mode = false
				_update_info()
				return true
			KEY_DOWN:
				pan_offset.y -= pan_speed
				fit_mode = false
				_update_info()
				return true
			KEY_HOME:  # 重置视图
				pan_offset = Vector2.ZERO
				_fit_to_screen()
				return true

	# 鼠标滚轮缩放
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_in()
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_out()
				return true
			MOUSE_BUTTON_LEFT:
				_dragging = true
				_drag_start = event.position
				_pan_start = pan_offset
				return true
			MOUSE_BUTTON_MIDDLE:
				# 中键重置
				pan_offset = Vector2.ZERO
				_fit_to_screen()
				return true

	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = false
			return true

	# 鼠标拖拽
	if event is InputEventMouseMotion and _dragging:
		pan_offset = _pan_start + (event.position - _drag_start)
		fit_mode = false
		_update_info()
		return true

	return false

func _zoom_in() -> void:
	zoom = minf(zoom * (1.0 + zoom_step), zoom_max)
	fit_mode = false
	_update_info()
	_update_nav()

func _zoom_out() -> void:
	zoom = maxf(zoom * (1.0 - zoom_step), zoom_min)
	fit_mode = false
	_update_info()
	_update_nav()

func _fit_to_screen() -> void:
	if texture == null or image_canvas == null:
		return
	var canvas_size: Vector2 = image_canvas.size
	var margin_px: float = 40.0  # 内边距
	var available: Vector2 = canvas_size - Vector2(margin_px * 2, margin_px * 2)
	if available.x <= 0 or available.y <= 0:
		return
	var scale_x: float = available.x / image_size.x
	var scale_y: float = available.y / image_size.y
	zoom = minf(scale_x, scale_y)
	zoom = clampf(zoom, zoom_min, zoom_max)
	pan_offset = Vector2.ZERO
	fit_mode = true
	_update_info()
	_update_nav()

func _zoom_to_actual() -> void:
	zoom = 1.0
	pan_offset = Vector2.ZERO
	fit_mode = false
	_update_info()
	_update_nav()

# ══════════════════════════════════════════
#  每帧处理（由 _ImageCanvas._process 调用）
# ══════════════════════════════════════════
func process_frame(delta: float) -> void:
	if not is_active:
		return

	# 扫描动画更新
	if scan_active:
		scan_progress += scan_speed * delta
		if scan_progress >= 1.0:
			scan_progress = 1.0
			scan_active = false
			scan_line_glow = 0.0
		else:
			# 扫描线发光脉冲
			scan_line_glow = 0.6 + 0.4 * sin(scan_progress * 20.0)

	if image_canvas:
		image_canvas.queue_redraw()

# ══════════════════════════════════════════
#  绘制（由 _ImageCanvas._draw 调用）
# ══════════════════════════════════════════
func draw_image(canvas: Control) -> void:
	if not is_active or texture == null:
		return

	var canvas_size: Vector2 = canvas.size

	# 背景
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas_size), background_color)

	# 第一次绘制时，如果是 fit_mode 需要计算初始缩放
	if fit_mode and zoom == 1.0:
		var margin_px: float = 40.0
		var available: Vector2 = canvas_size - Vector2(margin_px * 2, margin_px * 2)
		if available.x > 0 and available.y > 0:
			var scale_x: float = available.x / image_size.x
			var scale_y: float = available.y / image_size.y
			zoom = minf(minf(scale_x, scale_y), 1.0)  # 不超过原始尺寸
			zoom = clampf(zoom, zoom_min, zoom_max)

	# 计算图片绘制位置（居中 + 偏移）
	var draw_size: Vector2 = image_size * zoom
	var center: Vector2 = canvas_size * 0.5
	var draw_pos: Vector2 = center - draw_size * 0.5 + pan_offset

	# 绘制网格背景（棋盘格，表示透明区域）
	_draw_checker_background(canvas, Rect2(draw_pos, draw_size))

	# 绘制图片
	if scan_active:
		# 扫描动画：只显示已扫描的部分
		_draw_image_with_scanline(canvas, draw_pos, draw_size)
	else:
		# 正常显示完整图片
		canvas.draw_texture_rect(texture, Rect2(draw_pos, draw_size), false)

	# 图片边框
	var border_color: Color = draw_color_dim
	border_color.a = 0.4
	canvas.draw_rect(Rect2(draw_pos - Vector2(1, 1), draw_size + Vector2(2, 2)), border_color, false, 1.0)

	# 十字准线（画面中心标记）
	_draw_crosshair(canvas, canvas_size)


func _draw_checker_background(canvas: Control, rect: Rect2) -> void:
	# 简化棋盘格：只绘制两层纯色，不做逐格绘制
	var clip_rect: Rect2 = Rect2(Vector2.ZERO, canvas.size).intersection(rect)
	if clip_rect.size.x <= 0 or clip_rect.size.y <= 0:
		return
	var dark: Color = Color(0.03, 0.05, 0.03, 0.8)
	canvas.draw_rect(clip_rect, dark)


func _draw_image_with_scanline(canvas: Control, draw_pos: Vector2, draw_size: Vector2) -> void:
	if texture == null:
		return

	# 已扫描的区域高度
	var scan_height: float = draw_size.y * scan_progress

	# 使用 clip_children 替代方案：绘制完整图片，然后用黑色遮盖未扫描区域
	canvas.draw_texture_rect(texture, Rect2(draw_pos, draw_size), false)

	# 未扫描区域用背景色遮盖
	var unscan_y: float = draw_pos.y + scan_height
	var unscan_height: float = draw_size.y - scan_height
	if unscan_height > 0:
		canvas.draw_rect(
			Rect2(draw_pos.x, unscan_y, draw_size.x, unscan_height),
			background_color
		)

	# 扫描线发光效果
	if scan_progress > 0.0 and scan_progress < 1.0:
		var line_y: float = draw_pos.y + scan_height
		var line_width: float = draw_size.x

		# 发光光晕（宽）
		var glow_height: float = 12.0
		var glow_color: Color = scan_line_color
		glow_color.a = scan_line_glow * 0.15
		canvas.draw_rect(
			Rect2(draw_pos.x, line_y - glow_height * 0.5, line_width, glow_height),
			glow_color
		)

		# 主扫描线（亮）
		var main_line_color: Color = scan_line_color
		main_line_color.a = scan_line_glow * 0.9
		canvas.draw_line(
			Vector2(draw_pos.x, line_y),
			Vector2(draw_pos.x + line_width, line_y),
			main_line_color, 2.0
		)

		# 拖尾效果（扫描线上方渐暗）
		var trail_height: float = 30.0
		for ti in range(5):
			var t_ratio: float = float(ti) / 5.0
			var t_y: float = line_y - trail_height * t_ratio
			if t_y < draw_pos.y:
				break
			var t_color: Color = scan_line_color
			t_color.a = scan_line_glow * 0.05 * (1.0 - t_ratio)
			canvas.draw_line(
				Vector2(draw_pos.x, t_y),
				Vector2(draw_pos.x + line_width, t_y),
				t_color, 1.0
			)

func _draw_crosshair(canvas: Control, canvas_size: Vector2) -> void:
	var cx: float = canvas_size.x * 0.5
	var cy: float = canvas_size.y * 0.5
	var ch_size: float = 10.0
	var ch_color: Color = draw_color_dim
	ch_color.a = 0.15

	canvas.draw_line(Vector2(cx - ch_size, cy), Vector2(cx + ch_size, cy), ch_color, 1.0)
	canvas.draw_line(Vector2(cx, cy - ch_size), Vector2(cx, cy + ch_size), ch_color, 1.0)

# ══════════════════════════════════════════
#  信息栏
# ══════════════════════════════════════════
func _update_info() -> void:
	if info_label == null:
		return

	var p: String = T.primary_hex if T else "#99FF99"
	var m: String = T.muted_hex if T else "#8CAF8C"

	var zoom_pct: String = str(snapped(zoom * 100, 1)) + "%"
	var mode_str: String = "FIT" if fit_mode else "FREE"
	var size_str: String = str(int(image_size.x)) + "x" + str(int(image_size.y))

	var text: String = ""
	text += "[color=" + p + "]IMAGE VIEWER[/color]"
	text += "  [color=" + m + "]" + current_file_name + "[/color]"
	text += "  [color=" + m + "]" + size_str + "[/color]"
	text += "  [color=" + p + "]" + zoom_pct + "[/color]"
	text += "  [color=" + m + "][" + mode_str + "][/color]"

	if scan_active:
		var scan_pct: String = str(snapped(scan_progress * 100, 1)) + "%"
		text += "  [color=" + p + "]SCANNING: " + scan_pct + "[/color]"

	info_label.text = ""
	info_label.append_text(text)

func _update_nav() -> void:
	if nav_label == null:
		return

	var p: String = T.primary_hex if T else "#99FF99"
	var m: String = T.muted_hex if T else "#8CAF8C"

	var parts: Array[String] = []
	parts.append("  [color=" + p + "]+/-[/color][color=" + m + "]:缩放[/color]")
	parts.append("  [color=" + p + "]0[/color][color=" + m + "]:适应屏幕[/color]")
	parts.append("  [color=" + p + "]1[/color][color=" + m + "]:原始尺寸[/color]")
	parts.append("  [color=" + p + "]方向键/拖拽[/color][color=" + m + "]:平移[/color]")
	parts.append("  [color=" + p + "]滚轮[/color][color=" + m + "]:缩放[/color]")
	parts.append("  [color=" + p + "]Home[/color][color=" + m + "]:重置[/color]")
	parts.append("  [color=" + p + "]Q/Esc[/color][color=" + m + "]:退出[/color]")

	nav_label.text = ""
	nav_label.append_text("".join(parts))

# ══════════════════════════════════════════
#  内部类：图片绘制画布
# ══════════════════════════════════════════
class _ImageCanvas extends Control:
	var viewer: ImageViewer = null

	func _process(delta: float) -> void:
		if viewer:
			viewer.process_frame(delta)

	func _draw() -> void:
		if viewer:
			viewer.draw_image(self)

	func _gui_input(event: InputEvent) -> void:
		# 将画布上的鼠标事件转发给 viewer
		if viewer and viewer.is_active:
			if event is InputEventMouseButton or event is InputEventMouseMotion:
				viewer.handle_input(event)
				accept_event()
