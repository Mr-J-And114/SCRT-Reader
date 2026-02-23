# ============================================================
# cipher_decoder.gd - 密码解码引擎
# 支持：凯撒密码、维吉尼亚密码、替换密码、Base64、摩斯电码、ROT13
# ============================================================
class_name CipherDecoder
extends RefCounted

# ══════════════════════════════════════════
#  解码方法枚举
# ══════════════════════════════════════════
enum CipherType {
	CAESAR,
	VIGENERE,
	SUBSTITUTION,
	BASE64,
	MORSE,
	ROT13,
	ATBASH,
	REVERSE,
}

# ══════════════════════════════════════════
#  解码步骤（用于动画展示）
# ══════════════════════════════════════════
class DecodeStep:
	var step_index: int = 0
	var source_char: String = ""        # 原始字符
	var result_char: String = ""        # 解码后字符
	var description: String = ""        # 步骤说明
	var highlight_row: int = -1         # 表格高亮行
	var highlight_col: int = -1         # 表格高亮列
	var shift_value: int = 0            # 移位值（凯撒/维吉尼亚）
	var key_char: String = ""           # 密钥字符（维吉尼亚）
	var extra: Dictionary = {}          # 额外数据

# ══════════════════════════════════════════
#  解码结果
# ══════════════════════════════════════════
class DecodeResult:
	var cipher_type: CipherType = CipherType.CAESAR
	var input_text: String = ""
	var output_text: String = ""
	var key: String = ""
	var steps: Array = []               # Array[DecodeStep]
	var success: bool = true
	var error_message: String = ""
	var metadata: Dictionary = {}       # 额外元数据（如凯撒的最佳偏移）

# ══════════════════════════════════════════
#  常量
# ══════════════════════════════════════════
const ALPHABET_UPPER: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const ALPHABET_LOWER: String = "abcdefghijklmnopqrstuvwxyz"

const MORSE_TABLE: Dictionary = {
	"A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".",
	"F": "..-.", "G": "--.", "H": "....", "I": "..", "J": ".---",
	"K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---",
	"P": ".--.", "Q": "--.-", "R": ".-.", "S": "...", "T": "-",
	"U": "..-", "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--",
	"Z": "--..",
	"0": "-----", "1": ".----", "2": "..---", "3": "...--",
	"4": "....-", "5": ".....", "6": "-....", "7": "--...",
	"8": "---..", "9": "----.",
	".": ".-.-.-", ",": "--..--", "?": "..--..", "!": "-.-.--",
	"/": "-..-.", "-": "-....-", "(": "-.--.", ")": "-.--.-",
	"@": ".--.-.", " ": "/",
}

# 反向摩斯表
var _reverse_morse: Dictionary = {}

func _init() -> void:
	for key in MORSE_TABLE:
		_reverse_morse[MORSE_TABLE[key]] = key

# ══════════════════════════════════════════
#  统一解码入口
# ══════════════════════════════════════════
func decode(cipher_type: CipherType, input_text: String, key: String = "") -> DecodeResult:
	match cipher_type:
		CipherType.CAESAR:
			return decode_caesar(input_text, key)
		CipherType.VIGENERE:
			return decode_vigenere(input_text, key)
		CipherType.SUBSTITUTION:
			return decode_substitution(input_text, key)
		CipherType.BASE64:
			return decode_base64(input_text)
		CipherType.MORSE:
			return decode_morse(input_text)
		CipherType.ROT13:
			return decode_rot13(input_text)
		CipherType.ATBASH:
			return decode_atbash(input_text)
		CipherType.REVERSE:
			return decode_reverse(input_text)
		_:
			var r := DecodeResult.new()
			r.success = false
			r.error_message = "未知的密码类型"
			return r

