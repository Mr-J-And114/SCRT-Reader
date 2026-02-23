# two_page_reader.gd - 双页阅读模板（Overlay 覆盖 OutputArea）
class_name TwoPageReader
extends RefCounted

var main: Control = null
var fs: FileSystem = null
var T: Variant = null

var overlay: Panel = null
var _hbox: HBoxContainer = null
var _left_rtl: RichTextLabel = null
var _right_rtl: RichTextLabel = null
var _nav_label: RichTextLabel = null

var is_active: bool = false
var pages: Array[Dictionary] = []
var total_pages: int = 0
var current_spread: int = 0
var _on_exit_callback: Callable = Callable()
var _title: String = ""

func setup(p_main: Control, p_fs: FileSystem, p_theme: Variant) -> void:
	main = p_main
	fs = p_fs
	T = p_theme

func _ensure_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		return
	var root: Control = main
	overlay = Panel.new()
	overlay.name = "TwoPageReaderOverlay"
	overlay.visible = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0)
	overlay.add_theme_stylebox_override("panel", bg)
	root.add_child(overlay)
	var crt_node: Node = root.get_node_or_null("CRTEffect")
	if crt_node:
		root.move_child(overlay, crt_node.get_index())
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.offset_left = 0
	overlay.offset_top = 0
	overlay.offset_right = 0
	overlay.offset_bottom = 0
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	overlay.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)
	_nav_label = RichTextLabel.new()
	_nav_label.bbcode_enabled = true
	_nav_label.fit_content = true
	_nav_label.scroll_active = false
	_nav_label.selection_enabled = false
	_nav_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	CrtmlParser.apply_fonts(_nav_label)
	vbox.add_child(_nav_label)
	_hbox = HBoxContainer.new()
	_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(_hbox)
	_left_rtl = _make_page_rtl("LeftPage")
	_right_rtl = _make_page_rtl("RightPage")
	_hbox.add_child(_left_rtl)
	_hbox.add_child(_right_rtl)
	_align_overlay_to_output_area()
	var tree: SceneTree = main.get_tree()
	if tree and tree.root:
		tree.root.size_changed.connect(_align_overlay_to_output_area)

func _make_page_rtl(name: String) -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.name = name
	rtl.bbcode_enabled = true
	rtl.fit_content = false
	rtl.scroll_active = false
	rtl.selection_enabled = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rtl.mouse_filter = Control.MOUSE_FILTER_PASS
	CrtmlParser.apply_fonts(rtl)
	rtl.meta_clicked.connect(func(meta: Variant) -> void:
		if main and main.has_method("_on_meta_clicked"):
			main._on_meta_clicked(meta)
	)
	return rtl

func _align_overlay_to_output_area() -> void:
	if overlay == null:
		return
	var output_area: ScrollContainer = main.scroll_container
	if output_area == null:
		return
	var rect: Rect2 = output_area.get_global_rect()
	overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	overlay.position = main.to_local(rect.position)
	overlay.size = rect.size

func open(p_pages: Array, p_title: String = "", p_on_exit: Callable = Callable()) -> void:
	_ensure_overlay()
	pages.clear()
	for i in p_pages.size():
		var d: Dictionary = p_pages[i]
		pages.append(d)
	total_pages = pages.size()
	current_spread = 0
	_title = p_title
	_on_exit_callback = p_on_exit
	is_active = true
	overlay.visible = true
	_render_spread()
	_update_nav()

func close() -> void:
	if not is_active:
		return
	is_active = false
	if overlay and is_instance_valid(overlay):
		overlay.visible = false
	if _on_exit_callback.is_valid():
		_on_exit_callback.call()
	_on_exit_callback = Callable()

func handle_input(event: InputEvent) -> bool:
	if not is_active:
		return false
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE, KEY_Q:
				close(); return true
			KEY_LEFT, KEY_PAGEUP:
				_prev_spread(); return true
			KEY_RIGHT, KEY_PAGEDOWN:
				_next_spread(); return true
			KEY_HOME:
				_goto_spread(0); return true
			KEY_END:
				var total_spreads: int = int(ceil(float(total_pages) / 2.0))
				var max_spread: int = max(0, total_spreads - 1)
				_goto_spread(max_spread); return true
	return false

func _prev_spread() -> void:
	if current_spread > 0:
		current_spread -= 1
		_render_spread()
		_update_nav()

func _next_spread() -> void:
	var total_spreads: int = int(ceil(float(total_pages) / 2.0))
	var max_spread: int = max(0, total_spreads - 1)
	if current_spread < max_spread:
		current_spread += 1
		_render_spread()
		_update_nav()

func _goto_spread(spread_idx: int) -> void:
	var total_spreads: int = int(ceil(float(total_pages) / 2.0))
	var max_spread: int = max(0, total_spreads - 1)
	current_spread = clamp(spread_idx, 0, max_spread)
	_render_spread()
	_update_nav()

func _render_spread() -> void:
	var left_idx: int = current_spread * 2
	var right_idx: int = left_idx + 1
	_set_page_content(_left_rtl, left_idx)
	_set_page_content(_right_rtl, right_idx)

func _set_page_content(rtl: RichTextLabel, page_idx: int) -> void:
	rtl.text = ""
	if page_idx < 0 or page_idx >= total_pages:
		return
	var page: Dictionary = pages[page_idx]
	if page.has("bbcode"):
		rtl.append_text(str(page["bbcode"]))
	elif page.has("text"):
		rtl.append_text(str(page["text"]))
	else:
		rtl.append_text("")

func _update_nav() -> void:
	if _nav_label == null:
		return
	var p: String = "#A0FFA0"
	var m: String = "#888888"
	if T != null:
		p = str(T.primary_hex)
		m = str(T.muted_hex)
	var total_spreads: int = int(ceil(float(total_pages) / 2.0))
	var cur: int = current_spread + 1
	_nav_label.text = ""
	var title_str: String = _title if not _title.is_empty() else "DOCUMENT"
	_nav_label.append_text("[color=%s]%s[/color]  [color=%s]Spread %d / %d[/color]" % [p, title_str, m, cur, total_spreads])

func get_active_page_rtl() -> RichTextLabel:
	if _right_rtl and is_instance_valid(_right_rtl):
		return _right_rtl
	return _left_rtl
