# ============================================================
# performance_manager.gd
# 绩效管理系统 —— 评分、配额、加班追踪、结局影响
#
# 奖励和扣分统一计入累计总分；分类参数只保留为输入与回执兼容。
# 收工按累计要求计算缺口；缺口超过10分则失败。
# 4 日一次自动绩效报告（邮件投递）。
# 通过触发器 score:N:category 加分。
# ============================================================
class_name PerformanceManager
extends RefCounted

# ══════════════════════════════════════════
#  信号
# ══════════════════════════════════════════
signal score_changed(category: String, old_total: int, new_total: int)
signal daily_settled(day: int, result: Dictionary)
signal performance_warning(level: String, message: String)

# ══════════════════════════════════════════
#  引用
# ══════════════════════════════════════════
var main = null
var T = null

# ══════════════════════════════════════════
#  当日累积
# ══════════════════════════════════════════
var current_day_score: Dictionary = {
	"main": 0,
	"daily": 0,
	"side": 0,
	"bonus": 0,
	"penalty": 0,
}

# ══════════════════════════════════════════
#  历史记录（每天结算一条）
# ══════════════════════════════════════════
## 每项: {day, total(累计), quota(累计要求), gap, earned(当日新增)}
var score_history: Array[Dictionary] = []

# ══════════════════════════════════════════
#  累计统计
# ══════════════════════════════════════════
var career_total: int = 0
var career_main: int = 0
var career_daily: int = 0
var career_side: int = 0
var career_overtime: int = 0       # 旧接口兼容，不再增加
var warnings_issued: int = 0       # 累计警告次数
var overtime_gap: int = 0          # 当前未补的绩效缺口
var consecutive_low_days: int = 0  # 连续缺口天数

## ★ 剧情版本（由 main 从主线 manifest 同步；存档版本不匹配时自动重置）
var save_story_version: String = ""
# 与计分字段在同一 JSON 中提交，不从任务 profile 推测是否已经发奖。
var archive_reward_receipts: Dictionary = {}
var _archive_evidence_blocked: bool = false
var _performance_file_seen: bool = false

# ══════════════════════════════════════════
#  配置
# ══════════════════════════════════════════
var daily_quota: int = 3           # 每日新增要求（可被 DayConfig 覆盖）
var required_total: int = 3
var requirement_day: int = 0
var failed: bool = false
const FAILURE_GAP: int = 10
var game_total_days: int = 28      # 总游戏天数
var report_interval: int = 4       # 每 N 天生成一次报告

## 结局阈值
var threshold_termination_warnings: int = 5   # 旧接口兼容，不用于失败判定
var threshold_serious_warnings: int = 3       # 旧接口兼容，不用于失败判定

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(p_main, p_theme) -> void:
	main = p_main
	T = p_theme

## 仅复位账号进度，不写盘，不改宿主、当前剧情版本及全局配置。
func reset_player_progress() -> void:
	archive_reward_receipts.clear()
	current_day_score = {"main": 0, "daily": 0, "side": 0, "bonus": 0, "penalty": 0}
	score_history.clear()
	career_total = 0
	career_main = 0
	career_daily = 0
	career_side = 0
	career_overtime = 0
	warnings_issued = 0
	overtime_gap = 0
	consecutive_low_days = 0
	daily_quota = 3
	required_total = 3
	requirement_day = 0
	failed = false

# ══════════════════════════════════════════
#  加分
# ══════════════════════════════════════════
func configure_day(day: int, quota: int, cumulative_quota: int) -> void:
	requirement_day = day
	daily_quota = quota
	required_total = cumulative_quota
	_refresh_gap()

func _refresh_gap() -> void:
	overtime_gap = maxi(required_total - career_total, 0)

func get_gap() -> int:
	return maxi(required_total - career_total, 0)

func add_score(amount: int, category: String = "side") -> void:
	if amount == 0 or failed or category not in current_day_score:
		return
	var old_total: int = career_total
	current_day_score[category] += amount
	career_total += amount
	# 分类累计仅用于旧接口兼容，不参与结算和玩家显示。
	match category:
		"main": career_main += amount
		"daily": career_daily += amount
		"side": career_side += amount
	_refresh_gap()
	score_changed.emit(category, old_total, career_total)

# 同一天最多结算一次；宿主可延迟通知，先确认写盘成功。
func settle_day(day: int, notify: bool = true) -> void:
	if failed:
		return
	for entry in score_history:
		if int(entry.get("day", -1)) == day:
			return
	_refresh_gap()
	var record: Dictionary = {
		"day": day, "total": career_total, "quota": required_total,
		"gap": overtime_gap, "earned": _get_day_total(),
	}
	score_history.append(record)
	if overtime_gap > 0:
		warnings_issued += 1
		consecutive_low_days += 1
	else:
		consecutive_low_days = 0
	failed = overtime_gap > FAILURE_GAP
	current_day_score = {"main": 0, "daily": 0, "side": 0, "bonus": 0, "penalty": 0}
	if notify:
		publish_settlement(day)

