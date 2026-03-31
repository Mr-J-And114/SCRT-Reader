# ============================================================
# performance_manager.gd
# 绩效管理系统 —— 评分、配额、加班追踪、结局影响
#
# 三类绩效：主线(main) / 每日(daily) / 支线(side)
# 每日配额未达标时产生绩效缺口，次日补上的分数计入加班绩效。
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
## 每项: {day, main, daily, side, bonus, penalty, overtime, total, quota, gap}
var score_history: Array[Dictionary] = []

# ══════════════════════════════════════════
#  累计统计
# ══════════════════════════════════════════
var career_total: int = 0
var career_main: int = 0
var career_daily: int = 0
var career_side: int = 0
var career_overtime: int = 0       # 用于补缺口而计入的加班分
var warnings_issued: int = 0       # 累计警告次数
var overtime_gap: int = 0          # 当前未补的绩效缺口
var consecutive_low_days: int = 0  # 连续缺口天数

# ══════════════════════════════════════════
#  配置
# ══════════════════════════════════════════
var daily_quota: int = 3           # 当日最低要求（可被 DayConfig 覆盖）
var game_total_days: int = 28      # 总游戏天数
var report_interval: int = 4       # 每 N 天生成一次报告

## 结局阈值
var threshold_termination_warnings: int = 5   # 累计警告达到此值 → 可触发开除
var threshold_serious_warnings: int = 3       # 累计警告达到此值 → 严重警告状态

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(p_main, p_theme) -> void:
	main = p_main
	T = p_theme

# ══════════════════════════════════════════
#  加分
# ══════════════════════════════════════════
func add_score(amount: int, category: String = "side") -> void:
	## 加分。如果存在绩效缺口，优先填补缺口（计入加班绩效）
	if amount == 0:
		return

	var actual_amount: int = amount
	var overtime_filled: int = 0

	# 正分 + 有缺口 → 优先补缺口
	if amount > 0 and overtime_gap > 0:
		var fill: int = mini(amount, overtime_gap)
		overtime_gap -= fill
		career_overtime += fill
		overtime_filled = fill
		actual_amount = amount - fill

	# 记录到当日分类
	if actual_amount != 0:
		match category:
			"main":
				var old: int = career_main
				current_day_score["main"] += actual_amount
				career_main += actual_amount
				career_total += actual_amount
				score_changed.emit("main", old, career_main)
			"daily":
				var old: int = career_daily
				current_day_score["daily"] += actual_amount
				career_daily += actual_amount
				career_total += actual_amount
				score_changed.emit("daily", old, career_daily)
			"side":
				var old: int = career_side
				current_day_score["side"] += actual_amount
				career_side += actual_amount
				career_total += actual_amount
				score_changed.emit("side", old, career_side)
			"bonus":
				current_day_score["bonus"] += actual_amount
				career_total += actual_amount
			"penalty":
				current_day_score["penalty"] += actual_amount
				career_total += actual_amount  # amount 通常为负数

	if overtime_filled > 0:
		career_total += overtime_filled
		print("[PerformanceManager] 补填缺口 %d 分 (剩余缺口: %d)" % [overtime_filled, overtime_gap])

# ══════════════════════════════════════════
#  每日结算（天数推进前调用）
# ══════════════════════════════════════════
func settle_day(day: int) -> void:
	var day_total: int = _get_day_total()
	var gap: int = 0
	if day_total < daily_quota:
		gap = daily_quota - day_total

	var record: Dictionary = {
		"day": day,
		"main": current_day_score["main"],
		"daily": current_day_score["daily"],
		"side": current_day_score["side"],
		"bonus": current_day_score["bonus"],
		"penalty": current_day_score["penalty"],
		"overtime": 0,  # 当日补缺口的分数在 add_score 中已计入 career_overtime
		"total": day_total,
		"quota": daily_quota,
		"gap": gap,
	}
	score_history.append(record)

	# 处理缺口
	if gap > 0:
		overtime_gap += gap
		consecutive_low_days += 1
		_issue_warning(day, gap)
	else:
		consecutive_low_days = 0

	daily_settled.emit(day, record)

	# 4 日报告
	if day > 0 and day % report_interval == 0:
		_deliver_period_report(day)

	# 重置当日累积
	current_day_score = {"main": 0, "daily": 0, "side": 0, "bonus": 0, "penalty": 0}
	# 恢复默认配额（DayConfig 可在下一天开始时覆盖）
	daily_quota = 3

func _get_day_total() -> int:
	var t: int = 0
	for k in current_day_score.keys():
		t += current_day_score[k]
	return t

# ══════════════════════════════════════════
#  警告升级
# ══════════════════════════════════════════
func _issue_warning(day: int, gap: int) -> void:
	warnings_issued += 1
	var level: String = "low"
	var msg: String = ""

	if warnings_issued >= threshold_termination_warnings:
		level = "termination"
		msg = "第 %d 天绩效缺口 %d 分。累计警告 %d 次，已达解雇标准。" % [day, gap, warnings_issued]
		# 设置剧情标记
		if main and main.get("daily_dialogue_mgr"):
			main.daily_dialogue_mgr.set_flag("termination_eligible", true)
	elif warnings_issued >= threshold_serious_warnings or consecutive_low_days >= 2:
		level = "serious"
		msg = "第 %d 天绩效缺口 %d 分。连续 %d 天未达标，总部高度关注。" % [day, gap, consecutive_low_days]
	else:
		level = "low"
		msg = "第 %d 天绩效缺口 %d 分。请在接下来的工作中补回。" % [day, gap]

	performance_warning.emit(level, msg)

	# 自动发送 HQ 警告邮件
	_deliver_warning_mail(day, gap, level)

