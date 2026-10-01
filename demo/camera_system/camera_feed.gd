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

# ── Region-Based Depth ──
# 原始配置
var region_config: Dictionary = {}

# 三种深度来源（解析后）
var polygon_regions: Array[Dictionary] = []
var mask_regions: Array[Dictionary] = []
var layers: Array[Dictionary] = []

# 全局参数
var global_default_distance: float = 0.3
var smooth_radius: float = 0.02
var use_raw_depth_fallback: bool = true
var variation_scale: float = 0.3
var mask_feather_radius: float = 3.0

# 运行时纹理
var region_depth_image: Image = null
var region_depth_texture: ImageTexture = null
var use_region_depth: bool = false

# Absorption map
var absorption_image: Image = null
var absorption_texture: ImageTexture = null

# 合成底图（当有 layers 时使用）
var composite_base_image: Image = null
var composite_base_texture: ImageTexture = null

# 脏标记
var _region_dirty: bool = false

# 缓存
var _mask_textures: Dictionary = {}
var _layer_base_images: Dictionary = {}
var _layer_depth_images: Dictionary = {}

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

	# ── Region Depth Config ──
	polygon_regions.clear()
	mask_regions.clear()
	layers.clear()
	_region_dirty = false

	region_config = data.get("region_config", {})
	if not region_config.is_empty():
		use_region_depth = true
		global_default_distance = region_config.get("global_default_distance", 0.3)
		smooth_radius = region_config.get("smooth_radius", 0.02)
		use_raw_depth_fallback = region_config.get("use_raw_depth_fallback", true)
		variation_scale = region_config.get("variation_scale", 0.3)
		mask_feather_radius = region_config.get("mask_feather_radius", 3.0)

		# 解析 polygons
		for r_data in region_config.get("polygons", []):
			var r: Dictionary = {}
			r["id"] = r_data.get("id", "poly_%d" % polygon_regions.size())
			r["label"] = r_data.get("label", "")
			r["ref_distance"] = r_data.get("ref_distance", 0.5)
			r["points"] = r_data.get("points", [])
			r["light_absorption"] = r_data.get("light_absorption", 0.5)
			polygon_regions.append(r)

		# 解析 masks
		for m_data in region_config.get("masks", []):
			var m: Dictionary = {}
			m["id"] = m_data.get("id", "mask_%d" % mask_regions.size())
			m["label"] = m_data.get("label", "")
			m["image"] = _resolve_path(m_data.get("image", ""), base_path)
			m["ref_distance"] = m_data.get("ref_distance", 0.5)
			m["real_distance"] = m_data.get("real_distance", null)
			m["priority"] = m_data.get("priority", 0)
			m["light_absorption"] = m_data.get("light_absorption", 0.5)
			mask_regions.append(m)

		# 解析 layers
		for l_data in region_config.get("layers", []):
			var l: Dictionary = {}
			l["id"] = l_data.get("id", "layer_%d" % layers.size())
			l["label"] = l_data.get("label", "")
			l["base_image"] = _resolve_path(l_data.get("base_image", ""), base_path)
			l["depth_map"] = _resolve_path(l_data.get("depth_map", ""), base_path)
			l["z_offset"] = l_data.get("z_offset", 0.0)
			l["real_distance"] = l_data.get("real_distance", null)
			layers.append(l)

		# 按 z_offset 排序（从远到近）
		layers.sort_custom(_compare_z_offset)

		_region_dirty = true

func _resolve_path(rel_path: String, base: String) -> String:
	if rel_path.is_empty():
		return ""
	if rel_path.begins_with("res://") or rel_path.begins_with("/"):
		return rel_path
	if not base.ends_with("/"):
		base += "/"
	return base + rel_path

func _compare_z_offset(a: Dictionary, b: Dictionary) -> bool:
	return a["z_offset"] < b["z_offset"]

