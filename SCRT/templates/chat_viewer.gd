# ============================================================
# templates/chat_viewer.gd
# 聊天记录模板全屏查看器
# 功能：逐条消息动画、打字指示器、多说话人颜色/头像、
#       系统消息、多媒体内嵌、CRT-ML 语法兼容
# ============================================================
class_name ChatViewer
extends RefCounted

# ══════════════════════════════════════════
#  引用
# ══════════════════════════════════════════
var main: Control = null
var fs: FileSystem = null
var T: Variant = null

# ══════════════════════════════════════════
#  UI 节点
# ══════════════════════════════════════════
var overlay: Panel = null
var content_rtl: RichTextLabel = null
var nav_label: RichTextLabel = null
var typing_label: RichTextLabel = null  # "xxx 正在输入..." 指示器

# ══════════════════════════════════════════
#  状态
# ══════════════════════════════════════════
var is_active: bool = false
var viewer_title: String = ""
var _on_exit_callback: Callable = Callable()

var _cached_input_visible: bool = true
var _cached_prompt_visible: bool = true
var _cached_output_text: String = ""

# ── 参与者定义 ──
# key = 用户ID, value = { "name", "color", "avatar", "role", "id", ... }
var _participants: Dictionary = {}

# ── 消息列表 ──
var _messages: Array[Dictionary] = []
var _msg_index: int = 0

# ── 播放模式 ──
enum PlayMode { AUTO, MANUAL }
var _play_mode: PlayMode = PlayMode.AUTO
var _default_mode: PlayMode = PlayMode.AUTO
var _auto_delay: float = 0.8
var _typing_delay_remaining: float = 0.0
var _msg_delay_remaining: float = 0.0
var _is_typing_indicator: bool = false
var _typing_sender: String = ""
var _all_displayed: bool = false
var _skippable: bool = true         # 首次阅读是否可跳过
var _is_first_read: bool = true     # 是否首次阅读此文件
var _typing_anim_timer: float = 0.0 # 打字动画计时器
var _typing_anim_dots: int = 1      # 当前点数 1~3
var _last_sender: String = ""       # 上一条消息的发送者（用于连续消息合并）
var _last_time: String = ""         # 上一条消息的时间戳

# ── 连接标志 ──
var _size_changed_connected: bool = false
var _process_connected: bool = false
var _last_frame_ms: int = 0

# ── 头像缓存 ──
var _avatar_cache: Dictionary = {}

const AVATAR_SIZE: int = 32

const SPEAKER_COLORS: Array[String] = [
	"#66FF66", "#66CCFF", "#FFCC66", "#FF6699",
	"#CC99FF", "#66FFCC", "#FF9966", "#99FF66",
	"#FF6666", "#6699FF", "#FFFF66", "#CC66FF",
]
const SYSTEM_COLOR: String = "#888888"

# ============================================================
func setup(p_main: Control, p_fs: FileSystem, p_theme: Variant) -> void:
	main = p_main
	fs = p_fs
	T = p_theme

