# ============================================================
# radio_signal_manager.gd - 无线电信号管理器
# 负责：信号源管理、信号强度计算、自动扫描、衰落模拟
# ============================================================
class_name RadioSignalManager
extends RefCounted
# ══════════════════════════════════════════
#  引用
# ══════════════════════════════════════════
var signals: Array = []  # Array[RadioConfigParser.RadioSignal]
var discovered_signals: Array[String] = []  # 已发现的信号ID列表
var bookmarks: Array[Dictionary] = []       # 频率书签
# ══════════════════════════════════════════
#  信号日志
# ══════════════════════════════════════════
class SignalLogEntry:
	var time_str: String = ""
	var frequency: float = 0.0
	var band: String = ""
	var azimuth: float = 0
	var signal_type: String = ""
	var label: String = ""
	var signal_id: String = ""
var signal_log: Array = []  # Array[SignalLogEntry]
# ★ 信标日志
var beacon_log: Array[Dictionary] = []    # { "id", "beacon_id", "label", "freq", "band", "time" }
# ══════════════════════════════════════════
#  衰落模拟
# ══════════════════════════════════════════
var _time_elapsed: float = 0.0

# ══════════════════════════════════════════
# ★ 新增：从 manifest 加载（优先），自动回退旧版
# ══════════════════════════════════════════
func load_signals_from_manifest(manifest: Dictionary, fs) -> void:
	signals = RadioConfigParser.parse_signals_from_manifest(manifest, fs)
	# 如果 manifest 中没有 radio_signals，回退到旧版 signals.cfg
	if signals.is_empty():
		signals = RadioConfigParser.parse_signals(fs)

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func load_signals(fs) -> void:
	signals = RadioConfigParser.parse_signals(fs)
func has_signals() -> bool:
	return not signals.is_empty()
func get_signal_count() -> int:
	return signals.size()
# ══════════════════════════════════════════
#  按频率距离查找最近信号源（用于UI稳定显示）
# ══════════════════════════════════════════
## 返回同波段中频率距离最近的信号源，不考虑方位和仰角
## 这个结果只依赖 frequency 和 band，不受噪声/衰落影响，天然稳定
func get_nearest_signal_by_freq(current_freq: float, current_band: String):
	var best_signal = null
	var best_dist: float = INF
	for sig in signals:
		var s = sig as RadioConfigParser.RadioSignal
		if s.band != current_band:
			continue
		var dist: float = absf(current_freq - s.frequency)
		if dist < best_dist:
			best_dist = dist
			best_signal = s
	return best_signal
# ══════════════════════════════════════════
#  信号强度计算（核心算法）
# ══════════════════════════════════════════
## 计算某个信号在当前调谐参数下的信号质量
## 返回 0.0 ~ 1.0
## 计算某个信号在当前调谐参数下的信号质量
## 返回 0.0 ~ 1.0
func calculate_signal_quality(sig: RadioConfigParser.RadioSignal,
		current_freq: float, current_band: String,
		current_azimuth: float, current_elevation: float) -> float:
	# 波段不匹配 → 完全无信号
	if sig.band != current_band:
		return 0.0

	# ★ 渐进感知范围：使用 proximity_range（若设置），否则使用 tolerance_freq
	var effective_range: float = sig.proximity_range if sig.proximity_range > 0.0 else sig.tolerance_freq

	# 频率因子
	var freq_diff: float = absf(current_freq - sig.frequency)
	var freq_factor: float = 1.0 - clampf(freq_diff / effective_range, 0.0, 1.0)

	# 方位因子（考虑360°环绕）
	var azim_diff: float = _angle_difference_f(current_azimuth, sig.azimuth)
	var azim_tolerance: float = float(sig.tolerance_dir)
	# SSTV / audio 信号角度容差放宽
	if sig.type == "sstv" or sig.type == "audio":
		azim_tolerance *= 2.0
	var azim_factor: float = 1.0 - clampf(azim_diff / azim_tolerance, 0.0, 1.0)

	# 仰角因子
	var elev_diff: float = absf(current_elevation - sig.elevation)
	var elev_tolerance: float = float(sig.tolerance_dir) * 0.8
	if sig.type == "sstv" or sig.type == "audio":
		elev_tolerance *= 2.0
	var elev_factor: float = 1.0 - clampf(elev_diff / elev_tolerance, 0.0, 1.0)

	# 三因素乘积
	var raw_signal: float = freq_factor * azim_factor * elev_factor

	# 温和的锐化曲线
	var quality: float = pow(raw_signal, 1.2)

	# HF 波段衰落效果（SSTV/audio 不叠加）
	if sig.band == "HF" and sig.type != "sstv" and sig.type != "audio":
		var fading: float = sin(_time_elapsed * 0.3) * 0.05
		var atmospheric: float = randf_range(-0.02, 0.02)
		quality = clampf(quality + fading + atmospheric, 0.0, 1.0)

	# 非 HF 波段的轻微随机抖动
	if sig.band != "HF":
		var micro_noise: float = randf_range(-0.01, 0.01)
		quality = clampf(quality + micro_noise, 0.0, 1.0)

	# SSTV 信号传播干扰
	if sig.type == "sstv":
		var sstv_fade: float = sin(_time_elapsed * 0.1) * 0.03
		var burst_noise: float = 0.0
		if sin(_time_elapsed * 1.7) > 0.95:
			burst_noise = -0.04
		var sstv_jitter: float = randf_range(-0.01, 0.01)
		quality = clampf(quality + sstv_fade + burst_noise + sstv_jitter, 0.0, 1.0)

	# audio 类型的轻微起伏
	if sig.type == "audio":
		var audio_fade: float = sin(_time_elapsed * 0.15) * 0.02
		var audio_jitter: float = randf_range(-0.005, 0.005)
		quality = clampf(quality + audio_fade + audio_jitter, 0.0, 1.0)

	return quality


