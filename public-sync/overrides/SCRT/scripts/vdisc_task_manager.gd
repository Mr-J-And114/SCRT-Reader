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
var _modal_kind: String = "download"

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
		"redownload", "force_submit":
			if _confirm_pending:
				_confirm_choice = 1
		"keep", "close":
			close_download()

func _open_download(title: String, kind: String = "download") -> void:
	_modal_kind = kind
	_download_layer = CanvasLayer.new()
	var crt_layer: CanvasLayer = main.get_node("CRTEffect")
	_download_layer.layer = crt_layer.layer - 1
	main.add_child(_download_layer)
	var shade := ColorRect.new()
	shade.color = Color.TRANSPARENT
	_download_layer.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	shade.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var background := StyleBoxFlat.new()
	# 独立弹窗遮住底下正文，同时保留共同CRT背景的少量透光。
	background.bg_color = Color(main.T.bg, 0.90)
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
	var heading: String = "VDISC SUBMISSION / 上交确认" if _modal_kind == "submit" else "VDISC TRANSFER / 磁盘传输"
	var lines: Array[String] = [heading]
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
		if _modal_kind == "submit":
			lines.append("[url=force_submit]> 执意上交 [Y][/url]")
			lines.append("[url=keep]> 返回重做 [Enter/N/Esc][/url]")
		else:
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

func _confirm_incomplete_submit(task_id: String, verdict: Dictionary) -> bool:
	return await confirm_incomplete_submission(str(definitions[task_id].get("title", task_id)), verdict, definitions[task_id].get("on_fail", {}))

## 共用未达标确认页；只返回玩家决定，本身不归档、不计分、不触发通讯。
func confirm_incomplete_submission(title: String, verdict: Dictionary, failure: Dictionary = {}) -> bool:
	_open_download(title, "submit")
	_confirm_pending = true
	_confirm_choice = -1
	_download_show_bar = false
	_download_color = main.T.warning_hex
	var reasons: PackedStringArray = PackedStringArray(verdict.get("missing", []))
	_download_status = "警告：任务尚未达标。\n" + "\n".join(reasons)
	var note: String = str(failure.get("message", ""))
	if not note.is_empty():
		_download_status += "\n" + note
	_download_status += "\n\n执意上交将归档磁盘，结束本次任务，不能补交。\n达标奖励不会发放；返回重做保留磁盘及进度。"
	var score: PackedStringArray = str(failure.get("score", "")).split(":")
	if score.size() == 2 and int(score[1]) != 0:
		_download_status += "\n此任务另设未达标绩效调整：%+d。" % int(score[1])
	_render_download()
	while _confirm_choice < 0 and is_download_open():
		await main.get_tree().process_frame
	var confirmed: bool = _confirm_choice == 1
	_confirm_pending = false
	close_download()
	return confirmed

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
			# 主线绑定由主项目管理；盘内同名定义不能覆盖邮件与剧情路由。
			if bool(definitions.get(str(task_id), {}).get("main_story_binding", false)) and not bool(tasks[task_id].get("main_story_binding", false)):
				continue
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

func _save_state() -> Dictionary:
	if not _has_user():
		return SaveManager.save_result("skipped", "no_account")
	main.user_mgr.current_user["vdisc_task_data"] = {
		"tasks": task_states.duplicate(true),
		"modifications": modifications.duplicate(true),
		"archive": archive.duplicate(true),
	}
	return main.user_mgr._save_current_profile()

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
		if filename in download.get("legacy_filenames", []):
			return str(task_id)
		if filename == str(task_states.get(task_id, {}).get("filename", "")):
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
	if _archive_pending(task_id) or not _find_operation(task_id).is_empty() and str(task_states.get(task_id, {}).get("status", "")) == "downloaded":
		return {"ok": false, "message": "归档操作尚待恢复，暂不能重新领取。"}
	if get_task_status(task_id) == "submitted":
		return {"ok": false, "message": "任务已上交，归档记录可在 vdisc 中查看。"}
	var task: Dictionary = definitions[task_id]
	var download: Dictionary = task.get("download", {})
	if not str(download.get("radio_transfer_id", "")).is_empty():
		return {"ok": false, "message": "请在 RADIO 的 WATERFALL 页面找到发送电台，分别确认并接收所有分段。"}
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
		# 编辑器联调样例单独存放；正式任务与个人副本路径保持不变。
		if OS.has_feature("editor") and task_id.begins_with("demo_") and not FileAccess.file_exists(source):
			source = disc_mgr.vdisc_dir.path_join("_dev").path_join(filename)
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
		if OS.has_feature("editor") and task_id.begins_with("demo_") and not FileAccess.file_exists(source):
			source = disc_mgr.vdisc_dir.path_join("_dev").path_join(filename)
		if FileAccess.file_exists(source):
			bytes = FileAccess.get_file_as_bytes(source)
	var result: Dictionary = store_download(task_id, bytes)
	result["handled"] = true
	return result

