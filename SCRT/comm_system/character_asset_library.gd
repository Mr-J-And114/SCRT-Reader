# ============================================================
# character_asset_library.gd — 角色素材库
# 数据驱动的角色素材配置、加载与管理
# 支持分层(layered)、静态(static)、纯文字(minimal)三种模式
# 每个角色通过 AssetProfile 定义素材结构，轻松扩展新角色
# ============================================================
class_name CharacterAssetLibrary
extends RefCounted

# ══════════════════════════════════════════
#  素材配置（AssetProfile）
# ══════════════════════════════════════════

## 单个角色的完整素材配置
## 使用方法：创建 profile → 注册到 library → 加载纹理
class AssetProfile:
	extends RefCounted

	## 素材根目录（res:// 或虚拟文件系统路径）
	var base_dir: String = ""

	## 素材模式: "layered" / "static" / "minimal"
	var mode: String = "minimal"

	## ★ 图片画布原始尺寸（所有图层共用同一画布，用于精确计算缩放和底部对齐）
	var canvas_size: Vector2 = Vector2(1216, 1803)

	## ★ 显示调整参数（用于适配不同画布尺寸的素材）
	var display_scale: float = 1.0              # 整体缩放比例
	var display_offset: Vector2 = Vector2.ZERO  # 位置偏移 (px)
	var meeting_offset: Vector2 = Vector2.ZERO  # 仅 meeting 模式的额外位置偏移 (px)
	var clip_rect: Rect2 = Rect2()              # 裁剪区域 (空=不裁剪)
	var anchor_point: Vector2 = Vector2(0.5, 1.0)  # 锚点 (0.5,1.0=底部中心)

	## 分层渲染顺序（从底到顶）
	## 例: ["body", "head", "nose", "eye_L", "eye_R", "mouth", "eyehair", "glasses"]
	var layer_order: Array[String] = []
	var idle_eye_state: String = "open"
	var idle_mouth_key: String = "MBP"

	## 静态图层文件映射 { "head": "head.png", "body": "body.png" }
	var layer_files: Dictionary = {}

	## 眼睛状态文件 { "eye_L_open": "eyes-1-L-open.png", ... }
	## 命名规则: eye_{L|R}_{open|half|close}
	var eye_files: Dictionary = {}

	## 嘴型音素文件 { "MBP": "M-1-MBP-closed.png", "A": "M-3-A.png", ... }
	## 标准 8 音素: MBP, slight, A, EI, O, UW, FV, LNTS
	## 简易 4 帧: closed, half, open, wide
	var mouth_files: Dictionary = {}

	## 服装/变体 { "variant_name": { "body": "body-alt.png", "glasses": null } }
	## null 值表示隐藏该图层
	var costumes: Dictionary = {}

	## 动作帧序列 { "nod": ["nod-1.png", "nod-2.png", ...], ... }
	var action_files: Dictionary = {}

	## 静态头像文件（static 模式用）
	var static_image: String = "portrait.png"

	## 静态模式嘴型帧文件列表（按 closed/half/open/wide 顺序）
	var static_mouth_files: Array[String] = [
		"mouth_closed.png", "mouth_half.png", "mouth_open.png", "mouth_wide.png"
	]

	## 将 profile 导出为 Dictionary（用于序列化/调试）
	func to_dict() -> Dictionary:
		return {
			"base_dir": base_dir,
			"mode": mode,
			"canvas_size": [canvas_size.x, canvas_size.y],
			"display_scale": display_scale,
			"display_offset": [display_offset.x, display_offset.y],
			"meeting_offset": [meeting_offset.x, meeting_offset.y],
			"clip_rect": [clip_rect.position.x, clip_rect.position.y, clip_rect.size.x, clip_rect.size.y] if clip_rect.size != Vector2.ZERO else [],
			"anchor_point": [anchor_point.x, anchor_point.y],
			"layer_order": layer_order,
			"idle_eye_state": idle_eye_state,
			"idle_mouth_key": idle_mouth_key,
			"layer_files": layer_files,
			"eye_files": eye_files,
			"mouth_files": mouth_files,
			"costumes": costumes,
			"action_files": action_files,
			"static_image": static_image,
			"static_mouth_files": static_mouth_files,
		}

	## 从 Dictionary 创建 profile
	static func from_dict(data: Dictionary) -> AssetProfile:
		var p := AssetProfile.new()
		p.base_dir = str(data.get("base_dir", ""))
		p.mode = str(data.get("mode", "minimal"))

		# 显示调整参数
		if data.has("canvas_size") and data["canvas_size"] is Array:
			var cs: Array = data["canvas_size"]
			if cs.size() >= 2:
				p.canvas_size = Vector2(float(cs[0]), float(cs[1]))
		p.display_scale = float(data.get("display_scale", 1.0))
		if data.has("display_offset") and data["display_offset"] is Array:
			var off: Array = data["display_offset"]
			if off.size() >= 2:
				p.display_offset = Vector2(float(off[0]), float(off[1]))
		if data.has("meeting_offset") and data["meeting_offset"] is Array:
			var meeting_off: Array = data["meeting_offset"]
			if meeting_off.size() >= 2:
				p.meeting_offset = Vector2(float(meeting_off[0]), float(meeting_off[1]))
		if data.has("clip_rect") and data["clip_rect"] is Array:
			var cr: Array = data["clip_rect"]
			if cr.size() >= 4:
				p.clip_rect = Rect2(float(cr[0]), float(cr[1]), float(cr[2]), float(cr[3]))
		if data.has("anchor_point") and data["anchor_point"] is Array:
			var ap: Array = data["anchor_point"]
			if ap.size() >= 2:
				p.anchor_point = Vector2(float(ap[0]), float(ap[1]))

		if data.has("layer_order") and data["layer_order"] is Array:
			for item in data["layer_order"]:
				p.layer_order.append(str(item))
		p.idle_eye_state = str(data.get("idle_eye_state", "open"))
		p.idle_mouth_key = str(data.get("idle_mouth_key", "MBP"))

		if data.has("layer_files") and data["layer_files"] is Dictionary:
			p.layer_files = data["layer_files"]

		if data.has("eye_files") and data["eye_files"] is Dictionary:
			p.eye_files = data["eye_files"]

		if data.has("mouth_files") and data["mouth_files"] is Dictionary:
			p.mouth_files = data["mouth_files"]

		if data.has("costumes") and data["costumes"] is Dictionary:
			p.costumes = data["costumes"]

		if data.has("action_files") and data["action_files"] is Dictionary:
			p.action_files = data["action_files"]

		if data.has("static_image"):
			p.static_image = str(data["static_image"])

		if data.has("static_mouth_files") and data["static_mouth_files"] is Array:
			p.static_mouth_files.clear()
			for item in data["static_mouth_files"]:
				p.static_mouth_files.append(str(item))

		return p


