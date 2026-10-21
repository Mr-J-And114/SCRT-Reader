class_name RadioSpectrumPattern
extends RefCounted
## 软件接收模拟的谱图线索。灰度图输入接口供后续图像→音频工具使用。
## 不读取／显示线索正文，按时间逐行把强度加入接收频谱。
const GLYPHS: Dictionary = {
	"A": [14,17,17,31,17,17,17], "B": [30,17,17,30,17,17,30], "C": [14,17,16,16,16,17,14],
	"D": [30,17,17,17,17,17,30], "E": [31,16,16,30,16,16,31], "F": [31,16,16,30,16,16,16],
	"G": [14,17,16,23,17,17,15], "H": [17,17,17,31,17,17,17], "I": [31,4,4,4,4,4,31],
	"J": [7,2,2,2,18,18,12], "K": [17,18,20,24,20,18,17], "L": [16,16,16,16,16,16,31],
	"M": [17,27,21,21,17,17,17], "N": [17,25,21,19,17,17,17], "O": [14,17,17,17,17,17,14],
	"P": [30,17,17,30,16,16,16], "Q": [14,17,17,17,21,18,13], "R": [30,17,17,30,20,18,17],
	"S": [15,16,16,14,1,1,30], "T": [31,4,4,4,4,4,4], "U": [17,17,17,17,17,17,14],
	"V": [17,17,17,17,17,10,4], "W": [17,17,17,21,21,21,10], "X": [17,17,10,4,10,17,17],
	"Y": [17,17,10,4,4,4,4], "Z": [31,1,2,4,8,16,31],
	"0": [14,17,19,21,25,17,14], "1": [4,12,4,4,4,4,14], "2": [14,17,1,2,4,8,31],
	"3": [30,1,1,14,1,1,30], "4": [2,6,10,18,31,2,2], "5": [31,16,16,30,1,1,30],
	"6": [14,16,16,30,17,17,14], "7": [31,1,2,4,8,8,8], "8": [14,17,17,14,17,17,14],
	"9": [14,17,17,15,1,1,14], "-": [0,0,0,31,0,0,0], ".": [0,0,0,0,0,12,12],
	":": [0,12,12,0,12,12,0], "/": [1,1,2,4,8,16,16], "?": [14,17,1,2,4,0,4], " ": [0,0,0,0,0,0,0]
}
var _signal: RadioConfigParser.RadioSignal = null
var _image: Image = null
var _time: float = 0.0

func reset() -> void:
	_signal = null
	_image = null
	_time = 0.0

func _load(sig: RadioConfigParser.RadioSignal) -> void:
	_signal = sig
	_time = 0.0
	_image = null
	if not sig.spectrum_image.is_empty():
		var img := Image.new()
		if img.load_png_from_buffer(sig.spectrum_image) == OK or img.load_jpg_from_buffer(sig.spectrum_image) == OK:
			if img.get_width() <= 2048 and img.get_height() <= 2048: _image = img
	elif not sig.waterfall_text.is_empty():
		var lines: PackedStringArray = sig.waterfall_text.to_upper().split("\n")
		var width: int = 1
		for line in lines: width = maxi(width, mini(line.length(), 80) * 6)
		_image = Image.create(width, mini(lines.size(), 16) * 9, false, Image.FORMAT_RGB8)
		_image.fill(Color.BLACK)
		for ly in range(mini(lines.size(), 16)):
			for i in range(mini(lines[ly].length(), 80)):
				var glyph: Array = GLYPHS.get(lines[ly][i], GLYPHS["?"])
				for y in range(7):
					for x in range(5):
						if (int(glyph[y]) & (1 << (4 - x))) != 0: _image.set_pixel(i * 6 + x, ly * 9 + y, Color.WHITE)

func mix_row(spectrum: PackedFloat32Array, delta: float, sig: RadioConfigParser.RadioSignal, quality: float) -> void:
	if sig != _signal:
		reset()
		if sig != null: _load(sig)
	if sig == null: return
	_time += delta
	if _image == null or quality < 0.03: return
	var phase: float = fmod(_time, sig.spectrum_duration + sig.spectrum_repeat_gap)
	if phase >= sig.spectrum_duration: return
	# 新行在最上方，倒序发出后整个图案在历史区中保持正向。
	var row: int = clampi(int((1.0 - phase / sig.spectrum_duration) * _image.get_height()), 0, _image.get_height() - 1)
	for x in range(spectrum.size()):
		var ratio: float = float(x) / maxi(spectrum.size() - 1, 1)
		# 线索占用高音频段；文件数据载波占低音频段，两者互不替换。
		if ratio < 0.5 or ratio > 0.95: continue
		var px: int = clampi(int((ratio - 0.5) / 0.45 * _image.get_width()), 0, _image.get_width() - 1)
		var pixel: Color = _image.get_pixel(px, row)
		var gray: float = (pixel.r + pixel.g + pixel.b) / 3.0 * pixel.a
		spectrum[x] = maxf(spectrum[x], gray * quality)