# ============================================================
# 构建 UI
# ============================================================
func _ensure_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		return

	overlay = Panel.new()
	overlay.name = "ChatViewerOverlay"
	overlay.visible = false

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0)
	overlay.add_theme_stylebox_override("panel", bg_style)

	var root_control: Control = main
	root_control.add_child(overlay)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	overlay.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	# 主内容（自动滚到底部）
	content_rtl = RichTextLabel.new()
	content_rtl.bbcode_enabled = true
	content_rtl.fit_content = false
	content_rtl.scroll_active = true
	content_rtl.scroll_following = true
	content_rtl.selection_enabled = true
	content_rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_rtl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_rtl.mouse_filter = Control.MOUSE_FILTER_STOP
	CrtmlParser.apply_fonts(content_rtl)
	UIManager._apply_bold_font(content_rtl)
	if T:
		content_rtl.add_theme_color_override("default_color", T.secondary)
		content_rtl.add_theme_color_override("font_color", T.secondary)
	content_rtl.add_theme_constant_override("table_h_separation", 8)
	content_rtl.add_theme_constant_override("table_v_separation", 2)
	if main != null and main.has_method("_on_meta_clicked"):
		content_rtl.meta_clicked.connect(main._on_meta_clicked)
	vbox.add_child(content_rtl)

	# 打字指示器
	typing_label = RichTextLabel.new()
	typing_label.bbcode_enabled = true
	typing_label.fit_content = true
	typing_label.scroll_active = false
	typing_label.selection_enabled = false
	typing_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	typing_label.visible = false
	if T:
		typing_label.add_theme_color_override("default_color", T.muted)
	CrtmlParser.apply_fonts(typing_label)
	vbox.add_child(typing_label)

	# 底部导航
	nav_label = RichTextLabel.new()
	nav_label.bbcode_enabled = true
	nav_label.fit_content = true
	nav_label.scroll_active = false
	nav_label.selection_enabled = false
	nav_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if T:
		nav_label.add_theme_color_override("default_color", T.muted)
	CrtmlParser.apply_fonts(nav_label)
	vbox.add_child(nav_label)

	_align_overlay_to_output_area()

	var tree: SceneTree = main.get_tree()
	if tree and tree.root and not _size_changed_connected:
		_size_changed_connected = true
		tree.root.size_changed.connect(_align_overlay_to_output_area)
	if tree and not _process_connected:
		_process_connected = true
		_last_frame_ms = Time.get_ticks_msec()
		tree.process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if not is_active:
		return
	var now_ms: int = Time.get_ticks_msec()
	var delta: float = max(0.001, float(now_ms - _last_frame_ms) / 1000.0) if _last_frame_ms > 0 else 0.016
	_last_frame_ms = now_ms
	_process_playback(delta)

func _align_overlay_to_output_area() -> void:
	if overlay == null or not is_instance_valid(overlay):
		return
	var output_area: ScrollContainer = main.scroll_container
	if output_area == null:
		return
	var rect: Rect2 = output_area.get_global_rect()
	overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	overlay.position = rect.position
	overlay.size = rect.size

# ============================================================
# 打开
# ============================================================
func open(p_title: String, p_header: Dictionary, p_body: String, p_on_exit: Callable = Callable()) -> void:
	_ensure_overlay()
	viewer_title = p_title
	_on_exit_callback = p_on_exit
	_align_overlay_to_output_area()
	_avatar_cache.clear()

	_parse_participants(p_header)
	_parse_chat_options(p_header)
	_parse_messages(p_body)

	is_active = true
	_msg_index = 0
	_msg_delay_remaining = 0.3
	_typing_delay_remaining = 0.0
	_is_typing_indicator = false
	_all_displayed = false
	_play_mode = _default_mode
	_typing_anim_timer = 0.0
	_typing_anim_dots = 1
	_last_sender = ""
	_last_time = ""

	# 检查是否首次阅读
	_is_first_read = true
	if main.read_files.has(viewer_title) or main.read_files.has(p_title):
		_is_first_read = false

	_cached_input_visible = main.input_field.visible
	_cached_prompt_visible = main.prompt_label.visible
	main.input_field.visible = false
	main.prompt_label.visible = false
	_cached_output_text = main.output_text.text
	main.output_text.text = ""
	main.path_label.text = "CHAT LOG | " + viewer_title + " | Q/Esc 退出"

	# overlay 置顶
	var root_control: Control = main as Control
	root_control.move_child(overlay, root_control.get_child_count() - 1)
	var crt_node: Node = root_control.get_node_or_null("CRTEffect")
	if crt_node:
		root_control.move_child(crt_node, root_control.get_child_count() - 1)

	overlay.visible = true
	content_rtl.text = ""
	_render_chat_header()
	_update_nav()

# ============================================================
# 关闭
# ============================================================
func close() -> void:
	if not is_active:
		return
	is_active = false
	if overlay and is_instance_valid(overlay):
		overlay.visible = false
	if typing_label:
		typing_label.visible = false
	main.output_text.text = ""
	main.output_text.append_text(_cached_output_text)
	_cached_output_text = ""
	main.input_field.visible = _cached_input_visible
	main.prompt_label.visible = _cached_prompt_visible
	main._update_status_bar()
	main.input_field.grab_focus()
	if _on_exit_callback.is_valid():
		_on_exit_callback.call()
	viewer_title = ""
	_participants.clear()
	_messages.clear()
	_avatar_cache.clear()
	_msg_index = 0

