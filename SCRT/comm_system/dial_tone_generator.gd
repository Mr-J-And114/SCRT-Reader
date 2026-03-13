# dial_tone_generator.gd
class_name DialToneGenerator
extends RefCounted

# ══════════════════════════════════════════
#  DTMF 双音多频 + 调制解调器握手 程序化音频生成器
# ══════════════════════════════════════════

const SAMPLE_RATE: int = 22050
const MAX_AMPLITUDE: float = 0.4  # 主音量上限，防止爆音

# DTMF 频率表
const DTMF_LOW: Array[float] = [697.0, 770.0, 852.0, 941.0]
const DTMF_HIGH: Array[float] = [1209.0, 1336.0, 1477.0, 1633.0]
const DTMF_MAP: Dictionary = {
	"1": [0, 0], "2": [0, 1], "3": [0, 2], "A": [0, 3],
	"4": [1, 0], "5": [1, 1], "6": [1, 2], "B": [1, 3],
	"7": [2, 0], "8": [2, 1], "9": [2, 2], "C": [2, 3],
	"*": [3, 0], "0": [3, 1], "#": [3, 2], "D": [3, 3],
}

# ══════════════════════════════════════════
#  基础波形工具
# ══════════════════════════════════════════

## 生成正弦波样本数组（单声道 float）
func _generate_sine(freq: float, duration_sec: float, amplitude: float = MAX_AMPLITUDE) -> PackedFloat32Array:
	var sample_count: int = int(SAMPLE_RATE * duration_sec)
	var samples := PackedFloat32Array()
	samples.resize(sample_count)
	var phase_inc: float = TAU * freq / SAMPLE_RATE
	var phase: float = 0.0
	for i in range(sample_count):
		samples[i] = sin(phase) * amplitude
		phase += phase_inc
		if phase > TAU:
			phase -= TAU
	return samples

## 生成双正弦叠加（DTMF 用）
func _generate_dual_tone(freq_low: float, freq_high: float, duration_sec: float, amplitude: float = MAX_AMPLITUDE * 0.5) -> PackedFloat32Array:
	var sample_count: int = int(SAMPLE_RATE * duration_sec)
	var samples := PackedFloat32Array()
	samples.resize(sample_count)
	var phase_low: float = 0.0
	var phase_high: float = 0.0
	var inc_low: float = TAU * freq_low / SAMPLE_RATE
	var inc_high: float = TAU * freq_high / SAMPLE_RATE
	for i in range(sample_count):
		samples[i] = (sin(phase_low) + sin(phase_high)) * amplitude
		phase_low += inc_low
		phase_high += inc_high
		if phase_low > TAU:
			phase_low -= TAU
		if phase_high > TAU:
			phase_high -= TAU
	return samples

## 生成静音
func _generate_silence(duration_sec: float) -> PackedFloat32Array:
	var sample_count: int = int(SAMPLE_RATE * duration_sec)
	var samples := PackedFloat32Array()
	samples.resize(sample_count)
	samples.fill(0.0)
	return samples

## 生成白噪音
func _generate_white_noise(duration_sec: float, amplitude: float = 0.1) -> PackedFloat32Array:
	var sample_count: int = int(SAMPLE_RATE * duration_sec)
	var samples := PackedFloat32Array()
	samples.resize(sample_count)
	for i in range(sample_count):
		samples[i] = (randf() * 2.0 - 1.0) * amplitude
	return samples

## 生成频率扫描（线性扫频）
func _generate_sweep(freq_start: float, freq_end: float, duration_sec: float, amplitude: float = MAX_AMPLITUDE * 0.35) -> PackedFloat32Array:
	var sample_count: int = int(SAMPLE_RATE * duration_sec)
	var samples := PackedFloat32Array()
	samples.resize(sample_count)
	var phase: float = 0.0
	for i in range(sample_count):
		var t: float = float(i) / float(sample_count)
		var freq: float = lerpf(freq_start, freq_end, t)
		var phase_inc: float = TAU * freq / SAMPLE_RATE
		samples[i] = sin(phase) * amplitude
		phase += phase_inc
		if phase > TAU:
			phase -= TAU
	return samples

