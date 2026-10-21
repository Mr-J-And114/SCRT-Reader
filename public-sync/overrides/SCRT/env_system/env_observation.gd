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
# 独立内存预览：不进入 state()/任务/存档，时钟只推进测试目标。
var traffic_active: bool = false
var traffic_paused: bool = false
var traffic_scale: float = 10.0
var traffic_elapsed: float = 0.0
var traffic_preset: String = "all"
var _traffic_owner: String = ""
var _traffic_day: int = -1
var _traffic_routes: Array[Dictionary] = []
var _radar_samples: Dictionary = {}
var _radar_day: int = -1
var _radar_owner: String = ""

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
	if traffic_active:
		if _traffic_owner != main.user_mgr.get_username() or _traffic_day != monitor.current_day:
			clear_traffic()
		elif not traffic_paused:
			traffic_elapsed += delta * traffic_scale
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
	data["reference"] = monitor.get_weather_reference_snapshot()
	data["sample_sequence"] = monitor.reading_sequence
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
	# 日剧情可记录尚未达到报警线的观测变化，不把原因定性为设备故障。
	for event_id in monitor.active_events:
		var observation: Dictionary = monitor.event_defs.get(event_id, {}).get("observation", {})
		var sid: String = str(observation.get("sensor", ""))
		if sid.is_empty() or not monitor.sensors.has(sid):
			continue
		var id: String = "story_observation_" + str(event_id)
		seen[id] = true
		result.append({"id": id, "name": str(monitor.active_events[event_id].get("name", event_id)),
			"sensor": sid, "kind": "observation", "observation": true, "record_only": true,
			"note": str(observation.get("note", "读数变化已记录，原因尚未确定。")),
			"first": _safe_value(sid), "region": _sensor_region(sid), "marked": false})
	for anomaly in monitor.get_pending_anomalies() + monitor.get_detected_anomalies():
		if int(anomaly.get("day", monitor.current_day)) != monitor.current_day:
			continue
		var id: String = str(anomaly.get("anomaly_id", ""))
		if seen.has(id):
			continue
		seen[id] = true
		var sid: String = str(anomaly.get("sensor", ""))
		result.append({"id": id, "name": str(anomaly.get("name", id)), "sensor": sid,
			"kind": "observation", "observation": true, "note": "读数变化尚未定性；可复测并保留记录。",
			"first": _safe_value(sid), "region": _sensor_region(sid), "marked": false})
	for sid in monitor.sensors:
		var status: String = str(monitor.sensor_status.get(sid, "offline"))
		var offset: float = float(monitor.calibration_offsets.get(sid, 0.0))
		var cfg: Dictionary = monitor.get_sensor_config(str(sid))
		var tolerance: float = maxf(pow(10.0, -int(cfg.get("precision", 1))), float(cfg.get("observation_tolerance", float(cfg.get("calibration_drift_max", 0.0)) * 0.6)))
		if status in ["offline", "degraded", "malfunction"] or absf(offset) > tolerance:
			var merged: bool = false
			for existing in result:
				if existing.get("sensor", "") == sid:
					existing["kind"] = "device"
					existing["note"] = "观测变化伴随设备疑点；可复测、对照后再判断。"
					merged = true
					break
			if merged: continue
			result.append({"id": "device_" + str(sid), "name": str(monitor.get_sensor_config(str(sid)).get("name", sid)) + "设备疑点",
				"sensor": sid, "kind": "device", "note": "设备状态 %s；读数一致性待核对。先复测再处理。" % status,
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

func issue_guidance() -> String:
	var issue: Dictionary = current_issue()
	if issue.is_empty(): return "暂无疑点；check 查看设备，scan 采集。"
	if is_submitted(): return "日报已归档；观测点仍可常规维护，原证据保持不变。"
	if bool(issue.get("routine_resolved", false)): return "设备已完成常规维护与验证；原始证据保留，可 report 提交。"
	if bool(issue.get("verification_pending", false)): return "下一步：retest 验证处理结果。"
	if issue.get("kind", "") == "device":
		if monitor.sensor_status.get(str(issue.get("sensor", "")), "offline") in ["offline", "degraded", "malfunction"]:
			return "下一步：repair → retest；无法确认可 mark → report。"
		if not issue.has("retest") and not issue.has("verification"): return "下一步：retest；偏移待核对可 compare。"
		if not bool(issue.get("calibrated", false)) and not bool(issue.get("repaired", false)): return "下一步：calibrate → retest；不确定可 mark → report。"
	return "证据已保留；可 details evidence 查看，mark 关注或 report 提交。" if issue.has("retest") or issue.has("verification") else "下一步：retest；不确定可 mark → report。"

func retest() -> void:
	var issue: Dictionary = current_issue()
	if issue.is_empty():
		message = "当前没有待复测项目。"
		return
	if is_submitted():
		message = "日报已归档，保留提交时的证据；下次采集再记录变化。"
		return
	var pending: bool = bool(issue.get("verification_pending", bool(issue.get("calibrated", false)) and not issue.has("verification")))
	if (issue.has("retest") or issue.has("verification")) and not pending:
		message = "该疑点已有复测／验证记录；维修或校准后可再次验证，也可 mark 关注。"
		return
	var sid: String = str(issue.get("sensor", ""))
	if debug_scenario.is_empty():
		monitor.refresh_device_readings()
	var value: Variant = _safe_value(sid)
	if not debug_scenario.is_empty():
		value = 1007.0 if debug_scenario == "device" else 48220.0
	var verifying: bool = pending
	var record_key: String = "verification" if verifying else "retest"
	# 老存档只有单条验证；在写入新结果前保留它。
	if verifying and issue.has("verification") and not issue.has("verification_history"):
		issue["verification_history"] = [{"kind": "历史处理", "reading": issue["verification"].duplicate(true), "note": issue.get("verification_note", "") }]
	issue[record_key] = {"value": value, "hour": monitor.get_current_hour_display(), "sequence": monitor.reading_sequence, "trend": monitor.get_sensor_trend(sid), "reference": monitor.get_weather_reference().get(sid)}
	var original_note: String = str(issue.get("original_retest_note", issue.get("retest_note", "")))
	var first: Variant = issue.get("retest", {}).get("value", issue.get("first")) if verifying else issue.get("first")
	if value == null:
		issue["retest_note"] = "复测仍无有效读数；设备无数据，按未确认记录即可。"
	elif first != null:
		issue["retest_note"] = "首次 %s → 复测 %s；变化 %+.2f。" % [format_value(first), format_value(value), float(value) - float(first)]
	else:
		issue["retest_note"] = "恢复读数 %s，首次采集无有效读数。" % format_value(value)
	if verifying:
		var treatment: String = str(issue.get("maintenance_kind", "校准"))
		issue["verification_note"] = treatment + "后验证：" + str(issue["retest_note"]).replace("首次", "处理前")
		var history: Array = issue.get("verification_history", [])
		history.append({"kind": treatment, "reading": issue["verification"].duplicate(true), "note": issue["verification_note"]})
		issue["verification_history"] = history
		issue["verification_pending"] = false
		issue["retest_note"] = original_note
		message = str(issue["verification_note"])
	else:
		issue["original_retest_note"] = issue["retest_note"]
		message = str(issue["retest_note"])
	_persist()

func compare_readings() -> String:
	if not is_collected():
		return "请先 scan，才能对照同次采集的本站与区域参考。"
	var reference: Dictionary = state().get("reference", {})
	if reference.is_empty():
		return "该旧快照没有同期区域参考；不拿当前天气倒填旧证据，下次采集会记录。"
	var baseline: Dictionary = reference.get("readings", {})
	var observed: Dictionary = state().get("readings", {})
	var lines: Array[String] = ["同期对照 / 采集 %s / 基准 %s / 区域天气参考（OB-7K）" % [state().get("hour", ""), reference.get("time", "")]]
	for sid in ["air_temp", "wind_speed", "wind_dir", "visibility", "wave_height", "pressure"]:
		var cfg: Dictionary = monitor.get_sensor_config(sid)
		var base: Variant = baseline.get(sid)
		var value: Variant = observed.get(sid)
		var delta_text: String = "数据暂缺"
		if base != null and value != null and is_finite(float(base)) and is_finite(float(value)):
			var difference: float = float(value) - float(base)
			if sid == "wind_dir": difference = fmod(difference + 540.0, 360.0) - 180.0
			delta_text = "%+.2f" % difference
		lines.append("%s：本站 %s / 参考 %s / 差值 %s %s" % [cfg.get("name", sid), format_value(value), format_value(base), delta_text, cfg.get("unit", "")])
	lines.append("差异是核对依据，不直接代表设备故障；复测与校准后验证另存证据。")
	return "\n".join(lines)

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
	if issue.get("kind", "") != "device" or (not issue.has("retest") and not issue.has("verification")) or is_submitted():
		message = "请先 scan → issues → select <编号> → retest，再校准设备疑点；日报已提交时不可改写。"
		return
	if bool(issue.get("calibrated", false)):
		message = "已校准；输入 retest 进行校准后验证。"
		return
	var sid: String = str(issue.get("sensor", ""))
	if monitor.sensor_status.get(sid, "offline") == "offline":
		message = "设备离线，请 repair → retest 恢复并验证；也可 mark 后如实提交。"
		return
	if debug_scenario.is_empty():
		monitor.reset_calibration(sid)
		monitor.refresh_device_readings()
	issue["calibrated"] = true
	_record_maintenance(issue, "校准")
	message = "已校准设备偏移；输入 retest 验证。首次采集和复测证据保持原样。"
	_persist()

func _record_maintenance(issue: Dictionary, kind: String) -> void:
	issue["maintenance_kind"] = kind
	issue["verification_pending"] = true
	var history: Array = issue.get("maintenance_history", [])
	history.append({"kind": kind, "hour": monitor.get_current_hour_display(), "day": monitor.current_day})
	issue["maintenance_history"] = history

# 常规维护仅处理选中点的硬件；特殊故障由配置／疑点显式排除。
func _region_sensors(region_id: String) -> Array[String]:
	var result: Array[String] = []
	for region in config.get("regions", []):
		if str(region.get("id", "")) != region_id: continue
		for sid in region.get("sensors", []):
			if monitor.sensors.has(str(sid)) and not result.has(str(sid)): result.append(str(sid))
	return result

func _maintenance_block_reason(sid: String) -> String:
	var cfg: Dictionary = monitor.get_sensor_config(sid)
	if bool(cfg.get("requires_manual_maintenance", false)):
		return str(cfg.get("maintenance_hint", "特殊故障，需手动排查"))
	var manual: Dictionary = config.get("maintenance", {}).get("manual_only_sensors", {})
	if manual.has(sid): return str(manual[sid])
	for issue in issues():
		if issue.get("sensor", "") == sid and bool(issue.get("requires_manual_maintenance", false)):
			return str(issue.get("maintenance_hint", "特殊故障，需手动排查"))
	var status: String = str(monitor.sensor_status.get(sid, "offline"))
	if status not in ["online", "nominal", "optimal", "offline", "degraded", "malfunction"]:
		return "未知设备状态，需手动排查"
	return ""

func _needs_routine_maintenance(sid: String) -> bool:
	var cfg: Dictionary = monitor.get_sensor_config(sid)
	var tolerance: float = maxf(pow(10.0, -int(cfg.get("precision", 1))), float(cfg.get("observation_tolerance", float(cfg.get("calibration_drift_max", 0.0)) * 0.6)))
	return monitor.sensor_status.get(sid, "offline") in ["offline", "degraded", "malfunction"] or absf(float(monitor.calibration_offsets.get(sid, 0))) > tolerance

func routine_maintenance_status(region_id: String) -> Dictionary:
	var targets: Array[String] = []
	var blocked: Array[String] = []
	var sensors: Array[String] = _region_sensors(region_id)
	for sid in sensors:
		var reason: String = _maintenance_block_reason(sid)
		if not reason.is_empty(): blocked.append(sid + "：" + reason)
		elif _needs_routine_maintenance(sid): targets.append(sid)
	var label: String = "常规维护" if not targets.is_empty() else ("需手动排查" if not blocked.is_empty() else "无需维护")
	var enabled: bool = not targets.is_empty()
	var note: String = "修复、校准并自动验证" if enabled else "设备状态正常"
	if targets.is_empty() and blocked.is_empty() and pending_issue_count(region_id) > 0: note = "设备正常；观测变化仍待核对"
	if not blocked.is_empty(): note = "特殊故障保留；需手动排查"
	if sensors.is_empty():
		label = "未接入设备"
		note = "先选择已接入的观测点"
		enabled = false
	elif not debug_scenario.is_empty():
		label = "预览不可维护"
		note = "隔离预览不修改实际设备"
		enabled = false
	elif is_collecting():
		label = "采集中"
		note = "采集结束后可维护"
		enabled = false
	return {"label": label, "enabled": enabled, "note": note, "targets": targets, "blocked": blocked}

func maintain_region(region_id: String, sensor_only: String = "") -> void:
	var availability: Dictionary = routine_maintenance_status(region_id)
	if not sensor_only.is_empty():
		availability["targets"] = availability["targets"].filter(func(sid): return sid == sensor_only)
		availability["enabled"] = availability["enabled"] and not availability["targets"].is_empty()
	if not availability["enabled"]:
		message = str(availability["note"])
		if not availability["blocked"].is_empty(): message += "\n" + "\n".join(availability["blocked"])
		return
	var records: Array = []
	for sid in availability["targets"]:
		var record: Dictionary = {"sensor": sid, "region": region_id, "day": monitor.current_day, "hour": monitor.get_current_hour_display(),
			"before": _safe_value(sid), "before_status": monitor.sensor_status.get(sid, "offline"), "before_offset": monitor.calibration_offsets.get(sid, 0)}
		if monitor.sensor_status.get(sid, "offline") in ["offline", "degraded", "malfunction"]: monitor.repair_sensor(sid)
		monitor.reset_calibration(sid)
		records.append(record)
	monitor.refresh_device_readings()
	var log: Array = state().get("routine_maintenance", [])
	var lines: Array[String] = []
	for record in records:
		var sid: String = record["sensor"]
		var sample: Dictionary = {"value": _safe_value(sid), "hour": monitor.get_current_hour_display(), "sequence": monitor.reading_sequence,
			"trend": monitor.get_sensor_trend(sid), "reference": monitor.get_weather_reference().get(sid)}
		record["after"] = sample.duplicate(true)
		record["verified"] = not _needs_routine_maintenance(sid) and sample["value"] != null
		log.append(record)
		_award_story_repair(record)
		var note: String = "常规维护后验证：%s → %s；%s。" % [format_value(record["before"]), format_value(sample["value"]), "设备已恢复" if record["verified"] else "仍无有效读数，需排查"]
		lines.append(str(monitor.get_sensor_config(sid).get("name", sid)) + "：" + note)
		# 日报提交后只更新维护日志及硬件，不改写当日证据。
		if is_submitted(): continue
		for issue in issues():
			if issue.get("sensor", "") != sid: continue
			_record_maintenance(issue, "常规维护")
			var history: Array = issue.get("verification_history", [])
			if history.is_empty() and issue.has("verification"):
				history.append({"kind": "历史处理", "reading": issue["verification"].duplicate(true), "note": issue.get("verification_note", "")})
			history.append({"kind": "常规维护", "reading": sample.duplicate(true), "before": record["before"], "note": note})
			issue["verification_history"] = history
			issue["verification"] = sample.duplicate(true)
			issue["verification_note"] = note
			issue["verification_pending"] = false
			issue["routine_resolved"] = record["verified"] and issue.get("kind", "") == "device" and not bool(issue.get("observation", false))
			if bool(issue.get("observation", false)): lines.append("观测变化仍需核对；维护不会消除异常记录。")
	state()["routine_maintenance"] = log
	if not availability["blocked"].is_empty(): lines.append("未自动处理：" + "；".join(availability["blocked"]))
	message = "常规维护完成（%d 台）。\n" % records.size() + "\n".join(lines)
	_persist()

# 只接受本轮指定故障设备的实际维护与成功验证，不奖励复查或正常设备。
func _award_story_repair(record: Dictionary) -> void:
	# Content packages own repair rewards.
	pass

func investigation_items(region_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Array[String] = []
	var region_sensors: Array[String] = _region_sensors(region_id)
	for i in range(issues().size()):
		var issue: Dictionary = issues()[i]
		var sid: String = str(issue.get("sensor", ""))
		seen.append(sid)
		if not region_id.is_empty() and not region_sensors.has(sid) and issue.get("region", "") != region_id: continue
		result.append({"key": "issue:" + str(i), "sensor": sid, "issue": issue, "pending": issue_is_pending(issue)})
	if not debug_scenario.is_empty(): return result
	for sid in monitor.sensors:
		if seen.has(str(sid)) or (not region_id.is_empty() and not region_sensors.has(str(sid))): continue
		if not _needs_routine_maintenance(str(sid)) and _maintenance_block_reason(str(sid)).is_empty() and _safe_value(str(sid)) != null: continue
		result.append({"key": "sensor:" + str(sid), "sensor": str(sid), "issue": {}, "pending": true})
	return result

func investigation_item(key: String) -> Dictionary:
	for item in investigation_items():
		if item["key"] == key: return item
	# 正常设备也可以从分类页打开，查看状态与旧采集值。
	if key.begins_with("sensor:") and monitor.sensors.has(key.trim_prefix("sensor:")):
		for item in investigation_items():
			if item["sensor"] == key.trim_prefix("sensor:"): return item
		return {"key": key, "sensor": key.trim_prefix("sensor:"), "issue": {}, "pending": false}
	return {}

func maintain_sensor(sid: String) -> void:
	for region in config.get("regions", []):
		if _region_sensors(str(region.get("id", ""))).has(sid):
			maintain_region(str(region["id"]), sid)
			return
	message = "该设备尚未接入维护点。"

func review_item(key: String) -> void:
	var item: Dictionary = investigation_item(key)
	if item.is_empty() or item["issue"].is_empty():
		message = "该设备没有采集疑点；设备问题可直接维护并验证。"
		return
	selected_issue = int(str(item["key"]).trim_prefix("issue:"))
	retest()

func retain_item(key: String) -> void:
	if is_submitted() or not key.begins_with("issue:"):
		message = "已归档证据不可修改；设备状态仍可查看或维护。"
		return
	var item: Dictionary = investigation_item(key)
	if item.is_empty(): return
	var issue: Dictionary = item["issue"]
	if bool(issue.get("marked", false)):
		message = "该疑点已保留，可如实提交日报。"
		return
	issue["marked"] = true
	message = "已保留未确认疑点，可如实提交日报。"
	_persist()

func pending_issue_count(region_id: String = "") -> int:
	var count: int = 0
	for item in investigation_items(region_id):
		if bool(item["pending"]): count += 1
	return count

func issue_is_pending(issue: Dictionary) -> bool:
	# 采集证据是历史记录；工作页警告反映当前状态，不改写旧日报。
	if not debug_scenario.is_empty(): return not bool(issue.get("routine_resolved", false))
	var sid: String = str(issue.get("sensor", ""))
	if not _maintenance_block_reason(sid).is_empty(): return true
	if bool(issue.get("observation", false)) or issue.get("kind", "") != "device": return true
	if not monitor.sensors.has(sid): return true
	return _needs_routine_maintenance(sid) or _safe_value(sid) == null

func region_has_device_warning(region_id: String) -> bool:
	if not debug_scenario.is_empty(): return pending_issue_count(region_id) > 0
	for sid in _region_sensors(region_id):
		if not _maintenance_block_reason(sid).is_empty() or _needs_routine_maintenance(sid) or _safe_value(sid) == null: return true
	return false

func device_status_text(sid: String) -> String:
	var status: String = str(monitor.sensor_status.get(sid, "offline"))
	return str({"online": "在线", "nominal": "在线", "optimal": "良好", "degraded": "退化", "malfunction": "故障", "offline": "离线"}.get(status, status))

func device_check() -> String:
	var lines: Array[String] = ["设备检查 / check", "设备ID / 名称 / 状态 / 建议"]
	var normal: int = 0
	for sid in monitor.sensors:
		var status: String = str(monitor.sensor_status.get(sid, "offline"))
		var cfg: Dictionary = monitor.get_sensor_config(str(sid))
		var tolerance: float = maxf(pow(10.0, -int(cfg.get("precision", 1))), float(cfg.get("observation_tolerance", float(cfg.get("calibration_drift_max", 0.0)) * 0.6)))
		var action: String = "偏移待核对：select <疑点编号> → retest → calibrate"
		if status in ["offline", "degraded", "malfunction"]:
			action = "repair " + str(sid) + " → retest"
		elif absf(float(monitor.calibration_offsets.get(sid, 0.0))) <= tolerance:
			normal += 1
			continue
		lines.append("%s / %s / %s / %s" % [sid, cfg.get("name", sid), device_status_text(str(sid)), action])
	lines.append("正常设备 %d / 共 %d；上方仅列需处理或核对的设备。" % [normal, monitor.sensors.size()])
	lines.append("sensor 列全部设备ID；sensor <ID> 查看单台。scan → issues → select <编号> 选择疑点。")
	return "\n".join(lines)

func device_info(sid: String) -> String:
	if sid.is_empty():
		var groups: Dictionary = {}
		for id in monitor.sensors:
			var category: String = str(monitor.get_sensor_config(str(id)).get("category", "other"))
			var entries: Array = groups.get(category, [])
			entries.append(str(id))
			groups[category] = entries
		var lines: Array[String] = ["全部设备ID / sensor <ID> 查看详情"]
		for category in groups:
			lines.append(str(category) + ": " + ", ".join(groups[category]))
		lines.append("check 查看需处理设备；repair <ID> 修复。")
		return "\n".join(lines)
	if not monitor.sensors.has(sid): return "未知设备：%s；sensor 列全部设备ID。" % sid
	var cfg: Dictionary = monitor.get_sensor_config(sid)
	return "%s / %s\n状态：%s / 当前值：%s %s\n设备偏移：%+.3f %s\n%s" % [cfg.get("name", sid), sid, device_status_text(sid), format_value(_safe_value(sid)), cfg.get("unit", ""), monitor.calibration_offsets.get(sid, 0.0), cfg.get("unit", ""), "离线／退化／故障：repair " + sid + "；在线偏移：select <疑点编号> → retest → calibrate → retest。"]

func repair_device(sid: String = "") -> void:
	if not debug_scenario.is_empty():
		message = "当前是调试预览，不修改实际设备；退出预览后用 check 查看真实状态。"
		return
	if sid.is_empty(): sid = str(current_issue().get("sensor", ""))
	if sid.is_empty():
		message = "请 select <疑点编号> 后 repair，或 repair <设备ID>；check 查看设备。"
		return
	if not monitor.sensors.has(sid):
		message = "未知设备：%s；sensor 列全部设备ID。" % sid
		return
	if not monitor.repair_sensor(sid):
		message = "设备运行正常，无需维修；偏移疑点请先 retest，再 calibrate。"
		return
	monitor.refresh_device_readings()
	# 已归档日报不改写；维修状态仍立即保存。
	if not is_submitted():
		for issue in issues():
			if issue.get("sensor", "") == sid:
				issue["repaired"] = true
				_record_maintenance(issue, "维修")
	_persist()
	var next_step: String = "用 issues → select <对应编号> → retest 验证；首次快照保持原样。"
	if is_submitted(): next_step = "已归档日报保持原样；下次采集记录恢复情况。"
	elif not is_collected(): next_step = "用 scan 采集恢复后的状态；sensor " + sid + " 可查看实时读数。"
	message = "%s已修复、重新上线并保存。%s" % [monitor.get_sensor_config(sid).get("name", sid), next_step]

func help_text() -> String:
	return "\n".join([
		"ENV：scan 采集 → 点击观测点维护 → details 查看／处理可疑项目 → report 提交。",
		"details 中点击项目，查看问题、原因与依据；按钮复核观测、维护并验证、保留疑点。",
		"普通维护覆盖全部设备；特殊故障显示具体排查提示，未确认也可如实提交。",
		"details [overview/atmosphere/ocean/geophysics/composition/events/evidence]；history 查看日报。",
		"map 返回地图；Tab 在地图切近海／远海，在详情选择按钮；空输入时方向键选择、Enter 确认。",
		"manual 操作说明；clear 清反馈；exit 返回桌面。采集及原始日报不被维护覆盖。"
	])

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
	if debug_scenario.is_empty() and monitor.current_day == 2:
		data["submitted_unix"] = Time.get_unix_time_from_system()
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
	if traffic_active:
		return _traffic_contacts()
	if debug_scenario == "sea":
		return [
			{"id": "V-03", "kind": "ship", "position": [0.48, -0.18], "track": [[0.24, -0.08], [0.36, -0.13], [0.48, -0.18]], "source": "调试浮标回报"},
			{"id": "A-02", "kind": "aircraft", "position": [-0.3, 0.55], "track": [[-0.5, 0.6], [-0.3, 0.55]], "source": "调试航迹"},
			{"id": "S-04", "kind": "submarine", "position_m": [14500, -19000], "track_m": [[10000,-22000],[12500,-21000],[14500,-19000]], "source": "调试声纳回报"},
			{"id": "历史雷区（调试）", "kind": "mine", "position": [0.5, 0.55], "source": "调试历史记录，不是实时探测"}]
	var entries: Array = config.get("contacts", [])
	if main.daily_dialogue_mgr:
		entries = main.daily_dialogue_mgr.get_environment_config(monitor.current_day).get("contacts", entries)
	var result: Array = []
	var minute: float = fmod(monitor.current_hour, 24.0) * 60.0
	for raw in entries:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw.duplicate(true)
		if not bool(entry.get("visible", true)):
			continue
		var start: float = float(entry.get("start_minute", 0))
		var end: float = float(entry.get("end_minute", 1440))
		if minute < start or minute > end:
			continue
		var route: Array = entry.get("route", [])
		var trail: Array = []
		if not route.is_empty():
			entry["known_route_m"] = []
			for waypoint in route:
				if waypoint is Dictionary and _valid_map_pair(waypoint.get("position_m")):
					entry["known_route_m"].append(waypoint["position_m"])
			var previous: Dictionary = {}
			for waypoint in route:
				if not (waypoint is Dictionary):
					continue
				if not _valid_map_pair(waypoint.get("position_m")):
					continue
				var point: Array = waypoint["position_m"]
				var t: float = float(waypoint.get("minute", 0))
				if t <= minute:
					entry["position_m"] = point
					trail.append(point)
					previous = waypoint
				elif not previous.is_empty():
					var a: Array = previous["position_m"]
					var fraction: float = clampf((minute - float(previous.get("minute", 0))) / maxf(0.001, t - float(previous.get("minute", 0))), 0.0, 1.0)
					entry["position_m"] = [lerpf(float(a[0]), float(point[0]), fraction), lerpf(float(a[1]), float(point[1]), fraction)]
					trail.append(entry["position_m"])
					break
			if not entry.has("position_m"):
				continue
			entry["track_m"] = trail
		if str(entry.get("kind", "")) not in ["ship", "aircraft", "submarine", "mine"] or str(entry.get("id", "")).is_empty():
			continue
		if not _valid_map_pair(entry.get("position_m", entry.get("position"))):
			continue
		result.append(entry)
	return result

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
	return "数据暂缺" if value == null or not is_finite(float(value)) else "%.2f" % float(value)

func set_preview(scenario: String) -> void:
	clear_traffic()
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

func _valid_map_pair(value: Variant) -> bool:
	if not (value is Array) or value.size() != 2: return false
	return (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int) and is_finite(float(value[0])) and is_finite(float(value[1]))

func clear_traffic() -> void:
	_radar_samples.clear()
	traffic_active = false
	traffic_paused = false
	traffic_elapsed = 0.0
	traffic_scale = 10.0
	_traffic_routes.clear()
	if main and main.env_viewer and main.env_viewer.selected_region.begins_with("contact:"):
		main.env_viewer.selected_region = ""

func configure_traffic(args: Array) -> String:
	var action: String = str(args[0]).to_lower() if not args.is_empty() else "all"
	if action in ["off", "clear", "stop"]:
		clear_traffic()
		return "移动目标预览已取消，恢复原海域目标；未改动存档。"
	if action == "status": return traffic_status()
	if action == "speed":
		if args.size() != 2 or not str(args[1]).is_valid_float(): return "用法：debug 114514 env traffic speed <倍率1..120>"
		var scale_value: float = float(args[1])
		if not is_finite(scale_value) or scale_value < 1.0 or scale_value > 120.0: return "倍率范围1..120；1为实际速度。"
		traffic_scale = scale_value
		return traffic_status()
	if action in ["pause", "resume"]:
		traffic_paused = action == "pause"
		return traffic_status()
	if action == "restart": action = traffic_preset
	if action not in ["all", "ship", "aircraft", "submarine", "unrouted"]:
		return "用法：debug 114514 env traffic all/ship/aircraft/submarine/unrouted/speed <倍率>/pause/resume/restart/status/off"
	var chosen_scale: float = traffic_scale
	clear_traffic()
	traffic_scale = chosen_scale
	traffic_active = true
	traffic_preset = action
	_traffic_owner = main.user_mgr.get_username()
	_traffic_day = monitor.current_day
	var radius: float = float(config.get("sea_radius_nm", 30)) * 1852.0
	var presets: Array[Dictionary] = [
		{"id":"TEST-V01", "name":"测试货船", "kind":"ship", "threat":"civilian", "speed_knots":18.0, "points":[[-0.88,0.4],[-0.25,0.48],[0.4,0.46],[0.86,0.42]], "source":"隔离测试／海域雷达"},
		{"id":"TEST-A01", "name":"测试巡逻机", "kind":"aircraft", "threat":"military", "speed_knots":240.0, "points":[[-0.7,-0.66],[-0.25,-0.1],[0.35,0.28],[0.73,0.63]], "source":"隔离测试／空中雷达"},
		{"id":"TEST-S01", "name":"测试潜艇", "kind":"submarine", "threat":"unknown", "speed_knots":8.0, "points":[[0.55,-0.79],[0.1,-0.65],[-0.4,-0.62],[-0.75,-0.6]], "source":"隔离测试／声纳回报"}
	]
	for preset in presets:
		if action == "unrouted":
			if preset["kind"] != "ship": continue
			preset["id"] = "TEST-U01"
			preset["name"] = "未知测试回波"
			preset["threat"] = "unknown"
			preset["route_known"] = false
		elif action != "all" and preset["kind"] != action: continue
		var route: Array = []
		for pair in preset["points"]: route.append([float(pair[0]) * radius, float(pair[1]) * radius])
		preset["known_route_m"] = route.duplicate(true)
		if preset["kind"] == "aircraft":
			route[1][1] += radius * 0.06
			route[2][1] += radius * 0.04
		preset["track_m"] = route
		preset.erase("points")
		_traffic_routes.append(preset)
	return "已从地图边缘启动移动目标。" + traffic_status() + "；off取消，speed 1使用真实速度。"

func traffic_status() -> String:
	if not traffic_active: return "移动目标预览未开启。"
	return "测试目标 / %.0f倍 / %s / 模拟%.0f秒" % [traffic_scale, "暂停" if traffic_paused else "运行", traffic_elapsed]

func _traffic_contacts() -> Array:
	var result: Array = []
	for preset in _traffic_routes:
		var points: Array = preset["track_m"]
		var remaining: float = traffic_elapsed * float(preset["speed_knots"]) * 1852.0 / 3600.0
		var trail: Array = [points[0]]
		for i in range(1, points.size()):
			var a := Vector2(float(points[i-1][0]), float(points[i-1][1]))
			var b := Vector2(float(points[i][0]), float(points[i][1]))
			var length_m: float = a.distance_to(b)
			if remaining > length_m:
				remaining -= length_m
				trail.append(points[i])
				continue
			var pos: Vector2 = a.lerp(b, remaining / maxf(length_m, 0.001))
			trail.append([pos.x, pos.y])
			var contact: Dictionary = preset.duplicate(true)
			contact["position_m"] = [pos.x, pos.y]
			contact["track_m"] = trail
			contact["note"] = "测试航速 %.0f节，时间倍率%.0f；完成路线后退出展示。" % [preset["speed_knots"], traffic_scale]
			result.append(contact)
			break
	return result

func _contact_metric_position(entry: Dictionary) -> Array:
	if _valid_map_pair(entry.get("position_m")): return entry["position_m"]
	var pair: Variant = entry.get("position")
	if not _valid_map_pair(pair): return []
	var radius: float = float(config.get("sea_radius_nm", 30)) * 1852.0
	return [float(pair[0]) * radius, -float(pair[1]) * radius]

func update_radar(previous_angle: float, sweep_delta: float) -> Array[String]:
	# 只在扫描束越过目标方位时记录，不把目标连续真值当作雷达观测。
	var notifications: Array[String] = []
	if sweep_delta <= 0.0: return notifications
	if _radar_day != monitor.current_day or _radar_owner != main.user_mgr.get_username():
		_radar_samples.clear()
		_radar_day = monitor.current_day
		_radar_owner = main.user_mgr.get_username()
	var entries: Array = contacts()
	var ids: Array = []
	var radius: float = float(config.get("sea_radius_nm", 30)) * 1852.0
	var now: float = Time.get_ticks_msec() / 1000.0
	for entry in entries:
		var id: String = str(entry.get("id", ""))
		ids.append(id)
		if entry.get("kind", "") == "mine": continue
		var pair: Array = _contact_metric_position(entry)
		if pair.is_empty(): continue
		var pos := Vector2(float(pair[0]), -float(pair[1]))
		if pos.length() > radius * 0.97: continue
		var bearing: float = fposmod(pos.angle(), TAU)
		var distance: float = fposmod(bearing - previous_angle, TAU)
		if distance <= 0.0 or distance > sweep_delta: continue
		var first_seen: bool = not _radar_samples.has(id)
		var source: String = "声纳" if entry.get("kind", "") == "submarine" else "雷达"
		var azimuth: float = fposmod(rad_to_deg(pos.angle()) + 90.0, 360.0)
		notifications.append("[%s %s] %s (%s) / 方位%03d° / 距离%.1fNM" % [source, "首次发现" if first_seen else "更新回波", entry.get("name", id), id, roundi(azimuth) % 360, pos.length() / 1852.0])
		var sample: Dictionary = _radar_samples.get(id, {"points": []})
		var points: Array = sample.get("points", [])
		points.append(pair.duplicate())
		if points.size() > 64: points.pop_front()
		sample["position_m"] = pair.duplicate()
		sample["time"] = now
		sample["points"] = points
		_radar_samples[id] = sample
	for id in _radar_samples.keys():
		if not ids.has(id): _radar_samples.erase(id)

	return notifications

func radar_contacts() -> Array:
	var result: Array = []
	var now: float = Time.get_ticks_msec() / 1000.0
	var ttl: float = maxf(1.0, float(config.get("radar_echo_seconds", 14.0)))
	for entry in contacts():
		var view: Dictionary = entry.duplicate(true)
		view["echo_alpha"] = 0.0
		view["observed_track_m"] = []
		if entry.get("kind", "") == "mine":
			view["echo_alpha"] = 1.0
		elif _radar_samples.has(str(entry.get("id", ""))):
			var sample: Dictionary = _radar_samples[str(entry["id"])]
			var age: float = maxf(0.0, now - float(sample.get("time", now)))
			view["position_m"] = sample["position_m"]
			view["observed_track_m"] = sample["points"]
			view["echo_age"] = age
			view["echo_alpha"] = clampf(1.0 - age / ttl, 0.0, 1.0)
		if not bool(entry.get("route_known", true)): view["known_route_m"] = []
		result.append(view)
	return result

func known_routes() -> Array:
	# 当天已知情报可先于目标出现显示，不依赖雷达探测。
	var entries: Array = _traffic_routes if traffic_active else config.get("contacts", [])
	if not traffic_active and main.daily_dialogue_mgr:
		entries = main.daily_dialogue_mgr.get_environment_config(monitor.current_day).get("contacts", entries)
	var result: Array = []
	for entry in entries:
		if not (entry is Dictionary) or not bool(entry.get("visible", true)) or not bool(entry.get("route_known", true)): continue
		var route: Array = entry.get("known_route_m", []).duplicate(true)
		if route.is_empty():
			for point in entry.get("route", []):
				if point is Dictionary and _valid_map_pair(point.get("position_m")): route.append(point["position_m"])
		if route.is_empty(): continue
		var view: Dictionary = entry.duplicate(true)
		view["known_route_m"] = route
		result.append(view)
	return result
