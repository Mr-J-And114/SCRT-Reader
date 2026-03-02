# ============================================================
# env_monitor.gd
# 环境监测系统核心 —— 数据生成 + 传感器模拟 + 异常检测
#
# 基于萨哈林岛气候基线，通过每日随机种子驱动自然变化。
# 支持天气模式、特殊事件、SCP异常叠加。
# .scp 故事包可通过 manifest 覆盖/扩展所有参数。
# ============================================================
class_name EnvMonitor
extends RefCounted

# ══════════════════════════════════════════
#  信号
# ══════════════════════════════════════════
signal day_changed(day_number: int)
signal anomaly_detected(anomaly_id: String, data: Dictionary)
signal sensor_failure(sensor_id: String)
signal weather_changed(old_pattern: String, new_pattern: String)
signal event_started(event_id: String, event_data: Dictionary)
signal event_ended(event_id: String)

# ══════════════════════════════════════════
#  引用
# ══════════════════════════════════════════
var main = null
var T = null

# ══════════════════════════════════════════
#  配置（从 env_config.json 加载 + 故事包覆盖）
# ══════════════════════════════════════════
var config: Dictionary = {}
var sensors: Dictionary = {}           # sensor_id -> sensor config dict
var baselines: Dictionary = {}         # sensor_id -> [12 monthly values]
var variation: Dictionary = {}         # variation parameters
var weather_patterns: Dictionary = {}  # pattern_id -> config
var anomaly_types: Dictionary = {}     # anomaly_id -> config
var event_defs: Dictionary = {}        # event_id -> config
var task_defs: Dictionary = {}         # task_id -> config

# ══════════════════════════════════════════
#  模拟状态
# ══════════════════════════════════════════
var master_seed: int = 0               # 全局主种子（每个存档唯一）
var current_day: int = 1               # 当前天数
var current_hour: float = 6.0          # 当前小时 (0.0~24.0)
var game_time_accumulator: float = 0.0 # 游戏时间累积器

## 当前传感器读数
var current_readings: Dictionary = {}  # sensor_id -> float
## 传感器状态 (online/offline/degraded)
var sensor_status: Dictionary = {}     # sensor_id -> "online"/"offline"/"degraded"
## 传感器校准偏移（漂移模拟）
var calibration_offsets: Dictionary = {} # sensor_id -> float
## 最近 24 小时的读数历史（用于趋势分析）
var reading_history: Dictionary = {}   # sensor_id -> Array[{hour, value}]

## 天气
var current_weather: String = "partly_cloudy"
var weather_duration_remaining: float = 0.0  # 当前天气剩余时间（小时）
var daily_weather_base: String = ""    # 当日基础天气（由种子决定）

## 活跃事件
var active_events: Dictionary = {}     # event_id -> {start_day, end_day, effects}
## 已检测的异常
var detected_anomalies: Array[Dictionary] = []
## 当天已发现但未记录的异常
var pending_anomalies: Array[Dictionary] = []

## 风向（需要特殊处理的循环角度）
var current_wind_dir: float = 0.0
var target_wind_dir: float = 0.0

## 潮汐相位（半日潮）
var tide_phase: float = 0.0

## RNG
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _day_rng: RandomNumberGenerator = RandomNumberGenerator.new()

# ══════════════════════════════════════════
#  常量
# ══════════════════════════════════════════
const TIDE_PERIOD_HOURS: float = 12.42  # 半日潮周期
const CONFIG_PATH: String = "res://data/env_config.json"

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(p_main, p_theme) -> void:
	main = p_main
	T = p_theme
	_load_config()
	_init_sensors()

func _load_config() -> void:
	var path: String = CONFIG_PATH
	if main and main.has_method("get") and main.get("save_mgr"):
		var root: String = main.save_mgr.get_game_root_dir()
		var local: String = root + "data/env_config.json"
		if FileAccess.file_exists(local):
			path = local
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[EnvMonitor] 无法加载环境配置: " + path)
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
		config = json.data
	f.close()
	# 解包子配置
	sensors = config.get("sensors", {})
	baselines = config.get("baselines", {})
	variation = config.get("variation", {})
	weather_patterns = config.get("weather_patterns", {})
	anomaly_types = config.get("anomaly_types", {})
	event_defs = config.get("events", {})
	task_defs = config.get("tasks", {})
	print("[EnvMonitor] 配置加载完成: %d 传感器, %d 天气模式, %d 事件类型" % [
		sensors.size(), weather_patterns.size(), event_defs.size()])