## 计算360°角度差的绝对值（0-180）
func _angle_difference_f(a: float, b: float) -> float:
	var diff: float = absf(fmod(a - b + 540.0, 360.0) - 180.0)
	return diff
## 获取当前频率/方位下信号质量最高的信号
func get_best_signal(current_freq: float, current_band: String,
		current_azimuth: float, current_elevation: float) -> Dictionary:
	var best_quality: float = 0.0
	var best_signal = null
	for sig in signals:
		var s = sig as RadioConfigParser.RadioSignal
		var q: float = calculate_signal_quality(s, current_freq, current_band,
				current_azimuth, current_elevation)
		if q > best_quality:
			best_quality = q
			best_signal = s
	return {
		"signal": best_signal,
		"quality": best_quality,
	}
## 更新时间（用于衰落模拟）
func update(delta: float) -> void:
	_time_elapsed += delta
# ══════════════════════════════════════════
#  信号发现与日志
# ══════════════════════════════════════════
func discover_signal(sig: RadioConfigParser.RadioSignal) -> bool:
	if sig.id in discovered_signals:
		return false
	discovered_signals.append(sig.id)
	var entry := SignalLogEntry.new()
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	entry.time_str = "%02d:%02d:%02d" % [dt["hour"], dt["minute"], dt["second"]]
	entry.frequency = sig.frequency
	entry.band = sig.band
	entry.azimuth = sig.azimuth
	entry.signal_type = sig.type.to_upper()
	entry.label = sig.label
	entry.signal_id = sig.id
	signal_log.append(entry)
	# ★ 如果是信标信号，自动记录到信标日志
	if not sig.beacon_id.is_empty():
		log_beacon(sig)
	print("[RadioSignalManager] 发现新信号: ", sig.id, " (", sig.label, ")")
	return true
func is_discovered(signal_id: String) -> bool:
	return signal_id in discovered_signals
# ══════════════════════════════════════════
# ★ 信标日志系统
# ══════════════════════════════════════════
## 记录信标发现
func log_beacon(sig: RadioConfigParser.RadioSignal) -> bool:
	# 检查是否已记录
	for entry_item in beacon_log:
		if entry_item["id"] == sig.id:
			return false
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	beacon_log.append({
		"id": sig.id,
		"beacon_id": sig.beacon_id,
		"label": sig.label,
		"freq": sig.frequency,
		"band": sig.band,
		"azimuth": sig.azimuth,
		"elevation": sig.elevation,
		"time": "%02d:%02d:%02d" % [dt["hour"], dt["minute"], dt["second"]],
	})
	print("[RadioSignalManager] 信标已记录: ", sig.beacon_id, " (", sig.label, ")")
	return true
