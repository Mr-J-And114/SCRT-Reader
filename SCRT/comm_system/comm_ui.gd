# ============================================================
# comm_ui.gd — 通讯系统 UI 层
# ── 底部对话栏 + 角色立绘卡片 + COMM 按钮
# ── 历史记录：持久化到磁盘，通过 DocumentViewer 全屏查看
# ── 使用裁剪容器实现输入框上沿消失线
# ============================================================
class_name CommUI
extends RefCounted

# ── 引用 ──
var _main: Control = null
var _T: Variant = null

# ── 节点 ──
var _root: Control = null          # 裁剪容器，底部 = 输入框上沿（消失线）
var _dialog_bar: PanelContainer = null
var _toggle_btn: Button = null

# ── 对话栏内部 ──
var _name_label: RichTextLabel = null
var _text_label: RichTextLabel = null
var _text_scroll: ScrollContainer = null
var _continue_label: Label = null
var _wait_label: RichTextLabel = null
var _history_btn: Button = null

# ── 状态 ──
var is_visible: bool = false
var _collapsed: bool = true
var _auto_collapsed: bool = false
var _built: bool = false

# ── 立绘 ──
var _portrait_cards: Dictionary = {}
var _current_character: CommCharacter = null

# ── 动画 ──
var _blink_timer: float = 0.0
var _slide_tween: Tween = null
var _mouth_timer: float = 0.0

# ── 历史数据（内存 + 持久化） ──
var _history_lines: Array[Dictionary] = []
var _current_dialogue_id: String = ""

# ── 常量 ──
const DIALOG_BAR_HEIGHT_MIN: float = 100.0      # 最小高度
const DIALOG_BAR_HEIGHT_MAX: float = 300.0     # 最大高度（约屏幕1/3）
var _current_bar_height: float = 100.0           # 当前实际高度
const TOGGLE_BTN_SIZE: float = 24.0
const TOGGLE_BTN_GAP: float = 6.0    # 按钮与对话栏之间的间距
const SLIDE_DURATION: float = 0.3
const CARD_SIZE: Vector2 = Vector2(150, 210)  # 250:350 一寸照比例
const CARD_MARGIN_BOTTOM: float = 4.0
const CARD_OVERLAP: float = 24.0			  # 同位置多卡片叠放偏移量
const PORTRAIT_OFFSET_X: float = 12.0
const PADDING: float = 12.0

# 动态计算的目标 Y（相对于 _root 内部坐标）
var _target_y_expanded: float = 0.0
var _target_y_collapsed: float = 800.0


# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(main: Control, theme) -> void:
	_main = main
	_T = theme


