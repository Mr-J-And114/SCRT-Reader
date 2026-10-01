# ============================================================
# camera_viewer.gd - 监控摄像头查看器
# 职责：
#   - 全屏 overlay 显示摄像头画面（遵循 EnvViewer 模式）
#   - 底图裁剪 + shader 后处理（噪点/扫描线/照明/深度）
#   - 方向键平移镜头，TAB 切换摄像头
#   - UI 叠加（摄像头名称、时间戳、REC 指示灯、信号条）
# ============================================================
class_name CameraViewer
extends RefCounted

# ══════════════════════════════════════════
#  引用
# ══════════════════════════════════════════
var main = null
var camera_mgr: CameraManager = null
var T = null

# ══════════════════════════════════════════
#  UI 节点
# ══════════════════════════════════════════
var overlay_panel: Panel = null
var canvas: Control = null           # _CameraCanvas 内部类实例
var shader_rect: ColorRect = null    # shader 画面（SubViewportContainer 替代方案）

# ── 鼠标拖动平移 ──
var _drag_active: bool = false
var _drag_last_pos: Vector2 = Vector2.ZERO

# ── 控制按钮面板 ──
var _ctrl_panel: PanelContainer = null
var _buttons_visible: bool = true
var _double_click_timer: float = 0.0
const DOUBLE_CLICK_TIME: float = 0.35

# ── 激光束模式 ──
var _laser_active: bool = false
var _laser_time: float = 0.0

# ══════════════════════════════════════════
#  显示状态
# ══════════════════════════════════════════
var is_active: bool = false
var current_camera_index: int = 0    # 当前查看的摄像头在已解锁列表中的索引
var _time_val: float = 0.0           # shader 时间参数
var _rec_blink: bool = true          # REC 指示灯闪烁
var _blink_timer: float = 0.0
var _glitch_timer: float = 0.0       # 切换摄像头时的 glitch 过渡
var _switch_cooldown: float = 0.0    # 防止快速切换
var _pan_held: Dictionary = {}       # 方向键按住状态

# 缓存（打开前保存，关闭后恢复）
var _cached_input_visible: bool = true
var _cached_prompt_visible: bool = true
var _cached_output_text: String = ""

# 照明模式名称映射
const LIGHT_MODE_NAMES: Dictionary = {
	"none": 0,
	"spotlight": 1,
	"nightvision": 2,
	"infrared": 3,
}
const LIGHT_MODE_LABELS: Array = ["OFF", "SPOTLIGHT", "NIGHTVISION", "INFRARED"]
const LIGHT_MODES: Array = ["none", "spotlight", "nightvision", "infrared"]

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(p_main, p_camera_mgr: CameraManager) -> void:
	main = p_main
	camera_mgr = p_camera_mgr
	T = ThemeManager.current

# ══════════════════════════════════════════
#  打开 / 关闭
# ══════════════════════════════════════════
func open(camera_id: String = "") -> void:
	if is_active:
		return
	if camera_mgr == null or not camera_mgr.has_cameras():
		return
	var unlocked: Array[SecurityCameraFeed] = camera_mgr.get_unlocked_cameras()
	if unlocked.is_empty():
		return

	is_active = true
	T = ThemeManager.current
	_time_val = 0.0
	_glitch_timer = 0.0
	_switch_cooldown = 0.0
	_pan_held.clear()

	# 确定初始摄像头
	current_camera_index = 0
	if not camera_id.is_empty():
		for i in range(unlocked.size()):
			if unlocked[i].id == camera_id:
				current_camera_index = i
				break

	# 加载当前摄像头纹理
	_load_current_camera_textures()

	_ensure_overlay()
	_align_overlay()

	# 缓存并隐藏终端 UI
	_cached_input_visible = main.input_field.visible
	_cached_prompt_visible = main.prompt_label.visible
	main.input_field.visible = false
	main.prompt_label.visible = false
	_cached_output_text = main.output_text.text
	main.output_text.text = ""

	# 更新路径栏提示
	if main.path_label:
		main.path_label.text = "CCTV MONITOR | 鼠标拖动平移  滚轮缩放  R 深度  Q/ESC 退出"

	overlay_panel.visible = true

