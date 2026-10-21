extends Control
## 封面公共布局；preview_mode 保留独立调参，正式入口由 startup.gd 交接 Main。

@export var preview_mode: bool = true

const DESIGN_SIZE := Vector2(1920, 1080)
const LAYOUT_PATH := "res://preview/cover_layout.json"
const FONT := preload("res://fonts/SarasaMonoSC-Regular.ttf")
const TITLE_FONT := preload("res://fonts/SarasaMonoSC-SemiBold.ttf")
const LOGO := preload("res://images/core-mark.svg")
const LOGO_SHADER := preload("res://preview/cover_logo.gdshader")
const Atmosphere := preload("res://preview/cover_atmosphere.gd")
const CoverIntro := preload("res://preview/cover_intro.gd")
const INTRO_PATH := "res://preview/cover_intro.json"
const StartupSettings := preload("res://settings/startup_settings.gd")
const DEFAULTS := {
	"center_x": 960.0, "top": 170.0, "logo_size": 180.0,
	"logo_top_transparency": 0.0, "logo_bottom_transparency": 100.0, "logo_gradient_power": 1.0,
	"logo_gap": 22.0, "title_size": 116.0, "title_height": 142.0,
	"title_letter_spacing": 0.0,
	"subtitle_size": 28.0, "subtitle_gap": 12.0, "menu_gap": 50.0,
	"button_width": 310.0, "button_height": 60.0, "button_size": 30.0,
	"button_gap": 18.0, "links_x": 100.0, "links_bottom": 110.0,
	"links_width": 250.0, "links_height": 44.0, "links_size": 22.0,
	"links_gap": 12.0, "subtitle": "SCRT-Reader Core",
	"logo_x": 0.0, "logo_y": 0.0, "title_x": 0.0, "title_y": 0.0,
	"subtitle_x": 0.0, "subtitle_y": 0.0,
	"start_x": 0.0, "start_y": 0.0, "info_x": 0.0, "info_y": 0.0,
	"exit_x": 0.0, "exit_y": 0.0,
	"project_x": 0.0, "project_y": 0.0, "community_x": 0.0, "community_y": 0.0,
	"sponsor_x": 0.0, "sponsor_y": 0.0,
	"cloud_count": 3.0, "cloud_top": 24.0, "cloud_scale": 1.35,
	"cloud_speed": 8.0, "cloud_opacity": 36.0,
	"wave_bottom": 80.0, "wave_amplitude": 54.0, "wave_wavelength": 150.0,
	"wave_duration": 3.8, "wave_interval": 5.0, "wave_opacity": 65.0, "wave_volume": 18.0,
	"atmosphere_char_size": 28.0, "wave_wall_height": 240.0, "wave_splash_density": 1.0,
	"wave_blue_strength": 50.0, "wave_sound_fade": 4.0,
	"morse_volume": 8.0, "morse_min_volume": 55.0, "morse_wpm": 6.0,
	"morse_frequency": 550.0, "morse_swell_period": 24.0
}

# BootSequence 适配接口：复用实际关键帧、着色器及启动音，不初始化游戏。
var effect_settings: EffectSettings
var background: TextureRect
var background_logo: TextureRect
var output_text: RichTextLabel
var input_field: LineEdit = null
var boot_sequence: BootSequence
var _layout: Dictionary = DEFAULTS.duplicate(true)
var _canvas: Control
var _cover: Control
var _atmosphere: Control
var _logo: TextureRect
var _title: Label
var _title_font: FontVariation
var _subtitle: Label
var _menu: Array[Button] = []
var _links: Array[Button] = []
var _blink_buttons: Array[Button] = []
var _blink_selected: Button
var _blink_elapsed: float = 0.0
var _instructions: Control
var _tools: PanelContainer
var _feedback: Label
var _fields: Dictionary = {}
var _material_snapshots: Dictionary = {}
var _booting: bool = false
var _starting: bool = false
var _shutting_down: bool = false
var _intro: CoverIntro
var _tools_before_boot: bool = true
var _editable_nodes: Dictionary = {}
var _drag_mode: bool = false
var _drag_key: String = ""
var _drag_start: Vector2
var _drag_offsets: Vector2
var _selection: Panel
var _startup_settings: Dictionary = {}

