# ============================================================
# theme_manager.gd - 全局颜色主题管理
# 所有颜色集中定义，方便一键切换主题
# ============================================================
class_name ThemeManager
extends RefCounted

# ============================================================
# 主题配置结构
# ============================================================
class ThemeColors:
	# 主色调（用于标题、边框、高亮文字）
	var primary: Color
	# 次要色调（用于普通文字、提示）
	var secondary: Color
	# 暗色调（用于背景、不活跃元素）
	var dim: Color
	# 成功色
	var success: Color
	# 警告色
	var warning: Color
	# 错误色
	var error: Color
	# 信息色（目录等）
	var info: Color
	# 灰色/注释色
	var muted: Color
	# 背景色
	var bg: Color
	# 背景色（半透明，用于面板）
	var bg_panel: Color
	# 边框色
	var border: Color
	# 输入框文字色
	var input_text: Color
	# 选中高亮背景色
	var selection_bg: Color

	# BBCode 颜色字符串（缓存，避免重复转换）
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
# 当前激活的主题
# ============================================================
static var current: ThemeColors = null
static var current_theme_name: String = ""

# ============================================================
# 初始化（默认加载 phosphor_green 主题）
# ============================================================
static func init(theme_name: String = "phosphor_green") -> void:
	load_theme(theme_name)

# ============================================================
# 加载指定主题
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
	current.update_hex()
	print("[Theme] 已加载主题: " + theme_name)

# ============================================================
# 便捷方法：用 BBCode 包裹文字
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
# 主题定义：磷光绿（经典CRT终端）
# ============================================================
static func _theme_phosphor_green() -> ThemeColors:
	var t := ThemeColors.new()
	t.primary = Color(0.6, 1.0, 0.6, 1.0)       # #99FF99 浅绿
	t.secondary = Color(0.4, 0.9, 0.4, 1.0)      # #66E566 中绿
	t.dim = Color(0.25, 0.6, 0.25, 1.0)           # #409940 暗绿
	t.success = Color(0.5, 1.0, 0.5, 1.0)         # #80FF80 亮绿
	t.warning = Color(1.0, 0.85, 0.4, 1.0)        # #FFD966 琥珀黄
	t.error = Color(1.0, 0.45, 0.45, 1.0)         # #FF7373 柔红
	t.info = Color(0.5, 0.75, 1.0, 1.0)           # #80BFFF 淡蓝
	t.muted = Color(0.55, 0.75, 0.55, 1.0)        # #8CBF8C 灰绿
	t.bg = Color(0.01, 0.03, 0.01, 1.0)           # 近黑绿
	t.bg_panel = Color(0.0, 0.04, 0.0, 0.9)       # 面板背景
	t.border = Color(0.3, 0.7, 0.3, 0.4)          # 边框绿
	t.input_text = Color(0.6, 1.0, 0.6, 1.0)      # 输入文字浅绿
	t.selection_bg = Color(0.3, 0.6, 0.3, 0.5)    # 选中背景
	return t

# ============================================================
# 主题定义：琥珀色（复古琥珀显示器）
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
	return t

# ============================================================
# 主题定义：冷蓝（现代终端）
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
	return t

# ============================================================
# 主题定义：纯白（高对比）
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
	return t

# ============================================================
# 获取所有可用主题名称
# ============================================================
static func get_available_themes() -> Array[String]:
	return ["phosphor_green", "amber", "cool_blue", "white"]
