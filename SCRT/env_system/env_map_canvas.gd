class_name EnvMapCanvas
extends Control
## 观测盘按 1920×950 逻辑尺寸绘制；CAD 底图以本站为原点，北向上。
var viewer = null
var hits: Array[Dictionary] = []
var logical_scale: float = 1.0
var logical_offset: Vector2 = Vector2.ZERO
var _texture: Texture2D = null
var _texture_path: String = ""
var _textures: Dictionary = {}
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
	_dim = Color(viewer.T.muted)
	_amber = Color(viewer.T.warning)
	hits.clear()
	_text(Vector2(24, 34), "ENVIRONMENT / 环境监视", 26)
	var day_text: String = viewer.env_monitor.get_day_display() + "  " + viewer.env_monitor.get_current_hour_display()
	_text(Vector2(780, 34), day_text, 20, _dim)
	var obs: EnvObservation = viewer.main.env_observation
	if viewer.current_page == 1 and obs.traffic_active:
		var status_x: float = 780 + _font.get_string_size(day_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 25
		_text(Vector2(status_x, 34), "测试目标 %.0f× / %s / %.0fs" % [obs.traffic_scale, "暂停" if obs.traffic_paused else "运行", obs.traffic_elapsed], 16, _amber, 1400 - status_x)
	var page_title: String = "操作说明" if viewer.current_page == 10 else ("日报档案" if viewer.current_page == 8 else "地图 / " + ("海域" if viewer.current_page == 1 else "岛屿与近海"))
	if viewer.current_page in [2, 3, 4, 5, 6, 7, 9]: page_title = "详情 / 实时数据与采集证据"
	_text(Vector2(1420, 34), page_title, 21)
	if viewer.current_page == 10:
		_draw_manual()
		return
	if viewer.current_page == 8:
		_draw_history()
		return
	if viewer.current_page in [2, 3, 4, 5, 6, 7, 9]:
		_draw_details()
		return
	_draw_map()
	_draw_selection()
	_draw_footer()

func _text(pos: Vector2, value: String, font_size: int = 21, color: Color = Color(-1, -1, -1), width: float = -1) -> void:
	draw_string(_font, pos, value, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, _green if color.r < 0 else color)

func _box(rect: Rect2, title: String) -> void:
	draw_rect(rect, Color.TRANSPARENT)
	draw_rect(rect, viewer.T.border, false, 1.0)
	_text(rect.position + Vector2(14, 31), UIManager.terminal_section(title), 23)
	draw_line(rect.position + Vector2(12, 46), Vector2(rect.end.x - 12, rect.position.y + 46), viewer.T.border)

func action_at(local_pos: Vector2) -> String:
	if logical_scale <= 0:
		return ""
	var pos: Vector2 = (local_pos - logical_offset) / logical_scale
	for hit in hits:
		if (hit["rect"] as Rect2).has_point(pos):
			return str(hit["action"])
	return "deselect" if viewer.current_page in [0, 1] and pos.distance_to(Vector2(958, 463)) <= 382 else ""

func _selection_brackets(pos: Vector2, color: Color = Color(-1, -1, -1)) -> void:
	# 本站与无目标不显示选中框。
	_text(pos + Vector2(-27, 8), "[", 26, color)
	_text(pos + Vector2(20, 8), "]", 26, color)

func _draw_manual() -> void:
	for i in range(3):
		_button(Rect2(440 + i * 490, 70, 470, 48), ["维护速查", "全部指令", "地图图例"][i], "manual:" + str(i), viewer.manual_section == i)
	if viewer.manual_section == 0:
		_box(Rect2(440, 140, 1460, 150), "日常值班 / 只需采集和提交")
		_text(Vector2(465, 223), "scan → 观测点维护 → details 点击调查 → report", 28)
		_text(Vector2(465, 266), "无法确认时点击“保留疑点”再提交；维护和复核不单独加分。", 21, _dim)
		_box(Rect2(440, 310, 720, 295), "离线／退化／故障 → 维修")
		_text(Vector2(465, 390), "点击观测点，查看当前设备状态", 23)
		_text(Vector2(465, 436), "选择观测点 → 点击常规维护", 28, _amber)
		_text(Vector2(465, 482), "无需逐台输入维修／校准／复测命令。", 22)
		_text(Vector2(465, 524), "details 分类页点击设备查看具体问题", 21)
		_text(Vector2(465, 568), "无需退出 ENV；维修后立即刷新并保存。", 21, _dim)
		_box(Rect2(1180, 310, 720, 295), "在线但偏移 → 校准")
		_text(Vector2(1205, 390), "details 项目页统一展示同期比对", 23)
		_text(Vector2(1205, 436), "修复、校准并自动验证", 23, _amber)
		_text(Vector2(1205, 482), "特殊故障需手动排查；原始证据保留。", 22)
		_text(Vector2(1205, 524), "按钮统一处理普通故障与偏移。", 21)
		_text(Vector2(1205, 568), "环境变化不会被校准消除。", 21, _dim)
		_box(Rect2(440, 625, 1460, 230), "验证与归档 / 不覆盖原始证据")
		_text(Vector2(465, 704), "常规维护自动验证；details 的“复核观测”集中展示观测变化。", 23)
		_text(Vector2(465, 751), "仍不正常：点击保留疑点 → report 如实提交，不必消除所有异常。", 23)
		_text(Vector2(465, 802), "日报提交后锁定证据；设备仍可维修，下次采集记录恢复情况。", 21, _dim)
	elif viewer.manual_section == 1:
		_box(Rect2(440, 140, 1460, 715), "全部指令 / 在底部输入，可加 env 前缀")
		var columns: Array = [
			["日常操作", "scan / collect  采集当天快照", "点击观测点 → 常规维护", "details  今日可疑项目", "点击项目 → 查看问题与依据", "复核观测 → 自动展示比对", "维护并验证 → 单台普通设备", "保留疑点 → 如实记录未确认", "report / submit  提交日报", "maintain  维护地图选中点"],
			["页面与导航", "map nearshore / sea  地图", "details <分类> 实时设备／证据", "overview atmosphere ocean geophysics", "composition events evidence", "details next / prev  翻页", "history older / newer / next / prev", "manual  操作说明与图例", "clear  清反馈；exit  返回桌面", "详情：空输入时方向键／Tab选择，Enter确认"]
		]
		for column in range(2):
			for row in range(columns[column].size()):
				_text(Vector2(465 + column * 735, 222 + row * 45), str(columns[column][row]), 20 if row > 0 else 25, _green if row > 0 else _amber, 690)
	else:
		_box(Rect2(440, 140, 1460, 715), "地图图例与观测边界")
		var lines: Array[String] = [
			"● 固定设备 / ■ 船舶 / ▲ 飞行器 / ▼ 潜艇（声纳回报）",
			"绿色：已知民用；黄色：军用；红色：未知；固定点黄色：待核对。",
			"鼠标靠近显示名称；点击选择，[ ] 标识当前目标；点击空白取消选择。",
			"本站和无目标不显示选中框；点击后右侧展示可用简要信息。",
			"虚线：事先已知的航线；实线：电脑连接历次扫描位置形成的航迹。",
			"移动目标被扫到后显示并渐隐；未知航线的目标仅靠扫描发现。",
			"近海半径 900 m / 每格 50 m；远海半径 30 NM / 每格 5 NM。",
			"地形已配准；固定设备点位为示意，不代表独立空间实测。",
			"浮标、声纳未接入时不提供实测数据；无人机当前尚未开放。",
			"map 返回近海；map sea 返回远海；help 返回维护速查。"
		]
		for i in range(lines.size()):
			_text(Vector2(465, 225 + i * 58), lines[i], 22, _green, 1410)

func _draw_map() -> void:
	var obs: EnvObservation = viewer.main.env_observation
	var center := Vector2(958, 463)
	var radius: float = 382
	var sea: bool = viewer.current_page == 1
	draw_circle(center, radius, Color(0.015, 0.045, 0.027))
	# 地形底图先绘制；网格、扫描线和动态标记始终覆盖在底图上。
	# SVG 由 Godot 导入为 Texture2D，源文件保留矢量编辑能力。
	var map_config: Dictionary = obs.config.get("maps", {}).get("sea" if sea else "nearshore", {})
	var range_m: float = float(obs.config.get("sea_radius_nm", 30)) * 1852.0 if sea else float(obs.config.get("nearshore_radius_m", 900))
	_draw_terrain(center, radius, range_m, map_config, str(obs.config.get("map_texture", "")) if not sea else "")
	# 圆盘中的网格按比例尺生成，线段严格裁剪到圆边界。
	var range_units: float = float(obs.config.get("sea_radius_nm", 30) if sea else obs.config.get("nearshore_radius_m", 900))
	var grid_units: float = float(obs.config.get("sea_grid_nm", 5) if sea else obs.config.get("nearshore_grid_m", 50))
	var step: float = radius * grid_units / maxf(1.0, range_units)
	for i in range(-int(radius / step), int(radius / step) + 1):
		var offset: float = float(i) * step
		var span: float = sqrt(maxf(0.0, radius * radius - offset * offset))
		draw_line(center + Vector2(offset, -span), center + Vector2(offset, span), Color(viewer.T.dim, 0.4))
		draw_line(center + Vector2(-span, offset), center + Vector2(span, offset), Color(viewer.T.dim, 0.4))
	for ratio in [0.3333, 0.6667, 1.0]:
		draw_arc(center, radius * ratio, 0, TAU, 100, viewer.T.dim, 1.3, true)
	_draw_map_labels(center, radius, range_m, map_config)
	# 扫描线只是观测刷新提示，不会虚构空间探测能力。
	var angle: float = viewer._sweep_angle
	var trail_angle: float = deg_to_rad(clampf(float(obs.config.get("sweep_trail_degrees", 24)), 0.0, 60.0))
	for i in range(24):
		var a0: float = angle - trail_angle * float(i + 1) / 24.0
		var a1: float = angle - trail_angle * float(i) / 24.0
		var shade: Color = _green
		shade.a = 0.14 * pow(1.0 - float(i) / 24.0, 2.0)
		draw_colored_polygon(PackedVector2Array([center, center + Vector2(cos(a0), sin(a0)) * radius, center + Vector2(cos(a1), sin(a1)) * radius]), shade)
	draw_line(center, center + Vector2(cos(angle), sin(angle)) * radius, _green.darkened(0.3), 1.5)
	for entry in obs.config.get("regions", []):
		if str(entry.get("view", "nearshore")) != ("sea" if sea else "nearshore"):
			continue
		var pos: Vector2 = center + _map_offset(entry, range_m) * radius
		if pos.distance_to(center) > radius - 15.0:
			continue
		var sensors: Array = entry.get("sensors", [])
		var connected: bool = not sensors.is_empty()
		var col: Color = _green if connected else Color(viewer.T.dim)
		if obs.region_has_device_warning(str(entry.get("id", ""))):
			col = _amber
		draw_circle(pos, 5.5, col)
		if entry.get("id", "") == viewer.selected_region and viewer.selected_region != "station":
			_selection_brackets(pos)
		hits.append({"rect": Rect2(pos - Vector2(12, 12), Vector2(24, 24)), "action": "region:" + str(entry.get("id", "")), "name": str(entry.get("name", "")), "color": col, "position": pos})
	if sea:
		draw_circle(center, 5.5, _green)
		hits.append({"rect": Rect2(center - Vector2(12, 12), Vector2(24, 24)), "action": "region:station", "name":"本站", "color":_green, "position":center})
	_text(Vector2(center.x - 10, 68), "N", 21)
	_text(Vector2(center.x - 10, 873), "S", 21)
	_text(Vector2(550, 464), "W", 21)
	_text(Vector2(1355, 464), "E", 21)
	_text(Vector2(530, 865), "半径 %.0f %s / 每格 %.0f %s" % [range_units, "NM" if sea else "m", grid_units, "NM" if sea else "m"], 20)
	if sea:
		for route in obs.known_routes():
			_draw_contact_path(route.get("known_route_m", []), center, radius, range_m, _contact_color(route), true)
		for contact in obs.radar_contacts():
			var color: Color = _contact_color(contact)
			_draw_contact_path(contact.get("observed_track_m", []), center, radius, range_m, color, false)
			var alpha: float = float(contact.get("echo_alpha", 0))
			if alpha <= 0: continue
			var offset: Vector2 = _map_offset(contact, range_m)
			if offset.length() > 0.97: continue
			var pos: Vector2 = center + offset * radius
			var contact_id: String = str(contact.get("id", ""))
			color.a = alpha
			var kind: String = str(contact.get("kind", "ship"))
			if kind == "ship":
				draw_rect(Rect2(pos - Vector2(6, 6), Vector2(12, 12)), color)
			elif kind in ["aircraft", "submarine"]:
				var sign_y: float = -1.0 if kind == "aircraft" else 1.0
				draw_colored_polygon(PackedVector2Array([pos + Vector2(0, sign_y * 8), pos + Vector2(-6.928, -sign_y * 4), pos + Vector2(6.928, -sign_y * 4)]), color)
			else:
				draw_arc(pos, 8, 0, TAU, 24, color, 1.3, true)
				draw_line(pos - Vector2(5, 5), pos + Vector2(5, 5), color)
				draw_line(pos + Vector2(-5, 5), pos + Vector2(5, -5), color)
			if viewer.selected_region == "contact:" + contact_id: _selection_brackets(pos, color)
			hits.append({"rect":Rect2(pos - Vector2(12,12), Vector2(24,24)), "action":"contact:" + contact_id, "name":str(contact.get("name", contact_id)), "color":color, "position":pos})
	_draw_hover_name()

func _draw_hover_name() -> void:
	var action: String = action_at(get_local_mouse_position())
	for hit in hits:
		if hit.get("action", "") != action or not hit.has("name"): continue
		var pos: Vector2 = hit["position"]
		_text(pos + Vector2(28, 6), str(hit["name"]), 18, hit["color"])
		return

func _contact_color(contact: Dictionary) -> Color:
	if contact.get("kind", "") == "mine": return Color(viewer.T.error)
	match str(contact.get("threat", "unknown")):
		"civilian", "friendly": return _green
		"military": return _amber
		_: return Color(viewer.T.error)

func _draw_contact_path(points: Array, center: Vector2, radius: float, range_m: float, color: Color, dashed: bool) -> void:
	var previous: Vector2 = Vector2.INF
	color.a = 0.5 if dashed else 0.8
	for pair in points:
		if not (pair is Array) or pair.size() != 2: continue
		var next := Vector2(float(pair[0]), -float(pair[1])) * radius / range_m
		if previous != Vector2.INF:
			# 将线段裁剪到圆盘，不把圈外路径连成横贯圆盘的假线。
			var direction: Vector2 = next - previous
			var length_sq: float = direction.length_squared()
			if length_sq > 0.0001:
				var b: float = 2.0 * previous.dot(direction)
				var c: float = previous.length_squared() - radius * radius
				var discriminant: float = b * b - 4.0 * length_sq * c
				if discriminant >= 0:
					var start: float = maxf(0.0, (-b - sqrt(discriminant)) / (2.0 * length_sq))
					var end: float = minf(1.0, (-b + sqrt(discriminant)) / (2.0 * length_sq))
					if start <= end:
						var a: Vector2 = center + previous + direction * start
						var z: Vector2 = center + previous + direction * end
						if dashed:
							draw_dashed_line(a, z, color, 0.8, 6.0)
						else:
							draw_line(a, z, color, 1.1, true)
		previous = next

func _map_offset(entry: Dictionary, range_m: float) -> Vector2:
	# 新接口：相对本站的东／北向米；旧归一化坐标保留兼容。
	if entry.has("position_m"):
		var metric: Array = entry.get("position_m", [0, 0])
		return Vector2(float(metric[0]), -float(metric[1])) / maxf(range_m, 1.0)
	var coords: Array = entry.get("position", [0, 0])
	return Vector2(float(coords[0]), float(coords[1]))

func _draw_terrain(center: Vector2, radius: float, range_m: float, map_config: Dictionary, fallback_path: String) -> void:
	_load_texture(str(map_config.get("texture", fallback_path)))
	if _texture == null:
		_text(center + Vector2(-110, 95), "地形底图尚未加载", 20, _dim)
		return
	# extent_m 是正方形 SVG 的实际边长，底图中心就是已配准的本站。
	var extent_m: float = maxf(float(map_config.get("extent_m", range_m * 2.0)), 1.0)
	var half_size: float = extent_m * radius / maxf(range_m, 1.0) * 0.5
	var disc := PackedVector2Array()
	for i in range(192):
		var angle: float = TAU * float(i) / 192.0
		disc.append(center + Vector2(cos(angle), sin(angle)) * radius)
	var square := PackedVector2Array([
		center + Vector2(-half_size, -half_size), center + Vector2(half_size, -half_size),
		center + Vector2(half_size, half_size), center + Vector2(-half_size, half_size)])
	# 几何裁剪只作用于底图；网格、图标、文字仍沿用当前 CRT 画布。
	for polygon in Geometry2D.intersect_polygons(disc, square):
		var uvs := PackedVector2Array()
		for point in polygon:
			uvs.append((point - center) / (half_size * 2.0) + Vector2.ONE * 0.5)
		draw_polygon(polygon, PackedColorArray([Color.WHITE]), uvs, _texture)

func _draw_map_labels(center: Vector2, radius: float, range_m: float, map_config: Dictionary) -> void:
	# SVG 不依赖系统字体；地形／水深文字由游戏字体绘制。
	# 数据保留在配置中，显示开关不影响高程和水深记录。
	if not bool(map_config.get("show_labels", true)):
		return
	var occupied: Array[Rect2] = []
	for label in map_config.get("labels", []):
		var pos: Vector2 = center + _map_offset(label, range_m) * radius
		var value: String = str(label.get("name", ""))
		var font_size: int = 17 if value == "码头" else 15
		var width: float = _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if pos.distance_to(center) < 35.0 or pos.distance_to(center) + width > radius - 12.0:
			continue
		var bounds := Rect2(pos - Vector2(3, font_size), Vector2(width + 10, font_size + 6))
		var overlaps: bool = false
		for previous in occupied:
			if previous.intersects(bounds):
				overlaps = true
				break
		if overlaps:
			continue
		occupied.append(bounds)
		_text(pos, value, font_size, _green.darkened(0.35))

func _load_texture(path: String) -> void:
	if path == _texture_path and _texture != null:
		return
	_texture_path = path
	_texture = null
	if _textures.has(path):
		_texture = _textures[path] as Texture2D
		return
	if not path.is_empty() and ResourceLoader.exists(path):
		_texture = load(path) as Texture2D
		if _texture:
			_textures[path] = _texture

func _draw_selection() -> void:
	var obs: EnvObservation = viewer.main.env_observation
	_box(Rect2(1410, 70, 490, 320), "环境简报")
	_text(Vector2(1430, 150), "天气  " + viewer.env_monitor.get_weather_name(), 21)
	_text(Vector2(1430, 198), "采集  " + ("完成 / " + str(obs.state().get("hour", "")) if obs.is_collected() else "尚未采集"), 21)
	_text(Vector2(1430, 246), "日报  " + ("已归档" if obs.is_submitted() else "未提交"), 21)
	hits.append({"rect": Rect2(1425, 270, 450, 42), "action": "investigation_region:"})
	var pending_count: int = obs.pending_issue_count()
	_text(Vector2(1430, 294), "待核对  %d 项" % pending_count, 21, _amber if pending_count > 0 else _green)
	_text(Vector2(1430, 350), "详细读数：details evidence", 18, _dim)
	if viewer.selected_region.begins_with("contact:"):
		for contact in obs.radar_contacts():
			if float(contact.get("echo_alpha", 0)) <= 0: continue
			if "contact:" + str(contact.get("id", "")) != viewer.selected_region: continue
			_box(Rect2(1410, 430, 490, 270), "目标回报")
			_text(Vector2(1430, 515), str(contact.get("name", contact.get("id", ""))), 23, _contact_color(contact), 450)
			_wrapped(Vector2(1430, 555), "来源：" + str(contact.get("source", "未注明")), 440, 2)
			_text(Vector2(1430, 620), "上次扫描：%.1f秒前" % float(contact.get("echo_age", 0)), 18, _dim)
			_wrapped(Vector2(1430, 655), str(contact.get("note", "位置来自扫描回报；潜艇数据由声纳提供。")), 440, 2, _dim)
	else:
		for region in obs.config.get("regions", []):
			if str(region.get("id", "")) != viewer.selected_region: continue
			_box(Rect2(1410, 430, 490, 430), "观测点简报")
			_text(Vector2(1430, 510), str(region.get("name", "")), 23)
			_wrapped(Vector2(1430, 552), "来源：" + str(region.get("source", "未注明")), 440, 2)
			var sensors: Array = region.get("sensors", [])
			hits.append({"rect": Rect2(1425, 598, 450, 38), "action": "investigation_region:" + viewer.selected_region})
			var issue_count: int = obs.pending_issue_count(viewer.selected_region)
			_text(Vector2(1430, 620), "接入 %d 项参数 / 待核对 %d 项" % [sensors.size(), issue_count], 19, _amber if issue_count > 0 else _green)
			var y: float = 656
			if sensors.is_empty():
				_text(Vector2(1430, y), "尚未接入；当前仅显示示意点位。", 19, _dim)
			for sid in sensors.slice(0, 3):
				var cfg: Dictionary = viewer.env_monitor.get_sensor_config(str(sid))
				_text(Vector2(1430, y), "%s  %s %s" % [cfg.get("name", sid), _sensor_value(str(sid)), cfg.get("unit", "")], 19, _green, 445)
				y += 32
			var maintenance: Dictionary = obs.routine_maintenance_status(viewer.selected_region)
			var busy: bool = viewer.get("maintenance_busy") == true
			var here: bool = viewer.get("maintenance_region") == viewer.selected_region
			_button(Rect2(1430, 766, 180, 42), "检查维护中" if busy and here else str(maintenance["label"]), "routine_maintenance", false, bool(maintenance["enabled"]) and not busy)
			_wrapped(Vector2(1625, 786), "请稍候" if busy and here else str(maintenance["note"]), 255, 2, _dim)
			if here:
				_text(Vector2(1430, 842), Typewriter.format_progress_bar(float(viewer.get("maintenance_progress")), ""), 17, _green, 445)
			break

func _draw_footer() -> void:
	var obs: EnvObservation = viewer.main.env_observation
	var status: String = "Tab 近海／远海 | manual 操作说明 | details 详情 | exit 返回桌面"
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
		var items: Array = report.get("issues", [])
		var pages: int = maxi(1, ceili(float(items.size()) / 3.0))
		viewer.history_content_page = clampi(viewer.history_content_page, 0, pages - 1)
		_text(Vector2(1100, 225), "疑点页 %d / %d，共%d项" % [viewer.history_content_page + 1, pages, items.size()], 20, _dim)
		for issue in items.slice(viewer.history_content_page * 3, (viewer.history_content_page + 1) * 3):
			_text(Vector2(465, y), "%s / %s" % [issue.get("name", ""), "关注" if issue.get("marked", false) else "未确认记录"], 20, _amber, 1400)
			y += 30
			_text(Vector2(465, y), str(issue.get("retest_note", "未复测")), 18, _green, 1400)
			y += 30
			_text(Vector2(465, y), str(issue.get("verification_note", "未做处理后验证")), 18, _dim, 1400)
			y += 30

	_text(Vector2(465, 845), "history older/newer 切日报；history next/prev 翻疑点页；map 返回地图", 19, _dim)

func _button(rect: Rect2, text: String, action: String, selected: bool = false, enabled: bool = true) -> void:
	selected = selected or viewer.get("detail_focus") == action
	draw_rect(rect, Color(_green, (0.20 if selected else 0.08) if enabled else 0.0))
	draw_rect(rect, _green if selected else viewer.T.border, false, 1.0)
	_text(rect.position + Vector2(12, 27), text, 20, _green if enabled else Color(viewer.T.dim))
	if enabled: hits.append({"rect": rect, "action": action})

func _wrapped(pos: Vector2, text: String, width: float, max_lines: int = 3, color: Color = Color(-1, -1, -1)) -> void:
	var line: String = ""
	var row: int = 0
	for character in text:
		if character == "\n" or _font.get_string_size(line + character, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x > width:
			_text(pos + Vector2(0, row * 25), line, 18, color)
			row += 1
			line = ""
			if row >= max_lines: return
		if character != "\n": line += character
	_text(pos + Vector2(0, row * 25), line, 18, color)

func _draw_details() -> void:
	var em: EnvMonitor = viewer.env_monitor
	var obs: EnvObservation = viewer.main.env_observation
	var names: Array[String] = ["总览", "大气", "海洋", "地球物理", "大气成分", "事件／异常", "采集证据"]
	var pages: Array[int] = [2, 3, 4, 5, 6, 7, 9]
	_text(Vector2(450, 92), "观测数据 / " + em.get_weather_name() + " / " + em.get_current_hour_display(), 26)
	for i in range(names.size()):
		_button(Rect2(450 + i * 180, 120, 170, 40), names[i], "page:" + str(pages[i]), viewer.current_page == pages[i])
	_button(Rect2(1740, 120, 155, 40), "返回地图", "page:0")
	if viewer.current_page == 2:
		_draw_investigation(obs)
	elif viewer.current_page in [3, 4, 5, 6]:
		var category: String = ["atmosphere", "ocean", "geophysics", "composition"][viewer.current_page - 3]
		_text(Vector2(465, 210), "参数", 21, _dim)
		_text(Vector2(850, 210), "本站读数", 21, _dim)
		_text(Vector2(1160, 210), "设备状态", 21, _dim)
		_text(Vector2(1390, 210), "近期变化（约10秒）", 21, _dim)
		var ids: Array = em.get_sensors_by_category(category)
		for i in range(ids.size()):
			var sid: String = str(ids[i])
			var cfg: Dictionary = em.get_sensor_config(sid)
			var y: float = 260 + i * 52
			var status: String = str(em.sensor_status.get(sid, "offline"))
			var color: Color = _green if status == "online" else _amber
			draw_line(Vector2(455, y + 18), Vector2(1885, y + 18), viewer.T.border)
			_text(Vector2(465, y), str(cfg.get("name", sid)), 22)
			_text(Vector2(850, y), _sensor_value(sid) + " " + str(cfg.get("unit", "")), 22, color)
			_text(Vector2(1160, y), str({"online":"在线", "offline":"离线", "degraded":"退化", "malfunction":"故障"}.get(status, status)), 21, color)
			_text(Vector2(1390, y), str({"rising":"↑ 上升", "falling":"↓ 下降", "stable":"→ 稳定"}.get(em.get_sensor_trend(sid), "数据暂缺")), 21, color)
			_draw_sensor_trace(sid, Rect2(1600, y - 24, 260, 32))
			hits.append({"rect": Rect2(455, y - 30, 1430, 48), "action": "investigate:sensor:" + sid})
		_wrapped(Vector2(465, 810), "以上为实时设备读数。采集证据保存固定快照；点击设备查看问题与证据，复核按钮整合同期比对。", 1400, 2, _dim)
	elif viewer.current_page == 9:
		_draw_evidence_page(obs)
	else:
		_text(Vector2(465, 210), "剧情环境事件", 24)
		var y: float = 265
		if em.active_events.is_empty():
			_text(Vector2(465, y), "当前没有环境事件；后续由每日剧情明确启用。", 21, _dim)
		for eid in em.active_events:
			_text(Vector2(465, y), str(em.active_events[eid].get("name", eid)), 22, _amber)
			y += 42
		_text(Vector2(465, 510), "读数待核对项", 24)
		_wrapped(Vector2(465, 558), "当前 %d 项。设备退化或读数超出常规范围也可能产生疑点，疑点不等于特殊剧情事件。点击总览查看项目；采集证据页保留原始记录。" % obs.issues().size(), 1350, 3)
	_text(Vector2(465, 905), "点击项目／分类 | 空输入时 Tab／方向键选择，Enter 确认 | map 返回地图", 19, _dim)

func _draw_investigation(obs: EnvObservation) -> void:
	if not viewer.investigation_key.is_empty():
		_draw_investigation_item(obs)
		return
	var items: Array[Dictionary] = obs.investigation_items(viewer.investigation_filter)
	var pages: int = maxi(1, ceili(float(items.size()) / 7.0))
	viewer.detail_content_page = clampi(viewer.detail_content_page, 0, pages - 1)
	_text(Vector2(465, 207), "今日观测 / 点击项目查看问题、依据与处理", 24)
	_text(Vector2(465, 243), "采集：%s | 日报：%s | %s" % ["完成" if obs.is_collected() else "尚未采集", "已归档" if obs.is_submitted() else "未提交", "全部设备" if viewer.investigation_filter.is_empty() else viewer.investigation_filter], 20, _dim)
	if items.is_empty(): _text(Vector2(465, 325), "暂无可疑项目；采集后可提交日报。分类页可查看全部实时设备。", 22)
	var row: int = 0
	for item in items.slice(viewer.detail_content_page * 7, (viewer.detail_content_page + 1) * 7):
		var sid: String = item["sensor"]
		var issue: Dictionary = item["issue"]
		var name: String = str(issue.get("name", obs.monitor.get_sensor_config(sid).get("name", sid)))
		var status: String = "待处理" if item["pending"] else "已恢复"
		if bool(issue.get("marked", false)) and item["pending"]: status = "疑点已保留"
		_button(Rect2(465, 275 + row * 72, 1400, 56), name + "  /  " + status, "investigate:" + str(item["key"]))
		row += 1
	_text(Vector2(465, 826), "原始观测保留；普通设备一键维护，无法确认的变化可保留并如实提交。", 20, _dim)
	_button(Rect2(465, 850, 160, 40), "全部项目", "investigation_region:")
	_button(Rect2(1330, 850, 150, 40), "上一页", "detail_prev", false, viewer.detail_content_page > 0)
	_button(Rect2(1500, 850, 150, 40), "下一页", "detail_next", false, viewer.detail_content_page < pages - 1)
	_text(Vector2(1690, 877), "%d / %d" % [viewer.detail_content_page + 1, pages], 20)

func _draw_investigation_item(obs: EnvObservation) -> void:
	var item: Dictionary = obs.investigation_item(viewer.investigation_key)
	if item.is_empty():
		_text(Vector2(465, 235), "项目已更新，请返回列表。", 23)
		_button(Rect2(465, 790, 180, 42), "返回列表", "investigation_back")
		return
	var sid: String = item["sensor"]
	var issue: Dictionary = item["issue"]
	var cfg: Dictionary = obs.monitor.get_sensor_config(sid)
	var blocked: String = obs._maintenance_block_reason(sid)
	var hardware: bool = obs._needs_routine_maintenance(sid)
	var cause: String = "设备状态正常；观测变化的原因尚未确认，需要依据复核结果判断。"
	if hardware:
		cause = "设备退化／故障降低读数可靠性；维护后自动验证。"
		if obs.monitor.sensor_status.get(sid, "offline") == "offline": cause = "设备离线，无法提供读数；恢复连接后自动验证。"
		elif obs.monitor.sensor_status.get(sid, "online") in ["online", "nominal", "optimal"]: cause = "设备校准偏移超过容许范围，影响读数准确性；校准后自动验证。"
	elif not bool(item["pending"]): cause = "设备状态正常；历史采集证据保留。"
	if not blocked.is_empty(): cause = "特殊故障：" + blocked + "。当前不能自动维护。"
	_text(Vector2(465, 218), str(cfg.get("name", sid)) + " / " + ("待核对" if item["pending"] else "已恢复／正常"), 25, _amber if item["pending"] else _green)
	_wrapped(Vector2(465, 263), "问题与当前判断：" + cause, 1380, 2)
	_text(Vector2(465, 342), "证据 / 首次与参考来自同次采集，实时值单独展示", 22)
	var first: Variant = issue.get("first", obs.state().get("readings", {}).get(sid))
	var baseline: Variant = obs.state().get("reference", {}).get("readings", {}).get(sid)
	_text(Vector2(465, 395), "首次观测：%s  /  同期参考：%s  /  当前实时：%s %s" % [EnvObservation.format_value(first), EnvObservation.format_value(baseline), _sensor_value(sid), cfg.get("unit", "")], 22)
	var difference: String = "同期参考缺失，无法倒填旧证据。"
	if first != null and baseline != null:
		var delta: float = float(first) - float(baseline)
		if sid == "wind_dir": delta = fmod(delta + 540.0, 360.0) - 180.0
		difference = "首次与参考差值：%+.2f %s；差异本身不能确定故障原因。" % [delta, cfg.get("unit", "")]
	_wrapped(Vector2(465, 446), difference, 1380, 2, _dim)
	_wrapped(Vector2(465, 514), "复核：" + str(issue.get("retest_note", "尚未复核；点击复核观测取得一次样本。")), 1380, 2)
	var verification: String = str(issue.get("verification_note", "尚无维护后验证记录。"))
	for record in obs.state().get("routine_maintenance", []):
		if record.get("sensor", "") == sid:
			verification = "维护后读数 %s；%s。" % [EnvObservation.format_value(record.get("after", {}).get("value")), "设备已恢复" if record.get("verified", false) else "仍需排查"]
	_wrapped(Vector2(465, 585), "处理结果：" + verification, 1380, 2)
	_wrapped(Vector2(465, 659), "疑点已保留，可如实提交。" if issue.get("marked", false) else "原因不明确时可保留疑点；维护与复核不会自动提交日报。", 1380, 2, _dim)
	var review_enabled: bool = not issue.is_empty() and not obs.is_submitted() and not obs.is_collecting() and (not issue.has("retest") and not issue.has("verification") or bool(issue.get("verification_pending", false)))
	_button(Rect2(465, 760, 220, 44), "复核观测", "review_item", false, review_enabled)
	_button(Rect2(710, 760, 240, 44), "维护并验证", "maintain_item", false, hardware and blocked.is_empty() and obs.debug_scenario.is_empty() and not obs.is_collecting())
	_button(Rect2(975, 760, 220, 44), "保留疑点", "retain_item", false, not issue.is_empty() and bool(item["pending"]) and not obs.is_submitted() and not bool(issue.get("marked", false)))
	_button(Rect2(1220, 760, 200, 44), "返回列表", "investigation_back")
	_text(Vector2(465, 844), "已归档证据不可改写；设备仍可维护。特殊排查按上方提示进行。" if obs.is_submitted() else "复核仅记录一次；维护后自动验证。无法确认也可 report 提交。", 20, _dim)

func _sensor_value(sid: String) -> String:
	var em: EnvMonitor = viewer.env_monitor
	var value: float = em.get_reading(sid)
	if not is_finite(value) or em.sensor_status.get(sid, "offline") == "offline": return "数据暂缺"
	var precision: int = clampi(int(em.get_sensor_config(sid).get("precision", 1)), 0, 3)
	return ("%." + str(precision) + "f") % value

func _draw_sensor_trace(sid: String, rect: Rect2) -> void:
	var history: Array = viewer.env_monitor.reading_history.get(sid, [])
	var samples: Array = history.slice(maxi(0, history.size() - 20))
	var lo: float = INF
	var hi: float = -INF
	for sample in samples:
		var v: float = float(sample.get("value", NAN))
		if is_finite(v):
			lo = minf(lo, v)
			hi = maxf(hi, v)
	if not is_finite(lo): return
	var previous: Vector2 = Vector2.INF
	for i in range(samples.size()):
		var v: float = float(samples[i].get("value", NAN))
		if not is_finite(v):
			previous = Vector2.INF
			continue
		var point: Vector2 = rect.position + Vector2(float(i) / maxi(1, samples.size() - 1) * rect.size.x, rect.size.y * (0.5 if hi == lo else 1.0 - (v - lo) / (hi - lo)))
		if previous != Vector2.INF: draw_line(previous, point, _green.darkened(0.2), 1.2, true)
		previous = point

func _draw_evidence_page(obs: EnvObservation) -> void:
	var data: Dictionary = obs.state()
	_text(Vector2(465, 210), "固定快照 / " + str(data.get("hour", "尚未采集")), 24)
	var values: Dictionary = data.get("readings", {})
	var ids: Array = values.keys()
	var pages: int = maxi(1, maxi(ceili(float(obs.issues().size()) / 3.0), ceili(float(ids.size()) / 8.0)))
	viewer.detail_content_page = clampi(viewer.detail_content_page, 0, pages - 1)
	var y: float = 260
	for sid in ids.slice(viewer.detail_content_page * 8, (viewer.detail_content_page + 1) * 8):
		var cfg: Dictionary = viewer.env_monitor.get_sensor_config(str(sid))
		_text(Vector2(465, y), "%s  %s %s" % [cfg.get("name", sid), EnvObservation.format_value(values.get(sid)), cfg.get("unit", "")], 21)
		y += 40
	_text(Vector2(465, 650), "来源 / 同次区域参考", 22)
	_wrapped(Vector2(465, 695), "本站固定设备；区域天气参考 OB-7K。" + ("已保存同期参考，项目详情展示差值。" if data.has("reference") else "当前记录没有同期参考。"), 420, 4, _dim)
	_text(Vector2(960, 210), "证据页 %d项疑点 / 第%d/%d页" % [obs.issues().size(), viewer.detail_content_page + 1, pages], 22)
	if obs.issues().is_empty(): _text(Vector2(960, 270), "暂无疑点记录", 21, _dim)
	var row: int = 0
	for issue in obs.issues().slice(viewer.detail_content_page * 3, (viewer.detail_content_page + 1) * 3):
		var top: float = 265 + row * 182
		_text(Vector2(960, top), str(issue.get("name", "")) + (" [已恢复]" if not obs.issue_is_pending(issue) else (" [关注]" if issue.get("marked", false) else "")), 22, _amber if obs.issue_is_pending(issue) else _green, 920)
		_wrapped(Vector2(960, top + 32), str(issue.get("note", "")), 920, 2)
		_wrapped(Vector2(960, top + 89), str(issue.get("retest_note", "尚未复测")), 920, 2)
		hits.append({"rect": Rect2(960, top - 24, 920, 155), "action": "investigate:issue:" + str(viewer.detail_content_page * 3 + row)})
		var verification: String = "等待%s后验证：打开项目详情" % issue.get("maintenance_kind", "处理") if bool(issue.get("verification_pending", false)) else str(issue.get("verification_note", "点击项目查看处理与复核"))
		_wrapped(Vector2(960, top + 143), verification, 920, 1, _amber if bool(issue.get("verification_pending", false)) else _dim)
		row += 1
	_button(Rect2(1410, 840, 140, 40), "上一页", "detail_prev")
	_button(Rect2(1570, 840, 140, 40), "下一页", "detail_next")