func _init_sensors() -> void:
	for sid in sensors.keys():
		current_readings[sid] = 0.0
		sensor_status[sid] = "online"
		calibration_offsets[sid] = 0.0
		reading_history[sid] = []

# ══════════════════════════════════════════
#  存档
# ══════════════════════════════════════════
func get_save_data() -> Dictionary:
	return {
		"master_seed": master_seed,
		"current_day": current_day,
		"current_hour": current_hour,
		"sensor_status": sensor_status.duplicate(),
		"calibration_offsets": calibration_offsets.duplicate(),
		"current_weather": current_weather,
		"weather_duration": weather_duration_remaining,
		"active_events": active_events.duplicate(true),
		"detected_anomalies": detected_anomalies.duplicate(true),
		"current_wind_dir": current_wind_dir,
		"tide_phase": tide_phase,
	}

func load_save_data(data: Dictionary) -> void:
	master_seed = int(data.get("master_seed", 0))
	current_day = int(data.get("current_day", 1))
	current_hour = float(data.get("current_hour", 6.0))
	if data.has("sensor_status"):
		for k in data["sensor_status"]:
			sensor_status[k] = data["sensor_status"][k]
	if data.has("calibration_offsets"):
		for k in data["calibration_offsets"]:
			calibration_offsets[k] = float(data["calibration_offsets"][k])
	current_weather = str(data.get("current_weather", "partly_cloudy"))
	weather_duration_remaining = float(data.get("weather_duration", 0.0))
	if data.has("active_events"):
		active_events = data["active_events"]
	if data.has("detected_anomalies"):
		detected_anomalies.clear()
		for a in data["detected_anomalies"]:
			detected_anomalies.append(a)
	current_wind_dir = float(data.get("current_wind_dir", 0.0))
	tide_phase = float(data.get("tide_phase", 0.0))
	# 重新生成当前读数
	_regenerate_readings()

# ══════════════════════════════════════════
#  新游戏/新一天 初始化
# ══════════════════════════════════════════
func start_new_game(seed_value: int = 0) -> void:
	if seed_value == 0:
		_rng.randomize()
		master_seed = _rng.randi()
	else:
		master_seed = seed_value
	current_day = 1
	current_hour = 6.0
	game_time_accumulator = 0.0
	detected_anomalies.clear()
	pending_anomalies.clear()
	active_events.clear()
	_init_day()

func advance_day() -> void:
	current_day += 1
	current_hour = 6.0
	game_time_accumulator = 0.0
	pending_anomalies.clear()
	_init_day()
	day_changed.emit(current_day)

func _init_day() -> void:
	# 用主种子 + 天数 生成当日种子
	_day_rng.seed = _hash_seed(master_seed, current_day)
	# 生成当日天气
	_generate_daily_weather()
	# 生成传感器校准漂移
	_generate_calibration_drift()
	# 检查传感器故障
	_check_sensor_failures()
	# 生成/检查特殊事件
	_check_events()
	# 生成当前读数
	_regenerate_readings()

# ══════════════════════════════════════════
#  每帧驱动（由 main._process 调用）
# ══════════════════════════════════════════
func process(delta: float) -> void:
	var time_cfg: Dictionary = config.get("time", {})
	var time_scale: float = float(time_cfg.get("time_scale", 144.0))
	var update_interval: float = float(time_cfg.get("update_interval_seconds", 5.0))

	game_time_accumulator += delta
	# 推进游戏内时间
	var hour_delta: float = (delta * time_scale) / 3600.0
	current_hour += hour_delta
	# 潮汐相位推进
	tide_phase += hour_delta / TIDE_PERIOD_HOURS * TAU
	if tide_phase > TAU:
		tide_phase -= TAU
	# 风向缓慢变化
	_update_wind_direction(delta)
	# 天气持续时间递减
	weather_duration_remaining -= hour_delta
	if weather_duration_remaining <= 0:
		_shift_weather()
	# 定期更新读数
	if game_time_accumulator >= update_interval:
		game_time_accumulator -= update_interval
		_regenerate_readings()
		_record_history()
		_check_anomalies()
	# 检查事件结束
	_update_events()