# ══════════════════════════════════════════
#  凯撒密码解码
# ══════════════════════════════════════════
func decode_caesar(input_text: String, key: String = "") -> DecodeResult:
	var result := DecodeResult.new()
	result.cipher_type = CipherType.CAESAR
	result.input_text = input_text
	result.key = key

	var shift: int = 0
	if key.is_empty():
		# 自动尝试所有偏移（频率分析）
		var best_shift: int = _caesar_frequency_analysis(input_text)
		shift = best_shift
		result.metadata["auto_detected"] = true
		result.metadata["best_shift"] = best_shift
		# 生成所有26种偏移的预览
		var all_results: Array[Dictionary] = []
		for s in range(26):
			all_results.append({
				"shift": s,
				"text": _caesar_shift(input_text, s),
			})
		result.metadata["all_shifts"] = all_results
	else:
		if key.is_valid_int():
			shift = int(key) % 26
			if shift < 0:
				shift += 26
		else:
			result.success = false
			result.error_message = "凯撒密码的密钥必须是数字（偏移量 0-25）"
			return result

	result.key = str(shift)

	# 逐字符生成步骤
	var output: String = ""
	var step_idx: int = 0
	for i in range(input_text.length()):
		var ch: String = input_text[i]
		var step := DecodeStep.new()
		step.step_index = step_idx
		step.source_char = ch
		step.shift_value = shift

		var upper_pos: int = ALPHABET_UPPER.find(ch)
		var lower_pos: int = ALPHABET_LOWER.find(ch)

		if upper_pos >= 0:
			var new_pos: int = (upper_pos - shift + 26) % 26
			step.result_char = ALPHABET_UPPER[new_pos]
			step.highlight_row = upper_pos
			step.highlight_col = new_pos
			step.description = "'%s'(位置%d) - 偏移%d → '%s'(位置%d)" % [ch, upper_pos, shift, step.result_char, new_pos]
		elif lower_pos >= 0:
			var new_pos: int = (lower_pos - shift + 26) % 26
			step.result_char = ALPHABET_LOWER[new_pos]
			step.highlight_row = lower_pos
			step.highlight_col = new_pos
			step.description = "'%s'(位置%d) - 偏移%d → '%s'(位置%d)" % [ch, lower_pos, shift, step.result_char, new_pos]
		else:
			step.result_char = ch
			step.description = "'%s' 非字母，保持不变" % ch

		output += step.result_char
		result.steps.append(step)
		step_idx += 1

	result.output_text = output
	return result

func _caesar_shift(text: String, shift: int) -> String:
	var out: String = ""
	for ch in text:
		var upper_pos: int = ALPHABET_UPPER.find(ch)
		var lower_pos: int = ALPHABET_LOWER.find(ch)
		if upper_pos >= 0:
			out += ALPHABET_UPPER[(upper_pos - shift + 26) % 26]
		elif lower_pos >= 0:
			out += ALPHABET_LOWER[(lower_pos - shift + 26) % 26]
		else:
			out += ch
	return out


func _caesar_frequency_analysis(text: String) -> int:
	# 英文字母频率（A-Z，共26个）
	var english_freq: Array[float] = [
		8.167, 1.492, 2.782, 4.253, 12.702, 2.228, 2.015,  # A-G (7)
		6.094, 6.966, 0.153, 0.772, 4.025, 2.406, 6.749,   # H-N (7)
		7.507, 1.929, 0.095, 5.987, 6.327, 9.056,		   # O-T (6)
		2.758, 0.978, 2.360, 0.150, 1.974, 0.074,		   # U-Z (6)
	]
	var best_shift: int = 0
	var best_score: float = -INF
	for shift in range(26):
		var decrypted: String = _caesar_shift(text, shift)
		var score: float = 0.0
		var letter_count: int = 0
		var freq_count: Array[int] = []
		freq_count.resize(26)
		freq_count.fill(0)
		for ch in decrypted:
			var pos: int = ALPHABET_UPPER.find(ch.to_upper())
			if pos >= 0:
				freq_count[pos] += 1
				letter_count += 1
		if letter_count == 0:
			continue
		for i in range(26):
			var observed: float = float(freq_count[i]) / float(letter_count) * 100.0
			score += observed * english_freq[i]
		if score > best_score:
			best_score = score
			best_shift = shift
	return best_shift


