extends PanelContainer
## 收件箱专用列表；邮件 ID 保持选中项，正文返回保留筛选及滚动位置。

var main: Control
var mail_system: RefCounted
var is_active := false
var selected_id := ""
var _search: LineEdit
var _unread: Button
var _count: Label
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _message: Label
var _items: Array[Dictionary] = []
var _saved_scroll := 0
var _cached_input := true
var _cached_prompt := true

func setup(host: Control, system: RefCounted) -> void:
	main = host
	mail_system = system
	name = "MailInbox"
	main.add_child(self)
	UIManager.apply_terminal_theme(self, main.input_field.get_theme_font_size("font_size"))
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	var toolbar := HBoxContainer.new()
	column.add_child(toolbar)
	_count = Label.new()
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_count)
	_unread = Button.new()
	_unread.toggle_mode = true
	_unread.text = "[ 全部邮件 ]"
	_unread.focus_mode = Control.FOCUS_NONE
	_style_button(_unread)
	_unread.toggled.connect(func(on: bool) -> void:
		_unread.text = "[ 仅未读 ]" if on else "[ 全部邮件 ]"
		refresh())
	toolbar.add_child(_unread)
	var close_button := Button.new()
	close_button.text = "关闭邮箱 [Esc]"
	close_button.focus_mode = Control.FOCUS_NONE
	_style_button(close_button)
	close_button.pressed.connect(close)
	toolbar.add_child(close_button)
	_search = LineEdit.new()
	UIManager.setup_input_field(_search)
	_search.placeholder_text = "搜索主题、发件人或邮件 ID…  [Ctrl+F]"
	_search.text_changed.connect(func(_value: String) -> void: refresh())
	_search.text_submitted.connect(func(_value: String) -> void: _read_selected())
	column.add_child(_search)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UIManager.setup_scrollbar_style(_scroll)
	column.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	_scroll.add_child(_rows)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color", main.T.error)
	column.add_child(_message)
	var help := Label.new()
	help.text = "↑↓ 选择   Enter 阅读   Ctrl+F 搜索   Esc 关闭   ● 未读   [全局]/[临时] 邮件保存范围"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(help)
	hide()
	main.get_viewport().size_changed.connect(_align)
	_align()
	_search.add_theme_color_override("font_color", main.T.primary)
	_count.add_theme_color_override("font_color", main.T.primary)
	_unread.add_theme_color_override("font_color", main.T.primary)
	help.add_theme_color_override("font_color", main.T.muted)
	# CRT 使用 CanvasLayer；同层列表必须在 MainContent 之后，否则它会挡住点击。
	main.move_child(self, main.get_child_count() - 1)

func _align() -> void:
	var area: Rect2 = main.scroll_container.get_global_rect()
	position = area.position - main.global_position
	size = area.size

func open() -> void:
	if is_active:
		return
	_cached_input = main.input_field.visible
	_cached_prompt = main.prompt_label.visible
	UIManager.apply_terminal_theme(self, main.input_field.get_theme_font_size("font_size"))
	UIManager.setup_input_field(_search)
	_search.add_theme_color_override("font_color", main.T.primary)
	_count.add_theme_color_override("font_color", main.T.primary)
	_unread.add_theme_color_override("font_color", main.T.primary)
	_message.add_theme_color_override("font_color", main.T.error)
	is_active = true
	main.move_child(self, main.get_child_count() - 1)
	main.input_field.hide()
	main.prompt_label.hide()
	main.input_field.release_focus()
	main._clear_completion()
	main.path_label.text = "MAIL | 收件箱 | ↑↓ 选择 / Enter 阅读 / Esc 关闭"
	_align()
	show()
	refresh()
	_restore_scroll.call_deferred()

func _restore_scroll() -> void:
	_scroll.scroll_vertical = _saved_scroll

func close(notify: bool = true) -> void:
	if not is_active:
		return
	_saved_scroll = _scroll.scroll_vertical
	is_active = false
	hide()
	main.input_field.visible = _cached_input
	main.prompt_label.visible = _cached_prompt
	main._update_status_bar()
	main._refocus_input.call_deferred()
	if notify:
		mail_system._on_inbox_closed()

