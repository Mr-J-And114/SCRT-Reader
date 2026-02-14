# ============================================================
# theme_manager.gd - 全局颜色主题管理
# ============================================================
class_name ThemeManager
extends RefCounted

# ============================================================
# 主题配置结构
# ============================================================
class ThemeColors:
	var primary: Color
	var secondary: Color
	var dim: Color
	var success: Color
	var warning: Color
	var error: Color
	var info: Color
	var muted: Color
	var bg: Color
	var bg_panel: Color
	var border: Color
	var input_text: Color
	var selection_bg: Color

	# Shader 相关参数
	var phosphor_color: Color       # CRT磷光色（传给 crt_effect shader）
	var bg_tint_color: Color        # 背景 tint 叠加色
	var logo_tint_color: Color      # Logo tint 叠加色
	var hue_shift: float = 0.0      # 背景/Logo 色相偏移
	var bg_saturation: float = 1.0  # 背景饱和度
	var logo_saturation: float = 1.0 # Logo饱和度

	# BBCode hex 缓存
	var primary_hex: String
	var secondary_hex: String
	var dim_hex: String
	var success_hex: String
	var warning_hex: String
	var error_hex: String
	var info_hex: String
	var muted_hex: String

	func update_hex() -> void:
		primary_hex = "#" + primary.to_html(false)
		secondary_hex = "#" + secondary.to_html(false)
		dim_hex = "#" + dim.to_html(false)
		success_hex = "#" + success.to_html(false)
		warning_hex = "#" + warning.to_html(false)
		error_hex = "#" + error.to_html(false)
		info_hex = "#" + info.to_html(false)
		muted_hex = "#" + muted.to_html(false)

# ============================================================
# 静态状态
# ============================================================
static var current: ThemeColors = null
static var current_theme_name: String = ""
static var _pending_theme_name: String = ""

const THEME_CONFIG_PATH := "user://theme_config.cfg"

# ============================================================
# 初始化
# ============================================================
static func init(default_theme: String = "phosphor_green") -> void:
	var saved_theme: String = _load_saved_theme()
	if saved_theme.is_empty():
		load_theme(default_theme)
	else:
		load_theme(saved_theme)

# ============================================================
# 加载主题
# ============================================================
static func load_theme(theme_name: String) -> void:
	current_theme_name = theme_name
	match theme_name:
		"phosphor_green":
			current = _theme_phosphor_green()
		"amber":
			current = _theme_amber()
		"cool_blue":
			current = _theme_cool_blue()
		"white":
			current = _theme_white()
		_:
			current = _theme_phosphor_green()
			current_theme_name = "phosphor_green"
	current.update_hex()
	print("[Theme] 已加载主题: " + current_theme_name)

# ============================================================
# 持久化
# ============================================================
static func _save_theme_preference(theme_name: String) -> void:
	var config := ConfigFile.new()
	config.set_value("theme", "name", theme_name)
	var err := config.save(THEME_CONFIG_PATH)
	if err == OK:
		print("[Theme] 主题偏好已保存: " + theme_name)

static func _load_saved_theme() -> String:
	var config := ConfigFile.new()
	var err := config.load(THEME_CONFIG_PATH)
	if err == OK:
		var saved: String = config.get_value("theme", "name", "")
		if saved in get_available_themes():
			print("[Theme] 读取到保存的主题偏好: " + saved)
			return saved
	return ""

# ============================================================
# 便捷 BBCode 方法
# ============================================================
static func c_primary(text: String) -> String:
	return "[color=" + current.primary_hex + "]" + text + "[/color]"
static func c_secondary(text: String) -> String:
	return "[color=" + current.secondary_hex + "]" + text + "[/color]"
static func c_dim(text: String) -> String:
	return "[color=" + current.dim_hex + "]" + text + "[/color]"
static func c_success(text: String) -> String:
	return "[color=" + current.success_hex + "]" + text + "[/color]"
static func c_warning(text: String) -> String:
	return "[color=" + current.warning_hex + "]" + text + "[/color]"
