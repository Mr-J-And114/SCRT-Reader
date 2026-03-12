# ============================================================
# character_registry.gd — 角色注册中心
# 统一管理角色的创建、注册、查询和生命周期
# 支持内置角色、磁盘角色、模组角色三种来源
# ============================================================
class_name CharacterRegistry
extends RefCounted

# ══════════════════════════════════════════
#  角色来源标识
# ══════════════════════════════════════════
enum CharacterSource {
	BUILTIN,   ## 内置角色（教程、系统）
	DISC,      ## 磁盘/故事包角色
	MOD,       ## 模组注册角色
}

# ══════════════════════════════════════════
#  内部数据
# ══════════════════════════════════════════

## 所有已注册角色 { character_id: CommCharacter }
var _characters: Dictionary = {}

## 角色来源追踪 { character_id: CharacterSource }
var _sources: Dictionary = {}

## 素材库
var _asset_library: CharacterAssetLibrary = null

## 文件系统引用
var _fs: FileSystem = null

## main 引用
var _main = null

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════

func setup(main, fs: FileSystem) -> void:
	_main = main
	_fs = fs
	_asset_library = CharacterAssetLibrary.new()
	_asset_library.setup(fs)

## 获取素材库
func get_asset_library() -> CharacterAssetLibrary:
	return _asset_library

# ══════════════════════════════════════════
#  角色注册
# ══════════════════════════════════════════

## 从配置创建并注册角色
func register_character(char_id: String, config: Dictionary,
		source: CharacterSource = CharacterSource.BUILTIN) -> CommCharacter:
	config["id"] = char_id
	var character := CommCharacter.new()
	character.load_from_config(config, _fs)

	# 如果素材库中有该角色的 profile，使用新路径加载
	if _asset_library.has_profile(char_id):
		character.init_from_asset_library(_asset_library)

	_characters[char_id] = character
	_sources[char_id] = source
	print("[CharacterRegistry] 注册角色: %s (%s) [%s]" % [
		char_id, character.display_name, CharacterSource.keys()[source]
	])
	return character

## 注册已创建的角色实例
func register_existing(character: CommCharacter,
		source: CharacterSource = CharacterSource.BUILTIN) -> void:
	_characters[character.id] = character
	_sources[character.id] = source

## 注销角色
func unregister_character(char_id: String) -> void:
	_characters.erase(char_id)
	_sources.erase(char_id)
	_asset_library.unregister_profile(char_id)
	_asset_library.unload_character(char_id)

# ══════════════════════════════════════════
#  内置角色初始化
# ══════════════════════════════════════════

## 注册内置 AVA 角色的素材 profile 并加载
func setup_ava() -> void:
	var profile: CharacterAssetLibrary.AssetProfile = CharacterAssetLibrary.create_ava_profile()
	_asset_library.register_profile("ava", profile)
	# 如果角色已注册，重新加载素材
	if _characters.has("ava"):
		var ch: CommCharacter = _characters["ava"]
		ch.init_from_asset_library(_asset_library)
		print("[CharacterRegistry] AVA 分层头像已加载 (%d layers, %d mouth shapes)" % [
			ch.layer_textures.size(), ch.mouth_textures.size()
		])

## 注册内置 Researcher 角色的素材 profile 并加载
func setup_researcher() -> void:
	var profile: CharacterAssetLibrary.AssetProfile = CharacterAssetLibrary.create_researcher_profile()
	_asset_library.register_profile("researcher", profile)
	if _characters.has("researcher"):
		var ch: CommCharacter = _characters["researcher"]
		ch.init_from_asset_library(_asset_library)
		print("[CharacterRegistry] Researcher 头像已加载")

## 创建默认角色 OP7
func create_default_character() -> CommCharacter:
	var config: Dictionary = {
		"id": "op7",
		"name": "OPERATOR-7",
		"title": "Liaison Officer",
		"sprite_mode": "minimal",
		"default_expression": "neutral",
		"voice": {
			"tone": "square",
			"base_pitch": 0.9,
			"pitch_variance": 0.12,
			"speed": "normal",
		}
	}
	return register_character("op7", config, CharacterSource.BUILTIN)

# ══════════════════════════════════════════
#  磁盘角色管理
# ══════════════════════════════════════════

## 从磁盘 manifest 加载角色
func load_disc_characters(chars_data: Dictionary) -> Array[String]:
	var loaded_ids: Array[String] = []
	for char_id in chars_data.keys():
		var char_dict: Dictionary = chars_data[char_id] as Dictionary

		# 如果 manifest 包含 asset_profile，注册到素材库
		if char_dict.has("asset_profile") and char_dict["asset_profile"] is Dictionary:
			_asset_library.register_profile_from_dict(char_id, char_dict["asset_profile"])

		var character: CommCharacter = register_character(
			char_id, char_dict, CharacterSource.DISC
		)

		# 如果角色有头像路径但没有用 asset_library 加载，尝试旧路径
		if character.sprite_mode == CommCharacter.SpriteMode.MINIMAL or \
				(character.sprite_mode == CommCharacter.SpriteMode.STATIC and character.static_portrait == null):
			_load_character_portrait_legacy(character, char_dict)

		loaded_ids.append(char_id)
		print("[CharacterRegistry] 磁盘角色已加载: %s" % char_id)
	return loaded_ids