# ══════════════════════════════════════════
#  天气生成
# ══════════════════════════════════════════
func _generate_daily_weather() -> void:
	var month: int = _get_current_month()
	var weights: Array = []
	var ids: Array = []
	for pid in weather_patterns.keys():
		var p: Dictionary = weather_patterns[pid]
		# 季节限制
		if p.has("season_months"):
			var sm: Array = p["season_months"]
			if not sm.has(month):
				continue
		var w: float = float(p.get("probability_weight", 10))
		weights.append(w)
		ids.append(pid)
	var total: float = 0.0
	for w in weights:
		total += w
	var roll: float = _day_rng.randf() * total
	var cumulative: float = 0.0
	for i in range(ids.size()):
		cumulative += weights[i]
		if roll <= cumulative:
			daily_weather_base = ids[i]
			break
	if daily_weather_base.is_empty() and ids.size() > 0:
		daily_weather_base = ids[0]
	var old: String = current_weather
	current_weather = daily_weather_base
	weather_duration_remaining = _day_rng.randf_range(4.0, 12.0)
	if old != current_weather:
		weather_changed.emit(old, current_weather)

func _shift_weather() -> void:
	# 天气持续结束后，有概率变化或维持
	var old: String = current_weather
	if _day_rng.randf() < 0.4:
		# 回到当日基础天气
		current_weather = daily_weather_base
	else:
		# 随机小幅变化 (偏向相邻类型)
		var month: int = _get_current_month()
		var candidates: Array = []
		for pid in weather_patterns.keys():
			var p: Dictionary = weather_patterns[pid]
			if p.has("season_months") and not p["season_months"].has(month):
				continue
			candidates.append(pid)
		if candidates.size() > 0:
			current_weather = candidates[_day_rng.randi() % candidates.size()]
	weather_duration_remaining = _day_rng.randf_range(2.0, 8.0)
	if old != current_weather:
		weather_changed.emit(old, current_weather)

# ══════════════════════════════════════════
#  传感器读数生成
# ══════════════════════════════════════════
func _regenerate_readings() -> void:
	var month: int = _get_current_month()
	var month_idx: int = month - 1  # 0-based
	var hour: float = fmod(current_hour, 24.0)

	# 获取天气修正
	var wx_mod: Dictionary = {}
	if weather_patterns.has(current_weather):
		wx_mod = weather_patterns[current_weather].get("modifiers", {})

	# 获取事件修正
	var evt_mods: Dictionary = _get_event_modifiers()

	for sid in sensors.keys():
		if sensor_status.get(sid, "online") == "offline":
			current_readings[sid] = NAN
			continue

		var base_arr = baselines.get(sid, [])
		if base_arr is Array and base_arr.size() >= 12:
			var base: float = float(base_arr[month_idx])
			# 月际插值（和下个月平滑过渡）
			var next_month_idx: int = (month_idx + 1) % 12
			var day_of_month: float = float(current_day % 30) / 30.0
			var base_next: float = float(base_arr[next_month_idx])
			base = lerp(base, base_next, day_of_month)
			# 日内温度变化（正弦曲线，午后最高、黎明最低）
			var diurnal: float = _get_diurnal_factor(sid, hour)
			base += diurnal
			# 日间随机变化
			var daily_var_key: String = sid + "_daily"
			var daily_std: float = float(variation.get(daily_var_key, 0.0))
			if daily_std > 0:
				base += _seeded_normal(_hash_seed(master_seed, current_day * 1000 + sensors.keys().find(sid))) * daily_std
			# 小时随机波动
			var hourly_var_key: String = sid + "_hourly"
			var hourly_std: float = float(variation.get(hourly_var_key, 0.0))
			if hourly_std > 0:
				base += _seeded_normal(_hash_seed(master_seed, current_day * 100000 + int(hour) * 100 + sensors.keys().find(sid))) * hourly_std
			# 天气修正
			base = _apply_weather_modifier(sid, base, wx_mod)
			# 事件修正
			base = _apply_event_modifier(sid, base, evt_mods)
			# 校准偏移
			base += calibration_offsets.get(sid, 0.0)
			# 传感器退化加噪
			if sensor_status.get(sid) == "degraded":
				base += _rng.randf_range(-2.0, 2.0)
			# 范围钳位
			var cfg: Dictionary = sensors.get(sid, {})
			var range_arr = cfg.get("range", [])
			if range_arr is Array and range_arr.size() >= 2:
				base = clampf(base, float(range_arr[0]), float(range_arr[1]))
			# 精度处理
			var prec: int = int(cfg.get("precision", 1))
			var mult: float = pow(10.0, prec)
			base = roundf(base * mult) / mult
			current_readings[sid] = base
		else:
			# 特殊传感器的独立生成逻辑
			current_readings[sid] = _generate_special_sensor(sid, month_idx, hour, wx_mod, evt_mods)

	# 潮位使用半日潮模型
	_generate_tide(month_idx, wx_mod, evt_mods)
	# 光照根据太阳高度角
	_generate_light(month_idx, hour)
	# 风向
	current_readings["wind_dir"] = current_wind_dir