func close() -> void:
	if not is_active:
		return
	is_active = false
	_pan_held.clear()
	_drag_active = false
	_buttons_visible = true
	_laser_active = false
	_laser_time = 0.0
	# 隐藏覆盖层
	if overlay_panel and is_instance_valid(overlay_panel):
		overlay_panel.visible = false
	# 恢复终端 UI
	main.output_text.clear()
	main.output_text.append_text(_cached_output_text)
	_cached_output_text = ""
	main.input_field.visible = _cached_input_visible
	main.prompt_label.visible = _cached_prompt_visible

	if main.has_method("_update_status_bar"):
		main._update_status_bar()
	main.input_field.grab_focus()

# ══════════════════════════════════════════
#  输入处理（由 main._input 委托）
# ══════════════════════════════════════════
func handle_input(event: InputEvent) -> bool:
	if not is_active:
		return false

	# ── 鼠标输入 ──
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# 双击检测：隐藏按钮时双击恢复（同时不影响拖动）
				if not _buttons_visible:
					if _double_click_timer > 0.0:
						_set_buttons_visible(true)
						_double_click_timer = 0.0
						# 双击恢复后不开始拖动
						return true
					else:
						_double_click_timer = DOUBLE_CLICK_TIME
						# 第一次点击仍然开始拖动
				# 开始拖动
				_drag_active = true
				_drag_last_pos = mb.position
				return true
			else:
				# 释放拖动
				_drag_active = false
				return true
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_adjust_zoom(-0.03)
			return true
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_adjust_zoom(0.03)
			return true
		return false

	if event is InputEventMouseMotion and _drag_active:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		var delta: Vector2 = mm.position - _drag_last_pos
		_drag_last_pos = mm.position
		var cam: SecurityCameraFeed = _get_current_camera()
		if cam:
			# 拖动方向反转（向右拖 = 看向左侧）
			var pan_dir: Vector2 = Vector2(-delta.x, -delta.y)
			cam.pan(pan_dir * cam.pan_speed * 0.5)
		return true

	if event is InputEventKey:
		var key: InputEventKey = event
		# 按键释放：清除方向键持续状态
		if not key.pressed:
			match key.keycode:
				KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
					_pan_held.erase(key.keycode)
					return true
			return false

		# 按键按下
		match key.keycode:
			KEY_ESCAPE, KEY_Q:
				close()
				return true
			KEY_LEFT:
				_pan_held[KEY_LEFT] = true
				return true
			KEY_RIGHT:
				_pan_held[KEY_RIGHT] = true
				return true
			KEY_UP:
				_pan_held[KEY_UP] = true
				return true
			KEY_DOWN:
				_pan_held[KEY_DOWN] = true
				return true
			KEY_TAB:
				if key.shift_pressed:
					_switch_camera(-1)
				else:
					_switch_camera(1)
				return true
			KEY_F:
				_cycle_light_mode()
				return true
			KEY_R:
				_toggle_region_depth()
				return true
			KEY_BRACKETLEFT:   # [ 拉远（扩大视野）
				_adjust_zoom(0.05)
				return true
			KEY_BRACKETRIGHT:  # ] 拉近（缩小视野）
				_adjust_zoom(-0.05)
				return true
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				var idx: int = key.keycode - KEY_1
				_jump_to_camera(idx)
				return true
	return false

# ══════════════════════════════════════════
#  每帧更新
# ══════════════════════════════════════════
func process(delta: float) -> void:
	if not is_active or canvas == null:
		return

	_time_val += delta

	# 激光束时间更新（偏移量随时间正弦变化）
	if _laser_active:
		_laser_time += delta

	# 双击计时器衰减
	if _double_click_timer > 0.0:
		_double_click_timer = maxf(_double_click_timer - delta, 0.0)

	# REC 指示灯闪烁
	_blink_timer += delta
	if _blink_timer >= 0.8:
		_blink_timer -= 0.8
		_rec_blink = not _rec_blink

	# Glitch 过渡衰减
	if _glitch_timer > 0.0:
		_glitch_timer = maxf(_glitch_timer - delta * 3.0, 0.0)

	# 处理切换冷却
	if _switch_cooldown > 0.0:
		_switch_cooldown -= delta

	# 处理方向键持续平移
	_process_pan(delta)

	# 更新 shader 参数
	_update_shader_params()

	canvas.queue_redraw()

