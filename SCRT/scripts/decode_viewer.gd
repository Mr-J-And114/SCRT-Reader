# ============================================================
# decode_viewer.gd - 密码解码器全屏交互界面
# 参考 radio_receiver.gd / oscilloscope.gd 的 overlay 方案
# ============================================================
class_name DecodeViewer
extends RefCounted

# ══════════════════════════════════════════
#  模块引用
# ══════════════════════════════════════════
var main = null
var T = null
var decoder: CipherDecoder = null

# ══════════════════════════════════════════
#  状态
# ══════════════════════════════════════════
var is_active: bool = false
var overlay: Panel = null
var decode_canvas: Control = null
var nav_label: RichTextLabel = null

# 缓存
var _cached_input_visible: bool = true
var _cached_prompt_visible: bool = true
var _cached_output_text: String = ""

# ══════════════════════════════════════════
#  解码状态
# ══════════════════════════════════════════
enum ViewMode { SELECT, INPUT, ANIMATING, RESULT }
var view_mode: ViewMode = ViewMode.SELECT

var selected_cipher: CipherDecoder.CipherType = CipherDecoder.CipherType.CAESAR
var cipher_input_text: String = ""
var cipher_key: String = ""
var _input_step: int = 0  # 0=选择方法, 1=输入密文, 2=输入密钥, 3=运行

var current_result: CipherDecoder.DecodeResult = null

# 动画
var _anim_step_index: int = 0
var _anim_timer: float = 0.0
var _anim_speed: float = 0.08  # 每步间隔秒
var _anim_paused: bool = false
var _anim_complete: bool = false
var _anim_decoded_so_far: String = ""

# 选择菜单
var _menu_index: int = 0
var _menu_items: Array[Dictionary] = []

# 滚动偏移（步骤日志）
var _log_scroll: int = 0

# 绘制参数
var draw_color: Color = Color(0.2, 1.0, 0.3, 1.0)
var draw_color_dim: Color = Color(0.1, 0.5, 0.15, 0.6)
var grid_color: Color = Color(0.1, 0.3, 0.1, 0.3)
var error_color: Color = Color(1.0, 0.3, 0.2, 1.0)
var warning_color: Color = Color(1.0, 0.7, 0.0, 1.0)
var bg_color: Color = Color(0.0, 0, 0.0, 0)
var highlight_color: Color = Color(0.3, 1.0, 0.5, 0.3)

const MARGIN: float = 16.0
const LINE_HEIGHT: float = 18.0
const SECTION_GAP: float = 10.0

# 文本输入缓冲区
var _text_buffer: String = ""
var _cursor_blink_timer: float = 0.0
var _cursor_visible: bool = true

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(p_main) -> void:
	main = p_main
	T = ThemeManager.current
	decoder = CipherDecoder.new()
	_update_colors()
	_build_menu()

func _update_colors() -> void:
	if T == null:
		return
	draw_color = T.primary
	draw_color.a = 1.0
	draw_color_dim = T.primary
	draw_color_dim.a = 0.4
	grid_color = T.primary
	grid_color.a = 0.15
	if T.get("error") != null:
		error_color = T.error
	if T.get("warning") != null:
		warning_color = T.warning
	bg_color = Color(0, 0, 0, 0)  # ★ 透明背景
	highlight_color = Color(draw_color.r, draw_color.g, draw_color.b, 0.25)


func _build_menu() -> void:
	_menu_items = [
		{"type": CipherDecoder.CipherType.CAESAR, "name": "凯撒密码 (Caesar)", "desc": "字母表固定偏移", "needs_key": false, "optional_key": true, "key_hint": "偏移量(0-25)，留空自动检测"},
		{"type": CipherDecoder.CipherType.VIGENERE, "name": "维吉尼亚密码 (Vigenère)", "desc": "多表替换密码", "needs_key": true, "optional_key": false, "key_hint": "密钥单词"},
		{"type": CipherDecoder.CipherType.ROT13, "name": "ROT13", "desc": "偏移13的凯撒变体", "needs_key": false, "optional_key": false, "key_hint": ""},
		{"type": CipherDecoder.CipherType.ATBASH, "name": "Atbash 镜像密码", "desc": "字母表镜像反转 A↔Z", "needs_key": false, "optional_key": false, "key_hint": ""},
		{"type": CipherDecoder.CipherType.SUBSTITUTION, "name": "替换密码 (Substitution)", "desc": "自定义字母表映射", "needs_key": true, "optional_key": false, "key_hint": "26位字母替换表"},
		{"type": CipherDecoder.CipherType.BASE64, "name": "Base64", "desc": "Base64 编码", "needs_key": false, "optional_key": false, "key_hint": ""},
		{"type": CipherDecoder.CipherType.MORSE, "name": "摩斯电码 (Morse)", "desc": "点划分隔 / 空格分词", "needs_key": false, "optional_key": false, "key_hint": ""},
		{"type": CipherDecoder.CipherType.REVERSE, "name": "反转 (Reverse)", "desc": "字符串反转", "needs_key": false, "optional_key": false, "key_hint": ""},
	]

## ★ 播放 beep 音效
func _play_beep() -> void:
	if main and main.audio_manager:
		main.audio_manager.play_beep()


# ══════════════════════════════════════════
#  UI 构建
# ══════════════════════════════════════════
func _ensure_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		return

	overlay = Panel.new()
	overlay.name = "DecodeViewerOverlay"
	overlay.visible = false
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0)
	overlay.add_theme_stylebox_override("panel", bg_style)

	var root_control: Control = main as Control
	root_control.add_child(overlay)
	var crt_node: Node = root_control.get_node_or_null("CRTEffect")
	if crt_node:
		root_control.move_child(overlay, crt_node.get_index())

	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.offset_left = 0
	overlay.offset_top = 0
	overlay.offset_right = 0
	overlay.offset_bottom = 0

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	overlay.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	decode_canvas = _DecodeCanvas.new()
	decode_canvas.name = "DecodeCanvas"
	decode_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	decode_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(decode_canvas as _DecodeCanvas).viewer = self
	vbox.add_child(decode_canvas)

	nav_label = RichTextLabel.new()
	nav_label.bbcode_enabled = true
	nav_label.fit_content = true
	nav_label.scroll_active = false
	nav_label.selection_enabled = false
	nav_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(nav_label)

func _align_overlay() -> void:
	if overlay == null:
		return
	var output_area: ScrollContainer = main.scroll_container
	var rect: Rect2 = output_area.get_global_rect()
	overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	overlay.position = rect.position
	overlay.size = rect.size

