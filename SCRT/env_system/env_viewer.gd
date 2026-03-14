# ============================================================
# env_viewer.gd
# 环境监测站数据显示面板 —— CRT 风格覆盖层 UI
#
# 遵循 DocumentViewer / RadioReceiver 的 overlay 模式：
# 对齐到 OutputArea 区域，隐藏输入栏，
# 自定义 _draw() 绘制环境仪表盘。
# ============================================================
class_name EnvViewer
extends RefCounted

# ══════════════════════════════════════════
#  引用
# ══════════════════════════════════════════
var main = null
var env_monitor: EnvMonitor = null
var T = null

# ══════════════════════════════════════════
#  UI 节点
# ══════════════════════════════════════════
var overlay_panel: Panel = null
var _scroll: ScrollContainer = null  # ★ 滚动容器
var canvas: Control = null   # _EnvCanvas 内部类实例

# ══════════════════════════════════════════
#  显示状态
# ══════════════════════════════════════════
var is_active: bool = false
var current_page: int = 0       # 0=总览, 1=大气, 2=海洋, 3=地物, 4=成分, 5=事件
var page_names: Array = ["总览", "大气", "海洋", "地球物理", "大气成分", "事件/异常"]
const MAX_PAGES: int = 6

## 闪烁计时器（异常指示灯）
var _blink_timer: float = 0.0
var _blink_on: bool = true

# 缓存（打开前保存，关闭后恢复）
var _cached_input_visible: bool = true
var _cached_prompt_visible: bool = true
var _cached_output_text: String = ""

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(p_main, p_env_monitor: EnvMonitor, p_theme) -> void:
	main = p_main
	env_monitor = p_env_monitor
	T = p_theme

# ══════════════════════════════════════════
#  打开 / 关闭
# ══════════════════════════════════════════
func open() -> void:
	if is_active:
		return
	is_active = true
	current_page = 0
	_ensure_overlay()
	_align_overlay()
	# 缓存并隐藏终端 UI
	_cached_input_visible = main.input_field.visible
	_cached_prompt_visible = main.prompt_label.visible
	main.input_field.visible = false
	main.prompt_label.visible = false
	_cached_output_text = main.output_text.text
	main.output_text.text = ""
	# 更新路径栏提示
	if main.path_label:
		main.path_label.text = "ENV MONITOR | ←/→ 切换  TAB 下一页  Q/ESC 关闭"

	overlay_panel.visible = true
	# ★ 重置滚动位置
	if _scroll:
		_scroll.scroll_vertical = 0

func close() -> void:
	if not is_active:
		return
	is_active = false
	# 隐藏覆盖层
	if overlay_panel and is_instance_valid(overlay_panel):
		overlay_panel.visible = false
	# 恢复终端 UI
	main.output_text.clear()
	main.output_text.append_text(_cached_output_text)
	_cached_output_text = ""
	main.input_field.visible = _cached_input_visible
	main.prompt_label.visible = _cached_prompt_visible

	if main.has_method("_update_status_bar"):
		main._update_status_bar()
	main.input_field.grab_focus()

func toggle() -> void:
	if is_active:
		close()
	else:
		open()

# ══════════════════════════════════════════
#  输入处理（由 main._input 委托）
# ══════════════════════════════════════════
func handle_input(event: InputEvent) -> bool:
	if not is_active:
		return false
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE, KEY_Q:
				close()
				return true
			KEY_LEFT:
				current_page = (current_page - 1 + MAX_PAGES) % MAX_PAGES
				_reset_scroll()
				if canvas:
					canvas.queue_redraw()
				return true
			KEY_RIGHT:
				current_page = (current_page + 1) % MAX_PAGES
				_reset_scroll()
				if canvas:
					canvas.queue_redraw()
				return true
			KEY_TAB:
				current_page = (current_page + 1) % MAX_PAGES
				_reset_scroll()
				if canvas:
					canvas.queue_redraw()
				return true
	return false

## 重置滚动位置到顶部
func _reset_scroll() -> void:
	if _scroll:
		_scroll.scroll_vertical = 0

# ══════════════════════════════════════════
#  每帧更新
# ══════════════════════════════════════════
func process(delta: float) -> void:
	if not is_active or canvas == null:
		return
	_blink_timer += delta
	if _blink_timer >= 0.5:
		_blink_timer -= 0.5
		_blink_on = not _blink_on
		canvas.queue_redraw()

