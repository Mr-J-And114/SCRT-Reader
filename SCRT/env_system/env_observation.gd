class_name EnvObservation
extends RefCounted
## 观测台流程。正式数据由 EnvTaskManager 存档，debug 预览单独留在内存。
const CONFIG_PATH: String = "res://data/env_observation.json"
const BASE_TASKS: Array[String] = ["equipment_check", "weather_reading", "ocean_reading", "geophysics_reading", "composition_reading", "anomaly_check"]
var main = null
var monitor: EnvMonitor = null
var tasks: EnvTaskManager = null
var config: Dictionary = {}
var preview: Dictionary = {}
var debug_scenario: String = ""
var capture_remaining: float = 0.0
var capture_duration: float = 2.4
var message: String = "选择采集，生成今日环境快照。"
var selected_issue: int = 0
var suspended: bool = false
var _capture_day: int = -1
var _capture_owner: String = ""

func setup(p_main, p_monitor: EnvMonitor, p_tasks: EnvTaskManager) -> void:
	main = p_main
	monitor = p_monitor
	tasks = p_tasks
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			config = parsed
	capture_duration = maxf(0.2, float(config.get("capture_seconds", 2.4)))

func state() -> Dictionary:
	return preview if not debug_scenario.is_empty() else tasks.observation_data

func is_collected() -> bool:
	return bool(state().get("collected", false))

func is_submitted() -> bool:
	return bool(state().get("submitted", false)) or (debug_scenario.is_empty() and tasks.report_submitted)

func is_collecting() -> bool:
	return capture_remaining > 0.0

func begin_capture() -> void:
	if is_collecting():
		return
	if is_collected() or is_submitted():
		message = "今日已有记录；疑点可单独复测，无须重做采集。"
		return
	capture_remaining = capture_duration
	_capture_day = monitor.current_day
	_capture_owner = main.user_mgr.get_username()
	message = "正在采集固定观测设备的数据……"

func process(delta: float) -> void:
	if suspended or not main.user_mgr.is_logged_in:
		return
	if is_collecting():
		if _capture_day != monitor.current_day or _capture_owner != main.user_mgr.get_username():
			capture_remaining = 0.0
			message = "日期或账号已改变，请重新采集。"
			return
		capture_remaining = maxf(0.0, capture_remaining - delta)
		if capture_remaining == 0.0:
			_finish_capture()
	if debug_scenario.is_empty() and bool(state().get("notify_pending", false)):
		if main.is_terminal_covered() or main._command_running:
			return
		if main.comm_mgr and (main.comm_mgr.is_active or main.comm_mgr.is_call_ringing()):
			return
		if main.dial_mgr and main.dial_mgr.is_active():
			return
		state()["notify_pending"] = false
		tasks.save_task_progress()
		# 兼容 Day0 的完成回电：现在以提交日报为完成节点。
		if main.daily_dialogue_mgr:
			main.daily_dialogue_mgr.trigger_scan_complete(monitor.current_day)
			if not issues().is_empty():
				main.daily_dialogue_mgr.trigger_anomaly(monitor.current_day)

func _safe_readings() -> Dictionary:
	var values: Dictionary = {}
	for sid in monitor.sensors:
		var value: float = monitor.get_reading(str(sid))
		values[sid] = value if is_finite(value) else null
	return values

func _finish_capture() -> void:
	var data: Dictionary = state()
	data["day"] = monitor.current_day
	data["hour"] = monitor.get_current_hour_display()
	data["weather"] = monitor.get_weather_name()
	data["readings"] = _safe_readings()
	data["collected"] = true
	data["submitted"] = false
	data["issues"] = _build_issues()
	selected_issue = 0
	if not debug_scenario.is_empty():
		data["issues"] = _preview_issues()
	else:
		# 无自动校准。旧任务 ID 保留，方便现有剧情与 Mod 查询。
		for task_id in BASE_TASKS:
			if tasks.task_definitions.has(task_id) and not tasks.is_task_completed(task_id):
				tasks.begin_task(task_id)
		if tasks.task_definitions.has("calibration") and not tasks.is_task_completed("calibration"):
			tasks.complete_task("calibration", {"review_only": true, "message": "检查偏移，未自动修改读数"})
		_persist()
	message = "采集完成：%s。查看摘要后可提交日报。" % ("暂无待查项目" if issues().is_empty() else "发现 %d 个待核对项目" % issues().size())

