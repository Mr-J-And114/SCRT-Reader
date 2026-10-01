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
#  枚举
# ══════════════════════════════════════════
enum SensorState { OPTIMAL, NOMINAL, DEGRADED, MALFUNCTION, OFFLINE }
enum AnomalyLevel { LEVEL_0, LEVEL_1, LEVEL_2, LEVEL_3, LEVEL_4 }
enum ScanMode { QUICK, STANDARD, FOCUSED, DEEP }

# ══════════════════════════════════════════
#  模拟状态
# ══════════════════════════════════════════
var master_seed: int = 0               # 全局主种子（每个存档唯一）
var current_day: int = 1               # 当前天数
var current_hour: float = 6.0          # 当前小时 (0.0~24.0)，由系统时钟驱动
var _update_accumulator: float = 0.0   # 传感器刷新间隔累积器
var _weather_timer: float = 0.0        # 天气切换计时器（真实秒数）

## ★ 剧情版本（由 main 从主线 manifest 同步；存档版本不匹配时自动重置进度）
var save_story_version: String = ""

## 当前传感器读数
var current_readings: Dictionary = {}  # sensor_id -> float
## 传感器状态 (SensorState 枚举值)
var sensor_status: Dictionary = {}     # sensor_id -> "online"/"offline"/"degraded"/"optimal"/"malfunction"
## 传感器校准偏移（漂移模拟）
var calibration_offsets: Dictionary = {} # sensor_id -> float
## 最近 24 小时的读数历史（用于趋势分析）
var reading_history: Dictionary = {}   # sensor_id -> Array[{hour, value}]
## 气压历史（用于 3h 趋势计算）
var _pressure_history: Array[Dictionary] = []  # [{time_sec, value}]

## 天气
var current_weather: String = "partly_cloudy"
var daily_weather_base: String = ""    # 当日基础天气（由种子决定）

## 活跃事件
var active_events: Dictionary = {}     # event_id -> {start_day, end_day, effects}
## 已检测的异常（包含等级信息）
var detected_anomalies: Array[Dictionary] = []
## 当天已发现但未记录的异常
var pending_anomalies: Array[Dictionary] = []

## ★ 异常等级系统
var anomaly_levels: Dictionary = {}    # anomaly_id -> int (0-4)
var anomaly_consecutive_days: Dictionary = {}  # anomaly_id -> int
var anomaly_suppressed: Dictionary = {}  # anomaly_id -> bool (被校准压制的异常)

## ★ 传感器状态追踪
var sensor_state_hours: Dictionary = {}  # sensor_id -> float (上次校准/修复后的小时数)
var sensor_calibrated_this_scan: Dictionary = {}  # sensor_id -> bool (本次扫描是否校准过)

## ★ 扫描模式与精度
var current_scan_mode: int = ScanMode.STANDARD  # 当前扫描模式
var scan_focused_sectors: Array = []    # 重点扫描的分区 ID 列表
var sector_precision_modifiers: Dictionary = {}  # sector_id -> float (精度偏移量)

## ★ 玩家选择记录（存档用）
var env_choices: Dictionary = {
	"daily_scan_mode": "",
	"anomaly_responses": {},
	"report_focus_items": [],
	"investigation_leads": [],
}

## 风向（需要特殊处理的循环角度）
var current_wind_dir: float = 0.0
var target_wind_dir: float = 0.0

## 潮汐相位（半日潮）
var tide_phase: float = 0.0

## 派生参数缓存（每次 _regenerate_readings 后更新）
var derived_readings: Dictionary = {}  # "dew_point", "wind_chill", "heat_index", "feels_like", "beaufort", "pressure_tendency"

## RNG
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _day_rng: RandomNumberGenerator = RandomNumberGenerator.new()

