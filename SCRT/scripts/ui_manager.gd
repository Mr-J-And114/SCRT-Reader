# ============================================================
# ui_manager.gd - UI 初始化与背景管理
# 负责：背景图加载、Shader应用、各UI组件样式初始化、鼠标光标
# ============================================================
class_name UIManager
extends RefCounted

# ★ Bold 字体路径常量（使用 SemiBold 替代伪粗体，防止发光过亮）
const BOLD_FONT_PATH := "res://fonts/SarasaMonoSC-SemiBold.ttf"
const TERMINAL_FONT := preload("res://fonts/SarasaMonoSC-Regular.ttf")
const TERMINAL_BOLD := preload("res://fonts/SarasaMonoSC-SemiBold.ttf")

## 自绘／Label 的纯文本终端标记；用于 BBCode 时须先转义方括号。
static func terminal_status(tag: String, label: String) -> String:
	return "[%s] %s" % [tag, label]

static func terminal_section(title: String) -> String:
	return "[ %s ]" % title

## 玩家控件共同皮肤；独立覆盖层也使用，避免原生默认蓝选区。
static func create_terminal_theme(colors = null, font_size: int = 20) -> Theme:
	var t = colors if colors != null else ThemeManager.current
	var skin := Theme.new()
	skin.default_font = TERMINAL_FONT
	skin.default_font_size = font_size
	var primary: Color = t.primary
	var palette := {}
	for token in ["primary", "secondary", "muted", "dim", "success", "warning", "error", "info", "border"]:
		palette[token] = t.get(token)
	skin.set_meta("terminal_palette", palette)
	for type in ["Label", "Button", "LineEdit", "TextEdit", "RichTextLabel", "PopupMenu"]:
		skin.set_color("font_color", type, primary)
		skin.set_color("font_disabled_color", type, t.dim)
		skin.set_color("font_selected_color", type, primary)
		skin.set_color("selection_color", type, Color(primary, 0.30))
		skin.set_color("caret_color", type, primary)
		skin.set_color("font_placeholder_color", type, Color(primary, 0.35))
	for type in ["LineEdit", "TextEdit"]:
		for state in ["normal", "read_only"]:
			skin.set_stylebox(state, type, terminal_panel(t, true))
		skin.set_stylebox("focus", type, terminal_focus(t))
	for name in ["normal_font", "italics_font", "mono_font"]:
		skin.set_font(name, "RichTextLabel", TERMINAL_FONT)
	for name in ["bold_font", "bold_italics_font"]:
		skin.set_font(name, "RichTextLabel", TERMINAL_BOLD)
	skin.set_color("default_color", "RichTextLabel", primary)
	skin.set_stylebox("normal", "RichTextLabel", terminal_panel(t))
	skin.set_stylebox("focus", "RichTextLabel", terminal_focus(t))
	for type in ["Panel", "PanelContainer"]:
		skin.set_stylebox("panel", type, terminal_panel(t))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style := terminal_panel(t, true)
		var active: bool = state in ["hover", "pressed", "hover_pressed"]
		style.bg_color = Color(primary, 0.20 if active else (0.0 if state == "disabled" else 0.08))
		style.border_color = Color(primary, 0.8 if active else 0.35)
		skin.set_stylebox(state, "Button", style)
	for state in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		skin.set_color(state, "Button", primary)
	skin.set_stylebox("focus", "Button", terminal_focus(t))
	var menu_style := terminal_panel(t, true)
	menu_style.bg_color = Color(t.bg, 0.12)
	skin.set_stylebox("panel", "PopupMenu", menu_style)
	var menu_hover := terminal_panel(t)
	menu_hover.bg_color = Color(primary, 0.20)
	skin.set_stylebox("hover", "PopupMenu", menu_hover)
	skin.set_color("font_hover_color", "PopupMenu", primary)
	for type in ["VScrollBar", "HScrollBar"]:
		skin.set_stylebox("scroll", type, terminal_panel(t))
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			var grab := terminal_panel(t)
			grab.bg_color = Color(primary, 0.4 if state == "grabber" else 0.6)
			grab.set_content_margin_all(3)
			skin.set_stylebox(state, type, grab)
	return skin