func _ready() -> void:
	ThemeManager.load_theme("phosphor_green")
	var font_theme := Theme.new()
	font_theme.default_font = FONT
	font_theme.default_font_size = 20
	font_theme.set_color("font_color", "Label", ThemeManager.current.primary)
	theme = font_theme
	# 与 Main 完全相同的背景加载，包括外置 background.png 覆盖规则。
	var game_root: String = ProjectSettings.globalize_path("res://") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir() + "/"
	background = UIManager.setup_background(self, game_root)
	background_logo = $Background/CenterContainer/BackgroundLogo
	background_logo.hide()
	UIManager.setup_custom_cursor(self)
	_load_layout()
	_build_cover()
	if preview_mode:
		_build_tools()
	effect_settings = EffectSettings.new()
	effect_settings.setup_save_root(game_root + "saves/")
	_startup_settings = StartupSettings.load_values(_settings_save_root(game_root))
	StartupSettings.apply_master(float(_startup_settings["audio.master_volume"]))
	effect_settings.effect_level = {"full": EffectSettings.Level.FULL, "mild": EffectSettings.Level.MILD, "off": EffectSettings.Level.OFF}[_startup_settings["effect.level"]]
	effect_settings.photosensitive_mode = bool(_startup_settings["effect.photosensitive"])
	$CRTEffect/CRTShader.apply_effect_settings(effect_settings)
	if preview_mode:
		boot_sequence = BootSequence.new()
		boot_sequence.setup(self, $AudioManager, $CRTEffect/CRTShader)
		boot_sequence.skippable = true
		boot_sequence.boot_completed.connect(_return_to_cover)
	_intro = CoverIntro.new()
	add_child(_intro)
	_intro.cover_faded.connect(func() -> void: _cover.hide())
	_intro.completed.connect(_begin_boot)
	for node in [background, background_logo, $CRTEffect/CRTShader]:
		if node.material is ShaderMaterial:
			_material_snapshots[node] = node.material.duplicate()
	get_viewport().size_changed.connect(_resize)
	_resize()
	_apply_layout()
	await get_tree().process_frame
	await get_tree().process_frame
	_menu[0].grab_focus()

func _settings_save_root(game_root: String) -> String:
	return game_root + "saves/"

func _process(delta: float) -> void:
	_update_button_blink(delta)
	if _booting or (_shutting_down and boot_sequence != null):
		boot_sequence.process(delta)
	elif _cover.visible:
		_atmosphere.advance(delta)

func _input(event: InputEvent) -> void:
	if _shutting_down:
		get_viewport().set_input_as_handled()
		return
	if not _starting and not _booting and _drag_mode and _cover.visible and _handle_drag_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is not InputEventKey or not event.pressed or event.echo:
		return
	if _starting:
		if event.keycode in [KEY_F12, KEY_ESCAPE]:
			_intro.skip()
		get_viewport().set_input_as_handled()
		return
	if _booting:
		if event.keycode in [KEY_F12, KEY_ESCAPE]:
			boot_sequence.skip(true)
			get_viewport().set_input_as_handled()
		return
	if not preview_mode:
		if event.keycode == KEY_ESCAPE and _instructions.visible:
			_close_instructions()
			get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F2:
		_tools.visible = not _tools.visible
		if not _tools.visible:
			_set_drag_mode(false)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F3 and _cover.visible:
		_set_drag_mode(not _drag_mode)
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and event.keycode == KEY_S:
		_save_layout()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _instructions.visible:
		_close_instructions()
		get_viewport().set_input_as_handled()