# ══════════════════════════════════════════
#  覆盖层创建（首次调用时创建，之后复用）
# ══════════════════════════════════════════
func _ensure_overlay() -> void:
	if overlay_panel != null and is_instance_valid(overlay_panel):
		return
	# 创建覆盖 Panel（挂载到 main 根节点）
	overlay_panel = Panel.new()
	overlay_panel.name = "EnvViewerOverlay"
	overlay_panel.visible = false
	# 统一深色背景（避免 Canvas 每帧重绘）
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0.88)
	overlay_panel.add_theme_stylebox_override("panel", bg_style)

	var root_control: Control = main as Control
	root_control.add_child(overlay_panel)
	# 放在 CRTEffect 之前，确保 CRT 着色器仍覆盖在上面
	var crt_node: Node = root_control.get_node_or_null("CRTEffect")
	if crt_node:
		root_control.move_child(overlay_panel, crt_node.get_index())
	overlay_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_panel.offset_left = 0
	overlay_panel.offset_top = 0
	overlay_panel.offset_right = 0
	overlay_panel.offset_bottom = 0

	# ★ 创建 ScrollContainer 以支持内容滚动
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# 滚动条样式：使用细滚动条
	var vbar: VScrollBar = _scroll.get_v_scroll_bar()
	if vbar:
		vbar.custom_minimum_size.x = 6
	overlay_panel.add_child(_scroll)

	# 创建绘制画布（放入 ScrollContainer，高度由内容决定）
	canvas = _EnvCanvas.new()
	canvas.viewer = self
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(canvas)

## 将覆盖层对齐到 OutputArea 的位置和大小（与 DocumentViewer 相同模式）
func _align_overlay() -> void:
	if overlay_panel == null or not is_instance_valid(overlay_panel):
		return
	var output_area: ScrollContainer = main.scroll_container
	var rect: Rect2 = output_area.get_global_rect()
	overlay_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	overlay_panel.position = rect.position
	overlay_panel.size = rect.size

