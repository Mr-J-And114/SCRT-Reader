# ============================================================
# mail_system.gd — 邮件系统
#
# 邮件分类:
#   persistent (全局邮件) — 以 .txt 文件保存到 saves/{user}/mail/，退出故事包仍可查看
#   temporary  (临时邮件) — 引用故事包虚拟文件系统中的文件，弹出磁盘后消失
#
# 每封邮件就是一个标准的带 header 的文本文件，可以使用任何模板渲染。
# 收件箱索引: saves/{user}/mail/_inbox.json
#
# 触发器语法:
#   new_mail:mail_id              — 临时邮件（默认）
#   new_mail:mail_id:persistent   — 全局邮件
# ============================================================
class_name MailSystem
extends RefCounted

var main: Control = null
var fs: FileSystem = null
var T: Variant = null
var trigger_system = null

# ── 临时收件箱（当前故事包会话） ──
var _temp_inbox: Array[Dictionary] = []

# ── 全局收件箱索引（从磁盘加载） ──
var _global_inbox: Array[Dictionary] = []

# ── 合并视图（供列表展示用，按时间降序） ──
var _merged_inbox: Array[Dictionary] = []

# ── 延迟投递队列 ──
var _pending_deliveries: Array[Dictionary] = []

# ── 邮件定义缓存 ──
var _mail_defs: Dictionary = {}

# ── 闪烁控制 ──
var _blink_active: bool = false
var _blink_timer: float = 0.0

# ── 防止重入 ──
var _mail_busy: bool = false

# ── 已投递过的邮件ID集合（防止重复触发） ──
var _delivered_ids: Dictionary = {}

# ============================================================
# 初始化
# ============================================================
func setup(p_main: Control, p_fs: FileSystem, p_theme: Variant) -> void:
	main = p_main
	fs = p_fs
	T = p_theme

func set_trigger_system(p_trigger) -> void:
	trigger_system = p_trigger

# ============================================================
# 邮箱文件夹路径
# ============================================================
func _get_mail_dir() -> String:
	if main.user_mgr == null or not main.user_mgr.is_logged_in:
		return ""
	return main.user_mgr.ensure_mail_dir()

func _get_inbox_index_path() -> String:
	var mail_dir: String = _get_mail_dir()
	if mail_dir.is_empty():
		return ""
	return mail_dir + "_inbox.json"

# ============================================================
# 全局邮件磁盘操作
# ============================================================

## 将一封全局邮件的原始文本保存到 saves/{user}/mail/{mail_id}.txt
func _save_global_mail_file(mail_id: String, content: String) -> void:
	var mail_dir: String = _get_mail_dir()
	if mail_dir.is_empty():
		return
	var file_path: String = mail_dir + mail_id + ".txt"
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()

## 从磁盘读取全局邮件的原始文本
func _load_global_mail_file(mail_id: String) -> String:
	var mail_dir: String = _get_mail_dir()
	if mail_dir.is_empty():
		return ""
	var file_path: String = mail_dir + mail_id + ".txt"
	if not FileAccess.file_exists(file_path):
		return ""
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content

## 保存收件箱索引
func _save_inbox_index() -> void:
	var index_path: String = _get_inbox_index_path()
	if index_path.is_empty():
		return
	var index: Array[Dictionary] = []
	for mail in _global_inbox:
		index.append({
			"id": str(mail.get("id", "")),
			"read": bool(mail.get("read", false)),
			"delivered_at": str(mail.get("delivered_at", "")),
			"story_id": str(mail.get("story_id", "")),
			"title": str(mail.get("title", "")),
			"from": str(mail.get("from", "")),
			"template": str(mail.get("template", "email")),
			"priority": str(mail.get("priority", "normal")),
		})
	var file := FileAccess.open(index_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(index, "\t"))
		file.close()

