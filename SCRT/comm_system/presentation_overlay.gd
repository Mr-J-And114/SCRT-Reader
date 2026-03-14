# ============================================================
# presentation_overlay.gd — 演示模式幻灯片叠加层
# 在 meeting 模式基础上显示 PPT/图片幻灯片
# ── 角色在一侧，幻灯片在另一侧
# ============================================================
class_name PresentationOverlay
extends RefCounted

var _main: Control = null
var _root: Control = null
var _slide_rect: TextureRect = null
var _slide_tween: Tween = null
var _current_slide_path: String = ""
var _is_active: bool = false

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(main: Control, root: Control) -> void:
	_main = main
	_root = root

# ══════════════════════════════════════════
#  幻灯片控制
# ══════════════════════════════════════════

## 显示幻灯片
## config: { "image": path, "position": [x, y], "size": [w, h], "transition": "fade" }
func show_slide(config: Dictionary) -> void:
	var image_path: String = str(config.get("image", ""))
	if image_path.is_empty():
		return

	_ensure_slide_rect()
	var texture: Texture2D = _load_slide_texture(image_path)
	if texture == null:
		push_warning("[PresentationOverlay] 无法加载幻灯片: %s" % image_path)
		return

	_current_slide_path = image_path
	_slide_rect.texture = texture

	# 定位和大小（归一化坐标）
	var pos_arr: Array = config.get("position", [0.55, 0.1]) as Array
	var size_arr: Array = config.get("size", [0.4, 0.5]) as Array
	var transition: String = str(config.get("transition", "fade"))

	_update_slide_layout(pos_arr, size_arr)
	_slide_rect.visible = true
	_is_active = true
	_animate_transition(transition, true)

## 隐藏幻灯片
func hide_slide(transition: String = "fade") -> void:
	if _slide_rect == null or not _is_active:
		return
	_animate_transition(transition, false)

## 更新布局（窗口大小变化时）
func update_layout() -> void:
	if not _is_active or _slide_rect == null:
		return
	# 位置在 show_slide 时已设置，此处暂不需动态更新

## 清理
func cleanup() -> void:
	if _slide_tween:
		_slide_tween.kill()
		_slide_tween = null
	if _slide_rect and is_instance_valid(_slide_rect):
		_slide_rect.queue_free()
		_slide_rect = null
	_is_active = false
	_current_slide_path = ""

func is_active() -> bool:
	return _is_active

func get_current_slide_path() -> String:
	return _current_slide_path

# ══════════════════════════════════════════
#  内部方法
# ══════════════════════════════════════════

func _ensure_slide_rect() -> void:
	if _slide_rect != null and is_instance_valid(_slide_rect):
		return
	_slide_rect = TextureRect.new()
	_slide_rect.name = "PresentationSlide"
	_slide_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_slide_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_slide_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slide_rect.visible = false
	if _root and is_instance_valid(_root):
		_root.add_child(_slide_rect)

func _update_slide_layout(pos_arr: Array, size_arr: Array) -> void:
	if _slide_rect == null or _root == null:
		return
	var screen_w: float = _root.size.x if _root.size.x > 0 else 800.0
	var screen_h: float = _root.size.y if _root.size.y > 0 else 600.0

	var norm_x: float = float(pos_arr[0]) if pos_arr.size() > 0 else 0.55
	var norm_y: float = float(pos_arr[1]) if pos_arr.size() > 1 else 0.1
	var norm_w: float = float(size_arr[0]) if size_arr.size() > 0 else 0.4
	var norm_h: float = float(size_arr[1]) if size_arr.size() > 1 else 0.5

	_slide_rect.position = Vector2(screen_w * norm_x, screen_h * norm_y)
	_slide_rect.size = Vector2(screen_w * norm_w, screen_h * norm_h)

func _load_slide_texture(path: String) -> Texture2D:
	# 尝试从 res:// 加载（编辑器 import 后的资源）
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var res: Resource = ResourceLoader.load(path)
		if res is Texture2D:
			return res as Texture2D
	# 尝试从虚拟文件系统加载（故事包内的图片）
	if _main and _main.fs:
		var content: PackedByteArray = _main.fs.get_binary_data(path)
		if content.size() > 0:
			return _bytes_to_texture(content, path)
	return null

func _bytes_to_texture(data: PackedByteArray, path: String) -> ImageTexture:
	var image := Image.new()
	var err: Error = ERR_FILE_UNRECOGNIZED
	var ext: String = path.get_extension().to_lower()
	match ext:
		"png":
			err = image.load_png_from_buffer(data)
		"jpg", "jpeg":
			err = image.load_jpg_from_buffer(data)
		"webp":
			err = image.load_webp_from_buffer(data)
	if err != OK:
		return null
	return ImageTexture.create_from_image(image)

func _animate_transition(transition: String, show: bool) -> void:
	if _slide_rect == null:
		return
	if _slide_tween:
		_slide_tween.kill()

	var duration: float = 0.3
	match transition:
		"instant":
			if show:
				_slide_rect.modulate.a = 1.0
			else:
				_slide_rect.modulate.a = 0.0
				_slide_rect.visible = false
				_is_active = false
		"fade":
			if show:
				_slide_rect.modulate.a = 0.0
				_slide_tween = _main.create_tween()
				_slide_tween.tween_property(_slide_rect, "modulate:a", 1.0, duration)
			else:
				_slide_tween = _main.create_tween()
				_slide_tween.tween_property(_slide_rect, "modulate:a", 0.0, duration)
				_slide_tween.tween_callback(func():
					_slide_rect.visible = false
					_is_active = false
				)
		"slide_left":
			if show:
				var target_x: float = _slide_rect.position.x
				_slide_rect.position.x = _root.size.x if _root else 800.0
				_slide_rect.modulate.a = 1.0
				_slide_tween = _main.create_tween()
				_slide_tween.tween_property(_slide_rect, "position:x", target_x, duration)\
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			else:
				_slide_tween = _main.create_tween()
				_slide_tween.tween_property(_slide_rect, "position:x", -_slide_rect.size.x, duration)\
					.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
				_slide_tween.tween_callback(func():
					_slide_rect.visible = false
					_is_active = false
				)
		"slide_right":
			if show:
				var target_x: float = _slide_rect.position.x
				_slide_rect.position.x = -_slide_rect.size.x
				_slide_rect.modulate.a = 1.0
				_slide_tween = _main.create_tween()
				_slide_tween.tween_property(_slide_rect, "position:x", target_x, duration)\
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			else:
				var end_x: float = _root.size.x if _root else 800.0
				_slide_tween = _main.create_tween()
				_slide_tween.tween_property(_slide_rect, "position:x", end_x, duration)\
					.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
				_slide_tween.tween_callback(func():
					_slide_rect.visible = false
					_is_active = false
				)
		_:
			# 默认 fade
			_animate_transition("fade", show)