## 配置缓存（从 env_config.json 加载的新增字段）
var scan_sectors_cfg: Dictionary = {}     # sector_id -> {name, sensors, base_duration, deep_duration}
var scan_modes_cfg: Dictionary = {}    # mode_id -> {name, description, precision_modifier, ...}
var anomaly_evolution_cfg: Dictionary = {}  # 异常演化配置
var anomaly_story_links: Dictionary = {}   # anomaly_id -> story link config
var sensor_states_cfg: Dictionary = {}  # 传感器状态配置

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
	# ★ 新增配置字段
	scan_sectors_cfg = config.get("scan_sectors", {})
	scan_modes_cfg = config.get("scan_modes", {})
	anomaly_evolution_cfg = config.get("anomaly_evolution", {})
	anomaly_story_links = config.get("anomaly_story_links", {})
	sensor_states_cfg = config.get("sensor_states", {})
	print("[EnvMonitor] 配置加载完成: %d 传感器, %d 天气模式, %d 事件类型, %d 扫描分区" % [
		sensors.size(), weather_patterns.size(), event_defs.size(), scan_sectors_cfg.size()])

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
		"sensor_status": sensor_status.duplicate(),
		"calibration_offsets": calibration_offsets.duplicate(),
		"current_weather": current_weather,
		"weather_timer": _weather_timer,
		"active_events": active_events.duplicate(true),
		"detected_anomalies": detected_anomalies.duplicate(true),
		"current_wind_dir": current_wind_dir,
		"tide_phase": tide_phase,
		"anomaly_levels": anomaly_levels.duplicate(),
		"anomaly_consecutive_days": anomaly_consecutive_days.duplicate(),
		"anomaly_suppressed": anomaly_suppressed.duplicate(),
		"sensor_state_hours": sensor_state_hours.duplicate(),
		"current_scan_mode": current_scan_mode,
		"scan_focused_sectors": scan_focused_sectors.duplicate(),
		"env_choices": env_choices.duplicate(true),
		"story_version": save_story_version,
	}

func load_save_data(data: Dictionary) -> void:
	master_seed = int(data.get("master_seed", 0))
	current_day = int(data.get("current_day", 0))
	if data.has("sensor_status"):
		for k in data["sensor_status"]:
			sensor_status[k] = data["sensor_status"][k]
	if data.has("calibration_offsets"):
		for k in data["calibration_offsets"]:
			calibration_offsets[k] = float(data["calibration_offsets"][k])
	current_weather = str(data.get("current_weather", "partly_cloudy"))
	_weather_timer = float(data.get("weather_timer", 0.0))
	if data.has("active_events"):
		active_events = data["active_events"]
	if data.has("detected_anomalies"):
		detected_anomalies.clear()
		for a in data["detected_anomalies"]:
			detected_anomalies.append(a)
	current_wind_dir = float(data.get("current_wind_dir", 0.0))
	tide_phase = float(data.get("tide_phase", 0.0))
	# ★ 新增存档字段
	if data.has("anomaly_levels"):
		anomaly_levels = data["anomaly_levels"]
	if data.has("anomaly_consecutive_days"):
		anomaly_consecutive_days = data["anomaly_consecutive_days"]
	if data.has("anomaly_suppressed"):
		anomaly_suppressed = data["anomaly_suppressed"]
	if data.has("sensor_state_hours"):
		sensor_state_hours = data["sensor_state_hours"]
	if data.has("current_scan_mode"):
		current_scan_mode = int(data["current_scan_mode"])
	if data.has("scan_focused_sectors"):
		scan_focused_sectors = data["scan_focused_sectors"]
	if data.has("env_choices"):
		env_choices = data["env_choices"]
	# 同步系统时钟 + 重新生成当前读数
	_sync_system_clock()
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
	current_day = 0
	_sync_system_clock()
	_update_accumulator = 0.0
	_weather_timer = 0.0
	_pressure_history.clear()
	detected_anomalies.clear()
	pending_anomalies.clear()
	active_events.clear()
	_init_day()

func advance_day() -> void:
	current_day += 1
	_sync_system_clock()
	_update_accumulator = 0.0
	_weather_timer = 0.0
	_pressure_history.clear()
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
	var update_interval: float = float(time_cfg.get("update_interval_seconds", 5.0))
	var weather_shift_sec: float = float(time_cfg.get("weather_shift_interval_minutes", 45.0)) * 60.0

	# ── 系统时钟同步 ──
	_sync_system_clock()

	# ── 潮汐相位（由当前真实小时直接计算） ──
	tide_phase = fmod(current_hour / TIDE_PERIOD_HOURS, 1.0) * TAU

	# ── 风向缓慢变化 ──
	_update_wind_direction(delta)

	# ── 天气切换（真实秒数计时） ──
	_weather_timer += delta
	if _weather_timer >= weather_shift_sec:
		_weather_timer -= weather_shift_sec
		_shift_weather()

	# ── 定期更新读数 ──
	_update_accumulator += delta
	if _update_accumulator >= update_interval:
		_update_accumulator -= update_interval
		_regenerate_readings()
		_record_history()
		_record_pressure_history()
		_check_anomalies()

	# ── 检查事件结束 ──
	_check_events()


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
	_weather_timer = 0.0
	if old != current_weather:
		weather_changed.emit(old, current_weather)

