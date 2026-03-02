# ============================================================
# user_manager.gd - 多用户账户管理系统
# 负责：账户创建/登录/切换、档案存储、统计数据、系统评价
# ============================================================
class_name UserManager
extends RefCounted

# ============================================================
# 常量
# ============================================================
const AVATAR_SIZE: int = 64
const MIN_USERNAME_LENGTH: int = 2
const MAX_USERNAME_LENGTH: int = 16
const MIN_PASSWORD_LENGTH: int = 4
const ADMIN_USERNAME: String = "Admin"
const ADMIN_PASSWORD: String = "admin"

# ============================================================
# 引用
# ============================================================
var T = null

# ============================================================
# 状态
# ============================================================
var current_user: Dictionary = {}
var is_logged_in: bool = false
var _save_root: String = ""
var _session_start_time: int = 0

# ============================================================
# 初始化
# ============================================================
func setup(p_theme, save_manager = null) -> void:
	T = p_theme
	if save_manager:
		_save_root = save_manager.get_game_root_dir() + "saves/"
	else:
		if OS.has_feature("editor"):
			_save_root = ProjectSettings.globalize_path("res://") + "saves/"
		else:
			_save_root = OS.get_executable_path().get_base_dir() + "/saves/"
	_ensure_dirs()
	_ensure_admin_account()

# ============================================================
# 目录结构
# ============================================================
func _ensure_dirs() -> void:
	if not DirAccess.dir_exists_absolute(_save_root):
		DirAccess.make_dir_recursive_absolute(_save_root)

func _get_user_dir(username: String) -> String:
	return _save_root + username + "/"

func _get_profile_path(username: String) -> String:
	return _get_user_dir(username) + "profile.json"

func _get_global_config_path() -> String:
	return _save_root + "_global.json"

func get_save_path_for_user(username: String, story_id: String) -> String:
	return _get_user_dir(username) + "save_" + story_id + ".json"

func get_mail_dir(username: String = "") -> String:
	if username.is_empty():
		if not is_logged_in:
			return ""
		username = get_username()
	return _get_user_dir(username) + "mail/"

func ensure_mail_dir(username: String = "") -> String:
	var mail_dir: String = get_mail_dir(username)
	if mail_dir.is_empty():
		return ""
	if not DirAccess.dir_exists_absolute(mail_dir):
		DirAccess.make_dir_recursive_absolute(mail_dir)
	return mail_dir


# ============================================================
# 管理员预设账户
# ============================================================
func _ensure_admin_account() -> void:
	if not user_exists(ADMIN_USERNAME):
		var profile: Dictionary = _create_default_profile(ADMIN_USERNAME, ADMIN_PASSWORD)
		profile["role"] = "admin"
		profile["title"] = "系统管理员"
		profile["badge"] = "O5-COUNCIL"
		profile["system_notes"] = [
			{
				"from": "SYSTEM",
				"date": _get_current_datetime(),
				"content": "管理员账户已自动创建。此账户拥有最高权限。",
				"tone": "neutral"
			},
			{
				"from": "O5-1",
				"date": _get_current_datetime(),
				"content": "欢迎来到基金会终端系统。请谨慎操作。",
				"tone": "warning"
			}
		]
		_save_profile(ADMIN_USERNAME, profile)
		print("[UserManager] 管理员账户已创建: ", ADMIN_USERNAME, "/", ADMIN_PASSWORD)

# ============================================================
# 账户查询
# ============================================================
func user_exists(username: String) -> bool:
	return FileAccess.file_exists(_get_profile_path(username))

func get_all_users() -> Array[String]:
	var users: Array[String] = []
	var dir := DirAccess.open(_save_root)
	if dir == null:
		return users
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir() and not entry.begins_with("_") and not entry.begins_with("."):
			if FileAccess.file_exists(_get_profile_path(entry)):
				users.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	users.sort()
	return users