func store_download(task_id: String, bytes: PackedByteArray, replace_existing: bool = false, radio_transfer_id: String = "") -> Dictionary:
	if not definitions.has(task_id) or not _has_user():
		return {"ok": false, "message": "任务或玩家无效。"}
	if _archive_pending(task_id) or not _find_operation(task_id).is_empty() and str(task_states.get(task_id, {}).get("status", "")) == "downloaded":
		return {"ok": false, "message": "归档操作尚待恢复，暂不能重新领取。"}
	if get_task_status(task_id) == "submitted":
		return {"ok": false, "message": "任务已经上交。"}
	var download: Dictionary = definitions[task_id].get("download", {})
	var required_transfer: String = str(download.get("radio_transfer_id", ""))
	if not required_transfer.is_empty():
		if radio_transfer_id != required_transfer or main.radio_receiver == null or not main.radio_receiver.file_receiver.is_package_ready(required_transfer):
			return {"ok": false, "message": "无线电分段尚未全部接收并通过校验。"}
		if bytes != main.radio_receiver.file_receiver.assemble_package(required_transfer):
			return {"ok": false, "message": "磁盘内容与实际接收的无线电文件不一致。"}
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
	task_states[task_id] = {"status": "downloaded", "story_id": story_id, "filename": filename, "download_round": Crypto.new().generate_random_bytes(16).hex_encode()}
	_save_state()
	disc_mgr.scan_stories(true)
	var message: String = "磁盘已重新下载，任务与探索进度已重置。" if reset_progress else "磁盘已下载到个人任务箱。"
	return {"ok": true, "message": message + "\n关闭邮件后输入 scan，再用 load <编号> 加载。\n输入 vdisc 查看任务要求和上交命令。"}

func apply_modifications(story_id: String, target_fs: FileSystem = null) -> void:
	var working_fs: FileSystem = target_fs if target_fs != null else fs
	var task_id: String = get_task_for_story(story_id)
	var generated: Dictionary = task_states.get(task_id, {}).get("generated_files", {})
	for path in generated:
		working_fs.file_system[str(path)] = {"type": "file", "content": str(generated[path]), "origin": "reward"}
	var patch: Dictionary = modifications.get(story_id, {})
	for path in patch.get("deleted", []):
		working_fs.file_system.erase(str(path))
	var changed: Dictionary = patch.get("changed", {})
	for path in changed.keys():
		var record: Dictionary = changed[path]
		var entry: Dictionary = {"type": "file", "content": str(record.get("content", "")), "origin": str(record.get("origin", "created"))}
		if record.has("binary_base64"):
			entry["binary"] = Marshalls.base64_to_raw(str(record["binary_base64"]))
		working_fs.file_system[str(path)] = entry

## 仅当前任务盘声明的完成模块可以交付其规定的文件；普通文件编辑不能伪造通关回执。
func publish_module_reward(mod_id: String, files: Dictionary, receipt: Dictionary) -> bool:
	if not _has_user() or main._desktop_mode:
		return false
	var task_id: String = get_task_for_story(main.story_id)
	if task_id.is_empty() or get_task_status(task_id) != "downloaded":
		return false
	var task: Dictionary = definitions[task_id]
	if str(task.get("completion_mod_id", "")) != mod_id or str(receipt.get("reward_id", "")).is_empty():
		return false
	var state: Dictionary = task_states[task_id]
	if disc_mgr.current_loaded_path != get_inbox_dir().path_join(str(state.get("filename", ""))):
		return false
	var required: Array[String] = []
	if not bool(task.get("completion_receipt_only", false)):
		required = _required_paths(task, "reward_files") if task.has("reward_files") else _required_paths(task.get("requirements", {}), "required_read_files")
	if (required.is_empty() and not bool(task.get("completion_receipt_only", false))) or files.size() != required.size():
		return false
	for path in required:
		# 奖励只发布根目录文件；不允许脚本路径、覆盖原盘或越过配置名单。
		if not files.has(path) or not files[path] is String or path.get_base_dir() != "/" or fs.is_hidden_path(path):
			return false
	if state.has("completion_receipt"):
		return str(state.completion_receipt.get("reward_id", "")) == str(receipt.reward_id)
	for path in required:
		if fs.file_system.has(path):
			return false
	var previous: Dictionary = state.duplicate(true)
	state["generated_files"] = files.duplicate(true)
	state["completion_receipt"] = receipt.duplicate(true)
	task_states[task_id] = state
	var saved: Dictionary = _save_state()
	if saved.get("status", "") != "saved":
		task_states[task_id] = previous
		main.user_mgr.current_user["vdisc_task_data"]["tasks"][task_id] = previous.duplicate(true)
		return false
	apply_modifications(main.story_id)
	disc_mgr._auto_save()
	return true