func _get_diurnal_factor(sid: String, hour: float) -> float:
	# 各参数有不同的日变化曲线
	match sid:
		"air_temp":
			# 气温：凌晨5时最低，午后14时最高
			return sin((hour - 5.0) / 24.0 * TAU) * float(variation.get("air_temp_hourly", 1.5)) * 2.0
		"humidity":
			# 湿度：与气温反相
			return -sin((hour - 5.0) / 24.0 * TAU) * float(variation.get("humidity_hourly", 3.0))
		"pressure":
			# 气压：半日波（大气潮汐），10时和22时最高
			return sin((hour - 4.0) / 12.0 * TAU) * 0.5
		"wind_speed":
			# 风速：午后最大，夜间较小
			return sin((hour - 6.0) / 24.0 * TAU) * float(variation.get("wind_speed_hourly", 1.5)) * 0.5
		"sea_temp":
			# 海温日变化很小
			return sin((hour - 8.0) / 24.0 * TAU) * 0.3
		"soil_temp":
			# 地温日变化较气温滞后且幅度小
			return sin((hour - 8.0) / 24.0 * TAU) * 1.0
		_:
			return 0.0

func _apply_weather_modifier(sid: String, base: float, wx_mod: Dictionary) -> float:
	# 乘法修正
	var mult_key: String = sid + "_mult"
	if wx_mod.has(mult_key):
		base *= float(wx_mod[mult_key])
	# 特殊映射
	match sid:
		"cloud_cover":
			if wx_mod.has("cloud_cover_mult"):
				base = roundf(8.0 * float(wx_mod["cloud_cover_mult"]))
		"precipitation":
			if wx_mod.has("precipitation_mult"):
				base *= float(wx_mod["precipitation_mult"])
		"visibility":
			if wx_mod.has("visibility_mult"):
				base *= float(wx_mod["visibility_mult"])
		"wind_speed":
			if wx_mod.has("wind_speed_mult"):
				base *= float(wx_mod["wind_speed_mult"])
	# 加法修正
	var add_key: String = sid + "_add"
	if wx_mod.has(add_key):
		base += float(wx_mod[add_key])
	# 通用加法
	if sid == "humidity" and wx_mod.has("humidity_add"):
		base += float(wx_mod["humidity_add"])
	if sid == "air_temp" and wx_mod.has("air_temp_add"):
		base += float(wx_mod["air_temp_add"])
	return base

func _apply_event_modifier(sid: String, base: float, evt_mods: Dictionary) -> float:
	# 事件加法
	var add_key: String = sid + "_add"
	if evt_mods.has(add_key):
		var val = evt_mods[add_key]
		if val is Array and val.size() >= 2:
			# 范围随机
			base += _rng.randf_range(float(val[0]), float(val[1]))
		else:
			base += float(val)
	# 事件乘法
	var mult_key: String = sid + "_mult"
	if evt_mods.has(mult_key):
		base *= float(evt_mods[mult_key])
	return base

func _get_event_modifiers() -> Dictionary:
	var combined: Dictionary = {}
	for eid in active_events.keys():
		var evt: Dictionary = active_events[eid]
		var effects: Dictionary = evt.get("effects", {})
		for k in effects.keys():
			if combined.has(k):
				# 叠加
				var existing = combined[k]
				var adding = effects[k]
				if existing is float and adding is float:
					combined[k] = existing + adding
				elif existing is Array or adding is Array:
					combined[k] = adding  # 用最新的
				else:
					combined[k] = float(existing) + float(adding)
			else:
				combined[k] = effects[k]
	return combined