# ============================================================
# 输入
# ============================================================
func handle_input(event: InputEvent) -> bool:
	if not is_active:
		return false
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE, KEY_Q:
				close()
				return true
			KEY_SPACE, KEY_ENTER:
				if not _all_displayed:
					_skip_current_delay()
					return true
				return false
			KEY_S:
				# 首次阅读且不可跳过时禁止切换模式
				if _is_first_read and not _skippable:
					return true
				_play_mode = PlayMode.MANUAL if _play_mode == PlayMode.AUTO else PlayMode.AUTO
				_update_nav()
				return true
			KEY_F:
				# 首次阅读且不可跳过时禁止快进
				if _is_first_read and not _skippable:
					return true
				_show_all_remaining()
				return true
			KEY_UP:
				_scroll_content(-60)
				return true
			KEY_DOWN:
				_scroll_content(60)
				return true
			KEY_PAGEUP:
				_scroll_content(-300)
				return true
			KEY_PAGEDOWN:
				_scroll_content(300)
				return true
			KEY_HOME:
				content_rtl.scroll_to_line(0)
				return true
			KEY_END:
				content_rtl.scroll_to_line(content_rtl.get_line_count() - 1)
				return true
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_scroll_content(-60)
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_content(60)
				return true
	return false

func _scroll_content(amount: int) -> void:
	if content_rtl == null or not is_instance_valid(content_rtl):
		return
	var v_scroll: VScrollBar = content_rtl.get_v_scroll_bar()
	if v_scroll:
		v_scroll.value += amount


# ============================================================
# 解析头文件中的聊天选项
# ============================================================
func _parse_chat_options(header: Dictionary) -> void:
	# chat_mode: auto / manual
	var mode_str: String = str(header.get("chat_mode", "auto")).strip_edges().to_lower()
	if mode_str == "manual":
		_default_mode = PlayMode.MANUAL
	else:
		_default_mode = PlayMode.AUTO

	# chat_delay: 消息间隔（毫秒）
	var delay_str: String = str(header.get("chat_delay", "800")).strip_edges()
	_auto_delay = max(0.1, float(delay_str.to_int()) / 1000.0)

	# chat_skippable: 首次阅读是否可跳过
	var skip_str: String = str(header.get("chat_skippable", "true")).strip_edges().to_lower()
	_skippable = skip_str != "false" and skip_str != "0" and skip_str != "no"


# ============================================================
# 解析参与者
# ============================================================
func _parse_participants(header: Dictionary) -> void:
	_participants.clear()
	var participants_str: String = str(header.get("participants", ""))
	var color_idx: int = 0
	if not participants_str.is_empty():
		for raw_id in participants_str.split(","):
			var pid: String = raw_id.strip_edges()
			if pid.is_empty():
				continue
			if pid.to_upper() == "SYSTEM":
				_participants[pid] = {"name": "SYSTEM", "color": SYSTEM_COLOR, "avatar": "", "role": "system", "id": ""}
			else:
				_participants[pid] = {"name": pid, "color": SPEAKER_COLORS[color_idx % SPEAKER_COLORS.size()], "avatar": "", "role": "", "id": ""}
				color_idx += 1
	if not _participants.has("SYSTEM"):
		_participants["SYSTEM"] = {"name": "SYSTEM", "color": SYSTEM_COLOR, "avatar": "", "role": "system", "id": ""}

# ============================================================
# 解析 body
# ============================================================
func _parse_messages(body: String) -> void:
	_messages.clear()
	var lines: PackedStringArray = body.split("\n")
	var in_pblock: bool = false
	var message_lines: Array[String] = []

	for line in lines:
		var stripped: String = line.strip_edges()
		var upper: String = stripped.to_upper().replace(" ", "")
		if upper.begins_with("----PARTICIPANTS") and not upper.contains("END"):
			in_pblock = true
			continue
		if upper.begins_with("----END_PARTICIPANTS") or upper.begins_with("----ENDPARTICIPANTS"):
			in_pblock = false
			continue
		if in_pblock:
			_parse_participant_definition(stripped)
			continue
		message_lines.append(line)

	_parse_message_lines(message_lines)