func _build_cover() -> void:
	_canvas = Control.new()
	_canvas.name = "LayoutCanvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_cover = Control.new()
	_cover.size = DESIGN_SIZE
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_cover)
	_atmosphere = Atmosphere.new()
	_atmosphere.name = "CoverAtmosphere"
	_cover.add_child(_atmosphere)
	_logo = TextureRect.new()
	_logo.texture = LOGO
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var logo_material := ShaderMaterial.new()
	logo_material.shader = LOGO_SHADER
	_logo.material = logo_material
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.add_child(_logo)
	_title_font = FontVariation.new()
	_title_font.base_font = TITLE_FONT
	_title = _label("SCRT", _title_font)
	_title.z_index = 1
	_subtitle = _label("", FONT)
	_subtitle.z_index = 1
	_cover.add_child(_title)
	_cover.add_child(_subtitle)
	for caption in ["[ 启 动 ]", "[ 说 明 ]", "[ 退 出 ]"]:
		var button: Button = _button(caption, true)
		_cover.add_child(button)
		_menu.append(button)
	_menu[0].pressed.connect(_play_boot)
	_menu[1].pressed.connect(_open_instructions)
	_menu[2].pressed.connect(_play_shutdown)
	for caption in ["[ 项目链接 · 占位 ]", "[ 交流渠道 · 占位 ]", "[ 赞助渠道 · 占位 ]"]:
		var button: Button = _button(caption, true)
		if preview_mode:
			button.pressed.connect(func() -> void: _feedback.text = "该渠道尚未设置。")
		else:
			button.disabled = true
			# 仍保留作者认可的占位外观，链接到位后再启用。
			button.add_theme_color_override("font_disabled_color", ThemeManager.current.primary)
		_cover.add_child(button)
		_links.append(button)
	_editable_nodes = {"logo": _logo, "title": _title, "subtitle": _subtitle,
		"start": _menu[0], "info": _menu[1], "exit": _menu[2],
		"project": _links[0], "community": _links[1], "sponsor": _links[2]}
	_selection = Panel.new()
	_selection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var selection_style := StyleBoxFlat.new()
	selection_style.bg_color = Color.TRANSPARENT
	selection_style.border_color = ThemeManager.current.primary
	selection_style.set_border_width_all(1)
	_selection.add_theme_stylebox_override("panel", selection_style)
	_selection.hide()
	_cover.add_child(_selection)
	# 说明是同一 CRT 管线中的完整页面，正文故意留空。
	_instructions = Control.new()
	_instructions.size = DESIGN_SIZE
	_instructions.visible = false
	_canvas.add_child(_instructions)
	var paper := ColorRect.new()
	paper.size = DESIGN_SIZE
	paper.color = Color(0.0, 0.03, 0.0, 0.96)
	_instructions.add_child(paper)
	var heading: Label = _label("说 明", TITLE_FONT)
	heading.position = Vector2(160, 110)
	heading.size = Vector2(1600, 70)
	heading.add_theme_font_size_override("font_size", 42)
	_instructions.add_child(heading)
	var back: Button = _button("[ 返回封面 ]", true)
	back.position = Vector2(790, 900)
	back.size = Vector2(340, 60)
	back.pressed.connect(_close_instructions)
	_instructions.add_child(back)
	output_text = RichTextLabel.new()
	output_text.position = Vector2(80, 80)
	output_text.size = DESIGN_SIZE - Vector2(160, 160)
	output_text.bbcode_enabled = true
	output_text.add_theme_font_override("normal_font", FONT)
	output_text.add_theme_font_size_override("normal_font_size", 24)
	output_text.add_theme_color_override("default_color", ThemeManager.current.primary)
	output_text.visible = false
	_canvas.add_child(output_text)

func _label(caption: String, font: Font) -> Label:
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font)
	return label

func _button(caption: String, blink_selection: bool = false) -> Button:
	var button := Button.new()
	button.text = caption
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0) if blink_selection or state == "normal" else Color(0.12, 0.38, 0.12, 0.25)
		if state == "focus" and not blink_selection:
			style.border_color = ThemeManager.current.dim
			style.set_border_width_all(1)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", ThemeManager.current.primary)
	button.add_theme_color_override("font_hover_color", Color(0.85, 1, 0.85))
	button.add_theme_color_override("font_pressed_color", ThemeManager.current.secondary)
	button.add_theme_color_override("font_focus_color", ThemeManager.current.primary)
	if blink_selection:
		_blink_buttons.append(button)
	return button