func _shift_weather() -> void:
	# 天气切换：由气压趋势驱动方向，叠加随机
	var old: String = current_weather
	var tendency: String = get_pressure_tendency()
	# 气压下降 → 偏向恶劣天气；上升 → 偏向好天气
	var bad_bias: float = 0.0
	match tendency:
		"falling_fast": bad_bias = 0.6
		"falling": bad_bias = 0.3
		"rising": bad_bias = -0.3
		"rising_fast": bad_bias = -0.5
	if _rng.randf() < 0.35:
		# 回到当日基础天气
		current_weather = daily_weather_base
	else:
		var month: int = _get_current_month()
		var candidates: Array = []
		var weights: Array = []
		for pid in weather_patterns.keys():
			var p: Dictionary = weather_patterns[pid]
			if p.has("season_months") and not p["season_months"].has(month):
				continue
			candidates.append(pid)
			var w: float = float(p.get("probability_weight", 10))
			# 气压趋势影响：恶劣天气（高乘数风速）加权
			var wind_mult: float = float(p.get("modifiers", {}).get("wind_speed_mult", 1.0))
			if wind_mult > 1.5:
				w *= (1.0 + bad_bias)
			elif wind_mult < 0.8:
				w *= (1.0 - bad_bias)
			weights.append(maxf(w, 0.1))
		if candidates.size() > 0:
			var total: float = 0.0
			for w in weights:
				total += w
			var roll: float = _rng.randf() * total
			var cum: float = 0.0
			for i in range(candidates.size()):
				cum += weights[i]
				if roll <= cum:
					current_weather = candidates[i]
					break
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
	# ── 传感器间物理关联 ──
	_apply_cross_sensor_correlations()
	# ── 派生参数计算 ──
	_compute_derived_readings()

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
	# 触发邮件（通过直接注入 temp_inbox 实现，无需 mail 文件）
	if edef.get("triggers_mail", false) and main and main.get("mail_sys"):
		var subject: String = str(edef.get("mail_subject", "环境事件通知: " + str(edef.get("name", eid))))
		subject = subject.replace("{name}", str(edef.get("name", "")))
		subject = subject.replace("{kp_index}", str(_day_rng.randi_range(4, 9)))
		subject = subject.replace("{code}", "%04d" % _day_rng.randi_range(1000, 9999))
		var body: String = "操作员，\n\n" + str(edef.get("description", "")) + "\n预计持续 " + str(dur) + " 天。\n请密切监控相关参数。\n\n—— 总部气象处"
		var mail_id: String = "env_event_" + eid + "_day" + str(current_day)
		var mail_entry: Dictionary = {
			"id": mail_id,
			"title": subject,
			"from": "HQ-MET",
			"template": "email",
			"priority": "high" if edef.get("scp_related", false) else "normal",
			"read": false,
			"delivered_at": Time.get_datetime_string_from_system(),
			"persistent": false,
			"story_id": "",
			"_body_text": body,
		}
		if "_temp_inbox" in main.mail_sys:
			main.mail_sys._temp_inbox.append(mail_entry)
			if main.mail_sys.has_method("_rebuild_merged"):
				main.mail_sys._rebuild_merged()
			if "has_new_mail" in main:
				main.has_new_mail = true
			main.mail_sys.start_blink()

	# 触发特效（通过 main 的安全接口，自动处理预设和光敏降级）
	if edef.has("triggers_effect") and main:
		var fx_id: String = str(edef["triggers_effect"])
		if main.has_method("trigger_preset_effect"):
			main.trigger_preset_effect(fx_id)
		elif main.has_method("trigger_effect"):
			main.trigger_effect(fx_id)

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
#  ★ 异常等级系统
# ══════════════════════════════════════════

## 获取异常当前等级（0-4），未初始化返回 0
func get_anomaly_level(anomaly_id: String) -> int:
	return anomaly_levels.get(anomaly_id, 0)

## 设置异常等级，并更新连续天数追踪
func set_anomaly_level(anomaly_id: String, level: int) -> void:
	level = clampi(level, 0, 4)
	var old_level: int = anomaly_levels.get(anomaly_id, 0)
	anomaly_levels[anomaly_id] = level
	if level > old_level:
		# 等级提升时重置连续计数（新的严重程度需要重新累积）
		if not anomaly_consecutive_days.has(anomaly_id):
			anomaly_consecutive_days[anomaly_id] = 0
	elif level == 0:
		# 异常消失，清除追踪
		anomaly_consecutive_days.erase(anomaly_id)
		anomaly_suppressed.erase(anomaly_id)

