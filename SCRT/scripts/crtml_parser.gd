# crtml_parser.gd
# 职责：解析 CRT-ML 自定义标记语言，转换为 BBCode
class_name CrtmlParser
extends RefCounted

var T = null  # ThemeManager

## 初始化
func setup(p_theme) -> void:
	T = p_theme

## 主解析函数：将 CRT-ML 转换为 BBCode
func parse(raw_text: String) -> String:
	var result: String = raw_text

	# 阶段1：处理特殊 SCP 标记
	result = _parse_redacted(result)
	result = _parse_expunged(result)

	# 阶段2：处理格式标记
	result = _parse_headers(result)
	result = _parse_separators(result)
	result = _parse_classified(result)
	result = _parse_colors(result)
	result = _parse_bold(result)
	result = _parse_italic(result)

	# 阶段3：处理特效标记
	result = _parse_glitch(result)

	return result

## [REDACTED] -> 黑底黑字的遮挡效果
func _parse_redacted(text: String) -> String:
	var regex: RegEx = RegEx.new()
	regex.compile("\\[REDACTED(?::([^\\]]*))?\\]")
	var results: Array[RegExMatch] = regex.search_all(text)

	# 从后向前替换，避免偏移问题
	for i in range(results.size() - 1, -1, -1):
		var match_result: RegExMatch = results[i]
		var hidden_text: String = match_result.get_string(1)
		if hidden_text.is_empty():
			hidden_text = "██████████"
		else:
			hidden_text = "█".repeat(hidden_text.length())
		var replacement: String = "[bgcolor=black][color=black]" + hidden_text + "[/color][/bgcolor]"
		text = text.substr(0, match_result.get_start()) + replacement + text.substr(match_result.get_end())

	return text

## [DATA EXPUNGED] -> 删除线效果
func _parse_expunged(text: String) -> String:
	text = text.replace("[DATA EXPUNGED]", "[s][color=" + str(T.error_hex) + "]DATA EXPUNGED[/color][/s]")
	return text

## {header}...{/header} -> 标题样式
func _parse_headers(text: String) -> String:
	var regex: RegEx = RegEx.new()
	regex.compile("\\{header(?::(\\d))?\\}(.*?)\\{/header\\}")
	var results: Array[RegExMatch] = regex.search_all(text)

	for i in range(results.size() - 1, -1, -1):
		var match_result: RegExMatch = results[i]
		var level: String = match_result.get_string(1)
		var content: String = match_result.get_string(2)
		var size: int = 24
		if level == "2":
			size = 20
		elif level == "3":
			size = 16
		var replacement: String = "[font_size=" + str(size) + "][b][color=" + str(T.primary_hex) + "]" + content + "[/color][/b][/font_size]"
		text = text.substr(0, match_result.get_start()) + replacement + text.substr(match_result.get_end())

	return text

## {separator} -> 分隔线
func _parse_separators(text: String) -> String:
	var line: String = "[color=" + str(T.muted_hex) + "]" + "─".repeat(50) + "[/color]"
	text = text.replace("{separator}", line)
	text = text.replace("{hr}", line)
	return text

## {classified:N}...{/classified} -> 机密标记框
func _parse_classified(text: String) -> String:
	var regex: RegEx = RegEx.new()
	regex.compile("\\{classified:(\\d)\\}(.*?)\\{/classified\\}")
	var results: Array[RegExMatch] = regex.search_all(text)

	for i in range(results.size() - 1, -1, -1):
		var match_result: RegExMatch = results[i]
		var level: String = match_result.get_string(1)
		var content: String = match_result.get_string(2)
		var border_color: String = str(T.warning_hex)
		if level.to_int() >= 4:
			border_color = str(T.error_hex)
		var replacement: String = "[color=" + border_color + "]╔══ CLASSIFIED LEVEL " + level + " ══╗[/color]\n"
		replacement += content + "\n"
		replacement += "[color=" + border_color + "]╚═══════════════════════╝[/color]"
		text = text.substr(0, match_result.get_start()) + replacement + text.substr(match_result.get_end())

	return text

## {color:xxx}...{/color}
func _parse_colors(text: String) -> String:
	var regex: RegEx = RegEx.new()
	regex.compile("\\{color:([^}]+)\\}(.*?)\\{/color\\}")
	var results: Array[RegExMatch] = regex.search_all(text)

	for i in range(results.size() - 1, -1, -1):
		var match_result: RegExMatch = results[i]
		var color: String = _resolve_color(match_result.get_string(1))
		var content: String = match_result.get_string(2)
		var replacement: String = "[color=" + color + "]" + content + "[/color]"
		text = text.substr(0, match_result.get_start()) + replacement + text.substr(match_result.get_end())

	return text

## {bold}...{/bold}
func _parse_bold(text: String) -> String:
	text = text.replace("{bold}", "[b]").replace("{/bold}", "[/b]")
	text = text.replace("{b}", "[b]").replace("{/b}", "[/b]")
	return text

## {italic}...{/italic}
func _parse_italic(text: String) -> String:
	text = text.replace("{italic}", "[i]").replace("{/italic}", "[/i]")
	text = text.replace("{i}", "[i]").replace("{/i}", "[/i]")
	return text

## {glitch}...{/glitch} -> 故障效果
func _parse_glitch(text: String) -> String:
	var regex: RegEx = RegEx.new()
	regex.compile("\\{glitch\\}(.*?)\\{/glitch\\}")
	var results: Array[RegExMatch] = regex.search_all(text)

	for i in range(results.size() - 1, -1, -1):
		var match_result: RegExMatch = results[i]
		var content: String = match_result.get_string(1)
		var replacement: String = "[color=" + str(T.error_hex) + "][wave amp=3 freq=10]" + content + "[/wave][/color]"
		text = text.substr(0, match_result.get_start()) + replacement + text.substr(match_result.get_end())

	return text

## 解析颜色名称为十六进制
func _resolve_color(color_name: String) -> String:
	color_name = color_name.strip_edges().to_lower()
	match color_name:
		"primary":
			return str(T.primary_hex)
		"error", "red":
			return str(T.error_hex)
		"warning", "yellow":
			return str(T.warning_hex)
		"success", "green":
			return str(T.success_hex)
		"info", "blue":
			return str(T.info_hex)
		"muted", "gray", "grey":
			return str(T.muted_hex)
		_:
			if color_name.begins_with("#"):
				return color_name
			return str(T.primary_hex)