## 只有当前个人原盘的已加载模块可以登记一次真实的人类走子。
func record_module_play(mod_id: String) -> bool:
	if not _has_user() or main._desktop_mode:
		return false
	var task_id: String = get_task_for_story(main.story_id)
	if task_id.is_empty() or str(definitions[task_id].get("completion_mod_id", "")) != mod_id or get_task_status(task_id) != "downloaded":
		return false
	var state: Dictionary = task_states[task_id]
	if disc_mgr.current_loaded_path != get_inbox_dir().path_join(str(state.get("filename", ""))):
		return false
	var module = disc_mgr._loaded_external_mod
	if module == null or disc_mgr._loaded_external_mod_id != mod_id or not is_instance_valid(module._view):
		return false
	var moves: Array = module._view.game.engine.state.get("moves", [])
	if moves.is_empty() or str(moves.back().get("side", "")) != "cn":
		return false
	if not state.get("play_receipt", {}).is_empty(): return true
	var previous: Dictionary = state.duplicate(true)
	state["play_receipt"] = {"from": moves.back().from, "to": moves.back().to, "ply": moves.size()}
	task_states[task_id] = state
	if _save_state().get("status", "") == "saved": return true
	task_states[task_id] = previous
	main.user_mgr.current_user["vdisc_task_data"]["tasks"][task_id] = previous.duplicate(true)
	return false

func is_module_task_completed(mod_id: String) -> bool:
	if not _has_user() or main._desktop_mode:
		return false
	var task_id: String = get_task_for_story(main.story_id)
	if task_id.is_empty() or str(definitions[task_id].get("completion_mod_id", "")) != mod_id:
		return false
	var state: Dictionary = task_states.get(task_id, {})
	return disc_mgr.current_loaded_path == get_inbox_dir().path_join(str(state.get("filename", ""))) and not str(state.get("completion_receipt", {}).get("reward_id", "")).is_empty()

func create_module_backup(mod_id: String) -> Dictionary:
	if not is_module_task_completed(mod_id):
		return {"ok": false, "message": "当前个人任务盘尚未通关。"}
	return _ensure_task_backup(get_task_for_story(main.story_id))

## 备份是账号磁盘箱中的独立 SCP；原盘归档不会删除它，也不复用任务身份。
## 先写临时包、逐条核验，再改名；失败保留原盘并允许重试。
func _ensure_task_backup(task_id: String) -> Dictionary:
	if not _has_user() or not definitions.has(task_id):
		return {"ok": false, "message": "没有活动账号或任务。"}
	var state: Dictionary = task_states.get(task_id, {})
	var config: Dictionary = definitions[task_id].get("completion_backup", {})
	var backup_name: String = str(config.get("filename", ""))
	var backup_id: String = str(config.get("story_id", ""))
	if str(state.get("completion_receipt", {}).get("reward_id", "")).is_empty() or not _safe_filename(backup_name) or backup_id.is_empty() or not get_task_for_story(backup_id).is_empty():
		return {"ok": false, "message": "备份配置或通关回执无效。"}
	var source_path: String = get_inbox_dir().path_join(str(state.get("filename", "")))
	var target_path: String = get_inbox_dir().path_join(backup_name)
	if source_path == target_path:
		return {"ok": false, "message": "备份不能覆盖任务原盘。"}
	var source := ZIPReader.new()
	if source.open(source_path) != OK:
		return {"ok": false, "message": "无法读取原盘，请保留原盘后重试。"}
	var parsed: Variant = JSON.parse_string(source.read_file("manifest.json").get_string_from_utf8())
	if not parsed is Dictionary or str(parsed.get("story", {}).get("id", "")) != str(state.get("story_id", "")):
		source.close()
		return {"ok": false, "message": "原盘身份不匹配。"}
	var manifest: Dictionary = parsed
	if not bool(manifest.get("chess_replay_supported", false)):
		source.close()
		return {"ok": false, "message": "该介质版本不支持备份运行，未进行复制。"}
	manifest["story"]["id"] = backup_id
	manifest["story"]["title"] = str(config.get("title", "KING · 个人备份"))
	manifest["package"]["id"] = backup_id
	manifest["settings"]["start_clearance"] = 1
	manifest["settings"]["start_path"] = "/Chess"
	manifest["chess_replay"] = true
	manifest.erase("vdisc_tasks")
	var names: PackedStringArray = source.get_files()
	var expected: Dictionary = {}
	for name in names:
		expected[name] = JSON.stringify(manifest, "\t").to_utf8_buffer() if name == "manifest.json" else source.read_file(name)
	source.close()
	if FileAccess.file_exists(target_path):
		if _verify_backup(target_path, expected):
			return {"ok": true, "created": false, "path": target_path}
		# 已有旧版合法备份也满足“保留一份”要求，不覆盖玩家文件或阻塞原盘归档。
		var existing := ZIPReader.new()
		if existing.open(target_path) == OK:
			var old: Variant = JSON.parse_string(existing.read_file("manifest.json").get_string_from_utf8())
			existing.close()
			if old is Dictionary and str(old.get("story", {}).get("id", "")) == backup_id and bool(old.get("chess_replay", false)) and bool(old.get("chess_replay_supported", false)):
				return {"ok": true, "created": false, "path": target_path, "retained_version": str(old.story.get("version", ""))}
		return {"ok": false, "message": "已有同名备份与本次内容不符，未覆盖；请保留文件并检查。"}
	var pending_path: String = target_path + ".pending"
	var packer := ZIPPacker.new()
	var error: Error = packer.open(pending_path)
	if error == OK:
		for name in names:
			error = packer.start_file(name)
			if error != OK: break
			error = packer.write_file(expected[name])
			if error != OK: break
			error = packer.close_file()
			if error != OK: break
		var close_error: Error = packer.close()
		if error == OK: error = close_error
	if error != OK or not _verify_backup(pending_path, expected):
		return {"ok": false, "message": "备份写入或校验失败。请检查存储后重试。"}
	if DirAccess.rename_absolute(pending_path, target_path) != OK:
		return {"ok": false, "message": "备份落盘失败；请保留原盘后重试。"}
	return {"ok": true, "created": true, "path": target_path}

