# ============================================================
# presentation_overlay.gd — 演示模式幻灯片叠加层
# 在 meeting 模式基础上显示 PPT/图片幻灯片
# ── 角色在一侧，幻灯片在另一侧
# ============================================================
# JSON 配置字段 (均在 dialogue line 中设置):
#   slide_image: String           — 图片路径 (res:// 或故事包路径)
#   slide_position: [x, y]       — 图片归一化坐标 (默认 [0.55, 0.1])
#   slide_size: [w, h]           — 图片归一化尺寸 (默认 [0.4, 0.5])
#   slide_fit: String            — 图片适配: "contain"(默认) / "cover" / "stretch" / "actual"
#   slide_align: String          — 图片对齐: "center"(默认) / "top_left" / "top_center" / "top_right"
#                                   / "center_left" / "center_right" / "bottom_left" / "bottom_center" / "bottom_right"
#   slide_area: [x, y, w, h]    — 展示区域归一化坐标+尺寸 (覆盖 slide_position/slide_size)
#   slide_transition: String     — 过渡动画: "fade"(默认) / "instant" / "slide_left" / "slide_right"
#   slide_hide: true/String      — 隐藏幻灯片 (true 等同 "fade")
# ============================================================
class_name PresentationOverlay
extends RefCounted

var _main: Control = null
var _root: Control = null
var _slide_container: Control = null   # 展示区域容器 (clip + 定位)
var _slide_rect: TextureRect = null    # 图片节点 (在容器内)
var _slide_tween: Tween = null
var _current_slide_path: String = ""
var _is_active: bool = false
var _current_config: Dictionary = {}   # 缓存当前配置用于 update_layout

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
## config 字段见文件头注释
func show_slide(config: Dictionary) -> void:
	var image_path: String = str(config.get("image", ""))
	if image_path.is_empty():
		return

	_ensure_slide_nodes()
	var texture: Texture2D = _load_slide_texture(image_path)
	if texture == null:
		push_warning("[PresentationOverlay] 无法加载幻灯片: %s" % image_path)
		return

	_current_slide_path = image_path
	_current_config = config.duplicate()
	_slide_rect.texture = texture

	# 适配模式
	var fit: String = str(config.get("fit", "contain"))
	_apply_fit_mode(fit)

	# 布局: 展示区域 + 图片在区域内的对齐
	_update_slide_layout(config)

	_slide_container.visible = true
	_is_active = true

	var transition: String = str(config.get("transition", "fade"))
	_animate_transition(transition, true)

## 隐藏幻灯片
func hide_slide(transition: String = "fade") -> void:
	if _slide_container == null or not _is_active:
		return
	_animate_transition(transition, false)

## 更新布局（窗口大小变化时）
func update_layout() -> void:
	if not _is_active or _slide_container == null:
		return
	_update_slide_layout(_current_config)

## 清理
func cleanup() -> void:
	if _slide_tween:
		_slide_tween.kill()
		_slide_tween = null
	if _slide_container and is_instance_valid(_slide_container):
		_slide_container.queue_free()
		_slide_container = null
		_slide_rect = null  # 子节点随容器释放
	_is_active = false
	_current_slide_path = ""
	_current_config = {}

func is_active() -> bool:
	return _is_active

func get_current_slide_path() -> String:
	return _current_slide_path

# ══════════════════════════════════════════
#  内部方法
# ══════════════════════════════════════════

func _ensure_slide_nodes() -> void:
	if _slide_container != null and is_instance_valid(_slide_container):
		return
	# 展示区域容器 — 开启裁剪
	_slide_container = Control.new()
	_slide_container.name = "PresentationArea"
	_slide_container.clip_contents = true
	_slide_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slide_container.visible = false

	# 图片节点
	_slide_rect = TextureRect.new()
	_slide_rect.name = "PresentationSlide"
	_slide_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_slide_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_slide_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slide_container.add_child(_slide_rect)

	if _root and is_instance_valid(_root):
		_root.add_child(_slide_container)

func _apply_fit_mode(fit: String) -> void:
	if _slide_rect == null:
		return
	match fit:
		"cover":
			_slide_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		"stretch":
			_slide_rect.stretch_mode = TextureRect.STRETCH_SCALE
		"actual":
			_slide_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
			_slide_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		_:  # "contain" (default)
			_slide_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_slide_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