func _update_button_blink(delta: float) -> void:
	# 鼠标悬停优先于保留的键盘焦点，避免两项同时闪烁。
	var selected: Button = null
	if not _starting and not _booting and not _shutting_down and not _drag_mode:
		var hovered := get_viewport().gui_get_hovered_control()
		for button in _blink_buttons:
			if button.is_visible_in_tree() and not button.disabled:
				if hovered == button:
					selected = button
					break
				if button.has_focus():
					selected = button
	if selected != _blink_selected:
		_blink_selected = selected
		_blink_elapsed = 0.0
	else:
		_blink_elapsed += delta
	var allow_blink := effect_settings != null and not effect_settings.photosensitive_mode and effect_settings.effect_level != EffectSettings.Level.OFF
	for button in _blink_buttons:
		var color := ThemeManager.current.primary
		if button == selected:
			color = Color(0.85, 1, 0.85)
			if allow_blink and fmod(_blink_elapsed, 1.2) >= 0.6:
				color.a = 0.3
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, color)

func _build_tools() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	_tools = PanelContainer.new()
	layer.add_child(_tools)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.045, 0.025, 0.98)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_tools.add_theme_stylebox_override("panel", style)
	_tools.theme = theme
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tools.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 9)
	scroll.add_child(box)
	var header: Label = _label("封面布局预览 · F2 隐藏面板", FONT)
	header.add_theme_font_size_override("font_size", 16)
	box.add_child(header)
	var note := Label.new()
	note.text = "1920 × 1080 设计坐标\n位置／间距不限制范围，尺寸可继续增大。\nF3 切换拖动模式 · Ctrl+S 保存。"
	note.add_theme_font_size_override("font_size", 14)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	_add_group(box, "中央标题")
	_number(box, "center_x", "中心横坐标")
	_number(box, "top", "LOGO 顶部")
	_number(box, "logo_size", "LOGO 尺寸")
	_number(box, "logo_top_transparency", "LOGO 顶部透明度 %")
	_number(box, "logo_bottom_transparency", "LOGO 底部透明度 %")
	_number(box, "logo_gradient_power", "透明渐变变化率")
	var gradient_note := Label.new()
	gradient_note.text = "变化率 1：均匀渐变；小于 1：更早变淡；\n大于 1：上部更实，靠近底部才变淡。"
	gradient_note.add_theme_font_size_override("font_size", 13)
	gradient_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(gradient_note)
	_number(box, "logo_gap", "LOGO / 标题间距")
	_number(box, "title_size", "SCRT 字号")
	_number(box, "title_letter_spacing", "SCRT 字母间距")
	_number(box, "title_height", "SCRT 区域高度")
	_number(box, "subtitle_gap", "标题 / 小标题间距")
	_number(box, "subtitle_size", "小标题字号")
	var subtitle_field := LineEdit.new()
	subtitle_field.text = str(_layout["subtitle"])
	subtitle_field.add_theme_font_size_override("font_size", 14)
	subtitle_field.text_changed.connect(func(value: String) -> void: _set_value("subtitle", value))
	box.add_child(subtitle_field)
	_fields["subtitle"] = subtitle_field
	_add_group(box, "中央按钮")
	_number(box, "menu_gap", "小标题 / 按钮间距")
	_number(box, "button_width", "按钮宽度")
	_number(box, "button_height", "按钮高度")
	_number(box, "button_size", "按钮字号")
	_number(box, "button_gap", "按钮间距")
	_add_group(box, "左下渠道占位")
	_number(box, "links_x", "距离左边")
	_number(box, "links_bottom", "距离底边")
	_number(box, "links_width", "渠道宽度")
	_number(box, "links_height", "渠道高度")
	_number(box, "links_size", "渠道字号")
	_number(box, "links_gap", "渠道间距")
	_add_group(box, "云与海面共用字符")
	_number(box, "atmosphere_char_size", "统一字符字号")
	_add_group(box, "顶部云朵")
	_number(box, "cloud_count", "云朵数量（0—3）")
	_number(box, "cloud_top", "云层纵坐标")
	_number(box, "cloud_scale", "云朵大小倍率")
	_number(box, "cloud_speed", "向右速度（像素/秒）")
	_number(box, "cloud_opacity", "云朵不透明度 %")
	_add_group(box, "底部海浪与声音")
	_number(box, "wave_bottom", "水面距离底边")
	_number(box, "wave_amplitude", "海浪高度")
	_number(box, "wave_wavelength", "海浪波长")
	_number(box, "wave_wall_height", "贴墙水面抬升高度")
	_number(box, "wave_splash_density", "分离水花数量（0—3）")
	_number(box, "wave_duration", "每轮持续（秒，越小越快）")
	_number(box, "wave_interval", "轮次间歇（秒）")
	_number(box, "wave_opacity", "海浪不透明度 %")
	_number(box, "wave_blue_strength", "水体蓝色程度 %")
	_number(box, "wave_volume", "浪声音量 %（0 静音）")
	_number(box, "wave_sound_fade", "浪声淡出时长（秒）")
	for direction in [1.0, -1.0]:
		var wave_button: Button = _button("[ 从左涌出一轮海浪 ]" if direction > 0.0 else "[ 从右涌出一轮海浪 ]")
		wave_button.add_theme_font_size_override("font_size", 16)
		wave_button.pressed.connect(_atmosphere.trigger_wave.bind(direction))
		box.add_child(wave_button)
	_add_group(box, "摩斯背景声（凯撒 +7）")
	_number(box, "morse_volume", "摩斯音量 %（0 静音）")
	_number(box, "morse_min_volume", "起伏最低音量 %（相对音量）")
	_number(box, "morse_wpm", "播放速度（WPM）")
	_number(box, "morse_frequency", "摩斯音高（Hz）")
	_number(box, "morse_swell_period", "音量起伏周期（秒）")
	_add_group(box, "独立位置微调（相对整体布局）")
	for key in _editable_nodes:
		var captions := {"logo": "LOGO", "title": "SCRT", "subtitle": "小标题",
			"start": "启动", "info": "说明", "exit": "退出",
			"project": "项目链接", "community": "交流渠道", "sponsor": "赞助渠道"}
		_number(box, key + "_x", captions[key] + " 横向偏移")
		_number(box, key + "_y", captions[key] + " 纵向偏移")
	var drag_button: Button = _button("拖动元素（F3 开关）")
	drag_button.add_theme_font_size_override("font_size", 16)
	drag_button.pressed.connect(func() -> void: _set_drag_mode(not _drag_mode))
	box.add_child(drag_button)
	for action in ["保存当前布局", "恢复上次保存", "恢复初始布局", "隐藏面板（F2）"]:
		var button: Button = _button(action)
		button.add_theme_font_size_override("font_size", 16)
		box.add_child(button)
		match action:
			"保存当前布局": button.pressed.connect(_save_layout)
			"恢复上次保存": button.pressed.connect(_reload_layout)
			"恢复初始布局": button.pressed.connect(_reset_layout)
			_: button.pressed.connect(func() -> void:
				_tools.hide()
				_set_drag_mode(false)
			)
	_feedback = Label.new()
	_feedback.text = "启动：预览原开机动画，结束返回这里。"
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.add_theme_font_size_override("font_size", 14)
	box.add_child(_feedback)