func _compare_mask_priority(a: Dictionary, b: Dictionary) -> bool:
	return a.get("priority", 0) < b.get("priority", 0)

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

	# ★ 加载 Region Depth 纹理
	if _region_dirty and use_region_depth:
		_mask_textures.clear()
		for m in mask_regions:
			var path: String = m.get("image", "")
			if not path.is_empty():
				var img: Image = loader_func.call(path)
				if img:
					_mask_textures[m["id"]] = img

		_layer_base_images.clear()
		_layer_depth_images.clear()
		for l in layers:
			var base_path: String = l.get("base_image", "")
			var depth_path: String = l.get("depth_map", "")
			if not base_path.is_empty():
				var img: Image = loader_func.call(base_path)
				if img:
					_layer_base_images[l["id"]] = img
			if not depth_path.is_empty():
				var img: Image = loader_func.call(depth_path)
				if img:
					_layer_depth_images[l["id"]] = img

		build_region_depth_map()

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
	# Region depth cleanup — 只清除纹理缓存，保留配置元数据供重新加载
	region_depth_image = null
	region_depth_texture = null
	absorption_image = null
	absorption_texture = null
	composite_base_image = null
	composite_base_texture = null
	_mask_textures.clear()
	_layer_base_images.clear()
	_layer_depth_images.clear()
	_region_dirty = true
	# ★ 不清除 polygon_regions/mask_regions/layers/region_config
	# 这些是轻量 JSON 元数据，下次 load_textures() 需要用它们重新加载 mask/layer 图片

# ============================================================
# Region-Based Depth — 运行时合成管线（字节数组优化 + 覆盖掩码）
# ============================================================

func _rasterize_polygon_float(arr: PackedFloat32Array, coverage: PackedByteArray,
		pts: Array, val: float, w: int, h: int) -> void:
	if pts.size() < 3:
		return

	var px_pts: Array[Vector2] = []
	for v in pts:
		var p: Array = v if v is Array else [v.x, v.y]
		if p.size() >= 2:
			px_pts.append(Vector2(float(p[0]) * float(w - 1), float(p[1]) * float(h - 1)))

	var n: int = px_pts.size()
	if n < 3:
		return

	var y_min_f: float = INF
	var y_max_f: float = -INF
	for i in range(n):
		y_min_f = minf(y_min_f, px_pts[i].y)
		y_max_f = maxf(y_max_f, px_pts[i].y)
	var y_min: int = clampi(int(round(y_min_f)), 0, h - 1)
	var y_max: int = clampi(int(round(y_max_f)), 0, h - 1)

	for y in range(y_min, y_max + 1):
		var xs: Array[float] = []
		for i in range(n):
			var j: int = (i + 1) % n
			var yi: float = px_pts[i].y
			var yj: float = px_pts[j].y
			if (yi <= float(y) and yj > float(y)) or (yj <= float(y) and yi > float(y)):
				var t: float = (float(y) - yi) / (yj - yi)
				xs.append(px_pts[i].x + t * (px_pts[j].x - px_pts[i].x))

		xs.sort()

		var m: int = xs.size() / 2 * 2
		var k: int = 0
		while k < m:
			var x_start: int = maxi(0, int(ceil(xs[k])))
			var x_end: int = mini(w - 1, int(floor(xs[k + 1])))
			var row_offset: int = y * w
			for x in range(x_start, x_end + 1):
				var idx: int = row_offset + x
				arr[idx] = val
				coverage[idx] = 255
			k += 2

func _rasterize_polygon_bytes(arr: PackedByteArray, coverage: PackedByteArray,
		pts: Array, val: int, w: int, h: int) -> void:
	if pts.size() < 3:
		return

	var px_pts: Array[Vector2] = []
	for v in pts:
		var p: Array = v if v is Array else [v.x, v.y]
		if p.size() >= 2:
			px_pts.append(Vector2(float(p[0]) * float(w - 1), float(p[1]) * float(h - 1)))

	var n: int = px_pts.size()
	if n < 3:
		return

	var y_min_f: float = INF
	var y_max_f: float = -INF
	for i in range(n):
		y_min_f = minf(y_min_f, px_pts[i].y)
		y_max_f = maxf(y_max_f, px_pts[i].y)
	var y_min: int = clampi(int(round(y_min_f)), 0, h - 1)
	var y_max: int = clampi(int(round(y_max_f)), 0, h - 1)

	for y in range(y_min, y_max + 1):
		var xs: Array[float] = []
		for i in range(n):
			var j: int = (i + 1) % n
			var yi: float = px_pts[i].y
			var yj: float = px_pts[j].y
			if (yi <= float(y) and yj > float(y)) or (yj <= float(y) and yi > float(y)):
				var t: float = (float(y) - yi) / (yj - yi)
				xs.append(px_pts[i].x + t * (px_pts[j].x - px_pts[i].x))

		xs.sort()

		var m: int = xs.size() / 2 * 2
		var k: int = 0
		while k < m:
			var x_start: int = maxi(0, int(ceil(xs[k])))
			var x_end: int = mini(w - 1, int(floor(xs[k + 1])))
			var row_offset: int = y * w
			for x in range(x_start, x_end + 1):
				var idx: int = row_offset + x
				arr[idx] = val
				coverage[idx] = 255
			k += 2

