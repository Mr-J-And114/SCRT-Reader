# ============================================================
# comm_ui.gd — 通讯系统 UI 层
# ── 底部对话栏 + 角色立绘卡片 + COMM 按钮
# ── Meeting 模式: galgame 风格大图角色展示
# ── 历史记录：持久化到磁盘，通过 DocumentViewer 全屏查看
# ── 使用裁剪容器实现输入框上沿消失线
# ============================================================
class_name CommUI
extends RefCounted

# ══════════════════════════════════════════
#  ★ 手动微调区 — 修改这些值来调整角色显示
# ══════════════════════════════════════════

## ── 对话栏 ──
const DIALOG_BAR_HEIGHT_MIN: float = 100.0         # 对话栏最小高度 (px)
const DIALOG_BAR_HEIGHT_MAX: float = 300.0         # 对话栏最大高度 (约屏幕 1/3)
const TOGGLE_BTN_SIZE: float = 24.0                # COMM 按钮高度
const TOGGLE_BTN_GAP: float = 6.0                  # 按钮与对话栏间距
const SLIDE_DURATION: float = 0.3                  # 对话栏展开/收起动画时长 (秒)
const PADDING: float = 12.0                        # 对话栏内边距

## ── 小头像卡片 (Card Mode) ──
const CARD_SIZE: Vector2 = Vector2(150, 210)       # ★ 卡片宽高 (px), 250:350 比例
const CARD_MARGIN_BOTTOM: float = 4.0              # ★ 卡片底部与对话栏顶部的间距
const CARD_OVERLAP: float = 24.0                   # ★ 同位置多卡片叠放偏移
const PORTRAIT_OFFSET_X: float = 12.0              # ★ 卡片距屏幕左/右边缘的距离
const CARD_BRIGHTNESS: float = 0.5                 # ★ 卡片亮度 (0.0=全黑, 1.0=原亮度)

## ── 大图模式 (Meeting Mode) ──
const MEETING_CHAR_HEIGHT_RATIO: float = 0.65      # ★ 角色高度占屏幕高度比例 (0.3~0.8)
const MEETING_CHAR_BOTTOM_GAP: float = 0.0         # ★ 角色底部与对话栏顶部间距 (px)
const MEETING_POS_LEFT_X: float = 0.15             # ★ 左侧位置: 角色中心 X (屏幕宽度比例)
const MEETING_POS_CENTER_X: float = 0.5            # ★ 中间位置
const MEETING_POS_RIGHT_X: float = 0.85            # ★ 右侧位置
const MEETING_BRIGHTNESS: float = 0.5             # ★ 大图亮度 (0.0=全黑, 1.0=原亮度)
const MEETING_SLIDE_DURATION: float = 0.4          # ★ 入场/退场动画时长 (秒)
const MEETING_SHAKE_INTENSITY: float = 8.0         # ★ 震动幅度 (px)
const MEETING_SHAKE_DURATION: float = 0.3          # ★ 震动时长 (秒)
const MEETING_OVERLAP: float = 40.0                 # ★ 同位置多角色水平叠放偏移 (px)
const _MEETING_BASE_ASPECT: float = 1216.0 / 1803.0  # 标准图层宽高比（用于容器定位）

# ══════════════════════════════════════════
#  内部引用与状态
# ══════════════════════════════════════════

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

# ── 立绘 (Card Mode) ──
var _portrait_cards: Dictionary = {}
var _current_character: CommCharacter = null

# ── Meeting Mode ──
var _display_mode: String = "card"                 # "card" | "meeting" | "presentation"
var _meeting_chars: Dictionary = {}                # { char_id: { "container", "layer_rects", "slot" } }
var _meeting_slot_front: Dictionary = {}           # { slot_name: char_id } 每个位置最近发言的角色
var _meeting_tween: Tween = null
var _presentation: PresentationOverlay = null

# ── 动态状态 ──
var _current_bar_height: float = 100.0             # 对话栏当前实际高度

# ── 动画 ──
var _blink_timer: float = 0.0
var _slide_tween: Tween = null
var _mouth_timer: float = 0.0

