# ============================================================
# env_task_manager.gd
# 环境监测站每日任务系统
#
# 管理玩家每天必须完成的例行检查、记录、校准、报告工作。
# 所有任务完成后才能推进到下一天。
# 任务定义来自 env_config.json，可由 .scp 故事包覆盖/追加。
# ============================================================
class_name EnvTaskManager
extends RefCounted

# ══════════════════════════════════════════
#  信号
# ══════════════════════════════════════════
signal task_completed(task_id: String)
signal task_failed(task_id: String, reason: String)
signal all_tasks_completed()
signal day_can_advance()
signal special_task_added(task_id: String, task_data: Dictionary)

# ══════════════════════════════════════════
#  引用
# ══════════════════════════════════════════
var main = null
var env_monitor: EnvMonitor = null
var T = null

# ══════════════════════════════════════════
#  任务状态
# ══════════════════════════════════════════

## 任务定义 (从 env_config.json 的 tasks 段加载)
var task_definitions: Dictionary = {}  # task_id -> {name, description, type, ...}

## 当天任务状态
var task_status: Dictionary = {}  # task_id -> "pending"/"in_progress"/"completed"/"failed"

## 任务完成时记录的数据
var task_results: Dictionary = {}  # task_id -> {readings: {}, timestamp: float, ...}

## 当天是否已完成所有必要任务
var day_complete: bool = false

## 当天是否已提交日报
var report_submitted: bool = false

## 特殊任务（由事件/触发器动态添加）
var special_tasks: Dictionary = {}  # task_id -> {name, description, ...}

## 当日任务执行顺序记录
var task_order_log: Array[String] = []

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(p_main, p_env_monitor: EnvMonitor, p_theme) -> void:
	main = p_main
	env_monitor = p_env_monitor
	T = p_theme
	# 从 env_monitor 获取任务定义
	task_definitions = env_monitor.task_defs.duplicate(true)

# ══════════════════════════════════════════
#  存档
# ══════════════════════════════════════════
func get_save_data() -> Dictionary:
	return {
		"task_status": task_status.duplicate(),
		"task_results": task_results.duplicate(true),
		"day_complete": day_complete,
		"report_submitted": report_submitted,
		"special_tasks": special_tasks.duplicate(true),
		"task_order_log": task_order_log.duplicate(),
	}

func load_save_data(data: Dictionary) -> void:
	if data.has("task_status"):
		task_status = data["task_status"]
	if data.has("task_results"):
		task_results = data["task_results"]
	day_complete = data.get("day_complete", false)
	report_submitted = data.get("report_submitted", false)
	if data.has("special_tasks"):
		special_tasks = data["special_tasks"]
	if data.has("task_order_log"):
		task_order_log.clear()
		for t in data["task_order_log"]:
			task_order_log.append(str(t))

# ══════════════════════════════════════════
#  每日重置
# ══════════════════════════════════════════
func reset_for_new_day() -> void:
	task_status.clear()
	task_results.clear()
	task_order_log.clear()
	special_tasks.clear()
	day_complete = false
	report_submitted = false
	# 刷新任务定义（env_monitor 可能被故事包覆盖了）
	task_definitions = env_monitor.task_defs.duplicate(true)
	# 初始化所有任务为 pending
	for tid in task_definitions.keys():
		task_status[tid] = "pending"

# ══════════════════════════════════════════
#  任务执行
# ══════════════════════════════════════════

