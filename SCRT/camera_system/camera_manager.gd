# ============================================================
# camera_manager.gd - 监控摄像头管理器
# 职责：
#   - 从 manifest 加载摄像头配置
#   - 管理摄像头解锁、上下线状态
#   - 驱动异常图的随机/定时触发
#   - 提供存档/读档接口
# ============================================================
class_name CameraManager
extends RefCounted

var main = null
var fs = null
var T = null

var _cameras: Dictionary = {}           # id → CameraFeed
var _camera_order: Array[String] = []   # 有序的摄像头ID列表（按配置顺序）
var _anomaly_check_timer: float = 0.0   # 异常检查间隔计时
const ANOMALY_CHECK_INTERVAL: float = 1.0  # 每秒检查一次随机异常

signal camera_unlocked(camera_id: String)
signal camera_locked(camera_id: String)
signal camera_anomaly_started(camera_id: String, anomaly_id: String)
signal camera_anomaly_ended(camera_id: String)
signal camera_status_changed(camera_id: String, online: bool)

# ============================================================
# 初始化
# ============================================================
func setup(p_main) -> void:
	main = p_main
	if main:
		fs = main.fs
		T = ThemeManager.current

# ============================================================
# 从 manifest 加载摄像头配置
# ============================================================
func load_from_manifest(manifest: Dictionary) -> void:
	reset()
	if not manifest.has("camera_system"):
		return
	var cam_sys: Dictionary = manifest["camera_system"] as Dictionary
	if not cam_sys.has("cameras"):
		return

	var cameras_dict: Dictionary = cam_sys["cameras"] as Dictionary
	var defaults: Dictionary = cam_sys.get("defaults", {}) as Dictionary

	for cam_id in cameras_dict.keys():
		var cam_data: Dictionary = cameras_dict[cam_id] as Dictionary
		cam_data["id"] = cam_id

		# 合并默认值（摄像头配置覆盖全局默认值）
		var merged: Dictionary = defaults.duplicate(true)
		for key in cam_data.keys():
			merged[key] = cam_data[key]

		var feed := CameraFeed.new()
		# 图片路径相对于 cameras/ 目录
		var base_path: String = str(cam_sys.get("base_path", "cameras"))
		feed.load_from_dict(merged, base_path)

		_cameras[cam_id] = feed
		_camera_order.append(cam_id)

	print("[CameraManager] 已加载 %d 个摄像头" % _cameras.size())

# ============================================================
# 摄像头查询
# ============================================================
func get_camera(id: String) -> CameraFeed:
	return _cameras.get(id, null)

func get_all_cameras() -> Array[CameraFeed]:
	var result: Array[CameraFeed] = []
	for cam_id in _camera_order:
		if _cameras.has(cam_id):
			result.append(_cameras[cam_id])
	return result

func get_unlocked_cameras() -> Array[CameraFeed]:
	var result: Array[CameraFeed] = []
	for cam_id in _camera_order:
		if _cameras.has(cam_id):
			var cam: CameraFeed = _cameras[cam_id]
			if cam.unlocked:
				result.append(cam)
	return result

func get_camera_count() -> int:
	return _cameras.size()

func get_unlocked_count() -> int:
	var count: int = 0
	for cam_id in _camera_order:
		if _cameras.has(cam_id) and _cameras[cam_id].unlocked:
			count += 1
	return count

func has_cameras() -> bool:
	return not _cameras.is_empty()

# ============================================================
# 状态控制
# ============================================================
func unlock_camera(id: String) -> void:
	var cam: CameraFeed = get_camera(id)
	if cam and not cam.unlocked:
		cam.unlocked = true
		camera_unlocked.emit(id)
		print("[CameraManager] 摄像头已解锁: %s (%s)" % [id, cam.cam_name])

func lock_camera(id: String) -> void:
	var cam: CameraFeed = get_camera(id)
	if cam and cam.unlocked:
		cam.unlocked = false
		camera_locked.emit(id)
		print("[CameraManager] 摄像头已锁定: %s" % id)

func set_camera_online(id: String, online: bool) -> void:
	var cam: CameraFeed = get_camera(id)
	if cam and cam.online != online:
		cam.online = online
		camera_status_changed.emit(id, online)
		var status: String = "上线" if online else "离线"
		print("[CameraManager] 摄像头%s: %s" % [status, id])

func set_signal_quality(id: String, quality: float) -> void:
	var cam: CameraFeed = get_camera(id)
	if cam:
		cam.signal_quality = clampf(quality, 0.0, 1.0)

