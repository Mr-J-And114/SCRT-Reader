# ============================================================
# demo_camera.gd - Demo 主控制器
# 职责：CRT 后处理 + 幻灯片渲染 + 鼠标导航 + 摄像头系统集成 + stub 适配层
# ============================================================
extends Control

# ══════════════════════════════════════════
#  CRT 后处理
# ══════════════════════════════════════════
var _crt_layer: CanvasLayer = null
var _crt_rect: ColorRect = null
var _crt_mat: ShaderMaterial = null

# ══════════════════════════════════════════
#  点击导航区
# ══════════════════════════════════════════
var _click_left: Control = null
var _click_right: Control = null
var _click_left_hint: ColorRect = null
var _click_right_hint: ColorRect = null

# ══════════════════════════════════════════
#  Stub 属性（供 CameraManager / CameraViewer 使用）
# ══════════════════════════════════════════
var input_field: LineEdit = null
var prompt_label: Label = null
var output_text: RichTextLabel = null
var path_label: Label = null
var scroll_container: ScrollContainer = null
var fs = null
var effect_settings = null
var trigger_sys = null
var T = null

# ══════════════════════════════════════════
#  摄像头系统
# ══════════════════════════════════════════
var camera_mgr: CameraManager = null
var camera_viewer: CameraViewer = null

# ══════════════════════════════════════════
#  LaTeX 渲染器
# ══════════════════════════════════════════
var _latex: LatexRenderer = null
var _latex_formulas_ready: bool = false
var _formula_local_variation: ImageTexture = null

# ══════════════════════════════════════════
#  幻灯片
# ══════════════════════════════════════════
var _slides: Array[Dictionary] = []
var _current_slide: int = 0

# ══════════════════════════════════════════
#  UI 节点
# ══════════════════════════════════════════
var _bg: ColorRect = null
var _slide_layer: Control = null
var _title_label: Label = null
var _subtitle_label: Label = null
var _members_label: Label = null
var _footer_label: Label = null
var _body_text: RichTextLabel = null
var _slide_image: TextureRect = null
var _diagram_canvas: Control = null
var _code_panel: Panel = null
var _code_label: RichTextLabel = null
var _camera_button: Button = null
var _bottom_bar: Panel = null
var _page_indicator: Label = null
var _nav_hint: Label = null

# ══════════════════════════════════════════
#  代码高亮颜色
# ══════════════════════════════════════════
const COL_KEYWORD := Color(0.55, 0.77, 1.0)
const COL_TYPE := Color(0.5, 0.9, 0.5)
const COL_STRING := Color(1.0, 0.75, 0.4)
const COL_NUMBER := Color(1.0, 0.85, 0.3)
const COL_COMMENT := Color(0.45, 0.5, 0.45)
const COL_DEFAULT := Color(0.82, 0.88, 0.82)
const COL_FUNC := Color(1.0, 0.88, 0.5)

const GD_KEYWORDS: Array[String] = [
	"func", "var", "if", "else", "elif", "for", "while", "return", "not",
	"and", "or", "in", "is", "as", "null", "true", "false", "void",
	"class_name", "extends", "const", "enum", "match", "break", "continue",
	"pass", "self", "super", "static", "signal", "await",
]
const GD_TYPES: Array[String] = [
	"int", "float", "String", "bool", "Array", "Dictionary", "Vector2",
	"Vector2i", "Vector3", "Color", "PackedByteArray", "Image",
	"ImageTexture", "Callable", "Rect2", "Object", "Node", "Control",
]
const GL_KEYWORDS: Array[String] = [
	"float", "vec2", "vec3", "vec4", "int", "bool", "void", "if", "else",
	"for", "return", "uniform", "sampler2D", "texture", "in", "out",
	"inout", "const", "struct", "break", "continue", "discard",
]
const GL_FUNCS: Array[String] = [
	"texture", "mix", "clamp", "smoothstep", "pow", "sin", "cos",
	"distance", "dot", "floor", "fract", "step", "length", "normalize",
]

# ══════════════════════════════════════════
#  字体资源路径
# ══════════════════════════════════════════
const FONT_REGULAR: String = "res://fonts/SarasaMonoSC-Regular.ttf"
const FONT_SEMIBOLD: String = "res://fonts/SarasaMonoSC-SemiBold.ttf"
const FONT_ITALIC: String = "res://fonts/SarasaMonoSC-Italic.ttf"
const FONT_SEMIBOLD_ITALIC: String = "res://fonts/SarasaMonoSC-SemiBoldItalic.ttf"

var _font_regular: Font = null
var _font_semibold: Font = null
var _font_italic: Font = null
var _font_semibold_italic: Font = null

func _load_fonts() -> void:
	_font_regular = load(FONT_REGULAR) as Font
	_font_semibold = load(FONT_SEMIBOLD) as Font
	_font_italic = load(FONT_ITALIC) as Font
	_font_semibold_italic = load(FONT_SEMIBOLD_ITALIC) as Font

func _apply_fonts_to_rtl(rtl: RichTextLabel) -> void:
	if _font_regular:
		rtl.add_theme_font_override("normal_font", _font_regular)
	if _font_semibold:
		rtl.add_theme_font_override("bold_font", _font_semibold)
	if _font_italic:
		rtl.add_theme_font_override("italics_font", _font_italic)
	if _font_semibold_italic:
		rtl.add_theme_font_override("bold_italics_font", _font_semibold_italic)

func _apply_font_to_label(label: Control) -> void:
	if _font_regular:
		label.add_theme_font_override("font", _font_regular)

func _apply_font_to_button(btn: Button) -> void:
	if _font_regular:
		btn.add_theme_font_override("font", _font_regular)

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func _ready() -> void:
	T = ThemeManager.current
	_load_fonts()
	_build_ui()
	_init_camera_system()
	_slides = DemoSlides.get_slides()

	# 初始化 LaTeX 渲染器
	_latex = LatexRenderer.new()
	_latex.setup(self, _font_regular, _font_semibold, _font_italic, _font_semibold_italic)
	_latex.set_default_color(Color(0.78, 0.9, 0.78))

	# 预渲染所有公式（异步）
	await _pre_render_all_formulas()
	_latex_formulas_ready = true

	_show_slide(0)
	_setup_crt_effect()

	if get_tree().get_root().size_changed.is_connected(_on_viewport_resize):
		pass
	else:
		get_tree().get_root().size_changed.connect(_on_viewport_resize)

func _on_viewport_resize() -> void:
	# 延迟到下一帧，确保 Control.size 已更新
	call_deferred("_do_resize")

func _do_resize() -> void:
	_show_slide(_current_slide)
	_update_crt_size()
	_update_click_zones()

# ══════════════════════════════════════════
#  LaTeX 公式处理
# ══════════════════════════════════════════

func _pre_render_all_formulas() -> void:
	if _latex == null:
		return
	# 预渲染所有 slide 正文中的公式
	for slide in _slides:
		var body: String = slide.get("body", "")
		await _pre_render_math_in_text(body, 18)
	# 预渲染图表公式
	_formula_local_variation = await _latex.render_to_texture_colored(
		"final = ref_{dist} + (raw - \\mu) \\times scale", 14,
		Color(0.3, 0.8, 1.0, 1.0))

func _pre_render_math_in_text(text: String, font_size: int) -> void:
	if _latex == null:
		return
	var pos: int = 0
	while true:
		var block_start: int = text.find("[math block]", pos)
		var inline_start: int = text.find("[math]", pos)
		var nearest: int = -1
		var is_block: bool = false
		if block_start >= 0 and (inline_start < 0 or block_start < inline_start):
			nearest = block_start
			is_block = true
		elif inline_start >= 0:
			nearest = inline_start
			is_block = false
		if nearest < 0:
			break
		var tag: String = "[math block]" if is_block else "[math]"
		var content_start: int = nearest + tag.length()
		var end_pos: int = text.find("[/math]", content_start)
		if end_pos < 0:
			break
		var latex_str: String = text.substr(content_start, end_pos - content_start)
		var fs: int = 22 if is_block else font_size
		if not _latex.is_cached(latex_str, fs):
			await _latex.render_to_texture(latex_str, fs)
		pos = end_pos + 7  # strlen("[/math]") = 7

func _set_body_text_with_math(rtl: RichTextLabel, body_raw: String) -> void:
	rtl.clear()
	if not _latex_formulas_ready or _latex == null:
		rtl.append_text(body_raw)
		return
	var pos: int = 0
	var n: int = body_raw.length()
	while pos < n:
		var block_start: int = body_raw.find("[math block]", pos)
		var inline_start: int = body_raw.find("[math]", pos)
		var nearest: int = -1
		var is_block: bool = false
		if block_start >= 0 and (inline_start < 0 or block_start < inline_start):
			nearest = block_start
			is_block = true
		elif inline_start >= 0:
			nearest = inline_start
			is_block = false
		if nearest < 0:
			rtl.append_text(body_raw.substr(pos))
			break
		if nearest > pos:
			rtl.append_text(body_raw.substr(pos, nearest - pos))
		var tag: String = "[math block]" if is_block else "[math]"
		var content_start: int = nearest + tag.length()
		var end_pos: int = body_raw.find("[/math]", content_start)
		if end_pos < 0:
			rtl.append_text(body_raw.substr(nearest))
			break
		var latex_str: String = body_raw.substr(content_start, end_pos - content_start)
		var fs: int = 22 if is_block else 18
		if is_block:
			rtl.newline()
		var tex: ImageTexture = _latex.get_cached_texture(latex_str, fs)
		if tex:
			var align: int = INLINE_ALIGNMENT_CENTER if not is_block else INLINE_ALIGNMENT_TOP
			rtl.add_image(tex, tex.get_width(), tex.get_height(), Color.WHITE, align)
		else:
			rtl.append_text(latex_str)
		if is_block:
			rtl.newline()
		pos = end_pos + 7

