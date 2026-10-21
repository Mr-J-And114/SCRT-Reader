# ============================================================
# env_viewer.gd
# 环境监测站数据显示面板 —— CRT 风格覆盖层 UI
#
# 遵循 DocumentViewer / RadioReceiver 的 overlay 模式：
# 对齐到 OutputArea 区域，复用底部输入栏，
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
var map_canvas: EnvMapCanvas = null
var _layer: CanvasLayer = null
var command_log: RichTextLabel = null
var command_input: LineEdit = null
var command_panel: Panel = null
var _feedback_lines: Array[String] = []
var _last_observation_message: String = ""
var _command_history: Array[String] = []
var _history_cursor: int = 0
var _silent_command: bool = false
# 后续无人机模块注册 callable(Array[String]) -> String；当前没有飞行实现。
var command_extensions: Dictionary = {}

func register_command_extension(command_name: String, handler: Callable) -> void:
	command_extensions[command_name.to_lower()] = handler

func unregister_command_extension(command_name: String) -> void:
	command_extensions.erase(command_name.to_lower())
var selected_region: String = ""
var history_index: int = 0
var history_content_page: int = 0
var detail_content_page: int = 0
var investigation_filter: String = ""
var investigation_key: String = ""
var detail_focus: String = ""
var manual_section: int = 0 # 维护速查 / 全部指令 / 图例
var _sweep_angle: float = 0.0
# 维护结果仅在进度结束后应用；退出观测台取消未完成的检查。
var maintenance_region: String = ""
var maintenance_progress: float = 0.0
var maintenance_busy: bool = false
var _maintenance_duration: float = 0.0
var _maintenance_elapsed: float = 0.0
var _maintenance_hold: float = 0.0
var _maintenance_rng := RandomNumberGenerator.new()

# ══════════════════════════════════════════
#  显示状态
# ══════════════════════════════════════════
var is_active: bool = false
var current_page: int = 0       # 0/1地图，2..7实时详情，8历史，9采集证据
var page_names: Array = ["岛屿/近海", "海域", "总览", "大气", "海洋", "地球物理", "大气成分", "事件/异常", "日报历史"]
const MAX_PAGES: int = 11

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
	main._env_viewer_mode = true
	main.env_observation.migrate_legacy()
	current_page = 0
	manual_section = 0
	_ensure_overlay()
	_align_overlay()
	# 缓存并隐藏终端 UI
	_cached_input_visible = main.input_field.visible
	_cached_prompt_visible = main.prompt_label.visible
	main.input_field.visible = true
	main.prompt_label.visible = true
	_cached_output_text = main.output_text.text
	main.output_text.text = ""
	# 更新路径栏提示
	if main.path_label:
		main.path_label.text = "ENV | Tab 近海／远海 | manual 操作说明 | exit 返回桌面"

	overlay_panel.visible = true
	_refresh_page()
	_feedback_lines.clear()
	command_log.clear()
	selected_region = ""
	_log("环境观测终端就绪。输入 manual 阅读操作说明。\n常用流程：scan → 观测点常规维护 → details 点击调查 → report\n地图：map nearshore / map sea")
	_last_observation_message = main.env_observation.message
	command_input.clear()
	command_input.grab_focus()
	# ★ 重置滚动位置
	if _scroll:
		_scroll.scroll_vertical = 0