# ── 历史数据（内存 + 持久化） ──
var _history_lines: Array[Dictionary] = []
var _current_dialogue_id: String = ""

# 动态计算的目标 Y（相对于 _root 内部坐标）
var _target_y_expanded: float = 0.0
var _target_y_collapsed: float = 800.0


# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(main: Control, theme) -> void:
	_main = main
	_T = theme
	_presentation = PresentationOverlay.new()


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

	# ═══ 0.5 演示模式幻灯片叠加层 ═══
	if _presentation:
		_presentation.setup(_main, _root)

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
	UIManager._apply_bold_font(_name_label)
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
	UIManager._apply_bold_font(_text_label)
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
			card.modulate = Color(CARD_BRIGHTNESS, CARD_BRIGHTNESS, CARD_BRIGHTNESS, 1.0)
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

	# 根据角色素材模式创建图层栈（直接挂在 PanelContainer 下，由其自动填充）
	var layer_rects: Dictionary = {}
	if character.sprite_mode == CommCharacter.SpriteMode.LAYERED:
		var layer_order: Array = character.layer_config.get("order", [])
		for layer_name in layer_order:
			var rect := TextureRect.new()
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(rect)
			layer_rects[layer_name] = rect
	else:
		# STATIC/MINIMAL 模式：单张纹理
		var tex_rect := TextureRect.new()
		tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(tex_rect)
		layer_rects["static"] = tex_rect

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
	# ★ 有人物素材时隐藏卡片底部名称（避免遮挡立绘）
	if character.sprite_mode != CommCharacter.SpriteMode.MINIMAL:
		name_lbl.visible = false

	_root.add_child(card)
	# ★ 应用卡片亮度（调整 CARD_BRIGHTNESS 常量来改变）
	card.modulate = Color(CARD_BRIGHTNESS, CARD_BRIGHTNESS, CARD_BRIGHTNESS, 1.0)

	var position_slot: String = character.portrait_position if not character.portrait_position.is_empty() else "left"

	var card_data: Dictionary = {
		"card": card,
		"layer_rects": layer_rects,
		"name_label": name_lbl,
		"character_id": cid,
		"position": position_slot,
	}
	_portrait_cards[cid] = card_data
	_update_portrait_texture(card_data, character)
	_bring_card_to_front(cid)
	_update_card_layout()

func _update_portrait_texture(card_data: Dictionary, character: CommCharacter) -> void:
	var layer_rects: Dictionary = card_data.get("layer_rects", {})

	match character.sprite_mode:
		CommCharacter.SpriteMode.LAYERED:
			_update_layered_portrait(layer_rects, character)
		CommCharacter.SpriteMode.STATIC:
			var tex_rect: TextureRect = layer_rects.get("static")
			if tex_rect and character.static_portrait:
				tex_rect.texture = character.static_portrait
		_:
			pass  # MINIMAL 模式