## 每小时 tick 调用：未处理的异常有概率升级
func evolve_anomalies() -> void:
	var evolve_chance: float = anomaly_evolution_cfg.get("escalate_chance_per_level", 0.10)
	var suppress_chance: float = anomaly_evolution_cfg.get("suppress_chance_calibrate", 0.7)
	for anomaly_id in anomaly_levels.keys():
		var level: int = anomaly_levels[anomaly_id]
		if level <= 0 or level >= 4:
			continue
		var was_suppressed: bool = anomaly_suppressed.get(anomaly_id, false)
		if was_suppressed:
			# 被校准压制的异常有概率重新浮现
			if randf() < (1.0 - suppress_chance):
				anomaly_suppressed[anomaly_id] = false
				set_anomaly_level(anomaly_id, level)  # 恢复可见
				continue
		# 未压制异常有概率升级
		var escalate_prob: float = evolve_chance * level
		if randf() < escalate_prob:
			set_anomaly_level(anomaly_id, level + 1)
			anomaly_consecutive_days[anomaly_id] = anomaly_consecutive_days.get(anomaly_id, 0) + 1

## 玩家对异常做出响应，返回结果字典
func respond_to_anomaly(anomaly_id: String, response: String) -> Dictionary:
	var level: int = get_anomaly_level(anomaly_id)
	var result: Dictionary = {"anomaly_id": anomaly_id, "response": response, "level_before": level}
	var resolve_chance: float = anomaly_evolution_cfg.get("resolve_chance_investigate", 0.5)
	match response:
		"log":
			# 记录并上报——异常仍在，但 HQ 介入
			result["outcome"] = "reported"
			result["message"] = "已记录异常 [%s] 并上报 HQ。" % [anomaly_id]
		"investigate":
			# 深入调查——有机会定性（不再升级）
			if randf() < resolve_chance:
				result["outcome"] = "resolved"
				result["message"] = "深入调查后，异常 [%s] 已被定性，不再演化。" % [anomaly_id]
				set_anomaly_level(anomaly_id, 0)
			else:
				result["outcome"] = "inconclusive"
				result["message"] = "调查未得出明确结论，但获取了额外数据。"
				anomaly_consecutive_days[anomaly_id] = anomaly_consecutive_days.get(anomaly_id, 0) + 1
		"flag":
			# 标记待查——不消耗时间，但异常可能升级
			result["outcome"] = "flagged"
			result["message"] = "异常 [%s] 已标记待查，下次扫描时优先关注。" % [anomaly_id]
		"calibrate":
			# 自行校准——压制异常（若真实 SCP 事件会再浮现）
			anomaly_suppressed[anomaly_id] = true
			result["outcome"] = "suppressed"
			result["message"] = "已执行校准，异常 [%s] 被压制。若是设备故障则已解决；若非自然异常则会再浮现。" % [anomaly_id]
			# 检查是否是 SCP 关联异常——如果不是，校准即修复
			var story_links: Array = anomaly_story_links.get(anomaly_id, [])
			if story_links.is_empty():
				# 非叙事关联异常，校准即修复
				set_anomaly_level(anomaly_id, 0)
				result["outcome"] = "fixed"
				result["message"] = "校准成功，传感器已恢复正常读数。"
		_:
			result["outcome"] = "unknown"
			result["message"] = "未知响应类型。"
	# 记录到玩家选择
	if not env_choices.has("anomaly_responses"):
		env_choices["anomaly_responses"] = {}
	var key: String = "%s_day%d" % [anomaly_id, current_day]
	env_choices["anomaly_responses"][key] = response
	return result

## 检查异常是否触发叙事关联
func check_anomaly_story_triggers() -> Array[Dictionary]:
	var triggers: Array[Dictionary] = []
	for anomaly_id in anomaly_story_links.keys():
		var link_config: Dictionary = anomaly_story_links[anomaly_id]
		var trigger_level: int = link_config.get("trigger_level", 2)
		var current_level: int = get_anomaly_level(anomaly_id)
		if current_level < trigger_level:
			continue
		# 检查连续天数条件
		var required_days: int = link_config.get("consecutive_days", 0)
		if required_days > 0:
			var consecutive: int = anomaly_consecutive_days.get(anomaly_id, 0)
			if consecutive < required_days:
				continue
		# 检查时间窗口条件
		if link_config.has("time_window"):
			var window: Array = link_config["time_window"]
			if current_hour < window[0] or current_hour > window[1]:
				continue
		# 条件满足——触发叙事关联
		var trigger: Dictionary = {
			"anomaly_id": anomaly_id,
			"story_unlock": link_config.get("story_unlock", ""),
			"level": current_level,
			"type": "anomaly_story"
		}
		if trigger["story_unlock"] != "":
			triggers.append(trigger)
	return triggers

# ══════════════════════════════════════════
#  ★ 传感器状态机
# ══════════════════════════════════════════