# ══════════════════════════════════════════
#  打开 / 关闭
# ══════════════════════════════════════════
func open(args: Array = []) -> void:
	_ensure_overlay()
	T = ThemeManager.current
	_update_colors()
	_align_overlay()

	is_active = true

	# 缓存终端
	_cached_input_visible = main.input_field.visible
	_cached_prompt_visible = main.prompt_label.visible
	main.input_field.visible = false
	main.prompt_label.visible = false
	_cached_output_text = main.output_text.text
	main.output_text.text = ""
	main.path_label.text = "CIPHER DECODER | Q/Esc 退出"

	# 先清空密钥，避免沿用上一次的密钥
	cipher_key = ""

	# 解析参数：decode <method> [key]
	if args.size() >= 1:
		var method_key: String = str(args[0]).to_lower()
		selected_cipher = CipherDecoder.get_type_from_key(method_key)
		# ★ 同步 _menu_index 以匹配 selected_cipher
		for i in range(_menu_items.size()):
			if int(_menu_items[i]["type"]) == int(selected_cipher):
				_menu_index = i
				break
		view_mode = ViewMode.INPUT
		_input_step = 1  # 直接进入密文输入
		_text_buffer = ""

		# 如果命令显式传入了 key，这里才使用；否则保持清空
		if args.size() >= 2:
			cipher_key = str(args[1])
	else:
		view_mode = ViewMode.SELECT
		_menu_index = 0
		cipher_input_text = ""

	current_result = null
	_anim_step_index = 0
	_anim_complete = false
	_anim_decoded_so_far = ""
	_log_scroll = 0

	overlay.visible = true
	decode_canvas.set_process(true)
	_update_nav()


func close() -> void:
	if not is_active:
		return
	is_active = false

	if overlay and is_instance_valid(overlay):
		overlay.visible = false
	if decode_canvas:
		decode_canvas.set_process(false)

	main.output_text.clear()
	main.output_text.append_text(_cached_output_text)
	_cached_output_text = ""
	main.input_field.visible = _cached_input_visible
	main.prompt_label.visible = _cached_prompt_visible
	main._update_status_bar()
	main.input_field.grab_focus()

	if main.has_method("_on_decode_viewer_closed"):
		main._on_decode_viewer_closed()

# ══════════════════════════════════════════
#  输入处理
# ══════════════════════════════════════════
func handle_input(event: InputEvent) -> bool:
	if not is_active:
		return false
	if not (event is InputEventKey and event.pressed):
		return false

	# 全局退出
	if event.keycode == KEY_ESCAPE:
		if view_mode == ViewMode.ANIMATING or view_mode == ViewMode.RESULT:
			view_mode = ViewMode.SELECT
			_menu_index = 0
			current_result = null
			cipher_key = ""  # 返回选择时清空密钥
			_update_nav()
			return true
		elif view_mode == ViewMode.INPUT:
			view_mode = ViewMode.SELECT
			_menu_index = 0
			cipher_key = ""  # 返回选择时清空密钥
			_update_nav()
			return true
		else:
			close()
			return true

	if event.keycode == KEY_Q and view_mode == ViewMode.SELECT:
		close()
		return true

	match view_mode:
		ViewMode.SELECT:
			return _handle_select_input(event)
		ViewMode.INPUT:
			return _handle_text_input(event)
		ViewMode.ANIMATING:
			return _handle_anim_input(event)
		ViewMode.RESULT:
			return _handle_result_input(event)
	return false



func _handle_select_input(event: InputEventKey) -> bool:
	match event.keycode:
		KEY_UP:
			_menu_index = maxi(_menu_index - 1, 0)
			_play_beep()
			return true
		KEY_DOWN:
			_menu_index = mini(_menu_index + 1, _menu_items.size() - 1)
			_play_beep()
			return true
		KEY_ENTER:
			selected_cipher = _menu_items[_menu_index]["type"] as CipherDecoder.CipherType
			view_mode = ViewMode.INPUT
			_input_step = 1
			_text_buffer = ""
			cipher_key = ""  # ★ 清空上一次密钥，强制重新输入
			_play_beep()
			_update_nav()
			return true
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
			var idx: int = event.keycode - KEY_1
			if idx >= 0 and idx < _menu_items.size():
				_menu_index = idx
				selected_cipher = _menu_items[idx]["type"] as CipherDecoder.CipherType
				view_mode = ViewMode.INPUT
				_input_step = 1
				_text_buffer = ""
				cipher_key = ""  # ★ 清空上一次密钥，强制重新输入
				_play_beep()
				_update_nav()
				return true
	return false



func _handle_text_input(event: InputEventKey) -> bool:
	if event.keycode == KEY_BACKSPACE:
		if not _text_buffer.is_empty():
			_text_buffer = _text_buffer.left(-1)
		return true
	
	if event.keycode == KEY_ENTER:
		if _input_step == 1:
			if _text_buffer.strip_edges().is_empty():
				return true
			cipher_input_text = _text_buffer
			_text_buffer = ""
			_play_beep()  # ★ 添加
			var needs_key: bool = _menu_items[_menu_index].get("needs_key", false) as bool
			var optional_key: bool = _menu_items[_menu_index].get("optional_key", false) as bool
			if (needs_key or optional_key) and cipher_key.is_empty():
				_input_step = 2
			else:
				_start_decode()
			_update_nav()
			return true
		elif _input_step == 2:
			cipher_key = _text_buffer
			_text_buffer = ""
			_play_beep()  # ★ 添加
			_start_decode()
			_update_nav()
			return true
		return true
	
	if event.keycode == KEY_TAB:
		if _input_step == 2:
			cipher_key = ""
			_text_buffer = ""
			_play_beep()  # ★ 添加
			_start_decode()
			_update_nav()
			return true
		return true

	
	# 普通字符输入
	var unicode: int = event.unicode
	if unicode > 31 and unicode < 127:
		_text_buffer += char(unicode)
		return true
	# 支持中文等（unicode > 127）
	if unicode > 127:
		_text_buffer += char(unicode)
		return true
	return false


func _handle_anim_input(event: InputEventKey) -> bool:
	match event.keycode:
		KEY_SPACE:
			_anim_paused = not _anim_paused
			_play_beep()  # ★ 添加
			return true
		KEY_RIGHT:
			# 单步前进
			if _anim_step_index < current_result.steps.size():
				_advance_anim_step()
			return true
		KEY_LEFT:
			# 单步后退
			if _anim_step_index > 0:
				_anim_step_index -= 1
				_rebuild_decoded_so_far()
			return true
		KEY_UP:
			# 加速
			_anim_speed = maxf(_anim_speed - 0.02, 0.01)
			return true
		KEY_DOWN:
			# 减速
			_anim_speed = minf(_anim_speed + 0.02, 0.5)
			return true
		KEY_ENTER:
			# 跳到结果
			_anim_step_index = current_result.steps.size()
			_anim_complete = true
			_anim_decoded_so_far = current_result.output_text
			view_mode = ViewMode.RESULT
			_play_beep()  # ★ 添加
			_update_nav()
			return true
		KEY_PAGEUP:
			_log_scroll = maxi(_log_scroll - 5, 0)
			return true
		KEY_PAGEDOWN:
			_log_scroll += 5
			return true
	return false

