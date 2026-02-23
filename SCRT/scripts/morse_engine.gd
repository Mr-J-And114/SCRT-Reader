# ============================================================
# morse_engine.gd - 摩斯密码编解码引擎
# 负责：文本→摩斯编码、定时播放、实时解码显示、信号质量影响
# ============================================================
class_name MorseEngine
extends RefCounted
# ══════════════════════════════════════════
#  摩斯密码表
# ══════════════════════════════════════════
const MORSE_ENCODE: Dictionary = {
	"A": ".-",    "B": "-...",  "C": "-.-.",  "D": "-..",
	"E": ".",     "F": "..-.",  "G": "--.",   "H": "....",
	"I": "..",    "J": ".---",  "K": "-.-",   "L": ".-..",
	"M": "--",    "N": "-.",    "O": "---",   "P": ".--.",
	"Q": "--.-",  "R": ".-.",   "S": "...",   "T": "-",
	"U": "..-",   "V": "...-",  "W": ".--",   "X": "-..-",
	"Y": "-.--",  "Z": "--..",
	"0": "-----", "1": ".----", "2": "..---", "3": "...--",
	"4": "....-", "5": ".....", "6": "-....", "7": "--...",
	"8": "---..", "9": "----.",
	".": ".-.-.-", ",": "--..--", "?": "..--..", "!": "-.-.--",
	"/": "-..-.",  "=": "-...-", "+": ".-.-.",  "-": "-....-",
	"(": "-.--.",  ")": "-.--.-",
}
var _morse_decode: Dictionary = {}  # 运行时反向构建
# ══════════════════════════════════════════
#  播放状态
# ══════════════════════════════════════════
## 摩斯事件类型
enum EventType { DIT, DAH, CHAR_GAP, WORD_GAP, PAUSE, END }
## 单个播放事件
class MorseEvent:
	var type: int = EventType.DIT       # EventType
	var character: String = ""           # 对应的原文字符（仅在字符最后一个符号时设置）
	var morse_code: String = ""          # 对应的摩斯码（仅在字符最后时设置）
	var duration_ms: float = 0.0        # 持续时间（毫秒）
var events: Array = []                   # Array[MorseEvent]
var event_index: int = 0
var event_timer: float = 0.0
var is_playing: bool = false
var is_tone_on: bool = false             # 当前是否在发音
var speed_wpm: int = 15
var unit_ms: float = 80.0               # 1 WPM单位时长（毫秒）
# 已解码的内容
var decoded_chars: String = ""           # 完整解码文本
var current_morse: String = ""           # 当前正在接收的摩斯码
var current_char_code: String = ""       # 当前字符的摩斯码（用于显示）
var morse_display_buffer: String = ""    # 摩斯码显示缓冲
var decoded_lines: Array[String] = []    # 已完成的行
var loop: bool = false
var _initialized_decode: bool = false
# ★ 数字电台模式
var numbers_mode: bool = false           # 是否为数字电台模式
var _group_size: int = 5                 # 分组大小
var _group_pause_ms: float = 1500.0      # 组间停顿
var _repeat_count: int = 2              # 重复次数
var _current_repeat: int = 0            # 当前重复轮次
# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func _ensure_decode_table() -> void:
	if _initialized_decode:
		return
	_initialized_decode = true
	for key in MORSE_ENCODE.keys():
		var code: String = MORSE_ENCODE[key]
		_morse_decode[code] = key
func set_speed(wpm: int) -> void:
	speed_wpm = maxi(5, wpm)
	unit_ms = 1200.0 / float(speed_wpm)
