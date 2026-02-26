# ============================================================
# typewriter.gd - 打字机效果引擎
# 负责：逐字输出、队列管理、进度条动画、滚动控制
# ★ 支持 CrtmlParser 的 TW 占位符系统
# ============================================================
class_name Typewriter
extends Node

# ============================================================
# UI 节点引用（由 main.gd 初始化时传入）
# ============================================================
var output_text: RichTextLabel = null
var scroll_container: ScrollContainer = null
var T = null   # ThemeManager.ThemeColors 引用
var main_ref = null  # main.gd 引用，用于调用效果触发接口

# ============================================================
# 打字机状态
# ============================================================
var queue: Array[Dictionary] = []       # 待显示的文本队列
var is_typing: bool = false             # 是否正在打字
var instant: bool = false               # 是否跳过动画（用户按了空格/ESC）
var _noskip: bool = false   # ★ 是否处于强制不可跳过区域

# ============================================================
# 速度参数
# ============================================================
var base_speed: float = 0.008            # 基础打字速度
var pause_chance: float = 0.08           # 随机停顿概率
var pause_duration: float = 0.06         # 随机停顿时长
var comma_pause: float = 0.04            # 逗号/分号后的停顿
var period_pause: float = 0.08           # 句号/冒号/换行后的停顿
var progress_bar_speed: float = 1.0      # 进度条基础速度倍率
var _current_char_speed: float = 0.008   # 当前生效速度（可被 speed 控制）

# ============================================================
# TW 占位符常量（与 CrtmlParser 保持一致）
# ============================================================
const _TW_CHAR: String = "\u0001"
const _TW_END: String = "\u0002"


# ============================================================
# 信号
# ============================================================
signal typing_completed      # 一段或全部文本打字完成时发出
signal progress_completed    # 进度条动画完成时发出



# ============================================================
# 滚动控制
# ============================================================
var _needs_scroll: bool = false
var _scroll_delay: int = 0  # 延迟帧计数器

# ============================================================
# 初始化
# ============================================================
func setup(p_output: RichTextLabel, p_scroll: ScrollContainer, p_main = null) -> void:
	output_text = p_output
	scroll_container = p_scroll
	T = ThemeManager.current
	main_ref = p_main

# ============================================================
# 外部接口：追加文本到队列
# ============================================================
func append(text: String, extra_newline: bool = true) -> void:
	queue.append({"text": text, "extra_newline": extra_newline})
	if not is_typing:
		_process_queue()

# ============================================================
# 队列处理
# ============================================================
func _process_queue() -> void:
	if queue.is_empty():
		is_typing = false
		typing_completed.emit()
		return
	is_typing = true
	var entry = queue.pop_front()
	var text: String = entry["text"]
	var extra_newline: bool = entry["extra_newline"]
	if instant:
		# ★ 跳过模式：用循环处理所有队列项，避免深度递归
		var clean_text: String = _strip_tw_tags(text)
		output_text.append_text(clean_text)
		if extra_newline:
			output_text.append_text("\n")
		while not queue.is_empty():
			var next_entry = queue.pop_front()
			var next_text: String = _strip_tw_tags(next_entry["text"])
			output_text.append_text(next_text)
			if next_entry["extra_newline"]:
				output_text.append_text("\n")
		_do_scroll()
		is_typing = false
		typing_completed.emit()
	else:
		_typewrite_text(text, extra_newline)


# ============================================================
# ★ 剥离所有 TW 占位符（用于 skip 模式）
# ============================================================
func _strip_tw_tags(text: String) -> String:
	var result: String = ""
	var i: int = 0
	while i < text.length():
		if text[i] == _TW_CHAR:
			# 找到 \u0002 结束符，跳过整个占位符
			var end_pos: int = text.find(_TW_END, i)
			if end_pos != -1:
				i = end_pos + 1
				continue
		result += text[i]
		i += 1
	return result

# ============================================================
# ★ 解析 TW 占位符，返回 tag 名和值
# ============================================================
func _parse_tw_tag(text: String, start: int) -> Dictionary:
	# 格式: \u0001TW:tag=value\u0002 或 \u0001TW:tag\u0002
	var end_pos: int = text.find(_TW_END, start)
	if end_pos == -1:
		return {}
	# 提取 "TW:tag=value" 部分
	var inner: String = text.substr(start + 1, end_pos - start - 1)
	if not inner.begins_with("TW:"):
		return {}
	inner = inner.substr(3)  # 去掉 "TW:"
	var tag_name: String = inner
	var tag_value: String = ""
	var eq_pos: int = inner.find("=")
	if eq_pos != -1:
		tag_name = inner.substr(0, eq_pos)
		tag_value = inner.substr(eq_pos + 1)
	return {
		"tag": tag_name,
		"value": tag_value,
		"end": end_pos + 1  # 占位符结束后的下一个字符位置
	}

