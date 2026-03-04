# ============================================================
# profile_builder.gd - 人员档案页面构建器
# 使用 DocumentViewer 展示用户 profile 的全屏双栏视图
# ============================================================
class_name ProfileBuilder
extends RefCounted

var main = null
var fs: FileSystem = null
var T = null
var viewer: DocumentViewer = null
var user_mgr = null

func setup(p_main, p_fs, p_theme, p_viewer, p_user_mgr) -> void:
	main = p_main
	fs = p_fs
	T = p_theme
	viewer = p_viewer
	user_mgr = p_user_mgr

# ══════════════════════════════════════════
#  构建并打开 profile 查看器
# ══════════════════════════════════════════
func open_profile(page_num: int = 0) -> void:
	if not user_mgr.is_logged_in:
		main.append_output("[color=" + T.error_hex + "]请先登录。[/color]\n", false)
		return

	var data: Dictionary = user_mgr.get_profile_data()
	if data.is_empty():
		main.append_output("[color=" + T.error_hex + "]无法读取档案数据。[/color]\n", false)
		return

	var display_name: String = str(data.get("display_name", "UNKNOWN"))
	
	# 构建完整内容，用 ---PAGE--- 标记手动分页点
	var full_content: String = _build_page1(data) + "\n---PAGE---\n" + _build_page2(data) + "\n---PAGE---\n" + _build_page3(data)
	
	var pages: Array[Dictionary] = [{"content": full_content}]
	
	viewer.open("profile", pages, "PERSONNEL FILE — " + display_name)




# ══════════════════════════════════════════
#  第1页：基本信息（纯文本行，无外框）
# ══════════════════════════════════════════
func _build_page1(data: Dictionary) -> String:
	var m: String = T.muted_hex
	var w: String = T.warning_hex

	var lines: Array[String] = []
	lines.append("[color=" + w + "]PERSONNEL FILE — 人员档案[/color]")
	lines.append("")
	lines.append(_kv("用户名", str(data.get("username", ""))))
	lines.append(_kv("昵称", str(data.get("nickname", "未设置"))))
	lines.append(_kv("身份", str(data.get("role", ""))))

	var badge: String = str(data.get("badge", ""))
	if not badge.is_empty():
		lines.append(_kv("徽章", "[color=" + w + "][" + badge + "][/color]"))

	lines.append(_kv("头像", str(data.get("avatar", "未设置"))))
	lines.append(_kv("性别", str(data.get("gender", "未设置"))))
	lines.append(_kv("出生日期", str(data.get("birthday", "未设置"))))
	lines.append("")
	lines.append("[color=" + m + "]" + "-".repeat(30) + "[/color]")
	lines.append("")
	lines.append(_kv("创建时间", str(data.get("created_at", ""))))
	lines.append(_kv("上次登录", str(data.get("last_login", ""))))
	lines.append(_kv("登录次数", str(data.get("login_count", 0))))
	lines.append(_kv("会话次数", str(data.get("session_count", 0))))
	lines.append(_kv("总使用时长", str(data.get("total_time", ""))))

	return "\n".join(lines)

# ══════════════════════════════════════════
#  第2页：统计 + 系统评价（纯文本行，无外框）
# ══════════════════════════════════════════
func _build_page2(data: Dictionary) -> String:
	var m: String = T.muted_hex
	var w: String = T.warning_hex
	var e: String = T.error_hex
	var s: String = T.success_hex

	var lines: Array[String] = []
	lines.append("[color=" + w + "]ACTIVITY LOG — 活动记录[/color]")
	lines.append("")
	lines.append(_kv("执行命令数", str(data.get("command_count", 0))))
	lines.append(_kv("查阅文件数", str(data.get("files_read_count", 0))))
	lines.append(_kv("认证失败数", str(data.get("login_fail_count", 0))))
	lines.append(_kv("已加载磁盘", str(data.get("discs_loaded_count", 0))))
	lines.append("")
	lines.append("[color=" + m + "]" + "-".repeat(30) + "[/color]")
	lines.append("")
	lines.append("[color=" + w + "]SYSTEM EVALUATION — 系统评价[/color]")
	lines.append("")

	var notes: Array = data.get("system_notes", []) as Array
	if notes.is_empty():
		lines.append("[color=" + m + "](暂无系统评价)[/color]")
	else:
		var display_notes: Array = notes
		if display_notes.size() > 10:
			display_notes = notes.slice(notes.size() - 10, notes.size())
			lines.append("[color=" + m + "](显示最近 10 条，共 " + str(notes.size()) + " 条)[/color]")
			lines.append("")

		for note in display_notes:
			var n: Dictionary = note as Dictionary
			var from_str: String = str(n.get("from", "UNKNOWN"))
			var content_str: String = str(n.get("content", ""))
			var tone: String = str(n.get("tone", "neutral"))
			var date_str: String = str(n.get("date", ""))
			var tone_color: String = m
			match tone:
				"positive": tone_color = s
				"warning": tone_color = w
				"hostile": tone_color = e
				"redacted":
					content_str = "██████████████████"
					tone_color = e
			lines.append("[color=" + m + "]" + date_str + "[/color]")
			lines.append("  [color=" + w + "]<" + from_str + ">[/color]")
			lines.append("  [color=" + tone_color + "]\"" + content_str + "\"[/color]")
			lines.append("")

	return "\n".join(lines)