static func terminal_panel(colors = null, border: bool = false) -> StyleBoxFlat:
	var t = colors if colors != null else ThemeManager.current
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = t.border
	style.set_border_width_all(1 if border else 0)
	style.set_content_margin_all(8 if border else 0)
	return style

static func terminal_focus(colors = null) -> StyleBoxFlat:
	var t = colors if colors != null else ThemeManager.current
	var style := terminal_panel(t, true)
	style.border_color = Color(t.primary, 0.8)
	style.set_content_margin_all(0)
	return style

static func apply_terminal_theme(root: Control, font_size: int = 0) -> void:
	var base_size := font_size if font_size > 0 else root.get_theme_font_size("font_size")
	root.theme = create_terminal_theme(ThemeManager.current, base_size)

static func style_terminal_button(button: Button, colors = null) -> void:
	var t = colors if colors != null else ThemeManager.current
	var skin := create_terminal_theme(t, button.get_theme_font_size("font_size"))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, skin.get_stylebox(state, "Button"))
	for name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(name, skin.get_color(name, "Button"))

static func setup_text_selection(control: Control, colors = null) -> void:
	var t = colors if colors != null else ThemeManager.current
	control.add_theme_color_override("selection_color", Color(t.primary, 0.30))
	control.add_theme_color_override("font_selected_color", t.primary)
	if control.has_method("get_menu"):
		var menu: PopupMenu = control.call("get_menu")
		menu.theme = create_terminal_theme(t, control.get_theme_font_size("font_size"))

## 刷新已创建的覆盖层及本地覆盖值；不改语义色，也不触碰背景材质。
static func refresh_terminal_tree(node: Node, previous_palette: Dictionary) -> void:
	var t = ThemeManager.current
	if node is Control:
		if node.theme != null and node.theme.has_meta("terminal_palette"):
			apply_terminal_theme(node, node.theme.default_font_size)
		for name in ["font_color", "default_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color", "font_placeholder_color", "caret_color"]:
			if node.has_theme_color_override(name):
				node.add_theme_color_override(name, _refresh_semantic_color(node.get_theme_color(name), previous_palette, t))
		for name in ["panel", "normal", "hover", "pressed", "hover_pressed", "disabled", "focus", "read_only"]:
			if node.has_theme_stylebox_override(name):
				var style := node.get_theme_stylebox(name) as StyleBoxFlat
				if style:
					style.bg_color = _refresh_semantic_color(style.bg_color, previous_palette, t)
					style.border_color = _refresh_semantic_color(style.border_color, previous_palette, t)
		if node is RichTextLabel or node is LineEdit or node is TextEdit:
			setup_text_selection(node, t)
	for child in node.get_children():
		refresh_terminal_tree(child, previous_palette)

static func _refresh_semantic_color(color: Color, previous_palette: Dictionary, colors) -> Color:
	for token in previous_palette:
		var previous: Color = previous_palette[token]
		if Vector3(color.r, color.g, color.b).is_equal_approx(Vector3(previous.r, previous.g, previous.b)):
			return Color(colors.get(token), color.a)
	return color

# ============================================================
# 背景初始化
# ============================================================
static func setup_background(parent: Control, game_root_dir: String) -> TextureRect:
	var background := TextureRect.new()
	background.name = "Background"
	parent.add_child(background)
	parent.move_child(background, 0)

	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg_path: String = game_root_dir + "background.png"
	var tex: Texture2D = null

	if FileAccess.file_exists(bg_path):
		var image := Image.new()
		var err := image.load(bg_path)
		if err == OK:
			tex = ImageTexture.create_from_image(image)
			print("[UI] 已加载外部背景图: " + bg_path)
		else:
			print("[UI] 背景图加载失败: " + str(err))

	if tex == null:
		var t := ThemeManager.current
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(t.bg if t != null else Color(0.02, 0.04, 0.02, 1.0))
		tex = ImageTexture.create_from_image(image)
		print("[UI] 使用默认深色背景")

	background.texture = tex

	var shader_path: String = "res://shaders/background_vignette.gdshader"
	if not ResourceLoader.exists(shader_path):
		shader_path = "res://background_vignette.gdshader"

	if ResourceLoader.exists(shader_path):
		var shader: Shader = load(shader_path)
		var mat := ShaderMaterial.new()
		mat.shader = shader

		var t := ThemeManager.current
		mat.set_shader_parameter("vignette_strength", 0.8)
		mat.set_shader_parameter("vignette_radius", 0.9)
		mat.set_shader_parameter("glow_strength", 0.08)
		mat.set_shader_parameter("glow_radius", 0.4)
		mat.set_shader_parameter("brightness", 0.7)
		if t != null:
			mat.set_shader_parameter("tint_color", Color(t.primary.r * 0.15, t.primary.g * 0.15, t.primary.b * 0.15, 0.15))
		else:
			mat.set_shader_parameter("tint_color", Color(0.1, 0.3, 0.1, 0.15))
		background.material = mat
		print("[UI] 背景Shader已应用")
	else:
		print("[UI] 未找到背景Shader文件")

	return background