# ══════════════════════════════════════════
#  构建 UI
# ══════════════════════════════════════════
func _build_ui() -> void:
	if _built:
		return
	if _main == null:
		return
	_built = true

	# ═══ 0. 裁剪根容器 ═══
	# _root 的底部边界 = 输入框上沿 = 消失线
	# 开启 clip_children 使对话栏滑出底部时被裁剪
	_root = Control.new()
	_root.name = "CommUIRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_root.z_index = 10
	_main.add_child(_root)

	# ═══ 1. 对话栏主体 ═══
	_dialog_bar = PanelContainer.new()
	_dialog_bar.name = "CommDialogBar"
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.02, 0.02, 0.02, 0.95)
	bar_style.border_color = _T.primary.darkened(0.4) if _T else Color(0.0, 0.4, 0.0, 0.4)
	bar_style.border_width_top = 1
	bar_style.border_width_bottom = 0
	bar_style.border_width_left = 0
	bar_style.border_width_right = 0
	bar_style.content_margin_left = PADDING
	bar_style.content_margin_right = PADDING
	bar_style.content_margin_right = PADDING
	bar_style.content_margin_top = 6
	bar_style.content_margin_bottom = 6
	_dialog_bar.add_theme_stylebox_override("panel", bar_style)
	_dialog_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(_dialog_bar)

	# 内部布局
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog_bar.add_child(vbox)

	# 顶部行：角色名 + 历史按钮
	var top_row := HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top_row)

	_name_label = RichTextLabel.new()
	_name_label.bbcode_enabled = true
	_name_label.fit_content = true
	_name_label.scroll_active = false
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.custom_minimum_size.y = 20
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.add_theme_font_size_override("normal_font_size", 12)
	_name_label.add_theme_font_size_override("bold_font_size", 13)
	if _T:
		_name_label.add_theme_color_override("default_color", _T.primary)
	top_row.add_child(_name_label)

	# History 按钮（对话栏内）
	_history_btn = Button.new()
	_history_btn.text = "[History]"
	_history_btn.flat = true
	_history_btn.custom_minimum_size = Vector2(64, 20)
	_history_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_history_btn.add_theme_font_size_override("font_size", 11)
	if _T:
		_history_btn.add_theme_color_override("font_color", _T.muted)
		_history_btn.add_theme_color_override("font_hover_color", _T.primary)
		_history_btn.add_theme_color_override("font_pressed_color", _T.primary)
	var empty_style := StyleBoxEmpty.new()
	_history_btn.add_theme_stylebox_override("normal", empty_style)
	_history_btn.add_theme_stylebox_override("hover", empty_style)
	_history_btn.add_theme_stylebox_override("pressed", empty_style)
	_history_btn.add_theme_stylebox_override("focus", empty_style)
	_history_btn.pressed.connect(_on_history_btn_pressed)
	top_row.add_child(_history_btn)

# 对话文本区域（★ 不使用 ScrollContainer，改为自动变高）
	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.scroll_active = false
	_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_label.add_theme_font_size_override("normal_font_size", 13)
	if _T:
		_text_label.add_theme_color_override("default_color", Color.WHITE)
	vbox.add_child(_text_label)

	# 继续提示
	_continue_label = Label.new()
	_continue_label.text = "▶ CONTINUE"
	_continue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_continue_label.add_theme_font_size_override("font_size", 10)
	if _T:
		_continue_label.add_theme_color_override("font_color", _T.muted)
	_continue_label.visible = false
	_continue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_continue_label)

	# 等待提示
	_wait_label = RichTextLabel.new()
	_wait_label.bbcode_enabled = true
	_wait_label.fit_content = true
	_wait_label.scroll_active = false
	_wait_label.add_theme_font_size_override("normal_font_size", 10)
	if _T:
		_wait_label.add_theme_color_override("default_color", _T.warning)
	_wait_label.visible = false
	_wait_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_wait_label)

	# ═══ 2. COMM 按钮（也在 _root 裁剪容器内） ═══
	_toggle_btn = Button.new()
	_toggle_btn.name = "CommToggleBtn"
	_toggle_btn.text = "▲ COMM"
	_toggle_btn.custom_minimum_size = Vector2(90, TOGGLE_BTN_SIZE)
	_toggle_btn.size = Vector2(90, TOGGLE_BTN_SIZE)
	_toggle_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.02, 0.02, 0.02, 0.92)
	btn_style.border_color = _T.primary.darkened(0.3) if _T else Color(0.0, 0.5, 0.0, 0.5)
	btn_style.border_width_top = 1
	btn_style.border_width_bottom = 0
	btn_style.border_width_left = 1
	btn_style.border_width_right = 1
	_toggle_btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover := btn_style.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.04, 0.08, 0.04, 0.95)
	btn_hover.border_color = _T.primary if _T else Color(0.0, 0.8, 0.0, 0.7)
	_toggle_btn.add_theme_stylebox_override("hover", btn_hover)
	var btn_pressed := btn_style.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = Color(0.06, 0.12, 0.06, 0.95)
	_toggle_btn.add_theme_stylebox_override("pressed", btn_pressed)
	_toggle_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_toggle_btn.add_theme_font_size_override("font_size", 12)
	if _T:
		_toggle_btn.add_theme_color_override("font_color", _T.primary)
		_toggle_btn.add_theme_color_override("font_hover_color", _T.primary)
		_toggle_btn.add_theme_color_override("font_pressed_color", _T.primary)
	_toggle_btn.pressed.connect(_on_toggle_btn_pressed)
	_toggle_btn.visible = true
	_root.add_child(_toggle_btn)

	# 初始隐藏对话栏
	_dialog_bar.visible = false
	_update_positions()


