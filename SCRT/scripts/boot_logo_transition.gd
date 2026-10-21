extends RefCounted
## 从加载记录中的小图标过渡到原背景 LOGO；目标始终取现有节点的实际布局。

var _root: Control
var _target: TextureRect
var _output: RichTextLabel
var _sprite: TextureRect
var _material: ShaderMaterial
var _base_material: ShaderMaterial
var _line_character: int = 0
var _prefix: String = "VISUAL IDENTITY: "
var _small_size: float = 64.0
var _hold: float = 1.0
var _duration: float = 2.2
var _elapsed: float = 0.0
var _active: bool = false
var _source: Rect2
var _small_tint: Color
var _base_modulate := Color.WHITE

func setup(root: Control, target: TextureRect, output: RichTextLabel) -> void:
	_root = root
	_target = target
	_output = output
	if _target != null:
		_base_modulate = _target.modulate
	if _target != null and _target.material is ShaderMaterial:
		_base_material = _target.material.duplicate() as ShaderMaterial

func prepare() -> void:
	finish(false)
	if is_instance_valid(_target):
		# 保留容器布局参与，窗口缩放期间目标仍在原来的中央。
		_target.show()
		_target.modulate.a = 0.0
		if _base_material != null:
			_target.material.set_shader_parameter("alpha", _base_material.get_shader_parameter("alpha"))

func start(params: Dictionary) -> String:
	if not is_instance_valid(_target) or not is_instance_valid(_output):
		return ""
	finish(false)
	_prefix = str(params.get("prefix", "VISUAL IDENTITY: "))
	_small_size = maxf(24.0, float(params.get("size", 64.0)))
	_hold = maxf(0.0, float(params.get("hold", 1.0)))
	_duration = maxf(0.01, float(params.get("duration", 2.2)))
	_elapsed = 0.0
	_line_character = _output.get_total_character_count()
	# 大字号空位给小图标保留真实行高；图标在 CRT 层下独立绘制，可以离开文字行。
	var markup: String = "[color=%s]%s[/color][font_size=%d]  [/font_size][color=%s]  OK[/color]\n" % [ThemeManager.current.muted_hex, _prefix, int(_small_size), ThemeManager.current.success_hex]
	_output.append_text(markup)
	_sprite = TextureRect.new()
	_sprite.name = "BootIdentityLogo"
	_sprite.texture = _target.texture
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = _target.stretch_mode
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_sprite)
	if _base_material != null:
		_base_material = _target.material.duplicate() as ShaderMaterial
		_material = _base_material.duplicate() as ShaderMaterial
		_sprite.material = _material
	_sprite.modulate = _base_modulate
	_small_tint = ThemeManager.current.primary
	_small_tint.a = 1.0
	_target.modulate.a = 0.0
	_active = true
	_source = _line_rect()
	_apply(0.0)
	return markup

func advance(delta: float) -> void:
	if not _active or not is_instance_valid(_sprite):
		return
	_elapsed += maxf(delta, 0.0)
	if _elapsed <= _hold:
		_source = _line_rect()
		_apply(0.0)
		return
	var progress: float = clampf((_elapsed - _hold) / _duration, 0.0, 1.0)
	_apply(smoothstep(0.0, 1.0, progress))
	if progress >= 1.0:
		finish()

func _line_rect() -> Rect2:
	var line: int = _output.get_character_line(_line_character)
	var style: StyleBox = _output.get_theme_stylebox("normal")
	var font: Font = _output.get_theme_font("normal_font")
	var font_size: int = _output.get_theme_font_size("normal_font_size")
	var x: float = style.get_content_margin(SIDE_LEFT) + font.get_string_size(_prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var y: float = _output.get_line_offset(line) - _output.get_v_scroll_bar().value
	y += maxf(0.0, (float(_output.get_line_height(line)) - _small_size) * 0.5)
	var transform: Transform2D = _root.get_global_transform().affine_inverse() * _output.get_global_transform()
	return Rect2(transform * Vector2(x, y), Vector2.ONE * _small_size * transform.get_scale())

func _target_rect() -> Rect2:
	var transform: Transform2D = _root.get_global_transform().affine_inverse() * _target.get_global_transform()
	return Rect2(transform.origin, _target.size * transform.get_scale())

func _apply(progress: float) -> void:
	var destination: Rect2 = _target_rect()
	_sprite.position = _source.position.lerp(destination.position, progress)
	_sprite.size = _source.size.lerp(destination.size, progress)
	if _material != null:
		_material.set_shader_parameter("alpha", lerpf(0.95, float(_base_material.get_shader_parameter("alpha")), progress))
		_material.set_shader_parameter("contrast", lerpf(1.0, float(_base_material.get_shader_parameter("contrast")), progress))
		var tint: Color = _base_material.get_shader_parameter("tint_color")
		_material.set_shader_parameter("tint_color", _small_tint.lerp(tint, progress))

func finish(show_background: bool = true) -> void:
	_active = false
	if is_instance_valid(_sprite):
		_sprite.hide()
		_sprite.queue_free()
	_sprite = null
	_material = null
	if show_background and is_instance_valid(_target):
		_target.modulate = _base_modulate
		_target.show()

func is_active() -> bool:
	return _active
