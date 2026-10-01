# ============================================================
# theme_manager.gd - 最小化 ThemeManager 桩（仅提供绿色 CRT 主题色）
# ============================================================
class_name ThemeManager
extends RefCounted

static var current: ThemeColors = ThemeColors.new()

class ThemeColors:
	var primary: Color = Color(0.6, 1.0, 0.6)
	var secondary: Color = Color(0.8, 1.0, 0.8)
	var dim: Color = Color(0.4, 0.6, 0.4)
	var success: Color = Color(0.3, 0.9, 0.3)
	var warning: Color = Color(1.0, 0.85, 0.4)
	var error: Color = Color(1.0, 0.4, 0.4)
	var info: Color = Color(0.4, 0.8, 1.0)
	var muted: Color = Color(0.5, 0.6, 0.5)
	var bg: Color = Color(0.047, 0.078, 0.047)
	var bg_panel: Color = Color(0.08, 0.12, 0.08)
	var border: Color = Color(0.2, 0.35, 0.2)
	var input_text: Color = Color(0.7, 0.95, 0.7)
	var selection_bg: Color = Color(0.15, 0.3, 0.15)

	var primary_hex: String = "#99FF99"
	var secondary_hex: String = "#CCFFCC"
	var dim_hex: String = "#669966"
	var success_hex: String = "#4DE64D"
	var warning_hex: String = "#FFD966"
	var error_hex: String = "#FF6666"
	var info_hex: String = "#66CCFF"
	var muted_hex: String = "#809980"

	func update_hex() -> void:
		primary_hex = "#" + primary.to_html(false)
		secondary_hex = "#" + secondary.to_html(false)
		dim_hex = "#" + dim.to_html(false)
		success_hex = "#" + success.to_html(false)
		warning_hex = "#" + warning.to_html(false)
		error_hex = "#" + error.to_html(false)
		info_hex = "#" + info.to_html(false)
		muted_hex = "#" + muted.to_html(false)

	func _init() -> void:
		update_hex()
