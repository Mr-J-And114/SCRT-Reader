class_name EnvMapCanvas
extends Control
## 观测盘按 1920×950 逻辑尺寸绘制，整体缩放；底图等待用户绘制 SVG 矢量地形。
var viewer = null
var hits: Array[Dictionary] = []
var logical_scale: float = 1.0
var logical_offset: Vector2 = Vector2.ZERO
var _texture: Texture2D = null
var _texture_path: String = ""
var _font: Font = null
var _green: Color = Color(0.5, 1.0, 0.65)
var _dim: Color = Color(0.16, 0.36, 0.24)
var _amber: Color = Color(1.0, 0.75, 0.3)
var _blue: Color = Color(0.35, 0.8, 1.0)

func _draw() -> void:
	if viewer == null:
		return
	logical_scale = minf(size.x / 1920.0, size.y / 950.0)
	logical_offset = (size - Vector2(1920, 950) * logical_scale) * 0.5
	draw_set_transform(logical_offset, 0, Vector2.ONE * logical_scale)
	_font = viewer.main.output_text.get_theme_font("normal_font")
	_green = Color(viewer.T.primary)
	_dim = _green.darkened(0.65)
	_amber = Color(viewer.T.warning)
	hits.clear()
	_text(Vector2(24, 34), "ENVIRONMENT / 环境监视", 26)
	_text(Vector2(780, 34), viewer.env_monitor.get_day_display() + "  " + viewer.env_monitor.get_current_hour_display(), 20, _dim)
	var page_title: String = "操作说明" if viewer.current_page == 10 else ("日报档案" if viewer.current_page == 8 else "地图 / " + ("海域" if viewer.current_page == 1 else "岛屿与近海"))
	_text(Vector2(1420, 34), page_title, 21)
	if viewer.current_page == 10:
		_draw_manual()
		return
	if viewer.current_page == 8:
		_draw_history()
		return
	_draw_map()
	_draw_selection()
	_draw_footer()

func _text(pos: Vector2, value: String, font_size: int = 21, color: Color = Color(-1, -1, -1), width: float = -1) -> void:
	draw_string(_font, pos, value, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, _green if color.r < 0 else color)

func _box(rect: Rect2, title: String) -> void:
	draw_rect(rect, Color(0.015, 0.035, 0.024, 0.94))
	draw_rect(rect, _dim, false, 1.5)
	_text(rect.position + Vector2(14, 31), "┤ " + title + " ├", 23)
	draw_line(rect.position + Vector2(12, 46), Vector2(rect.end.x - 12, rect.position.y + 46), _dim)

func action_at(local_pos: Vector2) -> String:
	if logical_scale <= 0 or viewer.current_page not in [0, 1]:
		return ""
	var pos: Vector2 = (local_pos - logical_offset) / logical_scale
	for hit in hits:
		if (hit["rect"] as Rect2).has_point(pos):
			return str(hit["action"])
	return "deselect" if pos.distance_to(Vector2(958, 463)) <= 382 else ""

func _selection_brackets(pos: Vector2) -> void:
	# 本站与无目标不显示选中框。
	_text(pos + Vector2(-27, 8), "[", 26)
	_text(pos + Vector2(20, 8), "]", 26)

func _draw_manual() -> void:
	_box(Rect2(440, 70, 1460, 805), "ENV 操作说明")
	var lines: Array[String] = [
		"值班流程：scan 采集 → 查看简报 → 可选核对疑点 → report 提交日报。",
		"不确定的变化可如实提交；深入核对可选，重复提交不重复计分。",
		"地图：Tab 切换近海／远海；map nearshore / map sea 也可切换。",
		"选择：点击图标或 select <设施ID/疑点编号>；[ ] 表示选中目标。",
		"点击地图空白处取消选择；本站与无目标不显示选择框。",
		"status 简报 / issues 疑点编号清单 / next 下一疑点。",
		"retest 复测 / mark 关注开关 / calibrate 校准已复测的设备疑点。",
		"details 实时总览；details atmosphere / ocean / geophysics / composition / events。",
		"details evidence 查看采集快照、来源、疑点及复测证据。",
		"history 日报档案；history older / history newer 翻页。",
		"manual（或 help / guide）打开本页；map 返回地图；clear 清空反馈；exit 返回桌面。",
		"指令在底部通用输入框输入；上下键调出历史命令。",
		"图例：● 本站 / □ 固定观测设备 / ○ 声纳 / 黄色设备：存在待核对项目。",
		"灰色：设备未接入；蓝色：船只／飞行器目标；红色带叉：历史水雷标记。",
		"设施位置为示意，固定传感器读数不代表独立空间实测。",
		"海域目标按来源接入；debug 航迹为预览。无人机模块本版尚未启用。"
	]
	var y: float = 155
	for line in lines:
		_text(Vector2(465, y), line, 21, _green, 1410)
		y += 42