# ══════════════════════════════════════════
#  第3页：权限与安全状态
# ══════════════════════════════════════════
func _build_page3(data: Dictionary) -> String:
	var m: String = T.muted_hex
	var w: String = T.warning_hex
	var e: String = T.error_hex
	var s: String = T.success_hex

	var lines: Array[String] = []
	lines.append("[color=" + w + "]SECURITY CLEARANCE — 安全权限[/color]")
	lines.append("")

	# 当前权限等级
	var clearance: int = data.get("clearance_level", 0) as int
	var clearance_str: String = "LEVEL " + str(clearance)
	var clearance_color: String = s
	if clearance >= 4:
		clearance_color = e
	elif clearance >= 2:
		clearance_color = w
	lines.append(_kv("权限等级", "[color=" + clearance_color + "]" + clearance_str + "[/color]"))

	# 账户状态
	var status: String = str(data.get("account_status", "ACTIVE"))
	var status_color: String = s if status == "ACTIVE" else e
	lines.append(_kv("账户状态", "[color=" + status_color + "]" + status + "[/color]"))

	# 密码修改时间
	var pwd_changed: String = str(data.get("password_changed_at", "未记录"))
	lines.append(_kv("密码更新", pwd_changed))

	# 认证失败统计
	var fail_count: int = data.get("login_fail_count", 0) as int
	var fail_color: String = m
	if fail_count >= 5:
		fail_color = e
	elif fail_count >= 3:
		fail_color = w
	lines.append(_kv("认证失败", "[color=" + fail_color + "]" + str(fail_count) + " 次[/color]"))

	lines.append("")
	lines.append("[color=" + m + "]" + "-".repeat(30) + "[/color]")
	lines.append("")

	# 已解锁磁盘列表
	lines.append("[color=" + w + "]LOADED DISCS — 已加载磁盘记录[/color]")
	lines.append("")

	var discs_loaded: Array = data.get("discs_loaded", []) as Array
	if discs_loaded.is_empty():
		lines.append("[color=" + m + "](无磁盘加载记录)[/color]")
	else:
		var idx: int = 1
		for disc in discs_loaded:
			var disc_str: String = str(disc)
			lines.append("  [color=" + w + "]" + str(idx) + ".[/color] [color=" + m + "]" + disc_str + "[/color]")
			idx += 1

	lines.append("")
	lines.append("[color=" + m + "]" + "-".repeat(30) + "[/color]")
	lines.append("")

	# 终端信息
	lines.append("[color=" + w + "]TERMINAL INFO — 终端信息[/color]")
	lines.append("")
	lines.append(_kv("终端版本", "SCP TERMINAL v0.1"))
	lines.append(_kv("主题配色", str(data.get("theme", "phosphor_green"))))
	lines.append(_kv("会话ID", str(data.get("session_id", "N/A"))))

	lines.append("")
	lines.append("")
	lines.append("[color=" + m + "]" + "═".repeat(36) + "[/color]")
	lines.append("[color=" + m + "]  SECURE · CONTAIN · PROTECT[/color]")
	lines.append("[color=" + m + "]" + "═".repeat(36) + "[/color]")

	return "\n".join(lines)

# ══════════════════════════════════════════
#  工具：构建键值对行
# ══════════════════════════════════════════
func _kv(key: String, value: String) -> String:
	var m: String = T.muted_hex
	var p: String = T.primary_hex
	# 键名固定占 12 个显示宽度（中文2字符宽）
	var key_w: int = fs.display_width(key)
	var pad: int = 12 - key_w
	if pad < 1:
		pad = 1
	return "[color=" + m + "]" + key + "[/color]" + " ".repeat(pad) + ": [color=" + p + "]" + value + "[/color]"