func begin_task(task_id: String) -> Dictionary:
	## 开始执行一项任务，返回任务相关的数据
	## 返回 {"success": bool, "message": String, "data": Dictionary}
	var tdef: Dictionary = _get_task_def(task_id)
	if tdef.is_empty():
		return {"success": false, "message": "未知任务: " + task_id, "data": {}}

	# 检查前置任务
	if tdef.has("requires_tasks"):
		for req_id in tdef["requires_tasks"]:
			if task_status.get(str(req_id), "pending") != "completed":
				var req_def: Dictionary = _get_task_def(str(req_id))
				var req_name: String = str(req_def.get("name", req_id))
				return {"success": false, "message": "前置任务未完成: " + req_name, "data": {}}

	task_status[task_id] = "in_progress"
	var result: Dictionary = {"success": true, "message": "", "data": {}}

	match str(tdef.get("type", "")):
		"inspection":
			result = _execute_inspection(task_id, tdef)
		"recording":
			result = _execute_recording(task_id, tdef)
		"maintenance":
			result = _execute_calibration(task_id, tdef)
		"analysis":
			result = _execute_anomaly_check(task_id, tdef)
		"report":
			result = _execute_report(task_id, tdef)
		"special":
			result = _execute_special(task_id, tdef)
		_:
			result = _execute_generic(task_id, tdef)

	return result

func complete_task(task_id: String, data: Dictionary = {}) -> void:
	## 标记任务完成
	task_status[task_id] = "completed"
	task_results[task_id] = data
	task_order_log.append(task_id)
	task_completed.emit(task_id)
	# ★ 绩效加分
	if main.get("perf_mgr"):
		main.perf_mgr.add_score(1, "daily")
	_check_all_completed()

func fail_task(task_id: String, reason: String = "") -> void:
	task_status[task_id] = "failed"
	task_failed.emit(task_id, reason)

# ══════════════════════════════════════════
#  各类任务执行逻辑
# ══════════════════════════════════════════

func _execute_inspection(task_id: String, tdef: Dictionary) -> Dictionary:
	## 设备状态检查 —— 列出所有传感器的在线/离线/退化状态
	var sensors_to_check: Array = []
	if tdef.has("sensors_to_check"):
		sensors_to_check = tdef["sensors_to_check"]
	else:
		sensors_to_check = env_monitor.sensors.keys()

	var report_lines: Array = []
	var issues_found: int = 0
	var offline_sensors: Array = []

	for sid in sensors_to_check:
		var cfg: Dictionary = env_monitor.get_sensor_config(str(sid))
		var status: String = env_monitor.sensor_status.get(str(sid), "unknown")
		var name: String = str(cfg.get("name", sid))
		var status_text: String
		match status:
			"online":
				status_text = "[在线]"
			"degraded":
				status_text = "[退化]"
				issues_found += 1
			"offline":
				status_text = "[离线]"
				issues_found += 1
				offline_sensors.append(str(sid))
			_:
				status_text = "[未知]"
				issues_found += 1
		report_lines.append({"sensor": str(sid), "name": name, "status": status, "status_text": status_text})

	var result_data: Dictionary = {
		"sensors_checked": report_lines,
		"issues_found": issues_found,
		"offline_sensors": offline_sensors,
		"timestamp": env_monitor.current_hour,
	}

	complete_task(task_id, result_data)
	return {"success": true, "message": "", "data": result_data}

func _execute_recording(task_id: String, tdef: Dictionary) -> Dictionary:
	## 数据记录 —— 读取指定传感器组的当前值
	var sensor_ids: Array = tdef.get("sensors", [])
	var readings: Dictionary = {}
	var anomalies: Array = []

	for sid_raw in sensor_ids:
		var sid: String = str(sid_raw)
		var val: float = env_monitor.get_reading(sid)
		var cfg: Dictionary = env_monitor.get_sensor_config(sid)
		var trend: String = env_monitor.get_sensor_trend(sid)
		readings[sid] = {
			"value": val,
			"unit": str(cfg.get("unit", "")),
			"name": str(cfg.get("name", sid)),
			"status": env_monitor.sensor_status.get(sid, "unknown"),
			"trend": trend,
		}
		# 检查是否在正常范围内
		if not is_nan(val):
			var month_idx: int = env_monitor._get_current_month() - 1
			var base_arr = env_monitor.baselines.get(sid, [])
			if base_arr is Array and base_arr.size() > month_idx:
				var expected: float = float(base_arr[month_idx])
				var deviation: float = absf(val - expected)
				var threshold: float = expected * 0.3 if absf(expected) > 1 else 5.0
				if deviation > threshold:
					readings[sid]["anomalous"] = true
					anomalies.append(sid)

	var result_data: Dictionary = {
		"readings": readings,
		"anomalies_found": anomalies,
		"timestamp": env_monitor.current_hour,
		"category": str(tdef.get("sensors", ["unknown"])[0] if tdef.get("sensors", []).size() > 0 else "unknown"),
	}

	complete_task(task_id, result_data)
	return {"success": true, "message": "", "data": result_data}