## 从磁盘加载全局收件箱（登录后调用）
func load_global_inbox() -> void:
	_global_inbox.clear()
	var index_path: String = _get_inbox_index_path()
	if index_path.is_empty() or not FileAccess.file_exists(index_path):
		_rebuild_merged()
		_refresh_mail_icon()
		return
	var file := FileAccess.open(index_path, FileAccess.READ)
	if file == null:
		_rebuild_merged()
		_refresh_mail_icon()
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		_rebuild_merged()
		_refresh_mail_icon()
		return
	file.close()
	if not (json.data is Array):
		_rebuild_merged()
		_refresh_mail_icon()
		return
	for item in json.data:
		if not (item is Dictionary):
			continue
		var mail_id: String = str(item.get("id", ""))
		if mail_id.is_empty():
			continue
		# 检查 .txt 文件是否存在
		var mail_dir: String = _get_mail_dir()
		if not FileAccess.file_exists(mail_dir + mail_id + ".txt"):
			continue
		var entry: Dictionary = {
			"id": mail_id,
			"read": bool(item.get("read", false)),
			"delivered_at": str(item.get("delivered_at", "")),
			"story_id": str(item.get("story_id", "")),
			"title": str(item.get("title", mail_id)),
			"from": str(item.get("from", "未知")),
			"template": str(item.get("template", "email")),
			"priority": str(item.get("priority", "normal")),
			"persistent": true,
		}
		_global_inbox.append(entry)
		# 将全局邮件ID加入已投递集合
	for mail in _global_inbox:
		_delivered_ids[str(mail.get("id", ""))] = true
	_rebuild_merged()
	_refresh_mail_icon()
	print("[MailSystem] 已加载全局收件箱: ", _global_inbox.size(), " 封邮件")

# ============================================================
# 合并收件箱
# ============================================================
func _rebuild_merged() -> void:
	_merged_inbox.clear()
	for mail in _global_inbox:
		_merged_inbox.append(mail)
	for mail in _temp_inbox:
		_merged_inbox.append(mail)
	# 按投递时间降序
	_merged_inbox.sort_custom(func(a, b):
		return str(a.get("delivered_at", "")) > str(b.get("delivered_at", ""))
	)

# ============================================================
# 每帧驱动
# ============================================================
func process(delta: float) -> void:
	_tick_pending(delta)
	_tick_blink(delta)

func _tick_pending(delta: float) -> void:
	var remaining: Array[Dictionary] = []
	for p in _pending_deliveries:
		p["delay"] = float(p["delay"]) - delta
		if float(p["delay"]) <= 0:
			_do_deliver(str(p["id"]), str(p.get("context_path", "")), bool(p.get("persistent", false)))
		else:
			remaining.append(p)
	_pending_deliveries = remaining


func _tick_blink(delta: float) -> void:
	if not _blink_active:
		return
	_blink_timer += delta
	if main.mail_icon == null:
		return
	# 用透明度做闪烁，避免文字宽度跳动
	var alpha: float = 0.5 + 0.5 * sin(_blink_timer * 4.0)
	main.mail_icon.modulate = Color(1, 1, 1, alpha)


func start_blink() -> void:
	_blink_active = true
	_blink_timer = 0.0
	if main.mail_icon != null:
		main.mail_icon.text = "[Mail]"

func stop_blink() -> void:
	_blink_active = false
	if main.mail_icon != null:
		main.mail_icon.text = "[Mail]"
		main.mail_icon.modulate = Color(1, 1, 1, 1)

# ============================================================
# 投递邮件（由触发器调用）
# ============================================================
func deliver_mail(mail_id: String, context_path: String = "", persistent: bool = false) -> void:
	# 已投递过的邮件不再重复投递
	if _delivered_ids.has(mail_id):
		return
	# 也检查当前收件箱
	for mail in _global_inbox:
		if str(mail.get("id", "")) == mail_id:
			_delivered_ids[mail_id] = true
			return
	for mail in _temp_inbox:
		if str(mail.get("id", "")) == mail_id:
			_delivered_ids[mail_id] = true
			return

	var info: Dictionary = _load_mail_info(mail_id)
	if info.is_empty():
		push_warning("[MailSystem] 找不到邮件定义: " + mail_id)
		return
	var delay_ms: int = int(info.get("delay_ms", 0))
	if delay_ms > 0:
		_pending_deliveries.append({
			"id": mail_id,
			"delay": float(delay_ms) / 1000.0,
			"context_path": context_path,
			"persistent": persistent,
		})
	else:
		_do_deliver(mail_id, context_path, persistent)