# ============================================================
# 注册
# ============================================================
func register(username: String, password: String) -> Dictionary:
	var name_check: Dictionary = _validate_username(username)
	if not name_check["valid"]:
		return { "success": false, "message": name_check["message"] }

	if password.length() < MIN_PASSWORD_LENGTH:
		return { "success": false, "message": "密码长度不能少于 " + str(MIN_PASSWORD_LENGTH) + " 个字符。" }

	if user_exists(username):
		return { "success": false, "message": "用户名 \"" + username + "\" 已被占用。" }

	var profile: Dictionary = _create_default_profile(username, password)
	profile["system_notes"] = [
		{
			"from": "SYSTEM",
			"date": _get_current_datetime(),
			"content": "新操作员档案已建立。等待安全审查。",
			"tone": "neutral"
		}
	]
	_save_profile(username, profile)

	current_user = profile
	is_logged_in = true
	_session_start_time = int(Time.get_unix_time_from_system())
	current_user["login_count"] = 1
	current_user["last_login"] = _get_current_datetime()
	_save_current_profile()
	_save_last_login_user(username)

	return { "success": true, "message": "档案创建成功。欢迎, " + username + "。" }

# ============================================================
# 登录
# ============================================================
func login(username: String, password: String) -> Dictionary:
	if not user_exists(username):
		return { "success": false, "message": "未找到用户 \"" + username + "\"。" }

	var profile: Dictionary = _load_profile(username)
	if profile.is_empty():
		return { "success": false, "message": "档案读取失败。" }

	if str(profile.get("password", "")) != password:
		var fail_count: int = int(profile.get("login_fail_count", 0)) + 1
		profile["login_fail_count"] = fail_count
		profile["last_fail_time"] = _get_current_datetime()
		_save_profile(username, profile)

		var warning: String = ""
		if fail_count >= 5:
			warning = "\n[安全警告: 多次认证失败已被记录]"
		return { "success": false, "message": "密码错误。(连续失败: " + str(fail_count) + " 次)" + warning }

	profile["login_fail_count"] = 0
	profile["last_login"] = _get_current_datetime()
	profile["login_count"] = int(profile.get("login_count", 0)) + 1
	_save_profile(username, profile)

	current_user = profile
	is_logged_in = true
	_session_start_time = int(Time.get_unix_time_from_system())
	_save_last_login_user(username)

	return { "success": true, "message": "身份确认。欢迎回来, " + username + "。" }

# ============================================================
# 登出
# ============================================================
func logout() -> void:
	if is_logged_in:
		_update_session_time()
		_save_current_profile()
	current_user = {}
	is_logged_in = false
	_session_start_time = 0

# ============================================================
# 修改密码
# ============================================================
func change_password(old_password: String, new_password: String) -> Dictionary:
	if not is_logged_in:
		return { "success": false, "message": "未登录。" }
	if str(current_user.get("password", "")) != old_password:
		return { "success": false, "message": "旧密码错误。" }
	if new_password.length() < MIN_PASSWORD_LENGTH:
		return { "success": false, "message": "新密码长度不能少于 " + str(MIN_PASSWORD_LENGTH) + " 个字符。" }

	current_user["password"] = new_password
	_save_current_profile()
	return { "success": true, "message": "密码已更新。" }

# ============================================================
# 删除账户
# ============================================================
func delete_user(username: String) -> Dictionary:
	if username == ADMIN_USERNAME:
		return { "success": false, "message": "管理员账户不可删除。" }
	if not user_exists(username):
		return { "success": false, "message": "用户不存在。" }

	if is_logged_in and get_username() == username:
		logout()

	var user_dir: String = _get_user_dir(username)
	var dir := DirAccess.open(user_dir)
	if dir:
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while not entry.is_empty():
			if not dir.current_is_dir():
				dir.remove(entry)
			entry = dir.get_next()
		dir.list_dir_end()
	DirAccess.remove_absolute(user_dir)

	return { "success": true, "message": "用户 \"" + username + "\" 及其所有数据已永久删除。" }