# ============================================================
# 主内容区透明化
# ============================================================
static func setup_main_content(parent: Control, main_content: Control) -> void:
	apply_terminal_theme(parent)
	if main_content == null:
		return
	parent.move_child(main_content, parent.get_child_count() - 1)

	if main_content is Control:
		var transparent_style := StyleBoxFlat.new()
		transparent_style.bg_color = Color(0, 0, 0, 0)
		transparent_style.set_border_width_all(0)
		main_content.add_theme_stylebox_override("panel", transparent_style)

# ============================================================
# 状态栏样式（只有底部边框线，模拟终端分隔）
# ============================================================
static func setup_status_frame(status_frame: PanelContainer) -> void:
	var t := ThemeManager.current
	var style := StyleBoxFlat.new()
	style.bg_color = t.bg_panel if t != null else Color(0.0, 0.04, 0.0, 0.9)
	var border_color: Color = t.border if t != null else Color(0.2, 0.6, 0.2, 0.4)
	style.border_color = border_color
	style.border_width_bottom = 1
	style.border_width_top = 0
	style.border_width_left = 0
	style.border_width_right = 0
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	status_frame.add_theme_stylebox_override("panel", style)

# ============================================================
# 路径标签样式
# ============================================================
static func setup_path_label(path_label: Label) -> void:
	var t := ThemeManager.current
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0, 0, 0, 0)
	style.set_border_width_all(0)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	path_label.add_theme_stylebox_override("normal", style)
	if t != null:
		path_label.add_theme_color_override("font_color", t.primary)

# ============================================================
# 邮件图标样式
# ============================================================
static func setup_mail_icon(mail_icon: Label) -> void:
	var t := ThemeManager.current
	var style := StyleBoxFlat.new()
	style.bg_color = Color(t.bg.r, t.bg.g, t.bg.b, 0.6) if t != null else Color(0.0, 0.03, 0.0, 0.6)
	style.border_color = Color(t.border.r, t.border.g, t.border.b, 0.35) if t != null else Color(0.2, 0.6, 0.2, 0.35)
	style.set_border_width_all(1)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	mail_icon.add_theme_stylebox_override("normal", style)
	if t != null:
		mail_icon.add_theme_color_override("font_color", t.primary)

# ============================================================
# 输入区外框样式（只有顶部边框线）
# ============================================================
static func setup_input_frame(input_frame: PanelContainer) -> void:
	var t := ThemeManager.current
	var style := StyleBoxFlat.new()
	style.bg_color = t.bg_panel if t != null else Color(0.0, 0.04, 0.0, 0.9)
	var border_color: Color = t.border if t != null else Color(0.2, 0.6, 0.2, 0.4)
	style.border_color = border_color
	style.border_width_top = 1
	style.border_width_bottom = 0
	style.border_width_left = 0
	style.border_width_right = 0
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	input_frame.add_theme_stylebox_override("panel", style)