func _do_deliver(mail_id: String, _context_path: String, persistent: bool) -> void:
	# 再次检查防止重复
	var target: Array[Dictionary] = _global_inbox if persistent else _temp_inbox
	for mail in target:
		if str(mail.get("id", "")) == mail_id:
			return

	var info: Dictionary = _load_mail_info(mail_id)
	if info.is_empty():
		return

	var now_str: String = _get_current_datetime()
	info["read"] = false
	info["delivered_at"] = now_str
	info["persistent"] = persistent
	info["story_id"] = main.story_id if not main.story_id.is_empty() else ""

	if persistent:
		# 全局邮件：把原始文件内容复制到用户邮箱目录
		var raw_content: String = _load_mail_raw_content(mail_id)
		if not raw_content.is_empty():
			_save_global_mail_file(mail_id, raw_content)
		_global_inbox.append(info)
		_save_inbox_index()
	else:
		_temp_inbox.append(info)

	_rebuild_merged()
	main.has_new_mail = true
	main._update_status_bar()
	start_blink()
	_show_notification(info)

	_delivered_ids[mail_id] = true

	# 统一的自动保存请求（优先 DiscManager，失败则直接 SaveManager）
	_request_auto_save()

## 投递内联邮件（无需虚拟文件系统，用于主线剧情）
func deliver_inline_mail(mail_id: String, title: String, from: String, body_text: String, persistent: bool = true) -> void:
	if _delivered_ids.has(mail_id):
		return
	for mail in _global_inbox:
		if str(mail.get("id", "")) == mail_id:
			_delivered_ids[mail_id] = true
			return
	for mail in _temp_inbox:
		if str(mail.get("id", "")) == mail_id:
			_delivered_ids[mail_id] = true
			return
	var now_str: String = _get_current_datetime()
	var info: Dictionary = {
		"id": mail_id,
		"title": title,
		"from": from,
		"template": "email",
		"priority": "normal",
		"read": false,
		"delivered_at": now_str,
		"persistent": persistent,
		"story_id": main.story_id if not main.story_id.is_empty() else "main",
		"_body_text": body_text,
	}
	if persistent:
		var raw_content: String = "---\ntitle: %s\ntemplate: email\n---\nFrom: %s\nSubject: %s\n---\n%s" % [title, from, title, body_text]
		_save_global_mail_file(mail_id, raw_content)
		_global_inbox.append(info)
		_save_inbox_index()
	else:
		_temp_inbox.append(info)
	_rebuild_merged()
	main.has_new_mail = true
	main._update_status_bar()
	start_blink()
	_show_notification(info)
	_delivered_ids[mail_id] = true
	_request_auto_save()

# ============================================================
# 从虚拟文件系统加载邮件原始内容
# ============================================================
func _load_mail_raw_content(mail_id: String) -> String:
	var search_paths: Array[String] = [
		"/mail/" + mail_id + ".txt",
		"/mail/" + mail_id,
	]
	for sp in search_paths:
		var node = fs.get_node_at_path(sp)
		if node != null:
			var content = null
			if node is Dictionary:
				content = node.get("content", null)
			elif "content" in node:
				content = node.content
			if content != null and not str(content).is_empty():
				return str(content)
	return ""

