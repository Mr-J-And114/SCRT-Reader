extends CanvasLayer
## 开机前独立播片：整屏淡黑、按序展示文字／图片页，结束后交还开机流程。
## play(config) 接收页面列表，completed 是正式启动流程可复用的交接接口。

signal cover_faded
signal completed

const DESIGN_SIZE := Vector2(1920, 1080)
const FONT := preload("res://fonts/SarasaMonoSC-SemiBold.ttf")
const DEFAULT_SLIDE := {
	"text": "CC-BY-SA 3.0", "font_size": 120,
	"fade_in": 0.75, "hold": 1.5, "fade_out": 0.75
}

var _root: Control
var _shade: ColorRect
var _content: Control
var _title: Label
var _image: TextureRect
var _slides: Array[Dictionary] = []
var _slide_index: int = -1
var _elapsed: float = 0.0
var _cover_fade: float = 1.0
var _fade_in: float = 0.75
var _hold: float = 1.5
var _fade_out: float = 0.75
var _active: bool = false

func _ready() -> void:
	# CRT 的噪声也被遮住，保证播片背景是纯黑。
	layer = 110
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_shade = ColorRect.new()
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_shade)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content = Control.new()
	_content.size = DESIGN_SIZE
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_content)
	_image = TextureRect.new()
	_image.position = Vector2(160, 100)
	_image.size = DESIGN_SIZE - Vector2(320, 200)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_image)
	_title = Label.new()
	_title.position = Vector2(120, 100)
	_title.size = DESIGN_SIZE - Vector2(240, 200)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_font_override("font", FONT)
	_title.add_theme_color_override("font_color", Color.WHITE)
	_content.add_child(_title)
	get_viewport().size_changed.connect(_resize)
	_resize()
	cancel()

func play(config: Dictionary) -> void:
	_slides.clear()
	var entries: Variant = config.get("slides", [DEFAULT_SLIDE])
	if entries is Array:
		for entry in entries:
			if entry is Dictionary:
				_slides.append(entry.duplicate(true))
	_cover_fade = maxf(0.0, float(config.get("cover_fade", 1.0)))
	_slide_index = -1
	_elapsed = 0.0
	_active = true
	_shade.color = Color(0, 0, 0, 0)
	_content.hide()
	_root.show()
	set_process(true)

func cancel() -> void:
	_active = false
	_root.hide()
	set_process(false)

func hold_black() -> void:
	# 正式场景交接期间继续遮住底层，直到 Main 的开机节点就绪。
	_active = false
	set_process(false)
	_shade.color = Color.BLACK
	_content.hide()
	_root.show()

func skip() -> void:
	if _active:
		_finish()

func show_status(caption: String) -> void:
	hold_black()
	_title.text = caption
	_title.add_theme_font_size_override("font_size", 40)
	_title.show()
	_image.hide()
	_content.modulate.a = 1.0
	_content.show()

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	# 消耗当前阶段后把余下时间交给下一页，低帧率下也不延长既定时长。
	while _active:
		var duration: float = _cover_fade if _slide_index < 0 else maxf(0.001, _fade_in + _hold + _fade_out)
		var step: float = minf(maxf(0.0, delta), maxf(0.0, duration - _elapsed))
		_elapsed += step
		delta -= step
		_update_opacity()
		if _elapsed < duration:
			return
		if _slide_index < 0:
			cover_faded.emit()
		if _slide_index + 1 >= _slides.size():
			_finish()
			return
		_begin_slide(_slide_index + 1)

func _begin_slide(index: int) -> void:
	_slide_index = index
	_elapsed = 0.0
	var slide: Dictionary = _slides[index]
	_fade_in = maxf(0.0, float(slide.get("fade_in", 0.75)))
	_hold = maxf(0.0, float(slide.get("hold", 1.5)))
	_fade_out = maxf(0.0, float(slide.get("fade_out", 0.75)))
	_title.text = str(slide.get("text", ""))
	_title.add_theme_font_size_override("font_size", maxi(1, int(slide.get("font_size", 120))))
	_title.visible = not _title.text.is_empty()
	_image.texture = null
	var image_path: String = str(slide.get("image", ""))
	if not image_path.is_empty() and ResourceLoader.exists(image_path):
		_image.texture = load(image_path) as Texture2D
	_image.visible = _image.texture != null
	_content.show()
	_update_opacity()

func _update_opacity() -> void:
	if _slide_index < 0:
		_shade.color.a = smoothstep(0.0, _cover_fade, _elapsed) if _cover_fade > 0.0 else 1.0
		return
	_shade.color = Color.BLACK
	var opacity: float = 1.0
	if _fade_in > 0.0 and _elapsed < _fade_in:
		opacity = smoothstep(0.0, _fade_in, _elapsed)
	elif _fade_out > 0.0 and _elapsed > _fade_in + _hold:
		opacity = 1.0 - smoothstep(0.0, _fade_out, _elapsed - _fade_in - _hold)
	_content.modulate.a = opacity

func _finish() -> void:
	cancel()
	completed.emit()

func _resize() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var ratio: float = minf(viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y)
	_content.scale = Vector2.ONE * ratio
	_content.position = (viewport_size - DESIGN_SIZE * ratio) / 2.0