## 获取传感器状态枚举值
func get_sensor_state_enum(sensor_id: String) -> int:
	var status_str: String = sensor_status.get(sensor_id, "nominal")
	match status_str:
		"optimal":
			return SensorState.OPTIMAL
		"nominal":
			return SensorState.NOMINAL
		"degraded":
			return SensorState.DEGRADED
		"malfunction":
			return SensorState.MALFUNCTION
		"offline":
			return SensorState.OFFLINE
		_:
			return SensorState.NOMINAL

## 设置传感器状态
func set_sensor_state(sensor_id: String, state: int) -> void:
	var state_names: Array = ["optimal", "nominal", "degraded", "malfunction", "offline"]
	if state >= 0 and state < state_names.size():
		sensor_status[sensor_id] = state_names[state]
		if state == SensorState.MALFUNCTION:
			sensor_failure.emit(sensor_id)

## 获取传感器精度修正值（基于状态 + 扫描模式）
func get_sensor_precision(sensor_id: String) -> int:
	var precision: int = 0
	# 传感器状态修正
	var state: int = get_sensor_state_enum(sensor_id)
	match state:
		SensorState.OPTIMAL:
			precision += 1
		SensorState.DEGRADED:
			precision -= 1
		SensorState.MALFUNCTION:
			precision -= 2
		SensorState.OFFLINE:
			precision -= 3
	# 扫描模式修正
	var mode_cfg: Dictionary = _get_scan_mode_config()
	precision += int(mode_cfg.get("precision_modifier", 0))
	# 分区重点修正
	var sector: String = _get_sector_for_sensor(sensor_id)
	if sector != "" and scan_focused_sectors.has(sector):
		precision += 2
	return precision

## 获取传感器所属扫描分区
func _get_sector_for_sensor(sensor_id: String) -> String:
	if not scan_sectors_cfg.has("_sector_map"):
		# 构建一次查找表
		var sector_map: Dictionary = {}
		for sector_id in scan_sectors_cfg.keys():
			var sensors_arr: Array = scan_sectors_cfg[sector_id].get("sensors", [])
			for s in sensors_arr:
				sector_map[s] = sector_id
		scan_sectors_cfg["_sector_map"] = sector_map
	var sector_map: Dictionary = scan_sectors_cfg.get("_sector_map", {})
	return sector_map.get(sensor_id, "")

## 每小时 tick 调用：根据运行时长更新传感器状态
func update_sensor_states(hours_elapsed: float) -> void:
	var degrade_hours: float = sensor_states_cfg.get("degradation_threshold_hours", 48.0)
	for sid in sensors.keys():
		if not sensor_state_hours.has(sid):
			sensor_state_hours[sid] = 0.0
		sensor_state_hours[sid] += hours_elapsed
		var state: int = get_sensor_state_enum(sid)
		var hours: float = sensor_state_hours[sid]
		# 自动降级（仅在 NOMINAL/DEGRADED 状态）
		if state == SensorState.NOMINAL and hours > degrade_hours:
			set_sensor_state(sid, SensorState.DEGRADED)
		elif state == SensorState.DEGRADED and hours > degrade_hours * 2:
			set_sensor_state(sid, SensorState.MALFUNCTION)
		# 事件影响降级
		if active_events.size() > 0:
			for _eid in active_events:
				var ev: Dictionary = active_events[_eid]
				var effects: Dictionary = ev.get("effects", {})
				if effects.has("sensor_damage"):
					var damaged: Array = effects["sensor_damage"]
					if damaged.has(sid) and state < SensorState.MALFUNCTION:
						set_sensor_state(sid, state + 1)

## 校准传感器交互步骤——返回当前偏差和是否完成
func calibrate_sensor_interactive(sensor_id: String, adjustment: float) -> Dictionary:
	var state: int = get_sensor_state_enum(sensor_id)
	if state == SensorState.OFFLINE:
		return {"success": false, "message": "传感器 %s 离线，需要重启而非校准。" % sensor_id}
	# 获取当前偏差
	if not calibration_offsets.has(sensor_id):
		return {"success": false, "message": "传感器 %s 无校准数据。" % sensor_id}
	var current_offset: float = calibration_offsets[sensor_id]
	var new_offset: float = current_offset - adjustment
	# 检查偏差阈值
	var threshold: float = 0.02  # 2% 即完成校准
	var sensor_cfg: Dictionary = sensors.get(sensor_id, {})
	threshold = float(sensor_cfg.get("calibration_threshold", 0.02))
	calibration_offsets[sensor_id] = new_offset
	var is_done: bool = absf(new_offset) < threshold
	if is_done:
		# 校准成功
		calibration_offsets[sensor_id] = 0.0
		sensor_state_hours[sensor_id] = 0.0  # 重置降级计时
		if state >= SensorState.DEGRADED:
			set_sensor_state(sensor_id, state - 1)  # 提升一级
		sensor_calibrated_this_scan[sensor_id] = true
	else:
		# 调整过大可能反而更偏
		if absf(new_offset) > absf(current_offset) + 0.01:
			# 偏差增大——可能导致状态降级
			if randf() < 0.15:
				set_sensor_state(sensor_id, mini(state + 1, SensorState.OFFLINE))
				return {"success": false, "message": "校准偏差增大！传感器 %s 状态降级至 %s。" % [sensor_id, sensor_status.get(sensor_id, "unknown")], "new_offset": new_offset, "done": false}
	return {"success": true, "message": "偏差调整: %.3f → %.3f%s" % [current_offset, new_offset, " — 校准完成！" if is_done else ""], "new_offset": new_offset, "done": is_done}