func publish_settlement(day: int) -> void:
	for record in score_history:
		if int(record.get("day", -1)) != day:
			continue
		var gap: int = int(record.get("gap", 0))
		if gap > 0:
			_issue_warning(day, gap)
		daily_settled.emit(day, record)
		if day > 0 and day % report_interval == 0:
			_deliver_period_report(day)
		return

func _get_day_total() -> int:
	var t: int = 0
	for k in current_day_score.keys():
		t += current_day_score[k]
	return t

# ══════════════════════════════════════════
#  警告升级
# ══════════════════════════════════════════
func _issue_warning(day: int, gap: int) -> void:
	var level: String = "termination" if gap > FAILURE_GAP else "low"
	var msg: String = "Day%d 累计绩效缺口 %d 分。" % [day, gap]
	msg += "缺口超过10分，本次游戏失败。" if gap > FAILURE_GAP else "请在后续工作中补足。"
	performance_warning.emit(level, msg)
	_deliver_warning_mail(day, gap, level)

func restore_warning_mails() -> void:
	for record in score_history:
		var gap: int = int(record.get("gap", 0))
		if gap > 0:
			_deliver_warning_mail(int(record.day), gap, "termination" if gap > FAILURE_GAP else "low")

func _deliver_warning_mail(day: int, gap: int, level: String) -> void:
	if main == null or not main.get("mail_sys"):
		return
	for mail in main.mail_sys._temp_inbox:
		if str(mail.get("id", "")) == "perf_warning_day%d" % day:
			return
	var severity_text: String = ""
	var body: String = ""
	match level:
		"low":
			severity_text = "绩效提醒"
			body = "Performance reminder: day %d, gap %d." % [day, gap]
		"serious":
			severity_text = "绩效严重警告"
			body = "Consecutive low days %d, warnings %d, gap %d." % [consecutive_low_days, warnings_issued, overtime_gap]
		"termination":
			severity_text = "绩效不合格 — 游戏失败"
			body = "Performance threshold reached. Review perf for details."

	var mail_id: String = "perf_warning_day%d" % day
	var mail_entry: Dictionary = {
		"id": mail_id,
		"title": "[%s] %s" % [severity_text, "第%d天绩效报告" % day],
		"from": "HQ-OPS",
		"template": "email",
		"priority": "high" if level != "low" else "normal",
		"read": false,
		"delivered_at": Time.get_datetime_string_from_system(),
		"persistent": false,
		"story_id": "",
		"_body_text": body,
	}
	if "_temp_inbox" in main.mail_sys:
		main.mail_sys._temp_inbox.append(mail_entry)
		if main.mail_sys.has_method("_rebuild_merged"):
			main.mail_sys._rebuild_merged()
		if "has_new_mail" in main:
			main.has_new_mail = true
		main.mail_sys.start_blink()

# ══════════════════════════════════════════
#  4 日绩效报告
# ══════════════════════════════════════════
func _deliver_period_report(end_day: int) -> void:
	if main == null or not main.get("mail_sys"):
		return
	var start_day: int = maxi(1, end_day - report_interval + 1)
	var period_num: int = end_day / report_interval
	var body: String = "Days %d-%d: total %d, required %d, gap %d, warnings %d." % [start_day, end_day, career_total, required_total, get_gap(), warnings_issued]

	var mail_id: String = "perf_report_period%d" % period_num
	var mail_entry: Dictionary = {
		"id": mail_id,
		"title": "绩效报告 — 第 %d 周期 (Day %d-%d)" % [period_num, start_day, end_day],
		"from": "HQ-OPS",
		"template": "email",
		"priority": "normal",
		"read": false,
		"delivered_at": Time.get_datetime_string_from_system(),
		"persistent": true,
		"story_id": "",
		"_body_text": body,
	}
	if "_temp_inbox" in main.mail_sys:
		main.mail_sys._temp_inbox.append(mail_entry)
		if main.mail_sys.has_method("_rebuild_merged"):
			main.mail_sys._rebuild_merged()
		if "has_new_mail" in main:
			main.has_new_mail = true
		main.mail_sys.start_blink()

# ══════════════════════════════════════════
#  查询接口
# ══════════════════════════════════════════
func get_day_summary() -> Dictionary:
	return {
		"scores": current_day_score.duplicate(),
		"total": career_total,
		"quota": required_total,
		"overtime_gap": get_gap(),
	}