func _update_layered_portrait(layer_rects: Dictionary, character: CommCharacter) -> void:
	var state: Dictionary = character.get_render_state()
	var layers: Dictionary = state.get("layer_textures", {})
	var mtex: Dictionary = state.get("mouth_textures", {})
	var bp: int = state.get("blink_phase", 0)
	var cur_mouth: String = state.get("mouth", "MBP")
	var speaking: bool = state.get("is_speaking", false)
	var has_overrides: bool = state.get("has_overrides", false)
	var anim: CharacterAnimator = character.animator

	# 更新静态图层（从 layer_config.order 动态获取，不再硬编码）
	var layer_order: Array = character.layer_config.get("order", [])
	for layer_name in layer_order:
		# 跳过动态图层（眼睛、嘴巴由下方逻辑处理）
		if layer_name.begins_with("eye_") or layer_name == "mouth":
			continue
		var rect: TextureRect = layer_rects.get(layer_name)
		if rect == null:
			continue
		# 优先使用 animator 的有效纹理（支持服装/覆盖）
		if has_overrides and anim:
			var effective = anim.get_effective_layer_texture(layer_name)
			if effective == null:
				rect.visible = false  # 图层被隐藏
				continue
			elif effective is Texture2D:
				rect.texture = effective
				rect.visible = true
				continue
		# 默认：直接从 layer_textures 读取
		if layers.has(layer_name):
			rect.texture = layers[layer_name]
			rect.visible = true

	# 更新眼睛（支持图层覆盖，如 wink）
	var eye_state: String = "open"
	match bp:
		0: eye_state = "open"
		1, 3: eye_state = "half"
		2: eye_state = "close"

	for side in ["L", "R"]:
		var layer_key: String = "eye_%s" % side
		var rect: TextureRect = layer_rects.get(layer_key)
		if rect == null:
			continue
		# 优先使用 animator 的覆盖纹理（仅当该眼睛被显式覆盖时）
		if has_overrides and anim and anim.is_layer_overridden(layer_key):
			var effective = anim.get_effective_layer_texture(layer_key)
			if effective is Texture2D:
				rect.texture = effective
				rect.visible = true
				continue
			else:
				# 覆盖值为 "hide" / "" → 隐藏该眼睛
				rect.visible = false
				continue
		# 默认：根据眨眼状态选择
		var tex_key: String = "eye_%s_%s" % [side, eye_state]
		if layers.has(tex_key):
			rect.texture = layers[tex_key]
			rect.visible = true

	# 更新嘴型
	var mouth_rect: TextureRect = layer_rects.get("mouth")
	if mouth_rect:
		if speaking and mtex.has(cur_mouth):
			mouth_rect.texture = mtex[cur_mouth]
		else:
			mouth_rect.texture = mtex.get("MBP")  # 默认闭嘴

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
			card.visible = not _collapsed and _display_mode == "card"
			card.modulate = Color(CARD_BRIGHTNESS, CARD_BRIGHTNESS, CARD_BRIGHTNESS, 1.0)

func _update_mouth_animations() -> void:
	# 更新所有分层角色的嘴型和眨眼动画（Card + Meeting 两种模式共用）
	if _display_mode == "card":
		for cid in _portrait_cards.keys():
			var card_data: Dictionary = _portrait_cards[cid]
			var character: CommCharacter = _get_character_by_id(cid)
			if character:
				var layer_rects: Dictionary = card_data.get("layer_rects", {})
				if character.sprite_mode == CommCharacter.SpriteMode.LAYERED:
					_update_layered_portrait(layer_rects, character)
				elif character.sprite_mode == CommCharacter.SpriteMode.STATIC:
					var tex_rect: TextureRect = layer_rects.get("static")
					if tex_rect and character.static_portrait:
						tex_rect.texture = character.static_portrait
	elif _display_mode == "meeting" or _display_mode == "presentation":
		for cid in _meeting_chars.keys():
			var mdata: Dictionary = _meeting_chars[cid]
			var character: CommCharacter = _get_character_by_id(cid)
			if character:
				var layer_rects: Dictionary = mdata.get("layer_rects", {})
				if character.sprite_mode == CommCharacter.SpriteMode.LAYERED:
					_update_layered_portrait(layer_rects, character)
					# 纹理变化可能改变宽高比（如 body → body_indexfinger），需重算尺寸
					_resize_meeting_rects(mdata)
				elif character.sprite_mode == CommCharacter.SpriteMode.STATIC:
					var tex_rect: TextureRect = layer_rects.get("static")
					if tex_rect and character.static_portrait:
						tex_rect.texture = character.static_portrait

var _characters_speaking: Dictionary = {}

## 注册角色引用（供 meeting 模式下多角色查找）
var _character_refs: Dictionary = {}

func register_character_ref(character: CommCharacter) -> void:
	if character:
		_character_refs[character.id] = character

func _get_character_by_id(cid: String) -> CommCharacter:
	if _current_character and _current_character.id == cid:
		return _current_character
	if _character_refs.has(cid):
		return _character_refs[cid]
	return null