static func c_error(text: String) -> String:
	return "[color=" + current.error_hex + "]" + text + "[/color]"
static func c_info(text: String) -> String:
	return "[color=" + current.info_hex + "]" + text + "[/color]"
static func c_muted(text: String) -> String:
	return "[color=" + current.muted_hex + "]" + text + "[/color]"

# ============================================================
# 磷光绿（默认）
# ============================================================
static func _theme_phosphor_green() -> ThemeColors:
	var t := ThemeColors.new()
	t.primary = Color(0.6, 1.0, 0.6, 1.0)
	t.secondary = Color(0.4, 0.9, 0.4, 1.0)
	t.dim = Color(0.25, 0.6, 0.25, 1.0)
	t.success = Color(0.5, 1.0, 0.5, 1.0)
	t.warning = Color(1.0, 0.85, 0.4, 1.0)
	t.error = Color(1.0, 0.45, 0.45, 1.0)
	t.info = Color(0.5, 0.75, 1.0, 1.0)
	t.muted = Color(0.55, 0.75, 0.55, 1.0)
	t.bg = Color(0.01, 0.03, 0.01, 1.0)
	t.bg_panel = Color(0.0, 0.04, 0.0, 0.9)
	t.border = Color(0.3, 0.7, 0.3, 0.4)
	t.input_text = Color(0.6, 1.0, 0.6, 1.0)
	t.selection_bg = Color(0.3, 0.6, 0.3, 0.5)
	# Shader 参数
	t.phosphor_color = Color(0.1, 1.0, 0.3)
	t.bg_tint_color = Color(0.1, 0.3, 0.1, 0.15)
	t.logo_tint_color = Color(0.1, 0.3, 0.1, 0.15)
	t.hue_shift = 0.0
	t.bg_saturation = 1.0
	t.logo_saturation = 1.0
	return t

# ============================================================
# 琥珀色
# ============================================================
static func _theme_amber() -> ThemeColors:
	var t := ThemeColors.new()
	t.primary = Color(1.0, 0.85, 0.4, 1.0)
	t.secondary = Color(0.9, 0.75, 0.3, 1.0)
	t.dim = Color(0.6, 0.5, 0.2, 1.0)
	t.success = Color(0.6, 1.0, 0.4, 1.0)
	t.warning = Color(1.0, 0.95, 0.5, 1.0)
	t.error = Color(1.0, 0.4, 0.3, 1.0)
	t.info = Color(1.0, 0.9, 0.6, 1.0)
	t.muted = Color(0.7, 0.6, 0.35, 1.0)
	t.bg = Color(0.03, 0.02, 0.0, 1.0)
	t.bg_panel = Color(0.04, 0.03, 0.0, 0.9)
	t.border = Color(0.7, 0.55, 0.2, 0.4)
	t.input_text = Color(1.0, 0.85, 0.4, 1.0)
	t.selection_bg = Color(0.5, 0.4, 0.15, 0.5)
	# Shader 参数
	t.phosphor_color = Color(1.0, 0.7, 0.1)
	t.bg_tint_color = Color(0.3, 0.2, 0.05, 0.15)
	t.logo_tint_color = Color(0.3, 0.2, 0.05, 0.15)
	t.hue_shift = -0.25
	t.bg_saturation = 1.0
	t.logo_saturation = 1.0
	return t