func get_career_summary() -> Dictionary:
	return {
		"total": career_total,
		"main": career_main,
		"daily": career_daily,
		"side": career_side,
		"overtime": career_overtime,
		"warnings": warnings_issued,
		"overtime_gap": get_gap(),
		"days_completed": score_history.size(),
		"game_total_days": game_total_days,
	}

func get_history() -> Array[Dictionary]:
	return score_history.duplicate(true)

# ══════════════════════════════════════════
#  存档
# ══════════════════════════════════════════
func get_save_data() -> Dictionary:
	return {
		"current_day_score": current_day_score.duplicate(),
		"score_history": score_history.duplicate(true),
		"career_total": career_total,
		"career_main": career_main,
		"career_daily": career_daily,
		"career_side": career_side,
		"career_overtime": career_overtime,
		"warnings_issued": warnings_issued,
		"overtime_gap": get_gap(),
		"consecutive_low_days": consecutive_low_days,
		"daily_quota": daily_quota,
		"version": 2,
		"required_total": required_total,
		"requirement_day": requirement_day,
		"failed": failed,
		"story_version": save_story_version,
		"archive_reward_receipts": archive_reward_receipts.duplicate(true),
	}

func load_save_data(data: Dictionary) -> void:
	archive_reward_receipts = data.get("archive_reward_receipts", {}).duplicate(true)
	if data.has("current_day_score"):
		for k in data["current_day_score"]:
			current_day_score[k] = int(data["current_day_score"][k])
	if data.has("score_history"):
		score_history.clear()
		for entry in data["score_history"]:
			score_history.append(entry)
	career_total = int(data.get("career_total", 0))
	career_main = int(data.get("career_main", 0))
	career_daily = int(data.get("career_daily", 0))
	career_side = int(data.get("career_side", 0))
	career_overtime = int(data.get("career_overtime", 0))
	warnings_issued = int(data.get("warnings_issued", 0))
	overtime_gap = int(data.get("overtime_gap", 0))
	consecutive_low_days = int(data.get("consecutive_low_days", 0))
	daily_quota = int(data.get("daily_quota", 3))
	required_total = int(data.get("required_total", 3))
	requirement_day = int(data.get("requirement_day", 0))
	failed = bool(data.get("failed", false))
	_refresh_gap()

func _get_save_path() -> String:
	if main == null:
		return ""
	if not main.get("user_mgr") or not main.user_mgr.is_logged_in:
		return ""
	if main.get("save_mgr") == null:
		return ""
	var user_dir: String = main.save_mgr.get_game_root_dir() + "saves/" + main.user_mgr.get_username() + "/"
	return user_dir + "performance.json"

func save_progress() -> Dictionary:
	if main == null or main.get("user_mgr") == null or main.get("save_mgr") == null:
		return SaveManager.save_result("failed", "dependency", ERR_UNCONFIGURED)
	if not main.user_mgr.is_logged_in:
		return SaveManager.save_result("skipped", "no_account")
	var path: String = _get_save_path()
	if _profile_has_archive_evidence() or not archive_reward_receipts.is_empty():
		var evidence: Dictionary = _read_archive_performance(false)
		if evidence.status != "saved":
			return evidence
		if _archive_evidence_blocked:
			return SaveManager.save_result("failed", "reward_reload_required", ERR_FILE_CORRUPT)
	var result: Dictionary = SaveManager.write_json_checked(path, get_save_data())
	if result.status == "saved":
		_performance_file_seen = true
		_archive_evidence_blocked = false
	return result

func load_progress() -> bool:
	# 缺档、坏档、版本不符和部分字段都不能沿用上一账号的内存。
	reset_player_progress()
	_archive_evidence_blocked = false
	_performance_file_seen = false
	var path: String = _get_save_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		_archive_evidence_blocked = true
		return false
	_performance_file_seen = true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_archive_evidence_blocked = true
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not (json.data is Dictionary):
		file.close()
		_archive_evidence_blocked = true
		return false
	file.close()
	# ★ 剧情版本门控：主线剧情版本变化时视为无有效数据
	if save_story_version != "" and \
			str((json.data as Dictionary).get("story_version", "")) != save_story_version:
		print("[PerformanceManager] 剧情版本不匹配，重置绩效数据")
		return false
	load_save_data(json.data)
	print("[PerformanceManager] 绩效数据已加载: 总分 %d, 缺口 %d, 警告 %d" % [career_total, overtime_gap, warnings_issued])
	return true

