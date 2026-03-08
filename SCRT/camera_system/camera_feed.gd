# ============================================================
# camera_feed.gd - 单个摄像头数据模型
# 职责：存储一个摄像头的所有配置数据（底图、深度图、照明、异常等）
# ============================================================
class_name SecurityCameraFeed
extends RefCounted

# ── 基础信息 ──
var id: String = ""                     # 唯一标识 "cam_hallway_01"
var cam_name: String = ""               # 显示名 "走廊监控 #1"
var location: String = ""               # 位置描述 "东翼走廊 B2F"
var unlocked: bool = false              # 是否已解锁
var online: bool = true                 # 是否在线

# ── 底图系统 ──
var base_image_path: String = ""        # 底图路径（相对于 data 目录）
var base_image: Image = null            # 加载后的底图缓存
var base_texture: ImageTexture = null   # 底图纹理

# ── 深度图（伪3D透视）──
var depth_map_path: String = ""         # 黑白深度图路径
var depth_map: Image = null             # 深度图缓存
var depth_texture: ImageTexture = null  # 深度图纹理

# ── 照明系统 ──
var light_mode: String = "none"         # "none" | "spotlight" | "nightvision" | "infrared"
var light_image_path: String = ""       # 照明效果替换图路径（已废弃，保留兼容）
var light_image: Image = null
var light_texture: ImageTexture = null
var light_radius: float = 0.5          # 照明范围（归一化 0-1，预渲染 spotlight 范围替换半径）
var light_falloff: float = 2.0         # 衰减指数

# ── 预渲染图片（可选，优先于 shader 后处理）──
var use_prerendered: bool = false       # 是否使用预渲染图片
var spotlight_image_path: String = ""   # 聚光灯预渲染图路径
var spotlight_image: Image = null
var spotlight_texture: ImageTexture = null
var nightvision_image_path: String = "" # 夜视预渲染图路径
var nightvision_image: Image = null
var nightvision_texture: ImageTexture = null
var infrared_image_path: String = ""    # 红外预渲染图路径
var infrared_image: Image = null
var infrared_texture: ImageTexture = null

# ── 视差贴图参数 ──
var use_parallax: bool = false          # 是否启用视差效果
var parallax_scale: float = 0.05        # 视差强度（深度偏移量）
var parallax_layers: int = 8            # 视差采样层数（越多越精细）

# ── 镜头参数 ──
var viewport_size: Vector2 = Vector2(0.3, 0.3)   # 镜头视野占底图比例
var viewport_pos: Vector2 = Vector2(0.5, 0.5)    # 镜头中心在底图上的归一化位置
var pan_speed: float = 0.008           # 方向键平移速度（归一化/帧）
var pan_bounds: Rect2 = Rect2(0.0, 0.0, 1.0, 1.0) # 镜头中心可移动的边界
var fov_min: float = 0.1              # 最小视野（最大缩放，viewport_size 下限）
var fov_max: float = 1.0              # 最大视野（最小缩放，viewport_size 上限）

# ── 效果参数 ──
var noise_intensity: float = 0.15      # 基础噪点强度
var scanline_intensity: float = 0.3    # 扫描线强度
var vignette: float = 0.4             # 暗角强度
var timestamp_visible: bool = true     # 是否显示时间戳
var signal_quality: float = 1.0        # 信号质量 0-1（越低噪点越多）
var snow_intensity: float = 0.0        # 雪花点强度

# ── 异常图列表 ──
var anomalies: Array[Dictionary] = []
# 每个 Dictionary:
# {
#   "id": String,                 # 异常唯一标识
#   "image_path": String,         # 异常底图
#   "depth_map_path": String,     # 异常独立深度图（可选，缺省用主深度图）
#   "light_image_path": String,   # 异常独立照明图（可选）
#   "trigger": String,            # "random" | "trigger" | "timed"
#   "probability": float,         # random 模式每秒触发概率
#   "duration": float,            # 异常持续时间（秒）
#   "min_interval": float,        # 最小间隔（秒）
#   "cooldown_range": [float, float], # 随机冷却范围（可选，缺省用 min_interval）
#   "effects": Array[String],     # 附带效果 ["glitch:0.4", "noise_burst:0.3"]
#   "action": String,             # 触发后执行的触发器动作串
# }

# ── 运行时状态（不保存到配置）──
var _active_anomaly: Dictionary = {}   # 当前激活的异常数据（空=正常）
var _anomaly_timer: float = 0.0        # 异常持续倒计时
var _anomaly_cooldowns: Dictionary = {} # anomaly_id → 冷却倒计时
var _anomaly_blend: float = 0.0        # 异常混合因子 0-1（过渡动画用）

