# ============================================================
# character_animator.gd — 角色动画控制器
# 管理嘴型、眨眼、动作帧、图层覆盖、临时动画效果
# 与 CharacterAssetLibrary 配合，驱动角色的视觉状态变化
# ============================================================
class_name CharacterAnimator
extends RefCounted

# ══════════════════════════════════════════
#  信号
# ══════════════════════════════════════════
signal action_completed(action_id: String)
signal layer_override_expired(override_id: String)

# ══════════════════════════════════════════
#  素材引用
# ══════════════════════════════════════════
var _textures: CharacterAssetLibrary.CharacterTextures = null
var _profile: CharacterAssetLibrary.AssetProfile = null

# ══════════════════════════════════════════
#  当前状态
# ══════════════════════════════════════════

## 当前表情 ID
var current_expression: String = "neutral"

## 当前嘴型 key
var current_mouth: String = "closed"

## 当前动作 ID（空 = 无动作）
var current_action: String = ""

## 是否正在说话
var is_speaking: bool = false

## 眨眼阶段: 0=open, 1=half_closing, 2=closed, 3=half_opening
var blink_phase: int = 0

## 当前服装变体（空 = 默认）
var current_costume: String = ""

## 活跃的图层覆盖 { override_id: LayerOverride }
var _active_overrides: Dictionary = {}

# ══════════════════════════════════════════
#  嘴型动画参数
# ══════════════════════════════════════════
var _mouth_timer: float = 0.0
var _mouth_interval: float = 0.08
var _mouth_sequence: Array[String] = ["closed", "half", "open", "half"]
var _mouth_index: int = 0

# ══════════════════════════════════════════
#  眨眼动画参数
# ══════════════════════════════════════════
var _blink_timer: float = 0.0
var _blink_interval: float = 3.5
var _blink_duration: float = 0.15
var _blink_active: bool = false

# ══════════════════════════════════════════
#  动作播放参数
# ══════════════════════════════════════════
var _action_timer: float = 0.0
var _action_frame_index: int = 0
var _action_frame_duration: float = 0.12
var _action_playing: bool = false
var _action_callback: Callable = Callable()

# ══════════════════════════════════════════
#  图层覆盖数据结构
# ══════════════════════════════════════════

## 临时图层覆盖（如：单独睁一只眼闭一只眼并维持5秒）
class LayerOverride:
	extends RefCounted
	var id: String = ""
	## 要覆盖的图层名 → 纹理 key（用于从 textures 中查找）
	var layer_changes: Dictionary = {}
	## 持续时间（秒），<= 0 表示永久直到手动移除
	var duration: float = -1.0
	## 剩余时间
	var remaining: float = -1.0
	## 过期后的回调
	var on_expire: Callable = Callable()


# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════

## 绑定素材
func bind_assets(profile: CharacterAssetLibrary.AssetProfile, textures: CharacterAssetLibrary.CharacterTextures) -> void:
	_profile = profile
	_textures = textures
	# 根据素材模式设置嘴型序列
	if profile and profile.mode == "layered" and not textures.mouth_textures.is_empty():
		_mouth_sequence = ["MBP", "slight", "A", "EI", "O", "UW", "slight", "MBP"]
		current_mouth = "MBP"
	else:
		_mouth_sequence = ["closed", "half", "open", "half"]
		current_mouth = "closed"


# ══════════════════════════════════════════
#  表情与嘴型控制
# ══════════════════════════════════════════

## 设置表情
func set_expression(expr_id: String) -> void:
	current_expression = expr_id

## 开始说话
func start_speaking() -> void:
	is_speaking = true
	_mouth_timer = 0.0
	_mouth_index = 0
	current_mouth = _mouth_sequence[0]

## 停止说话
func stop_speaking() -> void:
	is_speaking = false
	current_mouth = _mouth_sequence[0]
	_mouth_index = 0


# ══════════════════════════════════════════
#  动作播放
# ══════════════════════════════════════════

## 播放动作帧序列
func play_action(action_id: String, on_complete: Callable = Callable()) -> void:
	if _textures == null or not _textures.action_frames.has(action_id):
		if on_complete.is_valid():
			on_complete.call()
		return
	current_action = action_id
	_action_playing = true
	_action_frame_index = 0
	_action_timer = 0.0
	_action_callback = on_complete