func _adjust_zoom(delta: float) -> void:
	var cam: SecurityCameraFeed = _get_current_camera()
	if cam == null:
		return
	var new_size: float = clampf(cam.viewport_size.x + delta, cam.fov_min, cam.fov_max)
	cam.viewport_size = Vector2(new_size, new_size)
	# 重新约束镜头位置，防止超出边界
	cam.viewport_pos.x = clampf(cam.viewport_pos.x,
		cam.pan_bounds.position.x + new_size * 0.5,
		cam.pan_bounds.end.x - new_size * 0.5)
	cam.viewport_pos.y = clampf(cam.viewport_pos.y,
		cam.pan_bounds.position.y + new_size * 0.5,
		cam.pan_bounds.end.y - new_size * 0.5)

func _process_pan(delta: float) -> void:
	var cam: SecurityCameraFeed = _get_current_camera()
	if cam == null:
		return
	var dir := Vector2.ZERO
	if _pan_held.has(KEY_LEFT):
		dir.x -= 1.0
	if _pan_held.has(KEY_RIGHT):
		dir.x += 1.0
	if _pan_held.has(KEY_UP):
		dir.y -= 1.0
	if _pan_held.has(KEY_DOWN):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		cam.pan(dir * delta * 60.0)

# ══════════════════════════════════════════
#  摄像头切换
# ══════════════════════════════════════════
func _switch_camera(direction: int) -> void:
	if _switch_cooldown > 0.0:
		return
	var unlocked: Array[SecurityCameraFeed] = camera_mgr.get_unlocked_cameras()
	if unlocked.size() <= 1:
		return
	current_camera_index = (current_camera_index + direction + unlocked.size()) % unlocked.size()
	_load_current_camera_textures()
	_glitch_timer = 1.0
	_switch_cooldown = 0.3

func _jump_to_camera(index: int) -> void:
	var unlocked: Array[SecurityCameraFeed] = camera_mgr.get_unlocked_cameras()
	if index >= 0 and index < unlocked.size() and index != current_camera_index:
		current_camera_index = index
		_load_current_camera_textures()
		_glitch_timer = 1.0
		_switch_cooldown = 0.3

func _cycle_light_mode() -> void:
	var cam: SecurityCameraFeed = _get_current_camera()
	if cam == null:
		return

	# 获取当前模式索引
	var current_idx: int = LIGHT_MODES.find(cam.light_mode)
	if current_idx < 0:
		current_idx = 0

	# 尝试切换到下一个模式
	var attempts: int = 0
	var next_idx: int = (current_idx + 1) % LIGHT_MODES.size()

	while attempts < LIGHT_MODES.size():
		var next_mode: String = LIGHT_MODES[next_idx]

		# 检查是否需要特殊资源
		var can_use: bool = true
		var missing_resource: String = ""

		# none 模式不需要任何资源
		if next_mode == "none":
			can_use = true
		# 检查是否有预渲染图片
		elif cam.use_prerendered:
			if next_mode == "spotlight":
				if cam.spotlight_texture == null:
					can_use = false
					missing_resource = "聚光灯预渲染图"
			elif next_mode == "nightvision":
				if cam.nightvision_texture == null:
					can_use = false
					missing_resource = "夜视预渲染图"
			elif next_mode == "infrared":
				if cam.infrared_texture == null:
					can_use = false
					missing_resource = "红外预渲染图"
		# 使用 shader 后处理
		else:
			# Spotlight/Nightvision 需要深度图
			if next_mode == "spotlight" or next_mode == "nightvision":
				if cam.depth_texture == null:
					can_use = false
					missing_resource = "深度图"
			# Infrared 必须使用预渲染图
			elif next_mode == "infrared":
				can_use = false
				missing_resource = "红外预渲染图（Infrared 模式不支持自动生成）"

		if can_use:
			cam.light_mode = next_mode
			return
		else:
			# 提示缺失资源
			if main:
				main.append_output("[color=" + main.T.warning_hex + "]无法切换到 " + LIGHT_MODE_LABELS[LIGHT_MODE_NAMES[next_mode]] + " 模式：缺少" + missing_resource + "[/color]\n", false)
			# 尝试下一个模式
			next_idx = (next_idx + 1) % LIGHT_MODES.size()
			attempts += 1

	# 如果所有模式都不可用，保持当前模式
	if main:
		main.append_output("[color=" + main.T.error_hex + "]所有照明模式都不可用[/color]\n", false)

