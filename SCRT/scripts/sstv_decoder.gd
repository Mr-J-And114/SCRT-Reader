# ============================================================
# sstv_decoder.gd - SSTV 图像接收模拟器
# 负责：模拟逐行扫描接收、信号质量噪点叠加、图像保存
# ============================================================
class_name SSTVDecoder
extends RefCounted

# ══════════════════════════════════════════
#  SSTV 模式定义
# ══════════════════════════════════════════

const SSTV_MODES: Dictionary = {
	"Robot 36":   { "width": 320, "height": 240, "duration": 36.0  },
	"Martin M1":  { "width": 320, "height": 256, "duration": 114.0 },
	"Scottie S1": { "width": 320, "height": 256, "duration": 110.0 },
	"PD120":      { "width": 640, "height": 496, "duration": 126.0 },
}

# ══════════════════════════════════════════
#  状态
# ══════════════════════════════════════════

var is_receiving: bool = false
var is_complete: bool = false
var was_interrupted: bool = false

var mode_name: String = "Martin M1"
var target_width: int = 320
var target_height: int = 256
var transmit_duration: float = 114.0

var current_scanline: int = 0
var receive_timer: float = 0.0
var seconds_per_line: float = 0.0

# 源图像
var source_image: Image = null

# 接收中的图像
var received_image: Image = null
var received_texture: ImageTexture = null

# 信号质量历史（用于判断每行的质量）
var _line_quality_history: Array[float] = []

# SSTV 音频
var _sstv_audio_stream: AudioStreamWAV = null
var _sstv_audio_ready: bool = false

# ★ 分帧音频生成
var _audio_gen_pending: bool = false
var _audio_gen_progress: float = 0.0
var _audio_gen_pcm_parts: Array[PackedByteArray] = []
var _audio_gen_current_line: int = 0
var _audio_gen_vis_done: bool = false
const AUDIO_GEN_LINES_PER_FRAME: int = 8  # 每帧处理的行数

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════

## 从字节数据加载源图像并开始接收
func start_receive(image_data: PackedByteArray, sstv_mode: String, duration_override: float = 0.0) -> bool:
	is_receiving = false
	is_complete = false
	was_interrupted = false
	current_scanline = 0
	receive_timer = 0.0
	_line_quality_history.clear()

	# 解析模式
	if SSTV_MODES.has(sstv_mode):
		mode_name = sstv_mode
		var mode_info: Dictionary = SSTV_MODES[sstv_mode]
		target_width = int(mode_info["width"])
		target_height = int(mode_info["height"])
		transmit_duration = float(mode_info["duration"])
	else:
		mode_name = "Martin M1"
		target_width = 320
		target_height = 256
		transmit_duration = 114.0

	if duration_override > 0.0:
		transmit_duration = duration_override

	seconds_per_line = transmit_duration / float(target_height)

	# 加载源图像
	source_image = Image.new()
	var err: int = source_image.load_png_from_buffer(image_data)
	if err != OK:
		err = source_image.load_jpg_from_buffer(image_data)
	if err != OK:
		err = source_image.load_bmp_from_buffer(image_data)
	if err != OK:
		err = source_image.load_webp_from_buffer(image_data)
	if err != OK:
		push_warning("[SSTVDecoder] 无法解析图像数据")
		source_image = null
		return false

	# 缩放源图像到目标分辨率
	if source_image.get_width() != target_width or source_image.get_height() != target_height:
		source_image.resize(target_width, target_height, Image.INTERPOLATE_BILINEAR)

	# 创建接收图像（初始全黑）
	received_image = Image.create(target_width, target_height, false, Image.FORMAT_RGB8)
	received_image.fill(Color(0, 0, 0))

	received_texture = ImageTexture.create_from_image(received_image)

	# ★ 启动分帧音频生成（避免同步卡顿）
	_sstv_audio_ready = false
	_audio_gen_pending = true
	_audio_gen_progress = 0.0
	_audio_gen_pcm_parts.clear()
	_audio_gen_current_line = 0
	_audio_gen_vis_done = false


	is_receiving = true
	print("[SSTVDecoder] 开始接收, 模式=", mode_name, " 分辨率=", target_width, "x", target_height, " 时长=", transmit_duration, "s")
	return true

## 后台生成完整的 SSTV 音频
## ★ 每帧推进音频生成（分帧，避免卡顿）
func _generate_sstv_audio_step() -> void:
	if source_image == null:
		_audio_gen_pending = false
		return

	# 第一步：生成 VIS 头
	if not _audio_gen_vis_done:
		var vis_code: int = 44
		match mode_name:
			"Scottie S1": vis_code = 60
			"Robot 36":   vis_code = 8
			"PD120":	  vis_code = 95
		_audio_gen_pcm_parts.append(
			RadioAudioGenerator.generate_sstv_vis_header(vis_code, RadioAudioGenerator.SAMPLE_RATE))
		_audio_gen_vis_done = true
		return

	# 第二步：逐批生成行音频
	var lines_this_frame: int = 0
	while _audio_gen_current_line < target_height and lines_this_frame < AUDIO_GEN_LINES_PER_FRAME:
		var line_pcm: PackedByteArray = RadioAudioGenerator.generate_sstv_line_audio(
			source_image, _audio_gen_current_line, RadioAudioGenerator.SAMPLE_RATE)
		_audio_gen_pcm_parts.append(line_pcm)
		_audio_gen_current_line += 1
		lines_this_frame += 1

	_audio_gen_progress = float(_audio_gen_current_line) / float(target_height)

	# 全部行完成 → 合成最终音频流
	if _audio_gen_current_line >= target_height:
		_sstv_audio_stream = RadioAudioGenerator.build_wav_stream(
			_audio_gen_pcm_parts, RadioAudioGenerator.SAMPLE_RATE, false)
		_sstv_audio_ready = true
		_audio_gen_pending = false
		_audio_gen_pcm_parts.clear()
		print("[SSTVDecoder] SSTV 音频分帧生成完成, 时长约 ",
			_sstv_audio_stream.data.size() / 2 / RadioAudioGenerator.SAMPLE_RATE, "s")