func _parse_participant_definition(line: String) -> void:
	if not line.begins_with("@"):
		return
	var colon_pos: int = line.find(":")
	if colon_pos <= 1:
		return
	var pid: String = line.substr(1, colon_pos - 1).strip_edges()
	var props_str: String = line.substr(colon_pos + 1).strip_edges()

	if not _participants.has(pid):
		var idx: int = _participants.size()
		_participants[pid] = {
			"name": pid,
			"color": SPEAKER_COLORS[idx % SPEAKER_COLORS.size()] if pid.to_upper() != "SYSTEM" else SYSTEM_COLOR,
			"avatar": "", "role": "system" if pid.to_upper() == "SYSTEM" else "", "id": "",
		}

	for prop in props_str.split(","):
		var eq_pos: int = prop.find("=")
		if eq_pos <= 0:
			continue
		var key: String = prop.substr(0, eq_pos).strip_edges().to_lower()
		var value: String = prop.substr(eq_pos + 1).strip_edges()
		match key:
			"name", "名称":
				_participants[pid]["name"] = value
			"avatar", "头像":
				_participants[pid]["avatar"] = value
			"role", "角色", "职务":
				_participants[pid]["role"] = value
			"color", "颜色":
				_participants[pid]["color"] = value
			"id", "工号":
				_participants[pid]["id"] = value
			_:
				_participants[pid][key] = value

func _parse_message_lines(lines: Array[String]) -> void:
	var current_msg: Dictionary = {}
	var msg_regex := RegEx.new()
	msg_regex.compile("^@(\\S+?)\\s*\\[([^\\]]+)\\]\\s*(?:\\{typing\\s+delay\\s*=\\s*(\\d+)\\})?\\s*:\\s*(.*)")

	for line in lines:
		var stripped: String = line.strip_edges()
		if stripped.is_empty():
			if not current_msg.is_empty():
				_finalize_message(current_msg)
				current_msg = {}
			continue

		var result: RegExMatch = msg_regex.search(stripped)
		if result:
			if not current_msg.is_empty():
				_finalize_message(current_msg)
			var sender: String = result.get_string(1)
			var typing_delay: int = result.get_string(3).to_int() if not result.get_string(3).is_empty() else 0
			_ensure_participant(sender)
			current_msg = {
				"type": "system" if sender.to_upper() == "SYSTEM" else "msg",
				"sender": sender,
				"time": result.get_string(2),
				"content": result.get_string(4),
				"typing_delay": typing_delay,
			}
		else:
			if stripped.begins_with("!["):
				if not current_msg.is_empty():
					_finalize_message(current_msg)
					current_msg = {}
				var parsed_media: String = stripped
				if main.crtml != null:
					parsed_media = main.crtml.parse(stripped)
				_messages.append({"type": "media", "sender": "", "time": "", "content": stripped, "typing_delay": 0, "parsed_bbcode": parsed_media})
			elif not current_msg.is_empty():
				current_msg["content"] = str(current_msg["content"]) + "\n" + line

	if not current_msg.is_empty():
		_finalize_message(current_msg)

func _finalize_message(msg: Dictionary) -> void:
	var raw: String = str(msg.get("content", ""))
	var parsed: String = raw
	if main.crtml != null:
		parsed = main.crtml.parse(raw)
	parsed = _replace_username(parsed)
	msg["parsed_bbcode"] = parsed
	_messages.append(msg)

func _ensure_participant(pid: String) -> void:
	if _participants.has(pid):
		return
	var idx: int = _participants.size()
	_participants[pid] = {
		"name": pid,
		"color": SPEAKER_COLORS[idx % SPEAKER_COLORS.size()] if pid.to_upper() != "SYSTEM" else SYSTEM_COLOR,
		"avatar": "", "role": "system" if pid.to_upper() == "SYSTEM" else "", "id": "",
	}