func clear_cards() -> void:
	for cid in _portrait_cards.keys():
		var card_data: Dictionary = _portrait_cards[cid]
		var card: Control = card_data["card"]
		if is_instance_valid(card):
			card.queue_free()
	_portrait_cards.clear()
	_characters_speaking.clear()
	clear_meeting_chars()




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
		if _display_mode == "card":
			_update_card_layout()
		elif _display_mode == "meeting":
			_update_meeting_layout()
	_update_mouth_animations()

	if _continue_label and _continue_label.visible:
		_blink_timer += delta
		if _blink_timer >= 0.5:
			_blink_timer = 0.0
			_continue_label.modulate.a = 0.3 if _continue_label.modulate.a > 0.5 else 1.0


# ══════════════════════════════════════════
#  Meeting 模式 — galgame 风格大图角色展示
# ══════════════════════════════════════════

## 切换显示模式: "card" (小头像卡片) | "meeting" (大图) | "presentation" (演示)
func set_display_mode(mode: String) -> void:
	if mode == _display_mode:
		return
	var old_mode: String = _display_mode
	_display_mode = mode

	# 退出旧模式：清理演示幻灯片
	if old_mode == "presentation" and _presentation and _presentation.is_active():
		_presentation.hide_slide("fade")

	if mode == "meeting" or mode == "presentation":
		# 隐藏卡片
		for cid in _portrait_cards.keys():
			var card_data: Dictionary = _portrait_cards[cid]
			var card: Control = card_data["card"]
			if is_instance_valid(card):
				card.visible = false
		# Meeting/Presentation 角色在 _ensure_meeting_char 中按需创建
	elif mode == "card":
		# 隐藏 meeting 角色
		for cid in _meeting_chars.keys():
			var mdata: Dictionary = _meeting_chars[cid]
			var container: Control = mdata.get("container")
			if container and is_instance_valid(container):
				container.visible = false
		# 隐藏演示幻灯片
		if _presentation and _presentation.is_active():
			_presentation.hide_slide("fade")
		# 重新显示卡片
		if not _collapsed:
			_update_card_layout()

## 显示演示模式幻灯片
func show_presentation_slide(config: Dictionary) -> void:
	_build_ui()
	if _presentation:
		_presentation.show_slide(config)

## 隐藏演示模式幻灯片
func hide_presentation_slide(transition: String = "fade") -> void:
	if _presentation:
		_presentation.hide_slide(transition)

## 创建/显示 meeting 模式下的角色大图
func ensure_meeting_char(character: CommCharacter, slot: String) -> void:
	if character == null or _root == null:
		return
	_build_ui()
	register_character_ref(character)
	var cid: String = character.id

	# 已存在则更新 slot 并显示
	if _meeting_chars.has(cid):
		var mdata: Dictionary = _meeting_chars[cid]
		var old_slot: String = str(mdata.get("slot", ""))
		# ★ slot 变更时清理旧 slot 的 front 记录
		if old_slot != slot and str(_meeting_slot_front.get(old_slot, "")) == cid:
			_meeting_slot_front.erase(old_slot)
		mdata["slot"] = slot
		var container: Control = mdata.get("container")
		if container and is_instance_valid(container):
			container.visible = _display_mode == "meeting"
			_layout_meeting_char(mdata)
			# 更新纹理
			var layer_rects: Dictionary = mdata.get("layer_rects", {})
			if character.sprite_mode == CommCharacter.SpriteMode.LAYERED:
				_update_layered_portrait(layer_rects, character)
				_resize_meeting_rects(mdata)
			elif character.sprite_mode == CommCharacter.SpriteMode.STATIC and character.static_portrait:
				var tex_rect: TextureRect = layer_rects.get("static")
				if tex_rect:
					tex_rect.texture = character.static_portrait
		# ★ slot 变更后刷新所有位置的堆叠
		_update_meeting_layout()
		_refresh_meeting_z_order()
		return

	# 创建新容器（普通 Control，不自动填充子节点，每个图层单独定位/缩放）
	var container := Control.new()
	container.name = "MeetingChar_" + cid
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(container)

	# 创建分层 TextureRect（每个 rect 根据纹理实际比例单独设置大小和位置）
	var layer_rects: Dictionary = {}
	if character.sprite_mode == CommCharacter.SpriteMode.LAYERED:
		var layer_order: Array = character.layer_config.get("order", [])
		for layer_name in layer_order:
			var rect := TextureRect.new()
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			container.add_child(rect)
			layer_rects[layer_name] = rect
	else:
		# STATIC 模式降级
		var tex_rect := TextureRect.new()
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(tex_rect)
		layer_rects["static"] = tex_rect

	# ★ 应用大图亮度
	container.modulate = Color(MEETING_BRIGHTNESS, MEETING_BRIGHTNESS, MEETING_BRIGHTNESS, 1.0)
	container.visible = _display_mode == "meeting"

	var mdata: Dictionary = {
		"container": container,
		"layer_rects": layer_rects,
		"slot": slot,
		"character_id": cid,
		"base_pos": Vector2.ZERO,  # 用于动画恢复
	}
	_meeting_chars[cid] = mdata
	_layout_meeting_char(mdata)
	# 初始纹理设置
	if character.sprite_mode == CommCharacter.SpriteMode.LAYERED:
		_update_layered_portrait(layer_rects, character)
		# 纹理加载后根据实际宽高比调整每个图层 rect
		_resize_meeting_rects(mdata)
	elif character.sprite_mode == CommCharacter.SpriteMode.STATIC and character.static_portrait:
		var tex_rect: TextureRect = layer_rects.get("static")
		if tex_rect:
			tex_rect.texture = character.static_portrait
	# ★ 新角色加入后，重新布局同 slot 的所有角色（更新重叠偏移）并提到前面
	_update_meeting_layout()
	bring_meeting_to_front(cid)

