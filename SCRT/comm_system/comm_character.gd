# ============================================================
# comm_character.gd — 通讯角色数据模型
# 轻量级数据模型，委托 CharacterAnimator 处理动画
# 委托 CharacterAssetLibrary 管理素材加载
# ============================================================
class_name CommCharacter
extends RefCounted

# ══════════════════════════════════════════
#  角色基础信息
# ══════════════════════════════════════════
var id: String = ""
var display_name: String = "UNKNOWN"
var title: String = ""
var sprite_dir: String = ""
var default_expression: String = "neutral"
var name_color: Color = Color.WHITE
## 头像在对话栏中的位置: "left" / "center" / "right"
var portrait_position: String = "left"


# ══════════════════════════════════════════
#  素材模式
# ══════════════════════════════════════════
## "layered" = 完整分层素材, "static" = 单张静态图 + 嘴型, "minimal" = 纯文字无图
enum SpriteMode { LAYERED, STATIC, MINIMAL }
var sprite_mode: SpriteMode = SpriteMode.MINIMAL

# ══════════════════════════════════════════
#  语音参数
# ══════════════════════════════════════════
var voice_config: Dictionary = {
	"tone": "sine",           # sine / square / saw / noise
	"base_pitch": 1.0,        # 0.5 ~ 2.0
	"pitch_variance": 0.15,   # 0.0 ~ 0.5
	"speed": "normal",        # slow / normal / fast
	"char_sound_duration": 50, # ms
	"vowel_pitch_boost": 0.1,
	"punctuation_pause": 200,  # ms
}

# ══════════════════════════════════════════
#  模块化组件
# ══════════════════════════════════════════

## 动画控制器（嘴型、眨眼、动作、图层覆盖）
var animator: CharacterAnimator = null

## 素材库引用（由 CharacterRegistry 注入）
var _asset_library: CharacterAssetLibrary = null

# ══════════════════════════════════════════
#  向后兼容的素材缓存（代理到 asset_library）
# ══════════════════════════════════════════
## 静态模式：单张头像纹理
var static_portrait: ImageTexture = null

## 分层模式：各层纹理 { "background": ImageTexture, "body": ImageTexture, ... }
var layer_textures: Dictionary = {}

## 表情帧 { "neutral": { "eyes": ImageTexture, "mouth_default": "closed" }, ... }
var expression_data: Dictionary = {}

## 嘴型帧 { "MBP": ImageTexture, "slight": ImageTexture, "A": ImageTexture, ... }
var mouth_textures: Dictionary = {}

## 眨眼帧 { "neutral_blink": ImageTexture, ... }
var blink_textures: Dictionary = {}

## 动作帧 { "appear": [ImageTexture, ...], "nod": [ImageTexture, ...] }
var action_frames: Dictionary = {}

## overlay 纹理列表
var overlay_textures: Dictionary = {}

## 分层渲染顺序与文件映射（可由 manifest 或 comm_manager 配置）
var layer_config: Dictionary = {
	"order": [],
	"files": {},
}

# ══════════════════════════════════════════
#  当前状态（代理到 animator）
# ══════════════════════════════════════════
var current_expression: String:
	get:
		return animator.current_expression if animator else "neutral"
	set(value):
		if animator:
			animator.current_expression = value

var current_mouth: String:
	get:
		return animator.current_mouth if animator else "closed"
	set(value):
		if animator:
			animator.current_mouth = value

var current_action: String:
	get:
		return animator.current_action if animator else ""
	set(value):
		if animator:
			animator.current_action = value

var is_speaking: bool:
	get:
		return animator.is_speaking if animator else false
	set(value):
		if animator:
			animator.is_speaking = value

var blink_phase: int:
	get:
		return animator.blink_phase if animator else 0
	set(value):
		if animator:
			animator.blink_phase = value


# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════

func _init() -> void:
	animator = CharacterAnimator.new()

## 从 manifest 配置加载角色数据
func load_from_config(config: Dictionary, fs: FileSystem) -> void:
	id = str(config.get("id", ""))
	display_name = str(config.get("name", "UNKNOWN"))
	title = str(config.get("title", ""))
	sprite_dir = str(config.get("sprite_dir", ""))
	default_expression = str(config.get("default_expression", "neutral"))

	# 名称颜色
	if config.has("name_color"):
		var nc = config["name_color"]
		if nc is String:
			name_color = Color.from_string(nc, Color.WHITE)
		elif nc is Color:
			name_color = nc

	# 头像位置
	portrait_position = str(config.get("portrait_position", "left")).to_lower()
	if portrait_position not in ["left", "center", "right"]:
		portrait_position = "left"

	# 语音
	if config.has("voice") and config["voice"] is Dictionary:
		for key in config["voice"].keys():
			voice_config[key] = config["voice"][key]

	# 分层素材配置（从 manifest 或代码传入）
	if config.has("layer_config") and config["layer_config"] is Dictionary:
		layer_config = config["layer_config"]

	# 判断素材模式
	var mode_str: String = str(config.get("sprite_mode", "")).to_lower()
	match mode_str:
		"static":
			sprite_mode = SpriteMode.STATIC
		"layered":
			sprite_mode = SpriteMode.LAYERED
		"minimal":
			sprite_mode = SpriteMode.MINIMAL
		_:
			if not sprite_dir.is_empty():
				sprite_mode = SpriteMode.STATIC
			else:
				sprite_mode = SpriteMode.MINIMAL

	# 加载素材（向后兼容路径）
	_load_sprites(config, fs)

	# 初始化 animator 表情
	animator.set_expression(default_expression)