# 异常的运行时纹理缓存
var _anomaly_base_tex: ImageTexture = null
var _anomaly_depth_tex: ImageTexture = null
var _anomaly_light_tex: ImageTexture = null

# ============================================================
# 从配置字典加载
# ============================================================
func load_from_dict(data: Dictionary, base_path: String) -> void:
	id = data.get("id", id)
	cam_name = data.get("name", cam_name)
	location = data.get("location", location)
	unlocked = data.get("unlocked", unlocked)
	online = data.get("online", online)

	# 路径（相对于 base_path）
	base_image_path = _resolve_path(data.get("base_image", ""), base_path)
	depth_map_path = _resolve_path(data.get("depth_map", ""), base_path)
	light_image_path = _resolve_path(data.get("light_image", ""), base_path)

	# ★ 预渲染图片路径
	use_prerendered = data.get("use_prerendered", false)
	spotlight_image_path = _resolve_path(data.get("spotlight_image", ""), base_path)
	nightvision_image_path = _resolve_path(data.get("nightvision_image", ""), base_path)
	infrared_image_path = _resolve_path(data.get("infrared_image", ""), base_path)

	# ★ 视差贴图参数
	use_parallax = data.get("use_parallax", false)
	parallax_scale = data.get("parallax_scale", parallax_scale)
	parallax_layers = data.get("parallax_layers", parallax_layers)

	# 镜头
	if data.has("viewport_size"):
		var vs = data["viewport_size"]
		if vs is Array and vs.size() >= 2:
			viewport_size = Vector2(vs[0], vs[1])
	if data.has("viewport_pos"):
		var vp = data["viewport_pos"]
		if vp is Array and vp.size() >= 2:
			viewport_pos = Vector2(vp[0], vp[1])
	pan_speed = data.get("pan_speed", pan_speed)
	if data.has("pan_bounds"):
		var pb = data["pan_bounds"]
		if pb is Array and pb.size() >= 4:
			pan_bounds = Rect2(pb[0], pb[1], pb[2] - pb[0], pb[3] - pb[1])
	fov_min = data.get("fov_min", fov_min)
	fov_max = data.get("fov_max", fov_max)

	# 照明
	light_mode = data.get("light_mode", light_mode)
	light_radius = data.get("light_radius", light_radius)
	light_falloff = data.get("light_falloff", light_falloff)

	# 效果
	noise_intensity = data.get("noise_intensity", noise_intensity)
	scanline_intensity = data.get("scanline_intensity", scanline_intensity)
	vignette = data.get("vignette", vignette)
	timestamp_visible = data.get("timestamp_visible", timestamp_visible)
	signal_quality = data.get("signal_quality", signal_quality)
	snow_intensity = data.get("snow_intensity", snow_intensity)

	# 异常图
	anomalies.clear()
	if data.has("anomalies"):
		for anom_data in data["anomalies"]:
			var anom: Dictionary = {}
			anom["id"] = anom_data.get("id", "unnamed")
			anom["image_path"] = _resolve_path(anom_data.get("image", ""), base_path)
			anom["depth_map_path"] = _resolve_path(anom_data.get("depth_map", ""), base_path)
			anom["light_image_path"] = _resolve_path(anom_data.get("light_image", ""), base_path)
			anom["trigger"] = anom_data.get("trigger", "random")
			anom["probability"] = anom_data.get("probability", 0.03)
			anom["duration"] = anom_data.get("duration", 3.0)
			anom["min_interval"] = anom_data.get("min_interval", 60.0)
			anom["effects"] = anom_data.get("effects", [])
			anom["action"] = anom_data.get("action", "")
			anom["overlay_mode"] = anom_data.get("overlay", false)
			anomalies.append(anom)

func _resolve_path(rel_path: String, base: String) -> String:
	if rel_path.is_empty():
		return ""
	if rel_path.begins_with("res://") or rel_path.begins_with("/"):
		return rel_path
	if not base.ends_with("/"):
		base += "/"
	return base + rel_path

# ============================================================
# 纹理加载
# ============================================================
func load_textures(loader_func: Callable) -> void:
	# loader_func 接受路径，返回 Image（由 CameraManager 提供，支持 ZIP/本地）
	if not base_image_path.is_empty() and base_image == null:
		base_image = loader_func.call(base_image_path)
		if base_image:
			base_texture = ImageTexture.create_from_image(base_image)
	if not depth_map_path.is_empty() and depth_map == null:
		depth_map = loader_func.call(depth_map_path)
		if depth_map:
			depth_texture = ImageTexture.create_from_image(depth_map)
	if not light_image_path.is_empty() and light_image == null:
		light_image = loader_func.call(light_image_path)
		if light_image:
			light_texture = ImageTexture.create_from_image(light_image)

	# ★ 加载预渲染图片
	if use_prerendered:
		if not spotlight_image_path.is_empty() and spotlight_image == null:
			spotlight_image = loader_func.call(spotlight_image_path)
			if spotlight_image:
				spotlight_texture = ImageTexture.create_from_image(spotlight_image)
		if not nightvision_image_path.is_empty() and nightvision_image == null:
			nightvision_image = loader_func.call(nightvision_image_path)
			if nightvision_image:
				nightvision_texture = ImageTexture.create_from_image(nightvision_image)
		if not infrared_image_path.is_empty() and infrared_image == null:
			infrared_image = loader_func.call(infrared_image_path)
			if infrared_image:
				infrared_texture = ImageTexture.create_from_image(infrared_image)

