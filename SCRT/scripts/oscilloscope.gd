# ============================================================
# oscilloscope.gd - 示波器 / 音频播放器界面
# 参考 document_viewer.gd 的节点布局方案
# 继承 RefCounted，动态创建 overlay 挂到 Main 根节点
# ============================================================
class_name Oscilloscope
extends RefCounted

var _nav_update_timer: float = 0.0

# ══════════════════════════════════════════
#  模块引用
# ══════════════════════════════════════════
var main = null
var audio_manager = null
var T = null
var crtml: CrtmlParser = null

# ══════════════════════════════════════════
#  显示模式
# ══════════════════════════════════════════
enum Mode { SPECTRUM, LISSAJOUS }
var current_mode: Mode = Mode.SPECTRUM
var mode_names: Dictionary = {
	Mode.SPECTRUM: "SPECTRUM",
	Mode.LISSAJOUS: "LISSAJOUS"
}

var desc_label: RichTextLabel = null      # 音频说明文字区域
var audio_description: String = ""         # 音频说明内容

# ══════════════════════════════════════════
#  状态
# ══════════════════════════════════════════
var is_active: bool = false
var is_playing_file: bool = false
var current_file_path: String = ""
var current_file_name: String = ""

# ══════════════════════════════════════════
#  UI 节点引用
# ══════════════════════════════════════════
var overlay: Panel = null
var scope_canvas: Control = null        # 示波器绘制区域（自定义 _draw）
var nav_label: RichTextLabel = null      # 底部导航/信息

# 缓存
var _cached_input_visible: bool = true
var _cached_prompt_visible: bool = true
var _cached_output_text: String = ""

# ══════════════════════════════════════════
#  频谱分析
# ══════════════════════════════════════════
var spectrum_data: Array[float] = []
var spectrum_peaks: Array[float] = []
var spectrum_bars: int = 64
var min_freq: float = 20.0
var max_freq: float = 16000.0

# ══════════════════════════════════════════
#  波形捕获（用于李萨如的真实 XY 模式）
# ══════════════════════════════════════════
var capture_buffer_size: int = 256        # 每帧读取的采样数

# ══════════════════════════════════════════
#  李萨如数据
# ══════════════════════════════════════════
var lissajous_points: Array[Vector2] = []
var lissajous_history: Array[Array] = []
var lissajous_history_max: int = 8
var lissajous_scale: float = 1.0           # 李萨如图形缩放
var lissajous_scale_min: float = 0.2
var lissajous_scale_max: float = 5.0
var lissajous_scale_step: float = 0.2

# ══════════════════════════════════════════
#  绘制参数
# ══════════════════════════════════════════
var draw_color: Color = Color(0.2, 1.0, 0.3, 1.0)
var draw_color_dim: Color = Color(0.1, 0.5, 0.15, 0.6)
var grid_color: Color = Color(0.1, 0.3, 0.1, 0.3)
var peak_color: Color = Color(0.3, 1.0, 0.5, 0.8)
var background_color: Color = Color(0.0, 0.02, 0.0, 0)

# ══════════════════════════════════════════
#  动画参数
# ══════════════════════════════════════════
var peak_fall_speed: float = 0.5
var spectrum_smooth: float = 0.3
var _close_pending: bool = false

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(p_main, p_audio_manager) -> void:
	main = p_main
	audio_manager = p_audio_manager
	T = ThemeManager.current
	_update_colors()
	_init_spectrum_data()

## 延迟获取 crtml 引用，确保 main.crtml 已完成 setup
func _ensure_crtml() -> void:
	if crtml != null:
		return
	if main != null and main.get("crtml") != null:
		crtml = main.crtml as CrtmlParser
		# 确认 crtml 已完成初始化（T 不为 null）
		if crtml != null and crtml.T == null:
			crtml.setup(T, main.fs if main.get("fs") != null else null)