# ============================================================
# 加载邮件定义信息（从虚拟文件系统的 header 解析元数据）
# ============================================================
func _load_mail_info(mail_id: String) -> Dictionary:
	if _mail_defs.has(mail_id):
		return _mail_defs[mail_id].duplicate()

	var raw_content: String = _load_mail_raw_content(mail_id)
	if raw_content.is_empty():
		return {}

	var header_result: Dictionary = HeaderParser.parse(raw_content)
	var header: Dictionary = header_result.get("header", {})
	var body: String = header_result.get("body", "")

	# 从 email 模板的 body 头部解析额外元数据
	var email_meta: Dictionary = _extract_email_meta(body)

	var template_name: String = str(header.get("template", "email")).to_lower()

	var info: Dictionary = {
		"id": mail_id,
		"file_path": "/mail/" + mail_id + ".txt",
		"title": str(header.get("title", email_meta.get("subject", mail_id))),
		"from": str(email_meta.get("from", header.get("author", "未知"))),
		"template": template_name,
		"priority": str(email_meta.get("priority", header.get("mail_priority", "normal"))),
		"delay_ms": int(header.get("mail_delay", 0)),
		"read": false,
		"delivered_at": "",
	}
	_mail_defs[mail_id] = info
	return info.duplicate()

func _extract_email_meta(body: String) -> Dictionary:
	var meta: Dictionary = {}
	for line in body.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.is_empty():
			continue
		if stripped == "---" or stripped == "===":
			break
		var colon: int = stripped.find(":")
		if colon <= 0 or colon >= 20:
			break
		var key: String = stripped.substr(0, colon).strip_edges().to_lower()
		var val: String = stripped.substr(colon + 1).strip_edges()
		match key:
			"发件人", "from", "sender": meta["from"] = val
			"收件人", "to", "recipient": meta["to"] = val
			"主题", "subject": meta["subject"] = val
			"优先级", "priority": meta["priority"] = val
	return meta

# ============================================================
# 终端通知（简短提示）
# ============================================================
func _show_notification(info: Dictionary) -> void:
	# ★ 播放新邮件提示音
	if main.audio_manager != null:
		var beep_path: String = "res://audio/mail-notification.mp3"
		if ResourceLoader.exists(beep_path):
			var beep_stream: AudioStream = load(beep_path)
			main.audio_manager.play_sfx(beep_stream)

	var p: String = T.primary_hex if T else "#A0FFA0"
	var w: String = T.warning_hex if T else "#FFFF80"
	var m: String = T.muted_hex if T else "#888888"
	var title: String = str(info.get("title", "新邮件"))
	var from: String = str(info.get("from", "未知发件人"))
	var persistent_tag: String = " [GLOBAL]" if bool(info.get("persistent", false)) else ""
	var divider: String = "================================================"
	var notify_text: String = "\n"
	notify_text += "[color=" + p + "]" + divider + "[/color]\n"
	notify_text += "[color=" + w + "]  [NEW MAIL" + persistent_tag + "][/color] [color=" + p + "]" + title + "[/color]\n"
	notify_text += "[color=" + m + "]  From: " + from + "[/color]\n"
	notify_text += "[color=" + m + "]  输入 [/color][color=" + p + "]mail[/color][color=" + m + "] 或点击 [Mail] 查看收件箱[/color]\n"
	notify_text += "[color=" + p + "]" + divider + "[/color]\n"
	main.append_output(notify_text, false)