## 获取信标日志
func get_beacon_log() -> Array[Dictionary]:
	return beacon_log
## 获取信标发现统计
func get_beacon_stats() -> Dictionary:
	var total_beacons: int = 0
	for sig in signals:
		var s = sig as RadioConfigParser.RadioSignal
		if not s.beacon_id.is_empty():
			total_beacons += 1
	return {
		"found": beacon_log.size(),
		"total": total_beacons,
	}
## 发现统计（所有信号）
func get_discovery_stats() -> Dictionary:
	return {
		"discovered": discovered_signals.size(),
		"total": signals.size(),
		"beacons_found": beacon_log.size(),
		"beacons_total": get_beacon_stats()["total"],
	}
## 检查是否所有信标都已发现
func all_beacons_found() -> bool:
	var stats: Dictionary = get_beacon_stats()
	return stats["total"] > 0 and stats["found"] >= stats["total"]
# ══════════════════════════════════════════
#  书签
# ══════════════════════════════════════════
func add_bookmark(freq: float, band: String, azimuth: float, elevation: float, label: String = "") -> void:
	bookmarks.append({
		"freq": freq,
		"band": band,
		"azimuth": azimuth,
		"elevation": elevation,
		"label": label,
	})
func get_bookmarks() -> Array[Dictionary]:
	return bookmarks as Array[Dictionary]
func remove_bookmark(index: int) -> void:
	if index >= 0 and index < bookmarks.size():
		bookmarks.remove_at(index)
# ══════════════════════════════════════════
#  自动扫描
# ══════════════════════════════════════════
## 在指定波段从当前频率向上扫描，寻找下一个信号质量 > threshold 的频率
func scan_next(from_freq: float, band: String, azimuth: float, elevation: float,
		threshold: float = 0.3) -> Dictionary:
	if not RadioConfigParser.BAND_RANGES.has(band):
		return {}
	var band_info: Dictionary = RadioConfigParser.BAND_RANGES[band]
	var step: float = float(band_info["step"])
	var max_f: float = float(band_info["max"])
	var freq: float = from_freq + step
	while freq <= max_f:
		var result: Dictionary = get_best_signal(freq, band, azimuth, elevation)
		if result["quality"] > threshold:
			return { "frequency": freq, "quality": result["quality"], "signal": result["signal"] }
		freq += step
	return {}
# ══════════════════════════════════════════
#  存档数据
# ══════════════════════════════════════════
func get_save_data() -> Dictionary:
	var log_data: Array[Dictionary] = []
	for entry_item in signal_log:
		var e: SignalLogEntry = entry_item as SignalLogEntry
		log_data.append({
			"time": e.time_str,
			"freq": e.frequency,
			"band": e.band,
			"azimuth": e.azimuth,
			"type": e.signal_type,
			"label": e.label,
			"id": e.signal_id,
		})
	return {
		"discovered": discovered_signals.duplicate(),
		"bookmarks": bookmarks.duplicate(true),
		"log": log_data,
		"beacon_log": beacon_log.duplicate(true),
	}
func load_save_data(data: Dictionary) -> void:
	discovered_signals.clear()
	var disc: Array = data.get("discovered", [])
	for d in disc:
		discovered_signals.append(str(d))
	bookmarks.clear()
	var bm: Array = data.get("bookmarks", [])
	for b in bm:
		bookmarks.append(b as Dictionary)
	signal_log.clear()
	var log_arr: Array = data.get("log", [])
	for l in log_arr:
		var ld: Dictionary = l as Dictionary
		var entry := SignalLogEntry.new()
		entry.time_str = str(ld.get("time", ""))
		entry.frequency = float(ld.get("freq", 0))
		entry.band = str(ld.get("band", ""))
		entry.azimuth = float(ld.get("azimuth", 0))
		entry.signal_type = str(ld.get("type", ""))
		entry.label = str(ld.get("label", ""))
		entry.signal_id = str(ld.get("id", ""))
		signal_log.append(entry)
	# ★ 恢复信标日志
	beacon_log.clear()
	var bl_arr: Array = data.get("beacon_log", [])
	for bl_item in bl_arr:
		beacon_log.append(bl_item as Dictionary)