func _update_colors() -> void:
	if T == null:
		return
	draw_color = T.primary
	draw_color.a = 1.0
	draw_color_dim = T.primary
	draw_color_dim.a = 0.4
	grid_color = T.primary
	grid_color.a = 0.15
	peak_color = T.primary
	peak_color.a = 0.7
	peak_color = peak_color.lightened(0.3)
	background_color = T.bg
	background_color.a = 0
	# 更新说明文字区域颜色
	if desc_label and is_instance_valid(desc_label):
		desc_label.add_theme_color_override("default_color", T.secondary)
	# 更新导航栏颜色
	if nav_label and is_instance_valid(nav_label):
		nav_label.add_theme_color_override("default_color", T.muted)

func _init_spectrum_data() -> void:
	spectrum_data.clear()
	spectrum_peaks.clear()
	for i in range(spectrum_bars):
		spectrum_data.append(0.0)
		spectrum_peaks.append(0.0)

# ══════════════════════════════════════════
#  将 CRT-ML 原始文本解析为 BBCode
# ══════════════════════════════════════════
func _parse_description(raw_text: String) -> String:
	_ensure_crtml()
	if crtml != null:
		var parsed: String = crtml.parse(raw_text)
		# 去除 TW 占位符（示波器不走打字机，不需要速度/暂停等控制）
		if CrtmlParser.has_tw_tags(parsed):
			parsed = CrtmlParser.strip_tw_tags(parsed)
		# 去除分页标记（示波器描述不分页）
		parsed = parsed.replace(CrtmlParser.PAGE_BREAK_TAG, "")
		return parsed
	# crtml 不可用时的回退：使用独立的临时实例
	var fallback_parser := CrtmlParser.new()
	fallback_parser.setup(T, main.fs if main != null and main.get("fs") != null else null)
	var parsed: String = fallback_parser.parse(raw_text)
	if CrtmlParser.has_tw_tags(parsed):
		parsed = CrtmlParser.strip_tw_tags(parsed)
	parsed = parsed.replace(CrtmlParser.PAGE_BREAK_TAG, "")
	return parsed

# ══════════════════════════════════════════
#  构建 UI 节点（参考 document_viewer.gd）
# ══════════════════════════════════════════
func _ensure_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		return

	var theme_colors = ThemeManager.current

	# ═══════════════════════════════
	#  最外层 Panel，挂到 Main 根节点
	# ═══════════════════════════════
	overlay = Panel.new()
	overlay.name = "OscilloscopeOverlay"
	overlay.visible = false

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0)
	overlay.add_theme_stylebox_override("panel", bg_style)

	# ★ 挂到 Main（根节点）
	var root_control: Control = main as Control
	root_control.add_child(overlay)

	# ★ 把 overlay 移到 CRTEffect 之前（这样 CRT shader 仍然覆盖在上面）
	var crt_node: Node = root_control.get_node_or_null("CRTEffect")
	if crt_node:
		root_control.move_child(overlay, crt_node.get_index())

	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.offset_left = 0
	overlay.offset_top = 0
	overlay.offset_right = 0
	overlay.offset_bottom = 0

	# ═══════════════════════════════
	#  MarginContainer
	# ═══════════════════════════════
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

	# ═══════════════════════════════
	#  VBoxContainer
	# ═══════════════════════════════
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	# ═══════════════════════════════
	#  内容区域：HBoxContainer（频谱+说明）
	# ═══════════════════════════════
	var content_hbox := HBoxContainer.new()
	content_hbox.name = "ContentHBox"
	content_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 0)
	vbox.add_child(content_hbox)

	# 示波器画布
	scope_canvas = _ScopeCanvas.new()
	scope_canvas.name = "ScopeCanvas"
	scope_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scope_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(scope_canvas as _ScopeCanvas).oscilloscope = self
	content_hbox.add_child(scope_canvas)

	# 说明文字区域（频谱模式下显示在右半边）
	desc_label = RichTextLabel.new()
	desc_label.name = "DescLabel"
	desc_label.bbcode_enabled = true
	desc_label.fit_content = false
	desc_label.scroll_active = true
	desc_label.scroll_following = false
	desc_label.selection_enabled = true
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_label.mouse_filter = Control.MOUSE_FILTER_STOP

	if theme_colors:
		desc_label.add_theme_color_override("default_color", theme_colors.secondary)

	# 透明背景
	var desc_style := StyleBoxFlat.new()
	desc_style.bg_color = Color(0, 0, 0, 0)
	desc_style.content_margin_left = 12
	desc_style.content_margin_right = 8
	desc_style.content_margin_top = 4
	desc_label.add_theme_stylebox_override("normal", desc_style)

	content_hbox.add_child(desc_label)
	desc_label.visible = false  # 默认隐藏，频谱模式且有说明时才显示

	# ★ 应用字体覆盖（参考 document_viewer.gd 的 _create_page_rtl）
	CrtmlParser.apply_fonts(desc_label)
	UIManager._apply_bold_font(desc_label)

	# ═══════════════════════════════
	#  底部导航/信息栏
	# ═══════════════════════════════
	nav_label = RichTextLabel.new()
	nav_label.bbcode_enabled = true
	nav_label.fit_content = true
	nav_label.scroll_active = false
	nav_label.selection_enabled = false
	nav_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if theme_colors:
		nav_label.add_theme_color_override("default_color", theme_colors.muted)

	vbox.add_child(nav_label)