# ══════════════════════════════════════════
#  UI 构建
# ══════════════════════════════════════════
func _build_ui() -> void:
	# 背景（与主项目一致：黑色底 + 带暗角 shader 的背景图）
	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0, 1)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)

	# 背景图片（带暗角 shader）
	var bg_tex_path: String = "res://images/backround.png"
	if ResourceLoader.exists(bg_tex_path):
		var bg_tex: TextureRect = TextureRect.new()
		bg_tex.texture = load(bg_tex_path) as Texture2D
		bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_tex.stretch_mode = TextureRect.STRETCH_SCALE
		bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 背景暗角 shader
		var bg_shader_path: String = "res://shaders/background_vignette.gdshader"
		if ResourceLoader.exists(bg_shader_path):
			var bg_mat := ShaderMaterial.new()
			bg_mat.shader = load(bg_shader_path) as Shader
			bg_mat.set_shader_parameter("vignette_strength", 1.442)
			bg_mat.set_shader_parameter("vignette_radius", 0.771)
			bg_mat.set_shader_parameter("glow_strength", 0.0)
			bg_mat.set_shader_parameter("glow_radius", 0.467)
			bg_mat.set_shader_parameter("brightness", 0.688)
			bg_mat.set_shader_parameter("tint_color", Color(0.1, 0.3, 0.1, 0.15))
			bg_mat.set_shader_parameter("alpha", 0.5)
			bg_mat.set_shader_parameter("hue_shift", 0.0)
			bg_mat.set_shader_parameter("saturation", 1.0)
			bg_mat.set_shader_parameter("contrast", 1.0)
			bg_tex.material = bg_mat
		_bg.add_child(bg_tex)

	# 幻灯片层
	_slide_layer = Control.new()
	_slide_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slide_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slide_layer)

	# 标题
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 36)
	_title_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	_apply_font_to_label(_title_label)
	_slide_layer.add_child(_title_label)

	# 副标题
	_subtitle_label = Label.new()
	_subtitle_label.add_theme_font_size_override("font_size", 22)
	_subtitle_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font_to_label(_subtitle_label)
	_slide_layer.add_child(_subtitle_label)

	# 成员信息
	_members_label = Label.new()
	_members_label.add_theme_font_size_override("font_size", 18)
	_members_label.add_theme_color_override("font_color", Color(0.65, 0.75, 0.65))
	_members_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font_to_label(_members_label)
	_slide_layer.add_child(_members_label)

	# 页脚
	_footer_label = Label.new()
	_footer_label.add_theme_font_size_override("font_size", 16)
	_footer_label.add_theme_color_override("font_color", Color(0.45, 0.55, 0.45))
	_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font_to_label(_footer_label)
	_slide_layer.add_child(_footer_label)

	# 正文
	_body_text = RichTextLabel.new()
	_body_text.bbcode_enabled = true
	_body_text.add_theme_font_size_override("normal_font_size", 18)
	_body_text.add_theme_color_override("default_color", Color(0.78, 0.9, 0.78))
	_body_text.fit_content = false
	_body_text.scroll_active = false
	_body_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_fonts_to_rtl(_body_text)
	_slide_layer.add_child(_body_text)

	# 图片
	_slide_image = TextureRect.new()
	_slide_image.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_slide_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_slide_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slide_layer.add_child(_slide_image)

	# 图表画布
	_diagram_canvas = _DiagramCanvas.new()
	_diagram_canvas.host = self
	_diagram_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slide_layer.add_child(_diagram_canvas)

	# 代码面板
	_code_panel = Panel.new()
	var code_style := StyleBoxFlat.new()
	code_style.bg_color = Color(0.06, 0.09, 0.06)
	code_style.border_width_left = 2
	code_style.border_color = Color(0.2, 0.35, 0.2)
	code_style.corner_radius_top_left = 4
	code_style.corner_radius_bottom_left = 4
	_code_panel.add_theme_stylebox_override("panel", code_style)
	_code_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slide_layer.add_child(_code_panel)

	_code_label = RichTextLabel.new()
	_code_label.add_theme_font_size_override("normal_font_size", 15)
	_code_label.fit_content = false
	_code_label.scroll_active = false
	_code_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_fonts_to_rtl(_code_label)
	_code_panel.add_child(_code_label)

	# 摄像头按钮
	_camera_button = Button.new()
	_camera_button.text = "▶  打开摄像头查看"
	_camera_button.add_theme_font_size_override("font_size", 18)
	_camera_button.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	_camera_button.add_theme_color_override("font_hover_color", Color(0.9, 1.0, 0.9))
	_camera_button.add_theme_stylebox_override("normal", _make_btn_style(Color(0.1, 0.2, 0.1, 0.8), Color(0.3, 0.6, 0.3)))
	_camera_button.add_theme_stylebox_override("hover", _make_btn_style(Color(0.15, 0.3, 0.15, 0.9), Color(0.5, 0.9, 0.5)))
	_camera_button.add_theme_stylebox_override("pressed", _make_btn_style(Color(0.05, 0.15, 0.05, 1.0), Color(0.4, 0.8, 0.4)))
	_apply_font_to_button(_camera_button)
	_camera_button.pressed.connect(_on_camera_button_pressed)
	_camera_button.visible = false
	_slide_layer.add_child(_camera_button)

	# ── 左右点击导航区 ──
	# 左侧（上一页）
	_click_left = Control.new()
	_click_left.name = "ClickLeft"
	_click_left.mouse_filter = Control.MOUSE_FILTER_STOP
	_click_left.gui_input.connect(_on_click_left_input)
	add_child(_click_left)

	_click_left_hint = ColorRect.new()
	_click_left_hint.color = Color(0, 0, 0, 0)
	_click_left_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_click_left.add_child(_click_left_hint)

	# 右侧（下一页）
	_click_right = Control.new()
	_click_right.name = "ClickRight"
	_click_right.mouse_filter = Control.MOUSE_FILTER_STOP
	_click_right.gui_input.connect(_on_click_right_input)
	add_child(_click_right)

	_click_right_hint = ColorRect.new()
	_click_right_hint.color = Color(0, 0, 0, 0)
	_click_right_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_click_right.add_child(_click_right_hint)

	_update_click_zones()

	# 底部栏
	_bottom_bar = Panel.new()
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0, 0, 0, 0.4)
	_bottom_bar.add_theme_stylebox_override("panel", bar_style)
	_bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bottom_bar)

	_page_indicator = Label.new()
	_page_indicator.add_theme_font_size_override("font_size", 14)
	_page_indicator.add_theme_color_override("font_color", Color(0.5, 0.6, 0.5))
	_page_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_page_indicator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_font_to_label(_page_indicator)
	_bottom_bar.add_child(_page_indicator)

	_nav_hint = Label.new()
	_nav_hint.add_theme_font_size_override("font_size", 13)
	_nav_hint.add_theme_color_override("font_color", Color(0.4, 0.5, 0.4))
	_nav_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nav_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_font_to_label(_nav_hint)
	_bottom_bar.add_child(_nav_hint)

	# ── Stub 节点（供 CameraViewer 隐藏/恢复） ──
	input_field = LineEdit.new()
	input_field.visible = false
	_apply_font_to_label(input_field)
	add_child(input_field)

	prompt_label = Label.new()
	prompt_label.visible = false
	_apply_font_to_label(prompt_label)
	add_child(prompt_label)

	output_text = RichTextLabel.new()
	output_text.visible = false
	_apply_fonts_to_rtl(output_text)
	add_child(output_text)

	# path_label（状态栏，摄像头模式时显示提示）
	path_label = Label.new()
	path_label.add_theme_font_size_override("font_size", 14)
	path_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	_apply_font_to_label(path_label)
	path_label.visible = false
	add_child(path_label)

	# scroll_container（CameraViewer 覆盖层定位用，全屏）
	scroll_container = ScrollContainer.new()
	scroll_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_container.visible = true
	add_child(scroll_container)

func _make_btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_bottom = 2
	s.border_width_top = 2
	s.border_width_left = 2
	s.border_width_right = 2
	s.border_color = border
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s

# ══════════════════════════════════════════
#  CRT 后处理效果
# ══════════════════════════════════════════
func _setup_crt_effect() -> void:
	var shader_path: String = "res://shaders/crt_effect.gdshader"
	var shader: Shader = null
	if ResourceLoader.exists(shader_path):
		shader = load(shader_path) as Shader
	if shader == null:
		push_warning("[Demo] 无法加载 CRT shader，跳过后处理")
		return

	_crt_mat = ShaderMaterial.new()
	_crt_mat.shader = shader

	# 设置 CRT 参数（与主项目 main.tscn 一致）
	_crt_mat.set_shader_parameter("scanline_intensity", 0.15)
	_crt_mat.set_shader_parameter("scanline_frequency", 300.0)
	_crt_mat.set_shader_parameter("scanline_speed", 1.0)
	_crt_mat.set_shader_parameter("curvature", 1.0)
	_crt_mat.set_shader_parameter("chromatic_aberration", 0.3)
	_crt_mat.set_shader_parameter("vignette_intensity", 0.4)
	_crt_mat.set_shader_parameter("vignette_size", 0.6)
	_crt_mat.set_shader_parameter("flicker_intensity", 0.03)
	_crt_mat.set_shader_parameter("flicker_speed", 8.0)
	_crt_mat.set_shader_parameter("noise_intensity", 0.04)
	_crt_mat.set_shader_parameter("tear_strength", 0.0)
	_crt_mat.set_shader_parameter("tear_speed", 3.0)
	_crt_mat.set_shader_parameter("tear_count", 3.0)
	_crt_mat.set_shader_parameter("glow_intensity", 0.9)
	_crt_mat.set_shader_parameter("bloom_spread", 0.8)
	_crt_mat.set_shader_parameter("bloom_intensity", 0.4)
	_crt_mat.set_shader_parameter("phosphor_color", Color(0.1, 1.0, 0.2, 1.0))
	_crt_mat.set_shader_parameter("phosphor_boost", 0.2)
	_crt_mat.set_shader_parameter("brightness", 1.2)
	_crt_mat.set_shader_parameter("contrast", 1.1)
	_crt_mat.set_shader_parameter("max_brightness", 1.0)
	_crt_mat.set_shader_parameter("tonemap_compensation", 1.6)
	_crt_mat.set_shader_parameter("glitch_intensity", 0.0)
	_crt_mat.set_shader_parameter("glitch_line_speed", 8.0)
	_crt_mat.set_shader_parameter("glitch_line_density", 10.0)
	_crt_mat.set_shader_parameter("glitch_color_drift", 0.0)
	_crt_mat.set_shader_parameter("noise_burst", 0.0)
	_crt_mat.set_shader_parameter("shake_offset", Vector2.ZERO)
	_crt_mat.set_shader_parameter("screen_height_ratio", 1.0)
	_crt_mat.set_shader_parameter("boot_glow", 0.0)

	# 创建 CanvasLayer（高层级，覆盖所有 UI）
	_crt_layer = CanvasLayer.new()
	_crt_layer.name = "CRTEffect"
	_crt_layer.layer = 10
	add_child(_crt_layer)

	# 创建全屏 ColorRect 应用 shader
	_crt_rect = ColorRect.new()
	_crt_rect.material = _crt_mat
	_crt_rect.color = Color.BLACK
	_crt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crt_layer.add_child(_crt_rect)

	_update_crt_size()