## 停止当前动作
func stop_action() -> void:
	_action_playing = false
	current_action = ""
	_action_frame_index = 0

## 动作是否正在播放
func is_action_playing() -> bool:
	return _action_playing

## 获取当前动作帧索引
func get_action_frame_index() -> int:
	return _action_frame_index


# ══════════════════════════════════════════
#  服装切换
# ══════════════════════════════════════════

## 切换服装变体（空字符串 = 恢复默认）
func set_costume(costume_name: String) -> void:
	current_costume = costume_name

## 获取当前服装下某图层的有效纹理
## 优先级: 图层覆盖 > 服装变体 > 默认图层
func get_effective_layer_texture(layer_name: String) -> Variant:
	if _textures == null:
		return null

	# 1. 检查活跃的图层覆盖（按添加顺序，后添加优先）
	for override_id in _active_overrides.keys():
		var override: LayerOverride = _active_overrides[override_id]
		if override.layer_changes.has(layer_name):
			var tex_key: String = str(override.layer_changes[layer_name])
			if tex_key == "hide" or tex_key.is_empty():
				return null  # 隐藏图层
			# 查找纹理
			if _textures.layer_textures.has(tex_key):
				return _textures.layer_textures[tex_key]
			if _textures.eye_textures.has(tex_key):
				return _textures.eye_textures[tex_key]

	# 2. 检查服装变体
	if not current_costume.is_empty() and _textures.costume_textures.has(current_costume):
		var costume_layers: Dictionary = _textures.costume_textures[current_costume]
		if costume_layers.has(layer_name):
			return costume_layers[layer_name]  # 可能是 null（隐藏）

	# 3. 默认图层
	if _textures.layer_textures.has(layer_name):
		return _textures.layer_textures[layer_name]

	return null


# ══════════════════════════════════════════
#  图层覆盖管理
# ══════════════════════════════════════════

## 添加临时图层覆盖
## layer_changes: { "eye_L": "eye_L_close", "eye_R": "eye_R_open" }
## duration: 持续秒数（<= 0 为永久）
## 返回: override_id（用于手动移除）
func add_layer_override(layer_changes: Dictionary, duration: float = -1.0,
		on_expire: Callable = Callable()) -> String:
	var override := LayerOverride.new()
	override.id = "override_%d" % Time.get_ticks_msec()
	override.layer_changes = layer_changes
	override.duration = duration
	override.remaining = duration
	override.on_expire = on_expire
	_active_overrides[override.id] = override
	return override.id

## 移除图层覆盖
func remove_layer_override(override_id: String) -> void:
	_active_overrides.erase(override_id)

## 清除所有图层覆盖
func clear_all_overrides() -> void:
	_active_overrides.clear()

## 获取活跃覆盖数量
func get_override_count() -> int:
	return _active_overrides.size()

## 检查指定图层是否被某个活跃覆盖显式控制
func is_layer_overridden(layer_name: String) -> bool:
	for override_id in _active_overrides.keys():
		var override: LayerOverride = _active_overrides[override_id]
		if override.layer_changes.has(layer_name):
			return true
	return false


# ══════════════════════════════════════════
#  预设动画效果
# ══════════════════════════════════════════

## 眨一只眼（wink）
## side: "L" 或 "R"，duration: 持续秒数
func play_wink(side: String, duration: float = 2.0) -> String:
	var close_key: String = "eye_%s_close" % side
	var layer_key: String = "eye_%s" % side
	return add_layer_override({layer_key: close_key}, duration)

## 双眼闭合
func play_eyes_closed(duration: float = 1.0) -> String:
	return add_layer_override({
		"eye_L": "eye_L_close",
		"eye_R": "eye_R_close",
	}, duration)

## 惊讶（双眼大睁 + 嘴巴张大，通过 override 实现）
func play_surprised(duration: float = 2.0) -> String:
	return add_layer_override({
		"eye_L": "eye_L_open",
		"eye_R": "eye_R_open",
	}, duration)