# ============================================================
# 逐字输出核心逻辑
# ============================================================
func _typewrite_text(text: String, extra_newline: bool = true) -> void:
	var i: int = 0
	var length: int = text.length()
	_current_char_speed = base_speed

	while i < length:
		# 如果中途切换为即时模式，把剩余文本一次性输出
		if instant:
			var remaining: String = _strip_tw_tags(text.substr(i))
			output_text.append_text(remaining)
			break

		# ★ 检查是否是 TW 占位符（\u0001 开头）
		if text[i] == _TW_CHAR:
			var tw_info: Dictionary = _parse_tw_tag(text, i)
			if not tw_info.is_empty():
				match tw_info["tag"]:
					"noskip":
						_noskip = true
					"noskip_end":
						_noskip = false
					"speed":
						var new_speed: float = tw_info["value"].to_float()
						if new_speed > 0.0:
							_current_char_speed = new_speed
					"speed_end":
						_current_char_speed = base_speed
					"pause":
						var pause_value: float = tw_info["value"].to_float()
						if not instant and pause_value > 0.0:
							var pause_seconds: float = pause_value / 1000.0 if pause_value > 1.0 else pause_value
							pause_seconds = clampf(pause_seconds, 0.0, 30.0)
							await get_tree().create_timer(pause_seconds).timeout
					"clear":
						output_text.text = ""
						_do_scroll()
					# ── 第五阶段：CRT Shader 内联效果 ──
					"fx_glitch":
						_fx_glitch_start(tw_info["value"])
					"fx_glitch_end":
						_fx_glitch_stop()
					"fx_shake":
						_fx_shake_start(tw_info["value"])
					"fx_shake_end":
						_fx_shake_stop()
					"fx_tear":
						_fx_tear_start(tw_info["value"])
					"fx_tear_end":
						_fx_tear_stop()
					"fx_noise":
						_fx_noise_start(tw_info["value"])
					"fx_noise_end":
						_fx_noise_stop()
					"fx_effect":
						_fx_play_effect(tw_info["value"])
					"fx_preset":
						_fx_play_preset(tw_info["value"])
					"fx_blackscreen":
						_fx_blackscreen(tw_info["value"])
					"fx_reboot":
						_fx_reboot()
					"fx_sound":
						_fx_sound(tw_info["value"])

				i = tw_info["end"]
				continue
			# 无法解析的占位符，跳过这个字符
			i += 1
			continue

		# 检查是否是BBCode标签
		if text[i] == "[":
			var close_bracket: int = text.find("]", i)
			if close_bracket != -1:
				var tag: String = text.substr(i, close_bracket - i + 1)

				# ── 兼容旧格式：自定义速度标签 [speed=0.05] ──
				if tag.begins_with("[speed="):
					var speed_str: String = tag.substr(7, tag.length() - 8)
					var new_speed: float = speed_str.to_float()
					if new_speed > 0.0:
						_current_char_speed = new_speed
					i = close_bracket + 1
					continue
				elif tag == "[/speed]":
					_current_char_speed = base_speed
					i = close_bracket + 1
					continue

				# ── 兼容旧格式：暂停标签 [pause=500] ──
				elif tag.begins_with("[pause="):
					var pause_str: String = tag.substr(7, tag.length() - 8)
					var pause_value: float = pause_str.to_float()
					if not instant:
						var pause_seconds: float = pause_value / 1000.0 if pause_value > 1.0 else pause_value
						pause_seconds = clampf(pause_seconds, 0.0, 30.0)
						if pause_seconds > 0.0:
							await get_tree().create_timer(pause_seconds).timeout
					i = close_bracket + 1
					continue

				# ── 兼容旧格式：清屏标签 [clear] ──
				elif tag == "[clear]":
					output_text.text = ""
					_do_scroll()
					i = close_bracket + 1
					continue

				# ── 判断是否是合法的BBCode标签 ──
				var tag_inner: String = tag.substr(1, tag.length() - 2)
				if tag_inner.length() > 0:
					var first_char: int = tag_inner[0].unicode_at(0)
					# A-Z: 65-90, a-z: 97-122, 或者是闭合标签 /
					var is_valid_bbcode: bool = (tag_inner[0] == "/") or (first_char >= 65 and first_char <= 90) or (first_char >= 97 and first_char <= 122)
					if is_valid_bbcode:
						output_text.append_text(tag)
						i = close_bracket + 1
						continue

			# 不是BBCode标签，转义方括号后逐字输出
			output_text.append_text("[lb]")
			i += 1
			continue

		# 普通字符
		var ch: String = text[i]

		# 换行符批量处理
		if ch == "\n":
			var newlines: String = "\n"
			i += 1
			while i < length and text[i] == "\n":
				newlines += "\n"
				i += 1
			output_text.append_text(newlines)
			if not instant:
				await get_tree().create_timer(period_pause).timeout
			_do_scroll()
			continue

		# ★ 跳过不可见的控制字符（\u0002 等残留）
		if ch.unicode_at(0) < 32 and ch != "\n" and ch != "\r" and ch != "\t":
			i += 1
			continue

		output_text.append_text(ch)
		i += 1

		# 根据字符类型决定延迟
		var delay: float = _current_char_speed
		if ch in ["，", "。", "；", "：", "！", "？", ",", ".", ";", ":", "!", "?"]:
			delay += period_pause
		elif ch in ["、", "—", "-", "…"]:
			delay += comma_pause
		else:
			if randf() < pause_chance:
				delay += pause_duration

		await get_tree().create_timer(delay).timeout

		# 每隔几个字符滚动一次
		if i % 8 == 0:
			_do_scroll()

	# 当前文本打完
	if extra_newline:
		output_text.append_text("\n")
	_do_scroll()

	# 继续处理队列
	_process_queue()