# ══════════════════════════════════════════
#  维吉尼亚密码解码
# ══════════════════════════════════════════
func decode_vigenere(input_text: String, key: String) -> DecodeResult:
	var result := DecodeResult.new()
	result.cipher_type = CipherType.VIGENERE
	result.input_text = input_text
	result.key = key

	if key.is_empty():
		result.success = false
		result.error_message = "维吉尼亚密码需要提供密钥字符串"
		return result

	var clean_key: String = ""
	for ch in key.to_upper():
		if ALPHABET_UPPER.find(ch) >= 0:
			clean_key += ch

	if clean_key.is_empty():
		result.success = false
		result.error_message = "密钥必须包含至少一个字母"
		return result

	var output: String = ""
	var key_index: int = 0
	var step_idx: int = 0

	for i in range(input_text.length()):
		var ch: String = input_text[i]
		var step := DecodeStep.new()
		step.step_index = step_idx
		step.source_char = ch

		var upper_pos: int = ALPHABET_UPPER.find(ch)
		var lower_pos: int = ALPHABET_LOWER.find(ch)

		if upper_pos >= 0 or lower_pos >= 0:
			var pos: int = upper_pos if upper_pos >= 0 else lower_pos
			var is_upper: bool = upper_pos >= 0
			var k_char: String = clean_key[key_index % clean_key.length()]
			var k_shift: int = ALPHABET_UPPER.find(k_char)

			var new_pos: int = (pos - k_shift + 26) % 26
			if is_upper:
				step.result_char = ALPHABET_UPPER[new_pos]
			else:
				step.result_char = ALPHABET_LOWER[new_pos]

			step.key_char = k_char
			step.shift_value = k_shift
			step.highlight_row = k_shift   # Tabula Recta 行 = 密钥字母
			step.highlight_col = pos       # 列 = 密文字母
			step.description = "'%s' - 密钥'%s'(移%d) → '%s'" % [ch, k_char, k_shift, step.result_char]
			step.extra["tabula_result_row"] = k_shift
			step.extra["tabula_result_col"] = new_pos

			key_index += 1
		else:
			step.result_char = ch
			step.description = "'%s' 非字母，保持不变" % ch

		output += step.result_char
		result.steps.append(step)
		step_idx += 1

	result.output_text = output
	return result

# ══════════════════════════════════════════
#  替换密码解码
# ══════════════════════════════════════════
func decode_substitution(input_text: String, key: String) -> DecodeResult:
	var result := DecodeResult.new()
	result.cipher_type = CipherType.SUBSTITUTION
	result.input_text = input_text
	result.key = key

	if key.length() != 26:
		result.success = false
		result.error_message = "替换密码的密钥必须是26个不重复字母的排列\n例如: QWERTYUIOPASDFGHJKLZXCVBNM"
		return result

	var upper_key: String = key.to_upper()
	# 验证密钥是否包含所有26个字母
	var used: Array[bool] = []
	used.resize(26)
	used.fill(false)
	for ch in upper_key:
		var pos: int = ALPHABET_UPPER.find(ch)
		if pos < 0:
			result.success = false
			result.error_message = "密钥中包含非字母字符: '%s'" % ch
			return result
		if used[pos]:
			result.success = false
			result.error_message = "密钥中字母 '%s' 重复" % ch
			return result
		used[pos] = true

	# 构建反向映射
	var reverse_map: Dictionary = {}
	for i in range(26):
		reverse_map[upper_key[i]] = ALPHABET_UPPER[i]

	var output: String = ""
	var step_idx: int = 0

	for i in range(input_text.length()):
		var ch: String = input_text[i]
		var step := DecodeStep.new()
		step.step_index = step_idx
		step.source_char = ch

		var upper_ch: String = ch.to_upper()
		if reverse_map.has(upper_ch):
			var mapped: String = str(reverse_map[upper_ch])
			if ch == ch.to_lower():
				step.result_char = mapped.to_lower()
			else:
				step.result_char = mapped

			var src_pos: int = ALPHABET_UPPER.find(upper_ch)
			var dst_pos: int = ALPHABET_UPPER.find(mapped)
			step.highlight_row = src_pos
			step.highlight_col = dst_pos
			step.description = "'%s' → 密表查找 → '%s'" % [ch, step.result_char]
		else:
			step.result_char = ch
			step.description = "'%s' 不在密表中，保持不变" % ch

		output += step.result_char
		result.steps.append(step)
		step_idx += 1

	result.output_text = output
	return result