# ══════════════════════════════════════════
#  每帧更新
# ══════════════════════════════════════════

func process(delta: float) -> void:
	_process_mouth(delta)
	_process_blink(delta)
	_process_action(delta)
	_process_overrides(delta)

func _process_mouth(delta: float) -> void:
	if not is_speaking:
		return
	_mouth_timer += delta
	if _mouth_timer >= _mouth_interval:
		_mouth_timer = 0.0
		_mouth_index = (_mouth_index + 1) % _mouth_sequence.size()
		if randf() < 0.2:
			_mouth_index = (_mouth_index + 1) % _mouth_sequence.size()
		current_mouth = _mouth_sequence[_mouth_index]

func _process_blink(delta: float) -> void:
	# 如果有眼睛相关的 override，暂停自动眨眼
	for override_id in _active_overrides.keys():
		var override: LayerOverride = _active_overrides[override_id]
		if override.layer_changes.has("eye_L") or override.layer_changes.has("eye_R"):
			return

	if _blink_active:
		_blink_timer += delta
		var phase_duration: float = _blink_duration / 4.0
		if _blink_timer >= phase_duration:
			_blink_timer = 0.0
			blink_phase += 1
			if blink_phase >= 4:
				blink_phase = 0
				_blink_active = false
				_blink_interval = randf_range(2.0, 5.0)
		return
	_blink_timer += delta
	if _blink_timer >= _blink_interval:
		_blink_active = true
		blink_phase = 1
		_blink_timer = 0.0

func _process_action(delta: float) -> void:
	if not _action_playing:
		return
	_action_timer += delta
	if _action_timer >= _action_frame_duration:
		_action_timer = 0.0
		_action_frame_index += 1
		var frames: Array = _textures.action_frames.get(current_action, []) if _textures else []
		if _action_frame_index >= frames.size():
			var completed_action: String = current_action
			_action_playing = false
			current_action = ""
			if _action_callback.is_valid():
				_action_callback.call()
			action_completed.emit(completed_action)

func _process_overrides(delta: float) -> void:
	var expired_ids: Array[String] = []
	for override_id in _active_overrides.keys():
		var override: LayerOverride = _active_overrides[override_id]
		if override.duration <= 0.0:
			continue  # 永久覆盖
		override.remaining -= delta
		if override.remaining <= 0.0:
			expired_ids.append(override_id)
	for oid in expired_ids:
		var override: LayerOverride = _active_overrides[oid]
		_active_overrides.erase(oid)
		if override.on_expire.is_valid():
			override.on_expire.call()
		layer_override_expired.emit(oid)


# ══════════════════════════════════════════
#  渲染状态查询
# ══════════════════════════════════════════

## 获取当前完整渲染状态（供渲染器使用）
func get_render_state() -> Dictionary:
	var state: Dictionary = {
		"expression": current_expression,
		"mouth": current_mouth,
		"is_speaking": is_speaking,
		"blink_phase": blink_phase,
		"action": current_action,
		"action_playing": _action_playing,
		"action_frame": _action_frame_index,
		"costume": current_costume,
		"has_overrides": not _active_overrides.is_empty(),
	}
	# 纹理引用（向后兼容）
	if _textures:
		state["static_portrait"] = _textures.static_portrait
		state["layer_textures"] = _textures.layer_textures
		state["mouth_textures"] = _textures.mouth_textures
		state["action_frames"] = _textures.action_frames
		state["overlay_textures"] = _textures.overlay_textures
		# 合并眼睛纹理到 layer_textures 中（兼容旧渲染逻辑）
		state["eye_textures"] = _textures.eye_textures
		state["blink_textures"] = {}
		state["expression_data"] = {}
	return state

## 重置所有动画状态
func reset() -> void:
	current_expression = "neutral"
	current_mouth = _mouth_sequence[0] if not _mouth_sequence.is_empty() else "closed"
	current_action = ""
	is_speaking = false
	blink_phase = 0
	current_costume = ""
	_active_overrides.clear()
	_action_playing = false
	_blink_active = false
	_mouth_index = 0
	_mouth_timer = 0.0
	_blink_timer = 0.0
	_action_timer = 0.0