# ============================================================
# mail 命令入口
# ============================================================
func handle_mail_command(args: Array) -> void:
	if _mail_busy:
		return
	_mail_busy = true
	stop_blink()

	var p: String = T.primary_hex if T else "#A0FFA0"
	var m: String = T.muted_hex if T else "#888888"

	# ★ 打开邮箱时播放 beep
	if main.audio_manager != null:
		var beep_path: String = "res://assets/audio/sfx_beep.wav"
		if ResourceLoader.exists(beep_path):
			var beep_stream: AudioStream = load(beep_path)
			main.audio_manager.play_sfx(beep_stream, -6.0)

	if args.is_empty() or str(args[0]).to_lower() == "list":
		# ★ 显示快速进度条后打开收件箱列表
		main.append_output("\n[color=" + m + "]Connecting to mail server...[/color]\n", false)
		await main.tw.show_progress_bar(200, 3.0)
		await main.get_tree().create_timer(0.2).timeout
		_open_inbox_viewer()
		_mail_busy = false
		return

	var sub: String = str(args[0]).to_lower()
	match sub:
		"read":
			if args.size() < 2:
				main.append_output("\n[color=" + m + "]Connecting to mail server...[/color]\n", false)
				await main.tw.show_progress_bar(200, 3.0)
				await main.get_tree().create_timer(0.2).timeout
				_open_inbox_viewer()
				_mail_busy = false
				return
			var idx: int = str(args[1]).to_int()
			if idx > 0:
				_read_mail(idx)
			else:
				_open_inbox_viewer()
		_:
			var idx: int = sub.to_int()
			if idx > 0:
				_read_mail(idx)
			else:
				main.append_output("\n[color=" + m + "]Connecting to mail server...[/color]\n", false)
				await main.tw.show_progress_bar(200, 3.0)
				await main.get_tree().create_timer(0.2).timeout
				_open_inbox_viewer()
	_mail_busy = false


# ============================================================
# 打开收件箱列表（全屏 DocumentViewer）
# ============================================================
func _open_inbox_viewer() -> void:
	_rebuild_merged()
	var content: String = _build_inbox_page()
	if main.doc_viewer != null:
		var unread: int = get_unread_count()
		var title_str: String = "INBOX"
		if unread > 0:
			title_str += " (" + str(unread) + " unread)"
		var pages: Array[Dictionary] = [{"content": content}]
		main.doc_viewer.open("mail_inbox", pages, title_str)
	else:
		main.append_output("\n" + content + "\n", false)

func _build_inbox_page() -> String:
	var p: String = T.primary_hex if T else "#A0FFA0"
	var m: String = T.muted_hex if T else "#888888"
	var w: String = T.warning_hex if T else "#FFFF80"
	var e: String = T.error_hex if T else "#FF6666"
	var s: String = T.success_hex if T else "#80FF80"

	var divider: String = "========================================================"

	var lines: Array[String] = []
	lines.append("[color=" + p + "]" + divider + "[/color]")
	lines.append("[color=" + p + "][b]  INBOX[/b][/color]")
	lines.append("[color=" + p + "]" + divider + "[/color]")
	lines.append("")

	var unread_count: int = get_unread_count()
	lines.append("[color=" + m + "]  " + str(unread_count) + " unread / " + str(_merged_inbox.size()) + " total[/color]")
	lines.append("")

	if _merged_inbox.is_empty():
		lines.append("[color=" + m + "]  (empty)[/color]")
	else:
		for i in range(_merged_inbox.size()):
			var mail: Dictionary = _merged_inbox[i]
			var idx: int = i + 1
			var is_read: bool = bool(mail.get("read", false))
			var title: String = str(mail.get("title", "无标题"))
			var from: String = str(mail.get("from", "未知"))
			var is_persistent: bool = bool(mail.get("persistent", false))
			var priority: String = str(mail.get("priority", "normal")).to_lower()
			var template: String = str(mail.get("template", "email")).to_lower()

			# 未读标记
			var marker: String
			if is_read:
				marker = "[color=" + m + "]  [/color]"
			else:
				marker = "[color=" + w + "] *[/color]"

			# 类型标记
			var type_tag: String
			if is_persistent:
				type_tag = "[color=" + s + "][G][/color]"
			else:
				type_tag = "[color=" + m + "][T][/color]"

			# 模板标记
			var tmpl_tag: String = "[color=" + m + "][" + template.left(4).to_upper() + "][/color]"

			# 优先级标记
			var pri_tag: String = ""
			if priority in ["high", "urgent"]:
				pri_tag = " [color=" + e + "][!][/color]"

			var idx_str: String = str(idx).lpad(3, " ")
			var from_str: String = from.left(12).rpad(12, " ")

			# 可点击链接
			var line_text: String = marker + " [url=cmd://mail read " + str(idx) + "][color=" + p + "]" + idx_str + "[/color] " + type_tag + " " + tmpl_tag + " " + from_str + " " + title + pri_tag + "[/url]"
			lines.append(line_text)

	lines.append("")
	lines.append("[color=" + p + "]" + divider + "[/color]")
	lines.append("")
	lines.append("[color=" + m + "]  [G]=Global  [T]=Temporary  *=Unread[/color]")
	lines.append("[color=" + m + "]  [EMAI]=Email  [DOCU]=Document  [CHAT]=Chat  [REPO]=Report[/color]")
	lines.append("")
	lines.append("[color=" + m + "]  Click title to read  |  [/color][color=" + p + "]Q/Esc[/color][color=" + m + "] close inbox[/color]")

	return "\n".join(lines)