func _toggle_region_depth() -> void:
	var cam: SecurityCameraFeed = _get_current_camera()
	if cam == null or cam.region_config.is_empty():
		return
	cam.use_region_depth = not cam.use_region_depth
	var status: String = "REGION DEPTH" if cam.use_region_depth else "PER-PIXEL DEPTH"
	if main:
		main.append_output("[color=" + main.T.info_hex + "]深度模式切换: " + status + "[/color]\n", false)
	if main.path_label:
		main.path_label.text = "深度模式: " + status

func _get_current_camera() -> SecurityCameraFeed:
	var unlocked: Array[SecurityCameraFeed] = camera_mgr.get_unlocked_cameras()
	if unlocked.is_empty() or current_camera_index >= unlocked.size():
		return null
	return unlocked[current_camera_index]

func _load_current_camera_textures() -> void:
	var cam: SecurityCameraFeed = _get_current_camera()
	if cam:
		camera_mgr.load_camera_textures(cam.id)

# ══════════════════════════════════════════
#  Shader 参数更新
# ══════════════════════════════════════════
func _update_shader_params() -> void:
	if shader_rect == null or not is_instance_valid(shader_rect):
		return
	var mat: ShaderMaterial = shader_rect.material as ShaderMaterial
	if mat == null:
		return

	var cam: SecurityCameraFeed = _get_current_camera()
	if cam == null:
		return

	# ★ 重置 spotlight overlay 标志
	mat.set_shader_parameter("use_spotlight_overlay", false)

	# ★ 检查是否使用预渲染图片
	var using_prerendered: bool = false
	if cam.use_prerendered:
		if cam.light_mode == "spotlight" and cam.spotlight_texture:
			# Spotlight 手电模式：
			# base_texture = 夜间图（spotlight_texture = dark image）
			# spotlight_overlay = 白天图（base_texture = day image）
			mat.set_shader_parameter("base_texture", cam.spotlight_texture)
			mat.set_shader_parameter("spotlight_overlay", cam.base_texture)
			mat.set_shader_parameter("use_spotlight_overlay", true)
			mat.set_shader_parameter("light_mode", 1)
			using_prerendered = true
		elif cam.light_mode == "nightvision" and cam.nightvision_texture:
			# 使用预渲染夜视图
			mat.set_shader_parameter("base_texture", cam.nightvision_texture)
			mat.set_shader_parameter("light_mode", 0)  # 关闭 shader 后处理
			using_prerendered = true
		elif cam.light_mode == "infrared" and cam.infrared_texture:
			# 使用预渲染红外图
			mat.set_shader_parameter("base_texture", cam.infrared_texture)
			mat.set_shader_parameter("light_mode", 0)  # 关闭 shader 后处理
			using_prerendered = true

	# 如果没有使用预渲染，使用正常流程
	if not using_prerendered:
		# 基础纹理
		if cam.base_texture:
			mat.set_shader_parameter("base_texture", cam.base_texture)
		if cam.depth_texture:
			mat.set_shader_parameter("depth_texture", cam.depth_texture)
		if cam.light_texture:
			mat.set_shader_parameter("light_texture", cam.light_texture)

		# 照明参数
		var mode_idx: int = LIGHT_MODE_NAMES.get(cam.light_mode, 0)
		mat.set_shader_parameter("light_mode", mode_idx)
	else:
		# 使用预渲染时，仍然需要设置深度图（用于视差效果）
		if cam.depth_texture:
			mat.set_shader_parameter("depth_texture", cam.depth_texture)

	# ★ 视差贴图参数
	mat.set_shader_parameter("use_parallax", cam.use_parallax)
	mat.set_shader_parameter("parallax_scale", cam.parallax_scale)
	mat.set_shader_parameter("parallax_layers", cam.parallax_layers)
	# 镜头朝向偏移：替代逐像素 view_dir，消除中央畸变
	mat.set_shader_parameter("parallax_view_offset", cam.viewport_pos - Vector2(0.5, 0.5))

	# 镜头裁剪区域
	var vr: Rect2 = cam.get_viewport_rect()
	mat.set_shader_parameter("viewport_rect", Vector4(vr.position.x, vr.position.y, vr.size.x, vr.size.y))

	# 照明参数（即使使用预渲染也需要设置，用于其他计算）
	mat.set_shader_parameter("light_center", Vector2(0.5, 0.5))
	mat.set_shader_parameter("light_radius", cam.light_radius)
	mat.set_shader_parameter("light_falloff", cam.light_falloff)

	# 效果参数
	var signal_q: float = cam.signal_quality
	# Glitch 过渡时降低信号质量
	if _glitch_timer > 0.0:
		signal_q *= (1.0 - _glitch_timer * 0.8)

	mat.set_shader_parameter("noise_intensity", cam.noise_intensity)
	mat.set_shader_parameter("scanline_intensity", cam.scanline_intensity)
	mat.set_shader_parameter("snow_intensity", cam.snow_intensity + _glitch_timer * 0.5)
	mat.set_shader_parameter("signal_quality", signal_q)
	mat.set_shader_parameter("vignette_strength", cam.vignette)
	mat.set_shader_parameter("time_val", _time_val)

	# 异常混合
	mat.set_shader_parameter("anomaly_blend", cam._anomaly_blend)
	# 异常叠加模式（透明叠加 vs 图像替换）
	var anom_overlay: bool = false
	if cam.is_anomaly_active():
		anom_overlay = cam._active_anomaly.get("overlay_mode", false)
	mat.set_shader_parameter("anomaly_overlay_mode", anom_overlay)
	if cam._anomaly_base_tex:
		mat.set_shader_parameter("anomaly_texture", cam._anomaly_base_tex)
	if cam._anomaly_depth_tex:
		mat.set_shader_parameter("anomaly_depth", cam._anomaly_depth_tex)
	if cam._anomaly_light_tex:
		mat.set_shader_parameter("anomaly_light", cam._anomaly_light_tex)

	# ★ Region Depth
	mat.set_shader_parameter("use_region_depth", cam.use_region_depth)
	if cam.use_region_depth and cam.region_depth_texture:
		mat.set_shader_parameter("region_depth_texture", cam.region_depth_texture)

	# 合成底图（含 layers）优先于原始 base_texture
	if cam.composite_base_texture:
		mat.set_shader_parameter("base_texture", cam.composite_base_texture)

	# ★ 激光束
	mat.set_shader_parameter("use_laser", _laser_active)
	if _laser_active:
		# 偏移量随时间正弦变化，模拟激光扫描
		var laser_off: float = sin(_laser_time * 0.8) * 0.15
		mat.set_shader_parameter("laser_offset", laser_off)

	# 离线时全雪花
	if not cam.online:
		mat.set_shader_parameter("snow_intensity", 0.9)
		mat.set_shader_parameter("signal_quality", 0.0)