func _draw_map() -> void:
	var obs: EnvObservation = viewer.main.env_observation
	var center := Vector2(958, 463)
	var radius: float = 382
	var sea: bool = viewer.current_page == 1
	draw_circle(center, radius, Color(0.015, 0.045, 0.027))
	# 地形底图先绘制；网格、扫描线和动态标记始终覆盖在底图上。
	# SVG 由 Godot 导入为 Texture2D，源文件保留矢量编辑能力。
	if not sea:
		_load_texture(str(obs.config.get("map_texture", "")))
		var map_rect := Rect2(center - Vector2.ONE * 205, Vector2.ONE * 410)
		if _texture:
			draw_texture_rect(_texture, map_rect, false, Color(0.7, 1.0, 0.8))
		else:
			draw_rect(map_rect, Color(0.05, 0.11, 0.065, 0.65))
			draw_rect(map_rect, _dim, false, 1.5)
			_text(center + Vector2(-145, 95), "地图占位 / 等待 SVG", 22, _dim)
	# 圆盘中的网格按比例尺生成，线段严格裁剪到圆边界。
	var range_units: float = float(obs.config.get("sea_radius_nm", 30) if sea else obs.config.get("nearshore_radius_m", 600))
	var grid_units: float = float(obs.config.get("sea_grid_nm", 5) if sea else obs.config.get("nearshore_grid_m", 50))
	var step: float = radius * grid_units / maxf(1.0, range_units)
	for i in range(-int(radius / step), int(radius / step) + 1):
		var offset: float = float(i) * step
		var span: float = sqrt(maxf(0.0, radius * radius - offset * offset))
		draw_line(center + Vector2(offset, -span), center + Vector2(offset, span), _dim.darkened(0.35))
		draw_line(center + Vector2(-span, offset), center + Vector2(span, offset), _dim.darkened(0.35))
	for ratio in [0.3333, 0.6667, 1.0]:
		draw_arc(center, radius * ratio, 0, TAU, 100, _dim, 1.3, true)
	# 扫描线只是观测刷新提示，不会虚构空间探测能力。
	var angle: float = viewer._sweep_angle
	draw_line(center, center + Vector2(cos(angle), sin(angle)) * radius, _green.darkened(0.4), 1.5)
	for entry in obs.config.get("regions", []):
		if str(entry.get("view", "nearshore")) != ("sea" if sea else "nearshore"):
			continue
		var coords: Array = entry.get("position", [0, 0])
		var pos: Vector2 = center + Vector2(float(coords[0]), float(coords[1])) * radius
		var sensors: Array = entry.get("sensors", [])
		var connected: bool = not sensors.is_empty()
		var col: Color = _green if connected else _dim
		var has_issue: bool = false
		for issue in obs.issues():
			if issue.get("region", "") == entry.get("id", ""):
				has_issue = true
		if has_issue:
			col = _amber
		if entry.get("id", "") == "station":
			draw_circle(pos, 7, col)
			draw_arc(pos, 12, 0, TAU, 30, col, 1.2, true)
		elif entry.get("kind", "") == "sonar":
			draw_arc(pos, 10, 0, TAU, 30, col, 1.5, true)
		else:
			draw_rect(Rect2(pos - Vector2(8, 8), Vector2(16, 16)), col, false, 1.5)
		if entry.get("id", "") == viewer.selected_region and viewer.selected_region != "station":
			_selection_brackets(pos)
		hits.append({"rect": Rect2(pos - Vector2(23, 23), Vector2(46, 46)), "action": "region:" + str(entry.get("id", ""))})
		_text(pos + Vector2(15, -10), str(entry.get("name", "")), 18, col)
	hits.append({"rect": Rect2(center - Vector2(18, 18), Vector2(36, 36)), "action": "region:station"})
	draw_circle(center, 5, _green)
	_text(center + Vector2(13, 30), "本站", 19)
	_text(Vector2(center.x - 10, 68), "N", 21)
	_text(Vector2(center.x - 10, 873), "S", 21)
	_text(Vector2(550, 464), "W", 21)
	_text(Vector2(1355, 464), "E", 21)
	_text(Vector2(530, 865), "半径 %.0f %s / 每格 %.0f %s" % [range_units, "NM" if sea else "m", grid_units, "NM" if sea else "m"], 20)
	if sea:
		for contact in obs.contacts():
			var coords: Array = contact.get("position", [0, 0])
			var offset := Vector2(float(coords[0]), float(coords[1]))
			if offset.length() > 0.9:
				continue
			var pos: Vector2 = center + offset * radius
			var contact_id: String = str(contact.get("id", ""))
			hits.append({"rect": Rect2(pos - Vector2(23, 23), Vector2(46, 46)), "action": "contact:" + contact_id})
			if viewer.selected_region == "contact:" + contact_id:
				_selection_brackets(pos)
			var mine: bool = contact.get("kind", "") == "mine"
			var col: Color = Color(viewer.T.error) if mine else _blue
			draw_arc(pos, 8, 0, TAU, 24, col, 1.3, true)
			if mine:
				draw_line(pos - Vector2(6, 6), pos + Vector2(6, 6), col, 1.4)
				draw_line(pos + Vector2(-6, 6), pos + Vector2(6, -6), col, 1.4)
			var last: Vector2 = Vector2.INF
			for point in contact.get("track", []):
				var next: Vector2 = center + Vector2(float(point[0]), float(point[1])) * radius
				if next.distance_to(center) > radius:
					continue
				if last != Vector2.INF:
					draw_line(last, next, col, 1.5, true)
				last = next
			_text(pos + Vector2(14, 18), str(contact.get("id", "")), 18, col)
		_text(Vector2(690, 817), "调试目标示意" if not obs.debug_scenario.is_empty() else "远海接入接口预留 / 暂无实测航迹", 18, _dim)