# ══════════════════════════════════════════
#  历史记录 — 持久化存储
# ══════════════════════════════════════════
func add_history_line(speaker_name: String, text: String) -> void:
	var entry: Dictionary = {
		"name": speaker_name,
		"text": text,
		"time": _get_timestamp(),
		"dialogue_id": _current_dialogue_id,
	}
	_history_lines.append(entry)

func set_current_dialogue_id(dialogue_id: String) -> void:
	_current_dialogue_id = dialogue_id

func flush_history_to_disk() -> void:
	if _history_lines.is_empty():
		return
	_save_history_to_disk(_history_lines)
	_history_lines.clear()

func clear_history() -> void:
	_history_lines.clear()

func _get_history_path() -> String:
	if _main == null:
		return ""
	if _main.user_mgr == null or not _main.user_mgr.is_logged_in:
		return ""
	var username: String = _main.user_mgr.get_username()
	if _main.save_mgr:
		var user_dir: String = _main.save_mgr.get_game_root_dir() + "saves/" + username
		if not DirAccess.dir_exists_absolute(user_dir):
			DirAccess.make_dir_recursive_absolute(user_dir)
		return user_dir + "/comm_history.json"
	return ""

func _save_history_to_disk(new_lines: Array[Dictionary]) -> void:
	var path: String = _get_history_path()
	if path.is_empty():
		return
	var existing: Array[Dictionary] = _load_history_from_disk()
	for line in new_lines:
		existing.append(line)
	while existing.size() > 500:
		existing.pop_front()
	var save_array: Array = []
	for entry in existing:
		save_array.append(entry)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_array, "\t"))
		file.close()

func _load_history_from_disk() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var path: String = _get_history_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return result
	file.close()
	if not (json.data is Array):
		return result
	for item in json.data:
		if item is Dictionary:
			result.append(item as Dictionary)
	return result

func _get_timestamp() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		dt["year"], dt["month"], dt["day"],
		dt["hour"], dt["minute"], dt["second"]
	]


# ══════════════════════════════════════════
#  History 按钮回调
# ══════════════════════════════════════════
func _on_history_btn_pressed() -> void:
	if _main == null:
		return
	# ★ 打开 History 前自动收起对话框和立绘
	auto_collapse()
	var all_lines: Array[Dictionary] = _load_history_from_disk()
	for line in _history_lines:
		all_lines.append(line)
	var content: String = _build_history_page(all_lines)
	if _main.doc_viewer != null:
		var title_str: String = "COMM HISTORY (" + str(all_lines.size()) + " records)"
		var pages: Array[Dictionary] = [{"content": content}]
		# ★ 传入关闭回调：通讯仍在进行时自动展开
		_main.doc_viewer.open("comm_history", pages, title_str, _on_history_viewer_closed)
	else:
		_main.append_output("\n" + content + "\n", false)

func _on_history_viewer_closed() -> void:
	if _main and _main.comm_mgr and _main.comm_mgr.is_active:
		auto_expand()