# ============================================================
# 冷蓝
# ============================================================
static func _theme_cool_blue() -> ThemeColors:
	var t := ThemeColors.new()
	t.primary = Color(0.5, 0.8, 1.0, 1.0)
	t.secondary = Color(0.4, 0.7, 0.95, 1.0)
	t.dim = Color(0.25, 0.45, 0.65, 1.0)
	t.success = Color(0.4, 1.0, 0.7, 1.0)
	t.warning = Color(1.0, 0.85, 0.4, 1.0)
	t.error = Color(1.0, 0.45, 0.45, 1.0)
	t.info = Color(0.6, 0.85, 1.0, 1.0)
	t.muted = Color(0.5, 0.65, 0.8, 1.0)
	t.bg = Color(0.01, 0.02, 0.04, 1.0)
	t.bg_panel = Color(0.0, 0.02, 0.05, 0.9)
	t.border = Color(0.3, 0.5, 0.8, 0.4)
	t.input_text = Color(0.5, 0.8, 1.0, 1.0)
	t.selection_bg = Color(0.2, 0.4, 0.6, 0.5)
	# Shader 参数
	t.phosphor_color = Color(0.2, 0.6, 1.0)
	t.bg_tint_color = Color(0.05, 0.1, 0.3, 0.15)
	t.logo_tint_color = Color(0.05, 0.1, 0.3, 0.15)
	t.hue_shift = 0.22
	t.bg_saturation = 1.0
	t.logo_saturation = 1.0
	return t

# ============================================================
# 纯白
# ============================================================
static func _theme_white() -> ThemeColors:
	var t := ThemeColors.new()
	t.primary = Color(0.95, 0.95, 0.95, 1.0)
	t.secondary = Color(0.8, 0.8, 0.8, 1.0)
	t.dim = Color(0.5, 0.5, 0.5, 1.0)
	t.success = Color(0.4, 1.0, 0.4, 1.0)
	t.warning = Color(1.0, 0.85, 0.3, 1.0)
	t.error = Color(1.0, 0.4, 0.4, 1.0)
	t.info = Color(0.5, 0.75, 1.0, 1.0)
	t.muted = Color(0.6, 0.6, 0.6, 1.0)
	t.bg = Color(0.02, 0.02, 0.02, 1.0)
	t.bg_panel = Color(0.03, 0.03, 0.03, 0.9)
	t.border = Color(0.5, 0.5, 0.5, 0.4)
	t.input_text = Color(0.95, 0.95, 0.95, 1.0)
	t.selection_bg = Color(0.4, 0.4, 0.4, 0.5)
	# Shader 参数
	t.phosphor_color = Color(0.9, 0.9, 0.9)
	t.bg_tint_color = Color(0.2, 0.2, 0.2, 0.15)
	t.logo_tint_color = Color(0.2, 0.2, 0.2, 0.15)
	t.hue_shift = 0.0
	t.bg_saturation = 0.1
	t.logo_saturation = 0.1
	return t

# ============================================================
# 获取所有可用主题
# ============================================================
static func get_available_themes() -> Array[String]:
	return ["phosphor_green", "amber", "cool_blue", "white"] as Array[String]

# ============================================================
# 显示主题列表
# ============================================================
static func show_themes(main_node: Node) -> void:
	var p: String = current.primary_hex
	var m: String = current.muted_hex
	var themes: Array[String] = get_available_themes()
	var lines: Array[String] = []
	lines.append("[color=" + p + "]═══════════ 可用主题 ═══════════[/color]")
	for theme_name in themes:
		var marker: String = " ◄ 当前" if theme_name == current_theme_name else ""
		var preview: String = _get_theme_preview(theme_name)
		lines.append("  [color=" + p + "]" + theme_name + "[/color]  " + preview + "[color=" + m + "]" + marker + "[/color]")
	lines.append("[color=" + p + "]════════════════════════════════[/color]")
	lines.append("[color=" + m + "]用法: theme <主题名>[/color]")
	main_node.append_output("\n".join(lines) + "\n", false)

static func _get_theme_preview(theme_name: String) -> String:
	var preview_color: String
	match theme_name:
		"phosphor_green": preview_color = "#33FF33"
		"amber": preview_color = "#FFB000"
		"cool_blue": preview_color = "#66CCFF"
		"white": preview_color = "#CCCCCC"
		_: preview_color = "#FFFFFF"
	return "[color=" + preview_color + "]████[/color] "