# ============================================================
# 设置生日
# ============================================================
func set_birthday(date_str: String) -> Dictionary:
	if not is_logged_in:
		return { "success": false, "message": "未登录。" }
	# 简单格式校验 YYYY-MM-DD
	var parts: PackedStringArray = date_str.split("-")
	if parts.size() != 3:
		return { "success": false, "message": "日期格式错误，请使用 YYYY-MM-DD 格式。" }
	for part in parts:
		if not part.is_valid_int():
			return { "success": false, "message": "日期格式错误，请使用 YYYY-MM-DD 格式。" }
	var year: int = int(parts[0])
	var month: int = int(parts[1])
	var day: int = int(parts[2])
	if year < 1900 or year > 2100 or month < 1 or month > 12 or day < 1 or day > 31:
		return { "success": false, "message": "日期不合法。" }

	current_user["birthday"] = date_str
	_save_current_profile()
	return { "success": true, "message": "出生日期已设置为 " + date_str + "。" }

# ============================================================
# 获取信息
# ============================================================
func get_username() -> String:
	return str(current_user.get("username", "UNKNOWN"))

func get_display_name() -> String:
	var title: String = str(current_user.get("title", ""))
	var name: String = get_username()
	if not title.is_empty():
		return title + " " + name
	return name

func get_role() -> String:
	return str(current_user.get("role", "user"))

func get_badge() -> String:
	return str(current_user.get("badge", ""))

# ============================================================
# 记住上次登录用户
# ============================================================
func get_last_login_user() -> String:
	var path: String = _get_global_config_path()
	if not FileAccess.file_exists(path):
		return ADMIN_USERNAME
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ADMIN_USERNAME
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return ADMIN_USERNAME
	file.close()
	var data: Dictionary = json.data if json.data is Dictionary else {}
	return str(data.get("last_user", ADMIN_USERNAME))

func _save_last_login_user(username: String) -> void:
	var path: String = _get_global_config_path()
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
				data = json.data
			file.close()
	data["last_user"] = username
	var write_file := FileAccess.open(path, FileAccess.WRITE)  # ← 改名
	if write_file:
		write_file.store_string(JSON.stringify(data, "\t"))
		write_file.close()


# ============================================================
# 统计
# ============================================================
func increment_command_count() -> void:
	_increment_stat("command_count")

func increment_files_read() -> void:
	_increment_stat("files_read_count")

func _increment_stat(key: String) -> void:
	if not is_logged_in:
		return
	current_user[key] = int(current_user.get(key, 0)) + 1

func _update_session_time() -> void:
	if not is_logged_in or _session_start_time == 0:
		return
	var now: int = int(Time.get_unix_time_from_system())
	var session_seconds: int = now - _session_start_time
	current_user["total_time_seconds"] = int(current_user.get("total_time_seconds", 0)) + session_seconds
	current_user["session_count"] = int(current_user.get("session_count", 0)) + 1

func _format_play_time(total_seconds: int) -> String:
	if total_seconds < 60:
		return str(total_seconds) + " 秒"
	@warning_ignore("integer_division")
	var minutes: int = total_seconds / 60
	if minutes < 60:
		return str(minutes) + " 分钟"
	@warning_ignore("integer_division")
	var hours: int = minutes / 60
	var remaining_min: int = minutes % 60
	return str(hours) + " 小时 " + str(remaining_min) + " 分钟"

func _get_current_session_time() -> int:
	if _session_start_time == 0:
		return 0
	return int(Time.get_unix_time_from_system()) - _session_start_time

# ============================================================
# 系统评价
# ============================================================
func add_system_note(note: Dictionary) -> void:
	if not is_logged_in:
		return
	if not current_user.has("system_notes"):
		current_user["system_notes"] = []
	note["date"] = _get_current_datetime()
	current_user["system_notes"].append(note)
	_save_current_profile()

func get_system_notes() -> Array:
	return current_user.get("system_notes", []) as Array