func _verify_backup(path: String, expected: Dictionary) -> bool:
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return false
	var names: PackedStringArray = reader.get_files()
	var valid: bool = true
	var file_count: int = 0
	for name in names:
		# ZIPPacker 自动补父目录条目；它们不属于待复制的文件载荷。
		if name.ends_with("/"): continue
		file_count += 1
		if not expected.has(name) or reader.read_file(name) != expected[name]:
			valid = false
	reader.close()
	return valid and file_count == expected.size()

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
	var task_id: String = get_task_for_story(story_id)
	if not task_id.is_empty():
		var requirements: Dictionary = definitions[task_id].get("requirements", {})
		if requirements.has("required_read_files"):
			# 必读名单固定分母；锁定、缺失的文件仍计入总数。
			var required_paths: Array[String] = _required_paths(requirements, "required_read_files")
			total = required_paths.size()
			for path in required_paths:
				if _is_required_file_read(path):
					read += 1
			var fixed_percent: int = int(float(read) / float(total) * 100.0) if total > 0 else 0
			return {"read": read, "total": total, "percent": fixed_percent, "size_kb": float(fs.count_total_size()) / 1024.0}
	for path in fs.file_system.keys():
		var entry: Dictionary = fs.file_system[path]
		if str(entry.get("type", "")) != "file" or fs.is_hidden_path(str(path)) or not fs.has_clearance(str(path)):
			continue
		total += 1
		if main.read_files.has(str(path)):
			read += 1
	var percent: int = int(float(read) / float(total) * 100.0) if total > 0 else 0
	return {"read": read, "total": total, "percent": percent, "size_kb": float(fs.count_total_size()) / 1024.0}

func _required_paths(requirements: Dictionary, field: String) -> Array[String]:
	var paths: Array[String] = []
	for value in requirements.get(field, []):
		var path: String = fs.normalize_path(str(value))
		if not paths.has(path):
			paths.append(path)
	return paths

func _is_required_file_read(path: String) -> bool:
	var node = fs.get_node_at_path(path)
	if node == null or node.type != "file" or fs.is_hidden_path(path) or not fs.has_clearance(path):
		return false
	if not fs.get_file_password_key(path).is_empty() and not fs.is_file_password_unlocked(path):
		return false
	return main.read_files.has(path)

func check_requirements(task_id: String) -> Dictionary:
	if not definitions.has(task_id):
		return {"passed": false, "missing": ["未知任务"]}
	var requirements: Dictionary = definitions[task_id].get("requirements", {})
	var task: Dictionary = definitions[task_id]
	var state: Dictionary = task_states.get(task_id, {})
	var detail: Dictionary = get_progress_detail(str(state.get("story_id", task.get("story_id", ""))))
	var missing: Array[String] = []
	if bool(requirements.get("completion_receipt", false)) and str(state.get("completion_receipt", {}).get("reward_id", "")).is_empty():
		missing.append("正式挑战尚未通关")
	if int(detail["percent"]) < int(requirements.get("min_read_percent", 0)):
		missing.append("探索进度不足：%d%% / %d%%" % [int(detail["percent"]), int(requirements["min_read_percent"])])
	for path in requirements.get("required_files", []):
		var required_node = fs.get_node_at_path(str(path))
		if required_node == null or required_node.type != "file":
			missing.append("缺少必需文件：" + str(path))
	for path in _required_paths(requirements, "required_read_files"):
		var required_node = fs.get_node_at_path(path)
		if required_node == null or required_node.type != "file":
			missing.append("必读文件缺失：" + path)
		elif not _is_required_file_read(path):
			missing.append("必读文件尚未完成阅读：" + path)
	for path in _required_paths(requirements, "required_unlocked_files"):
		var required_node = fs.get_node_at_path(path)
		if required_node == null or required_node.type != "file":
			missing.append("口令文件缺失：" + path)
		elif fs.get_file_password_key(path).is_empty():
			missing.append("口令文件未配置保护：" + path)
		elif not fs.is_file_password_unlocked(path):
			missing.append("文件口令尚未解锁：" + path)
	if int(detail["total"]) < int(requirements.get("min_total_files", 0)):
		missing.append("文件数量不足")
	if float(detail["size_kb"]) < float(requirements.get("min_size_kb", 0)):
		missing.append("数据包体积不足")
	var gate_missing: Array[String] = []
	if bool(task.get("submission_gate", false)):
		for path in _required_paths(requirements, "required_read_files"):
			if not _is_required_file_read(path): gate_missing.append("尚未完成资料审阅：" + path)
		if state.get("play_receipt", {}).is_empty(): gate_missing.append("尚无实际对局记录")
		if state.get("play_receipt", {}).is_empty(): missing.append("尚无实际对局记录")
	return {"passed": missing.is_empty(), "missing": missing, "detail": detail, "eligible": gate_missing.is_empty(), "eligibility_missing": gate_missing}