# ============================================================
# 请求切换主题（确认模式）
# ============================================================
static func request_theme_change(theme_name: String, main_node: Node) -> void:
	var themes: Array[String] = get_available_themes()
	if theme_name not in themes:
		var err_hex: String = current.error_hex if current != null else "#FF3333"
		var m_hex: String = current.muted_hex if current != null else "#666666"
		main_node.append_output("[color=" + err_hex + "][ERROR] 未知主题: " + theme_name + "[/color]\n", false)
		main_node.append_output("[color=" + m_hex + "]可用主题: " + ", ".join(themes) + "[/color]\n", false)
		return
	if theme_name == current_theme_name:
		main_node.append_output("[color=" + current.muted_hex + "]当前已是 " + theme_name + " 主题。[/color]\n", false)
		return

	_pending_theme_name = theme_name
	var w: String = current.warning_hex
	var m: String = current.muted_hex
	var p: String = current.primary_hex
	var preview: String = _get_theme_preview(theme_name)
	main_node.append_output("[color=" + w + "]切换主题需要重启终端才能完全生效。[/color]\n", false)
	main_node.append_output("[color=" + p + "]目标主题: [/color]" + preview + "[color=" + p + "]" + theme_name + "[/color]\n", false)
	main_node.append_output("[color=" + w + "]终端将自动重启，当前屏幕内容将被清空。[/color]\n", false)
	main_node.append_output("[color=" + m + "]确认切换？输入 Y 确认，其它任意键取消：[/color]\n", false)
	main_node._theme_confirm_mode = true

# ============================================================
# 确认并应用
# ============================================================
static func confirm_and_apply(main_node: Node) -> void:
	if _pending_theme_name.is_empty():
		return
	var new_name: String = _pending_theme_name
	_pending_theme_name = ""
	_save_theme_preference(new_name)
	load_theme(new_name)
	main_node.T = current
	_refresh_all_ui(main_node)
	var p: String = current.primary_hex
	main_node.append_output("[color=" + p + "]主题已切换为: " + new_name + "[/color]\n", false)
	main_node.append_output("[color=" + current.muted_hex + "]正在重启终端...[/color]\n", false)

static func cancel_theme_change(main_node: Node) -> void:
	_pending_theme_name = ""
	main_node.append_output("[color=" + current.muted_hex + "]已取消主题切换。[/color]\n", false)

static func get_pending_theme() -> String:
	return _pending_theme_name

# ============================================================
# 刷新所有 UI + Shader
# ============================================================
static func _refresh_all_ui(main_node: Node) -> void:
	# 刷新各模块的 T 引用
	if main_node.cmd_handler != null:
		main_node.cmd_handler.T = current
	if main_node.disc_mgr != null:
		main_node.disc_mgr.T = current
	if main_node.user_mgr != null:
		main_node.user_mgr.T = current
	if main_node.crtml != null:
		main_node.crtml.T = current
	if main_node.tw != null:
		main_node.tw.T = current

	# 重新应用 UI 样式
	UIManager.setup_all_styles(
		main_node.status_frame,
		main_node.path_label,
		main_node.mail_icon,
		main_node.input_frame,
		main_node.input_field,
		main_node.output_text,
		main_node.scroll_container
	)

	# 刷新状态栏
	main_node._update_status_bar()

	# 刷新 RichTextLabel 默认文字颜色
	if current != null:
		main_node.output_text.add_theme_color_override("default_color", current.secondary)

	# 刷新 > 提示符颜色
	var prompt_node = main_node.get_node_or_null("MainContent/InputFrame/InputArea/Prompt")
	if prompt_node != null:
		prompt_node.add_theme_color_override("font_color", current.primary)


	# 重新应用鼠标光标
	UIManager.setup_custom_cursor(main_node)

	# 刷新所有 Shader
	_refresh_crt_shader(main_node)
	_refresh_background_shader(main_node)
	_refresh_logo_shader(main_node)