# ══════════════════════════════════════════
#  覆盖层创建
# ══════════════════════════════════════════
func _ensure_overlay() -> void:
	if overlay_panel != null and is_instance_valid(overlay_panel):
		return

	# 创建覆盖 Panel
	overlay_panel = Panel.new()
	overlay_panel.name = "CameraViewerOverlay"
	overlay_panel.visible = false
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0)
	overlay_panel.add_theme_stylebox_override("panel", bg_style)

	var root_control: Control = main as Control
	root_control.add_child(overlay_panel)
	# 放在 CRTEffect 之前
	var crt_node: Node = root_control.get_node_or_null("CRTEffect")
	if crt_node:
		root_control.move_child(overlay_panel, crt_node.get_index())
	overlay_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_panel.offset_left = 0
	overlay_panel.offset_top = 0
	overlay_panel.offset_right = 0
	overlay_panel.offset_bottom = 0

	# Shader 画面（ColorRect + ShaderMaterial）
	shader_rect = ColorRect.new()
	shader_rect.name = "CameraShaderRect"
	shader_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	shader_rect.color = Color.BLACK
	shader_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 加载 shader
	var shader: Shader = _load_shader()
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		shader_rect.material = mat
	overlay_panel.add_child(shader_rect)

	# UI 覆盖画布（绘制在 shader 画面之上）
	canvas = _CameraCanvas.new()
	canvas.viewer = self
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_panel.add_child(canvas)

	# ── 控制按钮面板（右上角） ──
	_create_control_buttons()