func _apply_polygon_regions_bytes(depth: PackedFloat32Array, abs_arr: PackedByteArray,
		coverage: PackedByteArray, w: int, h: int) -> void:
	for region in polygon_regions:
		var pts: Array = region.get("points", [])
		if pts.size() < 3:
			continue
		var dist_val: float = clampf(region.get("ref_distance", 0.5), 0.0, 1.0)
		var abs_val: int = int(clampf(region.get("light_absorption", 0.5), 0.0, 1.0) * 255.0)
		_rasterize_polygon_float(depth, coverage, pts, dist_val, w, h)
		_rasterize_polygon_bytes(abs_arr, coverage, pts, abs_val, w, h)

func _apply_mask_regions_bytes(depth: PackedFloat32Array, abs_arr: PackedByteArray,
		coverage: PackedByteArray, raw_floats: PackedFloat32Array, w: int, h: int) -> void:
	var sorted: Array[Dictionary] = mask_regions.duplicate()
	sorted.sort_custom(_compare_mask_priority)

	var has_raw: bool = raw_floats.size() == depth.size()
	var total: int = w * h

	# 羽化半径（像素）
	var feather_px: int = maxi(0, int(round(mask_feather_radius)))

	# ── Pass 0: 预计算每个 mask 的浮点权重数组（含羽化模糊） ──
	var mask_weights: Dictionary = {}  # id → PackedFloat32Array
	for m in sorted:
		var mask_img: Image = _mask_textures.get(m["id"])
		if mask_img == null:
			continue
		var need_resize: bool = mask_img.get_size() != Vector2i(w, h)
		var need_convert: bool = mask_img.get_format() != Image.FORMAT_RGBA8
		if need_resize or need_convert:
			mask_img = mask_img.duplicate()
			if need_resize:
				mask_img.resize(w, h, Image.INTERPOLATE_BILINEAR)
			if need_convert:
				mask_img.convert(Image.FORMAT_RGBA8)

		var mask_bytes: PackedByteArray = mask_img.get_data()
		var weights := PackedFloat32Array()
		weights.resize(total)
		for i in range(total):
			var mi: int = i * 4
			var a_val: float = float(mask_bytes[mi + 3]) / 255.0
			var r_val: float = float(mask_bytes[mi]) / 255.0
			weights[i] = a_val * r_val

		# 羽化：对权重做 box blur，边缘产生 0→1 渐变
		if feather_px > 0:
			weights = _smooth_float(weights, w, h, feather_px)

		mask_weights[m["id"]] = weights

	# ── Pass 1: 用羽化权重计算每个 mask 的原深度图加权均值 ──
	var mask_means: Dictionary = {}
	if has_raw:
		for m in sorted:
			if not mask_weights.has(m["id"]):
				continue
			var weights: PackedFloat32Array = mask_weights[m["id"]]
			var sum: float = 0.0
			var weight_sum: float = 0.0
			for i in range(total):
				var wv: float = weights[i]
				if wv > 0.01:
					sum += raw_floats[i] * wv
					weight_sum += wv
			mask_means[m["id"]] = (sum / weight_sum) if weight_sum > 0.01 else 0.0

	# ── Pass 2: 用羽化权重做软合成 + 权重 coverage 累积 ──
	for m in sorted:
		if not mask_weights.has(m["id"]):
			continue
		var weights: PackedFloat32Array = mask_weights[m["id"]]
		var dist_val: float = clampf(m.get("ref_distance", 0.5), 0.0, 1.0)
		var abs_val: int = int(clampf(m.get("light_absorption", 0.5), 0.0, 1.0) * 255.0)
		var mask_mean: float = float(mask_means.get(m["id"], 0.0))

		for i in range(total):
			var wv: float = weights[i]
			if wv < 0.01:
				continue

			var final_val: float = dist_val
			if has_raw and mask_means.has(m["id"]):
				final_val = dist_val + (raw_floats[i] - mask_mean) * variation_scale
				final_val = clampf(final_val, 0.0, 2.0)

			# 软合成（alpha blend with weight）
			var old_d: float = depth[i]
			depth[i] = old_d + (final_val - old_d) * wv

			var old_a: float = float(abs_arr[i])
			abs_arr[i] = int(old_a + (float(abs_val) - old_a) * wv)

			# coverage 改为权重累积（取最大值，支持多 mask 重叠）
			var cov_w: int = int(wv * 255.0)
			if cov_w > int(coverage[i]):
				coverage[i] = cov_w