func _load_texture(path: String) -> void:
	if path == _texture_path:
		return
	_texture_path = path
	_texture = null
	if not path.is_empty() and ResourceLoader.exists(path):
		_texture = load(path) as Texture2D

func _draw_selection() -> void:
	var obs: EnvObservation = viewer.main.env_observation
	_box(Rect2(1410, 70, 490, 320), "环境简报")
	_text(Vector2(1430, 150), "天气  " + viewer.env_monitor.get_weather_name(), 21)
	_text(Vector2(1430, 198), "采集  " + ("完成 / " + str(obs.state().get("hour", "")) if obs.is_collected() else "尚未采集"), 21)
	_text(Vector2(1430, 246), "日报  " + ("已归档" if obs.is_submitted() else "未提交"), 21)
	_text(Vector2(1430, 294), "疑点  %d 项 / 可选核对" % obs.issues().size(), 21, _amber)
	_text(Vector2(1430, 350), "详细读数：details evidence", 18, _dim)

func _draw_footer() -> void:
	var obs: EnvObservation = viewer.main.env_observation
	var status: String = "Tab 近海／远海 · manual 操作说明 · details 详情 · exit 返回桌面"
	if obs.is_collecting():
		status = Typewriter.format_progress_bar(1.0 - obs.capture_remaining / obs.capture_duration, "采集中")
	_text(Vector2(440, 915), status, 19, _green, 1440)
	if not obs.debug_scenario.is_empty():
		_text(Vector2(1410, 895), "DEBUG / 隔离预览", 16, _amber)

func _draw_history() -> void:
	_box(Rect2(440, 70, 1460, 805), "日报档案 / 最近 30 份")
	var history: Array = viewer.main.env_task_mgr.observation_history
	if history.is_empty():
		_text(Vector2(465, 190), "暂无归档日报。采集后输入 report 提交。", 24)
	else:
		viewer.history_index = clampi(viewer.history_index, 0, history.size() - 1)
		var report: Dictionary = history[history.size() - 1 - viewer.history_index]
		_text(Vector2(465, 175), "第 %d 天 / 采集 %s / 提交 %s / %s" % [int(report.get("day", 0)), report.get("hour", ""), report.get("submitted_hour", ""), report.get("weather", "")], 25)
		_text(Vector2(465, 225), str(report.get("score_note", "旧版记录")), 22, _amber)
		var y: float = 285
		for sid in ["air_temp", "visibility", "pressure", "wave_height", "mag_field"]:
			var sensor: Dictionary = viewer.env_monitor.get_sensor_config(sid)
			_text(Vector2(465, y), "%s  %s %s" % [sensor.get("name", sid), EnvObservation.format_value(report.get("readings", {}).get(sid)), sensor.get("unit", "")], 22)
			y += 42
		for issue in report.get("issues", []):
			if y > 750:
				break
			_text(Vector2(465, y), "%s / %s / %s" % [issue.get("name", ""), "关注" if issue.get("marked", false) else "未确认记录", issue.get("retest_note", "未复测")], 20, _amber, 1400)
			y += 40
	_text(Vector2(465, 845), "history older / history newer 翻页；map 返回地图", 19, _dim)