func _generate_tide(month_idx: int, _wx_mod: Dictionary, evt_mods: Dictionary) -> void:
	var amp_arr = baselines.get("tide_amplitude", [])
	var amplitude: float = 1.0
	if amp_arr is Array and amp_arr.size() > month_idx:
		amplitude = float(amp_arr[month_idx])
	# 半日潮 + 微弱的全日分量
	var tide: float = amplitude * sin(tide_phase) + amplitude * 0.3 * sin(tide_phase * 0.5 + 0.5)
	# 事件修正
	var add = evt_mods.get("tide_level_add", 0.0)
	if add is Array and add is Array:
		tide += _rng.randf_range(float(add[0]), float(add[1]))
	elif add is float:
		tide += add
	# 随机波动
	tide += _rng.randf_range(-0.05, 0.05)
	current_readings["tide_level"] = snappedf(tide, 0.01)

func _generate_light(month_idx: int, hour: float) -> void:
	var daylight_arr = baselines.get("daylight_hours", [])
	var light_max_arr = baselines.get("light_max", [])
	var uv_max_arr = baselines.get("uv_max", [])
	var daylight: float = 12.0
	var light_max: float = 50000
	var uv_max: float = 5
	if daylight_arr is Array and daylight_arr.size() > month_idx:
		daylight = float(daylight_arr[month_idx])
	if light_max_arr is Array and light_max_arr.size() > month_idx:
		light_max = float(light_max_arr[month_idx])
	if uv_max_arr is Array and uv_max_arr.size() > month_idx:
		uv_max = float(uv_max_arr[month_idx])
	# 日出日落计算
	var sunrise: float = 12.0 - daylight / 2.0
	var sunset: float = 12.0 + daylight / 2.0
	var light: float = 0.0
	var uv: float = 0.0
	if hour >= sunrise and hour <= sunset:
		# 正弦曲线，正午最强
		var progress: float = (hour - sunrise) / (sunset - sunrise)
		var sun_factor: float = sin(progress * PI)
		light = light_max * sun_factor
		uv = uv_max * sun_factor
		# 云量衰减
		var cloud: float = float(current_readings.get("cloud_cover", 0))
		var cloud_factor: float = 1.0 - (cloud / 8.0) * 0.7
		light *= cloud_factor
		uv *= cloud_factor
	current_readings["light_level"] = roundf(maxf(0, light))
	current_readings["uv_index"] = roundi(maxf(0, uv))

func _generate_special_sensor(_sid: String, _month_idx: int, _hour: float, _wx_mod: Dictionary, _evt_mods: Dictionary) -> float:
	return 0.0

# ══════════════════════════════════════════
#  风向
# ══════════════════════════════════════════
func _update_wind_direction(delta: float) -> void:
	# 风向缓慢随机漫步
	if absf(current_wind_dir - target_wind_dir) < 2.0:
		var dir_var: float = float(variation.get("wind_dir_daily", 60))
		target_wind_dir = fmod(target_wind_dir + _rng.randf_range(-dir_var, dir_var), 360.0)
		if target_wind_dir < 0:
			target_wind_dir += 360.0
	# 角度插值（考虑圆周）
	var diff: float = fmod(target_wind_dir - current_wind_dir + 540.0, 360.0) - 180.0
	current_wind_dir += diff * delta * 0.1
	current_wind_dir = fmod(current_wind_dir + 360.0, 360.0)

# ══════════════════════════════════════════
#  校准漂移
# ══════════════════════════════════════════
func _generate_calibration_drift() -> void:
	for sid in sensors.keys():
		var cfg: Dictionary = sensors[sid]
		var max_drift: float = float(cfg.get("calibration_drift_max", 0.0))
		if max_drift > 0:
			calibration_offsets[sid] = _seeded_normal(_hash_seed(master_seed, current_day * 7 + sensors.keys().find(sid) * 3)) * max_drift * 0.5

func reset_calibration(sensor_id: String) -> void:
	calibration_offsets[sensor_id] = 0.0