# ============================================================
# 渲染聊天头部
# ============================================================
func _render_chat_header() -> void:
	var p: String = T.primary_hex if T else "#A0FFA0"
	var m: String = T.muted_hex if T else "#888888"

	content_rtl.append_text("[color=" + p + "]" + "=".repeat(50) + "[/color]\n")
	content_rtl.append_text("[color=" + p + "][b]  # " + _replace_username(viewer_title) + "[/b][/color]\n")

	var parts: Array[String] = []
	for pid in _participants:
		var info: Dictionary = _participants[pid]
		var name: String = _replace_username(str(info.get("name", pid)))
		var color: String = str(info.get("color", m))
		var role: String = str(info.get("role", ""))
		var display: String = "[color=" + color + "]" + name + "[/color]"
		if not role.is_empty() and role != "system":
			display += "[color=" + m + "](" + role + ")[/color]"
		parts.append(display)
	content_rtl.append_text("[color=" + m + "]  Participants: " + ", ".join(parts) + "[/color]\n")
	content_rtl.append_text("[color=" + p + "]" + "=".repeat(50) + "[/color]\n\n")

# ============================================================
# 播放
# ============================================================
func _process_playback(delta: float) -> void:
	if not is_active or _all_displayed:
		return

	# 打字指示器动画（无论模式都要更新动画）
	if _is_typing_indicator:
		_typing_anim_timer += delta
		if _typing_anim_timer >= 0.4:
			_typing_anim_timer = 0.0
			_typing_anim_dots = (_typing_anim_dots % 3) + 1
			_update_typing_indicator()

		_typing_delay_remaining -= delta
		if _typing_delay_remaining <= 0:
			_is_typing_indicator = false
			typing_label.visible = false
			_display_current_message()
			_advance_to_next()
		return

	if _play_mode == PlayMode.MANUAL:
		return

	_msg_delay_remaining -= delta
	if _msg_delay_remaining <= 0:
		_try_display_next()


func _try_display_next() -> void:
	if _msg_index >= _messages.size():
		_all_displayed = true
		_update_nav()
		return

	# 时间间隔分隔线
	_insert_time_separator()

	var msg: Dictionary = _messages[_msg_index]
	var typing_delay: int = int(msg.get("typing_delay", 0))
	if typing_delay > 0:
		_is_typing_indicator = true
		_typing_delay_remaining = float(typing_delay) / 1000.0
		_typing_anim_timer = 0.0
		_typing_anim_dots = 1
		_typing_sender = str(msg.get("sender", ""))
		_update_typing_indicator()
		typing_label.visible = true
	else:
		_display_current_message()
		_advance_to_next()

func _update_typing_indicator() -> void:
	var si: Dictionary = _participants.get(_typing_sender, {})
	var sn: String = _replace_username(str(si.get("name", _typing_sender)))
	var sc: String = str(si.get("color", SYSTEM_COLOR))
	var dots: String = ".".repeat(_typing_anim_dots)
	typing_label.text = ""
	typing_label.append_text("  [color=" + sc + "]" + sn + " is typing" + dots + "[/color]")

func _insert_time_separator() -> void:
	if _msg_index <= 0 or _last_time.is_empty():
		return
	var msg: Dictionary = _messages[_msg_index]
	var cur_time: String = str(msg.get("time", ""))
	if cur_time.is_empty() or _last_time.is_empty():
		return
	# 简单比较 HH:MM 格式时间差
	var last_minutes: int = _time_to_minutes(_last_time)
	var cur_minutes: int = _time_to_minutes(cur_time)
	if last_minutes < 0 or cur_minutes < 0:
		return
	var diff: int = cur_minutes - last_minutes
	if diff >= 10:
		var m: String = T.muted_hex if T else "#888888"
		var label: String = str(diff) + " minutes later"
		if diff >= 60:
			@warning_ignore("integer_division")
			var hours: int = diff / 60
			var mins: int = diff % 60
			if mins > 0:
				label = str(hours) + "h " + str(mins) + "min later"
			else:
				label = str(hours) + " hour(s) later"
		content_rtl.append_text("[color=" + m + "]        --- " + label + " ---[/color]\n\n")