# ============================================================
# 输入框样式
# ============================================================
static func setup_input_field(input_field: LineEdit) -> void:
	setup_ime_guard(input_field)
	setup_text_selection(input_field)
	var t := ThemeManager.current
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0, 0, 0, 0)
	style.set_border_width_all(0)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	input_field.add_theme_stylebox_override("normal", style)
	input_field.add_theme_stylebox_override("focus", style.duplicate())
	if t != null:
		input_field.add_theme_color_override("font_color", t.input_text)
		input_field.add_theme_color_override("caret_color", t.primary)
		input_field.add_theme_color_override("selection_color", Color(t.primary.r, t.primary.g, t.primary.b, 0.3))
		var placeholder_color := Color(t.primary.r, t.primary.g, t.primary.b, 0.35)
		input_field.add_theme_color_override("font_placeholder_color", placeholder_color)

## Windows 中断组合输入时可能不发送最后一次 IME 更新；同步空组合状态。
## 不用 apply_ime，避免把尚未确认的拼音写入正文。
static func sync_ime(input: Control) -> void:
	if input.call("has_ime_text") and DisplayServer.has_feature(DisplayServer.FEATURE_IME):
		if DisplayServer.ime_get_text().is_empty():
			input.call("cancel_ime")
			input.queue_redraw()

static func setup_ime_guard(input: Control) -> void:
	if input.has_node("ImeGuard"):
		return
	var guard := _ImeGuard.new()
	guard.name = "ImeGuard"
	guard.field = input
	input.add_child(guard)

class _ImeGuard extends Node:
	var field: Control
	var empty_frames := 0
	func _process(_delta: float) -> void:
		if not field.call("has_ime_text") or not DisplayServer.has_feature(DisplayServer.FEATURE_IME):
			empty_frames = 0
			return
		# 连续两帧为空才清理，避开正常中文上屏的同帧事件顺序。
		if DisplayServer.ime_get_text().is_empty():
			empty_frames += 1
			if empty_frames >= 2:
				UIManager.sync_ime(field)
		else:
			empty_frames = 0

# ============================================================
# 输出文本框初始化
# ★ 关键：设置真正的 Bold 字体，避免 Godot 伪粗体导致的发光过亮
# ============================================================
static func setup_output_text(output_text: RichTextLabel) -> void:
	setup_text_selection(output_text)
	var t := ThemeManager.current
	output_text.bbcode_enabled = true
	output_text.selection_enabled = true
	output_text.meta_underlined = true
	output_text.mouse_filter = Control.MOUSE_FILTER_STOP
	output_text.focus_mode = Control.FOCUS_CLICK
	if t != null:
		output_text.add_theme_color_override("default_color", t.secondary)
		# ★ 确保粗体文字颜色与普通文字一致，不会被字体变化影响
		output_text.add_theme_color_override("font_color", t.secondary)
		output_text.add_theme_color_override("selection_color", Color(t.primary.r, t.primary.g, t.primary.b, 0.3))
		# ★ 表格有边框视觉效果
		output_text.add_theme_constant_override("table_h_separation", 12)
		output_text.add_theme_constant_override("table_v_separation", 4)

	# ★ 加载 SemiBold 字体替代伪粗体
	# Godot 默认的 [b] 标签使用"伪粗体"（同一字形偏移叠绘），
	# 会导致笔画边缘模糊、亮度翻倍，经过 CRT shader 后严重过曝。
	# 使用真正的 SemiBold 字体文件可从根本上解决此问题。
	CrtmlParser.apply_fonts(output_text)
	# ★ 表格单元格间距
	output_text.add_theme_constant_override("table_h_separation", 16)
	output_text.add_theme_constant_override("table_v_separation", 4)

# ============================================================
# 为 RichTextLabel 应用真正的 Bold 字体
# 可供 output_text 和 document_viewer 的页面 RTL 共用
# ============================================================
static func _apply_bold_font(rtl: RichTextLabel) -> void:
	if ResourceLoader.exists(BOLD_FONT_PATH):
		var bold_font: Font = load(BOLD_FONT_PATH)
		if bold_font:
			rtl.add_theme_font_override("bold_font", bold_font)
			# bold_italics 也使用同一个 SemiBold 字体
			rtl.add_theme_font_override("bold_italics_font", bold_font)
	else:
		# 如果找不到 SemiBold，尝试 Bold
		var fallback_path := "res://fonts/SarasaMonoSC-Bold.ttf"
		if ResourceLoader.exists(fallback_path):
			var bold_font: Font = load(fallback_path)
			if bold_font:
				rtl.add_theme_font_override("bold_font", bold_font)
				rtl.add_theme_font_override("bold_italics_font", bold_font)
		else:
			print("[UI] 警告: 未找到 Bold 字体文件，将使用 Godot 伪粗体，会导致恩情发光")