func inject_story_notes(manifest: Dictionary) -> void:
	if not is_logged_in:
		return
	if not manifest.has("user_notes"):
		return
	var notes: Array = manifest["user_notes"] as Array
	var username: String = get_username()
	for note in notes:
		var note_dict: Dictionary = (note as Dictionary).duplicate()
		var content: String = str(note_dict.get("content", ""))
		content = content.replace("{username}", username)
		note_dict["content"] = content
		var duplicate_found: bool = false
		for existing in get_system_notes():
			var ex: Dictionary = existing as Dictionary
			if str(ex.get("from", "")) == str(note_dict.get("from", "")) and str(ex.get("content", "")) == content:
				duplicate_found = true
				break
		if not duplicate_found:
			add_system_note(note_dict)



# ============================================================
# 获取 Profile 纯数据（供 ProfileBuilder 使用）
# ============================================================
func get_profile_data() -> Dictionary:
	if not is_logged_in:
		return {}

	var total_time: int = int(current_user.get("total_time_seconds", 0)) + _get_current_session_time()
	var birthday: String = str(current_user.get("birthday", ""))
	if birthday.is_empty():
		birthday = "未设置"

	return {
		"username": get_username(),
		"display_name": get_display_name(),
		"role": _get_role_display(),
		"badge": get_badge(),
		"avatar": _get_avatar_status(),
		"birthday": birthday,
		"created_at": str(current_user.get("created_at", "未知")),
		"last_login": str(current_user.get("last_login", "未知")),
		"login_count": int(current_user.get("login_count", 0)),
		"session_count": int(current_user.get("session_count", 0)),
		"total_time": _format_play_time(total_time),
		"command_count": int(current_user.get("command_count", 0)),
		"files_read_count": int(current_user.get("files_read_count", 0)),
		"login_fail_count": int(current_user.get("login_fail_count", 0)),
		"discs_loaded_count": int(current_user.get("discs_loaded_count", 0)),
		"system_notes": get_system_notes(),
		"installed_packages_count": int(current_user.get("installed_packages", {}).size()),
		"packages_installed_count": int(current_user.get("packages_installed_count", 0)),
	}



# ============================================================
# Profile 页面 - 第一页：基本信息
# ============================================================
func get_profile_page1() -> String:
	if not is_logged_in:
		return "[color=" + str(T.error_hex) + "]未登录。[/color]"

	var p: String = str(T.primary_hex)
	var m: String = str(T.muted_hex)
	var w: String = str(T.warning_hex)

	var role_display: String = _get_role_display()
	var badge: String = get_badge()
	var total_time: int = int(current_user.get("total_time_seconds", 0)) + _get_current_session_time()
	var birthday: String = str(current_user.get("birthday", ""))
	if birthday.is_empty():
		birthday = "未设置 (use: birthday YYYY-MM-DD)"

	var lines: String = ""
	lines += "\n"
	lines += "[color=" + p + "]╔══════════════════════════════════════════════╗[/color]\n"
	lines += "[color=" + p + "]║[/color]                                              [color=" + p + "]║[/color]\n"
	lines += "[color=" + p + "]║[/color]   [color=" + w + "]PERSONNEL FILE — 人员档案[/color]                [color=" + p + "]║[/color]\n"
	lines += "[color=" + p + "]║[/color]                                              [color=" + p + "]║[/color]\n"
	lines += "[color=" + p + "]╠══════════════════════════════════════════════╣[/color]\n"
	lines += "[color=" + p + "]║[/color]                                              [color=" + p + "]║[/color]\n"
	lines += "[color=" + p + "]║[/color]   [color=" + m + "]用户名    :[/color]  [color=" + p + "]" + get_username() + "[/color]\n"
	lines += "[color=" + p + "]║[/color]   [color=" + m + "]身份      :[/color]  [color=" + p + "]" + role_display + "[/color]\n"
	if not badge.is_empty():
		lines += "[color=" + p + "]║[/color]   [color=" + m + "]徽章      :[/color]  [color=" + w + "][" + badge + "][/color]\n"
	lines += "[color=" + p + "]║[/color]   [color=" + m + "]头像      :[/color]  " + _get_avatar_status() + "\n"
	lines += "[color=" + p + "]║[/color]   [color=" + m + "]出生日期  :[/color]  [color=" + p + "]" + birthday + "[/color]\n"
	lines += "[color=" + p + "]║[/color]                                              [color=" + p + "]║[/color]\n"
	lines += "[color=" + p + "]╠══════════════════════════════════════════════╣[/color]\n"
	lines += "[color=" + p + "]║[/color]                                              [color=" + p + "]║[/color]\n"
	lines += "[color=" + p + "]║[/color]   [color=" + m + "]创建时间  :[/color]  [color=" + p + "]" + str(current_user.get("created_at", "未知")) + "[/color]\n"
	lines += "[color=" + p + "]║[/color]   [color=" + m + "]上次登录  :[/color]  [color=" + p + "]" + str(current_user.get("last_login", "未知")) + "[/color]\n"
	lines += "[color=" + p + "]║[/color]   [color=" + m + "]登录次数  :[/color]  [color=" + p + "]" + str(current_user.get("login_count", 0)) + "[/color]\n"
	lines += "[color=" + p + "]║[/color]   [color=" + m + "]会话次数  :[/color]  [color=" + p + "]" + str(current_user.get("session_count", 0)) + "[/color]\n"
	lines += "[color=" + p + "]║[/color]   [color=" + m + "]总使用时长:[/color]  [color=" + p + "]" + _format_play_time(total_time) + "[/color]\n"
	lines += "[color=" + p + "]║[/color]                                              [color=" + p + "]║[/color]\n"
	lines += "[color=" + p + "]╠══════════════════════════════════════════════╣[/color]\n"
	lines += "[color=" + p + "]║[/color]   [color=" + m + "]输入 profile 2 查看统计数据与系统评价[/color]    [color=" + p + "]║[/color]\n"
	lines += "[color=" + p + "]╚══════════════════════════════════════════════╝[/color]\n"
	return lines

