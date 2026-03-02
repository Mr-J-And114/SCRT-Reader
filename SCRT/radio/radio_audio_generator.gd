# ============================================================
# radio_audio_generator.gd - 无线电音效生成器
# 负责：白噪音生成、CW 摩斯音调生成、SSTV 特征音效
# ============================================================
class_name RadioAudioGenerator
extends RefCounted

# ══════════════════════════════════════════
#  音频参数
# ══════════════════════════════════════════

const SAMPLE_RATE: int = 22050
const CW_TONE_HZ: float = 700.0        # CW 音调频率
const NOISE_BUFFER_SECONDS: float = 2.0 # 噪音缓冲长度

var _noise_stream: AudioStreamWAV = null
var _tone_stream: AudioStreamWAV = null
var _current_noise_volume: float = 0.5
var _current_tone_volume: float = 0.0

# ══════════════════════════════════════════
#  生成白噪音 AudioStream
# ══════════════════════════════════════════

## 生成指定时长的白噪音（循环播放用）
func generate_noise_stream(duration: float = 2.0) -> AudioStreamWAV:
	var num_samples: int = int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)  # 16-bit = 2 bytes per sample

	for i in range(num_samples):
		# 白噪音：随机 16-bit 采样值
		var sample: int = randi_range(-3000, 3000)
		data.encode_s16(i * 2, sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = num_samples

	_noise_stream = stream
	return stream

## 生成CW音调（循环播放用）
func generate_tone_stream(frequency: float = 700.0, duration: float = 1.0) -> AudioStreamWAV:
	var num_samples: int = int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t: float = float(i) / float(SAMPLE_RATE)
		var sample_f: float = sin(t * frequency * TAU) * 16000.0
		data.encode_s16(i * 2, int(sample_f))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = num_samples

	_tone_stream = stream
	return stream

## 生成 SSTV 特征启动音（1900Hz→1200Hz→1500Hz 序列）
func generate_sstv_header_stream() -> AudioStreamWAV:
	var segments: Array[Dictionary] = [
		{ "freq": 1900.0, "duration": 0.3 },
		{ "freq": 1200.0, "duration": 0.01 },
		{ "freq": 1500.0, "duration": 0.3 },
	]

	var total_samples: int = 0
	for seg in segments:
		total_samples += int(SAMPLE_RATE * float(seg["duration"]))

	var data := PackedByteArray()
	data.resize(total_samples * 2)

	var offset: int = 0
	for seg in segments:
		var freq: float = float(seg["freq"])
		var dur: float = float(seg["duration"])
		var samples: int = int(SAMPLE_RATE * dur)
		for i in range(samples):
			var t: float = float(i) / float(SAMPLE_RATE)
			var sample_f: float = sin(t * freq * TAU) * 12000.0
			data.encode_s16(offset * 2, int(sample_f))
			offset += 1

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED

	return stream

# ══════════════════════════════════════════
#  音量计算辅助
# ══════════════════════════════════════════

## 根据信号质量计算噪音音量（质量越高噪音越低）
func get_noise_volume_db(signal_quality: float, base_volume_linear: float = 0.15) -> float:
	var noise_linear: float = (1.0 - signal_quality) * base_volume_linear
	if noise_linear < 0.001:
		return -80.0
	return linear_to_db(noise_linear)



## 根据信号质量和音调开关计算CW音调音量
func get_tone_volume_db(signal_quality: float, tone_on: bool, base_volume_linear: float = 0.4) -> float:
	if not tone_on:
		return -80.0
	var tone_linear: float = signal_quality * base_volume_linear
	if tone_linear < 0.001:
		return -80.0
	return linear_to_db(tone_linear)


# ══════════════════════════════════════════
#  SSTV 实时音频生成（真实可解码）
# ══════════════════════════════════════════

## 根据图像的一行像素生成对应的 SSTV 音频采样数据
## Martin M1 协议：每行 = 4.862ms同步(1200Hz) + 0.572ms同步间隔(1500Hz)
##				 + 绿色扫描146.432ms + 0.572ms间隔
##				 + 蓝色扫描146.432ms + 0.572ms间隔
##				 + 红色扫描146.432ms
## 像素亮度 0.0→1500Hz, 1.0→2300Hz
static func generate_sstv_line_audio(image: Image, line: int, sample_rate: int = 22050) -> PackedByteArray:
	if image == null or line < 0 or line >= image.get_height():
		return PackedByteArray()

	var width: int = image.get_width()

	# Martin M1 时序（秒）
	var sync_pulse: float = 0.004862
	var sync_porch: float = 0.000572
	var color_scan: float = 0.146432
	var separator: float = 0.000572

	var line_duration: float = sync_pulse + sync_porch + (color_scan + separator) * 3.0 - separator
	var total_samples: int = int(float(sample_rate) * line_duration) + 1
	var data := PackedByteArray()
	data.resize(total_samples * 2)

	var sample_idx: int = 0
	var phase: float = 0.0

	# 辅助：写入一段固定频率
	# 返回更新后的 phase
	var _write_tone := func(freq: float, duration: float, d: PackedByteArray, idx: int, ph: float) -> Array:
		var num: int = int(float(sample_rate) * duration)
		var dt: float = 1.0 / float(sample_rate)
		for i in range(num):
			var val: float = sin(ph * TAU) * 12000.0
			if idx + i < total_samples:
				d.encode_s16((idx + i) * 2, int(val))
			ph += freq * dt
			ph = fmod(ph, 1.0)
		return [idx + num, ph]

	# 辅助：写入一行颜色扫描（频率随像素亮度变化）
	var _write_color_scan := func(channel: int, d: PackedByteArray, idx2: int, ph2: float) -> Array:
		var num2: int = int(float(sample_rate) * color_scan)
		var dt2: float = 1.0 / float(sample_rate)
		for i in range(num2):
			var px: int = clampi(int(float(i) / float(num2) * float(width)), 0, width - 1)
			var col: Color = image.get_pixel(px, line)
			var brightness: float = 0.0
			match channel:
				0: brightness = col.g  # Green
				1: brightness = col.b  # Blue
				2: brightness = col.r  # Red
			var freq: float = 1500.0 + brightness * 800.0  # 1500~2300 Hz
			var val: float = sin(ph2 * TAU) * 12000.0
			if idx2 + i < total_samples:
				d.encode_s16((idx2 + i) * 2, int(val))
			ph2 += freq * dt2
			ph2 = fmod(ph2, 1.0)
		return [idx2 + num2, ph2]

	# 1. 同步脉冲 1200Hz
	var result: Array = _write_tone.call(1200.0, sync_pulse, data, sample_idx, phase)
	sample_idx = int(result[0])
	phase = float(result[1])

	# 2. 同步间隔 1500Hz
	result = _write_tone.call(1500.0, sync_porch, data, sample_idx, phase)
	sample_idx = int(result[0])
	phase = float(result[1])

	# 3. Green scan
	result = _write_color_scan.call(0, data, sample_idx, phase)
	sample_idx = int(result[0])
	phase = float(result[1])

	# 4. Separator
	result = _write_tone.call(1500.0, separator, data, sample_idx, phase)
	sample_idx = int(result[0])
	phase = float(result[1])

	# 5. Blue scan
	result = _write_color_scan.call(1, data, sample_idx, phase)
	sample_idx = int(result[0])
	phase = float(result[1])

	# 6. Separator
	result = _write_tone.call(1500.0, separator, data, sample_idx, phase)
	sample_idx = int(result[0])
	phase = float(result[1])

	# 7. Red scan
	result = _write_color_scan.call(2, data, sample_idx, phase)
	sample_idx = int(result[0])
	phase = float(result[1])

	return data

## 生成 SSTV VIS 头部音频（校准头 + VIS码）
## 1900Hz 300ms → 1200Hz 10ms → 1900Hz 300ms → 1200Hz 30ms → VIS bits
static func generate_sstv_vis_header(vis_code: int = 44, sample_rate: int = 22050) -> PackedByteArray:
	var segments: Array[Array] = [
		[1900.0, 0.300],  # Leader tone
		[1200.0, 0.010],  # Break
		[1900.0, 0.300],  # Leader tone
		[1200.0, 0.030],  # VIS start bit
	]

	# VIS code bits (LSB first, 7 data bits + 1 parity)
	var parity: int = 0
	for i in range(7):
		var bit: int = (vis_code >> i) & 1
		parity ^= bit
		if bit == 1:
			segments.append([1100.0, 0.030])  # 1 = 1100Hz
		else:
			segments.append([1300.0, 0.030])  # 0 = 1300Hz

	# Parity bit
	if parity == 1:
		segments.append([1100.0, 0.030])
	else:
		segments.append([1300.0, 0.030])

	# Stop bit
	segments.append([1200.0, 0.030])

	var total_samples: int = 0
	for seg in segments:
		total_samples += int(float(sample_rate) * seg[1])

	var data := PackedByteArray()
	data.resize(total_samples * 2)

	var offset: int = 0
	var ph: float = 0.0
	var dt: float = 1.0 / float(sample_rate)
	for seg in segments:
		var freq: float = seg[0]
		var dur: float = seg[1]
		var num: int = int(float(sample_rate) * dur)
		for i in range(num):
			var val: float = sin(ph * TAU) * 12000.0
			if offset < total_samples:
				data.encode_s16(offset * 2, int(val))
			ph += freq * dt
			ph = fmod(ph, 1.0)
			offset += 1

	return data

## 将多段 PCM 数据合并为一个 AudioStreamWAV
static func build_wav_stream(pcm_segments: Array[PackedByteArray], sample_rate: int = 22050, do_loop: bool = false) -> AudioStreamWAV:
	var total_size: int = 0
	for seg in pcm_segments:
		total_size += seg.size()

	var combined := PackedByteArray()
	combined.resize(total_size)
	var offset: int = 0
	for seg in pcm_segments:
		for i in range(seg.size()):
			combined[offset] = seg[i]
			offset += 1

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = combined
	if do_loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = total_size / 2
	else:
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream



	