# ══════════════════════════════════════════
#  内部画布类
# ══════════════════════════════════════════
class _EnvCanvas extends Control:
	var viewer: EnvViewer = null

	func _draw() -> void:
		if viewer == null or viewer.env_monitor == null:
			return
		var rect: Rect2 = get_rect()
		var w: float = rect.size.x
		# ★ 使用 ScrollContainer 的可见高度（用于底部提示定位）
		var visible_h: float = viewer._scroll.size.y if viewer._scroll else rect.size.y
		var em: EnvMonitor = viewer.env_monitor

		# 颜色（使用主题色，避免硬编码）
		var col_primary: Color = Color(viewer.T.primary) if viewer.T else Color.GREEN
		var col_dim: Color = col_primary * 0.4
		var col_bright: Color = col_primary * 1.2
		col_bright.a = 1.0
		var col_warn: Color = Color(viewer.T.warning) if viewer.T else Color(1.0, 0.8, 0.0)
		col_warn.a = 1.0
		var col_err: Color = Color(viewer.T.error) if viewer.T else Color(1.0, 0.2, 0.2)
		col_err.a = 1.0

		var font: Font = ThemeDB.fallback_font
		var font_size: int = 13
		var font_small: int = 11
		var line_h: float = 18.0

		var margin: float = 12.0
		var y: float = margin

		# ── 标题栏 ──
		var title: String = "ENVIRONMENTAL MONITORING SYSTEM — OB-7K"
		draw_string(font, Vector2(margin, y + font_size), title, HORIZONTAL_ALIGNMENT_LEFT, w - margin * 2, font_size, col_bright)
		y += line_h

		# 时间和天数
		var time_str: String = "%s  %s  天气: %s" % [em.get_day_display(), em.get_current_hour_display(), em.get_weather_name()]
		draw_string(font, Vector2(margin, y + font_size), time_str, HORIZONTAL_ALIGNMENT_LEFT, w - margin * 2, font_small, col_dim)
		y += line_h

		# 分隔线
		draw_line(Vector2(margin, y), Vector2(w - margin, y), col_dim, 1.0)
		y += 6

		# ── 页面标签 ──
		var tab_x: float = margin
		for i in range(viewer.page_names.size()):
			var label: String = viewer.page_names[i]
			var tab_col: Color = col_bright if i == viewer.current_page else col_dim
			if i == viewer.current_page:
				label = "[" + label + "]"
			draw_string(font, Vector2(tab_x, y + font_small), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_small, tab_col)
			tab_x += font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_small).x + 12
		y += line_h + 4

		# 分隔线
		draw_line(Vector2(margin, y), Vector2(w - margin, y), col_primary * 0.3, 1.0)
		y += 8

		# ── 页面内容 ──
		match viewer.current_page:
			0:
				y = _draw_overview(em, font, font_size, font_small, line_h, margin, y, w, visible_h, col_primary, col_dim, col_bright, col_warn, col_err)
			1:
				y = _draw_category(em, "atmosphere", font, font_size, font_small, line_h, margin, y, w, col_primary, col_dim, col_warn, col_err)
			2:
				y = _draw_category(em, "ocean", font, font_size, font_small, line_h, margin, y, w, col_primary, col_dim, col_warn, col_err)
			3:
				y = _draw_category(em, "geophysics", font, font_size, font_small, line_h, margin, y, w, col_primary, col_dim, col_warn, col_err)
			4:
				y = _draw_category(em, "composition", font, font_size, font_small, line_h, margin, y, w, col_primary, col_dim, col_warn, col_err)
			5:
				y = _draw_events(em, font, font_size, font_small, line_h, margin, y, w, col_primary, col_dim, col_warn, col_err)

		# ── 底部操作提示 ──
		y += 8
		var help_text: String = "←/→ 切换页面  |  TAB 下一页  |  滚轮滚动  |  Q/ESC 关闭"
		draw_string(font, Vector2(margin, y + font_small), help_text, HORIZONTAL_ALIGNMENT_LEFT, w - margin * 2, font_small, col_dim)
		y += line_h + margin

		# ★ 更新画布最小高度以驱动 ScrollContainer 滚动条
		custom_minimum_size.y = maxf(y, visible_h)

	# ── 总览页 ──
	func _draw_overview(em: EnvMonitor, font: Font, fs: int, fss: int, lh: float, mx: float, y: float, w: float, _h: float,
			col_p: Color, col_d: Color, col_b: Color, col_w: Color, col_e: Color) -> float:
		# 关键参数网格
		var col_width: float = (w - mx * 3) / 2.0
		var items: Array = [
			["气温", "air_temp", "°C"],
			["湿度", "humidity", "%"],
			["气压", "pressure", "hPa"],
			["风速", "wind_speed", "m/s"],
			["海温", "sea_temp", "°C"],
			["潮位", "tide_level", "m"],
			["磁场", "mag_field", "nT"],
			["辐射", "radiation", "μSv/h"],
			["风向", "wind_dir", "°"],
			["浪高", "wave_height", "m"],
			["能见度", "visibility", "km"],
			["光照", "light_level", "lux"],
		]

		draw_string(font, Vector2(mx, y + fs), "关键参数概览", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col_b)
		y += lh + 4

		for i in range(items.size()):
			var col_idx: int = i % 2
			var row_idx: int = i / 2
			var x: float = mx + col_idx * (col_width + mx)
			var item_y: float = y + row_idx * lh

			var label: String = items[i][0]
			var sid: String = items[i][1]
			var unit: String = items[i][2]
			var val: float = em.get_reading(sid)
			var status: String = em.sensor_status.get(sid, "online")

			var val_str: String
			if is_nan(val) or status == "offline":
				val_str = "---"
			elif absf(val) >= 1000:
				val_str = "%d" % roundi(val)
			else:
				val_str = "%.1f" % val

			var col: Color = col_p
			if status == "offline":
				col = col_e if viewer._blink_on else col_d
			elif status == "degraded":
				col = col_w

			var trend: String = em.get_sensor_trend(sid)
			var trend_sym: String = ""
			match trend:
				"rising": trend_sym = "↑"
				"falling": trend_sym = "↓"
				"stable": trend_sym = "→"

			draw_string(font, Vector2(x, item_y + fss), "%-6s" % label, HORIZONTAL_ALIGNMENT_LEFT, -1, fss, col_d)
			draw_string(font, Vector2(x + 70, item_y + fss), "%s %s %s" % [val_str, unit, trend_sym], HORIZONTAL_ALIGNMENT_LEFT, -1, fss, col)

		y += (items.size() / 2 + 1) * lh + 8

		# 天气状态
		draw_line(Vector2(mx, y), Vector2(w - mx, y), col_d * 0.5, 1.0)
		y += 6
		draw_string(font, Vector2(mx, y + fss), "天气: %s  |  风向: %s  |  云量: %d/8" % [
			em.get_weather_name(), em.get_wind_direction_name(), roundi(em.get_reading("cloud_cover"))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fss, col_p)
		y += lh

		# 活跃事件
		var events: Dictionary = em.get_active_events()
		if events.size() > 0:
			y += 4
			draw_string(font, Vector2(mx, y + fss), "活跃事件:", HORIZONTAL_ALIGNMENT_LEFT, -1, fss, col_w)
			y += lh
			for eid in events.keys():
				var evt: Dictionary = events[eid]
				var evt_col: Color = col_e if evt.get("scp_related", false) else col_w
				if evt.get("scp_related", false) and not viewer._blink_on:
					evt_col = col_d
				draw_string(font, Vector2(mx + 8, y + fss), "• %s (至第%d天)" % [str(evt.get("name", eid)), int(evt.get("end_day", 0))],
					HORIZONTAL_ALIGNMENT_LEFT, -1, fss, evt_col)
				y += lh

		# 待处理异常
		var anomalies: Array[Dictionary] = em.get_pending_anomalies()
		if anomalies.size() > 0:
			y += 4
			var anom_col: Color = col_e if viewer._blink_on else col_d
			draw_string(font, Vector2(mx, y + fss), "! 待确认异常: %d 项" % anomalies.size(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, fss, anom_col)
			y += lh

		return y

	# ── 分类详情页 ──
	func _draw_category(em: EnvMonitor, category: String, font: Font, fs: int, fss: int, lh: float, mx: float, y: float, w: float,
			col_p: Color, col_d: Color, col_w: Color, col_e: Color) -> float:
		var sensor_ids: Array = em.get_sensors_by_category(category)
		var cat_names: Dictionary = {
			"atmosphere": "大气参数",
			"ocean": "海洋参数",
			"geophysics": "地球物理参数",
			"composition": "大气成分",
		}
		draw_string(font, Vector2(mx, y + fs), str(cat_names.get(category, category)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col_p)
		y += lh + 6

		# 表头
		draw_string(font, Vector2(mx, y + fss), "%-14s %-12s %-8s %-8s %s" % ["参数", "读数", "单位", "状态", "趋势"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fss, col_d)
		y += lh
		draw_line(Vector2(mx, y), Vector2(w - mx, y), col_d * 0.3, 1.0)
		y += 4

		for sid in sensor_ids:
			var cfg: Dictionary = em.get_sensor_config(sid)
			var val: float = em.get_reading(sid)
			var status: String = em.sensor_status.get(sid, "online")
			var trend: String = em.get_sensor_trend(sid)
			var name: String = str(cfg.get("name", sid))
			var unit: String = str(cfg.get("unit", ""))

			var val_str: String
			if is_nan(val) or status == "offline":
				val_str = "---"
			elif absf(val) >= 1000:
				val_str = "%d" % roundi(val)
			else:
				val_str = "%.1f" % val

			var status_str: String
			var row_col: Color
			match status:
				"online":
					status_str = "在线"
					row_col = col_p
				"degraded":
					status_str = "退化"
					row_col = col_w
				"offline":
					status_str = "离线"
					row_col = col_e if viewer._blink_on else col_d
				_:
					status_str = "未知"
					row_col = col_d

			var trend_str: String
			match trend:
				"rising": trend_str = "↑ 上升"
				"falling": trend_str = "↓ 下降"
				"stable": trend_str = "→ 稳定"
				_: trend_str = "? 未知"

			draw_string(font, Vector2(mx, y + fss), "%-14s" % name, HORIZONTAL_ALIGNMENT_LEFT, -1, fss, col_d)
			draw_string(font, Vector2(mx + 110, y + fss), "%-12s" % val_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fss, row_col)
			draw_string(font, Vector2(mx + 210, y + fss), "%-8s" % unit, HORIZONTAL_ALIGNMENT_LEFT, -1, fss, col_d)
			draw_string(font, Vector2(mx + 280, y + fss), "%-8s" % status_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fss, row_col)
			draw_string(font, Vector2(mx + 350, y + fss), trend_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fss, col_d)
			y += lh

		# 简易读数历史 mini-graph (最近几个读数用点阵显示)
		y += 8
		draw_string(font, Vector2(mx, y + fss), "最近读数趋势:", HORIZONTAL_ALIGNMENT_LEFT, -1, fss, col_d)
		y += lh

		for sid in sensor_ids:
			var history: Array = em.reading_history.get(sid, [])
			if history.size() < 2:
				continue
			var cfg: Dictionary = em.get_sensor_config(sid)
			var name: String = str(cfg.get("name", sid))
			draw_string(font, Vector2(mx, y + fss), name + ":", HORIZONTAL_ALIGNMENT_LEFT, -1, fss, col_d)
			# 绘制简易折线 (最近 20 个点)
			var graph_x: float = mx + 90
			var graph_w: float = 300.0
			var graph_h: float = 14.0
			var points: Array = history.slice(maxi(0, history.size() - 20), history.size())
			if points.size() >= 2:
				var min_v: float = INF
				var max_v: float = -INF
				for p in points:
					var v: float = float(p.get("value", 0))
					if not is_nan(v):
						min_v = minf(min_v, v)
						max_v = maxf(max_v, v)
				if max_v - min_v < 0.001:
					max_v = min_v + 1.0
				var prev_px: Vector2 = Vector2.ZERO
				for j in range(points.size()):
					var v: float = float(points[j].get("value", 0))
					if is_nan(v):
						continue
					var px: Vector2 = Vector2(
						graph_x + float(j) / float(points.size() - 1) * graph_w,
						y + graph_h - (v - min_v) / (max_v - min_v) * graph_h
					)
					if j > 0 and prev_px != Vector2.ZERO:
						draw_line(prev_px, px, col_p * 0.6, 1.0)
					draw_rect(Rect2(px - Vector2(1, 1), Vector2(2, 2)), col_p)
					prev_px = px
			y += lh
		return y

	# ── 事件/异常页 ──
	func _draw_events(em: EnvMonitor, font: Font, fs: int, fss: int, lh: float, mx: float, y: float, w: float,
			col_p: Color, col_d: Color, col_w: Color, col_e: Color) -> float:
		# 活跃事件
		draw_string(font, Vector2(mx, y + fs), "活跃事件", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col_p)
		y += lh + 4
		var events: Dictionary = em.get_active_events()
		if events.is_empty():
			draw_string(font, Vector2(mx + 8, y + fss), "无活跃事件", HORIZONTAL_ALIGNMENT_LEFT, -1, fss, col_d)
			y += lh
		else:
			for eid in events.keys():
				var evt: Dictionary = events[eid]
				var evt_col: Color = col_e if evt.get("scp_related", false) else col_w
				draw_string(font, Vector2(mx + 8, y + fss),
					"• %s  (第%d天 - 第%d天)" % [str(evt.get("name", eid)), int(evt.get("start_day", 0)), int(evt.get("end_day", 0))],
					HORIZONTAL_ALIGNMENT_LEFT, -1, fss, evt_col)
				y += lh

		y += 8
		draw_line(Vector2(mx, y), Vector2(w - mx, y), col_d * 0.3, 1.0)
		y += 8

		# 待确认异常
		draw_string(font, Vector2(mx, y + fs), "待确认异常", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col_w)
		y += lh + 4
		var pending: Array[Dictionary] = em.get_pending_anomalies()
		if pending.is_empty():
			draw_string(font, Vector2(mx + 8, y + fss), "无待确认异常", HORIZONTAL_ALIGNMENT_LEFT, -1, fss, col_d)
			y += lh
		else:
			for a in pending:
				var sev_col: Color
				match str(a.get("severity", "info")):
					"critical": sev_col = col_e
					"warning", "anomalous": sev_col = col_w
					_: sev_col = col_d
				draw_string(font, Vector2(mx + 8, y + fss),
					"[%s] %s" % [str(a.get("severity", "")).to_upper(), str(a.get("name", ""))],
					HORIZONTAL_ALIGNMENT_LEFT, -1, fss, sev_col)
				y += lh
				draw_string(font, Vector2(mx + 16, y + fss),
					str(a.get("report", "")),
					HORIZONTAL_ALIGNMENT_LEFT, w - mx * 2 - 16, fss, col_d)
				y += lh

		y += 8
		draw_line(Vector2(mx, y), Vector2(w - mx, y), col_d * 0.3, 1.0)
		y += 8

		# 已确认异常历史
		draw_string(font, Vector2(mx, y + fs), "已记录异常 (历史)", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col_p)
		y += lh + 4
		var detected: Array[Dictionary] = em.get_detected_anomalies()
		if detected.is_empty():
			draw_string(font, Vector2(mx + 8, y + fss), "无历史异常记录", HORIZONTAL_ALIGNMENT_LEFT, -1, fss, col_d)
			y += lh
		else:
			for i in range(detected.size()):
				var a: Dictionary = detected[i]
				draw_string(font, Vector2(mx + 8, y + fss),
					"Day%d %s: %s" % [int(a.get("day", 0)), str(a.get("name", "")), str(a.get("report", "")).left(60)],
					HORIZONTAL_ALIGNMENT_LEFT, w - mx * 2 - 8, fss, col_d)
				y += lh

		return y