func _execute_calibration(task_id: String, tdef: Dictionary) -> Dictionary:
	## 仪器校准 —— 重置校准偏移
	var to_calibrate: Array = tdef.get("sensors_to_calibrate", [])
	var calibration_results: Dictionary = {}

	for sid_raw in to_calibrate:
		var sid: String = str(sid_raw)
		var old_offset: float = env_monitor.calibration_offsets.get(sid, 0.0)
		env_monitor.reset_calibration(sid)
		calibration_results[sid] = {
			"name": str(env_monitor.get_sensor_config(sid).get("name", sid)),
			"old_offset": old_offset,
			"new_offset": 0.0,
			"corrected": absf(old_offset) > 0.01,
		}

	var result_data: Dictionary = {
		"calibrations": calibration_results,
		"timestamp": env_monitor.current_hour,
	}

	complete_task(task_id, result_data)
	return {"success": true, "message": "", "data": result_data}

func _execute_anomaly_check(_task_id: String, _tdef: Dictionary) -> Dictionary:
	## 异常检查 —— 审查所有参数，确认异常
	var confirmed: Array[Dictionary] = env_monitor.confirm_anomalies()
	var pending: Array[Dictionary] = env_monitor.get_pending_anomalies()

	var result_data: Dictionary = {
		"confirmed_anomalies": confirmed,
		"remaining_pending": pending,
		"total_anomalies_today": confirmed.size(),
		"timestamp": env_monitor.current_hour,
	}

	complete_task(_task_id, result_data)
	return {"success": true, "message": "", "data": result_data}

func _execute_report(task_id: String, _tdef: Dictionary) -> Dictionary:
	## 日报提交 —— 编译所有数据生成报告
	var readings: Dictionary = env_monitor.get_all_readings()
	var anomalies: Array[Dictionary] = env_monitor.get_detected_anomalies()
	var events: Dictionary = env_monitor.get_active_events()

	var report_data: Dictionary = {
		"day": env_monitor.current_day,
		"hour": env_monitor.get_current_hour_display(),
		"weather": env_monitor.get_weather_name(),
		"readings": readings,
		"anomaly_count": anomalies.size(),
		"anomalies": anomalies,
		"active_events": events.size(),
		"tasks_completed": _count_completed(),
		"tasks_total": _count_required(),
		"operator": main.user_mgr.get_username() if main and main.get("user_mgr") else "unknown",
		"timestamp": env_monitor.current_hour,
	}

	report_submitted = true
	complete_task(task_id, report_data)
	return {"success": true, "message": "", "data": report_data}

func _execute_special(task_id: String, tdef: Dictionary) -> Dictionary:
	## 特殊任务（由事件触发的额外任务）
	var result_data: Dictionary = {
		"task_id": task_id,
		"description": tdef.get("description", ""),
		"timestamp": env_monitor.current_hour,
	}
	complete_task(task_id, result_data)
	return {"success": true, "message": "", "data": result_data}

func _execute_generic(task_id: String, tdef: Dictionary) -> Dictionary:
	var result_data: Dictionary = {
		"task_id": task_id,
		"description": tdef.get("description", ""),
		"timestamp": env_monitor.current_hour,
	}
	complete_task(task_id, result_data)
	return {"success": true, "message": "", "data": result_data}