## 将 overlay 对齐到 OutputArea
func _align_overlay_to_output_area() -> void:
	if overlay == null or not is_instance_valid(overlay):
		return
	var output_area: ScrollContainer = main.scroll_container
	var rect: Rect2 = output_area.get_global_rect()
	overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	overlay.position = rect.position
	overlay.size = rect.size

# ══════════════════════════════════════════
#  打开 / 关闭
# ══════════════════════════════════════════

## 以文件播放模式打开
func open_with_file(file_path: String, file_name: String, stream: AudioStream) -> void:
	_ensure_overlay()

	# 刷新主题色和 crtml 引用
	T = ThemeManager.current
	_ensure_crtml()
	_update_colors()
	_align_overlay_to_output_area()

	current_file_path = file_path
	current_file_name = file_name
	is_playing_file = true
	is_active = true
	_close_pending = false
	current_mode = Mode.SPECTRUM

	# 缓存并隐藏终端元素
	_cached_input_visible = main.input_field.visible
	_cached_prompt_visible = main.prompt_label.visible
	main.input_field.visible = false
	main.prompt_label.visible = false
	_cached_output_text = main.output_text.text
	main.output_text.text = ""

	# 更新状态栏
	var title: String = "OSCILLOSCOPE | " + file_name + " | Q/Esc 退出"
	main.path_label.text = title

	# 尝试加载同名 .txt 说明文件
	audio_description = ""
	var desc_path: String = file_path.get_basename() + ".txt"
	if main != null and main.fs != null:
		# ★ 优先使用 read_file()，它能正确处理编码和返回完整文本内容
		if main.fs.has_method("read_file"):
			var content_text: String = main.fs.read_file(desc_path)
			if not content_text.is_empty():
				audio_description = content_text
		# 回退：直接从 FSNode 读取 content 属性
		if audio_description.is_empty():
			var desc_node = main.fs.get_node_at_path(desc_path)
			if desc_node != null and desc_node.type == "file":
				if desc_node.content != null and not str(desc_node.content).is_empty():
					audio_description = str(desc_node.content)

	# ★ 调试输出，确认描述文本加载情况（上线前可删除）
	if not audio_description.is_empty():
		print("[Oscilloscope] 已加载音频说明文件: ", desc_path, " (", audio_description.length(), " 字符)")
	else:
		print("[Oscilloscope] 未找到音频说明文件: ", desc_path)

	# 播放音频
	audio_manager.play_media(stream)

	# 监听播放完成信号
	if not audio_manager.media_playback_finished.is_connected(_on_playback_finished):
		audio_manager.media_playback_finished.connect(_on_playback_finished)

	# 显示
	overlay.visible = true
	scope_canvas.set_process(true)
	_update_layout_for_mode()
	_update_nav()