# ══════════════════════════════════════════
#  已加载的素材缓存
# ══════════════════════════════════════════

## 已注册的素材配置 { character_id: AssetProfile }
var _profiles: Dictionary = {}

## 已加载的纹理缓存 { character_id: CharacterTextures }
var _loaded_textures: Dictionary = {}

## 文件系统引用（用于从虚拟文件系统加载）
var _fs: FileSystem = null


# ══════════════════════════════════════════
#  已加载纹理数据结构
# ══════════════════════════════════════════

## 一个角色所有已加载的纹理
class CharacterTextures:
	extends RefCounted

	## 静态头像
	var static_portrait: ImageTexture = null

	## 分层纹理 { "head": Texture2D, "body": Texture2D, ... }
	var layer_textures: Dictionary = {}

	## 眼睛纹理 { "eye_L_open": Texture2D, ... }
	var eye_textures: Dictionary = {}

	## 嘴型纹理 { "MBP": Texture2D, ... }
	var mouth_textures: Dictionary = {}

	## 服装变体纹理 { "variant_name": { "body": Texture2D } }
	var costume_textures: Dictionary = {}

	## 动作帧纹理 { "nod": [Texture2D, ...] }
	var action_frames: Dictionary = {}

	## overlay 纹理
	var overlay_textures: Dictionary = {}


# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════

func setup(fs: FileSystem) -> void:
	_fs = fs


# ══════════════════════════════════════════
#  Profile 注册
# ══════════════════════════════════════════

## 注册角色素材配置
func register_profile(character_id: String, profile: AssetProfile) -> void:
	_profiles[character_id] = profile

## 从 Dictionary 数据注册（用于 manifest / JSON 配置）
func register_profile_from_dict(character_id: String, data: Dictionary) -> void:
	var profile := AssetProfile.from_dict(data)
	_profiles[character_id] = profile

## 注销角色素材配置
func unregister_profile(character_id: String) -> void:
	_profiles.erase(character_id)
	_loaded_textures.erase(character_id)

## 检查是否已注册
func has_profile(character_id: String) -> bool:
	return _profiles.has(character_id)

## 获取 profile
func get_profile(character_id: String) -> AssetProfile:
	return _profiles.get(character_id) as AssetProfile


# ══════════════════════════════════════════
#  素材加载
# ══════════════════════════════════════════

## 加载角色的所有素材（根据 profile 配置）
func load_character_assets(character_id: String) -> CharacterTextures:
	if _loaded_textures.has(character_id):
		return _loaded_textures[character_id]

	var profile: AssetProfile = _profiles.get(character_id) as AssetProfile
	if profile == null:
		push_warning("[CharacterAssetLibrary] 未注册的角色: %s" % character_id)
		return null

	var textures := CharacterTextures.new()
	var base: String = profile.base_dir

	match profile.mode:
		"layered":
			_load_layered_assets(base, profile, textures)
		"static":
			_load_static_assets(base, profile, textures)
		"minimal":
			pass  # 无需加载

	_loaded_textures[character_id] = textures
	return textures