## 从明文生成播放事件序列
func load_text(text: String, wpm: int = 15, p_loop: bool = false) -> void:
	_ensure_decode_table()
	set_speed(wpm)
	loop = p_loop
	events.clear()
	event_index = 0
	event_timer = 0.0
	decoded_chars = ""
	current_morse = ""
	current_char_code = ""
	morse_display_buffer = ""
	decoded_lines.clear()
	is_playing = false
	is_tone_on = false
	numbers_mode = false
	_current_repeat = 0
	# 解析文本，支持 {pause=XXX} 指令
	var processed: String = text.strip_edges()
	var segments: Array[String] = []
	var remaining: String = processed
	while true:
		var pause_start: int = remaining.find("{pause=")
		if pause_start == -1:
			if not remaining.is_empty():
				segments.append(remaining)
			break
		if pause_start > 0:
			segments.append(remaining.substr(0, pause_start))
		var pause_end: int = remaining.find("}", pause_start)
		if pause_end == -1:
			segments.append(remaining.substr(pause_start))
			break
		var pause_val: String = remaining.substr(pause_start + 7, pause_end - pause_start - 7)
		segments.append("{PAUSE:" + pause_val + "}")
		remaining = remaining.substr(pause_end + 1)
	# 生成事件
	for segment in segments:
		if segment.begins_with("{PAUSE:"):
			var ms_str: String = segment.substr(7, segment.length() - 8)
			var evt := MorseEvent.new()
			evt.type = EventType.PAUSE
			evt.duration_ms = ms_str.to_float()
			events.append(evt)
			continue
		# 处理普通文本
		var upper: String = segment.to_upper()
		for ci in range(upper.length()):
			var ch: String = upper[ci]
			if ch == " " or ch == "\n" or ch == "\r":
				var gap := MorseEvent.new()
				gap.type = EventType.WORD_GAP
				gap.duration_ms = unit_ms * 7.0
				gap.character = " "
				events.append(gap)
				continue
			# 跳过不可编码字符
			if not MORSE_ENCODE.has(ch):
				continue
			var code: String = MORSE_ENCODE[ch]
			for si in range(code.length()):
				var symbol: String = code[si]
				# 音符事件
				var tone := MorseEvent.new()
				if symbol == ".":
					tone.type = EventType.DIT
					tone.duration_ms = unit_ms
				else:
					tone.type = EventType.DAH
					tone.duration_ms = unit_ms * 3.0
				# 在字符最后一个符号上标记
				if si == code.length() - 1:
					tone.character = ch
					tone.morse_code = code
				events.append(tone)
				# 符号间隔（同一字符内）
				if si < code.length() - 1:
					var sym_gap := MorseEvent.new()
					sym_gap.type = EventType.CHAR_GAP
					sym_gap.duration_ms = unit_ms
					events.append(sym_gap)
			# 字符间隔
			var char_gap := MorseEvent.new()
			char_gap.type = EventType.CHAR_GAP
			char_gap.duration_ms = unit_ms * 3.0
			events.append(char_gap)
	# 结束标记
	var end_evt := MorseEvent.new()
	end_evt.type = EventType.END
	end_evt.duration_ms = 0.0
	events.append(end_evt)
	print("[MorseEngine] 已生成 ", events.size(), " 个播放事件, WPM=", speed_wpm)

## ★ 数字电台专用加载：自动插入分组停顿和重复
func load_numbers_text(text: String, wpm: int = 12, p_loop: bool = true,
		group_size: int = 5, group_pause_ms: float = 1500.0,
		repeat_count: int = 2) -> void:
	_group_size = group_size
	_group_pause_ms = group_pause_ms
	_repeat_count = repeat_count
	_current_repeat = 0
	# 预处理：提取纯数字/字母序列
	var clean: String = ""
	for ch in text.to_upper():
		if MORSE_ENCODE.has(ch):
			clean += ch
	if clean.is_empty():
		load_text(text, wpm, p_loop)
		numbers_mode = true
		return
	# 构建分组文本：每 group_size 个字符插入 {pause=group_pause_ms}
	var grouped: String = ""
	# 开头标识符（模拟真实数字电台的 "消息开始" 信号）
	grouped += "VVV "
	grouped += "{pause=" + str(group_pause_ms) + "}"
	var char_count: int = 0
	for ch in clean:
		grouped += ch
		char_count += 1
		if char_count % group_size == 0:
			grouped += " {pause=" + str(group_pause_ms) + "} "
	# 尾部标识
	grouped += " {pause=" + str(group_pause_ms * 2.0) + "}"
	grouped += "AR"  # 标准结束信号
	# 重复整段（数字电台通常重复播报）
	var full_text: String = ""
	var actual_repeats: int = repeat_count if repeat_count > 0 else 1
	for i in range(actual_repeats):
		if i > 0:
			full_text += " {pause=" + str(group_pause_ms * 3.0) + "} "
		full_text += grouped
	load_text(full_text, wpm, p_loop)
	numbers_mode = true  # load_text 会重置状态，所以在之后再设
	print("[MorseEngine] 数字电台模式: ", clean.length(), " 字符, ",
			group_size, " 字符/组, 重复 ", actual_repeats, " 次")