# ══════════════════════════════════════════
#  ★ 扫描模式管理
# ══════════════════════════════════════════

## 设置当前扫描模式
func set_scan_mode(mode: int, focused_sectors: Array = []) -> void:
	current_scan_mode = mode
	scan_focused_sectors = focused_sectors
	# 计算分区精度修正
	sector_precision_modifiers.clear()
	var mode_cfg: Dictionary = _get_scan_mode_config()
	var base_mod: int = int(mode_cfg.get("precision_modifier", 0))
	for sector_id in scan_sectors_cfg.keys():
		if sector_id.begins_with("_"):
			continue
		if focused_sectors.has(sector_id):
			sector_precision_modifiers[sector_id] = base_mod + 2
		else:
			sector_precision_modifiers[sector_id] = base_mod - 1 if mode == ScanMode.FOCUSED else base_mod
	env_choices["daily_scan_mode"] = ScanMode.keys()[mode] if mode < ScanMode.size() else "STANDARD"

## 获取当前扫描模式配置
func _get_scan_mode_config() -> Dictionary:
	var mode_names: Array = ["quick", "standard", "focused", "deep"]
	var mode_key: String = mode_names[current_scan_mode] if current_scan_mode < mode_names.size() else "standard"
	return scan_modes_cfg.get(mode_key, {})

## 新扫描周期开始时调用——重置分区精度和校准追踪
func begin_new_scan_cycle() -> void:
	sector_precision_modifiers.clear()
	sensor_calibrated_this_scan.clear()

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
	if current_day == 0:
		return "Day 0（教程日）"
	return "第 %d 天" % current_day

func get_display_date() -> String:
	## 返回虚构日期字符串 (YYYY-MM-DD)
	var time_cfg: Dictionary = config.get("time", {})
	var year: int = int(time_cfg.get("fictional_year", 2024))
	var start_m: int = int(time_cfg.get("fictional_start_month", 10))
	var start_d: int = int(time_cfg.get("fictional_start_day", 15))
	var days_in_month: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var remaining: int = start_d + current_day - 2  # -1 for 0-based, -1 because day1=start_day
	var month: int = start_m
	while remaining >= days_in_month[(month - 1) % 12]:
		remaining -= days_in_month[(month - 1) % 12]
		month += 1
		if month > 12:
			month = 1
			year += 1
	var day: int = remaining + 1
	return "%d-%02d-%02d" % [year, month, day]

# ══════════════════════════════════════════
#  系统时钟同步
# ══════════════════════════════════════════
func _sync_system_clock() -> void:
	## 从操作系统读取真实时间，更新 current_hour
	var sys: Dictionary = Time.get_time_dict_from_system()
	current_hour = float(sys["hour"]) + float(sys["minute"]) / 60.0 + float(sys["second"]) / 3600.0