func _handle_result_input(event: InputEventKey) -> bool:
	match event.keycode:
		KEY_R:
			# 重新解码（回到输入）
			view_mode = ViewMode.INPUT
			_input_step = 1
			_text_buffer = cipher_input_text
			cipher_key = ""  # ★ 重新解码必须重新输入密钥
			current_result = null
			_update_nav()
			return true
		KEY_N:
			# 新解码（回到选择）
			view_mode = ViewMode.SELECT
			_menu_index = 0
			cipher_input_text = ""
			cipher_key = ""
			current_result = null
			_update_nav()
			return true
		KEY_C:
			# 复制结果到剪贴板
			if current_result != null:
				DisplayServer.clipboard_set(current_result.output_text)
				_play_beep()
			return true
		KEY_PAGEUP:
			_log_scroll = maxi(_log_scroll - 5, 0)
			return true
		KEY_PAGEDOWN:
			_log_scroll += 5
			return true
	return false


# ══════════════════════════════════════════
#  解码执行
# ══════════════════════════════════════════
func _start_decode() -> void:
	current_result = decoder.decode(selected_cipher, cipher_input_text, cipher_key)

	if not current_result.success:
		view_mode = ViewMode.RESULT
		_anim_complete = true
	else:
		view_mode = ViewMode.ANIMATING
		_anim_step_index = 0
		_anim_timer = 0.0
		_anim_paused = false
		_anim_complete = false
		_anim_decoded_so_far = ""
		_log_scroll = 0

	_update_nav()


func _advance_anim_step() -> void:
	if current_result == null:
		return
	if _anim_step_index >= current_result.steps.size():
		_anim_complete = true
		_anim_decoded_so_far = current_result.output_text
		view_mode = ViewMode.RESULT
		_play_beep()  # ★ 解码完成
		_update_nav()
		return
	var step: CipherDecoder.DecodeStep = current_result.steps[_anim_step_index] as CipherDecoder.DecodeStep
	_anim_decoded_so_far += step.result_char
	_anim_step_index += 1

	# ★ 节流 beep：速度快时每5步播一次，慢速时每步播
	if _anim_speed >= 0.05 or _anim_step_index % 5 == 0:
		_play_beep()

	# 自动滚动日志
	var visible_lines: int = 12
	if _anim_step_index > visible_lines:
		_log_scroll = _anim_step_index - visible_lines
	if _anim_step_index >= current_result.steps.size():
		_anim_complete = true
		view_mode = ViewMode.RESULT
		_update_nav()


func _rebuild_decoded_so_far() -> void:
	_anim_decoded_so_far = ""
	for i in range(_anim_step_index):
		var step: CipherDecoder.DecodeStep = current_result.steps[i] as CipherDecoder.DecodeStep
		_anim_decoded_so_far += step.result_char

# ══════════════════════════════════════════
#  每帧更新
# ══════════════════════════════════════════
func process(delta: float) -> void:
	if not is_active:
		return

	_cursor_blink_timer += delta
	if _cursor_blink_timer >= 0.5:
		_cursor_blink_timer = 0.0
		_cursor_visible = not _cursor_visible

	if view_mode == ViewMode.ANIMATING and not _anim_paused and not _anim_complete:
		_anim_timer += delta
		if _anim_timer >= _anim_speed:
			_anim_timer = 0.0
			_advance_anim_step()

	if decode_canvas:
		decode_canvas.queue_redraw()

# ══════════════════════════════════════════
#  导航栏
# ══════════════════════════════════════════
func _update_nav() -> void:
	if nav_label == null:
		return
	var m: String = T.muted_hex if T else "#666666"
	var parts: Array[String] = []

	match view_mode:
		ViewMode.SELECT:
			parts.append("[color=%s]↑↓[/color] 选择" % m)
			parts.append("[color=%s]Enter[/color] 确认" % m)
			parts.append("[color=%s]1-8[/color] 快速选择" % m)
			parts.append("[color=%s]Q/Esc[/color] 退出" % m)
		ViewMode.INPUT:
			parts.append("[color=%s]输入文本后按 Enter 确认[/color]" % m)
			parts.append("[color=%s]Esc[/color] 返回" % m)
			if _input_step == 2:
				var is_optional: bool = _menu_items[_menu_index].get("optional_key", false) as bool
				if is_optional:
					parts.append("[color=%s]Enter(留空)[/color] 自动检测" % m)
				parts.append("[color=%s]Tab[/color] 跳过密钥" % m)
		ViewMode.ANIMATING:
			parts.append("[color=%s]Space[/color] 暂停/继续" % m)
			parts.append("[color=%s]←→[/color] 单步" % m)
			parts.append("[color=%s]↑↓[/color] 速度" % m)
			parts.append("[color=%s]Enter[/color] 跳到结果" % m)
			parts.append("[color=%s]Esc[/color] 返回" % m)
		ViewMode.RESULT:
			parts.append("[color=%s]R[/color] 重新解码" % m)
			parts.append("[color=%s]N[/color] 新解码" % m)
			parts.append("[color=%s]C[/color] 复制结果" % m)
			parts.append("[color=%s]Esc[/color] 返回" % m)

	nav_label.text = " | ".join(parts)