# ============================================================
# Profile 页面 - 第二页：统计 + 系统评价
# ============================================================
func get_profile_page2() -> String:
	if not is_logged_in:
		return "[color=" + str(T.error_hex) + "]未登录。[/color]"

	var p: String = str(T.primary_hex)
	var m: String = str(T.muted_hex)
	var w: String = str(T.warning_hex)
	var e: String = str(T.error_hex)
	var s: String = str(T.success_hex)

	var lines: String = ""
	lines += "\n"
	lines += "[color=" + p + "]╔══════════════════════════════════════════════╗[/color]\n"
	lines += "[color=" + p + "]║[/color]                                              [color=" + p + "]║[/color]\n"
	lines += "[color=" + p + "]║[/color]   [color=" + w + "]ACTIVITY LOG — 活动记录[/color]                  [color=" + p + "]║[/color]\n"
	lines += "[color=" + p + "]║[/color]                                              [color=" + p + "]║[/color]\n"
	lines += "[color=" + p + "]╠══════════════════════════════════════════════╣[/color]\n"
	lines += "[color=" + p + "]║[/color]                                              [color=" + p + "]║[/color]\n"
	lines += "[color=" + p + "]║[/color]   [color=" + m + "]执行命令数  :[/color]  [color=" + p + "]" + str(current_user.get("command_count", 0)) + "[/color]\n"
	lines += "[color=" + p + "]║[/color]   [color=" + m + "]查阅文件数  :[/color]  [color=" + p + "]" + str(current_user.get("files_read_count", 0)) + "[/color]\n"
	lines += "[color=" + p + "]║[/color]   [color=" + m + "]认证失败数  :[/color]  [color=" + p + "]" + str(current_user.get("login_fail_count", 0)) + "[/color]\n"
	lines += "[color=" + p + "]║[/color]   [color=" + m + "]已加载磁盘  :[/color]  [color=" + p + "]" + str(current_user.get("discs_loaded_count", 0)) + "[/color]\n"
	lines += "[color=" + p + "]║[/color]                                              [color=" + p + "]║[/color]\n"

	# ── 系统评价 ──
	lines += "[color=" + p + "]╠══════════════════════════════════════════════╣[/color]\n"
	lines += "[color=" + p + "]║[/color]                                              [color=" + p + "]║[/color]\n"
	lines += "[color=" + p + "]║[/color]   [color=" + w + "]SYSTEM EVALUATION — 系统评价[/color]            [color=" + p + "]║[/color]\n"
	lines += "[color=" + p + "]║[/color]                                              [color=" + p + "]║[/color]\n"
	lines += "[color=" + p + "]╠══════════════════════════════════════════════╣[/color]\n"

	var notes: Array = get_system_notes()
	if notes.is_empty():
		lines += "[color=" + p + "]║[/color]                                              [color=" + p + "]║[/color]\n"
		lines += "[color=" + p + "]║[/color]   [color=" + m + "](暂无系统评价)[/color]                          [color=" + p + "]║[/color]\n"
		lines += "[color=" + p + "]║[/color]                                              [color=" + p + "]║[/color]\n"
	else:
		# 最多显示最近10条
		var display_notes: Array = notes
		if display_notes.size() > 10:
			display_notes = notes.slice(notes.size() - 10, notes.size())
			lines += "[color=" + p + "]║[/color]   [color=" + m + "](显示最近 10 条，共 " + str(notes.size()) + " 条)[/color]\n"

		for note in display_notes:
			var n: Dictionary = note as Dictionary
			var from_str: String = str(n.get("from", "UNKNOWN"))
			var content_str: String = str(n.get("content", ""))
			var tone: String = str(n.get("tone", "neutral"))
			var date_str: String = str(n.get("date", ""))

			var tone_color: String = m
			match tone:
				"positive":
					tone_color = s
				"warning":
					tone_color = w
				"hostile":
					tone_color = e
				"redacted":
					content_str = "██████████████████"
					tone_color = e

			lines += "[color=" + p + "]║[/color]\n"
			lines += "[color=" + p + "]║[/color]   [color=" + m + "]" + date_str + "[/color]\n"
			lines += "[color=" + p + "]║[/color]   [color=" + w + "]<" + from_str + ">[/color]\n"
			lines += "[color=" + p + "]║[/color]   [color=" + tone_color + "]\"" + content_str + "\"[/color]\n"

	lines += "[color=" + p + "]║[/color]                                              [color=" + p + "]║[/color]\n"

	# ── 预留扩展区 ──
	lines += "[color=" + p + "]╠══════════════════════════════════════════════╣[/color]\n"
	lines += "[color=" + p + "]║[/color]                                              [color=" + p + "]║[/color]\n"
	lines += "[color=" + p + "]║[/color]   [color=" + m + "](更多内容将在后续版本中解锁)[/color]            [color=" + p + "]║[/color]\n"
	lines += "[color=" + p + "]║[/color]                                              [color=" + p + "]║[/color]\n"
	lines += "[color=" + p + "]╚══════════════════════════════════════════════╝[/color]\n"
	return lines