# ============================================================
# 阅读邮件（根据模板选择查看器）
# ============================================================
func _read_mail(idx: int) -> void:
	_rebuild_merged()
	if idx < 1 or idx > _merged_inbox.size():
		var err_c: String = T.error_hex if T else "#FF6666"
		main.append_output("[color=" + err_c + "]无效的邮件编号: " + str(idx) + "[/color]\n", false)
		_mail_busy = false
		return

	# ★ 点击/阅读邮件时播放 beep 音效
	if main.audio_manager != null:
		main.audio_manager.play_beep()

	var mail: Dictionary = _merged_inbox[idx - 1]
	# 标记为已读
	mail["read"] = true
	if bool(mail.get("persistent", false)):
		_save_inbox_index()
	_refresh_mail_icon()  # 所有邮件读取后都刷新图标和未读计数

	# 获取原始内容
	var raw_content: String = ""
	# ★ 优先检查内联正文（程序注入的邮件使用 _body_text 字段）
	var inline_body: String = str(mail.get("_body_text", ""))
	if not inline_body.is_empty():
		# 为内联邮件构造伪 header + body 格式
		raw_content = "---\ntitle: %s\ntemplate: %s\n---\n%s" % [
			str(mail.get("title", "")),
			str(mail.get("template", "email")),
			inline_body,
		]
	elif bool(mail.get("persistent", false)):
		raw_content = _load_global_mail_file(str(mail.get("id", "")))
	else:
		raw_content = _load_mail_raw_content(str(mail.get("id", "")))
	if raw_content.is_empty():
		var err_c: String = T.error_hex if T else "#FF6666"
		main.append_output("[color=" + err_c + "]Cannot read mail content.[/color]\n", false)
		_mail_busy = false
		return

	# 解析 header
	var header_result: Dictionary = HeaderParser.parse(raw_content)
	var header: Dictionary = header_result.get("header", {})
	var body: String = header_result.get("body", "")

	# 变量替换
	if main.user_mgr != null and main.user_mgr.is_logged_in:
		body = body.replace("{username}", main.user_mgr.get_username())

	var template_name: String = str(mail.get("template", str(header.get("template", "email")))).to_lower()
	var display_title: String = str(mail.get("title", "邮件"))

	# 关闭当前的收件箱列表（如果还开着）
	if main.doc_viewer != null and main.doc_viewer.is_active:
		main.doc_viewer.close()

	# ★ 退出回调：阅读完毕后返回收件箱列表
	var return_to_inbox: Callable = Callable(self, "_open_inbox_viewer")

	# 根据模板选择查看器
	match template_name:
		"email":
			if main.email_viewer != null:
				main.email_viewer.open(display_title, header, body, return_to_inbox)
			else:
				_display_mail_in_terminal(display_title, body)
		"chat":
			if main.chat_viewer != null:
				main.chat_viewer.open(display_title, header, body, return_to_inbox)
			else:
				_display_mail_in_terminal(display_title, body)
		"article":
			if main.article_viewer != null:
				main.article_viewer.open(display_title, header, body, return_to_inbox)
			else:
				_display_mail_in_terminal(display_title, body)
		"two_page", "twopage":
			if main.two_page_viewer != null:
				main.two_page_viewer.open(display_title, header, body, return_to_inbox)
			else:
				_display_mail_in_terminal(display_title, body)
		"document", "raw", _:
			# 默认用 DocumentViewer
			if main.doc_viewer != null:
				# CRT-ML 解析
				var parsed_body: String = body
				if main.crtml != null:
					parsed_body = main.crtml.parse(body)
				var pages: Array[Dictionary] = [{"content": parsed_body}]
				main.doc_viewer.open("mail_" + str(mail.get("id", "")), pages, display_title, return_to_inbox)
			else:
				_display_mail_in_terminal(display_title, body)

	# 统一的自动保存请求（优先 DiscManager，失败则直接 SaveManager）
	_request_auto_save()

	# ★ 通知每日剧情系统邮件已阅读（触发 on_mail_read 类型对话）
	if main.daily_dialogue_mgr and main.env_monitor:
		main.daily_dialogue_mgr.trigger_mail_read(main.env_monitor.current_day, str(mail.get("id", "")))