## 关闭示波器
func close() -> void:
	if not is_active:
		return

	is_active = false

	# 断开信号
	if audio_manager.media_playback_finished.is_connected(_on_playback_finished):
		audio_manager.media_playback_finished.disconnect(_on_playback_finished)

	if overlay and is_instance_valid(overlay):
		overlay.visible = false
	if scope_canvas:
		scope_canvas.set_process(false)

	if is_playing_file:
		audio_manager.stop_media()

	is_playing_file = false
	current_file_path = ""
	current_file_name = ""

	# 恢复终端
	main.output_text.clear()
	main.output_text.append_text(_cached_output_text)
	_cached_output_text = ""
	main.input_field.visible = _cached_input_visible
	main.prompt_label.visible = _cached_prompt_visible
	main._update_status_bar()

	main.input_field.grab_focus()

	# 通知 main
	if main.has_method("_on_oscilloscope_closed"):
		main._on_oscilloscope_closed()

func _on_playback_finished() -> void:
	if is_active and is_playing_file:
		_close_pending = true

# ══════════════════════════════════════════
#  输入处理
# ══════════════════════════════════════════
func handle_input(event: InputEvent) -> bool:
	if not is_active:
		return false

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_Q, KEY_ESCAPE:
				close()
				return true
			KEY_F1:
				current_mode = Mode.SPECTRUM
				_update_layout_for_mode()
				_update_nav()
				return true
			KEY_F2:
				current_mode = Mode.LISSAJOUS
				_update_layout_for_mode()
				_update_nav()
				return true
			KEY_SPACE:
				if is_playing_file:
					audio_manager.pause_media()
					_update_nav()
					return true
			KEY_LEFT:
				if is_playing_file and audio_manager.is_media_playing():
					var pos: float = audio_manager.get_media_playback_position()
					audio_manager.seek_media(maxf(0.0, pos - 5.0))
					return true
			KEY_RIGHT:
				if is_playing_file and audio_manager.is_media_playing():
					var pos: float = audio_manager.get_media_playback_position()
					var total: float = audio_manager.get_media_length()
					audio_manager.seek_media(minf(total, pos + 5.0))
					return true
			KEY_EQUAL, KEY_KP_ADD:  # + 键（放大）
				if current_mode == Mode.LISSAJOUS:
					lissajous_scale = minf(lissajous_scale + lissajous_scale_step, lissajous_scale_max)
					_update_nav()
					return true
			KEY_MINUS, KEY_KP_SUBTRACT:  # - 键（缩小）
				if current_mode == Mode.LISSAJOUS:
					lissajous_scale = maxf(lissajous_scale - lissajous_scale_step, lissajous_scale_min)
					_update_nav()
					return true
			KEY_0, KEY_KP_0:  # 0 键（重置缩放）
				if current_mode == Mode.LISSAJOUS:
					lissajous_scale = 1.0
					_update_nav()
					return true

	return false

## 根据当前模式调整布局
func _update_layout_for_mode() -> void:
	if desc_label == null:
		return

	match current_mode:
		Mode.SPECTRUM:
			if not audio_description.is_empty():
				desc_label.visible = true
				desc_label.text = ""
				# ★ 关键：通过 _parse_description 使用 CrtmlParser 解析
				var parsed_bbcode: String = _parse_description(audio_description)
				desc_label.append_text(parsed_bbcode)
			else:
				desc_label.visible = false
		Mode.LISSAJOUS:
			desc_label.visible = false

# ══════════════════════════════════════════
#  每帧处理（由 _ScopeCanvas._process 调用）
# ══════════════════════════════════════════
func process_frame(delta: float) -> void:
	if not is_active:
		return

	_update_spectrum_data(delta)

	if is_playing_file:
		# 检测播放是否结束（未在播放且未暂停）
		var playing: bool = audio_manager.is_media_playing()
		var paused: bool = audio_manager.is_media_paused()
		if not playing and not paused:
			_close_pending = true

	if _close_pending:
		close()
		return

	_nav_update_timer += delta
	if _nav_update_timer >= 0.25:
		_nav_update_timer = 0.0
		_update_nav()

	if scope_canvas:
		scope_canvas.queue_redraw()