# ══════════════════════════════════════════
#  传感器故障
# ══════════════════════════════════════════
func _check_sensor_failures() -> void:
	for sid in sensors.keys():
		var cfg: Dictionary = sensors[sid]
		var fail_rate: float = float(cfg.get("failure_rate", 0.0))
		var roll: float = _day_rng.randf()
		if roll < fail_rate * 0.3:
			sensor_status[sid] = "offline"
			sensor_failure.emit(sid)
		elif roll < fail_rate:
			sensor_status[sid] = "degraded"
		else:
			# 如果之前离线，有一定概率自动恢复
			if sensor_status.get(sid) == "offline" and _day_rng.randf() < 0.5:
				sensor_status[sid] = "degraded"
			elif sensor_status.get(sid) == "degraded" and _day_rng.randf() < 0.3:
				sensor_status[sid] = "online"

func repair_sensor(sensor_id: String) -> bool:
	if sensor_status.get(sensor_id, "online") != "online":
		sensor_status[sensor_id] = "online"
		calibration_offsets[sensor_id] = 0.0
		return true
	return false

# ══════════════════════════════════════════
#  特殊事件
# ══════════════════════════════════════════
func _check_events() -> void:
	# 清理已结束的事件
	var to_remove: Array = []
	for eid in active_events.keys():
		var evt: Dictionary = active_events[eid]
		if current_day > int(evt.get("end_day", current_day)):
			to_remove.append(eid)
			event_ended.emit(eid)
	for eid in to_remove:
		active_events.erase(eid)
	# 检查是否触发新事件
	var month: int = _get_current_month()
	for eid in event_defs.keys():
		if active_events.has(eid):
			continue
		var edef: Dictionary = event_defs[eid]
		# 季节检查
		if edef.has("season_months"):
			if not edef["season_months"].has(month):
				continue
		var prob: float = float(edef.get("probability_base", 0.0))
		if _day_rng.randf() < prob:
			_activate_event(eid, edef)

func _activate_event(eid: String, edef: Dictionary) -> void:
	var duration_range = edef.get("duration_days", [1, 1])
	var dur: int = 1
	if duration_range is Array and duration_range.size() >= 2:
		dur = _day_rng.randi_range(int(duration_range[0]), int(duration_range[1]))
	var evt_data: Dictionary = {
		"start_day": current_day,
		"end_day": current_day + dur - 1,
		"effects": edef.get("effects", {}),
		"name": edef.get("name", eid),
		"scp_related": edef.get("scp_related", false),
	}
	active_events[eid] = evt_data
	event_started.emit(eid, evt_data)
	# 触发邮件
	if edef.get("triggers_mail", false) and main and main.get("mail_sys"):
		var subject: String = str(edef.get("mail_subject", "环境事件通知: " + str(edef.get("name", eid))))
		subject = subject.replace("{name}", str(edef.get("name", "")))
		subject = subject.replace("{kp_index}", str(_day_rng.randi_range(4, 9)))
		subject = subject.replace("{code}", "%04d" % _day_rng.randi_range(1000, 9999))
		var body: String = "操作员，\n\n" + str(edef.get("description", "")) + "\n预计持续 " + str(dur) + " 天。\n请密切监控相关参数。\n\n—— 总部气象处"
		var mail_data: Dictionary = {
			"from": "HQ-MET",
			"subject": subject,
			"body": body,
			"priority": "high" if edef.get("scp_related", false) else "normal",
		}
		main.mail_sys.deliver_system_mail(mail_data)
	# 触发特效
	if edef.has("triggers_effect") and main and main.get("effect_sys"):
		main.effect_sys.play_preset(str(edef["triggers_effect"]))

func inject_event(event_id: String, event_config: Dictionary) -> void:
	## 外部注入事件（由 .scp 故事包或 mod 调用）
	event_defs[event_id] = event_config

func force_start_event(event_id: String) -> void:
	## 强制启动一个已定义的事件
	if event_defs.has(event_id):
		_activate_event(event_id, event_defs[event_id])