func _apply_layer_depths_bytes(depth: PackedFloat32Array, coverage: PackedByteArray,
		w: int, h: int) -> void:
	for i in range(layers.size() - 1, -1, -1):
		var l: Dictionary = layers[i]
		var layer_depth: Image = _layer_depth_images.get(l["id"])
		var layer_base: Image = _layer_base_images.get(l["id"])
		if layer_depth == null or layer_base == null:
			continue

		var need_d_resize: bool = layer_depth.get_size() != Vector2i(w, h)
		var need_d_conv: bool = layer_depth.get_format() != Image.FORMAT_L8
		if need_d_resize or need_d_conv:
			layer_depth = layer_depth.duplicate()
			if need_d_resize:
				layer_depth.resize(w, h, Image.INTERPOLATE_LANCZOS)
			if need_d_conv:
				layer_depth.convert(Image.FORMAT_L8)

		var need_b_resize: bool = layer_base.get_size() != Vector2i(w, h)
		var need_b_conv: bool = layer_base.get_format() != Image.FORMAT_RGBA8
		if need_b_resize or need_b_conv:
			layer_base = layer_base.duplicate()
			if need_b_resize:
				layer_base.resize(w, h, Image.INTERPOLATE_LANCZOS)
			if need_b_conv:
				layer_base.convert(Image.FORMAT_RGBA8)

		var base_bytes: PackedByteArray = layer_base.get_data()
		var ld_bytes: PackedByteArray = layer_depth.get_data()

		var z_base: float = l.get("z_offset", 0.0)
		var bias: float = clampf(z_base * 0.15, 0.0, 1.0)

		for y in range(h):
			var row_offset: int = y * w
			for x in range(w):
				var base_idx: int = (row_offset + x) * 4
				if base_bytes[base_idx + 3] < 13:
					continue
				var raw_d: float = float(ld_bytes[row_offset + x]) / 255.0
				depth[row_offset + x] = clampf(raw_d + bias, 0.0, 2.0)
				coverage[row_offset + x] = 255

func _smooth_float(arr: PackedFloat32Array, w: int, h: int, radius: int) -> PackedFloat32Array:
	var kernel_f: float = float(radius * 2 + 1)
	var temp := PackedFloat32Array()
	temp.resize(w * h)

	# Pass 1: 水平方向 running sum
	for y in range(h):
		var row_offset: int = y * w
		var sum: float = 0.0
		for dx in range(-radius, radius + 1):
			sum += arr[row_offset + clampi(dx, 0, w - 1)]
		temp[row_offset] = sum / kernel_f
		for x in range(1, w):
			sum -= arr[row_offset + clampi(x - radius - 1, 0, w - 1)]
			sum += arr[row_offset + clampi(x + radius, 0, w - 1)]
			temp[row_offset + x] = sum / kernel_f

	# Pass 2: 垂直方向 running sum
	var result := PackedFloat32Array()
	result.resize(w * h)
	for x in range(w):
		var sum: float = 0.0
		for dy in range(-radius, radius + 1):
			sum += temp[clampi(dy, 0, h - 1) * w + x]
		result[x] = sum / kernel_f
		for y in range(1, h):
			sum -= temp[clampi(y - radius - 1, 0, h - 1) * w + x]
			sum += temp[clampi(y + radius, 0, h - 1) * w + x]
			result[y * w + x] = sum / kernel_f

	return result