# ══════════════════════════════════════════════════════════════
#  自定义绘制画布（内部类）
# ══════════════════════════════════════════════════════════════
class _DecodeCanvas extends Control:
	var viewer: DecodeViewer = null
	var _font: Font = null
	var _font_size: int = 16
	var _small_font_size: int = 14
	var _tiny_font_size: int = 11

	func _ready() -> void:
		_font = ThemeDB.fallback_font

	func _process(delta: float) -> void:
		if viewer and viewer.is_active:
			viewer.process(delta)

	func _draw() -> void:
		if viewer == null or not viewer.is_active:
			return

		var rect: Rect2 = get_rect()
		var w: float = rect.size.x
		var h: float = rect.size.y

		draw_rect(Rect2(0, 0, w, h), viewer.bg_color)

		# 标题
		var col: Color = viewer.draw_color
		var dim: Color = viewer.draw_color_dim
		var gc: Color = viewer.grid_color
		var y: float = MARGIN

		draw_string(_font, Vector2(MARGIN, y + _font_size),
			"CIPHER DECODER", HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, col)
		y += _font_size + 4
		draw_line(Vector2(MARGIN, y), Vector2(w - MARGIN, y), gc, 1.0)
		y += SECTION_GAP

		match viewer.view_mode:
			ViewMode.SELECT:
				_draw_select_menu(y, w, h)
			ViewMode.INPUT:
				_draw_input_mode(y, w, h)
			ViewMode.ANIMATING, ViewMode.RESULT:
				_draw_decode_view(y, w, h)

	# ══════════════════════════════════════════
	#  选择菜单
	# ══════════════════════════════════════════
	func _draw_select_menu(y: float, w: float, _h: float) -> void:
		var col: Color = viewer.draw_color
		var dim: Color = viewer.draw_color_dim
		var wc: Color = viewer.warning_color

		draw_string(_font, Vector2(MARGIN, y + _small_font_size),
			"选择解码方式:", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, dim)
		y += _small_font_size + SECTION_GAP

		for i in range(viewer._menu_items.size()):
			var item: Dictionary = viewer._menu_items[i]
			var is_selected: bool = (i == viewer._menu_index)
			var item_col: Color = col if is_selected else dim
			var prefix: String = "► " if is_selected else "  "
			var num: String = str(i + 1) + ". "

			if is_selected:
				draw_rect(Rect2(MARGIN - 2, y - 2, w - MARGIN * 2 + 4, _small_font_size + 6),
					viewer.highlight_color)

			draw_string(_font, Vector2(MARGIN, y + _small_font_size),
				prefix + num + str(item["name"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, item_col)
			y += _small_font_size + 2

			draw_string(_font, Vector2(MARGIN + 40, y + _tiny_font_size),
				str(item["desc"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, dim * 0.7)
			y += _tiny_font_size + 8

		# 底部说明框
		y += SECTION_GAP
		draw_line(Vector2(MARGIN, y), Vector2(w - MARGIN, y), viewer.grid_color, 1.0)
		y += 8

		var selected_item: Dictionary = viewer._menu_items[viewer._menu_index]
		draw_string(_font, Vector2(MARGIN, y + _small_font_size),
			"选中: " + str(selected_item["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, col)
		y += _small_font_size + 4

		var key_hint: String = str(selected_item.get("key_hint", ""))
		if not key_hint.is_empty():
			draw_string(_font, Vector2(MARGIN, y + _tiny_font_size),
				"密钥: " + key_hint,
				HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, dim)

	# ══════════════════════════════════════════
	#  文本输入模式
	# ══════════════════════════════════════════
	func _draw_input_mode(y: float, w: float, h: float) -> void:
		var col: Color = viewer.draw_color
		var dim: Color = viewer.draw_color_dim

		var cipher_name: String = CipherDecoder.get_type_name(viewer.selected_cipher)
		draw_string(_font, Vector2(MARGIN, y + _small_font_size),
			"解码方式: " + cipher_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, viewer.warning_color)
		y += _small_font_size + SECTION_GAP

		if viewer._input_step == 1:
			draw_string(_font, Vector2(MARGIN, y + _small_font_size),
				"输入密文:", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, col)
			y += _small_font_size + 4
		elif viewer._input_step == 2:
			# 显示已输入的密文
			draw_string(_font, Vector2(MARGIN, y + _small_font_size),
				"密文: " + _truncate(viewer.cipher_input_text, 60),
				HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, dim)
			y += _small_font_size + SECTION_GAP

			var key_hint: String = str(viewer._menu_items[viewer._menu_index].get("key_hint", "密钥"))
			var is_optional: bool = viewer._menu_items[viewer._menu_index].get("optional_key", false) as bool
			var prompt_text: String = "输入密钥 (" + key_hint + "):"
			if is_optional:
				prompt_text = "输入密钥 (" + key_hint + ") [Enter留空=自动/Tab跳过]:"
			draw_string(_font, Vector2(MARGIN, y + _small_font_size),
				prompt_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, col)
			y += _small_font_size + 4

		# 输入框
		var input_box_h: float = minf(h - y - MARGIN * 4, 200.0)
		draw_rect(Rect2(MARGIN, y, w - MARGIN * 2, input_box_h), viewer.grid_color)

		var cursor_ch: String = "█" if viewer._cursor_visible else " "
		var display_text: String = viewer._text_buffer + cursor_ch
		# 简单换行显示
		var max_chars: int = int((w - MARGIN * 2 - 8) / (_small_font_size * 0.6))
		if max_chars < 10:
			max_chars = 10
		var text_y: float = y + 4
		var remaining: String = display_text
		while not remaining.is_empty() and text_y + _small_font_size < y + input_box_h:
			var line_len: int = mini(remaining.length(), max_chars)
			var line: String = remaining.substr(0, line_len)
			remaining = remaining.substr(line_len)
			draw_string(_font, Vector2(MARGIN + 4, text_y + _small_font_size),
				line, HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, col)
			text_y += _small_font_size + 2

	# ══════════════════════════════════════════
	#  解码动画/结果视图
	# ══════════════════════════════════════════
	func _draw_decode_view(y: float, w: float, h: float) -> void:
		var col: Color = viewer.draw_color
		var dim: Color = viewer.draw_color_dim
		var wc: Color = viewer.warning_color

		if viewer.current_result == null:
			return

		var result: CipherDecoder.DecodeResult = viewer.current_result

		# 错误显示
		if not result.success:
			draw_string(_font, Vector2(MARGIN, y + _font_size),
				"ERROR", HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, viewer.error_color)
			y += _font_size + 8
			draw_string(_font, Vector2(MARGIN, y + _small_font_size),
				result.error_message,
				HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, viewer.error_color)
			return

		# 布局：左侧=可视化图表，右侧=步骤日志
		var left_w: float = w * 0.55
		var right_x: float = left_w + MARGIN
		var right_w: float = w - right_x - MARGIN

		# ── 左侧顶部：信息 ──
		var cipher_name: String = CipherDecoder.get_type_name(result.cipher_type)
		draw_string(_font, Vector2(MARGIN, y + _small_font_size),
			cipher_name, HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, wc)

		# 状态
		var status_text: String = ""
		if viewer.view_mode == ViewMode.ANIMATING:
			if viewer._anim_paused:
				status_text = "⏸ PAUSED"
			else:
				status_text = "▶ DECODING... %d/%d" % [viewer._anim_step_index, result.steps.size()]
		else:
			status_text = "✓ COMPLETE"
		var status_w: float = _font.get_string_size(status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size).x
		draw_string(_font, Vector2(left_w - status_w - MARGIN, y + _small_font_size),
			status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size,
			wc if viewer.view_mode == ViewMode.ANIMATING else col)
		y += _small_font_size + 4

		# 进度条
		var progress: float = 0.0
		if result.steps.size() > 0:
			progress = float(viewer._anim_step_index) / float(result.steps.size())
		var bar_w: float = left_w - MARGIN * 2
		draw_rect(Rect2(MARGIN, y, bar_w, 4), dim)
		draw_rect(Rect2(MARGIN, y, bar_w * progress, 4), col)
		y += 8

		# 分隔线
		draw_line(Vector2(left_w, y), Vector2(left_w, h - MARGIN), viewer.grid_color, 1.0)

		# ── 左侧：可视化区域 ──
		var viz_y: float = y
		match result.cipher_type:
			CipherDecoder.CipherType.CAESAR, CipherDecoder.CipherType.ROT13:
				_draw_caesar_visualization(MARGIN, viz_y, left_w - MARGIN * 2, h - viz_y - MARGIN * 4)
			CipherDecoder.CipherType.VIGENERE:
				_draw_vigenere_visualization(MARGIN, viz_y, left_w - MARGIN * 2, h - viz_y - MARGIN * 4)
			CipherDecoder.CipherType.ATBASH:
				_draw_atbash_visualization(MARGIN, viz_y, left_w - MARGIN * 2, h - viz_y - MARGIN * 4)
			CipherDecoder.CipherType.SUBSTITUTION:
				_draw_substitution_visualization(MARGIN, viz_y, left_w - MARGIN * 2, h - viz_y - MARGIN * 4)
			CipherDecoder.CipherType.BASE64:
				_draw_base64_visualization(MARGIN, viz_y, left_w - MARGIN * 2, h - viz_y - MARGIN * 4)
			CipherDecoder.CipherType.MORSE:
				_draw_morse_visualization(MARGIN, viz_y, left_w - MARGIN * 2, h - viz_y - MARGIN * 4)
			CipherDecoder.CipherType.REVERSE:
				_draw_reverse_visualization(MARGIN, viz_y, left_w - MARGIN * 2, h - viz_y - MARGIN * 4)

		# ── 右侧：步骤日志 + 解码结果 ──
		_draw_step_log(right_x, y, right_w, h - y - MARGIN * 2)

	# ══════════════════════════════════════════
	#  凯撒密码可视化：旋转字母环
	# ══════════════════════════════════════════
	func _draw_caesar_visualization(vx: float, vy: float, vw: float, vh: float) -> void:
		var col: Color = viewer.draw_color
		var dim: Color = viewer.draw_color_dim
		var wc: Color = viewer.warning_color
		var hc: Color = viewer.highlight_color
		var result: CipherDecoder.DecodeResult = viewer.current_result

		# 当前步骤信息
		var current_step: CipherDecoder.DecodeStep = null
		if viewer._anim_step_index > 0 and viewer._anim_step_index <= result.steps.size():
			current_step = result.steps[viewer._anim_step_index - 1] as CipherDecoder.DecodeStep
		elif viewer._anim_step_index == 0 and result.steps.size() > 0:
			current_step = result.steps[0] as CipherDecoder.DecodeStep

		var shift: int = int(result.key) if result.key.is_valid_int() else 0

		# ── 双环字母表 ──
		var top_padding: float = 30.0  # ★ 顶部留白，避免圆盘贴着标题
		var ring_cx: float = vx + vw * 0.5
		var outer_r: float = minf(vw * 0.38, vh * 0.3)  # ★ 略微缩小
		var inner_r: float = outer_r * 0.7
		var ring_cy: float = vy + top_padding + outer_r + 14  # ★ 圆心 = 顶部留白 + 半径 + 字母空间

		# 外环（密文字母表 - 原始）
		draw_arc(Vector2(ring_cx, ring_cy), outer_r, 0, TAU, 64, dim, 1.0)
		# 内环（明文字母表 - 偏移后）
		draw_arc(Vector2(ring_cx, ring_cy), inner_r, 0, TAU, 64, col, 1.0)

		for i in range(26):
			var angle: float = -PI / 2.0 + (float(i) / 26.0) * TAU
			var cos_a: float = cos(angle)
			var sin_a: float = sin(angle)

			# 外环字母
			var ox: float = ring_cx + cos_a * (outer_r + 10)
			var oy: float = ring_cy + sin_a * (outer_r + 10)
			var outer_char: String = CipherDecoder.ALPHABET_UPPER[i]
			var outer_col: Color = dim

			# 内环字母（偏移后的明文）
			var shifted_idx: int = (i - shift + 26) % 26
			var ix: float = ring_cx + cos_a * (inner_r - 10)
			var iy: float = ring_cy + sin_a * (inner_r - 10)
			var inner_char: String = CipherDecoder.ALPHABET_UPPER[shifted_idx]
			var inner_col: Color = col * 0.7

			# 高亮当前处理的字符
			if current_step != null:
				if current_step.highlight_row == i:
					outer_col = wc
					# 画连接线
					var lx1: float = ring_cx + cos_a * outer_r
					var ly1: float = ring_cy + sin_a * outer_r
					var lx2: float = ring_cx + cos_a * inner_r
					var ly2: float = ring_cy + sin_a * inner_r
					draw_line(Vector2(lx1, ly1), Vector2(lx2, ly2), wc, 2.0)
				if current_step.highlight_col == shifted_idx:
					inner_col = wc

			var char_w: float = _font.get_string_size(outer_char, HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size).x
			draw_string(_font, Vector2(ox - char_w * 0.5, oy + _tiny_font_size * 0.3),
				outer_char, HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, outer_col)
			draw_string(_font, Vector2(ix - char_w * 0.5, iy + _tiny_font_size * 0.3),
				inner_char, HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, inner_col)

			# 刻度线
			var tick_inner: float = outer_r - 3
			var tick_outer_pos: float = outer_r + 3
			draw_line(
				Vector2(ring_cx + cos_a * tick_inner, ring_cy + sin_a * tick_inner),
				Vector2(ring_cx + cos_a * tick_outer_pos, ring_cy + sin_a * tick_outer_pos),
				dim * 0.5, 1.0)

		# 环标签
		draw_string(_font, Vector2(ring_cx - 30, ring_cy - outer_r - 16),
			"CIPHER", HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, dim)
		draw_string(_font, Vector2(ring_cx - 24, ring_cy),
			"PLAIN", HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, col * 0.6)

		# 偏移值
		var shift_y: float = ring_cy + outer_r + 24
		draw_string(_font, Vector2(vx, shift_y + _small_font_size),
			"SHIFT: " + str(shift),
			HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, wc)

		# 自动检测提示
		if result.metadata.has("auto_detected") and result.metadata["auto_detected"]:
			draw_string(_font, Vector2(vx, shift_y + _small_font_size + 16),
				"(频率分析自动检测)",
				HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, dim)

		# ── 当前字符转换展示 ──
		if current_step != null and CipherDecoder.ALPHABET_UPPER.find(current_step.source_char.to_upper()) >= 0:
			var demo_y: float = shift_y + 40
			var arrow_text: String = "'%s'  ──[偏移%d]──►  '%s'" % [current_step.source_char, shift, current_step.result_char]
			draw_string(_font, Vector2(vx, demo_y + _font_size),
				arrow_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, col)

	# ══════════════════════════════════════════
	#  维吉尼亚密码可视化：Tabula Recta
	# ══════════════════════════════════════════
	func _draw_vigenere_visualization(vx: float, vy: float, vw: float, vh: float) -> void:
		var col: Color = viewer.draw_color
		var dim: Color = viewer.draw_color_dim
		var wc: Color = viewer.warning_color
		var hc: Color = viewer.highlight_color
		var result: CipherDecoder.DecodeResult = viewer.current_result

		var current_step: CipherDecoder.DecodeStep = null
		if viewer._anim_step_index > 0 and viewer._anim_step_index <= result.steps.size():
			current_step = result.steps[viewer._anim_step_index - 1] as CipherDecoder.DecodeStep

		draw_string(_font, Vector2(vx, vy + _small_font_size),
			"TABULA RECTA", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, wc)
		vy += _small_font_size + 6

		# 密钥显示
		draw_string(_font, Vector2(vx, vy + _tiny_font_size),
			"KEY: " + result.key.to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, col)
		vy += _tiny_font_size + 8

		# Tabula Recta 网格
		# 根据可用空间计算单元格大小
		var cell_size: float = minf((vw - 20) / 27.0, (vh - (vy - viewer.draw_color.a) - 60) / 27.0)
		cell_size = minf(cell_size, 16.0)
		cell_size = maxf(cell_size, 8.0)
		var font_sz: int = maxi(int(cell_size * 0.7), 7)

		var table_x: float = vx + 4
		var table_y: float = vy

		# 高亮行/列
		var hl_row: int = -1
		var hl_col: int = -1
		var hl_result_col: int = -1
		if current_step != null:
			hl_row = current_step.highlight_row
			hl_col = current_step.highlight_col
			hl_result_col = int(current_step.extra.get("tabula_result_col", -1))

		# 列头（密文字母）
		for c in range(26):
			var cx: float = table_x + (c + 1) * cell_size
			var ch: String = CipherDecoder.ALPHABET_UPPER[c]
			var c_col: Color = wc if c == hl_col else dim * 0.8
			if c == hl_col:
				draw_rect(Rect2(cx, table_y, cell_size, cell_size), hc)
			draw_string(_font, Vector2(cx + 1, table_y + font_sz),
				ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, c_col)

		# 行（密钥偏移）
		var visible_rows: int = mini(26, int((vh - (table_y - vy) - cell_size - 20) / cell_size))
		for r in range(visible_rows):
			var ry: float = table_y + (r + 1) * cell_size
			var row_char: String = CipherDecoder.ALPHABET_UPPER[r]
			var r_col: Color = wc if r == hl_row else dim * 0.8

			# 行头
			if r == hl_row:
				draw_rect(Rect2(table_x, ry, cell_size, cell_size), hc)
			draw_string(_font, Vector2(table_x + 1, ry + font_sz),
				row_char, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, r_col)

			# 网格内容
			for c in range(26):
				var cx2: float = table_x + (c + 1) * cell_size
				var cell_val: int = (r + c) % 26
				var cell_char: String = CipherDecoder.ALPHABET_UPPER[cell_val]
				var cell_col: Color = dim * 0.4

				# 高亮：当前行列交叉
				if r == hl_row and c == hl_col:
					draw_rect(Rect2(cx2, ry, cell_size, cell_size), Color(wc.r, wc.g, wc.b, 0.4))
					cell_col = wc
				elif r == hl_row or c == hl_col:
					cell_col = dim * 0.7
				# 高亮结果位置
				if r == hl_row and cell_val == hl_result_col and hl_result_col >= 0:
					draw_rect(Rect2(cx2, ry, cell_size, cell_size), Color(col.r, col.g, col.b, 0.3))
					cell_col = col

				draw_string(_font, Vector2(cx2 + 1, ry + font_sz),
					cell_char, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, cell_col)

		# 当前步骤说明
		if current_step != null:
			var info_y: float = table_y + (visible_rows + 2) * cell_size
			if info_y + _small_font_size < vy + vh:
				draw_string(_font, Vector2(vx, info_y + _small_font_size),
					current_step.description,
					HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, col)

	# ══════════════════════════════════════════
	#  Atbash 可视化：镜像字母对照
	# ══════════════════════════════════════════
	func _draw_atbash_visualization(vx: float, vy: float, vw: float, vh: float) -> void:
		var col: Color = viewer.draw_color
		var dim: Color = viewer.draw_color_dim
		var wc: Color = viewer.warning_color
		var result: CipherDecoder.DecodeResult = viewer.current_result

		var current_step: CipherDecoder.DecodeStep = null
		if viewer._anim_step_index > 0 and viewer._anim_step_index <= result.steps.size():
			current_step = result.steps[viewer._anim_step_index - 1] as CipherDecoder.DecodeStep

		draw_string(_font, Vector2(vx, vy + _small_font_size),
			"ATBASH MIRROR", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, wc)
		vy += _small_font_size + 12

		# 双行字母对照表
		var cell_w: float = minf((vw - 8) / 26.0, 20.0)
		var row_h: float = 24.0
		var table_x: float = vx + 4

		# 上行：原始字母表 A-Z
		draw_string(_font, Vector2(vx, vy + _tiny_font_size),
			"PLAIN:", HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, dim)
		vy += _tiny_font_size + 4

		for i in range(26):
			var cx: float = table_x + i * cell_w
			var ch: String = CipherDecoder.ALPHABET_UPPER[i]
			var ch_col: Color = dim

			if current_step != null and current_step.highlight_row == i:
				draw_rect(Rect2(cx, vy - 2, cell_w, row_h), viewer.highlight_color)
				ch_col = wc

			draw_string(_font, Vector2(cx + 2, vy + _tiny_font_size),
				ch, HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, ch_col)

		vy += row_h

		# 连接箭头
		for i in range(26):
			var cx: float = table_x + i * cell_w + cell_w * 0.5
			var mirror_i: int = 25 - i
			var mx: float = table_x + mirror_i * cell_w + cell_w * 0.5

			var arrow_col: Color = dim * 0.3
			if current_step != null and (current_step.highlight_row == i or current_step.highlight_col == i):
				arrow_col = wc * 0.6
				draw_line(Vector2(cx, vy - 4), Vector2(mx, vy + 8), arrow_col, 1.5)
			# 只画高亮的箭头，避免混乱

		draw_string(_font, Vector2(vx + vw * 0.45, vy + _tiny_font_size * 0.5),
			"↕ MIRROR ↕", HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, dim)
		vy += 16

		# 下行：镜像字母表 Z-A
		draw_string(_font, Vector2(vx, vy + _tiny_font_size),
			"CIPHER:", HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, dim)
		vy += _tiny_font_size + 4

		for i in range(26):
			var cx: float = table_x + i * cell_w
			var mirror_ch: String = CipherDecoder.ALPHABET_UPPER[25 - i]
			var ch_col: Color = dim

			if current_step != null and current_step.highlight_col == (25 - i):
				draw_rect(Rect2(cx, vy - 2, cell_w, row_h), viewer.highlight_color)
				ch_col = col

			draw_string(_font, Vector2(cx + 2, vy + _tiny_font_size),
				mirror_ch, HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, ch_col)

		vy += row_h + 16

		# 当前字符转换
		if current_step != null:
			draw_string(_font, Vector2(vx, vy + _font_size),
				current_step.description,
				HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, col)

	# ══════════════════════════════════════════
	#  替换密码可视化：映射表
	# ══════════════════════════════════════════
	func _draw_substitution_visualization(vx: float, vy: float, vw: float, vh: float) -> void:
		var col: Color = viewer.draw_color
		var dim: Color = viewer.draw_color_dim
		var wc: Color = viewer.warning_color
		var result: CipherDecoder.DecodeResult = viewer.current_result

		var current_step: CipherDecoder.DecodeStep = null
		if viewer._anim_step_index > 0 and viewer._anim_step_index <= result.steps.size():
			current_step = result.steps[viewer._anim_step_index - 1] as CipherDecoder.DecodeStep

		draw_string(_font, Vector2(vx, vy + _small_font_size),
			"SUBSTITUTION MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, wc)
		vy += _small_font_size + 8

		var cell_w: float = minf((vw - 8) / 26.0, 20.0)
		var row_h: float = 20.0
		var table_x: float = vx + 4

		# 标准字母表行
		draw_string(_font, Vector2(vx, vy + _tiny_font_size),
			"STD:", HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, dim)
		vy += _tiny_font_size + 2

		for i in range(26):
			var cx: float = table_x + i * cell_w
			var ch: String = CipherDecoder.ALPHABET_UPPER[i]
			var ch_col: Color = dim
			if current_step != null and current_step.highlight_col == i:
				draw_rect(Rect2(cx, vy - 1, cell_w, row_h), viewer.highlight_color)
				ch_col = col
			draw_string(_font, Vector2(cx + 2, vy + _tiny_font_size),
				ch, HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, ch_col)
		vy += row_h

		# 箭头行
		for i in range(26):
			var cx: float = table_x + i * cell_w + cell_w * 0.5 - 2
			draw_string(_font, Vector2(cx, vy + _tiny_font_size),
				"↑", HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, dim * 0.5)
		vy += _tiny_font_size + 4

		# 密钥字母表行
		draw_string(_font, Vector2(vx, vy + _tiny_font_size),
			"KEY:", HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, dim)
		vy += _tiny_font_size + 2

		var upper_key: String = result.key.to_upper()
		for i in range(mini(26, upper_key.length())):
			var cx: float = table_x + i * cell_w
			var ch: String = upper_key[i]
			var ch_col: Color = dim
			if current_step != null and current_step.highlight_row == i:
				draw_rect(Rect2(cx, vy - 1, cell_w, row_h), Color(wc.r, wc.g, wc.b, 0.25))
				ch_col = wc
			draw_string(_font, Vector2(cx + 2, vy + _tiny_font_size),
				ch, HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, ch_col)
		vy += row_h + 16

		if current_step != null:
			draw_string(_font, Vector2(vx, vy + _small_font_size),
				current_step.description,
				HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, col)

	# ══════════════════════════════════════════
	#  Base64 可视化：二进制分组
	# ══════════════════════════════════════════
	func _draw_base64_visualization(vx: float, vy: float, vw: float, vh: float) -> void:
		var col: Color = viewer.draw_color
		var dim: Color = viewer.draw_color_dim
		var wc: Color = viewer.warning_color
		var result: CipherDecoder.DecodeResult = viewer.current_result

		var current_step: CipherDecoder.DecodeStep = null
		if viewer._anim_step_index > 0 and viewer._anim_step_index <= result.steps.size():
			current_step = result.steps[viewer._anim_step_index - 1] as CipherDecoder.DecodeStep

		draw_string(_font, Vector2(vx, vy + _small_font_size),
			"BASE64 DECODE", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, wc)
		vy += _small_font_size + 8

		# Base64 字符集参考
		draw_string(_font, Vector2(vx, vy + _tiny_font_size),
			"CHARSET: A-Z a-z 0-9 + /",
			HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, dim)
		vy += _tiny_font_size + 4
		draw_string(_font, Vector2(vx, vy + _tiny_font_size),
			"每4字符 = 3字节 (6bit × 4 = 24bit = 8bit × 3)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, dim)
		vy += _tiny_font_size + 12

		if current_step == null:
			return

		# 当前组的可视化
		var chunk: String = current_step.source_char
		var binary_str: String = str(current_step.extra.get("binary", ""))
		var decoded: String = current_step.result_char

		# 输入字符
		draw_string(_font, Vector2(vx, vy + _font_size),
			"INPUT:  " + chunk,
			HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, wc)
		vy += _font_size + 8

		# 每个字符的6位二进制
		var b64_chars: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
		var bit_x: float = vx + 8
		for i in range(chunk.length()):
			var ch: String = chunk[i]
			var val: int = b64_chars.find(ch)
			if ch == "=":
				val = 0
			var bits: String = ""
			if val >= 0:
				for b in range(5, -1, -1):
					bits += "1" if (val >> b) & 1 else "0"
			else:
				bits = "??????"

			draw_string(_font, Vector2(bit_x, vy + _small_font_size),
				"'%s' = %d" % [ch, val],
				HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, col)
			vy += _small_font_size + 2

			# 绘制比特方块
			for b_idx in range(6):
				var bx: float = bit_x + 80 + b_idx * 16
				var bit_on: bool = bits[b_idx] == "1"
				var box_col: Color = col if bit_on else dim * 0.3
				draw_rect(Rect2(bx, vy - _small_font_size + 2, 12, 12), box_col)
				draw_string(_font, Vector2(bx + 2, vy),
					bits[b_idx], HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size,
					Color.BLACK if bit_on else dim)
			vy += 4

		vy += 8

		# 重组为8位字节
		draw_string(_font, Vector2(vx, vy + _small_font_size),
			"BINARY: " + binary_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, dim)
		vy += _small_font_size + 4

		# 箭头
		draw_string(_font, Vector2(vx + 40, vy + _small_font_size),
			"▼ 重组为 8-bit 字节 ▼",
			HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, wc)
		vy += _small_font_size + 8

		# 输出
		draw_string(_font, Vector2(vx, vy + _font_size),
			"OUTPUT: " + decoded,
			HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, col)

	# ══════════════════════════════════════════
	#  摩斯电码可视化：点划图形
	# ══════════════════════════════════════════
	func _draw_morse_visualization(vx: float, vy: float, vw: float, vh: float) -> void:
		var col: Color = viewer.draw_color
		var dim: Color = viewer.draw_color_dim
		var wc: Color = viewer.warning_color
		var result: CipherDecoder.DecodeResult = viewer.current_result

		var current_step: CipherDecoder.DecodeStep = null
		if viewer._anim_step_index > 0 and viewer._anim_step_index <= result.steps.size():
			current_step = result.steps[viewer._anim_step_index - 1] as CipherDecoder.DecodeStep

		draw_string(_font, Vector2(vx, vy + _small_font_size),
			"MORSE CODE", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, wc)
		vy += _small_font_size + 8

		# 摩斯码参考表（部分）
		var ref_chars: Array[String] = ["A","B","C","D","E","F","G","H","I","J","K","L","M",
										"N","O","P","Q","R","S","T","U","V","W","X","Y","Z"]
		var col_count: int = 4
		var row_count: int = ceili(ref_chars.size() / float(col_count))
		var col_w: float = vw / float(col_count)

		for idx in range(ref_chars.size()):
			var ch: String = ref_chars[idx]
			var morse_code: String = CipherDecoder.MORSE_TABLE.get(ch, "")
			var rx: float = vx + (idx % col_count) * col_w
			var ry: float = vy + (idx / col_count) * (_tiny_font_size + 3)

			var ref_col: Color = dim * 0.6
			if current_step != null and current_step.result_char.to_upper() == ch:
				ref_col = wc

			draw_string(_font, Vector2(rx, ry + _tiny_font_size),
				ch + " " + morse_code,
				HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, ref_col)

		vy += row_count * (_tiny_font_size + 3) + 12

		# 当前字符的图形化展示
		if current_step != null:
			draw_line(Vector2(vx, vy), Vector2(vx + vw, vy), viewer.grid_color, 1.0)
			vy += 8

			draw_string(_font, Vector2(vx, vy + _font_size),
				current_step.source_char + "  →  " + current_step.result_char,
				HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, col)
			vy += _font_size + 8

			# 绘制点和划的图形
			var morse: String = current_step.source_char
			var dot_x: float = vx + 8
			var dot_y: float = vy + 6
			var element_h: float = 12.0

			for ch in morse:
				if ch == ".":
					draw_rect(Rect2(dot_x, dot_y, element_h, element_h), col)
					dot_x += element_h + 6
				elif ch == "-":
					draw_rect(Rect2(dot_x, dot_y, element_h * 3, element_h), col)
					dot_x += element_h * 3 + 6
				elif ch == " ":
					dot_x += element_h * 2

	# ══════════════════════════════════════════
	#  反转可视化
	# ══════════════════════════════════════════
	func _draw_reverse_visualization(vx: float, vy: float, vw: float, vh: float) -> void:
		var col: Color = viewer.draw_color
		var dim: Color = viewer.draw_color_dim
		var wc: Color = viewer.warning_color
		var result: CipherDecoder.DecodeResult = viewer.current_result

		draw_string(_font, Vector2(vx, vy + _small_font_size),
			"STRING REVERSE", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, wc)
		vy += _small_font_size + 16

		var input_text: String = result.input_text
		var output_text: String = result.output_text
		var max_display: int = mini(input_text.length(), int(vw / 18.0))
		var cell_w: float = minf(vw / float(max_display + 1), 20.0)

		# 原始字符串
		draw_string(_font, Vector2(vx, vy + _tiny_font_size),
			"INPUT:", HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, dim)
		vy += _tiny_font_size + 4

		for i in range(mini(input_text.length(), max_display)):
			var cx: float = vx + i * cell_w
			draw_rect(Rect2(cx, vy, cell_w - 2, 20), viewer.grid_color)
			draw_string(_font, Vector2(cx + 3, vy + _small_font_size),
				input_text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, col)

			# 画交叉箭头
			var target_i: int = input_text.length() - 1 - i
			if target_i < max_display:
				var tx: float = vx + target_i * cell_w + cell_w * 0.5
				var sx: float = cx + cell_w * 0.5
				var arrow_col: Color = Color(col.r, col.g, col.b, 0.15)
				draw_line(Vector2(sx, vy + 22), Vector2(tx, vy + 50), arrow_col, 1.0)
		vy += 56

		# 结果字符串
		draw_string(_font, Vector2(vx, vy + _tiny_font_size),
			"OUTPUT:", HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, dim)
		vy += _tiny_font_size + 4

		for i in range(mini(output_text.length(), max_display)):
			var cx: float = vx + i * cell_w
			draw_rect(Rect2(cx, vy, cell_w - 2, 20), viewer.grid_color)
			draw_string(_font, Vector2(cx + 3, vy + _small_font_size),
				output_text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, wc)

	# ══════════════════════════════════════════
	#  步骤日志（右侧面板）
	# ══════════════════════════════════════════
	func _draw_step_log(rx: float, ry: float, rw: float, rh: float) -> void:
		var col: Color = viewer.draw_color
		var dim: Color = viewer.draw_color_dim
		var wc: Color = viewer.warning_color
		var result: CipherDecoder.DecodeResult = viewer.current_result
		if result == null:
			return

		var y: float = ry

		# 原文
		draw_string(_font, Vector2(rx, y + _tiny_font_size),
			"INPUT:", HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, dim)
		y += _tiny_font_size + 2
		var input_display: String = _truncate(result.input_text, int(rw / (_tiny_font_size * 0.6)))
		draw_string(_font, Vector2(rx, y + _tiny_font_size),
			input_display, HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, col * 0.7)
		y += _tiny_font_size + 8

		# 解码结果（动态更新）
		draw_string(_font, Vector2(rx, y + _tiny_font_size),
			"OUTPUT:", HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, dim)
		y += _tiny_font_size + 2

		var decoded_display: String = viewer._anim_decoded_so_far
		if decoded_display.length() > int(rw / (_tiny_font_size * 0.6)):
			decoded_display = "..." + decoded_display.right(int(rw / (_tiny_font_size * 0.6)) - 3)
		draw_string(_font, Vector2(rx, y + _small_font_size),
			decoded_display, HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, col)
		y += _small_font_size + 8

		draw_line(Vector2(rx, y), Vector2(rx + rw, y), viewer.grid_color, 1.0)
		y += 4

		# 步骤标题
		draw_string(_font, Vector2(rx, y + _tiny_font_size),
			"STEPS: %d / %d" % [viewer._anim_step_index, result.steps.size()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, dim)
		if viewer.view_mode == ViewMode.ANIMATING:
			var speed_text: String = "SPEED: %.0fms" % (viewer._anim_speed * 1000)
			var speed_w: float = _font.get_string_size(speed_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size).x
			draw_string(_font, Vector2(rx + rw - speed_w, y + _tiny_font_size),
				speed_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, dim)
		y += _tiny_font_size + 4

		# 步骤列表
		var log_area_h: float = rh - (y - ry)
		draw_rect(Rect2(rx, y, rw, log_area_h), Color(viewer.grid_color.r, viewer.grid_color.g, viewer.grid_color.b, 0.1))

		var line_h: float = _tiny_font_size + 3
		var visible_count: int = int(log_area_h / line_h)
		var scroll_offset: int = viewer._log_scroll
		var log_y: float = y + 2

		for i in range(visible_count):
			var step_idx: int = scroll_offset + i
			if step_idx >= viewer._anim_step_index:
				break
			if step_idx >= result.steps.size():
				break

			var step: CipherDecoder.DecodeStep = result.steps[step_idx] as CipherDecoder.DecodeStep
			var is_current: bool = (step_idx == viewer._anim_step_index - 1)

			var line_col: Color = col if is_current else dim * 0.7
			if is_current:
				draw_rect(Rect2(rx, log_y - 1, rw, line_h), viewer.highlight_color * 0.5)

			var step_num: String = "%03d" % step_idx
			var step_text: String = step_num + " " + _truncate(step.description, int(rw / (_tiny_font_size * 0.55)) - 5)

			draw_string(_font, Vector2(rx + 2, log_y + _tiny_font_size),
				step_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, line_col)
			log_y += line_h

		# 滚动指示
		var total_lines: int = viewer._anim_step_index
		if total_lines > visible_count:
			var scroll_ratio: float = float(scroll_offset) / float(maxi(total_lines - visible_count, 1))
			var bar_h: float = maxf(log_area_h * (float(visible_count) / float(total_lines)), 10.0)
			var bar_y_pos: float = y + scroll_ratio * (log_area_h - bar_h)
			draw_rect(Rect2(rx + rw - 3, bar_y_pos, 3, bar_h), dim)

	# ══════════════════════════════════════════
	#  工具
	# ══════════════════════════════════════════
	func _truncate(text: String, max_len: int) -> String:
		if text.length() <= max_len:
			return text
		return text.left(max_len - 3) + "..."