func _build_history_page(lines: Array[Dictionary]) -> String:
	var p: String = _T.primary_hex if _T else "#00ff00"
	var m: String = _T.muted_hex if _T else "#888888"
	var w: String = _T.warning_hex if _T else "#ffaa00"
	var divider: String = "========================================================"
	var parts: Array[String] = []
	parts.append("[color=" + p + "]" + divider + "[/color]")
	parts.append("[color=" + p + "][b]  COMMUNICATION HISTORY[/b][/color]")
	parts.append("[color=" + p + "]" + divider + "[/color]")
	parts.append("")
	if lines.is_empty():
		parts.append("[color=" + m + "]  (No communication records)[/color]")
	else:
		var current_dlg: String = ""
		for entry in lines:
			var dlg_id: String = str(entry.get("dialogue_id", ""))
			if dlg_id != current_dlg and not dlg_id.is_empty():
				current_dlg = dlg_id
				parts.append("")
				parts.append("[color=" + w + "]── " + dlg_id + " ──[/color]")
				parts.append("")
			var speaker: String = str(entry.get("name", "???"))
			var text: String = str(entry.get("text", ""))
			var time_str: String = str(entry.get("time", ""))
			var short_time: String = ""
			if time_str.length() >= 19:
				short_time = time_str.substr(11, 8)
			elif not time_str.is_empty():
				short_time = time_str
			var time_tag: String = ""
			if not short_time.is_empty():
				time_tag = "[color=" + m + "][" + short_time + "][/color] "
			parts.append(time_tag + "[color=" + p + "][b]" + speaker + ":[/b][/color] " + text)
	parts.append("")
	parts.append("[color=" + p + "]" + divider + "[/color]")
	parts.append("")
	parts.append("[color=" + m + "]  Total: " + str(lines.size()) + " records  |  Q/Esc to close[/color]")
	return "\n".join(parts)


# ══════════════════════════════════════════
#  显示 / 隐藏
# ══════════════════════════════════════════
func show() -> void:
	_build_ui()
	is_visible = true
	_collapsed = false
	_auto_collapsed = false
	_root.visible = true
	_dialog_bar.visible = true
	if _toggle_btn:
		_toggle_btn.visible = true
		_toggle_btn.text = "▼ COMM"
	if _main:
		(func():
			_update_positions()
			if _dialog_bar and is_instance_valid(_dialog_bar):
				# ★ 只在对话栏不在展开位置时才从底部弹出
				var dist: float = absf(_dialog_bar.position.y - _target_y_expanded)
				if dist > 2.0:
					_dialog_bar.position.y = _target_y_collapsed
					_slide_to_expanded()
				else:
					_dialog_bar.position.y = _target_y_expanded
					_sync_btn_to_bar()
					_update_card_layout()
		).call_deferred()

func hide() -> void:
	_collapsed = true
	_auto_collapsed = false
	is_visible = false
	if _dialog_bar:
		_dialog_bar.visible = false
	if _toggle_btn:
		_toggle_btn.visible = true
		_toggle_btn.text = "▲ COMM"
	_sync_btn_to_bar()


# ══════════════════════════════════════════
#  收起/展开
# ══════════════════════════════════════════
func auto_collapse() -> void:
	if _collapsed:
		return
	_collapsed = true
	_auto_collapsed = true
	_slide_to_collapsed()
	if _toggle_btn:
		_toggle_btn.text = "▲ COMM"

func auto_expand() -> void:
	if not _collapsed:
		return
	_collapsed = false
	_auto_collapsed = false
	is_visible = true
	_dialog_bar.visible = true
	_slide_to_expanded()
	if _toggle_btn:
		_toggle_btn.text = "▼ COMM"


func _on_toggle_btn_pressed() -> void:
	if _collapsed:
		_collapsed = false
		_auto_collapsed = false
		is_visible = true
		_dialog_bar.visible = true
		_slide_to_expanded()
		_toggle_btn.text = "▼ COMM"
	else:
		_collapsed = true
		_auto_collapsed = false
		_slide_to_collapsed()
		_toggle_btn.text = "▲ COMM"
	if _main and _main.input_field:
		_main.input_field.grab_focus()