# ══════════════════════════════════════════
#  频谱数据更新
# ══════════════════════════════════════════
func _update_spectrum_data(delta: float) -> void:
	match current_mode:
		Mode.SPECTRUM:
			_update_spectrum_mode(delta)
		Mode.LISSAJOUS:
			_update_lissajous_mode(delta)

func _update_spectrum_mode(delta: float) -> void:
	# 每帧从 audio_manager 获取最新的频谱分析器实例
	var analyzer = audio_manager.get_spectrum_analyzer_instance()
	if analyzer == null:
		return

	for i in range(spectrum_bars):
		var t0: float = float(i) / float(spectrum_bars)
		var t1: float = float(i + 1) / float(spectrum_bars)
		var freq_low: float = min_freq * pow(max_freq / min_freq, t0)
		var freq_high: float = min_freq * pow(max_freq / min_freq, t1)

		var magnitude: Vector2 = analyzer.get_magnitude_for_frequency_range(
			freq_low, freq_high, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE
		)
		var mag: float = (magnitude.x + magnitude.y) * 0.5

		var energy: float = clampf(
			(linear_to_db(maxf(mag, 0.00001)) + 80.0) / 80.0,
			0.0, 1.0
		)

		spectrum_data[i] = lerpf(spectrum_data[i], energy, spectrum_smooth)

		if spectrum_data[i] > spectrum_peaks[i]:
			spectrum_peaks[i] = spectrum_data[i]
		else:
			spectrum_peaks[i] = maxf(spectrum_peaks[i] - peak_fall_speed * delta, spectrum_data[i])

func _update_lissajous_mode(_delta: float) -> void:
	lissajous_points.clear()

	# 每帧从 audio_manager 获取音频捕获实例
	var capture = audio_manager.get_audio_capture_instance()
	if capture == null:
		return

	var frames_available: int = capture.get_frames_available()
	if frames_available < capture_buffer_size:
		return

	var frames: PackedVector2Array = capture.get_buffer(capture_buffer_size)
	if frames.size() == 0:
		return

	for i in range(frames.size()):
		var left: float = frames[i].x
		var right: float = frames[i].y
		lissajous_points.append(Vector2(left, right))

	lissajous_history.push_front(lissajous_points.duplicate())
	if lissajous_history.size() > lissajous_history_max:
		lissajous_history.pop_back()

# ══════════════════════════════════════════
#  绘制（由 _ScopeCanvas._draw 调用）
# ══════════════════════════════════════════
func draw_scope(canvas: Control) -> void:
	if not is_active:
		return

	var full_size: Vector2 = canvas.size
	var margin_h: float = 20.0
	var margin_top: float = 10.0
	var margin_bottom: float = 10.0

	var draw_rect: Rect2 = Rect2(
		margin_h, margin_top,
		full_size.x - margin_h * 2,
		full_size.y - margin_top - margin_bottom
	)

	# 背景
	canvas.draw_rect(Rect2(Vector2.ZERO, full_size), background_color)

	# 边框
	var border_rect: Rect2 = Rect2(
		draw_rect.position - Vector2(1, 1),
		draw_rect.size + Vector2(2, 2)
	)
	canvas.draw_rect(border_rect, Color(draw_color.r, draw_color.g, draw_color.b, 0.3), false, 1.0)

	# 网格 + 十字轴
	_draw_grid(canvas, draw_rect)

	# 根据模式绘制
	match current_mode:
		Mode.SPECTRUM:
			_draw_spectrum(canvas, draw_rect)
		Mode.LISSAJOUS:
			_draw_lissajous(canvas, draw_rect)

	# 顶部标题
	_draw_title(canvas, full_size, draw_rect)

	# 播放进度条（在绘制区底部）
	if is_playing_file:
		_draw_progress_bar(canvas, draw_rect)