## 失败时保留本实例的待确认计分和回执，重试只重写同一快照，不再次加分。
func commit_archive_reward(operation_id: String, amount: int, category: String, story_version: String) -> Dictionary:
	if operation_id.is_empty() or story_version != save_story_version or category not in current_day_score:
		return SaveManager.save_result("failed", "reward_context", ERR_INVALID_DATA)
	var evidence: Dictionary = _read_archive_performance()
	if evidence.status != "saved":
		return evidence
	var disk_receipts: Dictionary = evidence.data.get("archive_reward_receipts", {})
	if _archive_evidence_blocked or (disk_receipts.has(operation_id) and not archive_reward_receipts.has(operation_id)):
		load_save_data(evidence.data)
	_archive_evidence_blocked = false
	_performance_file_seen = true
	var receipt: Dictionary = {"amount": amount, "category": category, "story_version": story_version}
	if archive_reward_receipts.has(operation_id):
		var existing_receipt: Dictionary = archive_reward_receipts[operation_id]
		# JSON 的数字回读为 float，按字段语义核对，不能用严格字典类型相等。
		if float(existing_receipt.get("amount", INF)) != float(amount) or str(existing_receipt.get("category", "")) != category or str(existing_receipt.get("story_version", "")) != story_version:
			return SaveManager.save_result("failed", "reward_conflict", ERR_INVALID_DATA)
	else:
		archive_reward_receipts[operation_id] = receipt
		add_score(amount, category)
	return save_progress()

func has_archive_reward_receipt(operation_id: String) -> bool:
	# 完成、重新领取与跨日决策必须确认实际落盘回执，不能只信任当前会话内存。
	var evidence: Dictionary = _read_archive_performance()
	if evidence.status != "saved":
		return false
	if _archive_evidence_blocked:
		load_save_data(evidence.data)
		_archive_evidence_blocked = false
	var persisted: Dictionary = evidence.data.get("archive_reward_receipts", {})
	if not archive_reward_receipts.has(operation_id) or not persisted.get(operation_id) is Dictionary:
		return false
	var memory: Dictionary = archive_reward_receipts[operation_id]
	var receipt: Dictionary = persisted[operation_id]
	return float(memory.get("amount", INF)) == float(receipt.get("amount", -INF)) and str(memory.get("category", "")) == str(receipt.get("category", "")) and str(memory.get("story_version", "")) == str(receipt.get("story_version", ""))

## 旧任务的持久化引用本身说明该账号的领奖文件已经是必需证据。
func _profile_has_archive_evidence() -> bool:
	if main == null or main.get("user_mgr") == null or not main.user_mgr.is_logged_in:
		return false
	var data: Dictionary = main.user_mgr.current_user.get("vdisc_task_data", {})
	if not (data.get("archive", []) as Array).is_empty():
		return true
	for state in (data.get("tasks", {}) as Dictionary).values():
		if not str(state.get("archive_operation", "")).is_empty():
			return true
	return false

func _read_archive_performance(check_version: bool = true) -> Dictionary:
	var path: String = _get_save_path()
	if path.is_empty():
		return SaveManager.save_result("failed", "reward_dependency", ERR_UNCONFIGURED)
	if not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path):
		_archive_evidence_blocked = true
		return SaveManager.save_result("failed", "reward_evidence", ERR_FILE_NOT_FOUND)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return SaveManager.save_result("failed", "open", FileAccess.get_open_error())
	var json := JSON.new()
	var parsed: Error = json.parse(file.get_as_text())
	file.close()
	if parsed != OK or not json.data is Dictionary or not json.data.get("archive_reward_receipts", {}) is Dictionary:
		_archive_evidence_blocked = true
		return SaveManager.save_result("failed", "reward_evidence", ERR_FILE_CORRUPT)
	if check_version and str(json.data.get("story_version", "")) != save_story_version:
		return SaveManager.save_result("failed", "reward_evidence", ERR_INVALID_DATA)
	return {"status": "saved", "stage": "existing_baseline", "error": OK, "data": json.data}

## 仅在新操作建立前允许首次建档；恢复路径永远不调用这个创建入口。
func prepare_archive_baseline(allow_create: bool = false) -> Dictionary:
	var path: String = _get_save_path()
	if path.is_empty():
		return SaveManager.save_result("failed", "reward_dependency", ERR_UNCONFIGURED)
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		var existing: Dictionary = _read_archive_performance()
		if existing.status != "saved":
			return existing
		if _archive_evidence_blocked:
			load_save_data(existing.data)
		_archive_evidence_blocked = false
		_performance_file_seen = true
	elif not allow_create or _performance_file_seen or _profile_has_archive_evidence() or not archive_reward_receipts.is_empty():
		return SaveManager.save_result("failed", "reward_baseline_missing", ERR_FILE_NOT_FOUND)
	else:
		var created: Dictionary = SaveManager.write_json_checked(path, get_save_data())
		if created.status != "saved":
			return created
		_archive_evidence_blocked = false
		_performance_file_seen = true
	return {"status": "saved", "stage": "archive_baseline", "error": OK, "sha256": FileAccess.get_sha256(path)}