# ============================================================
# 异常系统
# ============================================================
func trigger_anomaly(camera_id: String, anomaly_id: String) -> void:
	var cam: CameraFeed = get_camera(camera_id)
	if cam == null:
		print("[CameraManager] 摄像头不存在: %s" % camera_id)
		return
	if not cam.can_trigger_anomaly(anomaly_id):
		return

	# ★ 效果安全等级检查：OFF 模式下不触发异常视觉
	var effect_blocked: bool = false
	if main and main.effect_settings:
		if not main.effect_settings.is_effect_allowed("jumpscare"):
			effect_blocked = true

	# 加载异常纹理（即使视觉被阻止，仍然需要触发逻辑动作）
	if not effect_blocked:
		cam.load_anomaly_textures(anomaly_id, _load_image_func())

	var anom: Dictionary = cam.start_anomaly(anomaly_id)
	if anom.is_empty():
		print("[CameraManager] 异常不存在: %s/%s" % [camera_id, anomaly_id])
		return

	camera_anomaly_started.emit(camera_id, anomaly_id)
	print("[CameraManager] 异常触发: %s/%s" % [camera_id, anomaly_id])

	# 执行附带效果（受 effect_settings 衰减）
	if not effect_blocked:
		_execute_anomaly_effects(anom)
	# 触发器动作始终执行（剧情推进不受效果等级影响）
	_execute_anomaly_action(anom)

func _execute_anomaly_effects(anom: Dictionary) -> void:
	if not main:
		return
	var effects: Array = anom.get("effects", [])
	for effect_str in effects:
		var parts: PackedStringArray = str(effect_str).split(":")
		var effect_name: String = parts[0].to_lower()
		var intensity: float = float(parts[1]) if parts.size() > 1 else 0.5
		match effect_name:
			"glitch":
				if main.has_method("apply_glitch"):
					main.apply_glitch(intensity, 0.5)
			"noise_burst":
				if main.has_method("apply_noise_burst"):
					main.apply_noise_burst(intensity, 0.3)
			"shake":
				if main.has_method("apply_shake"):
					main.apply_shake(intensity, 0.5)

func _execute_anomaly_action(anom: Dictionary) -> void:
	var action: String = anom.get("action", "")
	if action.is_empty() or not main:
		return
	if main.trigger_sys and main.trigger_sys.has_method("execute"):
		main.trigger_sys.execute(action)

# ============================================================
# 每帧处理（检查随机异常 + 更新异常计时器）
# ============================================================
func process(delta: float) -> void:
	# 更新所有摄像头的异常计时
	for cam_id in _cameras:
		var cam: CameraFeed = _cameras[cam_id]
		var just_ended: bool = cam.update_anomaly(delta)
		if just_ended:
			camera_anomaly_ended.emit(cam_id)

	# 定期检查随机异常
	_anomaly_check_timer += delta
	if _anomaly_check_timer >= ANOMALY_CHECK_INTERVAL:
		_anomaly_check_timer = 0.0
		_check_random_anomalies()

func _check_random_anomalies() -> void:
	for cam_id in _cameras:
		var cam: CameraFeed = _cameras[cam_id]
		if not cam.unlocked or not cam.online:
			continue
		if cam.is_anomaly_active():
			continue

		for anom in cam.anomalies:
			if anom.get("trigger", "") != "random":
				continue
			if not cam.can_trigger_anomaly(anom["id"]):
				continue
			var prob: float = anom.get("probability", 0.03)
			if randf() < prob:
				trigger_anomaly(cam_id, anom["id"])
				break  # 每个摄像头每次只触发一个异常

# ============================================================
# 图片加载
# ============================================================
func load_camera_textures(camera_id: String) -> void:
	var cam: CameraFeed = get_camera(camera_id)
	if cam:
		cam.load_textures(_load_image_func())

func _load_image_func() -> Callable:
	return func(path: String) -> Image:
		return _load_image(path)