func _update_crt_size() -> void:
	if _crt_rect == null:
		return
	var vp_size: Vector2 = get_viewport_rect().size
	_crt_rect.position = Vector2.ZERO
	_crt_rect.size = vp_size

# ══════════════════════════════════════════
#  摄像头系统初始化
# ══════════════════════════════════════════
func _init_camera_system() -> void:
	camera_mgr = CameraManager.new()
	camera_mgr.setup(self)
	camera_mgr.load_from_manifest(DemoSlides.DEMO_CAMERAS.duplicate(true))

	camera_viewer = CameraViewer.new()
	camera_viewer.setup(self, camera_mgr)

# ══════════════════════════════════════════
#  幻灯片渲染
# ══════════════════════════════════════════
func _show_slide(index: int) -> void:
	if index < 0 or index >= _slides.size():
		return
	_current_slide = index
	var slide: Dictionary = _slides[index]
	var stype: String = slide.get("type", "content")
	var w: float = size.x
	var h: float = size.y

	# 隐藏所有可选元素
	_subtitle_label.visible = false
	_members_label.visible = false
	_footer_label.visible = false
	_body_text.visible = false
	_slide_image.visible = false
	_diagram_canvas.visible = false
	_code_panel.visible = false
	_camera_button.visible = false

	# 底部栏
	_bottom_bar.position = Vector2(0, h - 36)
	_bottom_bar.size = Vector2(w, 36)
	_page_indicator.position = Vector2(w - 120, 0)
	_page_indicator.size = Vector2(110, 36)
	_page_indicator.text = "%d / %d" % [index + 1, _slides.size()]
	_nav_hint.position = Vector2(0, 0)
	_nav_hint.size = Vector2(w, 36)
	_nav_hint.text = "← 上一页  |  下一页 →"

	# 标题（所有类型通用）
	var title: String = slide.get("title", "")
	_title_label.text = title

	match stype:
		"title":
			_render_title_slide(slide, w, h)
		"content":
			_render_content_slide(slide, w, h)
		"diagram":
			_render_diagram_slide(slide, w, h)
		"code":
			_render_code_slide(slide, w, h)
		"camera_link":
			_render_camera_link_slide(slide, w, h)

	_diagram_canvas.queue_redraw()
	_update_click_zones()

func _render_title_slide(slide: Dictionary, w: float, h: float) -> void:
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.position = Vector2(0, h * 0.28)
	_title_label.size = Vector2(w, 50)

	if slide.has("subtitle"):
		_subtitle_label.visible = true
		_subtitle_label.text = slide["subtitle"]
		_subtitle_label.position = Vector2(0, h * 0.42)
		_subtitle_label.size = Vector2(w, 30)

	if slide.has("members") and not slide["members"].is_empty():
		_members_label.visible = true
		_members_label.text = slide["members"]
		_members_label.position = Vector2(0, h * 0.54)
		_members_label.size = Vector2(w, 26)

	if slide.has("footer") and not slide["footer"].is_empty():
		_footer_label.visible = true
		_footer_label.text = slide["footer"]
		_footer_label.position = Vector2(0, h * 0.72)
		_footer_label.size = Vector2(w, 24)

func _render_content_slide(slide: Dictionary, w: float, h: float) -> void:
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title_label.position = Vector2(60, 35)
	_title_label.size = Vector2(w - 120, 44)

	var has_image: bool = slide.has("image") and not slide["image"].is_empty()
	var body_w: float = w * 0.52 if has_image else w - 120

	_body_text.visible = true
	_body_text.position = Vector2(60, 95)
	_body_text.size = Vector2(body_w, h - 140)
	_set_body_text_with_math(_body_text, slide.get("body", ""))

	if has_image:
		_load_slide_image(slide["image"], w * 0.58, 95, w * 0.36, h - 140)

func _render_diagram_slide(slide: Dictionary, w: float, h: float) -> void:
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title_label.position = Vector2(60, 35)
	_title_label.size = Vector2(w - 120, 44)

	var has_code: bool = slide.has("code") and not slide["code"].is_empty()
	var body_h: float = h - 140
	var body_y: float = 95

	if has_code:
		body_h = h * 0.42

	_body_text.visible = true
	_body_text.position = Vector2(60, body_y)
	_body_text.size = Vector2(w * 0.45, body_h)
	_set_body_text_with_math(_body_text, slide.get("body", ""))

	# 图表
	var diagram_type: String = slide.get("diagram", "")
	if not diagram_type.is_empty():
		_diagram_canvas.visible = true
		_diagram_canvas.diagram_type = diagram_type
		_diagram_canvas.position = Vector2(w * 0.52, body_y)
		_diagram_canvas.size = Vector2(w * 0.42, body_h)

	# 代码
	if has_code:
		_code_panel.visible = true
		var code_y: float = body_y + body_h + 30
		_code_panel.position = Vector2(60, code_y)
		_code_panel.size = Vector2(w - 120, h - code_y - 90)
		_code_label.position = Vector2(16, 12)
		_code_label.size = Vector2(_code_panel.size.x - 32, _code_panel.size.y - 24)
		_render_code(_code_label, slide["code"], slide.get("code_lang", "gdscript"))

func _render_code_slide(slide: Dictionary, w: float, h: float) -> void:
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title_label.position = Vector2(60, 35)
	_title_label.size = Vector2(w - 120, 44)

	_body_text.visible = true
	_body_text.position = Vector2(60, 95)
	_body_text.size = Vector2(w - 120, 90)
	_set_body_text_with_math(_body_text, slide.get("body", ""))

	var code_y: float = 200
	_code_panel.visible = true
	_code_panel.position = Vector2(60, code_y)
	_code_panel.size = Vector2(w - 120, h - code_y - 90)
	_code_label.position = Vector2(16, 12)
	_code_label.size = Vector2(_code_panel.size.x - 32, _code_panel.size.y - 24)
	_render_code(_code_label, slide["code"], slide.get("code_lang", "gdscript"))

func _render_camera_link_slide(slide: Dictionary, w: float, h: float) -> void:
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title_label.position = Vector2(60, 35)
	_title_label.size = Vector2(w - 120, 44)

	var has_image: bool = slide.has("image") and not slide["image"].is_empty()
	var body_w: float = w * 0.52 if has_image else w - 120

	_body_text.visible = true
	_body_text.position = Vector2(60, 95)
	_body_text.size = Vector2(body_w, h - 200)
	_set_body_text_with_math(_body_text, slide.get("body", ""))

	if has_image:
		var img_x: float = slide.get("image_x", w * 0.50)
		var img_y: float = slide.get("image_y", 200.0)
		var img_w: float = slide.get("image_w", w * 0.26)
		var img_h: float = slide.get("image_h", h - 400.0)
		_load_slide_image(slide["image"], img_x, img_y, img_w, img_h)

	# 摄像头按钮
	_camera_button.visible = true
	var btn_w: float = 280
	var btn_h: float = 50
	_camera_button.position = Vector2((w - btn_w) * 0.5, h - 90)
	_camera_button.size = Vector2(btn_w, btn_h)

func _load_slide_image(asset_id: String, x: float, y: float, w: float, h: float) -> void:
	var tex: Texture2D = DemoSlides.load_placeholder(asset_id)
	if tex:
		_slide_image.visible = true
		_slide_image.texture = tex
		_slide_image.position = Vector2(x, y)
		_slide_image.size = Vector2(w, h)
	else:
		# 显示占位框
		_slide_image.visible = false
		_diagram_canvas.visible = true
		_diagram_canvas.diagram_type = "placeholder"
		_diagram_canvas.placeholder_text = "【占位】" + DemoSlides.get_placeholder_description(asset_id)
		_diagram_canvas.position = Vector2(x, y)
		_diagram_canvas.size = Vector2(w, h)

# ══════════════════════════════════════════
#  代码高亮
# ══════════════════════════════════════════
func _render_code(rtl: RichTextLabel, code: String, lang: String) -> void:
	rtl.clear()
	var keywords: Array = GD_KEYWORDS if lang == "gdscript" else GL_KEYWORDS
	var types: Array = GD_TYPES if lang == "gdscript" else []
	var funcs: Array = GL_FUNCS if lang == "glsl" else []
	var comment_str: String = "#" if lang == "gdscript" else "//"

	var lines: PackedStringArray = code.split("\n")
	for i in range(lines.size()):
		if i > 0:
			rtl.add_text("\n")
		_render_code_line(rtl, lines[i], comment_str, keywords, types, funcs)