func _deliver_warning_mail(day: int, gap: int, level: String) -> void:
	if main == null or not main.get("mail_sys"):
		return
	var severity_text: String = ""
	var body: String = ""
	match level:
		"low":
			severity_text = "绩效提醒"
			body = "操作员，\n\n根据监控记录，您在第 %d 天的绩效评分未达到当日最低要求（缺口 %d 分）。\n请在后续工作中及时补回缺口分数。\n\n未补回的分数将影响您的综合绩效评估。\n\n—— 站点运营监督部" % [day, gap]
		"serious":
			severity_text = "绩效严重警告"
			body = "操作员，\n\n您已连续 %d 天未达到最低绩效标准。总部对此高度关注。\n\n当前累计警告：%d 次\n当前绩效缺口：%d 分\n\n请立即改善工作表现。如情况持续恶化，总部将考虑采取进一步措施。\n\n—— 站点运营监督部（抄送：人事处）" % [consecutive_low_days, warnings_issued, overtime_gap]
		"termination":
			severity_text = "最终警告 — 解雇审查"
			body = "操作员，\n\n您的绩效表现已严重低于基金会最低标准。\n\n累计警告次数：%d\n累计绩效缺口：%d 分\n\n人事处已启动解雇审查程序。除非绩效出现显著改善，本站点将依据《基金会人事条例》第 7.3 条终止您的合同。\n\n请珍惜最后的机会。\n\n—— 站点运营监督部 / 人事处联合通知" % [warnings_issued, overtime_gap]

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
	var period_main: int = 0
	var period_daily: int = 0
	var period_side: int = 0
	var period_bonus: int = 0
	var period_penalty: int = 0
	var period_total: int = 0
	var gap_days: int = 0

	for record in score_history:
		var d: int = int(record.get("day", 0))
		if d >= start_day and d <= end_day:
			period_main += int(record.get("main", 0))
			period_daily += int(record.get("daily", 0))
			period_side += int(record.get("side", 0))
			period_bonus += int(record.get("bonus", 0))
			period_penalty += int(record.get("penalty", 0))
			period_total += int(record.get("total", 0))
			if int(record.get("gap", 0)) > 0:
				gap_days += 1

	var period_num: int = end_day / report_interval
	var body: String = "操作员，\n\n以下是第 %d-%d 天（第 %d 周期）的绩效汇总报告：\n" % [start_day, end_day, period_num]
	body += "\n╔════════════════════════════════╗"
	body += "\n║  绩效报告  第 %d 周期          ║" % period_num
	body += "\n╠════════════════════════════════╣"
	body += "\n║  主线绩效:  %+4d 分            ║" % period_main
	body += "\n║  每日绩效:  %+4d 分            ║" % period_daily
	body += "\n║  支线绩效:  %+4d 分            ║" % period_side
	body += "\n║  奖励:     %+4d 分            ║" % period_bonus
	if period_penalty != 0:
		body += "\n║  扣减:     %+4d 分            ║" % period_penalty
	body += "\n║  周期合计:  %+4d 分            ║" % period_total
	body += "\n╠════════════════════════════════╣"
	body += "\n║  累计总分:  %+4d 分            ║" % career_total
	body += "\n║  累计加班:  %+4d 分            ║" % career_overtime
	body += "\n║  当前缺口:  %+4d 分            ║" % overtime_gap
	body += "\n║  缺口天数:  %d / %d 天          ║" % [gap_days, report_interval]
	body += "\n║  累计警告:  %d 次              ║" % warnings_issued
	body += "\n╚════════════════════════════════╝"
	body += "\n\n请继续保持良好的工作表现。\n\n—— 站点运营监督部"

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
		"total": _get_day_total(),
		"quota": daily_quota,
		"overtime_gap": overtime_gap,
	}

func get_career_summary() -> Dictionary:
	return {
		"total": career_total,
		"main": career_main,
		"daily": career_daily,
		"side": career_side,
		"overtime": career_overtime,
		"warnings": warnings_issued,
		"overtime_gap": overtime_gap,
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
		"overtime_gap": overtime_gap,
		"consecutive_low_days": consecutive_low_days,
		"daily_quota": daily_quota,
		"version": 1,
	}

func load_save_data(data: Dictionary) -> void:
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

func _get_save_path() -> String:
	if main == null:
		return ""
	if not main.get("user_mgr") or not main.user_mgr.is_logged_in:
		return ""
	if main.get("save_mgr") == null:
		return ""
	var user_dir: String = main.save_mgr.get_game_root_dir() + "saves/" + main.user_mgr.get_username() + "/"
	return user_dir + "performance.json"

func save_progress() -> void:
	var path: String = _get_save_path()
	if path.is_empty():
		return
	var dir_path: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(get_save_data(), "\t"))
		file.close()

func load_progress() -> bool:
	var path: String = _get_save_path()
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
	print("[PerformanceManager] 绩效数据已加载: 总分 %d, 缺口 %d, 警告 %d" % [career_total, overtime_gap, warnings_issued])
	return true