# ══════════════════════════════════════════
#  特殊任务（动态添加）
# ══════════════════════════════════════════
func add_special_task(task_id: String, task_data: Dictionary) -> void:
	## 由事件系统或故事包动态添加特殊任务
	special_tasks[task_id] = task_data
	task_definitions[task_id] = task_data
	task_status[task_id] = "pending"
	special_task_added.emit(task_id, task_data)

func remove_special_task(task_id: String) -> void:
	special_tasks.erase(task_id)
	task_definitions.erase(task_id)
	task_status.erase(task_id)

# ══════════════════════════════════════════
#  查询接口
# ══════════════════════════════════════════
func get_task_list() -> Array[Dictionary]:
	## 返回按 order 排序的任务列表
	var result: Array[Dictionary] = []
	for tid in task_definitions.keys():
		var tdef: Dictionary = task_definitions[tid].duplicate()
		tdef["id"] = tid
		tdef["status"] = task_status.get(tid, "pending")
		tdef["is_special"] = special_tasks.has(tid)
		result.append(tdef)
	# 按 order 排序
	result.sort_custom(func(a, b): return int(a.get("order", 99)) < int(b.get("order", 99)))
	return result

func get_task_status(task_id: String) -> String:
	return task_status.get(task_id, "unknown")

func get_task_result(task_id: String) -> Dictionary:
	return task_results.get(task_id, {})

func is_task_completed(task_id: String) -> bool:
	return task_status.get(task_id, "") == "completed"

func is_all_required_completed() -> bool:
	for tid in task_definitions.keys():
		var tdef: Dictionary = task_definitions[tid]
		if tdef.get("required", false):
			if task_status.get(tid, "pending") != "completed":
				return false
	return true

func can_advance_day() -> bool:
	return is_all_required_completed() and report_submitted

func get_progress() -> Dictionary:
	var completed: int = _count_completed()
	var total: int = _count_required()
	return {
		"completed": completed,
		"total": total,
		"percentage": (float(completed) / maxf(float(total), 1.0)) * 100.0,
		"can_advance": can_advance_day(),
	}

func _count_completed() -> int:
	var count: int = 0
	for tid in task_definitions.keys():
		if task_definitions[tid].get("required", false) and task_status.get(tid) == "completed":
			count += 1
	return count

func _count_required() -> int:
	var count: int = 0
	for tid in task_definitions.keys():
		if task_definitions[tid].get("required", false):
			count += 1
	return count

func _get_task_def(task_id: String) -> Dictionary:
	if task_definitions.has(task_id):
		return task_definitions[task_id]
	if special_tasks.has(task_id):
		return special_tasks[task_id]
	return {}

func _check_all_completed() -> void:
	if is_all_required_completed():
		all_tasks_completed.emit()
		# ★ 全部任务完成的全勤奖励
		if main.get("perf_mgr"):
			main.perf_mgr.add_score(1, "bonus")
		if can_advance_day():
			day_can_advance.emit()