# ============================================================
# whoami 文本
# ============================================================
func get_whoami_text() -> String:
	if not is_logged_in:
		return "[color=" + str(T.error_hex) + "]未登录。[/color]"
	var p: String = str(T.primary_hex)
	var m: String = str(T.muted_hex)
	var w: String = str(T.warning_hex)
	var result: String = ""
	result += "[color=" + p + "]" + get_display_name() + "[/color]\n"
	result += "[color=" + m + "]角色: " + _get_role_display() + "[/color]\n"
	var badge: String = get_badge()
	if not badge.is_empty():
		result += "[color=" + m + "]徽章: [/color][color=" + w + "][" + badge + "][/color]\n"
	result += "[color=" + m + "]登录次数: " + str(current_user.get("login_count", 0)) + "[/color]\n"
	result += "[color=" + m + "]本次会话: " + _format_play_time(_get_current_session_time()) + "[/color]\n"
	return result

# ============================================================
# 内部工具
# ============================================================
func _validate_username(username: String) -> Dictionary:
	if username.length() < MIN_USERNAME_LENGTH:
		return { "valid": false, "message": "用户名长度不能少于 " + str(MIN_USERNAME_LENGTH) + " 个字符。" }
	if username.length() > MAX_USERNAME_LENGTH:
		return { "valid": false, "message": "用户名长度不能超过 " + str(MAX_USERNAME_LENGTH) + " 个字符。" }
	var forbidden: Array[String] = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", ".", " "]
	for ch in forbidden:
		if username.contains(ch):
			return { "valid": false, "message": "用户名不能包含特殊字符: " + ch }
	if username.begins_with("_"):
		return { "valid": false, "message": "用户名不能以下划线开头。" }
	# 禁止与管理员账户同名（不区分大小写）
	if username.to_lower() == ADMIN_USERNAME.to_lower() and username != ADMIN_USERNAME:
		return { "valid": false, "message": "该用户名为保留名称。" }
	return { "valid": true, "message": "" }