# ============================================================
# 进度条动画
# ============================================================
func show_progress_bar(file_size: int, speed_override: float = -1.0) -> void:
	var bar_width: int = 30
	var speed: float = progress_bar_speed
	if speed_override > 0.0:
		speed = speed_override

	var base_delay: float = clamp(float(file_size) / 5000.0, 0.01, 0.08)
	base_delay /= speed

	var bar_color: String = T.primary_hex if T != null else "#33FF33"

	if output_text.get_parsed_text().length() > 0:
		output_text.append_text("\n")

	output_text.append_text("[color=" + bar_color + "]加载中 [[/color]")

	for i in range(bar_width):
		if instant:
			var remaining: int = bar_width - i
			output_text.append_text("[color=" + bar_color + "]" + "█".repeat(remaining) + "[/color]")
			break
		output_text.append_text("[color=" + bar_color + "]█[/color]")
		_do_scroll()

		var jitter: float = randf_range(0.7, 1.5)
		await get_tree().create_timer(base_delay * jitter).timeout

	output_text.append_text("[color=" + bar_color + "]] 完成[/color]\n")
	_do_scroll()
	progress_completed.emit()


# ============================================================
# 滚动控制
# ============================================================
func _do_scroll() -> void:
	_needs_scroll = true
	_scroll_delay = 2

func process_scroll() -> void:
	if _needs_scroll:
		if _scroll_delay > 0:
			_scroll_delay -= 1
			return
		_needs_scroll = false
		var v_scroll: VScrollBar = scroll_container.get_v_scroll_bar()
		if v_scroll:
			scroll_container.scroll_vertical = int(v_scroll.max_value)
		var rt_vscroll := output_text.get_v_scroll_bar()
		if rt_vscroll:
			rt_vscroll.value = rt_vscroll.max_value

# ============================================================
# 重置
# ============================================================
func clear_queue() -> void:
	queue.clear()
	is_typing = false
	instant = false
	_noskip = false
	stop_all_fx()  # ★ 清理所有持续效果


# ============================================================
# ★ 第五阶段：CRT Shader 内联效果执行方法
# ============================================================

# ── 活跃的持续效果追踪 ──
var _active_fx_glitch: bool = false
var _active_fx_shake: bool = false
var _active_fx_tear: bool = false
var _active_fx_noise: bool = false