## 计算 meeting 角色的位置和大小（含同位置重叠偏移）
func _layout_meeting_char(mdata: Dictionary) -> void:
	var container: Control = mdata.get("container")
	if container == null or not is_instance_valid(container):
		return
	if _root == null:
		return

	var screen_w: float = _root.size.x if _root.size.x > 0 else 800.0
	var screen_h: float = _root.size.y if _root.size.y > 0 else 600.0

	# ★ 计算角色尺寸
	var char_h: float = screen_h * MEETING_CHAR_HEIGHT_RATIO
	var char_w: float = char_h * _MEETING_BASE_ASPECT

	# ★ 计算 X 位置（居中到 slot 位置）
	var slot: String = str(mdata.get("slot", "center"))
	var center_x: float = screen_w * MEETING_POS_CENTER_X
	match slot:
		"left": center_x = screen_w * MEETING_POS_LEFT_X
		"right": center_x = screen_w * MEETING_POS_RIGHT_X
		"center": center_x = screen_w * MEETING_POS_CENTER_X

	# ★ 计算同 slot 重叠偏移
	var overlap_offset: float = _compute_meeting_overlap_offset(str(mdata.get("character_id", "")), slot)
	center_x += overlap_offset

	var x: float = center_x - char_w / 2.0

	# ★ Y 位置：底部对齐对话栏顶部
	var bar_top: float = _target_y_expanded if not _collapsed else screen_h
	var y: float = bar_top - char_h - MEETING_CHAR_BOTTOM_GAP

	container.position = Vector2(x, y)
	container.custom_minimum_size = Vector2(char_w, char_h)
	container.size = Vector2(char_w, char_h)
	mdata["base_pos"] = container.position
	# 根据每个图层纹理的实际宽高比调整 TextureRect 大小
	_resize_meeting_rects(mdata)

## 计算 meeting 模式下同 slot 角色的水平偏移
func _compute_meeting_overlap_offset(cid: String, slot: String) -> float:
	# 收集同 slot 的角色 ID 列表
	var same_slot: Array[String] = []
	for other_cid in _meeting_chars.keys():
		var other_data: Dictionary = _meeting_chars[other_cid]
		if str(other_data.get("slot", "center")) == slot:
			same_slot.append(str(other_cid))
	if same_slot.size() <= 1:
		return 0.0
	var idx: int = same_slot.find(cid)
	if idx < 0:
		return 0.0
	# 居中分布偏移
	var center_idx: float = (same_slot.size() - 1) / 2.0
	var direction: float = 1.0
	match slot:
		"left": direction = 1.0    # 左侧向右展开
		"right": direction = -1.0  # 右侧向左展开
		"center": direction = 1.0  # 中间向右展开
	return (idx - center_idx) * MEETING_OVERLAP * direction