func _smooth_bytes(arr: PackedByteArray, w: int, h: int, radius: int) -> PackedByteArray:
	var kernel_f: float = float(radius * 2 + 1)
	var temp := PackedByteArray()
	temp.resize(w * h)

	# Pass 1: 水平方向 running sum
	for y in range(h):
		var row_offset: int = y * w
		var sum: float = 0.0
		for dx in range(-radius, radius + 1):
			sum += float(arr[row_offset + clampi(dx, 0, w - 1)])
		temp[row_offset] = int(sum / kernel_f)
		for x in range(1, w):
			sum -= float(arr[row_offset + clampi(x - radius - 1, 0, w - 1)])
			sum += float(arr[row_offset + clampi(x + radius, 0, w - 1)])
			temp[row_offset + x] = int(sum / kernel_f)

	# Pass 2: 垂直方向 running sum
	var result := PackedByteArray()
	result.resize(w * h)
	for x in range(w):
		var sum: float = 0.0
		for dy in range(-radius, radius + 1):
			sum += float(temp[clampi(dy, 0, h - 1) * w + x])
		result[x] = int(sum / kernel_f)
		for y in range(1, h):
			sum -= float(temp[clampi(y - radius - 1, 0, h - 1) * w + x])
			sum += float(temp[clampi(y + radius, 0, h - 1) * w + x])
			result[y * w + x] = int(sum / kernel_f)

	return result

func _apply_raw_fallback_bytes(depth: PackedFloat32Array, coverage: PackedByteArray,
		raw_floats: PackedFloat32Array) -> void:
	# 软过渡：coverage 权重 0→1 在 raw depth 和 region depth 之间 lerp
	# coverage=0   → 全用 raw depth（未覆盖区域）
	# coverage=128 → 50% 混合（mask 边缘羽化区）
	# coverage=255 → 全用 region depth（mask 内部）
	var total: int = depth.size()
	for i in range(total):
		var w: float = float(coverage[i]) / 255.0
		if w < 1.0:
			depth[i] = lerpf(raw_floats[i], depth[i], w)

func build_composite_base_image() -> void:
	if layers.is_empty():
		composite_base_image = null
		composite_base_texture = null
		return

	var img_w: int = base_image.get_width() if base_image else 0
	var img_h: int = base_image.get_height() if base_image else 0
	if img_w == 0 or img_h == 0:
		return

	var result_bytes: PackedByteArray
	if base_image:
		var base_copy: Image = base_image.duplicate()
		if base_copy.get_format() != Image.FORMAT_RGBA8:
			base_copy.convert(Image.FORMAT_RGBA8)
		result_bytes = base_copy.get_data()
	else:
		result_bytes = PackedByteArray()
		result_bytes.resize(img_w * img_h * 4)
		result_bytes.fill(0)

	for l in layers:
		var layer_img: Image = _layer_base_images.get(l["id"])
		if layer_img == null:
			continue

		var need_resize: bool = layer_img.get_size() != Vector2i(img_w, img_h)
		var need_conv: bool = layer_img.get_format() != Image.FORMAT_RGBA8
		if need_resize or need_conv:
			layer_img = layer_img.duplicate()
			if need_resize:
				layer_img.resize(img_w, img_h, Image.INTERPOLATE_LANCZOS)
			if need_conv:
				layer_img.convert(Image.FORMAT_RGBA8)

		var layer_bytes: PackedByteArray = layer_img.get_data()

		for y in range(img_h):
			var row_offset: int = y * img_w
			for x in range(img_w):
				var px_idx: int = (row_offset + x) * 4
				var upper_a_byte: int = layer_bytes[px_idx + 3]
				if upper_a_byte < 13:
					continue

				var ua: float = float(upper_a_byte) / 255.0
				var lower_a_byte: int = result_bytes[px_idx + 3]
				var la: float = float(lower_a_byte) / 255.0
				var out_a: float = ua + la * (1.0 - ua)

				if out_a > 0.0:
					var inv_out: float = 255.0 / out_a
					var ur: float = float(layer_bytes[px_idx])
					var ug: float = float(layer_bytes[px_idx + 1])
					var ub: float = float(layer_bytes[px_idx + 2])
					var lr: float = float(result_bytes[px_idx])
					var lg: float = float(result_bytes[px_idx + 1])
					var lb: float = float(result_bytes[px_idx + 2])

					result_bytes[px_idx] = int((ur * ua + lr * la * (1.0 - ua)) * inv_out)
					result_bytes[px_idx + 1] = int((ug * ua + lg * la * (1.0 - ua)) * inv_out)
					result_bytes[px_idx + 2] = int((ub * ua + lb * la * (1.0 - ua)) * inv_out)
					result_bytes[px_idx + 3] = int(out_a * 255.0)

	composite_base_image = Image.create_from_data(img_w, img_h, false, Image.FORMAT_RGBA8, result_bytes)
	composite_base_texture = ImageTexture.create_from_image(composite_base_image)