func close() -> void:
	if not is_active:
		return
	is_active = false
	_cancel_maintenance()
	main._env_viewer_mode = false
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
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT :
		var action: String = map_canvas.action_at(map_canvas.get_local_mouse_position())
		if not action.is_empty():
			if action == "detail_next":
				detail_content_page += 1
			elif action == "detail_prev":
				detail_content_page = maxi(0, detail_content_page - 1)
			elif action == "deselect":
				selected_region = ""
			elif action.begins_with("contact:"):
				selected_region = action
				_log("已选择目标：" + action.trim_prefix("contact:"))
			else:
				perform_action(action)
				if action.begins_with("region:"):
					_log("已选择设施：" + selected_region)
			_refresh_page()
			command_input.grab_focus()
			return true
	if event is InputEventKey and event.pressed:
		if current_page in [2, 3, 4, 5, 6, 7, 9] and command_input.text.is_empty():
			var actions: Array[String] = []
			for hit in map_canvas.hits: actions.append(str(hit["action"]))
			if not actions.is_empty() and event.keycode in [KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
				var direction: int = -1 if event.shift_pressed or event.keycode in [KEY_UP, KEY_LEFT] else 1
				detail_focus = actions[posmod(actions.find(detail_focus) + direction, actions.size())]
				_refresh_page()
				return true
			if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and actions.has(detail_focus):
				perform_action(detail_focus)
				detail_focus = ""
				return true
		if event.keycode == KEY_TAB:
			if not event.echo:
				perform_action("nearshore" if current_page == 1 else "sea")
				command_input.grab_focus()
			return true
		if command_input.has_focus() and event.keycode in [KEY_UP, KEY_DOWN] and not _command_history.is_empty():
			_history_cursor = clampi(_history_cursor + (-1 if event.keycode == KEY_UP else 1), 0, _command_history.size())
			command_input.text = _command_history[_history_cursor] if _history_cursor < _command_history.size() else ""
			command_input.caret_column = command_input.text.length()
			return true
	return false

func _log(value: String) -> void:
	if _silent_command:
		return
	if value.begins_with("采集完成："):
		_feedback_lines = _feedback_lines.filter(func(line): return not line.begins_with("正在采集固定观测设备的数据"))
	for line in value.split("\n"):
		_feedback_lines.append(line)
	if _feedback_lines.size() > 250:
		_feedback_lines = _feedback_lines.slice(-250)
	_render_feedback()

func _render_feedback() -> void:
	# 按当前字号与可见高度保留末尾反馈，无滚动条，不依赖自动滚动。
	var font: Font = main.output_text.get_theme_font("normal_font")
	var fs: int = command_log.get_theme_font_size("normal_font_size")
	var wrapped: Array[String] = []
	var token_pattern := RegEx.new()
	token_pattern.compile("[A-Za-z0-9_./-]+|.")
	for line in _feedback_lines:
		var row: String = ""
		for token in token_pattern.search_all(line):
			var word: String = token.get_string()
			if not row.is_empty() and font.get_string_size(row + word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > command_log.size.x - 10:
				wrapped.append(row)
				row = ""
			for character in word:
				if not row.is_empty() and font.get_string_size(row + character, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > command_log.size.x - 10:
					wrapped.append(row)
					row = ""
				row += character
		wrapped.append(row)
	var capacity: int = maxi(1, int(command_log.size.y / (font.get_height(fs) + 4)))
	command_log.text = "\n".join(wrapped.slice(maxi(0, wrapped.size() - capacity)))

func execute_command(raw: String) -> void:
	var parsed: Dictionary = CommandHandler.parse_debug_input(raw, true)
	var line: String = str(parsed["line"])
	var silent: bool = bool(parsed["silent"])
	command_input.clear()
	if line.is_empty():
		return
	if not silent:
		_log("> " + line)
		_command_history.append(line)
		if _command_history.size() > 100:
			_command_history.pop_front()
		_history_cursor = _command_history.size()
	var was_silent: bool = _silent_command
	_silent_command = silent
	if silent:
		main._silent_debug_depth += 1
	_execute_command_line(line)
	if silent:
		main._silent_debug_depth -= 1
	_silent_command = was_silent

func _execute_command_line(line: String) -> void:
	var parts: PackedStringArray = line.to_lower().split(" ", false)
	if parts[0] == "env":
		parts.remove_at(0)
	if parts.is_empty():
		parts.append("help")
	var verb: String = parts[0]
	var args: Array[String] = []
	for i in range(1, parts.size()):
		args.append(parts[i])
	var obs: EnvObservation = main.env_observation
	if verb in ["issues", "issue", "select", "next", "retest", "respond", "compare", "mark", "calibrate", "cal", "repair", "check", "sensor"]:
		_log("调查与设备操作已整合至 details；请点击项目，再使用复核／维护／保留疑点按钮。")
		return
	match verb:
		"debug":
			if args.size() >= 3 and args[0] == "114514" and args[1] == "env" and args[2] == "traffic":
				_log(obs.configure_traffic(args.slice(3)))
				current_page = 1
			elif args.size() >= 2 and args[0] == "114514" and args[1] == "warning":
				var duration: float = 5.0
				if args.size() >= 3:
					if not args[2].is_valid_float() or args[2].to_float() <= 0.0:
						_log("用法：debug 114514 warning [正数秒数]，默认5秒。")
						return
					duration = args[2].to_float()
				main.trigger_warning(duration)
				_log("WARNING 显示 %.1f 秒。" % duration)
			elif args.size() == 2 and args[0] == "114514" and args[1] == "reset_fx":
				main.crt_shader.reset_all_effects()
				_log("所有屏幕特效已清除。")
			else:
				_log("此界面支持 debug 114514 env traffic / warning / reset_fx；其它调试请 exit 后执行。")
		"help", "manual", "guide":
			var section: String = args[0] if not args.is_empty() else "maintenance"
			var sections: Array[String] = ["maintenance", "commands", "legend"]
			if section not in sections:
				_log("用法：help [maintenance/commands/legend]；也可点击页内分类。")
				return
			manual_section = sections.find(section)
			current_page = 10
			_log("已打开操作说明：维护速查／全部指令／图例可点击切换；map 返回地图。")
		"scan", "collect": perform_action("capture")

		"maintain": perform_action("routine_maintenance")
		"report", "submit": perform_action("submit")

		"status":
			_log("%s %s / %s\n采集：%s / 日报：%s / 疑点：%d" % [env_monitor.get_day_display(), env_monitor.get_current_hour_display(), env_monitor.get_weather_name(), "完成" if obs.is_collected() else "未完成", "已提交" if obs.is_submitted() else "未提交", obs.issues().size()])

		"map":
			if args.is_empty() or args[0] == "nearshore": perform_action("nearshore")
			elif args[0] == "sea": perform_action("sea")
			else: _log("用法：map nearshore / map sea")
		"details":
			var sections: Array[String] = ["overview", "atmosphere", "ocean", "geophysics", "composition", "events", "evidence"]
			var section: String = args[0] if not args.is_empty() else "overview"
			if section == "next":
				detail_content_page += 1
			elif section == "prev":
				detail_content_page = maxi(0, detail_content_page - 1)
			elif section in sections:
				detail_content_page = 0
				investigation_key = ""
				investigation_filter = ""
				current_page = 9 if section == "evidence" else 2 + sections.find(section)
				_reset_scroll()
			else: _log("未知详情分类，输入 help 查看。")
		"history":
			if args.is_empty(): perform_action("history")
			elif args[0] == "older": perform_action("history_older")
			elif args[0] == "newer": perform_action("history_newer")
			elif args[0] == "next": history_content_page += 1
			elif args[0] == "prev": history_content_page = maxi(0, history_content_page - 1)
			else: _log("用法：history [older/newer/next/prev]")
			current_page = 8
		"clear":
			_feedback_lines.clear()
			command_log.clear()
		"exit", "quit", "close": close()
		_:
			if command_extensions.has(verb):
				_log(str(command_extensions[verb].call(args)))
			elif verb == "drone": _log("无人机模块尚未接入。当前使用固定观测设备。")
			else: _log("未知命令：" + verb + "。输入 help 查看指令。")
	if verb in ["scan", "collect", "retest", "respond", "mark", "calibrate", "cal", "report", "submit"]:
		_log(obs.message)
	_last_observation_message = obs.message
	_refresh_page()
	if is_active: command_input.grab_focus()

func perform_action(action: String) -> void:
	var obs: EnvObservation = main.env_observation
	if maintenance_busy and action in ["routine_maintenance", "maintain_item", "review_item", "retain_item", "capture", "submit", "retest", "mark", "calibrate"]:
		return
	if action.begins_with("page:"):
		current_page = int(action.trim_prefix("page:"))
		detail_content_page = 0
		investigation_key = ""
		investigation_filter = ""
	elif action.begins_with("investigate:"):
		investigation_key = action.trim_prefix("investigate:")
		var selected: Dictionary = obs.investigation_item(investigation_key)
		if not selected.is_empty(): investigation_key = str(selected["key"])
		current_page = 2
	elif action.begins_with("investigation_region:"):
		investigation_filter = action.trim_prefix("investigation_region:")
		investigation_key = ""
		detail_content_page = 0
		current_page = 2
	elif action in ["review_item", "maintain_item", "retain_item"]:
		var item: Dictionary = obs.investigation_item(investigation_key)
		if item.is_empty(): return
		match action:
			"review_item": obs.review_item(investigation_key)
			"maintain_item": obs.maintain_sensor(str(item["sensor"]))
			"retain_item": obs.retain_item(investigation_key)
		_log(obs.message)
		_last_observation_message = obs.message
	elif action == "investigation_back":
		investigation_key = ""
	elif action.begins_with("manual:"):
		manual_section = clampi(int(action.trim_prefix("manual:")), 0, 2)
		current_page = 10
	elif action.begins_with("region:"):
		selected_region = action.trim_prefix("region:")
		for i in range(obs.issues().size()):
			if obs.issues()[i].get("region", "") == selected_region:
				obs.selected_issue = i
				break
	else:
		if action in ["retest", "mark", "calibrate"] and not obs.current_issue().is_empty() and obs.current_issue().get("region", "") != selected_region:
			obs.message = "当前设施未选中该疑点。输入 issues 查看清单，再用 select <编号> 选择。"
			return
		match action:
			"routine_maintenance":
				_begin_maintenance(selected_region)
			"detail_next": detail_content_page += 1
			"detail_prev": detail_content_page = maxi(0, detail_content_page - 1)
			"capture": obs.begin_capture()
			"retest": obs.retest()
			"mark": obs.mark_issue()
			"calibrate": obs.calibrate_issue()
			"submit": obs.submit()
			"next_issue":
				obs.selected_issue = (obs.selected_issue + 1) % maxi(1, obs.issues().size())
				selected_region = str(obs.current_issue().get("region", selected_region))
			"nearshore": current_page = 0
			"sea": current_page = 1
			"history":
				history_content_page = 0
				current_page = 8
				history_index = 0
			"details": current_page = 2
			"history_older":
				history_content_page = 0
				history_index = mini(history_index + 1, maxi(0, main.env_task_mgr.observation_history.size() - 1))
			"history_newer":
				history_content_page = 0
				history_index = maxi(0, history_index - 1)
			"close": close()
	_refresh_page()

func _begin_maintenance(region: String) -> void:
	if maintenance_busy or not main.env_observation.routine_maintenance_status(region)["enabled"]:
		return
	maintenance_region = region
	maintenance_progress = 0.0
	maintenance_busy = true
	_maintenance_elapsed = 0.0
	_maintenance_hold = 0.0
	_maintenance_rng.randomize()
	_maintenance_duration = _maintenance_rng.randf_range(0.9, 1.6)

func _advance_maintenance(delta: float) -> void:
	if maintenance_busy:
		_maintenance_elapsed += maxf(delta, 0.0)
		maintenance_progress = clampf(_maintenance_elapsed / _maintenance_duration, 0.0, 1.0)
		if maintenance_progress >= 1.0:
			maintenance_busy = false
			# 重新检查硬件与采集状态，复用维护后验证及存档的原实现。
			main.env_observation.maintain_region(maintenance_region)
			_log(main.env_observation.message)
			_last_observation_message = main.env_observation.message
			_maintenance_hold = 0.45
	elif _maintenance_hold > 0.0:
		_maintenance_hold -= maxf(delta, 0.0)
		if _maintenance_hold <= 0.0:
			_cancel_maintenance()

func _cancel_maintenance() -> void:
	maintenance_busy = false
	maintenance_region = ""
	maintenance_progress = 0.0
	_maintenance_hold = 0.0

func _refresh_page() -> void:
	if map_canvas:
		map_canvas.visible = true
		map_canvas.queue_redraw()
	if canvas:
		canvas.queue_redraw()

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
	_advance_maintenance(delta)
	_blink_timer += delta
	var previous_angle: float = _sweep_angle
	var sweep_delta: float = delta * 0.35
	_sweep_angle = fmod(_sweep_angle + sweep_delta, TAU)
	if current_page == 1:
		var detections: Array[String] = main.env_observation.update_radar(previous_angle, sweep_delta)
		if not detections.is_empty():
			_log("\n".join(detections))
	_align_overlay()
	var feedback: String = main.env_observation.message
	if feedback != _last_observation_message:
		_log(feedback)
		_last_observation_message = feedback
	if map_canvas and map_canvas.visible:
		map_canvas.queue_redraw()
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
	# 共享背景穿过观测台，旧终端正文由 Main 隐藏。
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color.TRANSPARENT
	overlay_panel.add_theme_stylebox_override("panel", bg_style)

	_layer = CanvasLayer.new()
	var crt_node: CanvasLayer = main.get_node_or_null("CRTEffect") as CanvasLayer
	_layer.layer = crt_node.layer - 1 if crt_node else 0
	main.add_child(_layer)
	_layer.add_child(overlay_panel)
	UIManager.apply_terminal_theme(overlay_panel, main.input_field.get_theme_font_size("font_size"))
	overlay_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_panel.offset_left = 0
	overlay_panel.offset_top = 0
	overlay_panel.offset_right = 0
	overlay_panel.offset_bottom = 0

	map_canvas = EnvMapCanvas.new()
	map_canvas.viewer = self
	canvas = map_canvas
	map_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_panel.add_child(map_canvas)
	map_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	command_panel = Panel.new()
	command_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	command_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_panel.add_child(command_panel)
	command_log = RichTextLabel.new()
	command_log.bbcode_enabled = false
	command_log.scroll_active = false
	command_log.autowrap_mode = TextServer.AUTOWRAP_OFF
	command_log.add_theme_constant_override("line_separation", 4)
	command_log.add_theme_font_override("normal_font", main.output_text.get_theme_font("normal_font"))
	command_log.add_theme_color_override("default_color", Color(T.primary))
	command_panel.add_child(command_log)
	# 复用桌面底部输入框，提交由 main 分流，不重复连接信号。
	command_input = main.input_field

## 将覆盖层对齐到 OutputArea 的位置和大小（与 DocumentViewer 相同模式）
func _align_overlay() -> void:
	if overlay_panel == null or not is_instance_valid(overlay_panel):
		return
	var output_area: ScrollContainer = main.scroll_container
	var rect: Rect2 = output_area.get_global_rect()
	overlay_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	overlay_panel.position = rect.position
	overlay_panel.size = rect.size
	var scale_factor: float = minf(rect.size.x / 1920.0, rect.size.y / 950.0)
	var origin: Vector2 = (rect.size - Vector2(1920, 950) * scale_factor) * 0.5
	command_panel.position = origin + Vector2(20, 70) * scale_factor
	command_panel.size = Vector2(390, 805) * scale_factor
	command_log.position = Vector2(12, 10) * scale_factor
	var feedback_size: Vector2 = Vector2(366, 785) * scale_factor
	var feedback_font_size: int = maxi(12, int(18 * scale_factor))
	var changed: bool = command_log.size != feedback_size or command_log.get_theme_font_size("normal_font_size") != feedback_font_size
	command_log.size = feedback_size
	command_log.add_theme_font_size_override("normal_font_size", feedback_font_size)
	if changed:
		_render_feedback()