# ══════════════════════════════════════════
#  异常检测
# ══════════════════════════════════════════
func _check_anomalies() -> void:
	for aid in anomaly_types.keys():
		var adef: Dictionary = anomaly_types[aid]
		var sid: String = str(adef.get("sensor", ""))
		if sid.is_empty() or not current_readings.has(sid):
			continue
		var val: float = current_readings[sid]
		if is_nan(val):
			continue
		var triggered: bool = false
		var detail: Dictionary = {"anomaly_id": aid, "sensor": sid, "value": val, "day": current_day, "hour": current_hour}
		# 绝对阈值
		if adef.has("threshold_absolute"):
			if val > float(adef["threshold_absolute"]):
				triggered = true
				detail["type"] = "above_threshold"
		if adef.has("threshold_absolute_below"):
			if val < float(adef["threshold_absolute_below"]):
				triggered = true
				detail["type"] = "below_threshold"
		# 偏差阈值
		if adef.has("threshold_deviation"):
			var month_idx: int = _get_current_month() - 1
			var base_arr = baselines.get(sid, [])
			if base_arr is Array and base_arr.size() > month_idx:
				var expected: float = float(base_arr[month_idx])
				var deviation: float = absf(val - expected)
				if deviation > float(adef["threshold_deviation"]):
					triggered = true
					detail["type"] = "deviation"
					detail["expected"] = expected
					detail["deviation"] = deviation
		if triggered:
			# 检查是否已经记录过（同一天同一异常只记一次）
			var already: bool = false
			for pa in pending_anomalies:
				if pa.get("anomaly_id") == aid:
					already = true
					break
			if not already:
				detail["name"] = adef.get("name", aid)
				detail["severity"] = adef.get("severity", "info")
				detail["scp_related"] = adef.get("scp_related", false)
				detail["report"] = _format_anomaly_report(adef, detail)
				pending_anomalies.append(detail)
				anomaly_detected.emit(aid, detail)

func _format_anomaly_report(adef: Dictionary, detail: Dictionary) -> String:
	var template: String = str(adef.get("report_template", "异常检测: {value}"))
	template = template.replace("{value}", _fmt(detail.get("value", 0)))
	template = template.replace("{expected}", _fmt(detail.get("expected", 0)))
	template = template.replace("{deviation}", _fmt(detail.get("deviation", 0)))
	template = template.replace("{baseline}", _fmt(detail.get("expected", 0)))
	template = template.replace("{duration}", "持续中")
	template = template.replace("{delta}", _fmt(detail.get("deviation", 0)))
	template = template.replace("{o2}", _fmt(current_readings.get("o2_concentration", 20.9)))
	template = template.replace("{co2}", _fmt(current_readings.get("co2_concentration", 415)))
	return template

func confirm_anomalies() -> Array[Dictionary]:
	## 确认并归档当天的异常（玩家完成异常检查任务时调用）
	var confirmed: Array[Dictionary] = pending_anomalies.duplicate(true)
	for a in confirmed:
		detected_anomalies.append(a)
	pending_anomalies.clear()
	return confirmed

# ══════════════════════════════════════════
#  历史记录
# ══════════════════════════════════════════
func _record_history() -> void:
	for sid in sensors.keys():
		if not reading_history.has(sid):
			reading_history[sid] = []
		var arr: Array = reading_history[sid]
		arr.append({"hour": current_hour, "value": current_readings.get(sid, 0.0)})
		# 保留最近 48 条
		while arr.size() > 48:
			arr.pop_front()

func get_sensor_trend(sensor_id: String) -> String:
	## 返回传感器趋势: "rising"/"falling"/"stable"/"unknown"
	var arr: Array = reading_history.get(sensor_id, [])
	if arr.size() < 3:
		return "unknown"
	var recent: float = float(arr[arr.size() - 1].get("value", 0))
	var older: float = float(arr[arr.size() - 3].get("value", 0))
	var diff: float = recent - older
	var cfg: Dictionary = sensors.get(sensor_id, {})
	var threshold: float = float(cfg.get("calibration_drift_max", 1.0)) * 2.0
	if diff > threshold:
		return "rising"
	elif diff < -threshold:
		return "falling"
	return "stable"