func refresh() -> void:
	if not is_active:
		return
	var old_scroll := _scroll.scroll_vertical
	_message.text = ""
	_items.clear()
	for row in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	var query := _search.text.strip_edges().to_lower()
	var all_items: Array = mail_system.get_inbox_items()
	for item in all_items:
		if _unread.button_pressed and bool(item.get("read", false)):
			continue
		var searchable := (str(item.get("title", "")) + " " + str(item.get("from", "")) + " " + str(item.get("id", ""))).to_lower()
		if not query.is_empty() and not searchable.contains(query):
			continue
		_items.append(item)
	_count.text = "收件箱  %d 未读 / %d 封 | 显示 %d 封" % [mail_system.get_unread_count(), all_items.size(), _items.size()]
	if _selected_index() < 0:
		selected_id = str(_items[0].get("id", "")) if not _items.is_empty() else ""
	for item in _items:
		var id := str(item.get("id", ""))
		var button := Button.new()
		_style_button(button)
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var marker := "●" if not bool(item.get("read", false)) else " "
		var scope := "全局" if bool(item.get("persistent", false)) else "临时"
		var priority := " [重要]" if str(item.get("priority", "normal")) in ["high", "urgent"] else ""
		var attachment: String = mail_system.get_attachment_label(id)
		button.text = "%s [%s] %s | %s%s%s\n    %s" % [marker, scope, item.get("from", "未知"), item.get("title", "无标题"), priority, "  [附件：" + attachment + "]" if not attachment.is_empty() else "", item.get("delivered_at", "")]
		button.tooltip_text = id
		button.pressed.connect(func() -> void:
			selected_id = id
			_read_selected())
		_rows.add_child(button)
	if _items.is_empty():
		var empty := Label.new()
		empty.text = "没有符合条件的邮件。" if not all_items.is_empty() else "收件箱为空。"
		_rows.add_child(empty)
	_highlight()
	_scroll.scroll_vertical = old_scroll

func show_message(message: String) -> void:
	_message.text = message

func _selected_index() -> int:
	for index in range(_items.size()):
		if str(_items[index].get("id", "")) == selected_id:
			return index
	return -1

func _highlight() -> void:
	for index in range(_items.size()):
		var button := _rows.get_child(index) as Button
		button.set_pressed_no_signal(str(_items[index].get("id", "")) == selected_id)
		button.add_theme_color_override("font_color", main.T.muted if bool(_items[index].get("read", false)) else main.T.primary)

func _style_button(button: Button) -> void:
	UIManager.style_terminal_button(button, main.T)

func _move_selection(step: int) -> void:
	if _items.is_empty():
		return
	var index := clampi(_selected_index() + step, 0, _items.size() - 1)
	selected_id = str(_items[index].get("id", ""))
	_highlight()
	_scroll.ensure_control_visible(_rows.get_child(index))

func _read_selected() -> void:
	if not selected_id.is_empty():
		mail_system.read_mail_id(selected_id)

func handle_input(event: InputEvent) -> bool:
	if not is_active or event is not InputEventKey or not event.pressed:
		return false
	if _search.has_focus() and _search.has_ime_text():
		UIManager.sync_ime(_search)
	if _search.has_focus() and _search.has_ime_text():
		return false
	if event.ctrl_pressed and event.keycode == KEY_F:
		_search.grab_focus()
		_search.select_all()
		return true
	match event.keycode:
		KEY_ESCAPE:
			close()
			return true
		KEY_UP, KEY_DOWN:
			if not _search.has_ime_text():
				_move_selection(-1 if event.keycode == KEY_UP else 1)
				return true
		KEY_ENTER, KEY_KP_ENTER:
			if not _search.has_focus():
				_read_selected()
				return true
		KEY_Q:
			if not _search.has_focus():
				close()
				return true
	return false