func _slide_to_collapsed() -> void:
	if _slide_tween:
		_slide_tween.kill()
	if _toggle_btn:
		_toggle_btn.text = "▲ COMM"
	_slide_tween = _main.create_tween().set_parallel(true)
	# ★ 对话栏和按钮一起滑动
	_slide_tween.tween_property(_dialog_bar, "position:y", _target_y_collapsed, SLIDE_DURATION)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	if _toggle_btn:
		var btn_target_y: float = _target_y_collapsed - TOGGLE_BTN_SIZE - TOGGLE_BTN_GAP
		_slide_tween.tween_property(_toggle_btn, "position:y", btn_target_y, SLIDE_DURATION)\
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# ★ 立绘淡出
	for cid in _portrait_cards.keys():
		var card_data: Dictionary = _portrait_cards[cid]
		var card: Control = card_data["card"]
		if is_instance_valid(card):
			_slide_tween.tween_property(card, "modulate:a", 0.0, SLIDE_DURATION * 0.5)
	# 动画完毕后隐藏
	_slide_tween.chain().tween_callback(func():
		_dialog_bar.visible = false
		_sync_btn_to_bar()
	)

func _slide_to_expanded() -> void:
	if _slide_tween:
		_slide_tween.kill()
	if _toggle_btn:
		_toggle_btn.text = "▼ COMM"
	_dialog_bar.visible = true

	# ★ 只在对话栏不在展开位置附近时才做动画
	var current_y: float = _dialog_bar.position.y
	var dist: float = absf(current_y - _target_y_expanded)
	if dist < 2.0:
		# 已经在目标位置，直接定位，不做动画
		_dialog_bar.position.y = _target_y_expanded
		_sync_btn_to_bar()
		_update_card_layout()
		return

	# ★ 不强制从底部开始，从当前位置滑到目标位置
	_update_card_layout()

	if _toggle_btn:
		_toggle_btn.position.y = current_y - TOGGLE_BTN_SIZE - TOGGLE_BTN_GAP

	_slide_tween = _main.create_tween().set_parallel(true)
	_slide_tween.tween_property(_dialog_bar, "position:y", _target_y_expanded, SLIDE_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	if _toggle_btn:
		var btn_target_y: float = _target_y_expanded - TOGGLE_BTN_SIZE - TOGGLE_BTN_GAP
		_slide_tween.tween_property(_toggle_btn, "position:y", btn_target_y, SLIDE_DURATION)\
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_slide_tween.chain().tween_callback(func():
		_sync_btn_to_bar()
	)

# ══════════════════════════════════════════
#  角色 / 文本更新
# ══════════════════════════════════════════
func set_character(character: CommCharacter) -> void:
	_current_character = character
	if _name_label and character:
		var nc: Color = character.name_color if character.name_color != Color.WHITE else Color.WHITE
		var color_hex: String = "#" + nc.to_html(false) if nc != Color.WHITE else (_T.primary_hex if _T else "#00ff00")
		_name_label.text = "[b][color=" + color_hex + "]" + character.display_name + "[/color][/b]"
		if not character.title.is_empty():
			var m_hex: String = _T.muted_hex if _T else "#888888"
			_name_label.text += "  [color=" + m_hex + "]" + character.title + "[/color]"
	_ensure_portrait_card(character)


func update_text(text: String) -> void:
	if _text_label:
		_text_label.clear()
		_text_label.append_text(text)
		# ★ 延迟一帧后根据文本内容调整对话栏高度
		(func(): _adjust_bar_height()).call_deferred()


func _adjust_bar_height() -> void:
	if _text_label == null or _dialog_bar == null:
		return
	# 文本实际高度 + 名称行(~22) + 提示行(~18) + 内边距(~24)
	var text_h: float = _text_label.get_content_height()
	var overhead: float = 64.0  # name_label + continue/wait + padding
	var desired: float = clampf(text_h + overhead, DIALOG_BAR_HEIGHT_MIN, DIALOG_BAR_HEIGHT_MAX)
	if absf(desired - _current_bar_height) < 2.0:
		return  # 变化太小，不更新
	_current_bar_height = desired
	_update_positions()
	_update_card_layout()

func show_continue_prompt(show_it: bool) -> void:
	if _continue_label:
		_continue_label.visible = show_it
	if show_it and _wait_label:
		_wait_label.visible = false

func hide_wait_prompt() -> void:
	if _wait_label:
		_wait_label.visible = false

func show_wait_prompt(condition: String) -> void:
	if _wait_label == null:
		return
	_wait_label.visible = true
	if _continue_label:
		_continue_label.visible = false
	var m_hex: String = _T.muted_hex if _T else "#888888"
	var w_hex: String = _T.warning_hex if _T else "#ffaa00"
	_wait_label.clear()
	if condition.begins_with("command:"):
		var cmd: String = condition.substr(8)
		_wait_label.append_text("[color=" + w_hex + "]⌨[/color] [color=" + m_hex + "]请在终端输入:[/color] [color=" + w_hex + "]" + cmd + "[/color]")
	elif condition.begins_with("open_file:"):
		var file_path: String = condition.substr(10)
		_wait_label.append_text("[color=" + w_hex + "]📂[/color] [color=" + m_hex + "]请打开文件:[/color] [color=" + w_hex + "]" + file_path + "[/color]")
	elif condition.begins_with("enter_dir:"):
		var dir_path: String = condition.substr(10)
		_wait_label.append_text("[color=" + w_hex + "]📁[/color] [color=" + m_hex + "]请进入目录:[/color] [color=" + w_hex + "]" + dir_path + "[/color]")
	else:
		_wait_label.append_text("[color=" + m_hex + "]等待: " + condition + "[/color]")

func show_wait_prompt_custom(text: String) -> void:
	if _wait_label:
		_wait_label.visible = true
		var w_hex: String = _T.warning_hex if _T else "#ffaa00"
		_wait_label.clear()
		_wait_label.append_text("[color=" + w_hex + "]" + text + "[/color]")
	if _continue_label:
		_continue_label.visible = false

# ══════════════════════════════════════════
#  立绘卡片
# ══════════════════════════════════════════
func _ensure_portrait_card(character: CommCharacter) -> void:
	if character == null or _root == null:
		return
	var cid: String = character.id
	if _portrait_cards.has(cid):
		var card_data: Dictionary = _portrait_cards[cid]
		var card: Control = card_data["card"]
		if is_instance_valid(card):
			card.visible = true
			card.modulate.a = 1.0
			_update_portrait_texture(card_data, character)
			# 将当前说话角色提到最前
			_bring_card_to_front(cid)
			_update_card_layout()
			return
	# 创建新卡片
	var card := PanelContainer.new()
	card.name = "PortraitCard_" + cid
	card.custom_minimum_size = CARD_SIZE
	card.size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.02, 0.02, 0.02, 0.95)
	var name_col: Color = character.name_color if character.name_color != Color.WHITE else (_T.primary if _T else Color.GREEN)
	card_style.border_color = name_col.darkened(0.3)
	card_style.set_border_width_all(1)
	card_style.corner_radius_top_left = 4
	card_style.corner_radius_top_right = 4
	card_style.corner_radius_bottom_left = 0
	card_style.corner_radius_bottom_right = 0
	card.add_theme_stylebox_override("panel", card_style)

	# 头像纹理
	var tex_rect := TextureRect.new()
	tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(tex_rect)

	# 嘴型覆盖层（预留）
	var mouth_rect := TextureRect.new()
	mouth_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	mouth_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouth_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouth_rect.visible = false
	card.add_child(mouth_rect)

	# 角色名标签（卡片底部）
	var name_lbl := Label.new()
	name_lbl.name = "CardNameLabel"
	name_lbl.text = character.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	name_lbl.add_theme_font_size_override("font_size", 9)
	name_lbl.add_theme_color_override("font_color", name_col)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 用锚点定位到卡片底部
	name_lbl.anchors_preset = Control.PRESET_BOTTOM_WIDE
	name_lbl.offset_top = -16
	name_lbl.offset_bottom = -2
	card.add_child(name_lbl)

	_root.add_child(card)

	var position_slot: String = character.portrait_position if not character.portrait_position.is_empty() else "left"

	var card_data: Dictionary = {
		"card": card,
		"texture_rect": tex_rect,
		"mouth_rect": mouth_rect,
		"name_label": name_lbl,
		"character_id": cid,
		"position": position_slot,
	}
	_portrait_cards[cid] = card_data
	_update_portrait_texture(card_data, character)
	_bring_card_to_front(cid)
	_update_card_layout()