## 加载分层素材
func _load_layered_assets(base: String, profile: AssetProfile, textures: CharacterTextures) -> void:
	# 基础图层
	for layer_name in profile.layer_files.keys():
		var file: String = str(profile.layer_files[layer_name])
		if file.is_empty():
			continue
		var tex: Texture2D = _load_texture(base + file)
		if tex:
			textures.layer_textures[layer_name] = tex

	# 眼睛状态
	for key in profile.eye_files.keys():
		var tex: Texture2D = _load_texture(base + str(profile.eye_files[key]))
		if tex:
			textures.eye_textures[key] = tex
			# 同时放入 layer_textures 供渲染器统一访问
			textures.layer_textures[key] = tex

	# 嘴型音素
	for key in profile.mouth_files.keys():
		var tex: Texture2D = _load_texture(base + str(profile.mouth_files[key]))
		if tex:
			textures.mouth_textures[key] = tex

	# 服装变体
	for costume_name in profile.costumes.keys():
		var costume_data: Dictionary = profile.costumes[costume_name] as Dictionary
		if costume_data == null:
			continue
		var costume_tex: Dictionary = {}
		for layer_name in costume_data.keys():
			var file = costume_data[layer_name]
			if file == null:
				costume_tex[layer_name] = null  # null = 隐藏该图层
			else:
				var tex: Texture2D = _load_texture(base + str(file))
				if tex:
					costume_tex[layer_name] = tex
		textures.costume_textures[costume_name] = costume_tex

	# 动作帧
	for action_id in profile.action_files.keys():
		var frames_list = profile.action_files[action_id]
		if not (frames_list is Array) or frames_list.is_empty():
			continue
		var loaded_frames: Array = []
		for frame_file in frames_list:
			var tex: Texture2D = _load_texture(base + str(frame_file))
			if tex:
				loaded_frames.append(tex)
		if not loaded_frames.is_empty():
			textures.action_frames[action_id] = loaded_frames

	# 加载失败则尝试静态降级
	if textures.layer_textures.is_empty():
		push_warning("[CharacterAssetLibrary] 分层素材加载失败，降级为静态模式")
		_load_static_assets(base, profile, textures)


## 加载静态素材
func _load_static_assets(base: String, profile: AssetProfile, textures: CharacterTextures) -> void:
	# 主头像
	var portrait_tex: Texture2D = _load_texture(base + profile.static_image)
	if portrait_tex and portrait_tex is ImageTexture:
		textures.static_portrait = portrait_tex as ImageTexture

	# 嘴型帧（简易 4 帧）
	var mouth_keys: Array[String] = ["closed", "half", "open", "wide"]
	for i in range(mini(profile.static_mouth_files.size(), mouth_keys.size())):
		var tex: Texture2D = _load_texture(base + profile.static_mouth_files[i])
		if tex and tex is ImageTexture:
			textures.mouth_textures[mouth_keys[i]] = tex


## 统一纹理加载：优先 res://，然后虚拟文件系统
func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null

	# 1. 尝试 res:// 路径
	if path.begins_with("res://") and ResourceLoader.exists(path):
		return load(path) as Texture2D

	# 2. 尝试虚拟文件系统
	if _fs != null:
		var normalized: String = _fs.normalize_path(path)
		var data: PackedByteArray = _fs.get_binary_data(normalized)
		if not data.is_empty():
			return _create_texture_from_buffer(data, path.get_extension().to_lower())

	return null


## 从二进制数据创建纹理
func _create_texture_from_buffer(data: PackedByteArray, ext: String) -> ImageTexture:
	var img := Image.new()
	var err: Error = ERR_FILE_UNRECOGNIZED
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
#  纹理查询
# ══════════════════════════════════════════

## 获取角色已加载的纹理
func get_textures(character_id: String) -> CharacterTextures:
	return _loaded_textures.get(character_id) as CharacterTextures

## 获取角色服装变体列表
func get_costume_names(character_id: String) -> Array[String]:
	var profile: AssetProfile = _profiles.get(character_id) as AssetProfile
	if profile == null:
		return []
	var result: Array[String] = []
	for key in profile.costumes.keys():
		result.append(str(key))
	return result

## 获取角色动作列表
func get_action_names(character_id: String) -> Array[String]:
	var textures: CharacterTextures = _loaded_textures.get(character_id) as CharacterTextures
	if textures == null:
		return []
	var result: Array[String] = []
	for key in textures.action_frames.keys():
		result.append(str(key))
	return result

## 获取角色图层顺序
func get_layer_order(character_id: String) -> Array[String]:
	var profile: AssetProfile = _profiles.get(character_id) as AssetProfile
	if profile == null:
		return []
	var result: Array[String] = []
	for item in profile.layer_order:
		result.append(item)
	return result


# ══════════════════════════════════════════
#  内置角色 Profile 工厂方法
# ══════════════════════════════════════════

func unload_character(character_id: String) -> void:
	_loaded_textures.erase(character_id)

## 清理所有
func cleanup() -> void:
	_profiles.clear()
	_loaded_textures.clear()