func _render_code_line(rtl: RichTextLabel, line: String, comment_str: String,
		keywords: Array, types: Array, funcs: Array) -> void:
	var comment_idx: int = line.find(comment_str)
	var code_part: String = line
	var comment_part: String = ""
	if comment_idx >= 0:
		code_part = line.substr(0, comment_idx)
		comment_part = line.substr(comment_idx)

	_render_tokens(rtl, code_part, keywords, types, funcs)

	if not comment_part.is_empty():
		rtl.push_color(COL_COMMENT)
		rtl.add_text(comment_part)
		rtl.pop()

func _render_tokens(rtl: RichTextLabel, text: String,
		keywords: Array, types: Array, funcs: Array) -> void:
	var i: int = 0
	var n: int = text.length()
	while i < n:
		var ch: String = text[i]

		if ch == '"':
			var end_idx: int = text.find('"', i + 1)
			if end_idx < 0:
				end_idx = n
			else:
				end_idx += 1
			rtl.push_color(COL_STRING)
			rtl.add_text(text.substr(i, end_idx - i))
			rtl.pop()
			i = end_idx
		elif ch == " " or ch == "\t":
			rtl.add_text(ch)
			i += 1
		elif _is_ident_start(ch):
			var end_idx: int = i + 1
			while end_idx < n and _is_ident_char(text[end_idx]):
				end_idx += 1
			var word: String = text.substr(i, end_idx - i)
			if keywords.has(word):
				rtl.push_color(COL_KEYWORD)
				rtl.add_text(word)
				rtl.pop()
			elif types.has(word):
				rtl.push_color(COL_TYPE)
				rtl.add_text(word)
				rtl.pop()
			elif funcs.has(word):
				rtl.push_color(COL_FUNC)
				rtl.add_text(word)
				rtl.pop()
			else:
				var j: int = end_idx
				while j < n and text[j] == " ":
					j += 1
				if j < n and text[j] == "(":
					rtl.push_color(COL_FUNC)
					rtl.add_text(word)
					rtl.pop()
				else:
					rtl.push_color(COL_DEFAULT)
					rtl.add_text(word)
					rtl.pop()
			i = end_idx
		elif _is_digit(ch):
			var end_idx: int = i + 1
			while end_idx < n and (_is_digit(text[end_idx]) or text[end_idx] == "."):
				end_idx += 1
			rtl.push_color(COL_NUMBER)
			rtl.add_text(text.substr(i, end_idx - i))
			rtl.pop()
			i = end_idx
		else:
			rtl.push_color(COL_DEFAULT)
			rtl.add_text(ch)
			rtl.pop()
			i += 1

func _is_ident_start(ch: String) -> bool:
	return (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch == "_"

func _is_ident_char(ch: String) -> bool:
	return _is_ident_start(ch) or (ch >= "0" and ch <= "9")

func _is_digit(ch: String) -> bool:
	return ch >= "0" and ch <= "9"

# ══════════════════════════════════════════
#  图表绘制（由 _DiagramCanvas._draw 调用）
# ══════════════════════════════════════════
func _draw_diagram(canvas_node: Control) -> void:
	var dc: _DiagramCanvas = canvas_node as _DiagramCanvas
	if dc == null:
		return
	match dc.diagram_type:
		"priority_chain":
			_draw_priority_chain(dc)
		"float_pipeline":
			_draw_float_pipeline(dc)
		"pom_stepping":
			_draw_pom_stepping(dc)
		"system_overview":
			_draw_system_overview(dc)
		"pom_principle":
			_draw_pom_principle(dc)
		"problem_comparison":
			_draw_problem_comparison(dc)
		"local_variation":
			_draw_local_variation(dc)
		"compare_result":
			_draw_compare_result(dc)
		"placeholder":
			_draw_placeholder(dc)

# ═══════════════════════════════════════════════════════════════
#  代码绘图函数索引表
#  所有图表均在 demo_camera.gd 中，由 _DiagramCanvas._draw() 触发
#  调用路径: _show_slide() → _render_diagram_slide() → _diagram_canvas.queue_redraw() → _draw_diagram() → match
#
#  ┌──────────┬───────────────────────────┬────────────────────────────────┬────────────┐
#  │ 幻灯片页  │ diagram_type 字符串        │ 绘图函数                        │ 行号(约)   │
#  ├──────────┼───────────────────────────┼────────────────────────────────┼────────────┤
#  │ Slide 2  │ "system_overview"         │ _draw_system_overview()        │ ~780       │
#  │ Slide 3  │ "pom_principle"           │ _draw_pom_principle()          │ ~845       │
#  │ Slide 4  │ "pom_stepping"            │ _draw_pom_stepping()           │ ~640       │
#  │ Slide 5  │ "problem_comparison"      │ _draw_problem_comparison()     │ ~1120      │
#  │ Slide 6  │ "priority_chain"          │ _draw_priority_chain()         │ ~572       │
#  │ Slide 7  │ "local_variation"         │ _draw_local_variation()        │ ~1220      │
#  │ Slide 8  │ "float_pipeline"          │ _draw_float_pipeline()         │ ~880       │
#  │ Slide 13 │ "compare_result"          │ _draw_compare_result()         │ ~1330      │
#  │ (占位)   │ "placeholder"             │ _draw_placeholder()            │ ~1410      │
#  └──────────┴───────────────────────────┴────────────────────────────────┴────────────┘
#
#  辅助函数:
#    _draw_gradient_rect()  — 32 条细矩形模拟水平/垂直渐变（~1390）
#    _draw_centered_text()  — 居中绘制文字（~905）
#    _draw_arrow()          — 带箭头头的直线（~910）
#
#  通用变量说明（每个函数开头都有）:
#    w, h      = 画布宽高（随窗口缩放自适应）
#    margin    = 四周留白像素
#    cx, cy    = 各子图中心坐标
#    fs        = 字号
#    col_*     = 各类颜色定义，用 Color(r, g, b, a) 表示，a=透明度 0~1
#
#  微调技巧:
#    • 调整文字大小: 修改 fs / font_size 变量
#    • 调整间距:     修改 margin / gap / bar_h 变量
#    • 调整颜色:     修改 col_* 变量或 colors_top/colors_bot 数组
#    • 调整位置:     修改 cx / cy / y1~y4 等坐标变量
#    • 调整大小:     修改 box_w / box_h / panel_w / panel_h 变量
# ═══════════════════════════════════════════════════════════════

# ── Slide 6: 优先级链图 ──
# 5 条水平渐变色块，从上到下优先级递减
# 右侧有"高→低"标注箭头
func _draw_priority_chain(dc: _DiagramCanvas) -> void:
	var w: float = dc.size.x          # 画布宽
	var h: float = dc.size.y          # 画布高
	var bar_h: float = h / 5.0        # 每条色块高度 = 总高/5
	var font: Font = _font_regular if _font_regular else ThemeDB.fallback_font
	var font_size: int = 14           # ← 调整文字大小

	# 5 条标签（从高到低）
	var labels: Array[String] = ["Layer (最高优先级)", "Mask", "Polygon", "Raw Depth Fallback", "Default (最低优先级)"]
	# 每条的渐变顶部颜色（亮色）
	var colors_top: Array[Color] = [
		Color(0.3, 0.6, 1.0),      # 蓝 — Layer
		Color(0.2, 0.8, 0.4),      # 绿 — Mask
		Color(0.2, 0.7, 0.8),      # 青 — Polygon
		Color(0.9, 0.8, 0.2),      # 黄 — Raw Depth
		Color(0.5, 0.5, 0.5),      # 灰 — Default
	]
	# 每条的渐变底部颜色（暗色）
	var colors_bot: Array[Color] = [
		Color(0.15, 0.3, 0.5),
		Color(0.1, 0.4, 0.2),
		Color(0.1, 0.35, 0.4),
		Color(0.45, 0.4, 0.1),
		Color(0.25, 0.25, 0.25),
	]

	# 绘制 5 条色块
	for i in range(5):
		var y: float = i * bar_h + 4                    # 第 i 条的 y 起点（+4px 上边距）
		var bh: float = bar_h - 8                       # 实际色块高度（上下各留 4px）
		# 渐变填充：从左(colors_top)到右(colors_bot)
		_draw_gradient_rect(dc, Rect2(10, y, w - 20, bh), colors_top[i], colors_bot[i], true)
		# 白色半透明边框
		dc.draw_rect(Rect2(10, y, w - 20, bh), Color(1, 1, 1, 0.15), false, 1.0)
		# 文字标签（左对齐，垂直居中，深色字）
		dc.draw_string(font, Vector2(24, y + bh * 0.5 + font_size * 0.35),
			labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.05, 0.08, 0.05))

	# 右侧优先级箭头（从上"高"到下"低"）
	var arrow_x: float = w - 8         # ← 调整箭头 x 位置
	var arrow_y0: float = 8            # 箭头顶端 y
	var arrow_y1: float = h - 8        # 箭头底端 y
	dc.draw_line(Vector2(arrow_x, arrow_y0), Vector2(arrow_x, arrow_y1), Color(1, 0.8, 0.2, 0.7), 2)
	dc.draw_string(font, Vector2(arrow_x - 50, arrow_y0 - 2), "高", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.8, 0.2, 0.7))
	dc.draw_string(font, Vector2(arrow_x - 50, arrow_y1 + 12), "低", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.8, 0.2, 0.7))