## 桌面检查独立个人副本，不载入其通讯、邮件、触发器或覆盖桌面状态。
func _inspect_task_copy(task_id: String, path: String) -> Dictionary:
	var loader := StoryLoader.new()
	if not loader.load_story(path):
		return {"ok": false, "message": "无法读取个人磁盘：" + loader.error_message}
	var story: Dictionary = loader.manifest.get("story", {})
	var story_id: String = str(story.get("id", ""))
	if story_id != str(task_states[task_id].get("story_id", definitions[task_id].get("story_id", ""))):
		return {"ok": false, "message": "个人磁盘的故事编号与任务不匹配。"}
	var working_fs := FileSystem.new()
	working_fs.file_system = loader.file_system
	working_fs.hidden_dirs.assign(loader.manifest.get("hidden_dirs", []))
	working_fs.story_permissions = loader.manifest.get("permissions", story.get("permissions", {}))
	working_fs.story_file_passwords = loader.manifest.get("file_passwords", story.get("file_passwords", {}))
	var saved: Dictionary = main.user_mgr.load_story_progress(story_id)
	var settings: Dictionary = loader.manifest.get("settings", {})
	working_fs.player_clearance = int(saved.get("player_clearance", settings.get("start_clearance", story.get("start_clearance", 0))))
	working_fs.unlocked_file_passwords.assign(saved.get("unlocked_file_passwords", []))
	apply_modifications(story_id, working_fs)
	var inspector = get_script().new()
	inspector.fs = working_fs
	inspector.main = {"read_files": saved.get("read_files", [])}
	inspector.definitions = definitions
	inspector.task_states = task_states
	return {"ok": true, "verdict": inspector.check_requirements(task_id)}

func submit(number: String, disc_number: String = "") -> Dictionary:
	if download_busy or is_download_open():
		return {"ok": false, "message": "请先完成当前磁盘操作。"}
	if not _has_user():
		return {"ok": false, "message": "请先登录。"}
	if not main._desktop_mode or not main.story_id.is_empty():
		return {"ok": false, "message": "请先 eject 返回桌面，再输入 submit <接收方号码> <盘编号>。"}
	if not disc_number.is_valid_int():
		return {"ok": false, "message": "用法：submit <接收方号码> <scan列表中的盘编号>。"}
	var index: int = int(disc_number) - 1
	if index < 0 or index >= disc_mgr.available_stories.size():
		return {"ok": false, "message": "盘编号无效，请先用 scan 查看当前磁盘列表。"}
	var selected: Dictionary = disc_mgr.available_stories[index]
	var loaded_path: String = str(selected.get("path", ""))
	var selected_story: Dictionary = selected.get("story", {})
	var task_id: String = get_task_for_story(str(selected_story.get("id", "")))
	if task_id.is_empty():
		return {"ok": false, "message": "这张磁盘没有关联的上交任务。"}
	var task: Dictionary = definitions[task_id]
	var state: Dictionary = task_states.get(task_id, {})
	if str(state.get("status", "")) != "downloaded":
		return {"ok": false, "message": "任务尚未下载，或已经结束。"}
	if loaded_path != get_inbox_dir().path_join(str(state.get("filename", ""))):
		return {"ok": false, "message": "只能上交个人任务箱中的磁盘副本。"}
	var inspected: Dictionary = _inspect_task_copy(task_id, loaded_path)
	if not bool(inspected.get("ok", false)):
		return inspected
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
	var verdict: Dictionary = inspected.verdict
	if not bool(verdict.get("eligible", true)):
		return {"ok": false, "message": "资料审阅或对局记录不完整，磁盘已退回。", "missing": verdict.get("eligibility_missing", [])}
	var forced: bool = false
	if not bool(verdict["passed"]):
		var username: String = main.user_mgr.get_username()
		var day: int = main.env_monitor.current_day
		forced = await _confirm_incomplete_submit(task_id, verdict)
		if not forced:
			return {"ok": false, "cancelled": true, "message": "已取消上交；磁盘和探索进度保留，可继续补做。"}
		# 确认期间只允许归档最初检查的账号、任务和个人副本。
		if not _has_user() or main.user_mgr.get_username() != username or not main._desktop_mode or not main.story_id.is_empty() or get_task_status(task_id) != "downloaded" or get_inbox_dir().path_join(str(task_states[task_id].get("filename", ""))) != loaded_path or main.env_monitor.current_day != day:
			return {"ok": false, "message": "任务状态已改变，上交已取消，请重新检查。"}
		inspected = _inspect_task_copy(task_id, loaded_path)
		if not bool(inspected.get("ok", false)):
			return inspected
		verdict = inspected.verdict
		if not bool(verdict.get("eligible", true)):
			return {"ok": false, "message": "资料审阅或对局记录不完整，磁盘已退回。"}
	var passed: bool = bool(verdict["passed"])
	if passed and task.has("completion_backup"):
		var backup: Dictionary = _ensure_task_backup(task_id)
		if not bool(backup.get("ok", false)):
			return backup
	var effects: Dictionary = task.get("on_success", {}) if passed else task.get("on_fail", {})
	return _finish_task(task_id, "submitted", effects, verdict, forced and not passed)