# ============================================================
# ScrollContainer 设置
# ============================================================
static func setup_scroll_container(scroll_container: ScrollContainer) -> void:
	scroll_container.mouse_filter = Control.MOUSE_FILTER_PASS

# ============================================================
# 滚动条 CRT 风格样式
# ============================================================
static func setup_scrollbar_style(scroll_container: ScrollContainer) -> void:
	var t := ThemeManager.current
	var v_scrollbar: VScrollBar = scroll_container.get_v_scroll_bar()
	if v_scrollbar == null:
		return
	var base_color: Color = t.primary if t != null else Color(0.6, 1.0, 0.6, 1.0)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.1, 0.3)
	bg.corner_radius_top_left = 2
	bg.corner_radius_top_right = 2
	bg.corner_radius_bottom_left = 2
	bg.corner_radius_bottom_right = 2
	v_scrollbar.add_theme_stylebox_override("scroll", bg)

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(base_color.r, base_color.g, base_color.b, 0.4)
	grabber.corner_radius_top_left = 2
	grabber.corner_radius_top_right = 2
	grabber.corner_radius_bottom_left = 2
	grabber.corner_radius_bottom_right = 2
	v_scrollbar.add_theme_stylebox_override("grabber", grabber)

	var grabber_highlight := StyleBoxFlat.new()
	grabber_highlight.bg_color = Color(base_color.r, base_color.g, base_color.b, 0.6)
	grabber_highlight.corner_radius_top_left = 2
	grabber_highlight.corner_radius_top_right = 2
	grabber_highlight.corner_radius_bottom_left = 2
	grabber_highlight.corner_radius_bottom_right = 2
	v_scrollbar.add_theme_stylebox_override("grabber_highlight", grabber_highlight)

	var grabber_pressed := StyleBoxFlat.new()
	grabber_pressed.bg_color = Color(base_color.r, base_color.g, base_color.b, 0.8)
	grabber_pressed.corner_radius_top_left = 2
	grabber_pressed.corner_radius_top_right = 2
	grabber_pressed.corner_radius_bottom_left = 2
	grabber_pressed.corner_radius_bottom_right = 2
	v_scrollbar.add_theme_stylebox_override("grabber_pressed", grabber_pressed)

# ============================================================
# CRT 效果层设置
# ============================================================
static func setup_crt_effect(crt_node: Node) -> void:
	if crt_node == null:
		return
	for child in crt_node.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE

# ============================================================
# 自定义鼠标光标（CRT风格像素光标）
# ============================================================
static func setup_custom_cursor(_parent: Control) -> void:
	var cursor_image := _generate_crt_cursor()
	var cursor_texture := ImageTexture.create_from_image(cursor_image)
	Input.set_custom_mouse_cursor(cursor_texture, Input.CURSOR_ARROW, Vector2(0, 0))

	var ibeam_image := _generate_crt_ibeam()
	var ibeam_texture := ImageTexture.create_from_image(ibeam_image)
	Input.set_custom_mouse_cursor(ibeam_texture, Input.CURSOR_IBEAM, Vector2(7, 11))

	var hand_image := _generate_crt_hand()
	var hand_texture := ImageTexture.create_from_image(hand_image)
	Input.set_custom_mouse_cursor(hand_texture, Input.CURSOR_POINTING_HAND, Vector2(6, 2))

	print("[UI] CRT风格鼠标光标已应用")