func _add_group(box: VBoxContainer, caption: String) -> void:
	var label := Label.new()
	label.text = "─ " + caption + " ─"
	label.add_theme_font_size_override("font_size", 16)
	box.add_child(label)

func _number(box: VBoxContainer, key: String, caption: String) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)
	var spin := SpinBox.new()
	# 仅保留有效尺寸／字号 >= 1；位置和间距允许负值和任意越界值。
	var positive: bool = key.ends_with("_size") or key.ends_with("_width") or key.ends_with("_height")
	spin.min_value = 1.0 if positive else -1920.0
	spin.max_value = 1920.0
	spin.allow_greater = true
	spin.allow_lesser = not positive
	spin.step = 0.1 if not positive else 1.0
	if key == "title_letter_spacing":
		spin.step = 1.0
	if key.ends_with("_transparency") or key.ends_with("_opacity") or key in ["wave_volume", "wave_blue_strength", "morse_volume", "morse_min_volume"]:
		spin.min_value = 0.0
		spin.max_value = 100.0
		spin.allow_greater = false
		spin.allow_lesser = false
		if key == "morse_min_volume":
			spin.min_value = 25.0
	elif key == "morse_wpm":
		spin.min_value = 2.0
		spin.max_value = 20.0
		spin.allow_greater = false
		spin.allow_lesser = false
	elif key == "morse_frequency":
		spin.min_value = 100.0
		spin.max_value = 1500.0
		spin.allow_greater = false
		spin.allow_lesser = false
	elif key in ["wave_sound_fade", "morse_swell_period"]:
		spin.min_value = 0.25 if key == "wave_sound_fade" else 4.0
		spin.allow_lesser = false
	elif key == "logo_gradient_power":
		spin.min_value = 0.05
		spin.max_value = 10.0
		spin.allow_greater = true
		spin.allow_lesser = false
		spin.step = 0.05
	elif key == "cloud_count":
		spin.min_value = 0.0
		spin.max_value = 3.0
		spin.allow_greater = false
		spin.allow_lesser = false
		spin.step = 1.0
	elif key == "cloud_top":
		spin.min_value = 0.0
		spin.max_value = DESIGN_SIZE.y * 0.4
		spin.allow_greater = false
		spin.allow_lesser = false
	elif key == "atmosphere_char_size":
		spin.min_value = 10.0
		spin.allow_lesser = false
	elif key == "wave_splash_density":
		spin.min_value = 0.0
		spin.max_value = 3.0
		spin.allow_greater = false
		spin.allow_lesser = false
	elif key in ["cloud_scale", "wave_duration", "wave_interval", "wave_wavelength"]:
		spin.min_value = 0.05 if key == "cloud_scale" else (8.0 if key == "wave_wavelength" else 0.5)
		spin.allow_lesser = false
		spin.step = 0.05 if key == "cloud_scale" else 0.1
	elif key in ["cloud_speed", "wave_amplitude", "wave_wall_height"]:
		spin.min_value = 0.0
		spin.allow_lesser = false
	spin.value = float(_layout[key])
	spin.custom_minimum_size.x = 100
	spin.add_theme_font_size_override("font_size", 14)
	spin.value_changed.connect(func(value: float) -> void: _set_value(key, value))
	row.add_child(spin)
	_fields[key] = spin