func _load_image(path: String) -> Image:
	if path.is_empty():
		return null

	# 1. 先尝试从虚拟文件系统加载（ZIP 内的文件）
	if fs and fs.file_system is Dictionary:
		# 尝试多种路径格式
		var try_paths: Array[String] = [path]
		if not path.begins_with("/"):
			try_paths.append("/" + path)
		for try_path in try_paths:
			if fs.file_system.has(try_path):
				var file_data: Dictionary = fs.file_system[try_path]
				if file_data.has("binary"):
					return _image_from_bytes(try_path, file_data["binary"])

	# 2. 尝试从本地文件系统加载
	var local_paths: Array[String] = []
	if path.begins_with("res://"):
		local_paths.append(path)
	else:
		# 相对于数据目录
		if main and main.has_method("get_data_dir"):
			local_paths.append(main.get_data_dir() + "/" + path)
		# 相对于项目根目录
		if OS.has_feature("editor"):
			local_paths.append(ProjectSettings.globalize_path("res://") + path)
		else:
			local_paths.append(OS.get_executable_path().get_base_dir() + "/" + path)

	for local_path in local_paths:
		if FileAccess.file_exists(local_path):
			var img := Image.new()
			var err: Error = img.load(local_path)
			if err == OK:
				return img

	print("[CameraManager] 无法加载图片: %s" % path)
	return null

func _image_from_bytes(file_path: String, data: PackedByteArray) -> Image:
	if data.is_empty():
		return null
	var img := Image.new()
	var ext: String = file_path.get_extension().to_lower()
	var err: Error = ERR_FILE_UNRECOGNIZED
	match ext:
		"png":
			err = img.load_png_from_buffer(data)
		"jpg", "jpeg":
			err = img.load_jpg_from_buffer(data)
		"bmp":
			err = img.load_bmp_from_buffer(data)
		"webp":
			err = img.load_webp_from_buffer(data)
		"tga":
			err = img.load_tga_from_buffer(data)
	if err == OK:
		return img
	return null

# ============================================================
# 存档系统
# ============================================================
func get_save_data() -> Dictionary:
	var data: Dictionary = {}
	var unlocked_ids: Array[String] = []
	var online_states: Dictionary = {}
	var signal_qualities: Dictionary = {}
	var viewport_positions: Dictionary = {}
	var cooldowns: Dictionary = {}

	for cam_id in _camera_order:
		var cam: CameraFeed = _cameras[cam_id]
		if cam.unlocked:
			unlocked_ids.append(cam_id)
		if not cam.online:
			online_states[cam_id] = false
		if cam.signal_quality != 1.0:
			signal_qualities[cam_id] = cam.signal_quality
		# 保存镜头位置
		viewport_positions[cam_id] = [cam.viewport_pos.x, cam.viewport_pos.y]
		# 保存冷却状态
		if not cam._anomaly_cooldowns.is_empty():
			cooldowns[cam_id] = cam._anomaly_cooldowns.duplicate()

	data["unlocked"] = unlocked_ids
	data["online_states"] = online_states
	data["signal_qualities"] = signal_qualities
	data["viewport_positions"] = viewport_positions
	data["cooldowns"] = cooldowns
	return data

func load_save_data(data: Dictionary) -> void:
	if data.is_empty():
		return

	# 恢复解锁状态
	if data.has("unlocked"):
		for cam_id in data["unlocked"]:
			var cam: CameraFeed = get_camera(str(cam_id))
			if cam:
				cam.unlocked = true

	# 恢复在线状态
	if data.has("online_states"):
		for cam_id in data["online_states"]:
			var cam: CameraFeed = get_camera(str(cam_id))
			if cam:
				cam.online = data["online_states"][cam_id]

	# 恢复信号质量
	if data.has("signal_qualities"):
		for cam_id in data["signal_qualities"]:
			var cam: CameraFeed = get_camera(str(cam_id))
			if cam:
				cam.signal_quality = float(data["signal_qualities"][cam_id])

	# 恢复镜头位置
	if data.has("viewport_positions"):
		for cam_id in data["viewport_positions"]:
			var cam: CameraFeed = get_camera(str(cam_id))
			if cam:
				var pos = data["viewport_positions"][cam_id]
				if pos is Array and pos.size() >= 2:
					cam.viewport_pos = Vector2(pos[0], pos[1])

	# 恢复冷却
	if data.has("cooldowns"):
		for cam_id in data["cooldowns"]:
			var cam: CameraFeed = get_camera(str(cam_id))
			if cam and data["cooldowns"][cam_id] is Dictionary:
				cam._anomaly_cooldowns = data["cooldowns"][cam_id].duplicate()

# ============================================================
# 重置
# ============================================================
func reset() -> void:
	for cam_id in _cameras:
		_cameras[cam_id].unload_textures()
	_cameras.clear()
	_camera_order.clear()
	_anomaly_check_timer = 0.0