func _archive_pending(task_id: String) -> bool:
	var state: Dictionary = task_states.get(task_id, {})
	var operation_id: String = str(state.get("archive_operation", ""))
	if operation_id.is_empty():
		return false
	return not bool(state.get("archive_complete", false)) or main.perf_mgr == null or not main.perf_mgr.has_archive_reward_receipt(operation_id) or main.daily_dialogue_mgr == null or not main.daily_dialogue_mgr.has_archive_effect_receipt(operation_id)

func has_pending_archives() -> bool:
	for task_id in task_states:
		if _archive_pending(str(task_id)):
			return true
	return false

func _archive_version() -> String:
	return main.daily_dialogue_mgr.get_story_version() if main.daily_dialogue_mgr else ""

func _operation_dir() -> String:
	return _user_disc_dir().path_join("archive_operations")

func _read_operation(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

func _find_operation(task_id: String) -> Dictionary:
	var state: Dictionary = task_states.get(task_id, {})
	var known: String = str(state.get("archive_operation", ""))
	if not known.is_empty():
		if known.length() != 32 or not known.is_valid_hex_number(false):
			return {"invalid": true}
		var existing: Dictionary = _read_operation(_operation_dir().path_join(known + ".json"))
		return existing if not existing.is_empty() else {"invalid": true}
	# 意图已落盘、profile尚未确认时，只关联同账号/版本/领取轮次的原任务。
	if str(state.get("status", "")) != "downloaded":
		return {}
	var found: Dictionary = {}
	if not DirAccess.dir_exists_absolute(_operation_dir()):
		return found
	for name in DirAccess.get_files_at(_operation_dir()):
		if name.get_extension() != "json":
			continue
		var candidate: Dictionary = _read_operation(_operation_dir().path_join(name))
		if str(candidate.get("task_id", "")) != task_id or str(candidate.get("account", "")) != main.user_mgr.get_username() or str(candidate.get("story_version", "")) != _archive_version() or str(candidate.get("round", "")) != str(state.get("download_round", "")):
			continue
		if name != str(candidate.get("operation_id", "")) + ".json":
			return {"invalid": true}
		if not found.is_empty():
			return {"invalid": true}
		found = candidate
	return found

func _archive_failure(stage: String, archived: bool = false) -> Dictionary:
	return {"ok": false, "pending": true, "archived": archived, "stage": stage,
		"message": "归档尚未完整确认（%s）；保留现有证据，请恢复保存条件后重新登录重试，勿重新领取。" % stage}

func _finish_task(task_id: String, result: String, effects: Dictionary, verdict: Dictionary = {}, forced: bool = false) -> Dictionary:
	if not _has_user() or not definitions.has(task_id) or not task_states.has(task_id):
		return _archive_failure("task_context")
	var operation: Dictionary = _find_operation(task_id)
	if not operation.is_empty():
		return _continue_archive(task_id, operation)
	var state: Dictionary = task_states[task_id]
	if result not in ["submitted", "confiscated"] or str(state.get("status", "")) != "downloaded":
		# 无操作证据的历史终态不补奖，也不根据文件名猜测旧操作。
		return _archive_failure("legacy_or_terminal_state")
	var filename: String = str(state.get("filename", ""))
	if not _safe_filename(filename):
		return _archive_failure("filename")
	var source: String = get_inbox_dir().path_join(filename)
	if not FileAccess.file_exists(source):
		return _archive_failure("source_missing")
	if main.perf_mgr == null:
		return _archive_failure("performance_dependency")
	var allow_baseline: bool = archive.is_empty() and not DirAccess.dir_exists_absolute(_operation_dir())
	for previous in task_states.values():
		if not str(previous.get("archive_operation", "")).is_empty():
			allow_baseline = false
	var baseline: Dictionary = main.perf_mgr.prepare_archive_baseline(allow_baseline)
	if baseline.status != "saved":
		return _archive_failure("performance_baseline")
	var operation_id: String = Crypto.new().generate_random_bytes(16).hex_encode()
	var folder: String = _user_disc_dir().path_join(result)
	var target: String = folder.path_join(filename)
	if FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target):
		target = folder.path_join(operation_id + "_" + filename)
	var story_id: String = str(state.get("story_id", ""))
	var patch: Dictionary = modifications.get(story_id, {})
	var passed: bool = result == "submitted" and bool(verdict.get("passed", false))
	var fake_pass: bool = passed and (not (patch.get("changed", {}) as Dictionary).is_empty() or not (patch.get("deleted", []) as Array).is_empty())
	var flags: Dictionary = {}
	var feedback: String = ""
	if result == "submitted":
		flags = {task_id + "_submitted": 1, task_id + "_passed": 1 if passed else 0,
			task_id + "_forced_submit": 1 if forced else 0, task_id + "_fake_pass": 1 if fake_pass else 0}
	flags.merge(effects.get("flags", {}), true)
	operation = {"operation_id": operation_id, "account": main.user_mgr.get_username(),
		"performance_baseline_sha256": str(baseline.sha256),
		"story_version": _archive_version(), "task_id": task_id, "story_id": story_id,
		"round": str(state.get("download_round", "")), "source": source, "target": target,
		"sha256": FileAccess.get_sha256(source), "filename": filename, "result": result,
		"passed": passed, "forced": forced, "fake_pass": fake_pass, "missing": verdict.get("missing", []).duplicate(),
		"effects": effects.duplicate(true), "flags": flags, "feedback": feedback,
		"day": main.env_monitor.current_day, "finished_at": int(Time.get_unix_time_from_system())}
	# 单次、不可变的操作意图；后续 profile / 奖励保存失败不会覆盖这份恢复证据。
	var intent_path: String = _operation_dir().path_join(operation_id + ".json")
	if FileAccess.file_exists(intent_path) or DirAccess.dir_exists_absolute(intent_path):
		return _archive_failure("intent_collision")
	if SaveManager.write_json_checked(intent_path, operation).status != "saved":
		return _archive_failure("intent_save")
	return _continue_archive(task_id, operation, true)