func _update_portrait_texture(card_data: Dictionary, character: CommCharacter) -> void:
	var tex_rect: TextureRect = card_data["texture_rect"]
	match character.sprite_mode:
		CommCharacter.SpriteMode.STATIC:
			if character.static_portrait:
				tex_rect.texture = character.static_portrait
		CommCharacter.SpriteMode.LAYERED:
			if character.static_portrait:
				tex_rect.texture = character.static_portrait
		_:
			tex_rect.texture = null

## 将指定角色的卡片提到其位置组的最前面（z_index最高）
func _bring_card_to_front(active_cid: String) -> void:
	if not _portrait_cards.has(active_cid):
		return
	var active_data: Dictionary = _portrait_cards[active_cid]
	var active_pos: String = active_data.get("position", "left")
	# 收集同位置的所有卡片
	var same_pos_ids: Array[String] = []
	for cid in _portrait_cards.keys():
		var data: Dictionary = _portrait_cards[cid]
		if data.get("position", "left") == active_pos:
			same_pos_ids.append(cid)
	# 设置 z_index: 活跃角色最高，其余递减
	var base_z: int = 0
	for cid in same_pos_ids:
		var card: Control = _portrait_cards[cid]["card"]
		if not is_instance_valid(card):
			continue
		if cid == active_cid:
			card.z_index = base_z + same_pos_ids.size()
		else:
			card.z_index = base_z
			base_z += 1