## 应用淡入淡出包络
func _apply_envelope(samples: PackedFloat32Array, fade_in_sec: float = 0.005, fade_out_sec: float = 0.005) -> PackedFloat32Array:
	var fade_in_samples: int = int(SAMPLE_RATE * fade_in_sec)
	var fade_out_samples: int = int(SAMPLE_RATE * fade_out_sec)
	var total: int = samples.size()
	for i in range(mini(fade_in_samples, total)):
		samples[i] *= float(i) / float(fade_in_samples)
	for i in range(mini(fade_out_samples, total)):
		var idx: int = total - 1 - i
		samples[idx] *= float(i) / float(fade_out_samples)
	return samples

## 拼接多段样本
func _concat_samples(segments: Array[PackedFloat32Array]) -> PackedFloat32Array:
	var total_size: int = 0
	for seg in segments:
		total_size += seg.size()
	var result := PackedFloat32Array()
	result.resize(total_size)
	var offset: int = 0
	for seg in segments:
		for i in range(seg.size()):
			result[offset + i] = seg[i]
		offset += seg.size()
	return result

## 混合两段等长样本（不等长则截短）
func _mix_samples(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var length: int = mini(a.size(), b.size())
	var result := PackedFloat32Array()
	result.resize(length)
	for i in range(length):
		result[i] = clampf(a[i] + b[i], -1.0, 1.0)
	return result

## 将 float32 样本转换为 16-bit PCM AudioStreamWAV
func _samples_to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	var byte_data := PackedByteArray()
	byte_data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var clamped: float = clampf(samples[i], -1.0, 1.0)
		var int_val: int = int(clamped * 32767.0)
		byte_data[i * 2] = int_val & 0xFF
		byte_data[i * 2 + 1] = (int_val >> 8) & 0xFF
	wav.data = byte_data
	return wav

# ══════════════════════════════════════════
#  公开接口
# ══════════════════════════════════════════

## 生成单个 DTMF 按键音（双正弦叠加）
func generate_dtmf_key(key: String, duration_ms: int = 120) -> AudioStreamWAV:
	var upper_key: String = key.to_upper()
	if not DTMF_MAP.has(upper_key):
		# 未知按键 → 静音
		return _samples_to_wav(_generate_silence(float(duration_ms) / 1000.0))
	var idx: Array = DTMF_MAP[upper_key]
	var freq_low: float = DTMF_LOW[idx[0]]
	var freq_high: float = DTMF_HIGH[idx[1]]
	var dur_sec: float = float(duration_ms) / 1000.0
	var samples: PackedFloat32Array = _generate_dual_tone(freq_low, freq_high, dur_sec)
	samples = _apply_envelope(samples, 0.003, 0.003)
	return _samples_to_wav(samples)

## 生成完整拨号序列（含间隔静音），返回总时长和 WAV
## number: 如 "1001-0001"，连字符产生短暂静音
func generate_dial_sequence(number: String, key_ms: int = 120, gap_ms: int = 60, dash_pause_ms: int = 80) -> Dictionary:
	var segments: Array[PackedFloat32Array] = []
	var total_duration: float = 0.0
	var key_dur: float = float(key_ms) / 1000.0
	var gap_dur: float = float(gap_ms) / 1000.0
	var dash_dur: float = float(dash_pause_ms) / 1000.0

	for i in range(number.length()):
		var ch: String = number[i]
		if ch == "-":
			segments.append(_generate_silence(dash_dur))
			total_duration += dash_dur
		elif ch == " ":
			continue
		else:
			var upper_ch: String = ch.to_upper()
			if DTMF_MAP.has(upper_ch):
				var idx: Array = DTMF_MAP[upper_ch]
				var freq_low: float = DTMF_LOW[idx[0]]
				var freq_high: float = DTMF_HIGH[idx[1]]
				var tone: PackedFloat32Array = _generate_dual_tone(freq_low, freq_high, key_dur)
				tone = _apply_envelope(tone, 0.003, 0.003)
				segments.append(tone)
				total_duration += key_dur
			else:
				# 未知字符 → 短静音
				segments.append(_generate_silence(key_dur))
				total_duration += key_dur
			# 按键间隔
			if i < number.length() - 1 and number[i + 1] != "-":
				segments.append(_generate_silence(gap_dur))
				total_duration += gap_dur

	var combined: PackedFloat32Array = _concat_samples(segments)
	return {
		"stream": _samples_to_wav(combined),
		"duration": total_duration
	}

## 生成回铃音 (425Hz, 1s on / 4s off，简化版 1s on / 2s off)
func generate_ringback(count: int = 2) -> Dictionary:
	var segments: Array[PackedFloat32Array] = []
	var on_dur: float = 1.0
	var off_dur: float = 2.0
	for i in range(count):
		var tone: PackedFloat32Array = _generate_sine(425.0, on_dur, MAX_AMPLITUDE * 0.35)
		tone = _apply_envelope(tone, 0.02, 0.02)
		segments.append(tone)
		if i < count - 1:
			segments.append(_generate_silence(off_dur))
	var combined: PackedFloat32Array = _concat_samples(segments)
	var total_dur: float = on_dur * count + off_dur * (count - 1)
	return {
		"stream": _samples_to_wav(combined),
		"duration": total_dur
	}

## 生成忙音 (480Hz + 620Hz, 0.5s on / 0.5s off)
func generate_busy_tone(count: int = 3) -> Dictionary:
	var segments: Array[PackedFloat32Array] = []
	var on_dur: float = 0.5
	var off_dur: float = 0.5
	for i in range(count):
		var tone: PackedFloat32Array = _generate_dual_tone(480.0, 620.0, on_dur, MAX_AMPLITUDE * 0.4)
		tone = _apply_envelope(tone, 0.01, 0.01)
		segments.append(tone)
		if i < count - 1:
			segments.append(_generate_silence(off_dur))
	var combined: PackedFloat32Array = _concat_samples(segments)
	var total_dur: float = on_dur * count + off_dur * (count - 1)
	return {
		"stream": _samples_to_wav(combined),
		"duration": total_dur
	}

## 生成调制解调器握手完整音序列（约 8~10s）
func generate_modem_handshake() -> Dictionary:
	var segments: Array[PackedFloat32Array] = []

	# 阶段 1: 短暂静音（DTMF 已在外部播放）
	segments.append(_generate_silence(0.2))

	# 阶段 2: 应答载波 2100Hz (1.5s)
	var carrier: PackedFloat32Array = _generate_sine(2100.0, 1.5, MAX_AMPLITUDE * 0.3)
	carrier = _apply_envelope(carrier, 0.05, 0.05)
	segments.append(carrier)

	# 短暂静音过渡
	segments.append(_generate_silence(0.15))

	# 阶段 3: 训练序列 — 快速扫频 + 噪音 (2.5s)
	var sweep1: PackedFloat32Array = _generate_sweep(600.0, 3000.0, 0.8, MAX_AMPLITUDE * 0.25)
	var sweep2: PackedFloat32Array = _generate_sweep(3000.0, 600.0, 0.7, MAX_AMPLITUDE * 0.25)
	var sweep3: PackedFloat32Array = _generate_sweep(800.0, 2500.0, 1.0, MAX_AMPLITUDE * 0.2)
	var training_sweep: PackedFloat32Array = _concat_samples([sweep1, sweep2, sweep3] as Array[PackedFloat32Array])
	var training_noise: PackedFloat32Array = _generate_white_noise(2.5, 0.12)
	# 截齐长度后混合
	var train_len: int = mini(training_sweep.size(), training_noise.size())
	training_sweep.resize(train_len)
	training_noise.resize(train_len)
	var training_mixed: PackedFloat32Array = _mix_samples(training_sweep, training_noise)
	training_mixed = _apply_envelope(training_mixed, 0.02, 0.02)
	segments.append(training_mixed)

	# 短暂静音
	segments.append(_generate_silence(0.1))

	# 阶段 4: 数据协商 — 短促脉冲音 + 带通噪音 (2.0s)
	var negotiation_segments: Array[PackedFloat32Array] = []
	var pulse_count: int = 12
	for i in range(pulse_count):
		var freq_n: float = 1200.0 + randf() * 1800.0
		var pulse_dur: float = 0.04 + randf() * 0.08
		var pulse: PackedFloat32Array = _generate_sine(freq_n, pulse_dur, MAX_AMPLITUDE * 0.2)
		pulse = _apply_envelope(pulse, 0.002, 0.002)
		negotiation_segments.append(pulse)
		var gap_n: float = 0.02 + randf() * 0.06
		negotiation_segments.append(_generate_silence(gap_n))
	var negotiation: PackedFloat32Array = _concat_samples(negotiation_segments)
	var neg_noise: PackedFloat32Array = _generate_white_noise(float(negotiation.size()) / SAMPLE_RATE, 0.06)
	neg_noise.resize(negotiation.size())
	var negotiation_mixed: PackedFloat32Array = _mix_samples(negotiation, neg_noise)
	segments.append(negotiation_mixed)

	# 阶段 5: 连接建立 — 极低音量噪音 (0.5s)
	var connect_noise: PackedFloat32Array = _generate_white_noise(0.5, 0.02)
	connect_noise = _apply_envelope(connect_noise, 0.05, 0.05)
	segments.append(connect_noise)

	var combined: PackedFloat32Array = _concat_samples(segments)
	var total_dur: float = float(combined.size()) / SAMPLE_RATE
	return {
		"stream": _samples_to_wav(combined),
		"duration": total_dur
	}

## 生成数据传输背景噪音（低音量白噪音 + 偶尔脉冲）
func generate_data_noise(duration_sec: float = 2.0) -> AudioStreamWAV:
	var base_noise: PackedFloat32Array = _generate_white_noise(duration_sec, 0.015)
	# 添加随机短脉冲
	var sample_count: int = base_noise.size()
	var pulse_interval: int = int(SAMPLE_RATE * 0.3)
	var i: int = 0
	while i < sample_count:
		if randf() < 0.3:
			var pulse_len: int = int(SAMPLE_RATE * (0.005 + randf() * 0.015))
			var freq_p: float = 1000.0 + randf() * 2000.0
			var phase_p: float = 0.0
			for j in range(mini(pulse_len, sample_count - i)):
				base_noise[i + j] = clampf(base_noise[i + j] + sin(phase_p) * 0.03, -1.0, 1.0)
				phase_p += TAU * freq_p / SAMPLE_RATE
		i += pulse_interval
	return _samples_to_wav(base_noise)


## 生成来电铃声（区别于回铃音 ringback，更高频更急促）
## 模拟老式电话铃声: 高频双音脉冲
func generate_phone_ring(ring_count: int = 2) -> Dictionary:
	var segments: Array[PackedFloat32Array] = []
	# 单次铃声: 两组短促高频脉冲 (模拟机械铃声)
	# 铃声频率: 2000Hz + 400Hz 混合，产生金属感
	var pulse_on: float = 0.08    # 单个脉冲持续时间
	var pulse_gap: float = 0.04   # 脉冲间隔
	var group_gap: float = 0.12   # 组间间隔
	var pulses_per_group: int = 5 # 每组脉冲数
	var ring_gap: float = 1.5     # 两次铃声间的静音

	for r in range(ring_count):
		# 每次铃声包含 2 组脉冲
		for g in range(2):
			for p in range(pulses_per_group):
				var tone: PackedFloat32Array = _generate_dual_tone(
					2000.0, 400.0, pulse_on, MAX_AMPLITUDE * 0.45)
				tone = _apply_envelope(tone, 0.002, 0.002)
				segments.append(tone)
				if p < pulses_per_group - 1:
					segments.append(_generate_silence(pulse_gap))
			if g == 0:
				segments.append(_generate_silence(group_gap))
		if r < ring_count - 1:
			segments.append(_generate_silence(ring_gap))

	var combined: PackedFloat32Array = _concat_samples(segments)
	var total_dur: float = float(combined.size()) / SAMPLE_RATE
	return {
		"stream": _samples_to_wav(combined),
		"duration": total_dur
	}

## 生成电话挂机音（短促双频嘟嘟声）
func generate_hangup_tone() -> Dictionary:
	var segments: Array[PackedFloat32Array] = []
	# 短促的挂机提示音：480Hz + 620Hz，两声短嘟
	var beep_dur: float = 0.15
	var gap_dur: float = 0.1
	# 第一声
	var beep1: PackedFloat32Array = _generate_dual_tone(480.0, 620.0, beep_dur, MAX_AMPLITUDE * 0.3)
	beep1 = _apply_envelope(beep1, 0.005, 0.01)
	segments.append(beep1)
	segments.append(_generate_silence(gap_dur))
	# 第二声（略低音量，模拟挂断感）
	var beep2: PackedFloat32Array = _generate_dual_tone(480.0, 620.0, beep_dur, MAX_AMPLITUDE * 0.2)
	beep2 = _apply_envelope(beep2, 0.005, 0.02)
	segments.append(beep2)
	# 短暂尾静音
	segments.append(_generate_silence(0.1))
	var combined: PackedFloat32Array = _concat_samples(segments)
	var total_dur: float = float(combined.size()) / SAMPLE_RATE
	return {
		"stream": _samples_to_wav(combined),
		"duration": total_dur
	}

	