func _continue_archive(task_id: String, operation: Dictionary, fresh: bool = false) -> Dictionary:
	if bool(operation.get("invalid", false)) or not _has_user():
		return _archive_failure("operation_evidence")
	var state: Dictionary = task_states[task_id]
	var operation_id: String = str(operation.get("operation_id", ""))
	var filename: String = str(state.get("filename", ""))
	var result: String = str(operation.get("result", ""))
	if operation_id.length() != 32 or not operation_id.is_valid_hex_number(false) or result not in ["submitted", "confiscated"] or not _safe_filename(filename):
		return _archive_failure("operation_context")
	var persisted: Dictionary = _read_operation(_operation_dir().path_join(operation_id + ".json"))
	if persisted.is_empty() or JSON.stringify(JSON.parse_string(JSON.stringify(operation))) != JSON.stringify(persisted):
		return _archive_failure("operation_evidence")
	for field in ["effects", "flags", "feedback", "missing", "passed", "forced", "fake_pass", "day", "finished_at"]:
		if not operation.has(field):
			return _archive_failure("operation_schema")
	if not operation.effects is Dictionary or not operation.flags is Dictionary or not operation.missing is Array:
		return _archive_failure("operation_schema")
	if str(operation.get("account", "")) != main.user_mgr.get_username() or str(operation.get("story_version", "")) != _archive_version() or str(operation.get("task_id", "")) != task_id or str(operation.get("round", "")) != str(state.get("download_round", "")) or str(operation.get("story_id", "")) != str(state.get("story_id", "")) or str(operation.get("filename", "")) != filename:
		return _archive_failure("operation_context")
	var source: String = get_inbox_dir().path_join(filename)
	var folder: String = _user_disc_dir().path_join(result)
	var target: String = str(operation.get("target", ""))
	if str(operation.get("source", "")) != source or target not in [folder.path_join(filename), folder.path_join(operation_id + "_" + filename)]:
		return _archive_failure("operation_paths")
	var digest: String = str(operation.get("sha256", ""))
	if digest.length() != 64 or not digest.is_valid_hex_number(false):
		return _archive_failure("operation_hash")
	var source_exists: bool = FileAccess.file_exists(source)
	var target_exists: bool = FileAccess.file_exists(target)
	if source_exists == target_exists:
		return _archive_failure("file_conflict_or_missing")
	if FileAccess.get_sha256(source if source_exists else target) != digest:
		return _archive_failure("file_hash_conflict")
	if bool(state.get("archive_complete", false)):
		if main.perf_mgr == null or not main.perf_mgr.has_archive_reward_receipt(operation_id) or main.daily_dialogue_mgr == null or not main.daily_dialogue_mgr.has_archive_effect_receipt(operation_id):
			return _archive_failure("completed_receipts_missing", target_exists)
		return _archive_success(operation) if target_exists else _archive_failure("terminal_file_conflict")
	state["archive_operation"] = operation_id
	task_states[task_id] = state
	# 每次继续前先确认 profile；失败时不移动磁盘、不发奖。
	if _save_state().status != "saved":
		return _archive_failure("intent_profile", target_exists)
	if source_exists:
		if DirAccess.make_dir_recursive_absolute(folder) != OK:
			return _archive_failure("archive_directory")
		if not main._desktop_mode:
			disc_mgr.eject_story()
		if DirAccess.rename_absolute(source, target) != OK:
			return _archive_failure("archive_move")
		if FileAccess.get_sha256(target) != digest:
			return _archive_failure("archive_verify", true)
	state["status"] = result
	for key in ["passed", "forced", "missing", "fake_pass", "finished_at"]:
		state[key] = operation[key]
	state["archive_path"] = target
	task_states[task_id] = state
	var recorded: bool = false
	for entry in archive:
		if str(entry.get("operation_id", "")) == operation_id:
			recorded = true
	if not recorded:
		archive.append({"operation_id": operation_id, "task_id": task_id, "filename": filename,
			"result": result, "passed": operation.passed, "forced": operation.forced,
			"missing": operation.missing, "fake_pass": operation.fake_pass, "day": operation.day, "path": target})
	if _save_state().status != "saved":
		return _archive_failure("terminal_profile", true)
	disc_mgr.scan_stories(true)
	if main.perf_mgr == null or main.daily_dialogue_mgr == null:
		return _archive_failure("effects_dependency", true)
	if main.env_monitor.current_day != int(operation.day) and not main.perf_mgr.has_archive_reward_receipt(operation_id):
		return _archive_failure("reward_day_context", true)
	var effects: Dictionary = operation.effects
	var amount: int = 0
	var category: String = "side"
	if effects.has("score"):
		var parts: PackedStringArray = str(effects.score).split(":")
		if parts.size() != 2 or not parts[1].is_valid_int():
			return _archive_failure("reward_format", true)
		category = parts[0]
		amount = int(parts[1])
	if main.perf_mgr.commit_archive_reward(operation_id, amount, category, str(operation.story_version)).status != "saved":
		return _archive_failure("reward_save", true)
	if main.daily_dialogue_mgr.commit_archive_effects(operation_id, operation.flags, str(operation.feedback), str(operation.story_version)).status != "saved":
		return _archive_failure("story_save", true)
	# trigger_dialogue 的 true 可能仅表示进入内存来电队列；也没有 flags_add 的整体提交回执。
	# 先持久化派发保留标记，只在本次新操作中调用一次；重登/重试绝不重播不确定效果。
	var dialogue: String = str(effects.get("dialogue", ""))
	if not dialogue.is_empty():
		if not state.has("archive_dialogue_dispatch"):
			state["archive_dialogue_dispatch"] = "reserved"
			task_states[task_id] = state
			if _save_state().status != "saved":
				return _archive_failure("dialogue_reservation", true)
			if fresh and main.comm_mgr:
				main.comm_mgr.trigger_dialogue(dialogue)
		return _archive_failure("dialogue_effects_unconfirmed", true)
	state["archive_complete"] = true
	task_states[task_id] = state
	if _save_state().status != "saved":
		state["archive_complete"] = false
		return _archive_failure("completion_profile", true)
	return _archive_success(operation)