# ══════════════════════════════════════════
#  Base64 解码
# ══════════════════════════════════════════
func decode_base64(input_text: String) -> DecodeResult:
	var result := DecodeResult.new()
	result.cipher_type = CipherType.BASE64
	result.input_text = input_text

	var clean_input: String = input_text.strip_edges()
	var decoded_bytes: PackedByteArray = Marshalls.base64_to_raw(clean_input)

	if decoded_bytes.is_empty() and not clean_input.is_empty():
		result.success = false
		result.error_message = "无法解码 Base64，输入格式无效"
		return result

	result.output_text = decoded_bytes.get_string_from_utf8()

	# 生成步骤：每4个字符一组
	var step_idx: int = 0
	var b64_chars: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	var i: int = 0
	while i < clean_input.length():
		var chunk: String = ""
		var chunk_end: int = mini(i + 4, clean_input.length())
		chunk = clean_input.substr(i, chunk_end - i)

		var step := DecodeStep.new()
		step.step_index = step_idx
		step.source_char = chunk

		# 计算该组对应的字节
		var values: Array[int] = []
		for ch in chunk:
			var val: int = b64_chars.find(ch)
			if ch == "=":
				val = 0
			if val >= 0:
				values.append(val)

		var decoded_chunk: String = ""
		if values.size() >= 2:
			var byte1: int = (values[0] << 2) | (values[1] >> 4)
			decoded_chunk += char(byte1)
			if values.size() >= 3 and chunk.length() > 2 and chunk[2] != "=":
				var byte2: int = ((values[1] & 0xF) << 4) | (values[2] >> 2)
				decoded_chunk += char(byte2)
			if values.size() >= 4 and chunk.length() > 3 and chunk[3] != "=":
				var byte3: int = ((values[2] & 0x3) << 6) | values[3]
				decoded_chunk += char(byte3)

		step.result_char = decoded_chunk

		# 二进制表示
		var binary_str: String = ""
		for v in values:
			var bits: String = ""
			for b in range(5, -1, -1):
				bits += "1" if (v >> b) & 1 else "0"
			binary_str += bits + " "

		step.description = "'%s' → [%s] → '%s'" % [chunk, binary_str.strip_edges(), decoded_chunk]
		step.extra["binary"] = binary_str.strip_edges()
		step.extra["values"] = values

		result.steps.append(step)
		step_idx += 1
		i += 4

	return result

# ══════════════════════════════════════════
#  摩斯电码解码
# ══════════════════════════════════════════
func decode_morse(input_text: String) -> DecodeResult:
	var result := DecodeResult.new()
	result.cipher_type = CipherType.MORSE
	result.input_text = input_text

	# 按空格分割摩斯码单元，/ 表示单词分隔
	var words: PackedStringArray = input_text.strip_edges().split("/")
	var output: String = ""
	var step_idx: int = 0

	for w_idx in range(words.size()):
		var word: String = words[w_idx].strip_edges()
		if word.is_empty():
			output += " "
			continue

		var codes: PackedStringArray = word.split(" ", false)
		for code in codes:
			var step := DecodeStep.new()
			step.step_index = step_idx
			step.source_char = code

			if _reverse_morse.has(code):
				step.result_char = str(_reverse_morse[code])
				step.description = "'%s' → '%s'" % [code, step.result_char]
			else:
				step.result_char = "?"
				step.description = "'%s' → 未知编码" % code

			output += step.result_char
			result.steps.append(step)
			step_idx += 1

		if w_idx < words.size() - 1:
			output += " "

	result.output_text = output
	return result