# ══════════════════════════════════════════
#  格式化输出辅助
# ══════════════════════════════════════════
func format_task_checklist(theme_colors: Dictionary) -> String:
	## 生成终端可用的任务清单 BBCode 文本
	var primary: String = str(theme_colors.get("primary", "#00ff00"))
	var muted: String = str(theme_colors.get("muted", "#666666"))
	var success: String = str(theme_colors.get("success", "#00ff00"))
	var warning: String = str(theme_colors.get("warning", "#ffcc00"))
	var error: String = str(theme_colors.get("error", "#ff4444"))

	var tasks: Array[Dictionary] = get_task_list()
	var progress: Dictionary = get_progress()

	var lines: Array = []
	lines.append("[color=%s]═══ 每日任务清单 (%s) ═══[/color]" % [primary, env_monitor.get_day_display()])
	lines.append("[color=%s]进度: %d/%d (%.0f%%)[/color]\n" % [
		muted, progress["completed"], progress["total"], progress["percentage"]])

	for t in tasks:
		var status_icon: String
		var color: String
		match str(t.get("status", "pending")):
			"completed":
				status_icon = "[x]"
				color = success
			"in_progress":
				status_icon = "[>]"
				color = warning
			"failed":
				status_icon = "[!]"
				color = error
			_:
				status_icon = "[ ]"
				color = muted
		var special_tag: String = " [特殊]" if t.get("is_special", false) else ""
		var req_tag: String = " *" if t.get("required", false) else ""
		lines.append("[color=%s]  %s %s%s%s[/color]" % [color, status_icon, str(t.get("name", t.get("id", "?"))), req_tag, special_tag])
		if str(t.get("status", "pending")) == "pending" and t.has("command"):
			lines.append("[color=%s]      命令: %s[/color]" % [muted, str(t["command"])])

	lines.append("")
	if progress["can_advance"]:
		lines.append("[color=%s]所有必要任务已完成。输入 [b]env advance[/b] 进入下一天。[/color]" % success)
	else:
		lines.append("[color=%s]完成所有标 * 的必要任务后即可推进。[/color]" % muted)

	return "\n".join(lines)

func format_recording_result(data: Dictionary, theme_colors: Dictionary) -> String:
	## 格式化数据记录结果为终端输出
	var primary: String = str(theme_colors.get("primary", "#00ff00"))
	var muted: String = str(theme_colors.get("muted", "#666666"))
	var warning: String = str(theme_colors.get("warning", "#ffcc00"))
	var error: String = str(theme_colors.get("error", "#ff4444"))

	var lines: Array = []
	var readings: Dictionary = data.get("readings", {})

	lines.append("[color=%s]── 数据记录完成 ──[/color]" % primary)
	lines.append("[color=%s]时间: %s[/color]\n" % [muted, env_monitor.get_current_hour_display()])

	for sid in readings.keys():
		var r: Dictionary = readings[sid]
		var val = r.get("value", 0)
		var val_str: String = "N/A" if (val is float and is_nan(val)) else _fmt_value(val, str(r.get("unit", "")))
		var trend_icon: String = _trend_icon(str(r.get("trend", "stable")))
		var color: String = error if r.get("anomalous", false) else primary
		var status_tag: String = ""
		if str(r.get("status", "online")) != "online":
			status_tag = " [%s]" % str(r["status"])
			color = warning
		lines.append("[color=%s]  %-12s %s %s%s[/color]" % [
			color, str(r.get("name", sid)), val_str, trend_icon, status_tag])

	var anomalies: Array = data.get("anomalies_found", [])
	if anomalies.size() > 0:
		lines.append("\n[color=%s]⚠ 检测到 %d 个异常读数[/color]" % [warning, anomalies.size()])

	return "\n".join(lines)

func format_inspection_result(data: Dictionary, theme_colors: Dictionary) -> String:
	## 格式化设备检查结果
	var primary: String = str(theme_colors.get("primary", "#00ff00"))
	var muted: String = str(theme_colors.get("muted", "#666666"))
	var success: String = str(theme_colors.get("success", "#00ff00"))
	var warning: String = str(theme_colors.get("warning", "#ffcc00"))
	var error: String = str(theme_colors.get("error", "#ff4444"))

	var lines: Array = []
	lines.append("[color=%s]── 设备状态检查 ──[/color]\n" % primary)

	var checks: Array = data.get("sensors_checked", [])
	for c in checks:
		var color: String
		match str(c.get("status", "")):
			"online":
				color = success
			"degraded":
				color = warning
			"offline":
				color = error
			_:
				color = muted
		lines.append("[color=%s]  %-12s %s[/color]" % [color, str(c.get("name", "")), str(c.get("status_text", ""))])

	var issues: int = int(data.get("issues_found", 0))
	if issues == 0:
		lines.append("\n[color=%s]所有传感器运行正常。[/color]" % success)
	else:
		lines.append("\n[color=%s]发现 %d 个问题。使用 env repair <传感器> 尝试修复。[/color]" % [warning, issues])

	return "\n".join(lines)

