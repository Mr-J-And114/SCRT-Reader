# ============================================================
# comm_character.gd — 通讯角色数据模型
# 管理角色的素材层、表情状态机、嘴型帧、动作帧
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
#  素材缓存
# ══════════════════════════════════════════
## 静态模式：单张头像纹理
var static_portrait: ImageTexture = null

## 分层模式：各层纹理 { "background": ImageTexture, "body": ImageTexture, ... }
var layer_textures: Dictionary = {}

## 表情帧 { "neutral": { "eyes": ImageTexture, "mouth_default": "closed" }, ... }
var expression_data: Dictionary = {}

## 嘴型帧 { "closed": ImageTexture, "half": ImageTexture, "open": ImageTexture, "wide": ImageTexture }
var mouth_textures: Dictionary = {}

## 眨眼帧 { "neutral_blink": ImageTexture, ... }
var blink_textures: Dictionary = {}

## 动作帧 { "appear": [ImageTexture, ...], "nod": [ImageTexture, ...] }
var action_frames: Dictionary = {}

## overlay 纹理列表
var overlay_textures: Dictionary = {}

# ══════════════════════════════════════════
#  当前状态
# ══════════════════════════════════════════
var current_expression: String = "neutral"
var current_mouth: String = "closed"
var current_action: String = ""
var is_speaking: bool = false
var is_blinking: bool = false

# 嘴型动画计时
var _mouth_timer: float = 0.0
var _mouth_interval: float = 0.08  # 嘴型切换间隔(秒)
var _mouth_sequence: Array[String] = ["closed", "half", "open", "half"]
var _mouth_index: int = 0

# 眨眼计时
var _blink_timer: float = 0.0
var _blink_interval: float = 3.5  # 平均眨眼间隔
var _blink_duration: float = 0.15
var _blink_active: bool = false

# 动作播放
var _action_timer: float = 0.0
var _action_frame_index: int = 0
var _action_frame_duration: float = 0.12
var _action_playing: bool = false
var _action_callback: Callable = Callable()

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════

## 从 manifest 配置加载角色数据
func load_from_config(config: Dictionary, fs: FileSystem) -> void:
	id = str(config.get("id", ""))
	display_name = str(config.get("name", "UNKNOWN"))
	title = str(config.get("title", ""))
	sprite_dir = str(config.get("sprite_dir", ""))
	default_expression = str(config.get("default_expression", "neutral"))
	current_expression = default_expression
	
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
			# 自动检测：有 sprite_dir 就尝试加载，否则 minimal
			if not sprite_dir.is_empty():
				sprite_mode = SpriteMode.STATIC  # 默认静态，有分层素材时升级
			else:
				sprite_mode = SpriteMode.MINIMAL

	# 加载素材
	_load_sprites(config, fs)

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
		# 默认文件名
		mouth_files = ["mouth_closed.png", "mouth_half.png", "mouth_open.png", "mouth_wide.png"]

	var mouth_keys: Array[String] = ["closed", "half", "open", "wide"]
	for i in range(mini(mouth_files.size(), mouth_keys.size())):
		var full_path: String = sprite_dir + str(mouth_files[i])
		var texture: ImageTexture = _load_texture_from_fs(full_path, fs)
		if texture:
			mouth_textures[mouth_keys[i]] = texture

## 加载分层素材（★ 预留：后续素材到位后实现）
func _load_layered_sprites(_config: Dictionary, _fs: FileSystem) -> void:
	# TODO: 加载 background, body, face, eyes, mouth, overlay 各层
	# 当前降级为静态模式
	push_warning("[CommCharacter] 分层素材尚未实现，降级为静态模式")
	sprite_mode = SpriteMode.STATIC
	_load_static_portrait(_config, _fs)
	_load_mouth_frames(_config, _fs)

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
#  表情与嘴型控制
# ══════════════════════════════════════════

## 设置表情
func set_expression(expr_id: String) -> void:
	current_expression = expr_id

## 开始说话（启动嘴型动画）
func start_speaking() -> void:
	is_speaking = true
	_mouth_timer = 0.0
	_mouth_index = 0
	current_mouth = "closed"

## 停止说话
func stop_speaking() -> void:
	is_speaking = false
	current_mouth = "closed"
	_mouth_index = 0

## 播放动作
func play_action(action_id: String, on_complete: Callable = Callable()) -> void:
	if not action_frames.has(action_id):
		# 动作素材不存在，直接完成
		if on_complete.is_valid():
			on_complete.call()
		return
	current_action = action_id
	_action_playing = true
	_action_frame_index = 0
	_action_timer = 0.0
	_action_callback = on_complete

## 每帧更新（嘴型、眨眼、动作动画）
func process(delta: float) -> void:
	_process_mouth(delta)
	_process_blink(delta)
	_process_action(delta)

func _process_mouth(delta: float) -> void:
	if not is_speaking:
		return
	_mouth_timer += delta
	if _mouth_timer >= _mouth_interval:
		_mouth_timer = 0.0
		# 半随机嘴型切换
		_mouth_index = (_mouth_index + 1) % _mouth_sequence.size()
		# 偶尔跳过一帧增加自然感
		if randf() < 0.2:
			_mouth_index = (_mouth_index + 1) % _mouth_sequence.size()
		current_mouth = _mouth_sequence[_mouth_index]

func _process_blink(delta: float) -> void:
	if _blink_active:
		_blink_timer += delta
		if _blink_timer >= _blink_duration:
			_blink_active = false
			is_blinking = false
			_blink_timer = 0.0
			_blink_interval = randf_range(2.0, 5.0)
		return

	_blink_timer += delta
	if _blink_timer >= _blink_interval:
		_blink_active = true
		is_blinking = true
		_blink_timer = 0.0

func _process_action(delta: float) -> void:
	if not _action_playing:
		return
	_action_timer += delta
	if _action_timer >= _action_frame_duration:
		_action_timer = 0.0
		_action_frame_index += 1
		var frames: Array = action_frames.get(current_action, [])
		if _action_frame_index >= frames.size():
			_action_playing = false
			current_action = ""
			if _action_callback.is_valid():
				_action_callback.call()

# ══════════════════════════════════════════
#  渲染数据获取（供 sprite_renderer 使用）
# ══════════════════════════════════════════

## 获取当前需要渲染的数据
func get_render_state() -> Dictionary:
	return {
		"sprite_mode": sprite_mode,
		"expression": current_expression,
		"mouth": current_mouth,
		"is_speaking": is_speaking,
		"is_blinking": is_blinking,
		"action": current_action,
		"action_playing": _action_playing,
		"action_frame": _action_frame_index,
		# 纹理引用
		"static_portrait": static_portrait,
		"layer_textures": layer_textures,
		"expression_data": expression_data,
		"mouth_textures": mouth_textures,
		"blink_textures": blink_textures,
		"action_frames": action_frames,
		"overlay_textures": overlay_textures,
	}

## 是否有可显示的视觉素材
func has_visual() -> bool:
	return sprite_mode != SpriteMode.MINIMAL