# ============================================================
# 刷新 CRT 后处理 Shader
# ============================================================
# ============================================================
# 刷新 CRT 后处理 Shader
# ============================================================
static func _refresh_crt_shader(main_node: Node) -> void:
	# CRT 结构是 CanvasLayer -> ColorRect(带ShaderMaterial)
	# 所以需要找到 CanvasLayer 下的 ColorRect 子节点
	var crt_layer: Node = null
	for name in ["CRTEffect", "CRTShader", "CRT"]:
		crt_layer = main_node.get_node_or_null(name)
		if crt_layer != null:
			break

	if crt_layer == null:
		print("[Theme] 未找到 CRT 效果节点")
		return

	# 如果找到的节点本身就是 CanvasItem 且有 material，直接用
	# 否则在其子节点中查找带 ShaderMaterial 的 CanvasItem
	var target_node: CanvasItem = null

	if crt_layer is CanvasItem and crt_layer.material is ShaderMaterial:
		target_node = crt_layer as CanvasItem
	else:
		# 遍历子节点查找带 ShaderMaterial 的 CanvasItem（通常是 ColorRect）
		for child in crt_layer.get_children():
			if child is CanvasItem and child.material is ShaderMaterial:
				target_node = child as CanvasItem
				break

	if target_node == null:
		print("[Theme] CRT 节点下未找到带 ShaderMaterial 的子节点")
		return

	var shader_mat: ShaderMaterial = target_node.material as ShaderMaterial
	if current != null:
		var pc: Color = current.phosphor_color
		shader_mat.set_shader_parameter("phosphor_color", Vector3(pc.r, pc.g, pc.b))
		print("[Theme] CRT phosphor_color 已更新: ", Vector3(pc.r, pc.g, pc.b))



# ============================================================
# 刷新背景图 Shader
# ============================================================
static func _refresh_background_shader(main_node: Node) -> void:
	# 从场景树查找实际的背景节点（注意你的节点可能叫 Backgrund）
	var bg_node: Node = null
	for name in ["Backgrund", "Background", "BG"]:
		bg_node = main_node.get_node_or_null(name)
		if bg_node != null:
			break

	if bg_node == null:
		print("[Theme] 未找到背景节点")
		return

	var mat = bg_node.material
	if mat == null or not mat is ShaderMaterial:
		# 可能 material 在子节点上
		print("[Theme] 背景节点没有 ShaderMaterial，尝试子节点...")
		for child in bg_node.get_children():
			if child is CanvasItem and child.material is ShaderMaterial:
				mat = child.material
				break

	if mat == null or not mat is ShaderMaterial:
		print("[Theme] 背景节点未找到有效的 ShaderMaterial")
		return

	var shader_mat: ShaderMaterial = mat as ShaderMaterial
	if current != null:
		shader_mat.set_shader_parameter("hue_shift", current.hue_shift)
		shader_mat.set_shader_parameter("saturation", current.bg_saturation)
		shader_mat.set_shader_parameter("tint_color", current.bg_tint_color)
		print("[Theme] 背景 Shader 已更新: hue_shift=", current.hue_shift, " sat=", current.bg_saturation)

# ============================================================
# 刷新 Logo Shader
# ============================================================
static func _refresh_logo_shader(main_node: Node) -> void:
	# 递归查找名为 BackgroundLogo 的节点
	var logo_node: Node = _find_node_recursive(main_node, "BackgroundLogo")

	if logo_node == null:
		print("[Theme] 未找到 BackgroundLogo 节点")
		return

	var mat = logo_node.material
	if mat == null or not mat is ShaderMaterial:
		print("[Theme] BackgroundLogo 节点没有 ShaderMaterial")
		return

	var shader_mat: ShaderMaterial = mat as ShaderMaterial
	if current != null:
		shader_mat.set_shader_parameter("hue_shift", current.hue_shift)
		shader_mat.set_shader_parameter("saturation", current.logo_saturation)
		shader_mat.set_shader_parameter("tint_color", current.logo_tint_color)
		print("[Theme] Logo Shader 已更新: hue_shift=", current.hue_shift, " sat=", current.logo_saturation)

# ============================================================
# 辅助：递归查找节点
# ============================================================
static func _find_node_recursive(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child in root.get_children():
		var found: Node = _find_node_recursive(child, target_name)
		if found != null:
			return found
	return null