# ══════════════════════════════════════════
#  ROT13 解码
# ══════════════════════════════════════════
func decode_rot13(input_text: String) -> DecodeResult:
	return decode_caesar(input_text, "13")

# ══════════════════════════════════════════
#  Atbash 密码解码
# ══════════════════════════════════════════
func decode_atbash(input_text: String) -> DecodeResult:
	var result := DecodeResult.new()
	result.cipher_type = CipherType.ATBASH
	result.input_text = input_text

	var output: String = ""
	var step_idx: int = 0

	for i in range(input_text.length()):
		var ch: String = input_text[i]
		var step := DecodeStep.new()
		step.step_index = step_idx
		step.source_char = ch

		var upper_pos: int = ALPHABET_UPPER.find(ch)
		var lower_pos: int = ALPHABET_LOWER.find(ch)

		if upper_pos >= 0:
			var new_pos: int = 25 - upper_pos
			step.result_char = ALPHABET_UPPER[new_pos]
			step.highlight_row = upper_pos
			step.highlight_col = new_pos
			step.description = "'%s'(%d) ↔ '%s'(%d) [镜像]" % [ch, upper_pos, step.result_char, new_pos]
		elif lower_pos >= 0:
			var new_pos: int = 25 - lower_pos
			step.result_char = ALPHABET_LOWER[new_pos]
			step.highlight_row = lower_pos
			step.highlight_col = new_pos
			step.description = "'%s'(%d) ↔ '%s'(%d) [镜像]" % [ch, lower_pos, step.result_char, new_pos]
		else:
			step.result_char = ch
			step.description = "'%s' 非字母，保持不变" % ch

		output += step.result_char
		result.steps.append(step)
		step_idx += 1

	result.output_text = output
	return result

# ══════════════════════════════════════════
#  反转解码
# ══════════════════════════════════════════
func decode_reverse(input_text: String) -> DecodeResult:
	var result := DecodeResult.new()
	result.cipher_type = CipherType.REVERSE
	result.input_text = input_text

	var reversed: String = ""
	for i in range(input_text.length() - 1, -1, -1):
		reversed += input_text[i]

	result.output_text = reversed

	# 单步
	var step := DecodeStep.new()
	step.step_index = 0
	step.source_char = input_text
	step.result_char = reversed
	step.description = "整体反转字符串"
	result.steps.append(step)

	return result

# ══════════════════════════════════════════
#  辅助：获取密码类型名称
# ══════════════════════════════════════════
static func get_type_name(t: CipherType) -> String:
	match t:
		CipherType.CAESAR: return "凯撒密码 (Caesar)"
		CipherType.VIGENERE: return "维吉尼亚密码 (Vigenère)"
		CipherType.SUBSTITUTION: return "替换密码 (Substitution)"
		CipherType.BASE64: return "Base64"
		CipherType.MORSE: return "摩斯电码 (Morse)"
		CipherType.ROT13: return "ROT13"
		CipherType.ATBASH: return "Atbash 密码"
		CipherType.REVERSE: return "反转 (Reverse)"
		_: return "未知"

static func get_type_key(t: CipherType) -> String:
	match t:
		CipherType.CAESAR: return "caesar"
		CipherType.VIGENERE: return "vigenere"
		CipherType.SUBSTITUTION: return "substitution"
		CipherType.BASE64: return "base64"
		CipherType.MORSE: return "morse"
		CipherType.ROT13: return "rot13"
		CipherType.ATBASH: return "atbash"
		CipherType.REVERSE: return "reverse"
		_: return ""

static func get_type_from_key(key: String) -> CipherType:
	match key.to_lower():
		"caesar": return CipherType.CAESAR
		"vigenere", "vigenère": return CipherType.VIGENERE
		"substitution", "sub": return CipherType.SUBSTITUTION
		"base64", "b64": return CipherType.BASE64
		"morse": return CipherType.MORSE
		"rot13": return CipherType.ROT13
		"atbash": return CipherType.ATBASH
		"reverse", "rev": return CipherType.REVERSE
		_: return CipherType.CAESAR