# ── Slide 8: 浮点深度管线流程图 ──
# 6 步纵向 + 横向混合：ByteArray→FloatArray→Mask两遍→Fallback→Smooth→FORMAT_RF
func _draw_float_pipeline(dc: _DiagramCanvas) -> void:
	var w: float = dc.size.x
	var h: float = dc.size.y
	var font: Font = _font_regular if _font_regular else ThemeDB.fallback_font
	var font_size: int = 12

	var steps: Array[String] = [
		"Float32 初始化",
		"Polygon/Mask",
		"Mask 两遍算法",
		"Raw Fallback",
		"边缘平滑",
		"FORMAT_RF",
	]
	var colors: Array[Color] = [
		Color(0.2, 0.7, 0.8),
		Color(0.2, 0.8, 0.4),
		Color(0.9, 0.8, 0.2),
		Color(0.3, 0.6, 1.0),
		Color(0.7, 0.3, 0.9),
		Color(0.5, 0.9, 0.6),
	]

	var box_h: float = 50
	var row_gap: float = 26
	var arrow_w: float = 14
	var margin: float = 10

	# 2 行 × 3 列，每行 2 个箭头
	var box_w: float = (w - margin * 2 - arrow_w * 2) / 3.0

	# 两行整体垂直居中
	var rows_h: float = box_h * 2 + row_gap
	var row1_y: float = (h - rows_h) * 0.5
	var row2_y: float = row1_y + box_h + row_gap

	# 顶部标题
	var title_y: float = row1_y - 18
	var title_text: String = "浮点深度合成管线（6 步）"
	var tw: float = font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	dc.draw_string(font, Vector2((w - tw) * 0.5, title_y), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.7, 0.6, 0.7))

	# Row 1: 步骤 0-2 (左→右)
	for i in 3:
		var idx: int = i
		var x: float = margin + i * (box_w + arrow_w)
		_draw_pipeline_box(dc, font, x, row1_y, box_w, box_h, steps[idx], colors[idx])
		if i < 2:
			_draw_arrow(dc, x + box_w + 2, row1_y + box_h * 0.5, x + box_w + arrow_w - 2, row1_y + box_h * 0.5, Color(0.7, 0.8, 0.7, 0.6))

	# 步骤 2 → 步骤 3 的向下箭头
	var mid_x: float = margin + 2 * (box_w + arrow_w) + box_w * 0.5
	_draw_arrow(dc, mid_x, row1_y + box_h + 2, mid_x, row2_y - 2, Color(0.7, 0.8, 0.7, 0.6))

	# Row 2: 步骤 3-5 (左→右)
	for i in 3:
		var idx: int = i + 3
		var x: float = margin + i * (box_w + arrow_w)
		_draw_pipeline_box(dc, font, x, row2_y, box_w, box_h, steps[idx], colors[idx])
		if i < 2:
			_draw_arrow(dc, x + box_w + 2, row2_y + box_h * 0.5, x + box_w + arrow_w - 2, row2_y + box_h * 0.5, Color(0.7, 0.8, 0.7, 0.6))

	# 底部标注：PackedFloat32Array + FORMAT_RF
	var bottom_y: float = row2_y + box_h + 16
	var bt: String = "PackedFloat32Array → Image.FORMAT_RF (32-bit float)"
	var btw: float = font.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	dc.draw_string(font, Vector2((w - btw) * 0.5, bottom_y), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.8, 1.0, 0.8))

func _draw_pipeline_box(dc: _DiagramCanvas, font: Font, x: float, y: float, bw: float, bh: float, label: String, col: Color) -> void:
	var fs: int = 12
	_draw_gradient_rect(dc, Rect2(x, y, bw, bh), col.darkened(0.7), col.darkened(0.85), true)
	dc.draw_rect(Rect2(x, y, bw, bh), Color(1, 1, 1, 0.15), false, 1.5)
	_draw_centered_text(dc, font, label, x + bw * 0.5, y + bh * 0.5, fs, Color(0.78, 0.9, 0.78))

# ── Slide 4: POM 步进采样示意图 ──
# 8 步阶梯路径模拟深度曲线，采样点用圆点标注
# 网格背景 + 交点高亮
func _draw_pom_stepping(dc: _DiagramCanvas) -> void:
	var w: float = dc.size.x
	var h: float = dc.size.y
	var font: Font = _font_regular if _font_regular else ThemeDB.fallback_font
	var font_size: int = 13

	var margin: float = 20              # ← 调整四周边距
	var cw: float = w - margin * 2      # 内容区宽
	var ch: float = h - margin * 2 - 20 # 内容区高（底部留 20px 给标注）

	# 左上角标注
	dc.draw_string(font, Vector2(margin, margin + 12), "深度值", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.6, 0.7, 0.6))
	# 右下角标注
	dc.draw_string(font, Vector2(w - margin - 40, h - margin - 4), "步进方向 →", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.6, 0.7, 0.6))

	# 竖直网格线（8+1 条）
	var steps: int = 8                  # ← 调整步数
	var step_w: float = cw / float(steps)
	for i in range(steps + 1):
		var gx: float = margin + i * step_w
		dc.draw_line(Vector2(gx, margin + 20), Vector2(gx, margin + 20 + ch), Color(0.15, 0.25, 0.15), 1)

	# 步进路径：从右下到左上的阶梯折线
	var prev_y: float = margin + 20 + ch * 0.8   # 起始 y（底部 80% 处）
	for i in range(steps):
		var sx: float = margin + i * step_w      # 当前步 x
		# y 随步数上升（模拟深度递减）
		var sy: float = margin + 20 + ch * (0.8 - float(i) / float(steps) * 0.6)
		# 垂直线（上升段）
		dc.draw_line(Vector2(sx, prev_y), Vector2(sx, sy), Color(0.5, 0.8, 0.5, 0.8), 2)
		# 水平线（步进段）
		var next_x: float = margin + (i + 1) * step_w
		dc.draw_line(Vector2(sx, sy), Vector2(next_x, sy), Color(0.5, 0.8, 0.5, 0.8), 2)
		# 采样点（绿色圆点）
		dc.draw_circle(Vector2(sx, sy), 4, Color(0.7, 1.0, 0.7))
		prev_y = sy

	# 交点标注（黄色大圆 + 文字）
	var hit_x: float = margin + steps * step_w * 0.625   # 交点 x（约 60% 处）
	var hit_y: float = margin + 20 + ch * 0.42          # 交点 y
	dc.draw_circle(Vector2(hit_x, hit_y), 6, Color(1.0, 0.8, 0.2))
	dc.draw_string(font, Vector2(hit_x + 10, hit_y - 8), "交点", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.8, 0.2))

# ── Slide 2: 系统架构总览 ──
# 4 层垂直流程：2D底图 → 灰度深度图 → POM视差Shader → 伪3D画面
# 每层一个渐变方框 + 向下箭头 + 右侧标注（输入/深度/计算/输出）
func _draw_system_overview(dc: _DiagramCanvas) -> void:
	var w: float = dc.size.x
	var h: float = dc.size.y
	var font: Font = _font_regular if _font_regular else ThemeDB.fallback_font
	var fs: int = 13                    # ← 调整方框内文字大小
	# 颜色定义
	var col_line: Color = Color(0.4, 0.7, 0.4, 0.8)    # 方框边框（绿色）
	var col_text: Color = Color(0.7, 0.9, 0.7)         # 方框文字
	var col_dim: Color = Color(0.4, 0.55, 0.4)         # 标注/标题（暗绿）
	var col_accent: Color = Color(0.3, 0.8, 1.0, 0.9)  # Shader 方框边框（蓝色高亮）

	# 顶部标题
	dc.draw_string(font, Vector2(w * 0.5 - 70, 18), "深度图 → 伪 3D 管线", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col_dim)

	# 布局参数
	var box_w: float = w * 0.4         # ← 调整方框宽度（占画布 40%）
	var box_h: float = 44               # ← 调整方框高度
	var cx: float = w * 0.5             # 水平居中
	var gap: float = 16                 # ← 调整方框间垂直间距

	# ── 第 1 层：2D 底图 ──
	var y1: float = 40                  # ← 调整第一层 y 起点
	_draw_gradient_rect(dc, Rect2(cx - box_w * 0.5, y1, box_w, box_h), Color(0.15, 0.3, 0.15), Color(0.08, 0.15, 0.08), true)
	dc.draw_rect(Rect2(cx - box_w * 0.5, y1, box_w, box_h), col_line, false, 1.5)
	_draw_centered_text(dc, font, "2D 底图 (base.png)", cx, y1 + box_h * 0.5, fs, col_text)

	# 向下箭头
	_draw_arrow(dc, cx, y1 + box_h + 2, cx, y1 + box_h + gap - 2, col_line)

	# ── 第 2 层：灰度深度图 ──
	var y2: float = y1 + box_h + gap
	_draw_gradient_rect(dc, Rect2(cx - box_w * 0.5, y2, box_w, box_h), Color(0.15, 0.25, 0.2), Color(0.08, 0.12, 0.1), true)
	dc.draw_rect(Rect2(cx - box_w * 0.5, y2, box_w, box_h), col_line, false, 1.5)
	_draw_centered_text(dc, font, "灰度深度图 (depth.png)", cx, y2 + box_h * 0.5, fs, col_text)

	_draw_arrow(dc, cx, y2 + box_h + 2, cx, y2 + box_h + gap - 2, col_line)

	# ── 第 3 层：POM 视差 Shader（蓝色高亮）──
	var y3: float = y2 + box_h + gap
	_draw_gradient_rect(dc, Rect2(cx - box_w * 0.5, y3, box_w, box_h), Color(0.1, 0.2, 0.3), Color(0.05, 0.1, 0.15), true)
	dc.draw_rect(Rect2(cx - box_w * 0.5, y3, box_w, box_h), col_accent, false, 1.5)
	_draw_centered_text(dc, font, "POM 视差 Shader", cx, y3 + box_h * 0.5, fs, Color(0.5, 0.8, 1.0))

	_draw_arrow(dc, cx, y3 + box_h + 2, cx, y3 + box_h + gap - 2, col_line)

	# ── 第 4 层：伪 3D 监控画面（暖色输出）──
	var y4: float = y3 + box_h + gap
	_draw_gradient_rect(dc, Rect2(cx - box_w * 0.5, y4, box_w, box_h), Color(0.2, 0.15, 0.05), Color(0.1, 0.08, 0.03), true)
	dc.draw_rect(Rect2(cx - box_w * 0.5, y4, box_w, box_h), Color(0.7, 0.6, 0.2, 0.7), false, 1.5)
	_draw_centered_text(dc, font, "伪 3D 监控画面", cx, y4 + box_h * 0.5, fs, Color(0.9, 0.85, 0.5))

	# 右侧标注（输入/深度/计算/输出）
	var label_x: float = cx + box_w * 0.5 + 12   # ← 调整标注 x 位置
	dc.draw_string(font, Vector2(label_x, y1 + box_h * 0.5 + 5), "输入", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col_dim)
	dc.draw_string(font, Vector2(label_x, y2 + box_h * 0.5 + 5), "深度", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col_dim)
	dc.draw_string(font, Vector2(label_x, y3 + box_h * 0.5 + 5), "计算", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col_dim)
	dc.draw_string(font, Vector2(label_x, y4 + box_h * 0.5 + 5), "输出", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col_dim)