## 使用 AssetLibrary 的新加载路径初始化
func init_from_asset_library(asset_library: CharacterAssetLibrary) -> void:
	_asset_library = asset_library
	if not asset_library.has_profile(id):
		return

	var textures: CharacterAssetLibrary.CharacterTextures = asset_library.load_character_assets(id)
	if textures == null:
		return

	var profile: CharacterAssetLibrary.AssetProfile = asset_library.get_profile(id)
	if profile == null:
		return

	# 同步素材模式
	match profile.mode:
		"layered":
			sprite_mode = SpriteMode.LAYERED
		"static":
			sprite_mode = SpriteMode.STATIC
		_:
			sprite_mode = SpriteMode.MINIMAL

	# 同步纹理到向后兼容字段
	static_portrait = textures.static_portrait
	layer_textures = textures.layer_textures
	mouth_textures = textures.mouth_textures
	action_frames = textures.action_frames
	overlay_textures = textures.overlay_textures

	# 更新 layer_config
	layer_config = {
		"order": profile.layer_order.duplicate(),
		"files": profile.layer_files.duplicate(),
	}

	# 绑定 animator
	animator.bind_assets(profile, textures)


# ══════════════════════════════════════════
#  向后兼容的素材加载（旧路径）
# ══════════════════════════════════════════

## 加载素材（根据模式）
func _load_sprites(config: Dictionary, fs: FileSystem) -> void:
	if sprite_mode == SpriteMode.MINIMAL:
		return
	if sprite_mode == SpriteMode.STATIC:
		_load_static_portrait(config, fs)
		_load_mouth_frames(config, fs)
		return
	if sprite_mode == SpriteMode.LAYERED:
		_load_layered_sprites(config, fs)
		return

## 加载静态头像
func _load_static_portrait(config: Dictionary, fs: FileSystem) -> void:
	var portrait_file: String = str(config.get("static_image", "portrait.png"))
	var full_path: String = sprite_dir + portrait_file
	var texture: ImageTexture = _load_texture_from_fs(full_path, fs)
	if texture:
		static_portrait = texture
	else:
		push_warning("[CommCharacter] 无法加载静态头像: %s" % full_path)
		sprite_mode = SpriteMode.MINIMAL

## 加载嘴型帧
func _load_mouth_frames(config: Dictionary, fs: FileSystem) -> void:
	var mouth_files: Array = []
	if config.has("mouth_frames") and config["mouth_frames"] is Array:
		mouth_files = config["mouth_frames"]
	else:
		mouth_files = ["mouth_closed.png", "mouth_half.png", "mouth_open.png", "mouth_wide.png"]
	var mouth_keys: Array[String] = ["closed", "half", "open", "wide"]
	for i in range(mini(mouth_files.size(), mouth_keys.size())):
		var full_path: String = sprite_dir + str(mouth_files[i])
		var texture: ImageTexture = _load_texture_from_fs(full_path, fs)
		if texture:
			mouth_textures[mouth_keys[i]] = texture