## 中断接收
func interrupt() -> void:
	if is_receiving:
		is_receiving = false
		was_interrupted = true
		# ★ 中断音频生成
		_audio_gen_pending = false
		_audio_gen_pcm_parts.clear()

## 每帧更新，返回是否有新行
func process(delta: float, signal_quality: float) -> bool:
	# ★ 分帧音频生成（接收照常进行，音频后台准备）
	if _audio_gen_pending:
		_generate_sstv_audio_step()
	if not is_receiving:
		return false

	receive_timer += delta
	var new_lines: bool = false

	while receive_timer >= seconds_per_line and current_scanline < target_height:
		receive_timer -= seconds_per_line
		_receive_scanline(current_scanline, signal_quality)
		_line_quality_history.append(signal_quality)
		current_scanline += 1
		new_lines = true

	if current_scanline >= target_height:
		is_receiving = false
		is_complete = true
		print("[SSTVDecoder] 接收完成")

	# 更新纹理
	if new_lines and received_image != null:
		received_texture.update(received_image)

	return new_lines

## 接收单行扫描线
func _receive_scanline(line: int, quality: float) -> void:
	if source_image == null or received_image == null:
		return

	for x in range(target_width):
		var src_color: Color = source_image.get_pixel(x, line)

		if quality > 0.9:
			# 完美接收
			received_image.set_pixel(x, line, src_color)
		elif quality > 0.6:
			# 偶尔噪点
			if randf() < (1.0 - quality) * 0.3:
				received_image.set_pixel(x, line, _random_noise_color())
			else:
				received_image.set_pixel(x, line, src_color)
		elif quality > 0.3:
			# 频繁噪点 + 水平偏移
			var shift: int = 0
			if randf() < 0.3:
				shift = randi_range(-10, 10)

			var sx: int = clampi(x + shift, 0, target_width - 1)
			var base_color: Color = source_image.get_pixel(sx, line)

			if randf() < (1.0 - quality) * 0.6:
				received_image.set_pixel(x, line, _random_noise_color())
			else:
				# 色偏
				var noise_r: float = randf_range(-0.2, 0.2) * (1.0 - quality)
				var noise_g: float = randf_range(-0.2, 0.2) * (1.0 - quality)
				var noise_b: float = randf_range(-0.2, 0.2) * (1.0 - quality)
				received_image.set_pixel(x, line, Color(
					clampf(base_color.r + noise_r, 0, 1),
					clampf(base_color.g + noise_g, 0, 1),
					clampf(base_color.b + noise_b, 0, 1)
				))
		elif quality > 0.1:
			# 大量噪点
			if randf() < 0.2:
				var sx2: int = clampi(x + randi_range(-20, 20), 0, target_width - 1)
				received_image.set_pixel(x, line, source_image.get_pixel(sx2, line))
			else:
				received_image.set_pixel(x, line, _random_noise_color())
		else:
			# 纯噪音
			received_image.set_pixel(x, line, _random_noise_color())

func _random_noise_color() -> Color:
	var v: float = randf_range(0.0, 0.25)
	return Color(v + randf_range(-0.05, 0.1), v, v + randf_range(-0.05, 0.05))

# ══════════════════════════════════════════
#  查询
# ══════════════════════════════════════════

func get_progress() -> float:
	if target_height <= 0:
		return 0.0
	return float(current_scanline) / float(target_height)

func get_received_texture() -> ImageTexture:
	return received_texture

func get_elapsed_time() -> float:
	return float(current_scanline) * seconds_per_line

func get_remaining_time() -> float:
	return float(target_height - current_scanline) * seconds_per_line

## 获取可保存的 PNG 字节
func get_image_as_png() -> PackedByteArray:
	if received_image == null:
		return PackedByteArray()
	return received_image.save_png_to_buffer()

func get_average_quality() -> float:
	if _line_quality_history.is_empty():
		return 0.0
	var total: float = 0.0
	for q in _line_quality_history:
		total += q
	return total / float(_line_quality_history.size())


func get_sstv_audio_stream() -> AudioStreamWAV:
	return _sstv_audio_stream

func has_sstv_audio() -> bool:
	return _sstv_audio_ready and _sstv_audio_stream != null


## ★ 音频是否准备就绪
func is_audio_ready() -> bool:
	return _sstv_audio_ready

## ★ 音频生成进度 (0.0 ~ 1.0)
func get_audio_gen_progress() -> float:
	if not _audio_gen_pending:
		return 1.0 if _sstv_audio_ready else 0.0
	return _audio_gen_progress


	