## 根据每个图层纹理的实际宽高比单独调整 TextureRect 大小和位置
## 所有图层同高度（= 容器高度），宽度按纹理比例自适应，水平居中
func _resize_meeting_rects(mdata: Dictionary) -> void:
	var container: Control = mdata.get("container")
	if container == null or not is_instance_valid(container):
		return
	var ch: float = container.size.y
	var cw: float = container.size.x
	if ch <= 0.0:
		return
	var layer_rects: Dictionary = mdata.get("layer_rects", {})
	for key in layer_rects.keys():
		var rect: TextureRect = layer_rects[key]
		if rect == null or not is_instance_valid(rect):
			continue
		var tex: Texture2D = rect.texture
		if tex == null:
			# 无纹理时使用标准尺寸
			rect.position = Vector2.ZERO
			rect.size = Vector2(cw, ch)
			continue
		var tw: float = tex.get_width()
		var th: float = tex.get_height()
		if th <= 0.0:
			continue
		# 图层高度 = 容器高度，宽度按纹理实际比例缩放
		var rect_w: float = ch * (tw / th)
		var rect_x: float = (cw - rect_w) / 2.0  # 水平居中
		rect.position = Vector2(rect_x, 0.0)
		rect.size = Vector2(rect_w, ch)

## 将活跃角色的 meeting 容器提到最前面（z_index 最高）
## ★ 同时维护所有位置的堆叠和亮度逻辑：
##   每个 slot 独立管理，只有该 slot 最近发言的角色在最前且明亮，其余变暗
func bring_meeting_to_front(active_cid: String) -> void:
	if not _meeting_chars.has(active_cid):
		return
	# 记录该 slot 最近发言的角色
	var active_slot: String = str(_meeting_chars[active_cid].get("slot", "center"))
	_meeting_slot_front[active_slot] = active_cid
	# 刷新所有 slot 的 z-ordering 和亮度
	_refresh_meeting_z_order()

## 根据 _meeting_slot_front 刷新所有位置的堆叠和亮度
func _refresh_meeting_z_order() -> void:
	# 按 slot 分组
	var slots: Dictionary = {}  # { slot: Array[String] }
	for cid in _meeting_chars.keys():
		var slot: String = str(_meeting_chars[cid].get("slot", "center"))
		if not slots.has(slot):
			slots[slot] = [] as Array[String]
		(slots[slot] as Array[String]).append(str(cid))

	# 每个 slot 的 z_index 区间互不重叠（slot 间隔 10）
	var slot_idx: int = 0
	for slot in slots.keys():
		var ids: Array = slots[slot] as Array
		var front_cid: String = str(_meeting_slot_front.get(slot, ""))
		# 如果没有记录或记录的角色已不在该 slot，用第一个
		if front_cid.is_empty() or not ids.has(front_cid):
			front_cid = str(ids[0])
			_meeting_slot_front[slot] = front_cid

		var base_z: int = slot_idx * 10
		var back_z: int = base_z
		for cid in ids:
			var container: Control = _meeting_chars[cid].get("container")
			if container == null or not is_instance_valid(container):
				continue
			if str(cid) == front_cid:
				container.z_index = base_z + ids.size()
				container.modulate = Color(MEETING_BRIGHTNESS, MEETING_BRIGHTNESS, MEETING_BRIGHTNESS, container.modulate.a)
			else:
				container.z_index = back_z
				back_z += 1
				var dim: float = MEETING_BRIGHTNESS * 0.7
				container.modulate = Color(dim, dim, dim, container.modulate.a)
		slot_idx += 1

## 更新所有 meeting 角色布局（在对话栏高度变化时调用）
func _update_meeting_layout() -> void:
	for cid in _meeting_chars.keys():
		var mdata: Dictionary = _meeting_chars[cid]
		_layout_meeting_char(mdata)