func _set_value(key: String, value: Variant) -> void:
	_layout[key] = value
	_apply_layout()
	_feedback.text = "布局已调整；点击保存以保留。"

func _apply_layout() -> void:
	var atmosphere_config: Dictionary = _layout.duplicate()
	atmosphere_config["audio_ambient_gain"] = float(_startup_settings.get("audio.ambient_volume", 0.7))
	atmosphere_config["atmosphere_motion_off"] = effect_settings != null and effect_settings.is_off()
	_atmosphere.configure(atmosphere_config, ThemeManager.current.primary)
	var cx: float = float(_layout["center_x"])
	var y: float = float(_layout["top"])
	var logo_size: float = float(_layout["logo_size"])
	_logo.position = Vector2(cx - logo_size / 2, y)
	_logo.size = Vector2.ONE * logo_size
	var logo_material: ShaderMaterial = _logo.material
	logo_material.set_shader_parameter("top_transparency", clampf(float(_layout["logo_top_transparency"]) / 100.0, 0.0, 1.0))
	logo_material.set_shader_parameter("bottom_transparency", clampf(float(_layout["logo_bottom_transparency"]) / 100.0, 0.0, 1.0))
	logo_material.set_shader_parameter("gradient_power", maxf(0.05, float(_layout["logo_gradient_power"])))
	y += logo_size + float(_layout["logo_gap"])
	# 独立字体间距只影响 SCRT；扩大标题区域后仍按同一中心定位。
	_title_font.spacing_glyph = roundi(float(_layout["title_letter_spacing"]))
	var title_width: float = maxf(1200.0, _title_font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_layout["title_size"])).x)
	_title.position = Vector2(cx - title_width / 2, y)
	_title.size = Vector2(title_width, float(_layout["title_height"]))
	_title.add_theme_font_size_override("font_size", int(_layout["title_size"]))
	y += _title.size.y + float(_layout["subtitle_gap"])
	_subtitle.text = str(_layout["subtitle"])
	_subtitle.position = Vector2(cx - 650, y)
	_subtitle.size = Vector2(1300, float(_layout["subtitle_size"]) * 1.6)
	_subtitle.add_theme_font_size_override("font_size", int(_layout["subtitle_size"]))
	y += _subtitle.size.y + float(_layout["menu_gap"])
	for button in _menu:
		button.position = Vector2(cx - float(_layout["button_width"]) / 2, y)
		button.add_theme_font_size_override("font_size", int(_layout["button_size"]))
		button.size = Vector2(float(_layout["button_width"]), float(_layout["button_height"]))
		y += button.size.y + float(_layout["button_gap"])
	y = DESIGN_SIZE.y - float(_layout["links_bottom"]) - 3 * float(_layout["links_height"]) - 2 * float(_layout["links_gap"])
	for button in _links:
		button.position = Vector2(float(_layout["links_x"]), y)
		button.add_theme_font_size_override("font_size", int(_layout["links_size"]))
		button.size = Vector2(float(_layout["links_width"]), float(_layout["links_height"]))
		y += button.size.y + float(_layout["links_gap"])
	for key in _editable_nodes:
		var node: Control = _editable_nodes[key]
		node.position += Vector2(float(_layout[key + "_x"]), float(_layout[key + "_y"]))