func _display_mail_in_terminal(title: String, body: String) -> void:
	var p: String = T.primary_hex if T else "#A0FFA0"
	var m: String = T.muted_hex if T else "#888888"
	var divider: String = "========================================================"
	main.append_output("\n[color=" + p + "]" + divider + "[/color]\n", false)
	main.append_output("[color=" + p + "][b]  " + title + "[/b][/color]\n", false)
	main.append_output("[color=" + p + "]" + divider + "[/color]\n\n", false)
	var parsed: String = body
	if main.crtml != null:
		parsed = main.crtml.parse(body)
	if main.user_mgr != null and main.user_mgr.is_logged_in:
		parsed = parsed.replace("{username}", main.user_mgr.get_username())
	main.append_output(parsed + "\n", true)
	main.append_output("\n[color=" + p + "]" + divider + "[/color]\n", false)
	main.append_output("[color=" + m + "]END OF MESSAGE[/color]\n", false)

# ============================================================
# 图标刷新
# ============================================================
func _refresh_mail_icon() -> void:
	var has_unread: bool = false
	for mail in _merged_inbox:
		if not bool(mail.get("read", false)):
			has_unread = true
			break
	main.has_new_mail = has_unread
	if not has_unread:
		stop_blink()
	# 调用 _update_status_bar() 会自动设置邮件图标文本
	main._update_status_bar()


func get_unread_count() -> int:
	var count: int = 0
	for mail in _merged_inbox:
		if not bool(mail.get("read", false)):
			count += 1
	return count

func get_total_count() -> int:
	return _merged_inbox.size()

# ============================================================
# 存档接口（仅临时邮件，全局邮件有独立持久化）
# ============================================================
func get_save_data() -> Dictionary:
	var temp_save: Array[Dictionary] = []
	for mail in _temp_inbox:
		temp_save.append({
			"id": str(mail.get("id", "")),
			"read": bool(mail.get("read", false)),
			"delivered_at": str(mail.get("delivered_at", "")),
		})
	# ★ 保存所有已投递ID，确保全局+临时邮件ID都包含在内
	var delivered_set: Dictionary = _delivered_ids.duplicate()
	for mail in _global_inbox:
		var gid: String = str(mail.get("id", ""))
		if not gid.is_empty():
			delivered_set[gid] = true
	for mail in _temp_inbox:
		var tid: String = str(mail.get("id", ""))
		if not tid.is_empty():
			delivered_set[tid] = true
	var delivered_list: Array[String] = []
	for key in delivered_set.keys():
		delivered_list.append(str(key))
	return {
		"temp_inbox": temp_save,
		"delivered_ids": delivered_list,
	}