func _update_slide_layout(config: Dictionary) -> void:
	if _slide_container == null or _slide_rect == null or _root == null:
		return
	var screen_w: float = _root.size.x if _root.size.x > 0 else 800.0
	var screen_h: float = _root.size.y if _root.size.y > 0 else 600.0

	# 展示区域位置和大小
	var area_x: float = 0.0
	var area_y: float = 0.0
	var area_w: float = 0.0
	var area_h: float = 0.0

	var area_arr: Array = config.get("area", []) as Array
	if area_arr.size() >= 4:
		# slide_area: [x, y, w, h] 优先级最高
		area_x = float(area_arr[0])
		area_y = float(area_arr[1])
		area_w = float(area_arr[2])
		area_h = float(area_arr[3])
	else:
		# 兼容 slide_position + slide_size
		var pos_arr: Array = config.get("position", [0.55, 0.1]) as Array
		var size_arr: Array = config.get("size", [0.4, 0.5]) as Array
		area_x = float(pos_arr[0]) if pos_arr.size() > 0 else 0.55
		area_y = float(pos_arr[1]) if pos_arr.size() > 1 else 0.1
		area_w = float(size_arr[0]) if size_arr.size() > 0 else 0.4
		area_h = float(size_arr[1]) if size_arr.size() > 1 else 0.5

	# 设置展示区域 (归一化 → 像素)
	_slide_container.position = Vector2(screen_w * area_x, screen_h * area_y)
	_slide_container.size = Vector2(screen_w * area_w, screen_h * area_h)

	# 图片在区域内的对齐
	var align: String = str(config.get("align", "center"))
	_apply_alignment(align, screen_w * area_w, screen_h * area_h)

func _apply_alignment(align: String, area_w: float, area_h: float) -> void:
	if _slide_rect == null:
		return

	# 默认填满展示区域
	_slide_rect.size = Vector2(area_w, area_h)

	# 对齐定位
	match align:
		"top_left":
			_slide_rect.position = Vector2.ZERO
		"top_center":
			_slide_rect.position = Vector2((area_w - _slide_rect.size.x) / 2.0, 0.0)
		"top_right":
			_slide_rect.position = Vector2(area_w - _slide_rect.size.x, 0.0)
		"center_left":
			_slide_rect.position = Vector2(0.0, (area_h - _slide_rect.size.y) / 2.0)
		"center_right":
			_slide_rect.position = Vector2(area_w - _slide_rect.size.x, (area_h - _slide_rect.size.y) / 2.0)
		"bottom_left":
			_slide_rect.position = Vector2(0.0, area_h - _slide_rect.size.y)
		"bottom_center":
			_slide_rect.position = Vector2((area_w - _slide_rect.size.x) / 2.0, area_h - _slide_rect.size.y)
		"bottom_right":
			_slide_rect.position = Vector2(area_w - _slide_rect.size.x, area_h - _slide_rect.size.y)
		_:  # "center"
			_slide_rect.position = Vector2((area_w - _slide_rect.size.x) / 2.0, (area_h - _slide_rect.size.y) / 2.0)

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
	if _slide_container == null:
		return
	if _slide_tween:
		_slide_tween.kill()

	var duration: float = 0.3
	match transition:
		"instant":
			if show:
				_slide_container.modulate.a = 1.0
			else:
				_slide_container.modulate.a = 0.0
				_slide_container.visible = false
				_is_active = false
		"fade":
			if show:
				_slide_container.modulate.a = 0.0
				_slide_tween = _main.create_tween()
				_slide_tween.tween_property(_slide_container, "modulate:a", 1.0, duration)
			else:
				_slide_tween = _main.create_tween()
				_slide_tween.tween_property(_slide_container, "modulate:a", 0.0, duration)
				_slide_tween.tween_callback(func():
					_slide_container.visible = false
					_is_active = false
				)
		"slide_left":
			if show:
				var target_x: float = _slide_container.position.x
				_slide_container.position.x = _root.size.x if _root else 800.0
				_slide_container.modulate.a = 1.0
				_slide_tween = _main.create_tween()
				_slide_tween.tween_property(_slide_container, "position:x", target_x, duration)\
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			else:
				_slide_tween = _main.create_tween()
				_slide_tween.tween_property(_slide_container, "position:x", -_slide_container.size.x, duration)\
					.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
				_slide_tween.tween_callback(func():
					_slide_container.visible = false
					_is_active = false
				)
		"slide_right":
			if show:
				var target_x: float = _slide_container.position.x
				_slide_container.position.x = -_slide_container.size.x
				_slide_container.modulate.a = 1.0
				_slide_tween = _main.create_tween()
				_slide_tween.tween_property(_slide_container, "position:x", target_x, duration)\
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			else:
				var end_x: float = _root.size.x if _root else 800.0
				_slide_tween = _main.create_tween()
				_slide_tween.tween_property(_slide_container, "position:x", end_x, duration)\
					.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
				_slide_tween.tween_callback(func():
					_slide_container.visible = false
					_is_active = false
				)
		_:
			# 默认 fade
			_animate_transition("fade", show)