func format_calibration_result(data: Dictionary, theme_colors: Dictionary) -> String:
	var primary: String = str(theme_colors.get("primary", "#00ff00"))
	var muted: String = str(theme_colors.get("muted", "#666666"))
	var success: String = str(theme_colors.get("success", "#00ff00"))

	var lines: Array = []
	lines.append("[color=%s]── 仪器校准 ──[/color]\n" % primary)

	var cals: Dictionary = data.get("calibrations", {})
	for sid in cals.keys():
		var c: Dictionary = cals[sid]
		var corrected_text: String = "已修正 (偏移 %.3f)" % float(c.get("old_offset", 0)) if c.get("corrected", false) else "无漂移"
		lines.append("[color=%s]  %-12s %s[/color]" % [
			success if c.get("corrected", false) else muted,
			str(c.get("name", sid)), corrected_text])

	lines.append("\n[color=%s]校准完成。[/color]" % success)
	return "\n".join(lines)

func format_anomaly_result(data: Dictionary, theme_colors: Dictionary) -> String:
	var primary: String = str(theme_colors.get("primary", "#00ff00"))
	var muted: String = str(theme_colors.get("muted", "#666666"))
	var warning: String = str(theme_colors.get("warning", "#ffcc00"))
	var error: String = str(theme_colors.get("error", "#ff4444"))

	var lines: Array = []
	lines.append("[color=%s]── 异常检查报告 ──[/color]\n" % primary)

	var anomalies: Array = data.get("confirmed_anomalies", [])
	if anomalies.size() == 0:
		lines.append("[color=%s]当日未检测到异常。所有参数在正常范围内。[/color]" % muted)
	else:
		for a in anomalies:
			var sev_color: String
			match str(a.get("severity", "info")):
				"critical":
					sev_color = error
				"warning", "anomalous":
					sev_color = warning
				_:
					sev_color = muted
			lines.append("[color=%s]  [%s] %s[/color]" % [sev_color, str(a.get("severity", "info")).to_upper(), str(a.get("name", "未知异常"))])
			lines.append("[color=%s]    %s[/color]" % [muted, str(a.get("report", ""))])

	lines.append("\n[color=%s]共 %d 项异常已记录。[/color]" % [primary, anomalies.size()])
	return "\n".join(lines)