# ══════════════════════════════════════════
#  传感器间物理关联
# ══════════════════════════════════════════
func _apply_cross_sensor_correlations() -> void:
	## 基于已生成的读数，应用交叉物理约束
	var pressure: float = current_readings.get("pressure", 1013.0)
	var humidity: float = current_readings.get("humidity", 70.0)
	var air_temp: float = current_readings.get("air_temp", 10.0)
	var wind_speed: float = current_readings.get("wind_speed", 5.0)
	var precip: float = current_readings.get("precipitation", 0.0)
	var visibility: float = current_readings.get("visibility", 15.0)

	# 1) 气压趋势影响风速：气压快速下降 → 风速增大
	var tendency: String = get_pressure_tendency()
	match tendency:
		"falling_fast":
			current_readings["wind_speed"] = _clamp_sensor("wind_speed", wind_speed * 1.3)
		"falling":
			current_readings["wind_speed"] = _clamp_sensor("wind_speed", wind_speed * 1.1)

	# 2) 高湿度 + 低温 → 雾（降低能见度）
	if humidity > 93.0 and air_temp < 8.0:
		var fog_factor: float = remap(humidity, 93.0, 100.0, 0.7, 0.2)
		current_readings["visibility"] = _clamp_sensor("visibility", visibility * fog_factor)
		visibility = current_readings["visibility"]

	# 3) 降水量 → 进一步降低能见度
	if precip > 2.0:
		var rain_vis_factor: float = maxf(0.15, 1.0 - precip * 0.04)
		current_readings["visibility"] = _clamp_sensor("visibility", visibility * rain_vis_factor)

	# 4) 强风 → 增加浪高
	var ws: float = current_readings.get("wind_speed", 5.0)
	if ws > 10.0:
		var wave: float = current_readings.get("wave_height", 1.0)
		var wind_wave_add: float = (ws - 10.0) * 0.15
		current_readings["wave_height"] = _clamp_sensor("wave_height", wave + wind_wave_add)

func _clamp_sensor(sid: String, val: float) -> float:
	## 将值钳位到传感器定义的范围内
	var cfg: Dictionary = sensors.get(sid, {})
	var range_arr = cfg.get("range", [])
	if range_arr is Array and range_arr.size() >= 2:
		val = clampf(val, float(range_arr[0]), float(range_arr[1]))
	var prec: int = int(cfg.get("precision", 1))
	var mult: float = pow(10.0, prec)
	return roundf(val * mult) / mult

# ══════════════════════════════════════════
#  派生参数计算（大气科学公式）
# ══════════════════════════════════════════
func _compute_derived_readings() -> void:
	var t: float = current_readings.get("air_temp", 10.0)
	var rh: float = current_readings.get("humidity", 70.0)
	var ws: float = current_readings.get("wind_speed", 5.0)

	derived_readings["dew_point"] = _calc_dew_point(t, rh)
	derived_readings["wind_chill"] = _calc_wind_chill(t, ws)
	derived_readings["heat_index"] = _calc_heat_index(t, rh)
	derived_readings["feels_like"] = _calc_feels_like(t, rh, ws)
	derived_readings["beaufort"] = get_beaufort_scale()
	derived_readings["pressure_tendency"] = get_pressure_tendency()
	derived_readings["weather_forecast"] = get_weather_forecast()

func _calc_dew_point(t: float, rh: float) -> float:
	## Magnus 公式计算露点温度
	if rh <= 0.0:
		return t - 30.0
	var a: float = 17.625
	var b: float = 243.04
	var alpha: float = log(clampf(rh, 0.1, 100.0) / 100.0) + (a * t) / (b + t)
	return snappedf(b * alpha / (a - alpha), 0.1)

func _calc_wind_chill(t: float, ws: float) -> float:
	## 加拿大标准风寒指数（适用于 T<10°C，V>4.8km/h）
	var v_kmh: float = ws * 3.6  # m/s → km/h
	if t >= 10.0 or v_kmh < 4.8:
		return t
	var wc: float = 13.12 + 0.6215 * t - 11.37 * pow(v_kmh, 0.16) + 0.3965 * t * pow(v_kmh, 0.16)
	return snappedf(wc, 0.1)

func _calc_heat_index(t: float, rh: float) -> float:
	## Rothfusz 回归方程（适用于 T>27°C，RH>40%）
	if t < 27.0 or rh < 40.0:
		return t
	# 使用华氏度计算
	var tf: float = t * 9.0 / 5.0 + 32.0
	var hi: float = -42.379 + 2.04901523 * tf + 10.14333127 * rh \
		- 0.22475541 * tf * rh - 0.00683783 * tf * tf \
		- 0.05481717 * rh * rh + 0.00122874 * tf * tf * rh \
		+ 0.00085282 * tf * rh * rh - 0.00000199 * tf * tf * rh * rh
	# 转回摄氏
	return snappedf((hi - 32.0) * 5.0 / 9.0, 0.1)

func _calc_feels_like(t: float, rh: float, ws: float) -> float:
	## 体感温度：低温用风寒，高温用热指数，中间用实际
	if t < 10.0:
		return _calc_wind_chill(t, ws)
	elif t > 27.0 and rh > 40.0:
		return _calc_heat_index(t, rh)
	return t

func get_beaufort_scale() -> int:
	## 蒲福风力等级 (0-12)
	var ws: float = current_readings.get("wind_speed", 0.0)
	var thresholds: Array[float] = [0.5, 1.5, 3.3, 5.5, 8.0, 10.8, 13.9, 17.2, 20.7, 24.5, 28.4, 32.6]
	for i in range(thresholds.size()):
		if ws < thresholds[i]:
			return i
	return 12