func _resize() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var ratio: float = minf(viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y)
	_canvas.scale = Vector2.ONE * ratio
	_canvas.position = (viewport_size - DESIGN_SIZE * ratio) / 2
	if _tools == null:
		return
	var panel_width: float = minf(360, viewport_size.x * 0.4)
	_tools.position = Vector2(viewport_size.x - panel_width - 14, 14)
	_tools.size = Vector2(panel_width, maxf(100, viewport_size.y - 28))

func _layout_path() -> String:
	return LAYOUT_PATH if not preview_mode or OS.has_feature("editor") else "user://cover_preview_layout.json"

func _load_layout() -> void:
	_layout = DEFAULTS.duplicate(true)
	if not FileAccess.file_exists(_layout_path()):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_layout_path()))
	if parsed is not Dictionary:
		return
	for key in DEFAULTS:
		var value: Variant = parsed.get(key)
		if (DEFAULTS[key] is String and value is String) or (DEFAULTS[key] is float and (value is float or value is int)):
			_layout[key] = value
	# 旧布局首次读取：沿用作者的水面字号，并将水位抬高两个字符行。
	# 保存后有统一字号字段；恢复／重新打开不会重复抬高水面。
	if not parsed.has("atmosphere_char_size"):
		var old_size: Variant = parsed.get("wave_char_size", 28.0)
		if old_size is float or old_size is int:
			_layout["atmosphere_char_size"] = maxf(10.0, float(old_size))
		var old_bottom: Variant = parsed.get("wave_bottom", 34.0)
		if old_bottom is float or old_bottom is int:
			_layout["wave_bottom"] = float(old_bottom) + 2.0 * float(_layout["atmosphere_char_size"]) * 0.82
	_layout["cloud_count"] = clampf(float(_layout["cloud_count"]), 0.0, 3.0)

func _save_layout() -> void:
	if not preview_mode:
		return
	var file := FileAccess.open(_layout_path(), FileAccess.WRITE)
	if file == null:
		_feedback.text = "保存失败：" + error_string(FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(_layout, "\t") + "\n")
	_feedback.text = "已保存：preview/cover_layout.json" if OS.has_feature("editor") else "已保存：user://cover_preview_layout.json"

func _sync_fields() -> void:
	for key in _fields:
		var field: Control = _fields[key]
		if field is SpinBox:
			field.set_value_no_signal(float(_layout[key]))
		else:
			field.text = str(_layout[key])
	_apply_layout()

func _reload_layout() -> void:
	_load_layout()
	_sync_fields()
	_feedback.text = "已恢复保存的布局。"

func _reset_layout() -> void:
	_layout = DEFAULTS.duplicate(true)
	_sync_fields()
	_feedback.text = "已恢复初始布局；尚未覆盖保存文件。"

func _set_drag_mode(enabled: bool) -> void:
	if not preview_mode:
		return
	_drag_mode = enabled
	_drag_key = ""
	_selection.hide()
	_feedback.text = "拖动模式：左键拖动元素，按钮不会启动；F3 恢复正常点击。" if enabled else "已退出拖动模式；按钮恢复正常点击。"

