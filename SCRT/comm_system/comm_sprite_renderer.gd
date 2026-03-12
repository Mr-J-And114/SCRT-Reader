# ============================================================
# comm_sprite_renderer.gd — 角色素材渲染器
# 根据角色当前状态合成显示画面
# ── 修改：头像区域适配 295:413 竖版宽高比
# ============================================================
class_name CommSpriteRenderer
extends RefCounted

var _portrait_rect: TextureRect = null
var _mouth_overlay: TextureRect = null
var _container: Control = null
var _mouth_indicator: Label = null
var _character: CommCharacter = null

## 尺寸配置（默认保持 295:413 比例）
var portrait_size: Vector2i = Vector2i(93, 130)

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════

## 创建渲染节点并挂到指定容器
func setup(parent_container: Control) -> void:
	_container = parent_container

	# 主头像
	_portrait_rect = TextureRect.new()
	_portrait_rect.custom_minimum_size = Vector2(portrait_size.x, portrait_size.y)
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.size = Vector2(portrait_size.x, portrait_size.y)
	_container.add_child(_portrait_rect)

	# 嘴型覆盖层
	_mouth_overlay = TextureRect.new()
	_mouth_overlay.custom_minimum_size = Vector2(portrait_size.x, portrait_size.y)
	_mouth_overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_mouth_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mouth_overlay.size = Vector2(portrait_size.x, portrait_size.y)
	_mouth_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mouth_overlay.visible = false
	_container.add_child(_mouth_overlay)

	# 程序化嘴型指示器
	_mouth_indicator = Label.new()
	_mouth_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mouth_indicator.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_mouth_indicator.visible = false
	_container.add_child(_mouth_indicator)

## 绑定角色
func set_character(character: CommCharacter) -> void:
	_character = character
	_update_portrait()

## 清除显示
func clear() -> void:
	_character = null
	if _portrait_rect:
		_portrait_rect.texture = null
	if _mouth_overlay:
		_mouth_overlay.texture = null
		_mouth_overlay.visible = false
	if _mouth_indicator:
		_mouth_indicator.visible = false

# ══════════════════════════════════════════
#  每帧更新
# ══════════════════════════════════════════
func process(_delta: float) -> void:
	if _character == null:
		return
	_update_mouth()
	_update_blink()
	_update_action()

## 更新头像主图
func _update_portrait() -> void:
	if _character == null or _portrait_rect == null:
		return
	var state: Dictionary = _character.get_render_state()
	var mode = state.get("sprite_mode", CommCharacter.SpriteMode.MINIMAL)
	match mode:
		CommCharacter.SpriteMode.STATIC:
			var tex = state.get("static_portrait")
			if tex is Texture2D:
				_portrait_rect.texture = tex
				_portrait_rect.visible = true
			else:
				_portrait_rect.visible = false
		CommCharacter.SpriteMode.LAYERED:
			var tex = state.get("static_portrait")
			if tex is Texture2D:
				_portrait_rect.texture = tex
				_portrait_rect.visible = true
		CommCharacter.SpriteMode.MINIMAL:
			_portrait_rect.visible = false

## 更新嘴型显示
func _update_mouth() -> void:
	if _character == null:
		return
	var state: Dictionary = _character.get_render_state()
	if not state.get("is_speaking", false):
		if _mouth_overlay:
			_mouth_overlay.visible = false
		if _mouth_indicator:
			_mouth_indicator.visible = false
		return

	var mouth_key: String = state.get("mouth", "closed")
	var mouth_textures: Dictionary = state.get("mouth_textures", {})

	if mouth_textures.has(mouth_key):
		_mouth_overlay.texture = mouth_textures[mouth_key] as ImageTexture
		_mouth_overlay.visible = true
		_mouth_indicator.visible = false
	else:
		_mouth_overlay.visible = false
		_show_programmatic_mouth(mouth_key)

## 程序化嘴型（ASCII 降级）
func _show_programmatic_mouth(mouth_key: String) -> void:
	if _mouth_indicator == null:
		return
	var mouth_char: String = ""
	match mouth_key:
		"closed": mouth_char = "—"
		"half": mouth_char = "○"
		"open": mouth_char = "◎"
		"wide": mouth_char = "●"
		_: mouth_char = "—"
	_mouth_indicator.text = mouth_char
	_mouth_indicator.visible = _character.is_speaking

## 更新眨眼效果
func _update_blink() -> void:
	if _character == null:
		return
	# 眨眼由 CharacterAnimator 驱动，通过 blink_phase 控制
	# 实际渲染在 CommUI._update_layered_portrait() 中处理

## 更新动作动画
func _update_action() -> void:
	if _character == null:
		return
	# 动作帧由 CharacterAnimator 驱动，通过 action_frame 控制
	# 实际渲染在 CommUI._update_layered_portrait() 中处理

# ══════════════════════════════════════════
#  布局辅助
# ══════════════════════════════════════════

## 设置头像区域位置
func set_position(pos: Vector2) -> void:
	if _portrait_rect:
		_portrait_rect.position = pos
	if _mouth_overlay:
		_mouth_overlay.position = pos
	if _mouth_indicator:
		_mouth_indicator.position = pos + Vector2(0, portrait_size.y - 20)

## 设置头像区域大小
func set_size(new_size: Vector2i) -> void:
	portrait_size = new_size
	if _portrait_rect:
		_portrait_rect.custom_minimum_size = Vector2(new_size.x, new_size.y)
		_portrait_rect.size = Vector2(new_size.x, new_size.y)
	if _mouth_overlay:
		_mouth_overlay.custom_minimum_size = Vector2(new_size.x, new_size.y)
		_mouth_overlay.size = Vector2(new_size.x, new_size.y)

## 销毁所有节点
func cleanup() -> void:
	if _portrait_rect and is_instance_valid(_portrait_rect):
		_portrait_rect.queue_free()
	if _mouth_overlay and is_instance_valid(_mouth_overlay):
		_mouth_overlay.queue_free()
	if _mouth_indicator and is_instance_valid(_mouth_indicator):
		_mouth_indicator.queue_free()
	_character = null