func get_pressure_tendency() -> String:
	## 3 小时气压趋势：rising_fast / rising / steady / falling / falling_fast
	if _pressure_history.size() < 2:
		return "steady"
	var now_sec: float = float(Time.get_unix_time_from_system())
	# 找到 3 小时前最接近的记录
	var target_sec: float = now_sec - 10800.0  # 3h = 10800s
	var oldest_val: float = _pressure_history[0].get("value", 1013.0)
	for entry in _pressure_history:
		if float(entry.get("time_sec", 0)) >= target_sec:
			oldest_val = float(entry.get("value", 1013.0))
			break
	var current_p: float = current_readings.get("pressure", 1013.0)
	var delta_p: float = current_p - oldest_val
	if delta_p > 3.5:
		return "rising_fast"
	elif delta_p > 1.0:
		return "rising"
	elif delta_p < -3.5:
		return "falling_fast"
	elif delta_p < -1.0:
		return "falling"
	return "steady"

func get_pressure_change_3h() -> float:
	## 返回 3 小时内气压变化量 (hPa)
	if _pressure_history.size() < 2:
		return 0.0
	var now_sec: float = float(Time.get_unix_time_from_system())
	var target_sec: float = now_sec - 10800.0
	var oldest_val: float = _pressure_history[0].get("value", 1013.0)
	for entry in _pressure_history:
		if float(entry.get("time_sec", 0)) >= target_sec:
			oldest_val = float(entry.get("value", 1013.0))
			break
	return current_readings.get("pressure", 1013.0) - oldest_val

func get_weather_forecast() -> String:
	## 基于气压趋势的简易天气预报
	var tendency: String = get_pressure_tendency()
	match tendency:
		"falling_fast":
			return "风暴可能接近，注意防范"
		"falling":
			return "天气可能转差"
		"rising_fast":
			return "天气正在好转"
		"rising":
			return "天气趋于稳定"
	return "天气相对稳定"

func get_derived_readings() -> Dictionary:
	return derived_readings.duplicate()

func _record_pressure_history() -> void:
	## 记录气压值到 3h 滑动窗口
	var p: float = current_readings.get("pressure", 1013.0)
	if is_nan(p):
		return
	var now_sec: float = float(Time.get_unix_time_from_system())
	_pressure_history.append({"time_sec": now_sec, "value": p})
	# 仅保留 3.5 小时内的记录
	var cutoff: float = now_sec - 12600.0
	while _pressure_history.size() > 0 and float(_pressure_history[0].get("time_sec", 0)) < cutoff:
		_pressure_history.pop_front()

# ══════════════════════════════════════════
#  工具函数
# ══════════════════════════════════════════
func _get_current_month() -> int:
	## 根据虚构起始日期 + 当前天数推算月份
	var time_cfg: Dictionary = config.get("time", {})
	var start_m: int = int(time_cfg.get("fictional_start_month", 10))
	var start_d: int = int(time_cfg.get("fictional_start_day", 15))
	var days_in_month: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var remaining: int = start_d + current_day - 2
	var month: int = start_m
	while remaining >= days_in_month[(month - 1) % 12]:
		remaining -= days_in_month[(month - 1) % 12]
		month += 1
		if month > 12:
			month = 1
	return month

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

# ══════════════════════════════════════════
#  玩家专属存档（跨磁盘/跨会话持久化）
# ══════════════════════════════════════════
func _get_env_progress_path() -> String:
	if main == null:
		return ""
	if not main.get("user_mgr") or not main.user_mgr.is_logged_in:
		return ""
	if main.get("save_mgr") == null:
		return ""
	var user_dir: String = main.save_mgr.get_game_root_dir() + "saves/" + main.user_mgr.get_username() + "/"
	return user_dir + "env_progress.json"

func save_env_progress() -> void:
	var path: String = _get_env_progress_path()
	if path.is_empty():
		return
	var dir_path: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(get_save_data(), "\t"))
		file.close()

func load_env_progress() -> bool:
	var path: String = _get_env_progress_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not (json.data is Dictionary):
		file.close()
		return false
	file.close()
	# ★ 剧情版本门控：主线剧情版本变化时视为无有效进度（重新开始）
	if save_story_version != "" and \
			str((json.data as Dictionary).get("story_version", "")) != save_story_version:
		print("[EnvMonitor] 剧情版本不匹配（%s → %s），重置环境进度" % [
			str((json.data as Dictionary).get("story_version", "")), save_story_version])
		return false
	load_save_data(json.data)
	print("[EnvMonitor] 玩家进度已加载: 第 %d 天" % current_day)
	return true