func _update_card_layout() -> void:
	if _dialog_bar == null or _root == null:
		return
	var bar_top_y: float = _dialog_bar.position.y
	var bar_width: float = _root.size.x if _root.size.x > 0 else 800.0

	# 按位置分组
	var groups: Dictionary = {"left": [], "center": [], "right": []}
	for cid in _portrait_cards.keys():
		var card_data: Dictionary = _portrait_cards[cid]
		var card: Control = card_data["card"]
		if not is_instance_valid(card):
			continue
		var pos_slot: String = card_data.get("position", "left")
		if not groups.has(pos_slot):
			pos_slot = "left"
		groups[pos_slot].append(card_data)

	# 计算每组的起始 X
	var group_x: Dictionary = {
		"left": PORTRAIT_OFFSET_X,
		"center": (bar_width - CARD_SIZE.x) / 2.0,
		"right": bar_width - CARD_SIZE.x - PORTRAIT_OFFSET_X,
	}

	# 卡片 Y: 底部对齐对话栏顶部
	var card_y: float = bar_top_y - CARD_SIZE.y + CARD_MARGIN_BOTTOM

	for pos_key in groups.keys():
		var group: Array = groups[pos_key]
		if group.is_empty():
			continue
		var base_x: float = group_x[pos_key]
		# 叠放方向：left 向右叠，right 向左叠，center 居中叠
		for i in range(group.size()):
			var card_data: Dictionary = group[i]
			var card: Control = card_data["card"]
			if not is_instance_valid(card):
				continue
			var offset_x: float = 0.0
			match pos_key:
				"left":
					offset_x = i * CARD_OVERLAP
				"right":
					offset_x = -i * CARD_OVERLAP
				"center":
					offset_x = (i - group.size() / 2.0) * CARD_OVERLAP
			card.position = Vector2(base_x + offset_x, card_y)
			card.visible = not _collapsed
			card.modulate.a = 1.0

func _update_mouth_animations() -> void:
	# 预留：分层模式嘴型动画
	pass

var _characters_speaking: Dictionary = {}

func _get_character_by_id(cid: String) -> CommCharacter:
	if _current_character and _current_character.id == cid:
		return _current_character
	return null

func clear_cards() -> void:
	for cid in _portrait_cards.keys():
		var card_data: Dictionary = _portrait_cards[cid]
		var card: Control = card_data["card"]
		if is_instance_valid(card):
			card.queue_free()
	_portrait_cards.clear()
	_characters_speaking.clear()




