# ============================================================
# ui_manager.gd - UI 初始化与背景管理
# 负责：背景图加载、Shader应用、各UI组件样式初始化、鼠标光标
# ============================================================
class_name UIManager
extends RefCounted

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
	if main_content == null:
		return
	parent.move_child(main_content, parent.get_child_count() - 1)
	if main_content is Control:
		var transparent_style := StyleBoxFlat.new()
		transparent_style.bg_color = Color(0, 0, 0, 0)
		transparent_style.set_border_width_all(0)
		main_content.add_theme_stylebox_override("panel", transparent_style)

# ============================================================
# 状态栏样式
# ============================================================
static func setup_status_frame(status_frame: PanelContainer) -> void:
	var t := ThemeManager.current
	var style := StyleBoxFlat.new()
	style.bg_color = t.bg_panel if t != null else Color(0.0, 0.04, 0.0, 0.9)
	style.border_color = t.border if t != null else Color(0.2, 0.6, 0.2, 0.4)
	style.set_border_width_all(1)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 3
	style.content_margin_bottom = 3
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
# 输入区外框样式
# ============================================================
static func setup_input_frame(input_frame: PanelContainer) -> void:
	var t := ThemeManager.current
	var style := StyleBoxFlat.new()
	style.bg_color = t.bg_panel if t != null else Color(0.0, 0.04, 0.0, 0.9)
	style.border_color = t.border if t != null else Color(0.2, 0.6, 0.2, 0.4)
	style.set_border_width_all(1)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	input_frame.add_theme_stylebox_override("panel", style)

# ============================================================
# 输入框样式
# ============================================================
static func setup_input_field(input_field: LineEdit) -> void:
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
		input_field.add_theme_color_override("font_placeholder_color", t.dim)
		input_field.add_theme_color_override("caret_color", t.primary)
		input_field.add_theme_color_override("selection_color", t.selection_bg)

# ============================================================
# 输出文本框初始化
# ============================================================
static func setup_output_text(output_text: RichTextLabel) -> void:
	var t := ThemeManager.current
	output_text.text = ""
	output_text.bbcode_enabled = true
	output_text.selection_enabled = true
	output_text.meta_underlined = true
	output_text.mouse_filter = Control.MOUSE_FILTER_STOP
	output_text.focus_mode = Control.FOCUS_CLICK
	if t != null:
		output_text.add_theme_color_override("default_color", t.secondary)
		output_text.add_theme_color_override("selection_color", t.selection_bg)

# ============================================================
# ScrollContainer 设置
# ============================================================
static func setup_scroll_container(scroll_container: ScrollContainer) -> void:
	scroll_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

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
	# 生成像素风格的箭头光标
	var cursor_image := _generate_crt_cursor()
	var cursor_texture := ImageTexture.create_from_image(cursor_image)
	Input.set_custom_mouse_cursor(cursor_texture, Input.CURSOR_ARROW, Vector2(0, 0))

	# 生成像素风格的 I-beam 光标（用于文字选中）
	var ibeam_image := _generate_crt_ibeam()
	var ibeam_texture := ImageTexture.create_from_image(ibeam_image)
	Input.set_custom_mouse_cursor(ibeam_texture, Input.CURSOR_IBEAM, Vector2(8, 10))

	# 生成像素风格的手指光标（用于超链接）
	var hand_image := _generate_crt_hand()
	var hand_texture := ImageTexture.create_from_image(hand_image)
	Input.set_custom_mouse_cursor(hand_texture, Input.CURSOR_POINTING_HAND, Vector2(6, 2))

	print("[UI] CRT风格鼠标光标已应用")

# ============================================================
# 生成 CRT 风格箭头光标 (16x20)
# ============================================================
static func _generate_crt_cursor() -> Image:
	var t := ThemeManager.current
	var fg: Color = t.primary if t != null else Color(0.6, 1.0, 0.6, 1.0)
	var outline: Color = Color(0, 0, 0, 0.9)
	var glow: Color = Color(fg.r, fg.g, fg.b, 0.3)

	var w: int = 16
	var h: int = 20
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# 箭头像素图案（1=填充, 2=轮廓, 3=发光）
	var pattern: Array = [
		[3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
		[3,2,3,0,0,0,0,0,0,0,0,0,0,0,0,0],
		[3,1,2,3,0,0,0,0,0,0,0,0,0,0,0,0],
		[3,1,1,2,3,0,0,0,0,0,0,0,0,0,0,0],
		[3,1,1,1,2,3,0,0,0,0,0,0,0,0,0,0],
		[3,1,1,1,1,2,3,0,0,0,0,0,0,0,0,0],
		[3,1,1,1,1,1,2,3,0,0,0,0,0,0,0,0],
		[3,1,1,1,1,1,1,2,3,0,0,0,0,0,0,0],
		[3,1,1,1,1,1,1,1,2,3,0,0,0,0,0,0],
		[3,1,1,1,1,1,1,1,1,2,3,0,0,0,0,0],
		[3,1,1,1,1,1,1,1,1,1,2,3,0,0,0,0],
		[3,1,1,1,1,1,1,2,2,2,2,2,0,0,0,0],
		[3,1,1,1,2,1,1,2,3,0,0,0,0,0,0,0],
		[3,1,1,2,3,2,1,1,2,3,0,0,0,0,0,0],
		[3,1,2,3,0,3,2,1,1,2,3,0,0,0,0,0],
		[3,2,3,0,0,0,3,2,1,1,2,3,0,0,0,0],
		[3,3,0,0,0,0,3,2,1,1,2,3,0,0,0,0],
		[0,0,0,0,0,0,0,3,2,1,2,3,0,0,0,0],
		[0,0,0,0,0,0,0,0,3,2,3,0,0,0,0,0],
		[0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,0],
	]

	for y in range(h):
		for x in range(w):
			if y < pattern.size() and x < pattern[y].size():
				match pattern[y][x]:
					1:
						img.set_pixel(x, y, fg)
					2:
						img.set_pixel(x, y, outline)
					3:
						img.set_pixel(x, y, glow)

	return img

# ============================================================
# 生成 CRT 风格 I-beam 文字光标 (16x20)
# ============================================================
static func _generate_crt_ibeam() -> Image:
	var t := ThemeManager.current
	var fg: Color = t.primary if t != null else Color(0.6, 1.0, 0.6, 1.0)
	var outline: Color = Color(0, 0, 0, 0.9)
	var glow: Color = Color(fg.r, fg.g, fg.b, 0.3)

	var w: int = 16
	var h: int = 20
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# I-beam 像素图案
	# 顶部横杠
	for x in range(4, 12):
		img.set_pixel(x, 0, glow)
		img.set_pixel(x, 1, fg)
		img.set_pixel(x, 2, glow)
	# 竖线
	for y in range(2, 18):
		img.set_pixel(7, y, outline)
		img.set_pixel(8, y, fg)
		img.set_pixel(9, y, outline)
	# 底部横杠
	for x in range(4, 12):
		img.set_pixel(x, 17, glow)
		img.set_pixel(x, 18, fg)
		img.set_pixel(x, 19, glow)

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

	# 手指光标像素图案
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
					1:
						img.set_pixel(x, y, fg)
					2:
						img.set_pixel(x, y, outline)
					3:
						img.set_pixel(x, y, glow)

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