func _draw_grid(canvas: Control, rect: Rect2) -> void:
	var cx: float = rect.position.x + rect.size.x * 0.5
	var cy: float = rect.position.y + rect.size.y * 0.5

	# 十字坐标轴（比网格线更亮）
	var axis_color: Color = Color(grid_color.r, grid_color.g, grid_color.b, grid_color.a * 2.5)
	canvas.draw_line(
		Vector2(rect.position.x, cy),
		Vector2(rect.position.x + rect.size.x, cy),
		axis_color, 1.0
	)
	canvas.draw_line(
		Vector2(cx, rect.position.y),
		Vector2(cx, rect.position.y + rect.size.y),
		axis_color, 1.0
	)

	# 水平网格线
	for i in range(1, 8):
		var y: float = rect.position.y + rect.size.y * float(i) / 8.0
		canvas.draw_line(
			Vector2(rect.position.x, y),
			Vector2(rect.position.x + rect.size.x, y),
			grid_color, 1.0
		)

	# 垂直网格线
	for i in range(1, 10):
		var x: float = rect.position.x + rect.size.x * float(i) / 10.0
		canvas.draw_line(
			Vector2(x, rect.position.y),
			Vector2(x, rect.position.y + rect.size.y),
			grid_color, 1.0
		)

func _draw_spectrum(canvas: Control, rect: Rect2) -> void:
	if spectrum_data.is_empty():
		return

	var bar_width: float = rect.size.x / float(spectrum_bars)
	var gap: float = maxf(1.0, bar_width * 0.15)

	for i in range(spectrum_bars):
		var bar_height: float = spectrum_data[i] * rect.size.y
		var x: float = rect.position.x + float(i) * bar_width
		@warning_ignore("shadowed_variable")
		var y: float = rect.position.y + rect.size.y - bar_height

		# 柱状图
		var bar_rect: Rect2 = Rect2(
			x + gap * 0.5, y,
			bar_width - gap, bar_height
		)
		var intensity: float = spectrum_data[i]
		var bar_color: Color = draw_color
		bar_color.a = 0.3 + intensity * 0.7
		canvas.draw_rect(bar_rect, bar_color)

		# 峰值标记
		var peak_y: float = rect.position.y + rect.size.y - spectrum_peaks[i] * rect.size.y
		canvas.draw_line(
			Vector2(x + gap * 0.5, peak_y),
			Vector2(x + bar_width - gap * 0.5, peak_y),
			peak_color, 2.0
		)

	# 顶部曲线
	var curve_points: PackedVector2Array = PackedVector2Array()
	for j in range(spectrum_bars):
		var curve_x: float = rect.position.x + (float(j) + 0.5) * bar_width
		var curve_y: float = rect.position.y + rect.size.y - spectrum_data[j] * rect.size.y
		curve_points.append(Vector2(curve_x, curve_y))

	if curve_points.size() > 1:
		canvas.draw_polyline(curve_points, draw_color, 1.5, true)

func _draw_lissajous(canvas: Control, rect: Rect2) -> void:
	var center: Vector2 = rect.position + rect.size * 0.5
	var base_scale: float = minf(rect.size.x, rect.size.y) * 0.45
	var sx: float = base_scale * lissajous_scale
	var sy: float = base_scale * lissajous_scale

	# 历史帧（拖尾）
	for h in range(lissajous_history.size() - 1, -1, -1):
		var history_points: Array = lissajous_history[h]
		var alpha: float = 1.0 - float(h) / float(lissajous_history_max)
		alpha *= 0.5

		var draw_points: PackedVector2Array = PackedVector2Array()
		for point in history_points:
			var p: Vector2 = point as Vector2
			draw_points.append(Vector2(
				center.x + p.x * sx,
				center.y - p.y * sy
			))

		if draw_points.size() > 1:
			var trail_color: Color = draw_color_dim
			trail_color.a = alpha * 0.3
			canvas.draw_polyline(draw_points, trail_color, 1.0, true)

	# 当前帧
	if lissajous_points.size() > 1:
		var draw_points: PackedVector2Array = PackedVector2Array()
		for point in lissajous_points:
			draw_points.append(Vector2(
				center.x + point.x * sx,
				center.y - point.y * sy
			))
		canvas.draw_polyline(draw_points, draw_color, 2.0, true)

	# 显示缩放倍率
	var font: Font = ThemeDB.fallback_font
	var scale_text: String = "SCALE: " + str(snapped(lissajous_scale, 0.1)) + "x"
	canvas.draw_string(font, Vector2(rect.position.x + 4, rect.position.y + rect.size.y - 8), scale_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, draw_color_dim)