# ══════════════════════════════════════════
#  位置计算
# ══════════════════════════════════════════

## 获取输入框上沿相对于 _main 的 Y 坐标
func _get_input_top_y() -> float:
	if _main == null:
		return 600.0
	var input_frame = _main.input_frame
	if input_frame != null and is_instance_valid(input_frame) and input_frame.is_inside_tree():
		# InputFrame 在 MainContent(VBoxContainer) 内，用 global_position 转换
		return input_frame.global_position.y - _main.global_position.y
	return _main.size.y - 40.0

## 更新裁剪容器 _root 的尺寸（底部 = 消失线 = 输入框上沿）
func _update_root_rect() -> void:
	if _root == null or _main == null:
		return
	var input_top_y: float = _get_input_top_y()
	_root.position = Vector2(0, 0)
	_root.size = Vector2(_main.size.x, input_top_y)

func _update_positions() -> void:
	if _dialog_bar == null or _main == null:
		return

	_update_root_rect()

	var bar_width: float = _root.size.x
	var clip_h: float = _root.size.y

	var bar_y: float = clip_h - _current_bar_height    # ★ 用动态高度
	if bar_y < 0:
		bar_y = 0

	_target_y_expanded = bar_y
	_target_y_collapsed = clip_h

	if not _collapsed and (_slide_tween == null or not _slide_tween.is_running()):
		_dialog_bar.position = Vector2(0, bar_y)
	_dialog_bar.size = Vector2(bar_width, _current_bar_height)   # ★ 用动态高度

	_sync_btn_to_bar()

## 同步 COMM 按钮位置到对话栏当前位置
func _sync_btn_to_bar() -> void:
	if _toggle_btn == null or _root == null:
		return

	var bar_width: float = _root.size.x if _root.size.x > 0 else 800.0
	var btn_x: float = bar_width - _toggle_btn.size.x - 12
	var clip_h: float = _root.size.y

	# 对话栏的当前 Y
	var bar_y: float = clip_h  # 默认：消失线
	if _dialog_bar and is_instance_valid(_dialog_bar) and _dialog_bar.visible:
		bar_y = _dialog_bar.position.y
	elif not _collapsed:
		bar_y = _target_y_expanded

	# 按钮在对话栏上方
	var btn_y: float = bar_y - TOGGLE_BTN_SIZE - TOGGLE_BTN_GAP
	_toggle_btn.position = Vector2(btn_x, btn_y)


# ══════════════════════════════════════════
#  每帧更新
# ══════════════════════════════════════════
func process(delta: float) -> void:
	if not _built:
		return

	# 动画中：每帧同步按钮和立绘跟随对话栏
	if _slide_tween and _slide_tween.is_running():
		_sync_btn_to_bar()
		_update_card_layout()
		return

	# 非动画：正常更新
	if _toggle_btn and is_instance_valid(_toggle_btn) and _toggle_btn.visible:
		_sync_btn_to_bar()

	if not is_visible:
		return

	_update_positions()
	if not _collapsed:
		_update_card_layout()
	_update_mouth_animations()

	if _continue_label and _continue_label.visible:
		_blink_timer += delta
		if _blink_timer >= 0.5:
			_blink_timer = 0.0
			_continue_label.modulate.a = 0.3 if _continue_label.modulate.a > 0.5 else 1.0


# ══════════════════════════════════════════
#  清理
# ══════════════════════════════════════════
func cleanup() -> void:
	flush_history_to_disk()
	clear_cards()
	if _slide_tween:
		_slide_tween.kill()
		_slide_tween = null
	if _root and is_instance_valid(_root):
		_root.queue_free()
		_root = null
	_dialog_bar = null
	_toggle_btn = null
	_history_btn = null
	_name_label = null
	_text_label = null
	_continue_label = null
	_wait_label = null
	_collapsed = true
	_built = false
	is_visible = false