func _handle_drag_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			var was_dragging: bool = not _drag_key.is_empty()
			_drag_key = ""
			return was_dragging
		if _tools.visible and _tools.get_global_rect().has_point(event.position):
			return false
		var keys: Array = _editable_nodes.keys()
		keys.reverse()
		for key in keys:
			var node: Control = _editable_nodes[key]
			if node.get_global_rect().has_point(event.position):
				_drag_key = key
				_drag_start = _canvas.get_global_transform().affine_inverse() * event.position
				_drag_offsets = Vector2(float(_layout[key + "_x"]), float(_layout[key + "_y"]))
				_selection.position = node.position
				_selection.size = node.size
				_selection.show()
				return true
		_selection.hide()
	elif event is InputEventMouseMotion and not _drag_key.is_empty():
		var cursor: Vector2 = _canvas.get_global_transform().affine_inverse() * event.position
		var offset: Vector2 = _drag_offsets + cursor - _drag_start
		_layout[_drag_key + "_x"] = snappedf(offset.x, 0.1)
		_layout[_drag_key + "_y"] = snappedf(offset.y, 0.1)
		_sync_fields()
		var node: Control = _editable_nodes[_drag_key]
		_selection.position = node.position
		_selection.size = node.size
		_feedback.text = "元素已移动；Ctrl+S 保存。F3 恢复正常点击。"
		return true
	return false

func _open_instructions() -> void:
	_atmosphere.set_active(false)
	_cover.hide()
	_instructions.show()
	_instructions.get_child(_instructions.get_child_count() - 1).grab_focus()

func _close_instructions() -> void:
	_atmosphere.set_active(true)
	_instructions.hide()
	_cover.show()
	_menu[1].grab_focus()

func _play_boot() -> void:
	if _starting or _booting or _shutting_down:
		return
	_starting = true
	_set_drag_mode(false)
	_atmosphere.set_active(false)
	if _tools != null:
		_tools_before_boot = _tools.visible
		_tools.hide()
	var config: Dictionary = {}
	if FileAccess.file_exists(INTRO_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INTRO_PATH))
		if parsed is Dictionary:
			config = parsed
	_intro.play(config)

func _play_shutdown() -> void:
	if _starting or _booting or _shutting_down:
		return
	_shutting_down = true
	_set_drag_mode(false)
	_atmosphere.set_active(false)
	if _tools != null:
		_tools.hide()
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	# 正式封面只在退出时创建动画适配器，不初始化 Main 或玩家存档。
	if boot_sequence == null:
		boot_sequence = BootSequence.new()
		boot_sequence.setup(self, $AudioManager, $CRTEffect/CRTShader)
		# setup 延迟挂载音频节点及黑屏遮罩，准备好后才启动关键帧。
		await get_tree().process_frame
		await get_tree().process_frame
	boot_sequence.skippable = false
	# 封面未经历开机淡入；将 shader 默认值显式写入，供关机 Tween 读取。
	var background_material := background.material as ShaderMaterial
	if background_material != null:
		# 与 background_vignette.gdshader 的默认值保持一致。
		var defaults := {"brightness": 0.688, "alpha": 0.5}
		for parameter in defaults:
			if background_material.get_shader_parameter(parameter) == null:
				background_material.set_shader_parameter(parameter, defaults[parameter])
	boot_sequence.play_shutdown()

func _begin_boot() -> void:
	if not _starting:
		return
	_starting = false
	_booting = true
	_cover.hide()
	output_text.show()
	# 仅开机动画使用原背景 LOGO，返回封面后再次隐藏。
	background_logo.show()
	background.material.set_shader_parameter("brightness", 0.0)
	background.material.set_shader_parameter("alpha", 0.0)
	background_logo.material.set_shader_parameter("alpha", 0.0)
	boot_sequence.play_boot()

func _return_to_cover() -> void:
	_intro.cancel()
	_starting = false
	# 快速跳过时清理尚未结束的启动渐变，避免返回后继续改变背景。
	for tween in get_tree().get_processed_tweens():
		tween.kill()
	# 保留 CRT 控制器持有的材质实例，仅恢复参数。
	for node in _material_snapshots:
		var snapshot: ShaderMaterial = _material_snapshots[node]
		for uniform in snapshot.shader.get_shader_uniform_list():
			var key: String = str(uniform["name"])
			node.material.set_shader_parameter(key, snapshot.get_shader_parameter(key))
	_booting = false
	_atmosphere.set_active(true)
	background_logo.hide()
	output_text.hide()
	_cover.show()
	if _tools != null:
		_tools.visible = _tools_before_boot
	_menu[0].grab_focus()

func _request_scroll() -> void:
	output_text.scroll_to_line(maxi(0, output_text.get_line_count() - 1))