## 卸载指定来源的所有角色
func unload_by_source(source: CharacterSource) -> void:
	var to_remove: Array[String] = []
	for char_id in _sources.keys():
		if _sources[char_id] == source:
			to_remove.append(char_id)
	for char_id in to_remove:
		unregister_character(char_id)
	print("[CharacterRegistry] 已卸载 %d 个 %s 角色" % [
		to_remove.size(), CharacterSource.keys()[source]
	])

## 旧路径加载头像（兼容不使用 asset_profile 的磁盘角色）
func _load_character_portrait_legacy(character: CommCharacter, char_dict: Dictionary) -> void:
	var portrait_path: String = str(char_dict.get("portrait", ""))
	if portrait_path.is_empty():
		return

	# 尝试从虚拟文件系统加载
	if _main and _main.fs:
		var normalized: String = _main.fs.normalize_path(portrait_path)
		var binary: PackedByteArray = _main.fs.get_binary_data(normalized)
		if not binary.is_empty():
			var img := Image.new()
			var ext: String = portrait_path.get_extension().to_lower()
			var err: Error = ERR_FILE_UNRECOGNIZED
			match ext:
				"png":
					err = img.load_png_from_buffer(binary)
				"jpg", "jpeg":
					err = img.load_jpg_from_buffer(binary)
				"webp":
					err = img.load_webp_from_buffer(binary)
			if err == OK:
				character.static_portrait = ImageTexture.create_from_image(img)
				character.sprite_mode = CommCharacter.SpriteMode.STATIC
				print("[CharacterRegistry] 磁盘角色头像已加载: %s" % character.id)
				return

	# 尝试从 res:// 路径加载
	if portrait_path.begins_with("res://") and ResourceLoader.exists(portrait_path):
		var tex = load(portrait_path)
		if tex is Texture2D:
			var img: Image = tex.get_image()
			if img:
				character.static_portrait = ImageTexture.create_from_image(img)
			character.sprite_mode = CommCharacter.SpriteMode.STATIC
			print("[CharacterRegistry] 角色头像已加载(res): %s" % character.id)

# ══════════════════════════════════════════
#  模组角色管理
# ══════════════════════════════════════════

## 模组注册角色
func register_mod_character(char_id: String, config: Dictionary) -> bool:
	if _characters.has(char_id):
		push_warning("[CharacterRegistry] 角色已存在: %s" % char_id)
		return false

	# 模组可提供 asset_profile 来定义分层素材
	if config.has("asset_profile") and config["asset_profile"] is Dictionary:
		_asset_library.register_profile_from_dict(char_id, config["asset_profile"])

	register_character(char_id, config, CharacterSource.MOD)
	return true

## 模组注销角色
func unregister_mod_character(char_id: String) -> void:
	if _sources.get(char_id) == CharacterSource.MOD:
		unregister_character(char_id)

## 模组为已有角色注册素材 profile（如为内置角色添加服装）
func register_mod_asset_profile(char_id: String, profile_data: Dictionary) -> void:
	_asset_library.register_profile_from_dict(char_id, profile_data)
	if _characters.has(char_id):
		_characters[char_id].init_from_asset_library(_asset_library)

# ══════════════════════════════════════════
#  分层角色快速设置（向后兼容）
# ══════════════════════════════════════════

## 通用分层角色设置（供旧代码调用）
func setup_layered_character(char_id: String, sprite_dir: String, config: Dictionary) -> void:
	if not _characters.has(char_id):
		push_warning("[CharacterRegistry] 角色不存在: %s" % char_id)
		return
	var ch: CommCharacter = _characters[char_id]
	ch.sprite_mode = CommCharacter.SpriteMode.LAYERED
	ch.sprite_dir = sprite_dir
	ch.layer_config = config
	ch._load_layered_sprites({}, null)
	print("[CharacterRegistry] %s 分层头像已加载 (%d layers, %d mouth shapes)" % [
		char_id, ch.layer_textures.size(), ch.mouth_textures.size()
	])

# ══════════════════════════════════════════
#  查询接口
# ══════════════════════════════════════════

## 获取角色
func get_character(char_id: String) -> CommCharacter:
	return _characters.get(char_id) as CommCharacter

## 检查角色是否存在
func has_character(char_id: String) -> bool:
	return _characters.has(char_id)

## 获取所有角色 ID
func get_character_ids() -> Array[String]:
	var result: Array[String] = []
	for key in _characters.keys():
		result.append(str(key))
	return result

## 获取指定来源的角色 ID
func get_character_ids_by_source(source: CharacterSource) -> Array[String]:
	var result: Array[String] = []
	for char_id in _sources.keys():
		if _sources[char_id] == source:
			result.append(char_id)
	return result

## 获取所有角色（Dictionary）
func get_all_characters() -> Dictionary:
	return _characters

## 角色数量
func size() -> int:
	return _characters.size()

## 是否为空
func is_empty() -> bool:
	return _characters.is_empty()

# ══════════════════════════════════════════
#  清理
# ══════════════════════════════════════════

func cleanup() -> void:
	_characters.clear()
	_sources.clear()
	if _asset_library:
		_asset_library.cleanup()
