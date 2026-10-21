# ============================================================
# daily_dialogue_manager.gd
# 每日剧情对话管理器 —— 根据当前天数自动触发通讯对话
#
# 数据来源：
#   1. res://data/main/manifest.json（内置主线剧情）
#   2. .scp 故事包 manifest 中的 daily_dialogues 段（覆盖/追加）
#
# 触发时机：
#   - on_start:        每天登录后自动触发
#   - on_scan_complete: env scan 完成后触发
#   - on_anomaly:       检测到异常时触发
#   - on_mail_read:     阅读特定邮件后触发
#   - on_command:       执行特定命令后触发
#
# 存档位置：
#   saves/{username}/story_progress.json（独立于磁盘存档）
# ============================================================
class_name DailyDialogueManager
extends RefCounted

var main = null
var _daily_config: Dictionary = {}  # day_number(str) -> {on_start, on_scan_complete, on_anomaly, ...}
var _dialogues: Dictionary = {}     # dialogue_id -> dialogue_data
var _characters: Dictionary = {}    # character_id -> character_config
var _triggered_today: Dictionary = {} # 记录今天已触发的事件类型，防止重复
var _pending_dialogues: Array = []

# ★ 主线剧情进度（独立存档，不绑定磁盘）
var _story_day: int = 1             # 当前主线天数
var _completed_dialogues: Array[String] = []  # 已完成的对话 ID 列表
var _story_choices: Dictionary = {} # 关键剧情选项记录 {choice_id: selected_option}
var _archive_effect_receipts: Dictionary = {}
var _story_evidence_blocked: bool = false
var _completion_notice_day: int = -1
var _story_flags: Dictionary = {}   # 剧情标记 {flag_name: value}

# ★ 剧情变量初始值（manifest 的 initial_flags 段，新存档时自动补齐）
var _initial_flags: Dictionary = {}

# ★ 主线剧情版本（manifest 的 story.version，存档版本门控用）
var _story_version: String = ""

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(p_main) -> void:
	main = p_main
	# ★ 不在初始化时加载主线剧情，改为登录后加载