# ============================================================
# 生成 CRT 风格箭头光标 (20x24)
# ============================================================
static func _generate_crt_cursor() -> Image:
	var t := ThemeManager.current
	var fg: Color = t.primary if t != null else Color(0.6, 1.0, 0.6, 1.0)
	var outline: Color = Color(0, 0, 0, 0.95)
	var glow: Color = Color(fg.r, fg.g, fg.b, 0.35)
	var w: int = 20
	var h: int = 24
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var pattern: Array = [
		[3,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
		[3,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
		[3,1,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
		[3,1,1,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
		[3,1,1,1,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
		[3,1,1,1,1,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0],
		[3,1,1,1,1,1,1,2,0,0,0,0,0,0,0,0,0,0,0,0],
		[3,1,1,1,1,1,1,1,2,0,0,0,0,0,0,0,0,0,0,0],
		[3,1,1,1,1,1,1,1,1,2,0,0,0,0,0,0,0,0,0,0],
		[3,1,1,1,1,1,1,1,1,1,2,0,0,0,0,0,0,0,0,0],
		[3,1,1,1,1,1,1,1,1,1,1,2,0,0,0,0,0,0,0,0],
		[3,1,1,1,1,1,1,1,1,1,1,1,2,0,0,0,0,0,0,0],
		[3,1,1,1,1,1,1,1,2,2,2,2,2,0,0,0,0,0,0,0],
		[3,1,1,1,1,2,1,1,1,2,0,0,0,0,0,0,0,0,0,0],
		[3,1,1,1,2,0,2,1,1,1,2,0,0,0,0,0,0,0,0,0],
		[3,1,1,2,0,0,2,1,1,1,2,0,0,0,0,0,0,0,0,0],
		[3,1,2,0,0,0,0,2,1,1,1,2,0,0,0,0,0,0,0,0],
		[3,2,0,0,0,0,0,2,1,1,1,2,0,0,0,0,0,0,0,0],
		[3,0,0,0,0,0,0,0,2,1,1,2,0,0,0,0,0,0,0,0],
		[0,0,0,0,0,0,0,0,2,1,1,2,0,0,0,0,0,0,0,0],
		[0,0,0,0,0,0,0,0,0,2,1,2,0,0,0,0,0,0,0,0],
		[0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0],
		[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
		[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
	]
	for y in range(h):
		for x in range(w):
			if y < pattern.size() and x < pattern[y].size():
				match pattern[y][x]:
					1: img.set_pixel(x, y, fg)
					2: img.set_pixel(x, y, outline)
					3: img.set_pixel(x, y, glow)
	var bold_img := img.duplicate()
	for y2 in range(h):
		for x2 in range(w - 1):
			if img.get_pixel(x2, y2) == fg and bold_img.get_pixel(x2 + 1, y2).a < 0.1:
				bold_img.set_pixel(x2 + 1, y2, fg)
	return bold_img

# ============================================================
# 生成 CRT 风格 I-beam 文字光标 (16x22)
# ============================================================
static func _generate_crt_ibeam() -> Image:
	var t := ThemeManager.current
	var fg: Color = t.primary if t != null else Color(0.6, 1.0, 0.6, 1.0)
	var outline: Color = Color(0, 0, 0, 0.95)
	var glow: Color = Color(fg.r, fg.g, fg.b, 0.35)
	var w: int = 16
	var h: int = 22
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var pattern: Array = [
		[0,0,0,2,2,2,2,2,2,2,2,2,0,0,0,0],
		[0,0,3,1,1,1,1,1,1,1,1,1,3,0,0,0],
		[0,0,3,1,1,1,1,1,1,1,1,1,3,0,0,0],
		[0,0,0,2,2,2,1,1,2,2,2,0,0,0,0,0],
		[0,0,0,0,0,2,1,1,2,0,0,0,0,0,0,0],
		[0,0,0,0,0,2,1,1,2,0,0,0,0,0,0,0],
		[0,0,0,0,0,2,1,1,2,0,0,0,0,0,0,0],
		[0,0,0,0,0,2,1,1,2,0,0,0,0,0,0,0],
		[0,0,0,0,0,2,1,1,2,0,0,0,0,0,0,0],
		[0,0,0,0,0,2,1,1,2,0,0,0,0,0,0,0],
		[0,0,0,0,0,2,1,1,2,0,0,0,0,0,0,0],
		[0,0,0,0,0,2,1,1,2,0,0,0,0,0,0,0],
		[0,0,0,0,0,2,1,1,2,0,0,0,0,0,0,0],
		[0,0,0,0,0,2,1,1,2,0,0,0,0,0,0,0],
		[0,0,0,0,0,2,1,1,2,0,0,0,0,0,0,0],
		[0,0,0,0,0,2,1,1,2,0,0,0,0,0,0,0],
		[0,0,0,0,0,2,1,1,2,0,0,0,0,0,0,0],
		[0,0,0,0,0,2,1,1,2,0,0,0,0,0,0,0],
		[0,0,0,2,2,2,1,1,2,2,2,0,0,0,0,0],
		[0,0,3,1,1,1,1,1,1,1,1,1,3,0,0,0],
		[0,0,3,1,1,1,1,1,1,1,1,1,3,0,0,0],
		[0,0,0,2,2,2,2,2,2,2,2,2,0,0,0,0],
	]
	for y in range(h):
		for x in range(w):
			if y < pattern.size() and x < pattern[y].size():
				match pattern[y][x]:
					1: img.set_pixel(x, y, fg)
					2: img.set_pixel(x, y, outline)
					3: img.set_pixel(x, y, glow)
	return img

# ============================================================
# 生成 CRT 风格手指光标 (16x20)
# ============================================================
static func _generate_crt_hand() -> Image:
	var t := ThemeManager.current
	var fg: Color = t.primary if t != null else Color(0.6, 1.0, 0.6, 1.0)
	var outline: Color = Color(0, 0, 0, 0.9)
	var glow: Color = Color(fg.r, fg.g, fg.b, 0.3)
	var w: int = 16
	var h: int = 20
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var pattern: Array = [
		[0,0,0,0,0,3,2,3,0,0,0,0,0,0,0,0],
		[0,0,0,0,3,2,1,2,3,0,0,0,0,0,0,0],
		[0,0,0,0,3,2,1,2,3,0,0,0,0,0,0,0],
		[0,0,0,0,3,2,1,2,3,0,0,0,0,0,0,0],
		[0,0,0,0,3,2,1,2,3,2,3,0,0,0,0,0],
		[0,0,0,0,3,2,1,2,1,2,3,2,3,0,0,0],
		[0,0,0,0,3,2,1,2,1,2,1,2,3,2,0,0],
		[0,3,2,3,3,2,1,1,1,2,1,2,1,2,3,0],
		[3,2,1,2,3,1,1,1,1,1,1,1,1,2,3,0],
		[3,2,1,1,2,1,1,1,1,1,1,1,1,2,3,0],
		[0,3,2,1,1,1,1,1,1,1,1,1,1,2,3,0],
		[0,0,3,2,1,1,1,1,1,1,1,1,2,3,0,0],
		[0,0,3,2,1,1,1,1,1,1,1,1,2,3,0,0],
		[0,0,0,3,2,1,1,1,1,1,1,2,3,0,0,0],
		[0,0,0,3,2,1,1,1,1,1,1,2,3,0,0,0],
		[0,0,0,0,3,2,1,1,1,1,2,3,0,0,0,0],
		[0,0,0,0,3,2,1,1,1,1,2,3,0,0,0,0],
		[0,0,0,0,0,3,2,1,1,2,3,0,0,0,0,0],
		[0,0,0,0,0,3,2,1,1,2,3,0,0,0,0,0],
		[0,0,0,0,0,0,3,2,2,3,0,0,0,0,0,0],
	]
	for y in range(h):
		for x in range(w):
			if y < pattern.size() and x < pattern[y].size():
				match pattern[y][x]:
					1: img.set_pixel(x, y, fg)
					2: img.set_pixel(x, y, outline)
					3: img.set_pixel(x, y, glow)
	return img

# ============================================================
# 一次性初始化所有 UI 样式
# ============================================================
static func setup_all_styles(
	status_frame: PanelContainer,
	path_label: Label,
	mail_icon: Label,
	input_frame: PanelContainer,
	input_field: LineEdit,
	output_text: RichTextLabel,
	scroll_container: ScrollContainer = null
) -> void:
	setup_status_frame(status_frame)
	setup_path_label(path_label)
	setup_mail_icon(mail_icon)
	setup_input_frame(input_frame)
	setup_input_field(input_field)
	setup_output_text(output_text)
	if scroll_container != null:
		setup_scroll_container(scroll_container)
		setup_scrollbar_style(scroll_container)