func _fx_glitch_start(value: String) -> void:
	_active_fx_glitch = true
	if main_ref == null or not main_ref.has_method("trigger_glitch"):
		return
	var presets: Array[String] = ["subtle", "moderate", "heavy", "chaos"]
	var stripped: String = value.strip_edges().to_lower()
	if stripped in presets:
		var preset_intensity: float = 0.5
		match stripped:
			"subtle": preset_intensity = 0.2
			"moderate": preset_intensity = 0.5
			"heavy": preset_intensity = 0.8
			"chaos": preset_intensity = 1.0
		main_ref.trigger_glitch(preset_intensity, 99.0, stripped)
	else:
		var intensity: float = clampf(value.to_float(), 0.1, 2.0) if not value.is_empty() else 0.5
		main_ref.trigger_glitch(intensity, 99.0)

func _fx_glitch_stop() -> void:
	_active_fx_glitch = false
	if main_ref == null:
		return
	# 通过触发一个极短的零强度 glitch 来重置
	if main_ref.has_method("trigger_glitch"):
		main_ref.trigger_glitch(0.0, 0.05)

func _fx_shake_start(value: String) -> void:
	_active_fx_shake = true
	if main_ref == null or not main_ref.has_method("trigger_shake"):
		return
	var intensity: float = clampf(value.to_float(), 0.001, 0.1) if not value.is_empty() else 0.01
	main_ref.trigger_shake(intensity, 99.0)

func _fx_shake_stop() -> void:
	_active_fx_shake = false
	if main_ref == null:
		return
	if main_ref.has_method("trigger_shake"):
		main_ref.trigger_shake(0.0, 0.05)

func _fx_tear_start(value: String) -> void:
	_active_fx_tear = true
	if main_ref == null or not main_ref.has_method("trigger_tear"):
		return
	var strength: float = clampf(value.to_float(), 0.01, 0.15) if not value.is_empty() else 0.08
	main_ref.trigger_tear(strength, 99.0)

func _fx_tear_stop() -> void:
	_active_fx_tear = false
	if main_ref == null:
		return
	if main_ref.has_method("trigger_tear"):
		main_ref.trigger_tear(0.0, 0.05)

func _fx_noise_start(value: String) -> void:
	_active_fx_noise = true
	if main_ref == null or not main_ref.has_method("trigger_noise_burst"):
		return
	var intensity: float = clampf(value.to_float(), 0.1, 1.0) if not value.is_empty() else 0.8
	main_ref.trigger_noise_burst(intensity, 99.0)

func _fx_noise_stop() -> void:
	_active_fx_noise = false
	if main_ref == null:
		return
	if main_ref.has_method("trigger_noise_burst"):
		main_ref.trigger_noise_burst(0.0, 0.05)

func _fx_play_effect(effect_id: String) -> void:
	if main_ref == null or not main_ref.has_method("trigger_effect"):
		return
	main_ref.trigger_effect(effect_id.strip_edges())

func _fx_play_preset(preset_name: String) -> void:
	if main_ref == null or not main_ref.has_method("trigger_preset_effect"):
		return
	main_ref.trigger_preset_effect(preset_name.strip_edges())

func _fx_blackscreen(value: String) -> void:
	if main_ref == null or not main_ref.has_method("trigger_screen_off"):
		return
	var duration_ms: float = value.to_float() if not value.is_empty() else 2000.0
	main_ref.trigger_screen_off(duration_ms / 1000.0)

func _fx_reboot() -> void:
	if main_ref == null or not main_ref.has_method("trigger_reboot"):
		return
	main_ref.trigger_reboot()

func _fx_sound(path: String) -> void:
	if main_ref == null:
		return
	# 通过 effect_system 的 sound 步骤或直接调用 audio_manager
	if main_ref.has_method("trigger_effect"):
		# 构造临时效果数据
		if "effect_sys" in main_ref and main_ref.effect_sys != null:
			main_ref.effect_sys.play("_inline_sound_" + path, {
				"steps": [
					{"time": 0.0, "action": "sound", "params": {"path": path.strip_edges()}}
				]
			})

## ★ 停止所有活跃的持续效果（在文档关闭/跳过时调用）
func stop_all_fx() -> void:
	if _active_fx_glitch:
		_fx_glitch_stop()
	if _active_fx_shake:
		_fx_shake_stop()
	if _active_fx_tear:
		_fx_tear_stop()
	if _active_fx_noise:
		_fx_noise_stop()



func skip() -> void:
	if _noskip:
		return
	instant = true
	stop_all_fx()  # ★ 跳过时也清理持续效果


	
