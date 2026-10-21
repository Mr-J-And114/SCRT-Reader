# 常驻天气台：每轮冻结天气数据，只在新一轮更新，不写公共电台目录。
class_name WeatherBroadcast
extends RefCounted

const CONFIG_PATH: String = "res://radio/weather_broadcast.json"
const SIGNAL_ID: String = "weather_broadcast"
const WEATHER_NAMES: Dictionary = {
	"clear": "CLEAR", "partly_cloudy": "PARTLY CLOUDY", "overcast": "OVERCAST",
	"rain": "RAIN", "storm": "STORM", "snow": "SNOW", "fog": "FOG",
	"blizzard": "BLIZZARD"
}
const WIND_NAMES: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

var config: Dictionary = {
	"enabled": true, "frequency": 0.25, "band": "LF", "callsign": "CORE",
	"azimuth": 320.0, "elevation": 15.0,
	"label": "示例气象广播", "speed_wpm": 22, "omnidirectional": false,
	"tolerance_freq": 0.08, "proximity_range": 0.15,
	"refresh_seconds": 60.0, "pause_seconds": 8.0, "source": "regional",
	"fields": ["air_temp", "wind", "visibility", "wave_height", "pressure"]
}
var snapshot: Dictionary = {}
var report: String = ""
var _capture_ticks: int = -1
var _context: String = ""
var _monitor = null

func _init() -> void:
	if FileAccess.file_exists(CONFIG_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if parsed is Dictionary:
			config.merge(parsed, true)

func ensure_signal(manager: RadioSignalManager) -> RadioConfigParser.RadioSignal:
	if not bool(config.get("enabled", true)):
		manager.remove_signal(SIGNAL_ID)
		return null
	for item in manager.signals:
		if item.id == SIGNAL_ID:
			_configure_signal(item)
			return item
	var sig := RadioConfigParser.RadioSignal.new()
	sig.id = SIGNAL_ID
	_configure_signal(sig)
	manager.add_signal(sig)
	return sig

func _configure_signal(sig: RadioConfigParser.RadioSignal) -> void:
	sig.type = "morse"
	sig.frequency = float(config.get("frequency", 0.25))
	sig.band = str(config.get("band", "LF")).to_upper()
	sig.azimuth = float(config.get("azimuth", 320.0))
	sig.elevation = float(config.get("elevation", 15.0))
	sig.label = str(config.get("label", "示例气象广播"))
	sig.speed_wpm = maxi(5, int(config.get("speed_wpm", 22)))
	sig.tolerance_freq = maxf(0.001, float(config.get("tolerance_freq", 0.08)))
	sig.proximity_range = maxf(sig.tolerance_freq, float(config.get("proximity_range", 0.15)))
	sig.omnidirectional = bool(config.get("omnidirectional", false))
	sig.hidden = false
	sig.loop = false # 由接收器逐轮启动，以便刷新报文。
	sig.character_set = ""
	sig.content_file = ""
	sig.content_text = report if not report.is_empty() else "VVV DE CORE WX DATA UNAVAILABLE AR"

func prepare_round(monitor, sig: RadioConfigParser.RadioSignal) -> void:
	refresh(monitor)
	var pause_ms: int = int(maxf(0.0, float(config.get("pause_seconds", 8.0))) * 1000.0)
	sig.content_text = report + " {pause=%d}" % pause_ms

func invalidate() -> void:
	_capture_ticks = -1
	_context = ""
	snapshot.clear()
	report = ""
	_monitor = null

func refresh(monitor, force: bool = false) -> void:
	var ticks: int = Time.get_ticks_msec()
	var context: String = ""
	if monitor != null:
		context = "%d/%s/%s/%s" % [monitor.current_day, monitor.current_weather, monitor.master_seed, str(monitor.weather_reference_metadata.get("weather", ""))]
	var interval: int = int(maxf(1.0, float(config.get("refresh_seconds", 60.0))) * 1000.0)
	if not force and monitor == _monitor and context == _context and _capture_ticks >= 0 and ticks - _capture_ticks < interval:
		return
	_capture_ticks = ticks
	_context = context
	_monitor = monitor
	if monitor == null:
		snapshot = {}
		report = "VVV DE %s WX DATA UNAVAILABLE AR" % str(config.get("callsign", "CORE"))
		return
	var readings: Dictionary = monitor.get_all_readings()
	snapshot = {
		"day": monitor.current_day, "time": monitor.get_current_hour_display(),
		"weather": monitor.current_weather, "readings": readings.duplicate(true)
	}
	if str(config.get("source", "regional")) == "regional":
		snapshot = monitor.get_weather_reference_snapshot()
		readings = snapshot.get("readings", {})
	snapshot["source"] = str(config.get("source", "regional"))
	var parts: Array[String] = ["VVV DE " + str(config.get("callsign", "CORE")), "WX",
		"DAY %d TIME %s" % [int(snapshot.get("day", monitor.current_day)), str(snapshot.get("time", "0000")).replace(":", "")],
		str(WEATHER_NAMES.get(str(snapshot.get("weather", "")), "UNAVAILABLE"))]
	for field in config.get("fields", []):
		match str(field):
			"air_temp": parts.append("TEMP " + _number(readings, "air_temp") + " C")
			"wind":
				var direction: float = float(readings.get("wind_dir", NAN))
				var name: String = "UNAVAILABLE"
				if is_finite(direction):
					name = WIND_NAMES[posmod(roundi(direction / 45.0), 8)]
				parts.append("WIND FROM " + name + " " + _number(readings, "wind_speed") + " M/S")
			"visibility":
				var vis: float = float(readings.get("visibility", NAN))
				parts.append("VIS " + ("%d M" % roundi(vis * 1000.0) if is_finite(vis) and vis < 1.0 else _number(readings, "visibility") + " KM"))
			"wave_height": parts.append("WAVE " + _number(readings, "wave_height") + " M")
			"pressure": parts.append("PRESS " + _number(readings, "pressure") + " HPA")
	parts.append("AR")
	report = " ".join(parts)

func _number(readings: Dictionary, key: String) -> String:
	var value: float = float(readings.get(key, NAN))
	if not is_finite(value):
		return "UNAVAILABLE"
	var rounded: float = snappedf(value, 0.1)
	return ("MINUS " if rounded < 0.0 else "") + ("%.1f" % absf(rounded))