func load_anomaly_textures(anomaly_id: String, loader_func: Callable) -> void:
	for anom in anomalies:
		if anom["id"] == anomaly_id:
			if not anom["image_path"].is_empty():
				var img: Image = loader_func.call(anom["image_path"])
				if img:
					_anomaly_base_tex = ImageTexture.create_from_image(img)
			if not anom["depth_map_path"].is_empty():
				var img2: Image = loader_func.call(anom["depth_map_path"])
				if img2:
					_anomaly_depth_tex = ImageTexture.create_from_image(img2)
			else:
				_anomaly_depth_tex = depth_texture  # 复用主深度图
			if not anom["light_image_path"].is_empty():
				var img3: Image = loader_func.call(anom["light_image_path"])
				if img3:
					_anomaly_light_tex = ImageTexture.create_from_image(img3)
			else:
				_anomaly_light_tex = light_texture  # 复用主照明图
			break

# ============================================================
# 异常系统运行时
# ============================================================
func is_anomaly_active() -> bool:
	return not _active_anomaly.is_empty()

func get_active_anomaly_id() -> String:
	return _active_anomaly.get("id", "")

func start_anomaly(anomaly_id: String) -> Dictionary:
	for anom in anomalies:
		if anom["id"] == anomaly_id:
			_active_anomaly = anom
			_anomaly_timer = anom.get("duration", 3.0)
			_anomaly_blend = 0.0
			return anom
	return {}

func end_anomaly() -> void:
	if not _active_anomaly.is_empty():
		var anom_id: String = _active_anomaly.get("id", "")
		_active_anomaly = {}
		_anomaly_timer = 0.0
		_anomaly_blend = 0.0
		_anomaly_base_tex = null
		_anomaly_depth_tex = null
		_anomaly_light_tex = null
		# 设置冷却
		for anom in anomalies:
			if anom["id"] == anom_id:
				_anomaly_cooldowns[anom_id] = anom.get("min_interval", 60.0)
				break

func update_anomaly(delta: float) -> bool:
	# 更新冷却计时
	var finished_cooldowns: Array[String] = []
	for anom_id in _anomaly_cooldowns:
		_anomaly_cooldowns[anom_id] -= delta
		if _anomaly_cooldowns[anom_id] <= 0.0:
			finished_cooldowns.append(anom_id)
	for fc in finished_cooldowns:
		_anomaly_cooldowns.erase(fc)

	# 更新异常混合（渐入渐出）
	if is_anomaly_active():
		_anomaly_blend = minf(_anomaly_blend + delta * 4.0, 1.0)
		_anomaly_timer -= delta
		if _anomaly_timer <= 0.0:
			end_anomaly()
			return true  # 异常刚结束
	else:
		_anomaly_blend = maxf(_anomaly_blend - delta * 4.0, 0.0)
	return false

func can_trigger_anomaly(anomaly_id: String) -> bool:
	if is_anomaly_active():
		return false
	return not _anomaly_cooldowns.has(anomaly_id)

# ============================================================
# 镜头操作（平移模式）
# ============================================================
func pan(direction: Vector2) -> void:
	viewport_pos += direction * pan_speed
	viewport_pos.x = clampf(viewport_pos.x, pan_bounds.position.x + viewport_size.x * 0.5,
		pan_bounds.end.x - viewport_size.x * 0.5)
	viewport_pos.y = clampf(viewport_pos.y, pan_bounds.position.y + viewport_size.y * 0.5,
		pan_bounds.end.y - viewport_size.y * 0.5)

func get_viewport_rect() -> Rect2:
	# 返回当前镜头在底图上的归一化矩形
	var half: Vector2 = viewport_size * 0.5
	return Rect2(viewport_pos - half, viewport_size)

# ============================================================
# 清理
# ============================================================
func unload_textures() -> void:
	base_image = null
	base_texture = null
	depth_map = null
	depth_texture = null
	light_image = null
	light_texture = null
	_anomaly_base_tex = null
	_anomaly_depth_tex = null
	_anomaly_light_tex = null
	_active_anomaly = {}
	_anomaly_timer = 0.0
	_anomaly_cooldowns.clear()