func _archive_success(operation: Dictionary) -> Dictionary:
	var effects: Dictionary = operation.effects
	var result: String = str(operation.result)
	var message: String = str(effects.get("message", ""))
	if result == "submitted":
		message += "\n磁盘已上交并存入个人归档。" if bool(operation.passed) else "\n磁盘已上交并归档，但未达标；未获得达标奖励，本次任务已结束。"
	else:
		message = message if not message.is_empty() else "磁盘已被没收；可重新下载。"
	return {"ok": true, "archived": true, "passed": operation.passed, "forced": operation.forced, "operation_id": operation.operation_id, "message": message.strip_edges()}

## 登录时在账号、主线与绩效加载后运行；仅按同账号/版本/轮次的持久证据继续。
func recover_archives() -> Dictionary:
	if not _has_user():
		return {"ok": false, "pending": []}
	var pending: Array = []
	for task_id in task_states.keys():
		var operation: Dictionary = _find_operation(str(task_id))
		if operation.is_empty():
			continue
		if not bool(_continue_archive(str(task_id), operation).get("ok", false)):
			pending.append(str(task_id))
	return {"ok": pending.is_empty(), "pending": pending}


func debug_reset_task(task_id: String) -> bool:
	if not definitions.has(task_id):
		return false
	if _archive_pending(task_id):
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

func get_task_list(include_development: bool = false) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for task_id in definitions.keys():
		var task: Dictionary = definitions[task_id]
		var state: Dictionary = task_states.get(task_id, {})
		var status: String = get_task_status(str(task_id))
		# 普通状态页不展示尚未领取的联调任务；已领取或归档的历史记录仍可见。
		if not include_development and str(task_id).begins_with("demo_") and status == "not_started":
			continue
		var label: String = {"not_started": "未领取", "downloaded": "调查中", "submitted": "已上交", "confiscated": "已没收"}.get(status, status)
		if status == "submitted":
			# 旧存档的 submitted 均来自达标上交。
			label += "／达标" if bool(state.get("passed", true)) else "／未达标"
		items.append({"id": task_id, "title": str(task.get("title", task_id)), "status": status, "status_label": label})
	return items