func load_save_data(data: Dictionary) -> void:
	_temp_inbox.clear()

	# ★ 不清空 _delivered_ids，而是追加（load_global_inbox 可能已填充了全局邮件ID）
	var saved_ids: Array = data.get("delivered_ids", []) as Array
	for sid in saved_ids:
		_delivered_ids[str(sid)] = true

	# 确保全局邮件的ID也在 delivered 集合中
	for mail in _global_inbox:
		_delivered_ids[str(mail.get("id", ""))] = true

	# 恢复临时邮件（优先使用存档里的 temp_inbox）
	var saved_temp: Array = data.get("temp_inbox", []) as Array
	for item in saved_temp:
		if not (item is Dictionary):
			continue
		var mail_id: String = str(item.get("id", ""))
		if mail_id.is_empty():
			continue
		_delivered_ids[mail_id] = true
		var info: Dictionary = _load_mail_info(mail_id)
		if info.is_empty():
			continue
		info["read"] = bool(item.get("read", false))
		info["delivered_at"] = str(item.get("delivered_at", ""))
		info["persistent"] = false
		_temp_inbox.append(info)

	# ★ 容错补齐：如果 temp_inbox 为空或缺少，利用 delivered_ids - 全局ID 反推临时邮件
	var global_id_set: Dictionary = {}
	for g in _global_inbox:
		var gid := str(g.get("id", ""))
		if not gid.is_empty():
			global_id_set[gid] = true

	# 把 delivered_ids 中非全局、且尚未在 temp_inbox 的ID补齐为临时邮件
	var existing_temp: Dictionary = {}
	for t in _temp_inbox:
		existing_temp[str(t.get("id", ""))] = true

	for sid in saved_ids:
		var mid := str(sid)
		if mid.is_empty():
			continue
		if global_id_set.has(mid):
			continue
		if existing_temp.has(mid):
			continue
		var info := _load_mail_info(mid)
		if info.is_empty():
			continue
		info["read"] = false
		info["delivered_at"] = _get_current_datetime()
		info["persistent"] = false
		_temp_inbox.append(info)

	_rebuild_merged()
	_refresh_mail_icon()


# 统一的自动保存请求：优先调用 DiscManager._auto_save；失败则直接用 SaveManager 写入
func _request_auto_save() -> void:
	# 先尝试走 DiscManager（带所有系统 extra）
	if main.disc_mgr != null and main.disc_mgr.has_method("_auto_save"):
		main.disc_mgr._auto_save()
		return

	# 兜底：直接调用 SaveManager（必要时自己组 extra_data）
	if main.save_mgr != null and main.story_id != "":
		var extra: Dictionary = {}
		if trigger_system != null and trigger_system.has_method("get_save_data"):
			extra["trigger_data"] = trigger_system.get_save_data()
		extra["mail_data"] = get_save_data()
		# 无线电（若存在）
		if main.radio_receiver != null and main.radio_receiver.signal_mgr != null:
			extra["radio_data"] = main.radio_receiver.signal_mgr.get_save_data()

		main.save_mgr.auto_save(
			main.story_id,
			fs.player_clearance,
			main.read_files,
			main.unlocked_passwords,
			fs.unlocked_file_passwords,
			main.current_path,
			extra
		)


# ============================================================
# 清空 / 重置
# ============================================================
func clear() -> void:
	_temp_inbox.clear()
	_pending_deliveries.clear()
	_mail_defs.clear()
	stop_blink()
	_rebuild_merged()
	_refresh_mail_icon()

func clear_all() -> void:
	_temp_inbox.clear()
	_global_inbox.clear()
	_merged_inbox.clear()
	_pending_deliveries.clear()
	_mail_defs.clear()
	_delivered_ids.clear()
	stop_blink()
	main.has_new_mail = false


func load_from_manifest(_manifest: Dictionary) -> void:
	_temp_inbox.clear()
	_pending_deliveries.clear()
	_mail_defs.clear()
	_rebuild_merged()

func reset() -> void:
	clear()

# ============================================================
# 工具
# ============================================================
func _get_current_datetime() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		dt["year"], dt["month"], dt["day"],
		dt["hour"], dt["minute"], dt["second"]
	]
