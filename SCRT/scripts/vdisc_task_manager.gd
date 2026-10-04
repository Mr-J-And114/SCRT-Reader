class_name VdiscTaskManager
extends RefCounted

var main = null
var fs: FileSystem = null
var save_mgr: SaveManager = null
var disc_mgr: DiscManager = null
var definitions: Dictionary = {}
var task_states: Dictionary = {}
var modifications: Dictionary = {}
var archive: Array = []
var download_busy: bool = false
var _download_layer: CanvasLayer = null
var _download_frame: RichTextLabel = null
var _download_title: String = ""
var _download_status: String = ""
var _download_progress: float = 0.0
var _download_finished: bool = false
var _download_show_bar: bool = true
var _download_color: String = ""
var _last_download_render: String = ""
var _confirm_pending: bool = false
var _confirm_choice: int = -1

func is_download_open() -> bool:
	return is_instance_valid(_download_layer)

func close_download() -> void:
	if _confirm_pending:
		_confirm_choice = 0
		return
	if download_busy or not is_download_open():
		return
	_download_layer.queue_free()
	_download_layer = null
	main._refocus_input.call_deferred()

func handle_download_input(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	if _confirm_pending:
		if event.keycode == KEY_Y:
			_confirm_choice = 1
		elif event.keycode in [KEY_N, KEY_ESCAPE, KEY_ENTER]:
			_confirm_choice = 0
	elif _download_finished and event.keycode in [KEY_ESCAPE, KEY_ENTER]:
		close_download()

func _on_download_action(action: Variant) -> void:
	match str(action):
		"redownload":
			if _confirm_pending:
				_confirm_choice = 1
		"keep", "close":
			close_download()

func _open_download(title: String) -> void:
	_download_layer = CanvasLayer.new()
	var crt_layer: CanvasLayer = main.get_node("CRTEffect")
	_download_layer.layer = crt_layer.layer - 1
	main.add_child(_download_layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	_download_layer.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	shade.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var background := StyleBoxFlat.new()
	background.bg_color = main.T.bg_panel
	# 控件本身不画任何边线，外框只由 build_box() 的字符构成。
	background.border_color = Color.TRANSPARENT
	background.set_border_width_all(0)
	background.shadow_color = Color.TRANSPARENT
	background.shadow_size = 0
	panel.add_theme_stylebox_override("panel", background)
	center.add_child(panel)
	_download_frame = RichTextLabel.new()
	_download_frame.bbcode_enabled = true
	_download_frame.fit_content = true
	_download_frame.scroll_active = false
	_download_frame.autowrap_mode = TextServer.AUTOWRAP_OFF
	# 按键由 main._input 统一处理；禁用 RichTextLabel 焦点框，避免默认白色描边。
	_download_frame.focus_mode = Control.FOCUS_NONE
	_download_frame.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_download_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	CrtmlParser.apply_fonts(_download_frame)
	_download_frame.add_theme_font_size_override("normal_font_size", main.output_text.get_theme_font_size("normal_font_size"))
	_download_frame.add_theme_color_override("default_color", main.T.secondary)
	_download_frame.meta_clicked.connect(_on_download_action)
	panel.add_child(_download_frame)
	_download_title = title
	_download_status = "准备下载……"
	_download_progress = 0.0
	_download_finished = false
	_download_show_bar = true
	_download_color = main.T.secondary_hex
	_last_download_render = ""
	main._sync_terminal_visibility()
	_render_download()

func _wrap_download_text(value: String) -> Array[String]:
	var lines: Array[String] = []
	for paragraph in value.split("\n"):
		var line: String = ""
		for index in paragraph.length():
			var character: String = paragraph[index]
			if fs.display_width(line + character) > 54:
				lines.append(line)
				line = ""
			line += character
		lines.append(line)
	return lines

func _render_download() -> void:
	var lines: Array[String] = ["VDISC TRANSFER / 磁盘传输"]
	lines.append_array(_wrap_download_text(_download_title))
	lines.append("")
	if _download_show_bar:
		var caption: String = "下载完成" if _download_finished and _download_progress >= 100.0 else ("下载停止" if _download_finished else "下载中")
		lines.append(Typewriter.format_progress_bar(_download_progress / 100.0, caption))
		lines.append("")
	for line in _wrap_download_text(_download_status):
		lines.append("[color=" + _download_color + "]" + line + "[/color]")
	lines.append("")
	if _confirm_pending:
		lines.append("[url=redownload]> 重新下载 [Y][/url]    [url=keep]> 保留 [N/Esc][/url]")
	elif _download_finished:
		lines.append("[url=close]> 返回 [Enter/Esc][/url]")
	else:
		lines.append("传输进行中，请稍候……")
	# 保持短状态之间框宽一致，长行由同一个系统字符框函数扩展。
	lines.append(" ".repeat(54))
	var rendered: String = fs.build_box(lines, main.T.primary_hex)
	if rendered == _last_download_render:
		return
	_last_download_render = rendered
	var cells: int = 60
	var font: Font = _download_frame.get_theme_font("normal_font")
	var font_size: int = _download_frame.get_theme_font_size("normal_font_size")
	_download_frame.custom_minimum_size.x = font.get_string_size(" ".repeat(cells), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_download_frame.text = rendered

func _set_download_progress(progress: float, status: String) -> void:
	_download_progress = progress
	_download_status = status
	_render_download()

func _download_result(result: Dictionary) -> Dictionary:
	download_busy = false
	_confirm_pending = false
	_download_finished = true
	_download_show_bar = not bool(result.get("cancelled", false))
	if bool(result.get("ok", false)):
		_download_progress = 100.0
	elif _download_progress < 0.0:
		_download_show_bar = false
	_download_color = main.T.muted_hex if bool(result.get("cancelled", false)) else (main.T.success_hex if bool(result.get("ok", false)) else main.T.error_hex)
	_download_status = str(result.get("message", ""))
	_render_download()
	return result

func _confirm_redownload() -> bool:
	_confirm_pending = true
	_confirm_choice = -1
	_download_show_bar = false
	_download_status = "该任务磁盘已存在，是否重新下载？\n确认后重置此盘的探索进度、文件修改及任务状态。\n新包校验成功后才替换；失败保留现有磁盘。"
	_render_download()
	while _confirm_choice < 0:
		await main.get_tree().process_frame
	_confirm_pending = false
	_download_show_bar = true
	return _confirm_choice == 1

func setup(p_main, p_fs: FileSystem, p_save_mgr: SaveManager, p_disc_mgr: DiscManager) -> void:
	main = p_main
	fs = p_fs
	save_mgr = p_save_mgr
	disc_mgr = p_disc_mgr
	var file := FileAccess.open("res://data/main/manifest.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
			load_tasks_from_manifest(json.data)
		file.close()

func load_tasks_from_manifest(manifest: Dictionary) -> void:
	var tasks: Dictionary = manifest.get("vdisc_tasks", {})
	for task_id in tasks.keys():
		if tasks[task_id] is Dictionary:
			definitions[str(task_id)] = tasks[task_id]
	register_modem_numbers()

func register_modem_numbers() -> void:
	if main == null or main.dial_mgr == null:
		return
	for task_id in definitions.keys():
		var task: Dictionary = definitions[task_id]
		var download: Dictionary = task.get("download", {})
		var number: String = str(download.get("number", ""))
		if not number.is_empty():
			main.dial_mgr.register_system_modem(number, {
				"label": str(task.get("title", task_id)),
				"filename": str(download.get("filename", "")),
				"url": str(download.get("url", "")),
				"speed_display": str(download.get("speed_display", "9600 bps")),
			})

func load_player_state() -> void:
	task_states = {}
	modifications = {}
	archive = []
	if not _has_user():
		return
	var data: Dictionary = main.user_mgr.current_user.get("vdisc_task_data", {})
	task_states = (data.get("tasks", {}) as Dictionary).duplicate(true)
	modifications = (data.get("modifications", {}) as Dictionary).duplicate(true)
	archive = (data.get("archive", []) as Array).duplicate(true)
	register_modem_numbers()

func _save_state() -> void:
	if not _has_user():
		return
	main.user_mgr.current_user["vdisc_task_data"] = {
		"tasks": task_states.duplicate(true),
		"modifications": modifications.duplicate(true),
		"archive": archive.duplicate(true),
	}
	main.user_mgr._save_current_profile()

func _has_user() -> bool:
	return main != null and main.user_mgr != null and main.user_mgr.is_logged_in

func _user_disc_dir() -> String:
	if not _has_user():
		return ""
	return save_mgr.get_game_root_dir().path_join("saves").path_join(main.user_mgr.get_username()).path_join("vdisc")

func get_inbox_dir() -> String:
	var root: String = _user_disc_dir()
	return root.path_join("inbox") if not root.is_empty() else ""

func _safe_filename(name: String) -> bool:
	return not name.is_empty() and name == name.get_file() and name.get_extension().to_lower() == "scp" and not name.contains("..")

func get_task_for_filename(filename: String) -> String:
	for task_id in definitions.keys():
		var download: Dictionary = definitions[task_id].get("download", {})
		if str(download.get("filename", "")) == filename:
			return str(task_id)
	return ""

func get_task_for_story(story_id: String) -> String:
	for task_id in definitions.keys():
		var task: Dictionary = definitions[task_id]
		if str(task.get("story_id", "")) == story_id:
			return str(task_id)
		var state: Dictionary = task_states.get(task_id, {})
		if str(state.get("story_id", "")) == story_id:
			return str(task_id)
	return ""

func get_task_status(task_id: String) -> String:
	return str((task_states.get(task_id, {}) as Dictionary).get("status", "not_started"))

func download_task(task_id: String) -> Dictionary:
	if download_busy or is_download_open():
		return {"ok": false, "message": "请先完成并关闭当前下载窗口。"}
	if not definitions.has(task_id):
		return {"ok": false, "message": "未知 Vdisc 任务。"}
	if not _has_user():
		return {"ok": false, "message": "请先登录。"}
	if get_task_status(task_id) == "submitted":
		return {"ok": false, "message": "任务已上交，归档记录可在 vdisc 中查看。"}
	var task: Dictionary = definitions[task_id]
	var download: Dictionary = task.get("download", {})
	var filename: String = str(download.get("filename", ""))
	if not _safe_filename(filename):
		return {"ok": false, "message": "任务的磁盘文件名无效。"}
	var url: String = str(download.get("url", ""))
	if not url.is_empty() and not url.begins_with("https://") and not url.begins_with("http://"):
		return {"ok": false, "message": "下载地址必须是 HTTP 或 HTTPS。"}
	var username: String = main.user_mgr.get_username()
	download_busy = true
	_open_download(str(task.get("title", task_id)))
	var exists: bool = FileAccess.file_exists(get_inbox_dir().path_join(filename))
	var replace_existing: bool = exists or get_task_status(task_id) == "downloaded"
	if exists:
		var confirmed: bool = await _confirm_redownload()
		if not confirmed:
			return _download_result({"ok": false, "cancelled": true, "message": "已保留现有磁盘及进度。"})
	_set_download_progress(-1.0, "正在连接……")
	var bytes: PackedByteArray = PackedByteArray()
	if not url.is_empty():
		var request := HTTPRequest.new()
		request.timeout = 30.0
		main.add_child(request)
		var completed: Dictionary = {"done": false, "response": []}
		request.request_completed.connect(func(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
			completed["response"] = [result, code, headers, body]
			completed["done"] = true
		)
		var error: Error = request.request(url)
		if error != OK:
			request.queue_free()
			return _download_result({"ok": false, "message": "下载请求未能发起。"})
		while not bool(completed["done"]):
			var total: int = request.get_body_size()
			var received: int = request.get_downloaded_bytes()
			var percent: float = minf(95.0, float(received) / total * 95.0) if total > 0 else -1.0
			_set_download_progress(percent, "正在下载：%d KB" % (received / 1024))
			await main.get_tree().process_frame
		var response: Array = completed["response"]
		request.queue_free()
		if int(response[0]) != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200:
			return _download_result({"ok": false, "message": "下载失败，请稍后重试。"})
		bytes = response[3]
	else:
		var source: String = disc_mgr.vdisc_dir.path_join(filename)
		if not FileAccess.file_exists(source):
			return _download_result({"ok": false, "message": "本地尚无该磁盘源文件。"})
		bytes = FileAccess.get_file_as_bytes(source)
		# 本地联调包模拟传输；联网包上方显示实际接收进度。
		for step in range(1, 13):
			_set_download_progress(step * 7.5, "正在传输本地磁盘：%d / %d KB" % [int(bytes.size() * step / 12.0 / 1024), int(bytes.size() / 1024)])
			await main.get_tree().create_timer(0.1).timeout
	if not _has_user() or main.user_mgr.get_username() != username:
		return _download_result({"ok": false, "message": "账号已切换，下载未保存。"})
	_set_download_progress(95.0, "正在校验并保存磁盘……")
	await main.get_tree().process_frame
	return _download_result(store_download(task_id, bytes, replace_existing))

func download_mail_attachment(mail_id: String) -> Dictionary:
	for task_id in definitions.keys():
		var download: Dictionary = definitions[task_id].get("download", {})
		if str(download.get("mail_attachment", "")) == mail_id:
			var result: Dictionary = await download_task(str(task_id))
			# 重复领取等即时提示也留在邮件上方，避免被查看器遮住。
			if not is_download_open():
				_open_download(str(definitions[task_id].get("title", task_id)))
				_download_result(result)
			return result
	return {"ok": false, "message": "这封邮件没有 Vdisc 附件。"}

func has_mail_attachment(mail_id: String) -> bool:
	for task_id in definitions.keys():
		var download: Dictionary = definitions[task_id].get("download", {})
		if str(download.get("mail_attachment", "")) == mail_id:
			return true
	return false

func on_modem_complete(filename: String, bytes: PackedByteArray) -> Dictionary:
	var task_id: String = get_task_for_filename(filename)
	if task_id.is_empty():
		return {"handled": false}
	if bytes.is_empty():
		var download: Dictionary = definitions[task_id].get("download", {})
		if not str(download.get("url", "")).is_empty():
			return {"handled": true, "ok": false, "message": "下载失败，未收到磁盘数据。"}
		var source: String = disc_mgr.vdisc_dir.path_join(filename)
		if FileAccess.file_exists(source):
			bytes = FileAccess.get_file_as_bytes(source)
	var result: Dictionary = store_download(task_id, bytes)
	result["handled"] = true
	return result

func store_download(task_id: String, bytes: PackedByteArray, replace_existing: bool = false) -> Dictionary:
	if not definitions.has(task_id) or not _has_user():
		return {"ok": false, "message": "任务或玩家无效。"}
	if get_task_status(task_id) == "submitted":
		return {"ok": false, "message": "任务已经上交。"}
	var download: Dictionary = definitions[task_id].get("download", {})
	var filename: String = str(download.get("filename", ""))
	if not _safe_filename(filename) or bytes.size() < 4 or bytes[0] != 80 or bytes[1] != 75:
		return {"ok": false, "message": "下载内容不是有效的 .scp 磁盘。"}
	var dir: String = get_inbox_dir()
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return {"ok": false, "message": "无法创建玩家磁盘目录。"}
	var path: String = dir.path_join(filename)
	if FileAccess.file_exists(path) and not replace_existing:
		return {"ok": false, "message": "该任务磁盘已在个人任务箱中。"}
	# 先写入临时包并校验，不能用失败的下载覆盖旧磁盘。
	var staged_path: String = path + ".download"
	var file := FileAccess.open(staged_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "无法保存玩家磁盘副本。"}
	file.store_buffer(bytes)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(staged_path)
		return {"ok": false, "message": "磁盘写入失败，请检查剩余空间后重试。"}
	var reader := ZIPReader.new()
	if reader.open(staged_path) != OK:
		DirAccess.remove_absolute(staged_path)
		return {"ok": false, "message": "磁盘压缩包损坏。"}
	var story_id: String = ""
	var disc_manifest: Dictionary = {}
	for entry in reader.get_files():
		if entry.get_file() == "manifest.json":
			var json := JSON.new()
			if json.parse(reader.read_file(entry).get_string_from_utf8()) == OK and json.data is Dictionary:
				disc_manifest = json.data
				story_id = str((json.data.get("story", {}) as Dictionary).get("id", ""))
			break
	reader.close()
	if story_id.is_empty():
		DirAccess.remove_absolute(staged_path)
		return {"ok": false, "message": "磁盘缺少有效的 story.id。"}
	var expected_id: String = str(definitions[task_id].get("story_id", ""))
	if not expected_id.is_empty() and story_id != expected_id:
		DirAccess.remove_absolute(staged_path)
		return {"ok": false, "message": "下载磁盘与任务指定的 story.id 不符。"}
	var prior: Dictionary = task_states.get(task_id, {})
	var reset_progress: bool = replace_existing or str(prior.get("status", "")) == "confiscated"
	var backup_dir: String = _user_disc_dir().path_join("replaced").path_join(str(Time.get_ticks_usec()))
	if reset_progress and DirAccess.make_dir_recursive_absolute(backup_dir) != OK:
		DirAccess.remove_absolute(staged_path)
		return {"ok": false, "message": "无法备份现有磁盘，重新下载未保存。"}
	var fresh_save: String = backup_dir.path_join("fresh_progress.json")
	if reset_progress:
		# 写入空白个人存档，防止 load_save 回退迁移旧的全局存档。
		var settings: Dictionary = disc_manifest.get("settings", {})
		var story: Dictionary = disc_manifest.get("story", {})
		var fresh_file := FileAccess.open(fresh_save, FileAccess.WRITE)
		if fresh_file == null:
			DirAccess.remove_absolute(staged_path)
			return {"ok": false, "message": "无法创建新的任务进度，旧磁盘已保留。"}
		fresh_file.store_string(JSON.stringify({"story_id": story_id,
			"player_clearance": int(settings.get("start_clearance", story.get("start_clearance", 0))),
			"read_files": [], "unlocked_passwords": [], "unlocked_file_passwords": [], "current_path": "/"}))
		fresh_file.flush()
		var fresh_error: Error = fresh_file.get_error()
		fresh_file.close()
		if fresh_error != OK:
			DirAccess.remove_absolute(staged_path)
			return {"ok": false, "message": "新任务进度写入失败，旧磁盘已保留。"}
	# 弹出正在使用的同故事磁盘，避免旧内存随后重新写回旧进度。
	if reset_progress and main.story_id == story_id:
		disc_mgr.eject_story()
	var save_path: String = save_mgr.get_save_path(story_id)
	var saved_backup: String = backup_dir.path_join("progress.json")
	var had_save: bool = reset_progress and FileAccess.file_exists(save_path)
	if had_save and DirAccess.rename_absolute(save_path, saved_backup) != OK:
		DirAccess.remove_absolute(staged_path)
		return {"ok": false, "message": "无法刷新旧进度，现有磁盘已保留。"}
	var disc_backup: String = backup_dir.path_join(filename)
	var had_disc: bool = FileAccess.file_exists(path)
	if had_disc and DirAccess.rename_absolute(path, disc_backup) != OK:
		if had_save:
			DirAccess.rename_absolute(saved_backup, save_path)
		DirAccess.remove_absolute(staged_path)
		return {"ok": false, "message": "无法替换现有磁盘，旧磁盘已保留。"}
	if DirAccess.rename_absolute(staged_path, path) != OK:
		if had_disc:
			DirAccess.rename_absolute(disc_backup, path)
		if had_save:
			DirAccess.rename_absolute(saved_backup, save_path)
		DirAccess.remove_absolute(staged_path)
		return {"ok": false, "message": "新磁盘保存失败，已尝试恢复原磁盘与进度。"}
	if reset_progress:
		if DirAccess.rename_absolute(fresh_save, save_path) != OK:
			DirAccess.remove_absolute(path)
			if had_disc:
				DirAccess.rename_absolute(disc_backup, path)
			if had_save:
				DirAccess.rename_absolute(saved_backup, save_path)
			return {"ok": false, "message": "新进度保存失败，已尝试恢复原磁盘与进度。"}
		modifications.erase(story_id)
	task_states[task_id] = {"status": "downloaded", "story_id": story_id, "filename": filename}
	_save_state()
	disc_mgr.scan_stories(true)
	var message: String = "磁盘已重新下载，任务与探索进度已重置。" if reset_progress else "磁盘已下载到个人任务箱。"
	return {"ok": true, "message": message + "\n关闭邮件后输入 scan，再用 load <编号> 加载。\n输入 vdisc 查看任务要求和上交命令。"}

func apply_modifications(story_id: String) -> void:
	var patch: Dictionary = modifications.get(story_id, {})
	for path in patch.get("deleted", []):
		fs.file_system.erase(str(path))
	var changed: Dictionary = patch.get("changed", {})
	for path in changed.keys():
		var record: Dictionary = changed[path]
		var entry: Dictionary = {"type": "file", "content": str(record.get("content", "")), "origin": str(record.get("origin", "created"))}
		if record.has("binary_base64"):
			entry["binary"] = Marshalls.base64_to_raw(str(record["binary_base64"]))
		fs.file_system[str(path)] = entry

func record_path_change(story_id: String, path: String) -> void:
	if story_id.is_empty() or get_task_for_story(story_id).is_empty():
		return
	path = fs.normalize_path(path)
	var patch: Dictionary = modifications.get(story_id, {"changed": {}, "deleted": []})
	var changed: Dictionary = patch.get("changed", {})
	var deleted: Array = patch.get("deleted", [])
	if fs.file_system.has(path):
		var entry: Dictionary = fs.file_system[path]
		var record: Dictionary = {"content": str(entry.get("content", "")), "origin": str(entry.get("origin", "original"))}
		if entry.has("binary"):
			record["binary_base64"] = Marshalls.raw_to_base64(entry["binary"])
		changed[path] = record
		deleted.erase(path)
	else:
		changed.erase(path)
		if not deleted.has(path):
			deleted.append(path)
	patch["changed"] = changed
	patch["deleted"] = deleted
	modifications[story_id] = patch
	_save_state()

func get_progress_detail(story_id: String) -> Dictionary:
	var total: int = 0
	var read: int = 0
	for path in fs.file_system.keys():
		var entry: Dictionary = fs.file_system[path]
		if str(entry.get("type", "")) != "file" or fs.is_hidden_path(str(path)) or not fs.has_clearance(str(path)):
			continue
		total += 1
		if main.read_files.has(str(path)):
			read += 1
	var percent: int = int(float(read) / float(total) * 100.0) if total > 0 else 0
	return {"read": read, "total": total, "percent": percent, "size_kb": float(fs.count_total_size()) / 1024.0}

func check_requirements(task_id: String) -> Dictionary:
	if not definitions.has(task_id):
		return {"passed": false, "missing": ["未知任务"]}
	var requirements: Dictionary = definitions[task_id].get("requirements", {})
	var task: Dictionary = definitions[task_id]
	var state: Dictionary = task_states.get(task_id, {})
	var detail: Dictionary = get_progress_detail(str(state.get("story_id", task.get("story_id", ""))))
	var missing: Array[String] = []
	if int(detail["percent"]) < int(requirements.get("min_read_percent", 0)):
		missing.append("探索进度不足：%d%% / %d%%" % [int(detail["percent"]), int(requirements["min_read_percent"])])
	for path in requirements.get("required_files", []):
		var required_node = fs.get_node_at_path(str(path))
		if required_node == null or required_node.type != "file":
			missing.append("缺少必需文件：" + str(path))
	if int(detail["total"]) < int(requirements.get("min_total_files", 0)):
		missing.append("文件数量不足")
	if float(detail["size_kb"]) < float(requirements.get("min_size_kb", 0)):
		missing.append("数据包体积不足")
	return {"passed": missing.is_empty(), "missing": missing, "detail": detail}

func submit(number: String) -> Dictionary:
	if main.story_id.is_empty():
		return {"ok": false, "message": "请先加载任务磁盘。"}
	var task_id: String = get_task_for_story(main.story_id)
	if task_id.is_empty():
		return {"ok": false, "message": "这张磁盘没有关联的上交任务。"}
	var task: Dictionary = definitions[task_id]
	var state: Dictionary = task_states.get(task_id, {})
	if str(state.get("status", "")) != "downloaded":
		return {"ok": false, "message": "任务尚未下载，或已经结束。"}
	var loaded_path: String = disc_mgr.current_loaded_path
	if loaded_path != get_inbox_dir().path_join(str(state.get("filename", ""))):
		return {"ok": false, "message": "请加载个人任务箱中的磁盘副本再上交。"}
	if number != str(task.get("giver_number", "")):
		var recipient: Dictionary = main.dial_mgr.resolve_number(number)
		var character: String = str(recipient.get("character", ""))
		if character.is_empty():
			return {"ok": false, "message": "未知的接收方号码。"}
		var wrong: Dictionary = task.get("wrong_recipient", {})
		var rule: Dictionary = wrong.get(character, wrong.get("default", {"action": "return"}))
		if str(rule.get("action", "return")) == "confiscate":
			return _finish_task(task_id, "confiscated", rule)
		return {"ok": false, "message": str(rule.get("message", "这不是交给我的任务，磁盘已退回。"))}
	var verdict: Dictionary = check_requirements(task_id)
	if not bool(verdict["passed"]):
		var failure: Dictionary = task.get("on_fail", {})
		var reasons: PackedStringArray = PackedStringArray()
		for reason in verdict["missing"]:
			reasons.append(str(reason))
		return {"ok": false, "message": str(failure.get("message", "任务未达标，请继续探索。")) + "\n" + "\n".join(reasons)}
	return _finish_task(task_id, "submitted", task.get("on_success", {}))

func _finish_task(task_id: String, result: String, effects: Dictionary) -> Dictionary:
	var state: Dictionary = task_states[task_id]
	var filename: String = str(state.get("filename", ""))
	var source: String = get_inbox_dir().path_join(filename)
	if not FileAccess.file_exists(source):
		return {"ok": false, "message": "个人磁盘副本不存在，无法归档。"}
	var folder: String = _user_disc_dir().path_join(result)
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return {"ok": false, "message": "无法创建归档目录。"}
	var target: String = folder.path_join(filename)
	if FileAccess.file_exists(target):
		target = folder.path_join(str(Time.get_unix_time_from_system()) + "_" + filename)
	# 当前磁盘先存档并弹出，再移动玩家副本。
	disc_mgr.eject_story()
	if DirAccess.rename_absolute(source, target) != OK:
		return {"ok": false, "message": "磁盘归档失败，任务仍可重试。"}
	var story_id: String = str(state.get("story_id", ""))
	var patch: Dictionary = modifications.get(story_id, {})
	var fake_pass: bool = not (patch.get("changed", {}) as Dictionary).is_empty() or not (patch.get("deleted", []) as Array).is_empty()
	state["status"] = result
	state["fake_pass"] = fake_pass
	state["finished_at"] = int(Time.get_unix_time_from_system())
	task_states[task_id] = state
	archive.append({"task_id": task_id, "filename": filename, "result": result, "fake_pass": fake_pass, "day": main.env_monitor.current_day})
	_save_state()
	disc_mgr.scan_stories(true)
	if result == "submitted" and fake_pass:
		main.daily_dialogue_mgr.set_flag(task_id + "_fake_pass", 1)
	if effects.has("score") and main.perf_mgr:
		var parts: PackedStringArray = str(effects["score"]).split(":")
		if parts.size() == 2:
			main.perf_mgr.add_score(int(parts[1]), str(parts[0]))
			main.perf_mgr.save_progress()
	if effects.has("flags") and main.daily_dialogue_mgr:
		var flags: Dictionary = effects["flags"]
		for flag in flags.keys():
			main.daily_dialogue_mgr.set_flag(str(flag), flags[flag])
	if not str(effects.get("dialogue", "")).is_empty() and main.comm_mgr:
		main.comm_mgr.trigger_dialogue(str(effects["dialogue"]))
	return {"ok": true, "message": "磁盘已上交并存入个人归档。" if result == "submitted" else str(effects.get("message", "磁盘已被没收；可重新下载。"))}

func debug_reset_task(task_id: String) -> bool:
	if not definitions.has(task_id):
		return false
	task_states.erase(task_id)
	var kept: Array = []
	for entry in archive:
		if str((entry as Dictionary).get("task_id", "")) != task_id:
			kept.append(entry)
	archive = kept
	var story_id: String = str(definitions[task_id].get("story_id", ""))
	if not story_id.is_empty():
		modifications.erase(story_id)
	_save_state()
	disc_mgr.scan_stories(true)
	return true

func get_task_list() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for task_id in definitions.keys():
		var task: Dictionary = definitions[task_id]
		items.append({"id": task_id, "title": str(task.get("title", task_id)), "status": get_task_status(str(task_id))})
	return items