## 加载分层素材
func _load_layered_sprites(_config: Dictionary, _fs: FileSystem) -> void:
	var base_path: String = sprite_dir
	if base_path.is_empty():
		push_warning("[CommCharacter] sprite_dir 为空，无法加载分层素材")
		sprite_mode = SpriteMode.STATIC
		_load_static_portrait(_config, _fs)
		return

	# 加载静态图层
	var files_map: Dictionary = layer_config.get("files", {})
	for layer_name in files_map.keys():
		var file: String = str(files_map[layer_name])
		if file.is_empty():
			continue
		var full_path: String = base_path + file
		if not ResourceLoader.exists(full_path):
			push_warning("[CommCharacter] 图层未找到: %s" % full_path)
			continue
		var tex: Texture2D = load(full_path)
		if tex:
			layer_textures[layer_name] = tex

	# 加载眼睛状态 (3 状态 × 2 侧)
	var eye_files: Dictionary = layer_config.get("eye_files", {})
	for key in eye_files.keys():
		var full_path: String = base_path + str(eye_files[key])
		if ResourceLoader.exists(full_path):
			var tex: Texture2D = load(full_path)
			if tex:
				layer_textures[key] = tex

	# 加载嘴型音素帧 (8 种)
	var mouth_map: Dictionary = layer_config.get("mouth_files", {})
	for key in mouth_map.keys():
		var full_path: String = base_path + str(mouth_map[key])
		if ResourceLoader.exists(full_path):
			var tex: Texture2D = load(full_path)
			if tex:
				mouth_textures[key] = tex

	# 加载失败则降级
	if layer_textures.is_empty():
		push_warning("[CommCharacter] 分层素材加载失败，降级为静态模式")
		sprite_mode = SpriteMode.STATIC
		_load_static_portrait(_config, _fs)
		return

	# 分层模式使用 8 音素嘴型序列
	animator._mouth_sequence = ["MBP", "slight", "A", "EI", "O", "UW", "slight", "MBP"]
	animator.current_mouth = "MBP"

	# 加载动作帧序列（可选）
	var act_files: Dictionary = layer_config.get("action_files", {})
	for action_id in act_files.keys():
		var frames_list: Array = act_files[action_id] as Array
		if frames_list == null or frames_list.is_empty():
			continue
		var loaded_frames: Array = []
		for frame_file in frames_list:
			var full_path: String = base_path + str(frame_file)
			if ResourceLoader.exists(full_path):
				var tex: Texture2D = load(full_path)
				if tex:
					loaded_frames.append(tex)
		if not loaded_frames.is_empty():
			action_frames[action_id] = loaded_frames

## 从文件系统加载纹理
func _load_texture_from_fs(path: String, fs: FileSystem) -> ImageTexture:
	if fs == null:
		return null
	var data: PackedByteArray = fs.get_binary_data(fs.normalize_path(path))
	if data.is_empty():
		return null
	var img := Image.new()
	var err: Error = ERR_FILE_UNRECOGNIZED
	var ext: String = path.get_extension().to_lower()
	match ext:
		"png":
			err = img.load_png_from_buffer(data)
		"jpg", "jpeg":
			err = img.load_jpg_from_buffer(data)
		"webp":
			err = img.load_webp_from_buffer(data)
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)

# ══════════════════════════════════════════
#  表情与嘴型控制（代理到 animator）
# ══════════════════════════════════════════

## 设置表情
func set_expression(expr_id: String) -> void:
	animator.set_expression(expr_id)

## 开始说话（启动嘴型动画）
func start_speaking() -> void:
	animator.start_speaking()

## 停止说话
func stop_speaking() -> void:
	animator.stop_speaking()

## 播放动作
func play_action(action_id: String, on_complete: Callable = Callable()) -> void:
	animator.play_action(action_id, on_complete)

## 每帧更新（嘴型、眨眼、动作动画）
func process(delta: float) -> void:
	animator.process(delta)

# ══════════════════════════════════════════
#  图层覆盖（新功能，代理到 animator）
# ══════════════════════════════════════════

## 添加临时图层覆盖
func add_layer_override(layer_changes: Dictionary, duration: float = -1.0,
		on_expire: Callable = Callable()) -> String:
	return animator.add_layer_override(layer_changes, duration, on_expire)

## 移除图层覆盖
func remove_layer_override(override_id: String) -> void:
	animator.remove_layer_override(override_id)

## 清除所有图层覆盖
func clear_all_overrides() -> void:
	animator.clear_all_overrides()

## 切换服装
func set_costume(costume_name: String) -> void:
	animator.set_costume(costume_name)

## 播放预设动画：眨一只眼
func play_wink(side: String, duration: float = 2.0) -> String:
	return animator.play_wink(side, duration)

# ══════════════════════════════════════════
#  渲染数据获取（供 sprite_renderer 使用）
# ══════════════════════════════════════════

## 获取当前需要渲染的数据
func get_render_state() -> Dictionary:
	var state: Dictionary = animator.get_render_state()
	state["sprite_mode"] = sprite_mode
	# 向后兼容：如果 animator 没有绑定素材，从本地缓存读取
	if state.get("static_portrait") == null and static_portrait != null:
		state["static_portrait"] = static_portrait
	if state.get("layer_textures", {}).is_empty() and not layer_textures.is_empty():
		state["layer_textures"] = layer_textures
	if state.get("mouth_textures", {}).is_empty() and not mouth_textures.is_empty():
		state["mouth_textures"] = mouth_textures
	if state.get("action_frames", {}).is_empty() and not action_frames.is_empty():
		state["action_frames"] = action_frames
	if state.get("overlay_textures", {}).is_empty() and not overlay_textures.is_empty():
		state["overlay_textures"] = overlay_textures
	if state.get("expression_data", {}).is_empty() and not expression_data.is_empty():
		state["expression_data"] = expression_data
	if state.get("blink_textures", {}).is_empty() and not blink_textures.is_empty():
		state["blink_textures"] = blink_textures
	return state

## 是否有可显示的视觉素材
func has_visual() -> bool:
	return sprite_mode != SpriteMode.MINIMAL