func _draw_title(canvas: Control, full_size: Vector2, _draw_rect: Rect2) -> void:
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 13

	var title: String = "OSCILLOSCOPE"
	if not current_file_name.is_empty():
		title += "  —  " + current_file_name

	var mode_text: String = "[" + mode_names[current_mode] + "]"

	canvas.draw_string(font, Vector2(22, 22), title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, draw_color)
	canvas.draw_string(font, Vector2(full_size.x - 130, 22), mode_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, draw_color_dim)

func _draw_progress_bar(canvas: Control, rect: Rect2) -> void:
	var pos: float = audio_manager.get_media_playback_position()
	var total: float = audio_manager.get_media_length()
	if total <= 0.0:
		return

	var progress: float = pos / total

	# 进度条放在绘制区域底部上方 20px 处，避免被遮挡
	var bar_y: float = rect.position.y + rect.size.y - 20.0
	var bar_width: float = rect.size.x
	var bar_height: float = 3.0

	# 背景
	canvas.draw_rect(Rect2(rect.position.x, bar_y, bar_width, bar_height), grid_color)
	# 前景
	canvas.draw_rect(Rect2(rect.position.x, bar_y, bar_width * progress, bar_height), draw_color)

	# 时间文字
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 12
	var paused: bool = audio_manager.is_media_paused()
	var icon: String = "||" if paused else ">"
	var time_text: String = icon + " " + _format_time(pos) + " / " + _format_time(total)
	canvas.draw_string(font, Vector2(rect.position.x, bar_y - 5), time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, draw_color)

# ══════════════════════════════════════════
#  导航栏
# ══════════════════════════════════════════
func _update_nav() -> void:
	if nav_label == null:
		return

	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var parts: Array[String] = []

	parts.append("  [color=" + p + "]F1[/color][color=" + m + "]:频谱[/color]")
	parts.append("  [color=" + p + "]F2[/color][color=" + m + "]:李萨如[/color]")

	if is_playing_file:
		parts.append("  [color=" + p + "]Space[/color][color=" + m + "]:暂停[/color]")
		parts.append("  [color=" + p + "]←→[/color][color=" + m + "]:快退/快进[/color]")

	if current_mode == Mode.LISSAJOUS:
		parts.append("  [color=" + p + "]+/-[/color][color=" + m + "]:缩放(" + str(snapped(lissajous_scale, 0.1)) + "x)[/color]")

	parts.append("  [color=" + p + "]Q/Esc[/color][color=" + m + "]:退出[/color]")
	parts.append("   [color=" + m + "][" + mode_names[current_mode] + "][/color]")

	nav_label.text = ""
	nav_label.append_text("".join(parts))

# ══════════════════════════════════════════
#  工具函数
# ══════════════════════════════════════════
func _format_time(seconds: float) -> String:
	var total_seconds: int = int(seconds)
	@warning_ignore("integer_division")
	var mins: int = total_seconds / 60
	var secs: int = total_seconds % 60
	return "%02d:%02d" % [mins, secs]

# ══════════════════════════════════════════
#  内部类：示波器绘制画布
#  继承 Control，负责 _process 和 _draw
# ══════════════════════════════════════════
class _ScopeCanvas extends Control:
	var oscilloscope: Oscilloscope = null

	func _process(delta: float) -> void:
		if oscilloscope:
			oscilloscope.process_frame(delta)

	func _draw() -> void:
		if oscilloscope:
			oscilloscope.draw_scope(self)