func _time_to_minutes(t: String) -> int:
	# 解析 "HH:MM" 或 "HH:MM:SS" 格式
	var parts: PackedStringArray = t.strip_edges().split(":")
	if parts.size() < 2:
		return -1
	var h: int = parts[0].to_int()
	var m_val: int = parts[1].to_int()
	return h * 60 + m_val

func _display_current_message() -> void:
	if _msg_index >= _messages.size():
		return
	_render_message(_messages[_msg_index])
	_update_nav()

func _advance_to_next() -> void:
	_msg_index += 1
	if _msg_index >= _messages.size():
		_all_displayed = true
		_update_nav()
	else:
		# 自然节奏：基础延迟 + 随机抖动 + 根据下条消息长度微调
		var jitter: float = randf_range(-0.2, 0.4)
		var next_msg: Dictionary = _messages[_msg_index]
		var next_type: String = str(next_msg.get("type", "msg"))
		var next_content: String = str(next_msg.get("content", ""))
		var next_sender: String = str(next_msg.get("sender", ""))

		var delay: float = _auto_delay + jitter

		# 系统消息弹出快一些
		if next_type == "system":
			delay = delay * 0.4

		# 同一人连续发言间隔短
		if next_sender == _last_sender and not _last_sender.is_empty():
			delay = delay * 0.5

		# 长消息前多停顿一下（模拟阅读上一条）
		if next_content.length() > 80:
			delay += 0.3

		_msg_delay_remaining = max(0.15, delay)

func _skip_current_delay() -> void:
	if _is_typing_indicator:
		_is_typing_indicator = false
		typing_label.visible = false
		_display_current_message()
		_advance_to_next()
	elif _msg_index < _messages.size():
		_display_current_message()
		_advance_to_next()
	if _play_mode == PlayMode.MANUAL:
		_msg_delay_remaining = 999999.0

func _show_all_remaining() -> void:
	typing_label.visible = false
	_is_typing_indicator = false
	while _msg_index < _messages.size():
		_render_message(_messages[_msg_index])
		_msg_index += 1
	_all_displayed = true
	_update_nav()

# ============================================================
# 渲染单条消息
# ============================================================
func _render_message(msg: Dictionary) -> void:
	var msg_type: String = str(msg.get("type", "msg"))
	var sender: String = str(msg.get("sender", ""))
	var time_str: String = str(msg.get("time", ""))
	var parsed: String = str(msg.get("parsed_bbcode", str(msg.get("content", ""))))
	match msg_type:
		"system":
			_render_system_message(time_str, parsed)
		"media":
			_render_media_message(parsed)
		_:
			_render_user_message(sender, time_str, parsed)

func _render_system_message(time_str: String, content: String) -> void:
	# 系统消息打断连续消息合并
	_last_sender = ""
	_last_time = time_str

	var m: String = SYSTEM_COLOR
	var line: String = "[color=" + m + "]"
	if not time_str.is_empty():
		line += "  [" + time_str + "] "
	line += "--- " + content + " ---"
	line += "[/color]\n"
	content_rtl.append_text(line)

func _render_media_message(content: String) -> void:
	content_rtl.append_text("  " + content + "\n")