func _clear_region_data() -> void:
	region_depth_image = null
	region_depth_texture = null
	absorption_image = null
	absorption_texture = null

func build_region_depth_map() -> void:
	if not use_region_depth:
		_clear_region_data()
		return

	# 优先合成底图（layers 按 z_offset 从远到近覆盖到 base_image 上）
	build_composite_base_image()

	var img_w: int = 0
	var img_h: int = 0
	if composite_base_image:
		img_w = composite_base_image.get_width()
		img_h = composite_base_image.get_height()
	elif base_image:
		img_w = base_image.get_width()
		img_h = base_image.get_height()
	elif depth_map:
		img_w = depth_map.get_width()
		img_h = depth_map.get_height()
	else:
		return

	var total: int = img_w * img_h
	var default_val: float = clampf(global_default_distance, 0.0, 2.0)

	# 创建浮点深度数组 + L8 吸光 + L8 覆盖掩码
	var depth_floats := PackedFloat32Array()
	depth_floats.resize(total)
	depth_floats.fill(default_val)

	var abs_bytes := PackedByteArray()
	abs_bytes.resize(total)
	abs_bytes.fill(128)

	var coverage_bytes := PackedByteArray()
	coverage_bytes.resize(total)
	coverage_bytes.fill(0)

	# ── 预处理原深度图为浮点数组（供 mask 局部变化和 fallback 使用）──
	var raw_floats := PackedFloat32Array()
	raw_floats.resize(total)
	raw_floats.fill(0.0)
	var has_raw: bool = false
	if depth_map:
		var raw: Image = depth_map
		if raw.get_size() != Vector2i(img_w, img_h):
			raw = raw.duplicate()
			raw.resize(img_w, img_h, Image.INTERPOLATE_LANCZOS)
		if raw.get_format() != Image.FORMAT_L8:
			raw = raw.duplicate()
			raw.convert(Image.FORMAT_L8)
		var raw_bytes: PackedByteArray = raw.get_data()
		for i in range(total):
			raw_floats[i] = float(raw_bytes[i]) / 255.0
		has_raw = true

	# Step 1: Polygon regions（最低优先级）
	_apply_polygon_regions_bytes(depth_floats, abs_bytes, coverage_bytes, img_w, img_h)

	# Step 2: PNG mask regions（覆盖 polygon，两遍算法 with 局部变化）
	_apply_mask_regions_bytes(depth_floats, abs_bytes, coverage_bytes, raw_floats, img_w, img_h)

	# Step 3: Layer z_offset（最高优先级，覆盖 mask）
	_apply_layer_depths_bytes(depth_floats, coverage_bytes, img_w, img_h)

	# Step 4: Raw depth fallback — 使用覆盖掩码判断，先于平滑
	if use_raw_depth_fallback and has_raw:
		_apply_raw_fallback_bytes(depth_floats, coverage_bytes, raw_floats)

	# Step 5: 边缘平滑 — 在 fallback 之后，使 region 与 raw depth 自然过渡
	if smooth_radius > 0.0:
		var px_radius: int = maxi(1, int(smooth_radius * float(mini(img_w, img_h))))
		depth_floats = _smooth_float(depth_floats, img_w, img_h, px_radius)
		abs_bytes = _smooth_bytes(abs_bytes, img_w, img_h, px_radius)

	# 从浮点数组创建最终图像（FORMAT_RF = 32-bit float per pixel）
	region_depth_image = Image.create_from_data(img_w, img_h, false, Image.FORMAT_RF, depth_floats.to_byte_array())
	region_depth_texture = ImageTexture.create_from_image(region_depth_image)
	absorption_image = Image.create_from_data(img_w, img_h, false, Image.FORMAT_L8, abs_bytes)
	absorption_texture = ImageTexture.create_from_image(absorption_image)
	_region_dirty = false