func load_main_storyline() -> void:
	## 由 main.gd 在登录后调用，加载主线剧情配置
	var path: String = "res://data/main/manifest.json"
	if not FileAccess.file_exists(path):
		print("[DailyDialogue] 主线剧情文件不存在: " + path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	var text: String = f.get_as_text()
	f.close()
	if json.parse(text) != OK or not (json.data is Dictionary):
		push_warning("[DailyDialogue] 主线剧情 JSON 解析失败")
		return
	var data: Dictionary = json.data
	# ★ 主线剧情版本（存档门控）
	_story_version = str((data.get("story", {}) as Dictionary).get("version", ""))
	# 加载每日对话配置
	_daily_config = data.get("daily_dialogues", {})
	# ★ 剧情变量初始值（新存档时自动补齐）
	_initial_flags = data.get("initial_flags", {}) as Dictionary
	if not _initial_flags.is_empty() and _initial_flags.has("_comment"):
		_initial_flags = _initial_flags.duplicate()
		_initial_flags.erase("_comment")
	# 加载对话定义
	var dlgs: Dictionary = data.get("comm_dialogues", {})
	for dlg_id in dlgs.keys():
		_dialogues[dlg_id] = dlgs[dlg_id]
	# 加载角色定义
	_characters = data.get("comm_characters", {})
	# 扫描 dialogues 子目录加载扩展对话文件
	_load_dialogue_extensions("res://data/main/dialogues/")
	print("[DailyDialogue] 主线剧情加载完成: %d 天配置, %d 对话" % [_daily_config.size(), _dialogues.size()])

func _load_dialogue_extensions(dir_path: String) -> void:
	## 扫描目录下的所有 .json 文件，追加对话和天配置
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full_path: String = dir_path + file_name
			var f := FileAccess.open(full_path, FileAccess.READ)
			if f != null:
				var json := JSON.new()
				if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
					var ext_data: Dictionary = json.data
					# 追加每日对话配置
					var ext_daily: Dictionary = ext_data.get("daily_dialogues", {})
					for day_key in ext_daily.keys():
						if not _daily_config.has(day_key):
							_daily_config[day_key] = ext_daily[day_key]
					# 追加对话定义
					var ext_dlgs: Dictionary = ext_data.get("comm_dialogues", {})
					for dlg_id in ext_dlgs.keys():
						if not _dialogues.has(dlg_id):
							_dialogues[dlg_id] = ext_dlgs[dlg_id]
					# 追加角色定义
					var ext_chars: Dictionary = ext_data.get("comm_characters", {})
					for char_id in ext_chars.keys():
						if not _characters.has(char_id):
							_characters[char_id] = ext_chars[char_id]
				f.close()
		file_name = dir.get_next()
	dir.list_dir_end()

# ══════════════════════════════════════════
#  故事包覆盖
# ══════════════════════════════════════════
func load_from_manifest(manifest: Dictionary) -> void:
	# 故事包可以追加/覆盖每日对话配置
	var story_daily: Dictionary = manifest.get("daily_dialogues", {})
	for day_key in story_daily.keys():
		_daily_config[day_key] = story_daily[day_key]
	# 故事包的 comm_dialogues 也可以包含每日对话
	var story_dlgs: Dictionary = manifest.get("comm_dialogues", {})
	for dlg_id in story_dlgs.keys():
		_dialogues[dlg_id] = story_dlgs[dlg_id]
	var story_chars: Dictionary = manifest.get("comm_characters", {})
	for char_id in story_chars.keys():
		_characters[char_id] = story_chars[char_id]

# ══════════════════════════════════════════
#  注册对话到 CommManager
# ══════════════════════════════════════════
func register_dialogues_to_comm() -> void:
	if main == null or main.comm_mgr == null:
		return
	# 注册角色（通过 registry API）
	var registry: CharacterRegistry = main.comm_mgr.get_registry()
	for char_id in _characters.keys():
		if registry and not registry.has_character(char_id):
			var char_config: Dictionary = _characters[char_id].duplicate()
			registry.register_character(char_id, char_config, CharacterRegistry.CharacterSource.BUILTIN)
	# 注册对话（通过公共 API）
	for dlg_id in _dialogues.keys():
		if not main.comm_mgr.get_dialogue_ids().has(dlg_id):
			main.comm_mgr.register_mod_dialogue(dlg_id, _dialogues[dlg_id])

# ══════════════════════════════════════════
#  触发接口
# ══════════════════════════════════════════
func trigger_day_start(day: int) -> void:
	## 每天登录时调用（与磁盘加载无关）
	_story_day = day
	_triggered_today.clear()
	# ★ 补齐剧情变量初始值（新玩家/新存档）
	_ensure_default_flags()
	register_dialogues_to_comm()
	# ★ 应用当日绩效配置
	_apply_day_performance_config(day)
	# ★ 处理当日邮件投递
	_deliver_day_mails(day)
	if main.env_monitor:
		var environment: Dictionary = get_environment_config(day)
		var event_definitions: Dictionary = environment.get("event_definitions", {})
		for event_id in event_definitions:
			main.env_monitor.inject_event(str(event_id), event_definitions[event_id])
		main.env_monitor.apply_story_events(environment.get("events", []))
		main.env_monitor.save_env_progress()
	# ★ 执行当日触发器动作（radio_update 等）
	_execute_day_actions(day)
	if main.radio_receiver:
		main.radio_receiver.reload_signals()
	var dlg_ids: Array = _get_trigger_list(day, "on_start")
	if dlg_ids.size() > 0 and not _triggered_today.has("on_start"):
		var valid_ids: Array = _filter_playable(dlg_ids)
		if valid_ids.size() > 0:
			_triggered_today["on_start"] = true
			_trigger_dialogues(valid_ids)

func has_day_config(day: int) -> bool:
	return _daily_config.has(str(day))

## ★ 获取主线剧情版本（供 main 传播到各进度存档做版本门控）
func get_story_version() -> String:
	return _story_version

## ★ 补齐剧情变量初始值（新存档时把 manifest initial_flags 写入 _story_flags）
func _ensure_default_flags() -> void:
	var added: bool = false
	for fk in _initial_flags.keys():
		if not _story_flags.has(fk):
			_story_flags[fk] = _initial_flags[fk]
			added = true
	if added:
		save_story_save()

## ★ 应用当日绩效配置（覆盖 PerformanceManager 的 daily_quota）
func _apply_day_performance_config(day: int) -> void:
	if main == null or not main.get("perf_mgr"):
		return
	var cumulative: int = 0
	for index in range(day + 1):
		cumulative += _day_quota(index)
	main.perf_mgr.configure_day(day, _day_quota(day), cumulative)

func _day_quota(day: int) -> int:
	var config: Dictionary = _daily_config.get(str(day), _daily_config.get("default", {}))
	return int(config.get("performance", {}).get("min_quota", 3))

## ★ 执行每日触发器动作（如 radio_update、radio_visible 等）
func _execute_day_actions(day: int) -> void:
	if main == null or main.trigger_sys == null:
		return
	var day_key: String = str(day)
	var config: Dictionary = {}
	if _daily_config.has(day_key):
		config = _daily_config[day_key]
	elif _daily_config.has("default"):
		config = _daily_config["default"]
	var raw = config.get("on_start_actions", [])
	if not (raw is Array) or raw.is_empty():
		return
	for action in raw:
		main.trigger_sys._execute(str(action), {})

func trigger_scan_complete(day: int) -> void:
	## env scan 完成后调用
	var dlg_ids: Array = _get_trigger_list(day, "on_scan_complete")
	if dlg_ids.size() > 0 and not _triggered_today.has("on_scan_complete"):
		var valid_ids: Array = _filter_playable(dlg_ids)
		if valid_ids.size() > 0:
			_triggered_today["on_scan_complete"] = true
			_trigger_dialogues(valid_ids)

func trigger_anomaly(day: int) -> void:
	## 检测到异常时调用
	var dlg_ids: Array = _get_trigger_list(day, "on_anomaly")
	if dlg_ids.size() > 0 and not _triggered_today.has("on_anomaly"):
		var valid_ids: Array = _filter_playable(dlg_ids)
		if valid_ids.size() > 0:
			_triggered_today["on_anomaly"] = true
			_trigger_dialogues(valid_ids)

func trigger_mail_read(day: int, mail_id: String) -> void:
	## 阅读特定邮件后调用
	var dlg_ids: Array = _get_trigger_list(day, "on_mail_read")
	# 过滤出 mail_id 匹配的对话
	var matched: Array = []
	for dlg_id in dlg_ids:
		var dlg_data: Dictionary = _dialogues.get(str(dlg_id), {})
		var req_mail: String = str(dlg_data.get("requires_mail", ""))
		if req_mail.is_empty() or req_mail == mail_id:
			matched.append(dlg_id)
	var trigger_key: String = "on_mail_read:" + mail_id
	if matched.size() > 0 and not _triggered_today.has(trigger_key):
		var valid_ids: Array = _filter_playable(matched)
		if valid_ids.size() > 0:
			_triggered_today[trigger_key] = true
			_trigger_dialogues(valid_ids)

func trigger_command(day: int, cmd_name: String) -> void:
	## 执行特定命令后调用
	var dlg_ids: Array = _get_trigger_list(day, "on_command")
	var matched: Array = []
	for dlg_id in dlg_ids:
		var dlg_data: Dictionary = _dialogues.get(str(dlg_id), {})
		var req_cmd: String = str(dlg_data.get("requires_command", ""))
		if req_cmd.is_empty() or req_cmd == cmd_name:
			matched.append(dlg_id)
	var trigger_key: String = "on_command:" + cmd_name
	if matched.size() > 0 and not _triggered_today.has(trigger_key):
		var valid_ids: Array = _filter_playable(matched)
		if valid_ids.size() > 0:
			_triggered_today[trigger_key] = true
			_trigger_dialogues(valid_ids)

# ══════════════════════════════════════════
#  剧情选项记录
# ══════════════════════════════════════════
func record_choice(choice_id: String, selected_option: String) -> void:
	## 记录玩家的关键剧情选择
	_story_choices[choice_id] = selected_option
	save_story_save()

func get_choice(choice_id: String, default: String = "") -> String:
	## 查询某个剧情选择
	return str(_story_choices.get(choice_id, default))

func has_choice(choice_id: String) -> bool:
	return _story_choices.has(choice_id)

# ══════════════════════════════════════════
#  剧情标记（通用 flag 系统）
# ══════════════════════════════════════════
func set_flag(flag_name: String, value: Variant = true) -> void:
	_story_flags[flag_name] = value
	save_story_save()

func get_flag(flag_name: String, default: Variant = null) -> Variant:
	return _story_flags.get(flag_name, default)

func has_flag(flag_name: String) -> bool:
	return _story_flags.has(flag_name)

# ══════════════════════════════════════════
#  独立存档（保存到 saves/{username}/story_progress.json）
# ══════════════════════════════════════════
func _get_save_path() -> String:
	if main == null or main.user_mgr == null or not main.user_mgr.is_logged_in:
		return ""
	if main.save_mgr == null:
		return ""
	var user_dir: String = main.save_mgr.get_game_root_dir() + "saves/" + main.user_mgr.get_username() + "/"
	return user_dir + "story_progress.json"

func save_story_save() -> Dictionary:
	## 保存主线剧情进度到独立文件
	if main == null or main.get("user_mgr") == null or main.get("save_mgr") == null:
		return SaveManager.save_result("failed", "dependency", ERR_UNCONFIGURED)
	if not main.user_mgr.is_logged_in:
		return SaveManager.save_result("skipped", "no_account")
	var evidence: Dictionary = _check_story_evidence()
	if evidence.status != "saved":
		return evidence
	if _story_evidence_blocked:
		return SaveManager.save_result("failed", "story_reload_required", ERR_FILE_CORRUPT)
	var path: String = _get_save_path()
	var save_data: Dictionary = {
		"pending_dialogues": _pending_dialogues.duplicate(true),
		"story_day": _story_day,
		"triggered_today": _triggered_today.duplicate(),
		"completed_dialogues": _completed_dialogues.duplicate(),
		"story_choices": _story_choices.duplicate(),
		"story_flags": _story_flags.duplicate(),
		"story_version": _story_version,
		"archive_effect_receipts": _archive_effect_receipts.duplicate(true),
		"saved_at": Time.get_datetime_string_from_system(),
	}
	return SaveManager.write_json_checked(path, save_data)

func load_story_save() -> void:
	_completion_notice_day = -1
	_story_evidence_blocked = false
	_archive_effect_receipts.clear()
	## 从独立文件加载主线剧情进度
	_pending_dialogues.clear()
	# 新账号没有剧情文件时也必须清空前一账号的内存状态。
	_completed_dialogues.clear()
	_story_choices.clear()
	_story_flags.clear()
	_triggered_today.clear()
	var path: String = _get_save_path()
	if DirAccess.dir_exists_absolute(path):
		_story_evidence_blocked = true
		return
	if path.is_empty() or not FileAccess.file_exists(path):
		_story_evidence_blocked = _has_archive_story_evidence()
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_story_evidence_blocked = true
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not _valid_story_evidence(json.data):
		file.close()
		_story_evidence_blocked = true
		return
	file.close()
	var data: Dictionary = json.data
	# ★ 剧情版本门控：主线剧情版本变化时重置剧情进度（新剧情从头开始）
	if not _story_version.is_empty() and str(data.get("story_version", "")) != _story_version:
		print("[DailyDialogue] 剧情版本不匹配（%s → %s），重置主线剧情进度" % [
			str(data.get("story_version", "")), _story_version])
		_triggered_today.clear()
		_completed_dialogues.clear()
		_story_choices.clear()
		_story_flags.clear()
		return
	_archive_effect_receipts = data.get("archive_effect_receipts", {}).duplicate(true)
	_story_day = int(data.get("story_day", 1))
	_pending_dialogues = data.get("pending_dialogues", []).duplicate(true)
	if data.has("triggered_today"):
		_triggered_today = data["triggered_today"]
	if data.has("completed_dialogues"):
		_completed_dialogues.clear()
		for d in data["completed_dialogues"]:
			_completed_dialogues.append(str(d))
	if data.has("story_choices"):
		_story_choices = data["story_choices"]
	if data.has("story_flags"):
		_story_flags = data["story_flags"]
	print("[DailyDialogue] 主线存档已加载: day=%d, choices=%d, flags=%d" % [_story_day, _story_choices.size(), _story_flags.size()])

# ══════════════════════════════════════════
#  兼容旧存档（disc_manager 调用的接口保留）
# ══════════════════════════════════════════
func get_save_data() -> Dictionary:
	return {
		"pending_dialogues": _pending_dialogues.duplicate(true),
		"triggered_today": _triggered_today.duplicate(),
		"story_day": _story_day,
		"completed_dialogues": _completed_dialogues.duplicate(),
		"story_choices": _story_choices.duplicate(),
		"story_flags": _story_flags.duplicate(),
	}

func load_save_data(data: Dictionary) -> void:
	_pending_dialogues = data.get("pending_dialogues", []).duplicate(true)
	if data.has("triggered_today"):
		_triggered_today = data["triggered_today"]
	if data.has("story_day"):
		_story_day = int(data["story_day"])
	if data.has("completed_dialogues"):
		_completed_dialogues.clear()
		for d in data["completed_dialogues"]:
			_completed_dialogues.append(str(d))
	if data.has("story_choices"):
		_story_choices = data["story_choices"]
	if data.has("story_flags"):
		_story_flags = data["story_flags"]

# ══════════════════════════════════════════
#  内部
# ══════════════════════════════════════════
func _deliver_day_mails(day: int) -> void:
	## 投递当日配置中的邮件（mail_deliveries 字段；deliver_on="scene" 的由场景内触发）
	if main.mail_sys == null:
		return
	var day_key: String = str(day)
	var config: Dictionary = {}
	if _daily_config.has(day_key):
		config = _daily_config[day_key]
	elif _daily_config.has("default"):
		config = _daily_config["default"]
	var mails: Array = config.get("mail_deliveries", [])
	for mail_def in mails:
		if not (mail_def is Dictionary):
			continue
		# ★ 场景内投递的邮件跳过（由对话的 deliver_mail 字段触发）
		if str(mail_def.get("deliver_on", "")) == "scene":
			continue
		_deliver_mail_def(mail_def)

## ★ 投递场景内邮件（对话的 deliver_mail 字段调用，按 id 从当日配置查找）
func deliver_scene_mail(mail_id: String) -> void:
	if main == null or main.mail_sys == null:
		return
	var day_key: String = str(_story_day)
	var config: Dictionary = {}
	if _daily_config.has(day_key):
		config = _daily_config[day_key]
	elif _daily_config.has("default"):
		config = _daily_config["default"]
	var mails: Array = config.get("mail_deliveries", [])
	for mail_def in mails:
		if not (mail_def is Dictionary):
			continue
		if str(mail_def.get("id", "")) != mail_id:
			continue
		_deliver_mail_def(mail_def)
		return

func _deliver_mail_def(mail_def: Dictionary) -> void:
	var mail_id: String = str(mail_def.get("id", ""))
	if mail_id.is_empty():
		return
	var title: String = str(mail_def.get("title", mail_id))
	var from: String = str(mail_def.get("from", "SYSTEM"))
	var body: String = str(mail_def.get("body", ""))
	var persistent: bool = bool(mail_def.get("persistent", true))
	main.mail_sys.deliver_inline_mail(mail_id, title, from, body, persistent)

func _get_trigger_list(day: int, event_type: String) -> Array:
	var day_key: String = str(day)
	var config: Dictionary = {}
	if _daily_config.has(day_key):
		config = _daily_config[day_key]
	elif _daily_config.has("default"):
		config = _daily_config["default"]
	return config.get(event_type, [])

func _trigger_dialogues(dlg_ids: Array) -> void:
	if main == null or main.comm_mgr == null:
		return
	if dlg_ids.size() == 0:
		return
	# 过滤掉已完成且不可重复的对话，以及条件不满足的对话
	var valid_ids: Array = _filter_playable(dlg_ids)
	if valid_ids.size() == 0:
		return
	_pending_dialogues.append({"ids": valid_ids, "day": _story_day, "delay": 1.5})
	save_story_save()

## 现实时间后安排独立来电；截止时间存档，界面被覆盖时不丢失来电。
func schedule_dialogue(dlg_id: String, real_seconds: float) -> void:
	if _filter_playable([dlg_id]).is_empty():
		return
	for pending in _pending_dialogues:
		if dlg_id in pending.get("ids", []):
			return
	_pending_dialogues.append({"ids": [dlg_id], "day": _story_day,
		"due_unix": Time.get_unix_time_from_system() + maxf(0.0, real_seconds)})
	save_story_save()

## 剧情奖励独立去重，防止调试重播或中断后重复领取。
func award_score_once(reward_id: String, amount: int, category: String) -> void:
	var flag_name: String = "reward:" + reward_id
	if bool(get_flag(flag_name, false)) or main == null or main.perf_mgr == null:
		return
	main.perf_mgr.add_score(amount, category)
	main.perf_mgr.save_progress()
	set_flag(flag_name, true)

func process_pending(delta: float) -> void:
	# 延迟期间重新检查覆盖界面，防止重新打开 mail/env 后被来电穿透。
	if _story_day == 2:
		update_day2_progress()
	show_day_complete_notice()
	if _pending_dialogues.is_empty() or main == null or main.comm_mgr == null:
		return
	if main.is_terminal_covered() or main._command_running or main.comm_mgr.is_active or main.comm_mgr.is_call_ringing() or main.comm_mgr.has_pending_call_answer():
		return
	if main.dial_mgr and main.dial_mgr.is_active():
		return
	var pending: Dictionary = _pending_dialogues[0]
	if int(pending.get("day", -1)) != _story_day:
		_pending_dialogues.pop_front()
		return
	if pending.has("due_unix"):
		if Time.get_unix_time_from_system() < float(pending["due_unix"]):
			return
	else:
		pending["delay"] = float(pending.get("delay", 1.5)) - delta
		if float(pending["delay"]) > 0:
			return
	_pending_dialogues.pop_front()
	save_story_save()
	var ids: Array = _filter_playable(pending.get("ids", []))
	if ids.size() == 1:
		main.comm_mgr.trigger_dialogue(str(ids[0]))
	elif ids.size() > 1:
		main.comm_mgr.trigger_dialogue_sequence(ids)

## A session-only reminder; it never advances the day or awards performance.
func show_day_complete_notice() -> void:
	# Completion behavior belongs to the content package.
	pass

func _filter_playable(dlg_ids: Array) -> Array:
	var valid_ids: Array = []
	for dlg_id in dlg_ids:
		var sid: String = str(dlg_id)
		if main == null or main.comm_mgr == null:
			continue
		if main.comm_mgr.has_dialogue(sid):
			var dlg_data: Dictionary = main.comm_mgr.get_dialogue_data(sid)
			var repeatable: bool = dlg_data.get("repeatable", false)
			if not repeatable and sid in _completed_dialogues:
				continue
			if not repeatable and main.comm_mgr.is_dialogue_completed(sid):
				continue
			# ★ 检查前置条件（需要某个选项或标记）
			if not _check_conditions(dlg_data):
				continue
			valid_ids.append(sid)
	return valid_ids

## ★ 公开条件检查（供 comm_manager 拨号选择对话时调用）
func check_dialogue_conditions(dlg_data: Dictionary) -> bool:
	return _check_conditions(dlg_data)

func _check_conditions(dlg_data: Dictionary) -> bool:
	## 检查对话的前置条件是否满足
	if dlg_data.has("requires_day") and int(dlg_data["requires_day"]) != _story_day:
		return false
	# requires_choice: {"choice_id": "expected_value"}
	var req_choice: Dictionary = dlg_data.get("requires_choice", {})
	for choice_id in req_choice.keys():
		if get_choice(choice_id) != str(req_choice[choice_id]):
			return false
	# requires_flag: {"flag_name": expected_value}
	var req_flag: Dictionary = dlg_data.get("requires_flag", {})
	for flag_name in req_flag.keys():
		if not has_flag(flag_name):
			return false
		# 简单值比较（JSON 解析的数字为 float，flag 可能存为 int，需数值兼容）
		var expected = req_flag[flag_name]
		var actual = get_flag(flag_name)
		if (expected is float or expected is int) and (actual is float or actual is int):
			if float(actual) != float(expected):
				return false
		elif str(actual) != str(expected):
			return false
	# ★ requires_tasks: "all"（当日 env 任务全部完成）/ "incomplete"（未全部完成）
	var req_tasks: String = str(dlg_data.get("requires_tasks", ""))
	if not req_tasks.is_empty():
		if main == null or main.env_task_mgr == null:
			return false
		var all_done: bool = main.env_task_mgr.is_all_required_completed() \
				and main.env_task_mgr.report_submitted
		# 邮件阅读也属于岗前任务；不能只核查 ENV 就判定全部完成。
		for mail_id in dlg_data.get("required_task_mails", []):
			var mail_read: bool = main.mail_sys != null and main.mail_sys.is_mail_read(str(mail_id))
			all_done = all_done and mail_read
		if req_tasks == "all" and not all_done:
			return false
		if req_tasks == "incomplete" and all_done:
			return false
	return true

func mark_dialogue_completed(dlg_id: String) -> void:
	if dlg_id not in _completed_dialogues:
		_completed_dialogues.append(dlg_id)
		save_story_save()

func get_environment_config(day: int) -> Dictionary:
	# 缺省环境与当日字段合并；显式 contacts/events 空数组表示清空。
	var result: Dictionary = {}
	for key in ["default", str(day)]:
		var day_data: Variant = _daily_config.get(key, {})
		if not (day_data is Dictionary): continue
		var environment: Variant = day_data.get("environment", {})
		if environment is Dictionary: result.merge(environment, true)
	return result

func day2_tasks_complete() -> bool:
	return false

func update_day2_progress() -> void:
	pass

func prepare_day2_dialogue(dialogue_id: String, data: Dictionary) -> Dictionary:
	return data

func day2_contact_dialogue(character_id: String) -> String:
	return ""

func commit_archive_effects(operation_id: String, flags: Dictionary, feedback: String, version: String) -> Dictionary:
	if version != _story_version or operation_id.is_empty():
		return SaveManager.save_result("failed", "story_context", ERR_INVALID_DATA)
	var evidence: Dictionary = _check_story_evidence()
	if evidence.status != "saved":
		return evidence
	if _story_evidence_blocked:
		load_story_save()
		if _story_evidence_blocked:
			return SaveManager.save_result("failed", "story_reload_required", ERR_FILE_CORRUPT)
	var receipt: Dictionary = JSON.parse_string(JSON.stringify({"flags": flags, "feedback": feedback}))
	if _archive_effect_receipts.has(operation_id):
		if _archive_effect_receipts[operation_id] != receipt:
			return SaveManager.save_result("failed", "story_conflict", ERR_INVALID_DATA)
	else:
		for key in flags:
			_story_flags[key] = flags[key]
		if not feedback.is_empty() and not _filter_playable([feedback]).is_empty():
			_pending_dialogues.append({"ids": [feedback], "day": _story_day, "due_unix": Time.get_unix_time_from_system()})
		_archive_effect_receipts[operation_id] = receipt
	return save_story_save()

func has_archive_effect_receipt(operation_id: String) -> bool:
	var evidence: Dictionary = _check_story_evidence()
	if evidence.status != "saved" or not evidence.has("data"):
		return false
	if str(evidence.data.get("story_version", "")) != _story_version:
		return false
	if _story_evidence_blocked:
		load_story_save()
	var persisted: Dictionary = evidence.data.get("archive_effect_receipts", {})
	if not _archive_effect_receipts.has(operation_id) or not persisted.get(operation_id) is Dictionary:
		return false
	return JSON.stringify(JSON.parse_string(JSON.stringify(_archive_effect_receipts[operation_id]))) == JSON.stringify(persisted[operation_id])

## 已知归档意味着剧情文件是恢复证据；缺失不能再按首次登录建空白档。
func _has_archive_story_evidence() -> bool:
	if not _archive_effect_receipts.is_empty():
		return true
	if main == null or main.user_mgr == null or not main.user_mgr.is_logged_in:
		return false
	var data: Dictionary = main.user_mgr.current_user.get("vdisc_task_data", {})
	if not (data.get("archive", []) as Array).is_empty():
		return true
	for state in (data.get("tasks", {}) as Dictionary).values():
		if not str(state.get("archive_operation", "")).is_empty():
			return true
	# 意图可能已写入，但 profile 尚未确认；仅检查当前账号的专用操作目录。
	var operations: String = _get_save_path().get_base_dir().path_join("vdisc/archive_operations")
	if DirAccess.dir_exists_absolute(operations):
		for filename in DirAccess.get_files_at(operations):
			if filename.get_extension() == "json":
				return true
	return false

func _valid_story_evidence(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	for key in ["story_flags", "story_choices", "triggered_today", "archive_effect_receipts"]:
		if data.has(key) and not data[key] is Dictionary:
			return false
	for key in ["pending_dialogues", "completed_dialogues"]:
		if data.has(key) and not data[key] is Array:
			return false
	return true

## 不清除损坏锁存；有效文件恢复后由归档入口先重载，再允许写入。
func _check_story_evidence() -> Dictionary:
	var path: String = _get_save_path()
	if path.is_empty():
		return SaveManager.save_result("failed", "story_dependency", ERR_UNCONFIGURED)
	if not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path):
		_story_evidence_blocked = _story_evidence_blocked or _has_archive_story_evidence()
		return SaveManager.save_result("failed", "story_evidence_missing", ERR_FILE_NOT_FOUND) if _story_evidence_blocked else SaveManager.save_result("saved", "first_story")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return SaveManager.save_result("failed", "open", FileAccess.get_open_error())
	var json := JSON.new()
	var parsed: Error = json.parse(file.get_as_text())
	file.close()
	if parsed != OK or not _valid_story_evidence(json.data):
		_story_evidence_blocked = true
		return SaveManager.save_result("failed", "story_evidence", ERR_FILE_CORRUPT)
	return {"status": "saved", "stage": "existing_story", "error": OK, "data": json.data}