func _render_user_message(sender: String, time_str: String, content: String) -> void:
	var m: String = T.muted_hex if T else "#888888"
	var info: Dictionary = _participants.get(sender, {})
	var sender_name: String = _replace_username(str(info.get("name", sender)))
	var sender_color: String = str(info.get("color", "#AAAAAA"))
	var sender_role: String = str(info.get("role", ""))
	var sender_avatar_path: String = str(info.get("avatar", ""))
	var sender_id: String = str(info.get("id", ""))

	# 判断是否和上一条是同一发送者的连续消息（时间差<2分钟）
	var is_continuation: bool = false
	if sender == _last_sender and not _last_sender.is_empty():
		var last_m: int = _time_to_minutes(_last_time)
		var cur_m: int = _time_to_minutes(time_str)
		if last_m >= 0 and cur_m >= 0 and (cur_m - last_m) < 2:
			is_continuation = true

	# 更新追踪
	_last_sender = sender
	_last_time = time_str

	if is_continuation:
		# 连续消息：不重复头像和用户名，只显示时间和内容
		var indent: String = "    " if not sender_avatar_path.is_empty() else "  "
		if not time_str.is_empty():
			content_rtl.append_text(indent + "[color=" + m + "]" + time_str + "[/color]\n")
		for cline in content.split("\n"):
			content_rtl.append_text(indent + cline + "\n")
		content_rtl.append_text("\n")
	else:
		# 完整消息：头像 + 用户名 + 角色 + 时间
		var avatar_tex: ImageTexture = _get_avatar(sender_avatar_path)
		if avatar_tex != null:
			content_rtl.add_image(avatar_tex, AVATAR_SIZE, AVATAR_SIZE)
			content_rtl.append_text(" ")

		content_rtl.append_text("[color=" + sender_color + "][b]" + sender_name + "[/b][/color]")
		if not sender_role.is_empty() and sender_role != "system":
			content_rtl.append_text(" [color=" + m + "][" + sender_role + "][/color]")
		if not sender_id.is_empty():
			content_rtl.append_text(" [color=" + m + "](" + sender_id + ")[/color]")
		if not time_str.is_empty():
			content_rtl.append_text("  [color=" + m + "]" + time_str + "[/color]")
		content_rtl.append_text("\n")

		var indent: String = "    " if avatar_tex != null else "  "
		for cline in content.split("\n"):
			content_rtl.append_text(indent + cline + "\n")
		content_rtl.append_text("\n")

# ============================================================
# 头像
# ============================================================
func _get_avatar(avatar_path: String) -> ImageTexture:
	if avatar_path.is_empty():
		return null
	if _avatar_cache.has(avatar_path):
		return _avatar_cache[avatar_path]
	if fs == null:
		_avatar_cache[avatar_path] = null
		return null

	var normalized: String = fs.normalize_path(avatar_path)
	var data: PackedByteArray = fs.get_binary_data(normalized)
	if data.is_empty():
		_avatar_cache[avatar_path] = null
		return null

	var image := Image.new()
	var err: Error = ERR_FILE_UNRECOGNIZED
	match avatar_path.get_extension().to_lower():
		"png": err = image.load_png_from_buffer(data)
		"jpg", "jpeg": err = image.load_jpg_from_buffer(data)
		"bmp": err = image.load_bmp_from_buffer(data)
		"webp": err = image.load_webp_from_buffer(data)
	if err != OK:
		_avatar_cache[avatar_path] = null
		return null

	image.resize(AVATAR_SIZE, AVATAR_SIZE, Image.INTERPOLATE_LANCZOS)
	var texture := ImageTexture.create_from_image(image)
	_avatar_cache[avatar_path] = texture
	return texture

# ============================================================
# 工具
# ============================================================
func _replace_username(text: String) -> String:
	if main.user_mgr != null and main.user_mgr.is_logged_in:
		return text.replace("{username}", main.user_mgr.get_username())
	return text

func _update_nav() -> void:
	if nav_label == null:
		return
	nav_label.text = ""
	var p: String = T.primary_hex if T != null else "#A0FFA0"
	var m: String = T.muted_hex if T != null else "#888888"
	var total: int = _messages.size()
	var current: int = total if _all_displayed else mini(_msg_index + 1, total)
	var mode_str: String = "AUTO" if _play_mode == PlayMode.AUTO else "MANUAL"
	var parts: Array[String] = []
	parts.append("[color=" + p + "]" + str(current) + "/" + str(total) + "[/color]")
	parts.append("[color=" + m + "][" + mode_str + "][/color]")
	if _all_displayed:
		parts.append("[color=" + m + "]-- END --[/color]")
	elif _is_first_read and not _skippable:
		parts.append("[color=" + m + "]Space=next[/color]")
	else:
		parts.append("[color=" + m + "]Space=next  S=mode  F=skip all[/color]")
	parts.append("[color=" + m + "][Q/Esc 退出][/color]")
	nav_label.append_text("  ".join(parts))

func get_active_page_rtl() -> RichTextLabel:
	if is_active and content_rtl != null and is_instance_valid(content_rtl):
		return content_rtl
	return null