## 开始播放
func start() -> void:
	if events.is_empty():
		return
	event_index = 0
	event_timer = 0.0
	is_playing = true
	is_tone_on = false

## 从随机位置开始播放（模拟半途截获信号）
func start_from_random() -> void:
	if events.is_empty():
		return
	# 随机选一个事件位置（避免选到尾部）
	var max_start: int = maxi(1, events.size() - 10)
	event_index = randi_range(0, max_start)
	event_timer = 0.0
	is_playing = true
	is_tone_on = false
	# 标记已经跳过的部分为"未知"
	decoded_chars = "(...) "
	morse_display_buffer = "... "

## 停止播放
func stop() -> void:
	is_playing = false
	is_tone_on = false
## 重置
func reset() -> void:
	stop()
	event_index = 0
	event_timer = 0.0
	decoded_chars = ""
	current_morse = ""
	current_char_code = ""
	morse_display_buffer = ""
	decoded_lines.clear()
	numbers_mode = false
	_current_repeat = 0
# ══════════════════════════════════════════
#  每帧更新
# ══════════════════════════════════════════
## 返回: { "tone_on": bool, "finished": bool, "new_char": String }
func process(delta: float, signal_quality: float) -> Dictionary:
	var result: Dictionary = {
		"tone_on": false,
		"finished": false,
		"new_char": "",
	}
	if not is_playing or events.is_empty():
		return result
	event_timer -= delta * 1000.0  # 转为毫秒
	if event_timer > 0.0:
		result["tone_on"] = is_tone_on
		return result
	# 前进到下一事件
	if event_index >= events.size():
		if loop:
			event_index = 0
			decoded_chars = ""
			current_morse = ""
			morse_display_buffer = ""
			decoded_lines.clear()
		else:
			is_playing = false
			is_tone_on = false
			result["finished"] = true
			return result
	var evt: MorseEvent = events[event_index] as MorseEvent
	event_index += 1
	match evt.type:
		EventType.DIT, EventType.DAH:
			is_tone_on = true
			event_timer = evt.duration_ms
			# 记录摩斯码符号
			if evt.type == EventType.DIT:
				current_char_code += "·"
				morse_display_buffer += "·"
			else:
				current_char_code += "−"
				morse_display_buffer += "−"
			# 如果是字符末尾，解码
			if not evt.character.is_empty():
				var decoded: String = _decode_with_quality(evt.character, evt.morse_code, signal_quality)
				decoded_chars += decoded
				result["new_char"] = decoded
				current_char_code = ""
				morse_display_buffer += " "
		EventType.CHAR_GAP:
			is_tone_on = false
			event_timer = evt.duration_ms
		EventType.WORD_GAP:
			is_tone_on = false
			event_timer = evt.duration_ms
			decoded_chars += " "
			morse_display_buffer += "  "
			if not evt.character.is_empty():
				result["new_char"] = " "
		EventType.PAUSE:
			is_tone_on = false
			event_timer = evt.duration_ms
		EventType.END:
			is_playing = false
			is_tone_on = false
			result["finished"] = true
	result["tone_on"] = is_tone_on
	return result
## 根据信号质量决定解码准确性
func _decode_with_quality(original_char: String, _morse_code: String, quality: float) -> String:
	if quality >= 0.8:
		return original_char
	elif quality >= 0.5:
		# 偶尔误码
		if randf() < (1.0 - quality) * 0.5:
			return "?"
		return original_char
	elif quality >= 0.3:
		# 频繁误码
		if randf() < 0.6:
			return "?"
		return original_char
	elif quality >= 0.1:
		# 大部分为 ?
		if randf() < 0.15:
			return original_char
		return "?"
	else:
		return "?"
# ══════════════════════════════════════════
#  查询方法
# ══════════════════════════════════════════
func get_decoded_text() -> String:
	return decoded_chars
func get_morse_display() -> String:
	return morse_display_buffer
func get_progress() -> float:
	if events.is_empty():
		return 0.0
	return float(event_index) / float(events.size())
func is_finished() -> bool:
	return not is_playing and event_index >= events.size()