# ── Slide 3: POM 视差原理示意图 ──
# 左侧观察者眼睛 → 视线连接到三个不同深度的物体
# 每个物体有水平偏移箭头（偏移量随深度增大）
func _draw_pom_principle(dc: _DiagramCanvas) -> void:
	var w: float = dc.size.x
	var h: float = dc.size.y
	var font: Font = _font_regular if _font_regular else ThemeDB.fallback_font
	var fs: int = 12
	# 颜色定义
	var col_line: Color = Color(0.4, 0.7, 0.4, 0.8)   # 视线/边框
	var col_dim: Color = Color(0.4, 0.55, 0.4)        # 标注文字
	var col_near: Color = Color(0.3, 0.8, 0.3, 0.8)   # 近处物体（亮绿）
	var col_far: Color = Color(0.2, 0.4, 0.2, 0.6)    # 远处物体（暗绿）
	var col_eye: Color = Color(1.0, 0.8, 0.2, 0.9)    # 眼睛（黄色）
	var col_offset: Color = Color(0.9, 0.5, 0.2, 0.7) # 偏移箭头（橙色）

	var margin: float = 16
	var cw: float = w - margin * 2
	var ch: float = h - margin * 2 - 16

	# 标题
	dc.draw_string(font, Vector2(w * 0.5 - 50, 16), "视差原理示意", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col_dim)

	# ── 左侧：观察者（黄色圆 + "观察者"标注）──
	var eye_x: float = margin + 20      # ← 调整眼睛 x 位置
	var eye_y: float = margin + 20 + ch * 0.5  # 垂直居中
	dc.draw_circle(Vector2(eye_x, eye_y), 8, col_eye)  # ← 调整眼睛半径
	dc.draw_string(font, Vector2(eye_x - 10, eye_y + 24), "观察者", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col_dim)

	# ── 右侧：底图平面（竖线）──
	var plane_x: float = margin + cw * 0.75  # ← 调整底图平面 x 位置
	dc.draw_line(Vector2(plane_x, margin + 20), Vector2(plane_x, margin + 20 + ch), Color(0.3, 0.5, 0.3, 0.5), 1.5)
	dc.draw_string(font, Vector2(plane_x - 16, margin + 14), "底图", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col_dim)

	# ── 三个物体（不同深度，y 错开排列）──
	# depth: 0.0=最远, 1.0=最近
	# y: 0.25=上(远), 0.5=中, 0.75=下(近)
	var objs: Array = [
		{"y": ch * 0.25, "depth": 0.2, "label": "远处"},   # 深度小=远，偏移小
		{"y": ch * 0.5, "depth": 0.5, "label": "中处"},   # 中等
		{"y": ch * 0.75, "depth": 0.85, "label": "近处"}, # 深度大=近，偏移大
	]

	for obj in objs:
		var oy: float = margin + 20 + obj["y"]
		var d: float = obj["depth"]
		# 物体 x 位置：深度越大越靠左（离观察者越近）
		var obj_x: float = plane_x - d * cw * 0.35   # ← 调整深度偏移系数 0.35
		# 物体颜色：远暗近亮
		var obj_col: Color = col_far.lerp(col_near, d)
		# 物体圆点
		dc.draw_circle(Vector2(obj_x, oy), 6, obj_col)
		# 视线（眼睛→物体）
		dc.draw_line(Vector2(eye_x, eye_y), Vector2(obj_x, oy), obj_col, 1)
		# 偏移箭头（水平向左，长度 = depth * 30）
		var off_len: float = d * 30     # ← 调整偏移箭头最大长度
		dc.draw_line(Vector2(obj_x, oy), Vector2(obj_x - off_len, oy), col_offset, 2)
		# 箭头头（两条短斜线）
		dc.draw_line(Vector2(obj_x - off_len, oy), Vector2(obj_x - off_len + 4, oy - 3), col_offset, 2)
		dc.draw_line(Vector2(obj_x - off_len, oy), Vector2(obj_x - off_len + 4, oy + 3), col_offset, 2)
		# 物体标注（右侧）
		dc.draw_string(font, Vector2(obj_x + 12, oy + 4), obj["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col_dim)

	# 底部标注
	dc.draw_string(font, Vector2(margin + 10, h - margin - 2), "← 偏移量随深度增大", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col_offset)

# ── 辅助函数：居中绘制文字 ──
# cx, cy = 文字中心坐标；font_size = 字号；col = 颜色
func _draw_centered_text(dc: Control, font: Font, text: String, cx: float, cy: float, font_size: int, col: Color) -> void:
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	dc.draw_string(font, Vector2(cx - tw * 0.5, cy + font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)

# ── 辅助函数：带箭头头的直线 ──
# 自动判断水平/垂直方向，绘制对应朝向的箭头头
func _draw_arrow(dc: Control, x1: float, y1: float, x2: float, y2: float, col: Color) -> void:
	dc.draw_line(Vector2(x1, y1), Vector2(x2, y2), col, 1.5)
	var dy: float = y2 - y1
	var dx: float = x2 - x1
	if abs(dy) > abs(dx):
		# 垂直箭头：箭头头朝下/上
		dc.draw_line(Vector2(x2, y2), Vector2(x2 - 4, y2 - 4 * sign(dy)), col, 1.5)
		dc.draw_line(Vector2(x2, y2), Vector2(x2 + 4, y2 - 4 * sign(dy)), col, 1.5)
	else:
		# 水平箭头：箭头头朝右/左
		dc.draw_line(Vector2(x2, y2), Vector2(x2 - 4 * sign(dx), y2 - 4), col, 1.5)
		dc.draw_line(Vector2(x2, y2), Vector2(x2 - 4 * sign(dx), y2 + 4), col, 1.5)

# ── Slide 5: 三大缺陷示意图 ──
# 3 列等宽面板，每列展示一个问题：
#   ① 空间错位 — 墙 + 柱子无分离（红色边框标注"柱子=墙"）
#   ② 边缘撕裂 — 正弦曲线中间跳变（红色竖线标注"UV跳变"）
#   ③ 照明不准 — 同心圆照明 + 两个物体亮度相同（标注"近=远"）
func _draw_problem_comparison(dc: _DiagramCanvas) -> void:
	var w: float = dc.size.x
	var h: float = dc.size.y
	var font: Font = _font_regular if _font_regular else ThemeDB.fallback_font
	var fs: int = 11                    # ← 调整面板标题字号
	# 颜色定义
	var col_dim: Color = Color(0.4, 0.55, 0.4)    # 标注/标题
	var col_red: Color = Color(0.9, 0.3, 0.2, 0.9) # 面板标题红色
	var col_err: Color = Color(0.8, 0.2, 0.15)     # 错误标注红色

	var margin: float = 10             # ← 调整面板间间距
	var panel_w: float = (w - margin * 4) / 3.0  # 每列宽度（3列等分）
	var panel_h: float = h - margin * 2 - 16     # 面板高度

	# 标题
	dc.draw_string(font, Vector2(w * 0.5 - 40, 14), "三大缺陷示意", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col_dim)

	# 三个问题定义
	var problems: Array = [
		{"title": "① 空间错位", "type": "misalign"},
		{"title": "② 边缘撕裂", "type": "tear"},
		{"title": "③ 照明不准", "type": "light"},
	]

	for i in range(3):
		var px: float = margin + i * (panel_w + margin)  # 第 i 列 x 起点
		var py: float = margin + 16                       # 面板 y 起点
		# 面板背景（暗色半透明填充）
		dc.draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.06, 0.1, 0.06, 0.5), true)
		# 面板边框（暗红）
		dc.draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.2, 0.15, 0.1, 0.6), false, 1)
		# 面板标题（红色，居中）
		var tw: float = font.get_string_size(problems[i]["title"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		dc.draw_string(font, Vector2(px + (panel_w - tw) * 0.5, py + 18), problems[i]["title"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col_red)

		# 子图中心坐标
		var cx: float = px + panel_w * 0.5
		var cy: float = py + panel_h * 0.55
		match problems[i]["type"]:
			"misalign":
				# ── ① 空间错位：墙 + 柱子同深度无分离 ──
				var wall_col: Color = Color(0.3, 0.35, 0.3, 0.6)
				var pillar_col: Color = Color(0.35, 0.35, 0.35, 0.8)
				# 墙壁矩形（背景）
				dc.draw_rect(Rect2(cx - 35, cy - 30, 70, 50), wall_col, true)
				# 柱子矩形（贴在墙上，无偏移）
				dc.draw_rect(Rect2(cx - 8, cy - 20, 16, 40), pillar_col, true)
				# 红色边框标注柱子
				dc.draw_rect(Rect2(cx - 8, cy - 20, 16, 40), col_err, false, 1)
				# 错误标注文字
				dc.draw_string(font, Vector2(cx - 20, cy + 32), "柱子=墙", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col_err)
			"tear":
				# ── ② 边缘撕裂：正弦曲线在中间跳变 ──
				var line_col: Color = Color(0.3, 0.6, 0.3, 0.8)
				var prev: Vector2 = Vector2(cx - 35, cy - 25)
				for j in range(8):
					var jx: float = cx - 35 + j * 10       # x 均匀步进
					var jy: float = cy - 25 + sin(j * 1.5) * 8  # y 正弦波动
					if j == 4:
						jy += 15                           # 第 4 步制造跳变（撕裂）
					dc.draw_line(prev, Vector2(jx, jy), line_col, 2)
					# 在跳变处画红色竖线标注
					if j == 3 or j == 4:
						dc.draw_line(Vector2(jx, jy - 5), Vector2(jx, jy + 5), col_err, 1)
					prev = Vector2(jx, jy)
				dc.draw_string(font, Vector2(cx - 16, cy + 28), "UV跳变", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col_err)
			"light":
				# ── ③ 照明不准：同心圆衰减 + 两个物体亮度相同 ──
				var center: Vector2 = Vector2(cx, cy)
				# 同心圆（从大到小，模拟照明衰减）
				for r in range(30, 5, -5):
					var alpha: float = float(30 - r) / 30.0 * 0.3
					dc.draw_circle(center, float(r), Color(0.8, 0.7, 0.2, alpha))
				# 中心亮点
				dc.draw_circle(center, 3, Color(1.0, 0.9, 0.3))
				# 两个物体（左右各一个方块，亮度相同=错误）
				dc.draw_rect(Rect2(cx - 25, cy - 5, 8, 8), Color(0.5, 0.5, 0.5), true)  # 左（近处）
				dc.draw_rect(Rect2(cx + 17, cy - 5, 8, 8), Color(0.5, 0.5, 0.5), true)  # 右（远处，但亮度相同）
				dc.draw_string(font, Vector2(cx - 28, cy + 18), "近=远", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col_err)

# ── Slide 7: Mask 局部变化算法示意图 ──
# 上方公式：final = ref_distance + (raw - mean) × scale
# 下方三段管线：Pass 1 计算均值 → Pass 2 写入 ref+变化 → 输出
func _draw_local_variation(dc: _DiagramCanvas) -> void:
	var w: float = dc.size.x
	var h: float = dc.size.y
	var font: Font = _font_regular if _font_regular else ThemeDB.fallback_font
	var fs: int = 13
	var col_dim: Color = Color(0.4, 0.55, 0.4)
	var col_accent: Color = Color(0.3, 0.8, 1.0, 0.9)
	var col_ref: Color = Color(0.9, 0.8, 0.2, 0.9)
	var col_raw: Color = Color(0.3, 0.8, 0.4, 0.9)
	var col_result: Color = Color(0.5, 0.9, 0.6, 0.9)

	# ── 上方公式区 ──
	var cx: float = w * 0.5
	# 整体偏上居中：公式 + 标注 + 盒子 + 底部文字总高约 168px
	var total_h: float = 168.0
	var start_y: float = (h - total_h) * 0.5 - 40.0
	start_y = max(start_y, 10.0)

	var formula_y: float = start_y

	# 公式：final = ref_{dist} + (raw - μ) × scale（LaTeX 渲染）
	var formula_h: float = 16.0
	if _formula_local_variation:
		var fw2: float = _formula_local_variation.get_width()
		var fh2: float = _formula_local_variation.get_height()
		formula_h = fh2
		dc.draw_texture_rect(_formula_local_variation,
			Rect2(cx - fw2 * 0.5, formula_y, fw2, fh2), false)
	else:
		var formula: String = "final = ref_distance + (raw - mask_mean) × scale"
		var fw: float = font.get_string_size(formula, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		dc.draw_string(font, Vector2(cx - fw * 0.5, formula_y), formula,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col_accent)

	# 公式变量标注（三行，紧跟公式下方）
	var annot_y: float = formula_y + formula_h + 6
	var annot_fs: int = 10
	dc.draw_string(font, Vector2(cx - 120, annot_y), "ref = 绝对距离基准", HORIZONTAL_ALIGNMENT_LEFT, -1, annot_fs, col_ref)
	dc.draw_string(font, Vector2(cx - 120, annot_y + 14), "raw = 原深度图值", HORIZONTAL_ALIGNMENT_LEFT, -1, annot_fs, col_raw)
	dc.draw_string(font, Vector2(cx + 20, annot_y), "mean = mask 区域均值", HORIZONTAL_ALIGNMENT_LEFT, -1, annot_fs, col_dim)
	dc.draw_string(font, Vector2(cx + 20, annot_y + 14), "scale = 变化强度", HORIZONTAL_ALIGNMENT_LEFT, -1, annot_fs, col_dim)

	# ── 下方管线区（三段） ──
	var pipe_y: float = annot_y + 48   # 与标注区紧密衔接
	var box_h: float = 50
	var arrow_w: float = 20            # 缩小箭头间距，方框更靠近
	var n: int = 3
	var box_w: float = (w - arrow_w * (n - 1) - 20) / n

	var steps: Array = [
		{"label": "Pass 1: 计算均值", "color": col_raw},
		{"label": "Pass 2: ref + 变化", "color": col_ref},
		{"label": "输出: 浮点深度", "color": col_result},
	]

	for i in range(n):
		var x: float = 10 + i * (box_w + arrow_w)
		var col: Color = steps[i]["color"]
		_draw_gradient_rect(dc, Rect2(x, pipe_y, box_w, box_h), col.darkened(0.7), col.darkened(0.85), true)
		dc.draw_rect(Rect2(x, pipe_y, box_w, box_h), col, false, 1.5)
		var label: String = steps[i]["label"]
		var lw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		dc.draw_string(font, Vector2(x + (box_w - lw) * 0.5, pipe_y + box_h * 0.5 + 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.78, 0.9, 0.78))

		if i < n - 1:
			var ax: float = x + box_w + 4
			var ay: float = pipe_y + box_h * 0.5
			dc.draw_line(Vector2(ax, ay), Vector2(ax + arrow_w - 8, ay), Color(0.7, 0.8, 0.7, 0.6), 2)
			dc.draw_line(Vector2(ax + arrow_w - 8, ay), Vector2(ax + arrow_w - 12, ay - 5), Color(0.7, 0.8, 0.7, 0.6), 2)
			dc.draw_line(Vector2(ax + arrow_w - 8, ay), Vector2(ax + arrow_w - 12, ay + 5), Color(0.7, 0.8, 0.7, 0.6), 2)

	# 底部退化说明
	var degrade_y: float = pipe_y + box_h + 22
	var degrade: String = "scale = 0 → 退化为平坦模式（仅 ref_distance）"
	var dw: float = font.get_string_size(degrade, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	dc.draw_string(font, Vector2(cx - dw * 0.5, degrade_y), degrade, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col_dim)

# ── Slide 13: 效果对比图 ──
# 左右两个面板对比：
#   左 Per-Pixel（旧）— 红色框，柱子粘在墙上 + 撕裂线
#   右 Region Depth（新）— 绿色框，柱子与墙正确分离 + 深度差标注
#   中间水平箭头连接
func _draw_compare_result(dc: _DiagramCanvas) -> void:
	var w: float = dc.size.x
	var h: float = dc.size.y
	var font: Font = _font_regular if _font_regular else ThemeDB.fallback_font
	var fs: int = 12
	# 颜色定义
	var col_dim: Color = Color(0.4, 0.55, 0.4)      # 标题/标注
	var col_bad: Color = Color(0.7, 0.2, 0.15, 0.9)  # 旧方案红色
	var col_good: Color = Color(0.2, 0.7, 0.3, 0.9)  # 新方案绿色

	var margin: float = 12
	var panel_w: float = (w - margin * 3) * 0.5      # 左右各占一半
	var panel_h: float = h - margin * 2 - 16

	# 标题
	dc.draw_string(font, Vector2(w * 0.5 - 40, 14), "效果对比", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col_dim)

	# ══ 左侧：Per-Pixel（纯逐像素，问题）══
	var lx: float = margin
	var ly: float = margin + 16
	# 暗红色渐变背景
	_draw_gradient_rect(dc, Rect2(lx, ly, panel_w, panel_h), Color(0.15, 0.08, 0.05), Color(0.08, 0.04, 0.02), true)
	# 红色边框
	dc.draw_rect(Rect2(lx, ly, panel_w, panel_h), col_bad, false, 1.5)
	# 标题（红色，居中）
	var ltitle: String = "纯逐像素 (AI 深度图)"
	var ltw: float = font.get_string_size(ltitle, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	dc.draw_string(font, Vector2(lx + (panel_w - ltw) * 0.5, ly + 18), ltitle, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col_bad)

	# 子图中心
	var lcx: float = lx + panel_w * 0.5
	var lcy: float = ly + panel_h * 0.55
	# 墙壁（暗灰，背景）
	dc.draw_rect(Rect2(lcx - 40, lcy - 30, 80, 55), Color(0.25, 0.25, 0.22, 0.6), true)
	# 柱子（与墙同深度，无分离）
	dc.draw_rect(Rect2(lcx - 8, lcy - 22, 16, 45), Color(0.3, 0.3, 0.28, 0.8), true)
	# 红色边框标注柱子
	dc.draw_rect(Rect2(lcx - 8, lcy - 22, 16, 45), col_bad, false, 1)
	# 撕裂线（两条水平红线）
	dc.draw_line(Vector2(lcx - 35, lcy - 10), Vector2(lcx + 35, lcy - 10), col_bad, 1)
	dc.draw_line(Vector2(lcx - 35, lcy + 5), Vector2(lcx + 35, lcy + 5), Color(0.5, 0.15, 0.1, 0.5), 1)
	# 底部标注
	dc.draw_string(font, Vector2(lcx - 28, lcy + 38), "错位 + 撕裂", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col_bad)

	# ══ 右侧：区域优化（mask + 局部变化）══
	var rx: float = margin * 2 + panel_w
	var ry: float = margin + 16
	# 暗绿色渐变背景
	_draw_gradient_rect(dc, Rect2(rx, ry, panel_w, panel_h), Color(0.05, 0.12, 0.06), Color(0.02, 0.06, 0.03), true)
	# 绿色边框
	dc.draw_rect(Rect2(rx, ry, panel_w, panel_h), col_good, false, 1.5)
	# 标题（绿色，居中）
	var rtitle: String = "区域优化 (mask + 变化)"
	var rtw: float = font.get_string_size(rtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	dc.draw_string(font, Vector2(rx + (panel_w - rtw) * 0.5, ry + 18), rtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col_good)

	# 子图中心
	var rcx: float = rx + panel_w * 0.5
	var rcy: float = ry + panel_h * 0.55
	# 墙壁（更暗=更远）
	dc.draw_rect(Rect2(rcx - 40, rcy - 30, 80, 55), Color(0.15, 0.2, 0.15, 0.4), true)
	# 柱子（更亮=更近，有偏移分离 + 局部变化纹理）
	dc.draw_rect(Rect2(rcx - 10, rcy - 25, 20, 50), Color(0.2, 0.4, 0.2, 0.7), true)
	# 绿色边框标注柱子
	dc.draw_rect(Rect2(rcx - 10, rcy - 25, 20, 50), col_good, false, 1)
	# 局部变化纹理线（柱子内部，表示保留 3D 细节）
	dc.draw_line(Vector2(rcx - 6, rcy - 18), Vector2(rcx + 6, rcy - 18), Color(0.3, 0.6, 0.3, 0.4), 1)
	dc.draw_line(Vector2(rcx - 6, rcy - 5), Vector2(rcx + 6, rcy - 5), Color(0.3, 0.6, 0.3, 0.4), 1)
	dc.draw_line(Vector2(rcx - 6, rcy + 8), Vector2(rcx + 6, rcy + 8), Color(0.3, 0.6, 0.3, 0.4), 1)
	# 深度差标注线（L 形，表示墙和柱子有深度差）
	dc.draw_line(Vector2(rcx - 40, rcy + 28), Vector2(rcx - 12, rcy + 28), Color(0.3, 0.6, 0.3, 0.5), 1)
	dc.draw_line(Vector2(rcx - 12, rcy + 28), Vector2(rcx - 12, rcy + 22), Color(0.3, 0.6, 0.3, 0.5), 1)
	# 底部标注
	dc.draw_string(font, Vector2(rcx - 28, rcy + 38), "正确分离 + 3D 细节", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col_good)

	# ══ 中间箭头（左→右）══
	var ax: float = lx + panel_w + margin * 0.5
	var ay: float = ly + panel_h * 0.5
	_draw_arrow(dc, ax - 4, ay, ax + 4, ay, Color(0.6, 0.7, 0.6, 0.8))

# ── 占位框（图片素材缺失时显示虚线框 + 描述文字）──
func _draw_placeholder(dc: _DiagramCanvas) -> void:
	var w: float = dc.size.x
	var h: float = dc.size.y
	var font: Font = _font_regular if _font_regular else ThemeDB.fallback_font

	# 虚线框：四条边各用短线段拼接
	var dash_len: float = 8       # 每段虚线长度
	var gap_len: float = 6        # 虚线间隔
	var total: float = dash_len + gap_len
	# 上边
	var x: float = 0
	while x < w:
		dc.draw_line(Vector2(x, 0), Vector2(minf(x + dash_len, w), 0), Color(0.4, 0.5, 0.4, 0.6), 1.5)
		x += total
	# 下边
	x = 0
	while x < w:
		dc.draw_line(Vector2(x, h - 1), Vector2(minf(x + dash_len, w), h - 1), Color(0.4, 0.5, 0.4, 0.6), 1.5)
		x += total
	# 左边
	var y: float = 0
	while y < h:
		dc.draw_line(Vector2(0, y), Vector2(0, minf(y + dash_len, h)), Color(0.4, 0.5, 0.4, 0.6), 1.5)
		y += total
	# 右边
	y = 0
	while y < h:
		dc.draw_line(Vector2(w - 1, y), Vector2(w - 1, minf(y + dash_len, h)), Color(0.4, 0.5, 0.4, 0.6), 1.5)
		y += total

	# 居中描述文字
	var text: String = dc.placeholder_text
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	dc.draw_string(font, Vector2((w - tw) * 0.5, h * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 0.6, 0.5, 0.8))

# ── 辅助函数：渐变矩形 ──
# 用 32 条细矩形（draw_rect）模拟渐变，避免 GradientTexture2D API 兼容问题
# c1 = 起始颜色，c2 = 结束颜色，horizontal = true 水平渐变 / false 垂直渐变
func _draw_gradient_rect(dc: Control, rect: Rect2, c1: Color, c2: Color, horizontal: bool) -> void:
	var slices: int = 32            # ← 调大更平滑但更慢，调小更快但可能有条纹
	if horizontal:
		var slice_w: float = rect.size.x / float(slices)
		for i in range(slices):
			var t: float = float(i) / float(slices - 1)
			var col: Color = c1.lerp(c2, t)   # 线性插值颜色
			# +1px 避免接缝
			dc.draw_rect(Rect2(rect.position.x + i * slice_w, rect.position.y, slice_w + 1, rect.size.y), col, true)
	else:
		var slice_h: float = rect.size.y / float(slices)
		for i in range(slices):
			var t: float = float(i) / float(slices - 1)
			var col: Color = c1.lerp(c2, t)
			dc.draw_rect(Rect2(rect.position.x, rect.position.y + i * slice_h, rect.size.x, slice_h + 1), col, true)

# ══════════════════════════════════════════
#  导航
# ══════════════════════════════════════════
func _next_slide() -> void:
	if _current_slide < _slides.size() - 1:
		_show_slide(_current_slide + 1)

func _prev_slide() -> void:
	if _current_slide > 0:
		_show_slide(_current_slide - 1)

func _on_camera_button_pressed() -> void:
	var slide: Dictionary = _slides[_current_slide]
	var cam_id: String = slide.get("camera", "")
	if not cam_id.is_empty():
		_open_camera(cam_id)

func _open_camera(cam_id: String) -> void:
	if camera_viewer == null:
		return
	path_label.visible = true
	camera_viewer.open(cam_id)

# ══════════════════════════════════════════
#  输入处理
# ══════════════════════════════════════════
func _input(event: InputEvent) -> void:
	if camera_viewer and camera_viewer.is_active:
		camera_viewer.handle_input(event)
		if not camera_viewer.is_active:
			_on_camera_closed()
		return

func _unhandled_input(event: InputEvent) -> void:
	if camera_viewer and camera_viewer.is_active:
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT, KEY_BACKSPACE:
				_prev_slide()
				get_viewport().set_input_as_handled()
			KEY_RIGHT, KEY_SPACE, KEY_ENTER:
				_next_slide()
				get_viewport().set_input_as_handled()
			KEY_F11:
				toggle_fullscreen()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if _current_slide == _slides.size() - 1:
					get_tree().quit()
				else:
					toggle_fullscreen()
				get_viewport().set_input_as_handled()

func toggle_fullscreen() -> void:
	var win := get_window()
	if win.mode == Window.MODE_FULLSCREEN:
		win.mode = Window.MODE_WINDOWED
	else:
		win.mode = Window.MODE_FULLSCREEN

# ══════════════════════════════════════════
#  点击导航区
# ══════════════════════════════════════════
func _update_click_zones() -> void:
	var w: float = size.x
	var h: float = size.y
	var zone_w: float = w * 0.18
	var bottom_h: float = 36.0

	# 左侧点击区
	_click_left.position = Vector2.ZERO
	_click_left.size = Vector2(zone_w, h - bottom_h)

	# 右侧点击区
	_click_right.position = Vector2(w - zone_w, 0)
	_click_right.size = Vector2(zone_w, h - bottom_h)

	# hint 子节点填满父节点
	_click_left_hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_click_right_hint.set_anchors_preset(Control.PRESET_FULL_RECT)

	# 摄像头模式时隐藏点击区
	var cam_active: bool = camera_viewer != null and camera_viewer.is_active
	_click_left.visible = not cam_active
	_click_right.visible = not cam_active

func _on_click_left_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_prev_slide()

func _on_click_right_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_next_slide()

func _on_camera_closed() -> void:
	path_label.visible = false
	_show_slide(_current_slide)
	_update_click_zones()

# ══════════════════════════════════════════
#  每帧更新
# ══════════════════════════════════════════
func _process(delta: float) -> void:
	if camera_viewer and camera_viewer.is_active:
		camera_viewer.process(delta)
		if camera_mgr:
			camera_mgr.process(delta)

# ══════════════════════════════════════════
#  Stub 方法（供 CameraManager / CameraViewer 调用）
# ══════════════════════════════════════════
func append_output(text: String, add_newline: bool = true) -> void:
	var clean: String = text.replace("[color=#99FF99]", "").replace("[color=#FFD966]", "")
	clean = clean.replace("[color=#FF6666]", "").replace("[color=#66CCFF]", "")
	clean = clean.replace("[/color]", "").replace("[b]", "").replace("[/b]", "")
	clean = clean.replace("\n", " ").strip_edges()
	if not clean.is_empty():
		print("[CameraViewer] " + clean)

func get_data_dir() -> String:
	return ProjectSettings.globalize_path("res://data")

# ══════════════════════════════════════════
#  图表画布内部类
# ══════════════════════════════════════════
class _DiagramCanvas extends Control:
	var host: Control = null
	var diagram_type: String = ""
	var placeholder_text: String = ""

	func _draw() -> void:
		if host == null:
			return
		host._draw_diagram(self)