func _build_issues() -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	for anomaly in monitor.get_pending_anomalies() + monitor.get_detected_anomalies():
		if int(anomaly.get("day", monitor.current_day)) != monitor.current_day:
			continue
		var id: String = str(anomaly.get("anomaly_id", ""))
		if seen.has(id):
			continue
		seen[id] = true
		var sid: String = str(anomaly.get("sensor", ""))
		result.append({"id": id, "name": str(anomaly.get("name", id)), "sensor": sid,
			"kind": "observation", "note": "读数变化尚未定性；可复测并保留记录。",
			"first": _safe_value(sid), "region": _sensor_region(sid), "marked": false})
	for sid in monitor.sensors:
		var status: String = str(monitor.sensor_status.get(sid, "offline"))
		var offset: float = float(monitor.calibration_offsets.get(sid, 0.0))
		if status in ["offline", "degraded", "malfunction"] or absf(offset) > 0.02:
			result.append({"id": "device_" + str(sid), "name": str(monitor.get_sensor_config(str(sid)).get("name", sid)) + "设备疑点",
				"sensor": sid, "kind": "device", "note": "设备状态 %s；校准偏移 %.3f。先复测再处理。" % [status, offset],
				"first": _safe_value(str(sid)), "region": _sensor_region(str(sid)), "marked": false})
	return result

func _safe_value(sid: String) -> Variant:
	var value: float = monitor.get_reading(sid)
	return value if is_finite(value) else null

func _sensor_region(sid: String) -> String:
	var category: String = str(monitor.get_sensor_config(sid).get("category", "atmosphere"))
	return category

func issues() -> Array:
	return state().get("issues", [])

func current_issue() -> Dictionary:
	var items: Array = issues()
	if items.is_empty():
		return {}
	selected_issue = clampi(selected_issue, 0, items.size() - 1)
	return items[selected_issue]

func retest() -> void:
	var issue: Dictionary = current_issue()
	if issue.is_empty():
		message = "当前没有待复测项目。"
		return
	if is_submitted():
		message = "日报已归档，保留提交时的证据；下次采集再记录变化。"
		return
	if issue.has("retest"):
		message = "该疑点已有复测记录，可查看或标记关注。"
		return
	var sid: String = str(issue.get("sensor", ""))
	var value: Variant = _safe_value(sid)
	if not debug_scenario.is_empty():
		value = 1007.0 if debug_scenario == "device" else 48220.0
	issue["retest"] = {"value": value, "hour": monitor.get_current_hour_display(), "trend": monitor.get_sensor_trend(sid)}
	var first: Variant = issue.get("first")
	if value == null:
		issue["retest_note"] = "复测仍无有效读数；设备无数据，按未确认记录即可。"
	elif first != null:
		issue["retest_note"] = "首次 %s → 复测 %s；变化 %+.2f。" % [format_value(first), format_value(value), float(value) - float(first)]
	else:
		issue["retest_note"] = "恢复读数 %s，首次采集无有效读数。" % format_value(value)
	message = str(issue["retest_note"])
	_persist()

func mark_issue() -> void:
	if is_submitted():
		message = "日报已归档，无法改写提交时的备注。"
		return
	var issue: Dictionary = current_issue()
	if issue.is_empty():
		message = "暂无需要标记的疑点。"
		return
	issue["marked"] = not bool(issue.get("marked", false))
	message = "已标记关注，提交时注明尚未确认。" if issue["marked"] else "已取消关注标记。"
	_persist()

func calibrate_issue() -> void:
	var issue: Dictionary = current_issue()
	if issue.get("kind", "") != "device" or not issue.has("retest") or is_submitted():
		message = "仅对已复测的设备疑点提供校准；不会自动消除环境变化。"
		return
	var sid: String = str(issue.get("sensor", ""))
	if monitor.sensor_status.get(sid, "offline") == "offline":
		message = "设备离线；校准不能替代维修，可按尚未确认提交。"
		return
	if debug_scenario.is_empty():
		monitor.reset_calibration(sid)
	issue["calibrated"] = true
	message = "已校准设备偏移；首次采集和复测证据保持原样。"
	_persist()