func format_daily_report(data: Dictionary, theme_colors: Dictionary) -> String:
	var primary: String = str(theme_colors.get("primary", "#00ff00"))
	var muted: String = str(theme_colors.get("muted", "#666666"))
	var success: String = str(theme_colors.get("success", "#00ff00"))

	var readings: Dictionary = data.get("readings", {})

	var lines: Array = []
	lines.append("[color=%s]╔══════════════════════════════════════════════╗[/color]" % primary)
	lines.append("[color=%s]║  Site-██ 环境监测日报  %s              ║[/color]" % [primary, env_monitor.get_day_display()])
	lines.append("[color=%s]║  时间: %s  天气: %s[/color]" % [primary, str(data.get("hour", "00:00")), str(data.get("weather", "未知"))])
	lines.append("[color=%s]╠══════════════════════════════════════════════╣[/color]" % primary)

	# 大气参数
	lines.append("[color=%s]║ 【大气参数】[/color]" % primary)
	lines.append("[color=%s]║  气温: %s°C  湿度: %s%%[/color]" % [muted,
		_fmt_r(readings, "air_temp"), _fmt_r(readings, "humidity")])
	lines.append("[color=%s]║  气压: %shPa  风速: %sm/s[/color]" % [muted,
		_fmt_r(readings, "pressure"), _fmt_r(readings, "wind_speed")])
	lines.append("[color=%s]║  风向: %s  能见度: %skm[/color]" % [muted,
		env_monitor.get_wind_direction_name(), _fmt_r(readings, "visibility")])

	# 海洋参数
	lines.append("[color=%s]╠══════════════════════════════════════════════╣[/color]" % primary)
	lines.append("[color=%s]║ 【海洋参数】[/color]" % primary)
	lines.append("[color=%s]║  海温: %s°C  潮位: %sm[/color]" % [muted,
		_fmt_r(readings, "sea_temp"), _fmt_r(readings, "tide_level")])
	lines.append("[color=%s]║  浪高: %sm  盐度: %sPSU[/color]" % [muted,
		_fmt_r(readings, "wave_height"), _fmt_r(readings, "salinity")])

	# 地球物理
	lines.append("[color=%s]╠══════════════════════════════════════════════╣[/color]" % primary)
	lines.append("[color=%s]║ 【地球物理】[/color]" % primary)
	lines.append("[color=%s]║  磁场: %snT  辐射: %sμSv/h[/color]" % [muted,
		_fmt_r(readings, "mag_field"), _fmt_r(readings, "radiation")])

	# 大气成分
	lines.append("[color=%s]╠══════════════════════════════════════════════╣[/color]" % primary)
	lines.append("[color=%s]║ 【大气成分】[/color]" % primary)
	lines.append("[color=%s]║  O2: %s%%  CO2: %sppm[/color]" % [muted,
		_fmt_r(readings, "o2_concentration"), _fmt_r(readings, "co2_concentration")])

	# 汇总
	lines.append("[color=%s]╠══════════════════════════════════════════════╣[/color]" % primary)
	lines.append("[color=%s]║  异常事件: %d  活跃事件: %d[/color]" % [muted,
		int(data.get("anomaly_count", 0)), int(data.get("active_events", 0))])
	lines.append("[color=%s]║  任务完成: %d/%d  操作员: %s[/color]" % [muted,
		int(data.get("tasks_completed", 0)), int(data.get("tasks_total", 0)), str(data.get("operator", ""))])
	lines.append("[color=%s]╚══════════════════════════════════════════════╝[/color]" % primary)

	lines.append("\n[color=%s]日报已提交至总部。[/color]" % success)
	return "\n".join(lines)

# ══════════════════════════════════════════
#  工具
# ══════════════════════════════════════════
func _fmt_value(val, unit: String) -> String:
	if val is float:
		if absf(val) >= 1000:
			return "%d %s" % [roundi(val), unit]
		return "%.1f %s" % [val, unit]
	return "%s %s" % [str(val), unit]

func _fmt_r(readings: Dictionary, key: String) -> String:
	var val = readings.get(key, 0)
	if val is float:
		if is_nan(val):
			return "N/A"
		if absf(val) >= 1000:
			return str(roundi(val))
		return "%.1f" % val
	return str(val)

func _trend_icon(trend: String) -> String:
	match trend:
		"rising":
			return "↑"
		"falling":
			return "↓"
		"stable":
			return "→"
		_:
			return "?"

# ══════════════════════════════════════════
#  玩家专属存档（跨磁盘/跨会话持久化）
# ══════════════════════════════════════════
func _get_task_progress_path() -> String:
	if main == null:
		return ""
	if not main.get("user_mgr") or not main.user_mgr.is_logged_in:
		return ""
	if main.get("save_mgr") == null:
		return ""
	var user_dir: String = main.save_mgr.get_game_root_dir() + "saves/" + main.user_mgr.get_username() + "/"
	return user_dir + "env_task_progress.json"

func save_task_progress() -> void:
	var path: String = _get_task_progress_path()
	if path.is_empty():
		return
	var dir_path: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(get_save_data(), "\t"))
		file.close()

func load_task_progress() -> bool:
	var path: String = _get_task_progress_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not (json.data is Dictionary):
		file.close()
		return false
	file.close()
	load_save_data(json.data)
	return true