## 播放 meeting 模式角色动画
func play_meeting_anim(char_id: String, anim: String) -> void:
	if not _meeting_chars.has(char_id):
		return
	var mdata: Dictionary = _meeting_chars[char_id]
	var container: Control = mdata.get("container")
	if container == null or not is_instance_valid(container):
		return

	if _meeting_tween:
		_meeting_tween.kill()

	var screen_w: float = _root.size.x if _root and _root.size.x > 0 else 800.0
	var base_pos: Vector2 = mdata.get("base_pos", container.position)

	match anim:
		"slide_in_left":
			container.position.x = -container.size.x
			container.modulate.a = 0.0
			_meeting_tween = _main.create_tween().set_parallel(true)
			_meeting_tween.tween_property(container, "position:x", base_pos.x, MEETING_SLIDE_DURATION)\
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			_meeting_tween.tween_property(container, "modulate:a", 1.0, MEETING_SLIDE_DURATION)
		"slide_in_right":
			container.position.x = screen_w
			container.modulate.a = 0.0
			_meeting_tween = _main.create_tween().set_parallel(true)
			_meeting_tween.tween_property(container, "position:x", base_pos.x, MEETING_SLIDE_DURATION)\
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			_meeting_tween.tween_property(container, "modulate:a", 1.0, MEETING_SLIDE_DURATION)
		"slide_in_center":
			container.position.y = base_pos.y + 60.0
			container.modulate.a = 0.0
			_meeting_tween = _main.create_tween().set_parallel(true)
			_meeting_tween.tween_property(container, "position:y", base_pos.y, MEETING_SLIDE_DURATION)\
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			_meeting_tween.tween_property(container, "modulate:a", 1.0, MEETING_SLIDE_DURATION)
		"slide_out_left":
			_meeting_tween = _main.create_tween().set_parallel(true)
			_meeting_tween.tween_property(container, "position:x", -container.size.x, MEETING_SLIDE_DURATION)\
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			_meeting_tween.tween_property(container, "modulate:a", 0.0, MEETING_SLIDE_DURATION)
		"slide_out_right":
			_meeting_tween = _main.create_tween().set_parallel(true)
			_meeting_tween.tween_property(container, "position:x", screen_w, MEETING_SLIDE_DURATION)\
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			_meeting_tween.tween_property(container, "modulate:a", 0.0, MEETING_SLIDE_DURATION)
		"fade_in":
			container.modulate.a = 0.0
			_meeting_tween = _main.create_tween()
			_meeting_tween.tween_property(container, "modulate:a", 1.0, MEETING_SLIDE_DURATION)
		"fade_out":
			_meeting_tween = _main.create_tween()
			_meeting_tween.tween_property(container, "modulate:a", 0.0, MEETING_SLIDE_DURATION)
		"shake":
			_meeting_tween = _main.create_tween()
			var steps: int = int(MEETING_SHAKE_DURATION / 0.05)
			for i in range(steps):
				var offset_x: float = randf_range(-MEETING_SHAKE_INTENSITY, MEETING_SHAKE_INTENSITY)
				_meeting_tween.tween_property(container, "position:x", base_pos.x + offset_x, 0.05)
			_meeting_tween.tween_property(container, "position:x", base_pos.x, 0.05)

## 清除所有 meeting 角色
func clear_meeting_chars() -> void:
	for cid in _meeting_chars.keys():
		var mdata: Dictionary = _meeting_chars[cid]
		var container: Control = mdata.get("container")
		if container and is_instance_valid(container):
			container.queue_free()
	_meeting_chars.clear()
	_meeting_slot_front.clear()
	_display_mode = "card"

## 隐藏指定 meeting 角色
func hide_meeting_char(char_id: String) -> void:
	if _meeting_chars.has(char_id):
		var mdata: Dictionary = _meeting_chars[char_id]
		var container: Control = mdata.get("container")
		if container and is_instance_valid(container):
			container.visible = false


# ══════════════════════════════════════════
#  清理
# ══════════════════════════════════════════
func cleanup() -> void:
	flush_history_to_disk()
	clear_cards()
	if _slide_tween:
		_slide_tween.kill()
		_slide_tween = null
	if _meeting_tween:
		_meeting_tween.kill()
		_meeting_tween = null
	if _presentation:
		_presentation.cleanup()
	_display_mode = "card"
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