# ══════════════════════════════════════════
#  故事包覆盖
# ══════════════════════════════════════════
func load_from_manifest(manifest: Dictionary) -> void:
	## 从 .scp manifest 加载环境覆盖
	var env_cfg: Dictionary = manifest.get("env_config", {})
	if env_cfg.is_empty():
		return
	# 覆盖位置
	if env_cfg.has("location"):
		for k in env_cfg["location"]:
			config["location"][k] = env_cfg["location"][k]
	# 覆盖/追加传感器
	if env_cfg.has("sensors"):
		for sid in env_cfg["sensors"]:
			sensors[sid] = env_cfg["sensors"][sid]
			if not current_readings.has(sid):
				current_readings[sid] = 0.0
				sensor_status[sid] = "online"
				calibration_offsets[sid] = 0.0
				reading_history[sid] = []
	# 覆盖基线
	if env_cfg.has("baselines"):
		for k in env_cfg["baselines"]:
			baselines[k] = env_cfg["baselines"][k]
	# 追加天气模式
	if env_cfg.has("weather_patterns"):
		for k in env_cfg["weather_patterns"]:
			weather_patterns[k] = env_cfg["weather_patterns"][k]
	# 追加异常类型
	if env_cfg.has("anomaly_types"):
		for k in env_cfg["anomaly_types"]:
			anomaly_types[k] = env_cfg["anomaly_types"][k]
	# 追加事件
	if env_cfg.has("events"):
		for k in env_cfg["events"]:
			event_defs[k] = env_cfg["events"][k]
	# 追加/覆盖任务
	if env_cfg.has("tasks"):
		for k in env_cfg["tasks"]:
			task_defs[k] = env_cfg["tasks"][k]
	# 设置主种子
	if env_cfg.has("master_seed"):
		master_seed = int(env_cfg["master_seed"])
	print("[EnvMonitor] 故事包环境覆盖已加载")

func clear_story_overrides() -> void:
	## 弹出磁盘时重置为默认配置
	_load_config()
	_init_sensors()

# ══════════════════════════════════════════
#  查询接口
# ══════════════════════════════════════════
func get_reading(sensor_id: String) -> float:
	return current_readings.get(sensor_id, NAN)

func get_all_readings() -> Dictionary:
	return current_readings.duplicate()

func get_sensor_config(sensor_id: String) -> Dictionary:
	return sensors.get(sensor_id, {})

func get_sensors_by_category(category: String) -> Array:
	var result: Array = []
	for sid in sensors.keys():
		if sensors[sid].get("category", "") == category:
			result.append(sid)
	return result

func get_weather_name() -> String:
	if weather_patterns.has(current_weather):
		return str(weather_patterns[current_weather].get("name", current_weather))
	return current_weather

func get_wind_direction_name() -> String:
	var dir: float = current_wind_dir
	var dirs: Array = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
	var idx: int = roundi(dir / 45.0) % 8
	return dirs[idx]

func get_active_events() -> Dictionary:
	return active_events.duplicate(true)

func get_pending_anomalies() -> Array[Dictionary]:
	return pending_anomalies.duplicate(true)

func get_detected_anomalies() -> Array[Dictionary]:
	return detected_anomalies.duplicate(true)

func is_sensor_online(sensor_id: String) -> bool:
	return sensor_status.get(sensor_id, "offline") != "offline"

func get_current_hour_display() -> String:
	var h: int = int(fmod(current_hour, 24.0))
	var m: int = int(fmod(current_hour * 60.0, 60.0))
	return "%02d:%02d" % [h, m]

func get_day_display() -> String:
	return "第 %d 天" % current_day

# ══════════════════════════════════════════
#  工具函数
# ══════════════════════════════════════════
func _get_current_month() -> int:
	# 根据天数推算月份（简化：每月30天，从1月开始）
	return (((current_day - 1) / 30) % 12) + 1

func _hash_seed(base: int, offset: int) -> int:
	# 简单哈希混合
	var h: int = base ^ (offset * 2654435761)
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = (h ^ (h >> 16)) * 0x45d9f3b
	return h & 0x7FFFFFFF

func _seeded_normal(seed_val: int) -> float:
	# Box-Muller 变换，从种子生成正态分布随机数
	var temp_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	temp_rng.seed = seed_val
	var u1: float = maxf(temp_rng.randf(), 0.0001)
	var u2: float = temp_rng.randf()
	return sqrt(-2.0 * log(u1)) * cos(TAU * u2)

func _fmt(val) -> String:
	if val is float:
		if absf(val) > 100:
			return "%d" % roundi(val)
		return "%.1f" % val
	return str(val)