func _create_default_profile(username: String, password: String) -> Dictionary:
	return {
		"username": username,
		"password": password,
		"role": "user",
		"title": "",
		"badge": "",
		"avatar": "",
		"birthday": "",
		"created_at": _get_current_datetime(),
		"last_login": _get_current_datetime(),
		"login_count": 0,
		"login_fail_count": 0,
		"last_fail_time": "",
		"session_count": 0,
		"total_time_seconds": 0,
		"command_count": 0,
		"files_read_count": 0,
		"discs_loaded_count": 0,
		"system_notes": [],
		"achievements": [],
		"installed_packages": {},
		"preferences": {
			"theme": "",
			"typing_speed": 1.0
		}
	}

func _get_role_display() -> String:
	var role: String = get_role()
	match role:
		"admin":
			return "系统管理员"
		"user":
			return "标准操作员"
		_:
			return role

func _get_avatar_status() -> String:
	var m: String = str(T.muted_hex)
	var p: String = str(T.primary_hex)
	var avatar_path: String = str(current_user.get("avatar", ""))
	if avatar_path.is_empty():
		return "[color=" + m + "]未设置[/color]"
	return "[color=" + p + "]" + avatar_path + " (" + str(AVATAR_SIZE) + "x" + str(AVATAR_SIZE) + ")[/color]"

func _get_current_datetime() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		dt["year"], dt["month"], dt["day"],
		dt["hour"], dt["minute"], dt["second"]
	]

# ============================================================
# 存档读写
# ============================================================
func _load_profile(username: String) -> Dictionary:
	var path: String = _get_profile_path(username)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		return {}
	if json.data is Dictionary:
		return json.data
	return {}

func _save_profile(username: String, profile: Dictionary) -> void:
	var user_dir: String = _get_user_dir(username)
	if not DirAccess.dir_exists_absolute(user_dir):
		DirAccess.make_dir_recursive_absolute(user_dir)
	var path: String = _get_profile_path(username)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(profile, "\t"))
		file.close()

func _save_current_profile() -> void:
	if is_logged_in and current_user.has("username"):
		_save_profile(get_username(), current_user)

# ============================================================
# 故事包存档（当前用户）
# ============================================================
func save_story_progress(story_id: String, data: Dictionary) -> void:
	if not is_logged_in or story_id.is_empty():
		return
	var path: String = get_save_path_for_user(get_username(), story_id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		data["username"] = get_username()
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		print("[UserManager] 已保存故事进度: ", path)

func load_story_progress(story_id: String) -> Dictionary:
	if not is_logged_in or story_id.is_empty():
		return {}
	var path: String = get_save_path_for_user(get_username(), story_id)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		return {}
	if json.data is Dictionary:
		return json.data
	return {}

func has_story_save(story_id: String) -> bool:
	if not is_logged_in or story_id.is_empty():
		return false
	return FileAccess.file_exists(get_save_path_for_user(get_username(), story_id))