func submit() -> void:
	if is_collecting() or not is_collected():
		message = "请先完成今日采集，再查看摘要并提交。"
		return
	if is_submitted():
		message = "今日日报已提交，不会重复计分。"
		return
	var gap_before: int = main.perf_mgr.overtime_gap if main.perf_mgr else 0
	if debug_scenario.is_empty():
		var result: Dictionary = tasks.begin_task("daily_report")
		if not result.get("success", false):
			message = str(result.get("message", "提交失败"))
			return
	var data: Dictionary = state()
	data["submitted"] = true
	data["submitted_hour"] = monitor.get_current_hour_display()
	data["score_note"] = "调试预览，不计分" if not debug_scenario.is_empty() else ("教程日：由剧情记录绩效" if monitor.current_day == 0 else "日报首次提交 +1 日常绩效")
	if debug_scenario.is_empty() and monitor.current_day > 0 and main.perf_mgr:
		var filled: int = maxi(0, gap_before - main.perf_mgr.overtime_gap)
		data["score_amount"] = 1
		data["overtime_filled"] = filled
		if filled > 0:
			data["score_note"] = "日报首次提交 +1，已用于补绩效缺口"
	if debug_scenario.is_empty():
		data["notify_pending"] = true
		var archive: Array = tasks.observation_history
		archive.append(data.duplicate(true))
		while archive.size() > 30:
			archive.pop_front()
		_persist()
	message = "日报已提交并归档；未确认的变化已如实记录。退出观测台后接收后续通讯。"

func _persist() -> void:
	if not debug_scenario.is_empty():
		return
	tasks.save_task_progress()
	monitor.save_env_progress()
	if main.perf_mgr:
		main.perf_mgr.save_progress()

func migrate_legacy() -> void:
	# 老存档已提交的日报只补字段，不执行任务，不再次发奖或触发剧情。
	if not debug_scenario.is_empty() or is_collected() or not tasks.report_submitted:
		return
	var old: Dictionary = tasks.task_results.get("daily_report", {})
	tasks.observation_data = {"day": old.get("day", monitor.current_day), "hour": old.get("hour", "--:--"),
		"weather": old.get("weather", "旧记录"), "readings": old.get("readings", {}).duplicate(true),
		"issues": [], "collected": true, "submitted": true, "score_note": "旧版日报：保留原绩效", "legacy": true}
	tasks.observation_history.append(tasks.observation_data.duplicate(true))
	while tasks.observation_history.size() > 30:
		tasks.observation_history.pop_front()
	_persist()

func contacts() -> Array:
	if debug_scenario == "sea":
		return [
			{"id": "V-03", "kind": "ship", "position": [0.48, -0.18], "track": [[0.24, -0.08], [0.36, -0.13], [0.48, -0.18]], "source": "调试浮标回报"},
			{"id": "A-02", "kind": "aircraft", "position": [-0.3, 0.55], "track": [[-0.5, 0.6], [-0.3, 0.55]], "source": "调试航迹"},
			{"id": "历史雷区（调试）", "kind": "mine", "position": [0.5, 0.55], "source": "调试历史记录，不是实时探测"}]
	return config.get("contacts", [])

func summary() -> Array[String]:
	var lines: Array[String] = []
	var values: Dictionary = state().get("readings", {})
	for sid in ["air_temp", "visibility", "wind_speed", "wave_height"]:
		var sensor: Dictionary = monitor.get_sensor_config(sid)
		var text: String = "%s  %s %s" % [sensor.get("name", sid), format_value(values.get(sid)), sensor.get("unit", "")]
		if not tasks.observation_history.is_empty() and values.get(sid) != null:
			var previous: Dictionary = tasks.observation_history.back().get("readings", {})
			if previous.get(sid) != null and int(tasks.observation_history.back().get("day", -1)) != monitor.current_day:
				text += "  (%+.1f)" % (float(values[sid]) - float(previous[sid]))
		lines.append(text)
	return lines

static func format_value(value: Variant) -> String:
	return "无数据" if value == null else "%.2f" % float(value)

func set_preview(scenario: String) -> void:
	debug_scenario = "" if scenario == "clear" else scenario
	preview = {}
	capture_remaining = 0.0
	selected_issue = 0
	message = "已退出调试预览，恢复玩家数据。" if debug_scenario.is_empty() else "调试预览：不会写入玩家数据、计分或触发剧情。"
	if not debug_scenario.is_empty():
		_finish_capture()

func _preview_issues() -> Array:
	match debug_scenario:
		"device":
			return [{"id": "preview_device", "name": "气压计偏移（调试）", "sensor": "pressure", "kind": "device", "region": "atmosphere", "first": 1012.0, "note": "模拟设备偏移；复测后可尝试校准。", "marked": false}]
		"mystery":
			return [{"id": "preview_mystery", "name": "磁场持续变化（调试）", "sensor": "mag_field", "kind": "observation", "region": "geophysics", "first": 48100.0, "note": "模拟未解变化；复测并保留未确认记录。", "marked": false}]
	return []