func _create_control_buttons() -> void:
	_ctrl_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.1, 0.05, 0.75)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.2, 0.4, 0.2, 0.6)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_ctrl_panel.add_theme_stylebox_override("panel", style)
	_ctrl_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_panel.add_child(_ctrl_panel)

	# 横向排列按钮
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	_ctrl_panel.add_child(hbox)

	# 各按钮
	_add_ctrl_btn(hbox, "✕ 退出", _on_btn_exit)
	_add_ctrl_btn(hbox, "− 缩小", _on_btn_zoom_out)
	_add_ctrl_btn(hbox, "+ 放大", _on_btn_zoom_in)
	_add_ctrl_btn(hbox, "R 深度", _on_btn_depth)
	_add_ctrl_btn(hbox, "F 照明", _on_btn_light)
	_add_ctrl_btn(hbox, "L 激光", _on_btn_laser)
	_add_ctrl_btn(hbox, "切换", _on_btn_switch)
	_add_ctrl_btn(hbox, "隐藏", _on_btn_hide)

	# 定位到右上角（延后设置位置，等 overlay 尺寸确定后）
	call_deferred("_position_control_buttons")

func _add_ctrl_btn(parent: HBoxContainer, text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", Color(0.7, 0.95, 0.7))
	btn.add_theme_color_override("font_hover_color", Color(0.9, 1.0, 0.9))
	btn.add_theme_color_override("font_pressed_color", Color(0.5, 0.8, 0.5))
	var ns := StyleBoxFlat.new()
	ns.bg_color = Color(0.08, 0.15, 0.08, 0.8)
	ns.border_width_bottom = 1
	ns.border_width_top = 1
	ns.border_width_left = 1
	ns.border_width_right = 1
	ns.border_color = Color(0.25, 0.4, 0.25, 0.7)
	ns.corner_radius_top_left = 3
	ns.corner_radius_top_right = 3
	ns.corner_radius_bottom_left = 3
	ns.corner_radius_bottom_right = 3
	ns.content_margin_left = 8
	ns.content_margin_right = 8
	ns.content_margin_top = 4
	ns.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", ns)
	var hs := ns.duplicate()
	hs.bg_color = Color(0.12, 0.22, 0.12, 0.9)
	btn.add_theme_stylebox_override("hover", hs)
	var ps := ns.duplicate()
	ps.bg_color = Color(0.05, 0.1, 0.05, 1.0)
	btn.add_theme_stylebox_override("pressed", ps)
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn

func _position_control_buttons() -> void:
	if _ctrl_panel == null or not is_instance_valid(_ctrl_panel):
		return
	if overlay_panel == null:
		return
	# PanelContainer 自动计算 minimum_size，用它来获取实际宽度
	var panel_size: Vector2 = _ctrl_panel.get_combined_minimum_size()
	var w: float = overlay_panel.size.x
	_ctrl_panel.position = Vector2(w - panel_size.x - 12, 12)
	_ctrl_panel.size = panel_size

func _set_buttons_visible(vis: bool) -> void:
	_buttons_visible = vis
	if _ctrl_panel:
		_ctrl_panel.visible = vis

# ── 按钮回调 ──
func _on_btn_exit() -> void:
	close()

func _on_btn_zoom_in() -> void:
	_adjust_zoom(-0.05)

func _on_btn_zoom_out() -> void:
	_adjust_zoom(0.05)

func _on_btn_depth() -> void:
	_toggle_region_depth()

func _on_btn_light() -> void:
	_cycle_light_mode()

func _on_btn_switch() -> void:
	_switch_camera(1)

func _on_btn_laser() -> void:
	_laser_active = not _laser_active
	if main:
		var status: String = "开启" if _laser_active else "关闭"
		main.append_output("[color=#66CCFF]激光束: " + status + "[/color]\n", false)

func _on_btn_hide() -> void:
	_set_buttons_visible(false)

func _load_shader() -> Shader:
	# 尝试加载摄像头 shader
	var shader_path: String = "res://camera_system/camera_effect.gdshader"
	if ResourceLoader.exists(shader_path):
		return load(shader_path) as Shader

	# 尝试旧路径（兼容性）
	var old_path: String = "res://SCRT/camera_system/camera_effect.gdshader"
	if ResourceLoader.exists(old_path):
		return load(old_path) as Shader

	# 编辑器外回退：尝试绝对路径
	if not OS.has_feature("editor"):
		var exe_dir: String = OS.get_executable_path().get_base_dir()
		var alt_paths: Array[String] = [
			exe_dir + "/camera_system/camera_effect.gdshader",
			exe_dir + "/SCRT/camera_system/camera_effect.gdshader"
		]
		for alt_path in alt_paths:
			if FileAccess.file_exists(alt_path):
				var shader := Shader.new()
				var code: String = FileAccess.get_file_as_string(alt_path)
				if not code.is_empty():
					shader.code = code
					return shader

	# ★ 静默失败，只在首次打开查看器时警告
	push_warning("[CameraViewer] 无法加载摄像头 shader，将使用无 shader 模式")
	return null

func _align_overlay() -> void:
	if overlay_panel == null or not is_instance_valid(overlay_panel):
		return
	var output_area: ScrollContainer = main.scroll_container
	var rect: Rect2 = output_area.get_global_rect()
	overlay_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	overlay_panel.position = rect.position
	overlay_panel.size = rect.size
	# 重新定位控制按钮
	call_deferred("_position_control_buttons")

# ══════════════════════════════════════════
#  UI 绘制内部画布
# ══════════════════════════════════════════
class _CameraCanvas extends Control:
	var viewer: CameraViewer = null

	func _draw() -> void:
		if viewer == null:
			return
		viewer._draw_ui(self)

# ══════════════════════════════════════════
#  UI 叠加绘制
# ══════════════════════════════════════════
func _draw_ui(canvas_node: Control) -> void:
	var rect: Rect2 = canvas_node.get_rect()
	var w: float = rect.size.x
	var h: float = rect.size.y
	var cam: SecurityCameraFeed = _get_current_camera()
	var unlocked: Array[SecurityCameraFeed] = camera_mgr.get_unlocked_cameras()

	var font: Font = ThemeDB.fallback_font
	var font_size: int = 14
	var small_size: int = 11
	var margin: float = 12.0

	# UI 颜色（跟随主题色）
	var theme_primary: Color = T.primary if T else Color(0.6, 1.0, 0.6)
	var col_text: Color = Color(theme_primary.r, theme_primary.g, theme_primary.b, 0.9)
	var col_dim: Color = Color(theme_primary.r * 0.6, theme_primary.g * 0.6, theme_primary.b * 0.6, 0.7)
	var col_rec: Color = Color(1.0, 0.15, 0.1, 1.0) if _rec_blink else Color(0.4, 0.1, 0.08, 0.6)
	var col_offline: Color = Color(1.0, 0.3, 0.2, 0.9)
	var col_bg: Color = Color(0, 0, 0, 0.5)

	if cam == null:
		# 无摄像头可用
		var msg: String = "NO CAMERA FEED AVAILABLE"
		var msg_w: float = font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		canvas_node.draw_string(font, Vector2((w - msg_w) * 0.5, h * 0.5), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col_offline)
		return

	# ── 顶部：摄像头名称 + 位置 ──
	var top_y: float = margin + font_size
	# 背景条
	canvas_node.draw_rect(Rect2(0, 0, w, top_y + 8), col_bg)

	var cam_label: String = "CAM %02d | %s" % [current_camera_index + 1, cam.cam_name]
	canvas_node.draw_string(font, Vector2(margin, top_y), cam_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col_text)

	# 位置信息（右侧）
	var loc_text: String = cam.location
	var loc_w: float = font.get_string_size(loc_text, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size).x
	canvas_node.draw_string(font, Vector2(w - margin - loc_w, top_y), loc_text, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, col_dim)

	# ── 左上角：REC 指示灯 ──
	var rec_y: float = top_y + 22
	# REC 圆点
	canvas_node.draw_circle(Vector2(margin + 6, rec_y - 4), 4.0, col_rec)
	canvas_node.draw_string(font, Vector2(margin + 16, rec_y), "REC", HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, col_rec)

	# ── 右上角：信号质量条 ──
	if cam.online:
		var bar_w: float = 60.0
		var bar_h: float = 6.0
		var bar_x: float = w - margin - bar_w
		var bar_y: float = rec_y - bar_h - 1
		# 背景
		canvas_node.draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.2, 0.2, 0.2, 0.6))
		# 填充
		var fill_w: float = bar_w * cam.signal_quality
		var bar_color: Color = Color(0.2, 0.8, 0.3) if cam.signal_quality > 0.5 else Color(1.0, 0.6, 0.1)
		if cam.signal_quality < 0.25:
			bar_color = Color(1.0, 0.2, 0.2)
		canvas_node.draw_rect(Rect2(bar_x, bar_y, fill_w, bar_h), bar_color)
		# 标签
		var sig_label: String = "SIG %d%%" % int(cam.signal_quality * 100)
		var sig_w: float = font.get_string_size(sig_label, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size).x
		canvas_node.draw_string(font, Vector2(bar_x - sig_w - 4, rec_y), sig_label, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, col_dim)
	else:
		# 离线状态
		var offline_label: String = "[ OFFLINE ]"
		var off_w: float = font.get_string_size(offline_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		canvas_node.draw_string(font, Vector2(w - margin - off_w, rec_y), offline_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col_offline)

	# ── 左下角：照明模式 ──
	var bottom_y: float = h - margin
	var mode_idx: int = LIGHT_MODE_NAMES.get(cam.light_mode, 0)
	var mode_label: String = "LIGHT: " + LIGHT_MODE_LABELS[mode_idx]
	canvas_node.draw_string(font, Vector2(margin, bottom_y), mode_label, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, col_dim)

	# ── 深度模式指示（照明模式右侧）──
	if not cam.region_config.is_empty():
		var depth_mode: String = "DEPTH: " + ("REGION" if cam.use_region_depth else "PER-PIXEL")
		var mode_w: float = font.get_string_size(mode_label, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size).x
		canvas_node.draw_string(font, Vector2(margin + mode_w + 20, bottom_y), depth_mode,
			HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, Color(0.3, 0.8, 1.0, 0.8))

	# ── 右下角：时间戳 ──
	if cam.timestamp_visible:
		var time_dict: Dictionary = Time.get_datetime_dict_from_system()
		var timestamp: String = "%04d-%02d-%02d %02d:%02d:%02d" % [
			time_dict["year"], time_dict["month"], time_dict["day"],
			time_dict["hour"], time_dict["minute"], time_dict["second"]]
		var ts_w: float = font.get_string_size(timestamp, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size).x
		canvas_node.draw_string(font, Vector2(w - margin - ts_w, bottom_y), timestamp, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, col_dim)

	# ── 底部中间：摄像头列表指示 ──
	if unlocked.size() > 1:
		var list_y: float = bottom_y - 18
		var indicators: String = ""
		for i in range(unlocked.size()):
			if i == current_camera_index:
				indicators += "[%d] " % (i + 1)
			else:
				indicators += " %d  " % (i + 1)
		var ind_w: float = font.get_string_size(indicators, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size).x
		canvas_node.draw_string(font, Vector2((w - ind_w) * 0.5, list_y), indicators, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, col_dim)

	# ── 异常警告 ──
	if cam.is_anomaly_active() and _rec_blink:
		var warn: String = "! ANOMALY DETECTED !"
		var warn_w: float = font.get_string_size(warn, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var warn_x: float = (w - warn_w) * 0.5
		var warn_y: float = h * 0.25
		canvas_node.draw_rect(Rect2(warn_x - 8, warn_y - font_size - 2, warn_w + 16, font_size + 8), Color(0.6, 0, 0, 0.5))
		canvas_node.draw_string(font, Vector2(warn_x, warn_y), warn, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.2, 0.1))

	# ── 操作提示（最底部）──
	var help_y: float = bottom_y
	var help_text: String = ""
	if not _buttons_visible:
		help_text = "双击恢复按钮  |  鼠标拖动平移  |  滚轮缩放"
	else:
		help_text = "鼠标拖动平移  滚轮缩放  R 深度  F 照明"
		if not cam.region_config.is_empty():
			pass  # R 深度已在上面
		help_text += "  Q 退出"
	var help_w: float = font.get_string_size(help_text, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size).x
	# 背景条
	canvas_node.draw_rect(Rect2(0, help_y - small_size - 4, w, small_size + 8), col_bg)
	canvas_node.draw_string(font, Vector2((w - help_w) * 0.5, help_y), help_text, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, Color(0.5, 0.55, 0.5, 0.5))
