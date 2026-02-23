# ============================================================
# radio_config_parser.gd - 无线电信号源配置解析器
# 负责：解析 signals.cfg / 摩斯密码内容文件 / 信号源管理
# ============================================================
class_name RadioConfigParser
extends RefCounted

# ══════════════════════════════════════════
#  信号数据结构
# ══════════════════════════════════════════

## 单个信号源的完整描述
class RadioSignal:
	extends RefCounted
	var id: String = ""
	var type: String = "morse"            # "morse" | "sstv"
	var frequency: float = 14.300         # MHz
	var band: String = "HF"              # LF | HF | VHF | UHF
	var azimuth: float = 0                  # 0-359°
	var elevation: float = 0                # 0-90°
	var tolerance_freq: float = 0.05      # ±MHz
	var tolerance_dir: int = 20           # ±度
	var content_file: String = ""         # 摩斯内容文件路径 / SSTV图片路径
	var content_text: String = ""         # 加载后的文本内容（摩斯）
	var content_image: PackedByteArray = PackedByteArray()  # 加载后的图片数据（SSTV）
	var loop: bool = false
	var speed_wpm: int = 15
	var label: String = ""
	var hint: String = ""
	var sstv_mode: String = "Martin M1"   # Martin M1 | Scottie S1 | Robot 36 | PD120
	var transmit_duration: float = 114.0
	var character_set: String = ""        # "" = 正常, "numbers" = 数字电台
	var ephemeral: bool = false           # 短暂信号
	var reappear_interval: float = 0.0    # 重现间隔（秒）
	var discovered_flag: String = ""

	# ★ 第一阶段扩展
	var beacon_id: String = ""			# 信标呼号（如 "VVV DE XX3YZ"），非空时视为信标
	var cipher_type: String = ""		  # 加密类型: "" | "caesar" | "vigenere" | "otp"
	var cipher_key_file: String = ""	  # 密钥文件路径（相对包根）
	var group_size: int = 5			   # 数字电台分组大小（每组几个字符）
	var group_pause_ms: float = 1500.0	# 数字电台组间停顿（毫秒）
	var repeat_count: int = 2			 # 数字电台整段重复次数（0=不限）


# ══════════════════════════════════════════
#  波段定义
# ══════════════════════════════════════════

const BAND_RANGES: Dictionary = {
	"LF":  { "min": 0.1,   "max": 0.5,    "step": 0.001 },
	"HF":  { "min": 1.8,   "max": 30.0,   "step": 0.005 },
	"VHF": { "min": 30.0,  "max": 300.0,  "step": 0.025 },
	"UHF": { "min": 300.0, "max": 3000.0, "step": 0.1   },
}

const BAND_ORDER: Array[String] = ["LF", "HF", "VHF", "UHF"]

# ══════════════════════════════════════════
#  解析主入口
# ══════════════════════════════════════════

## 从虚拟文件系统解析信号配置
## fs: FileSystem 引用
## 返回: Array[RadioSignal]
static func parse_signals(fs) -> Array:
	var signals: Array = []

	# 查找 signals.cfg（优先 /radio/signals.cfg，其次 /signals.cfg）
	var cfg_paths: Array[String] = ["/radio/signals.cfg", "/signals.cfg"]
	var cfg_content: String = ""
	var cfg_dir: String = "/"

	for path in cfg_paths:
		var node = fs.get_node_at_path(path)
		if node != null and node.type == "file":
			cfg_content = str(node.content)
			cfg_dir = path.get_base_dir()
			if cfg_dir.is_empty():
				cfg_dir = "/"
			break

	if cfg_content.is_empty():
		return signals

	# 解析 INI 风格配置
	var current_signal: RadioSignal = null
	var current_id: String = ""

	var lines: PackedStringArray = cfg_content.split("\n")
	for line in lines:
		var stripped: String = line.strip_edges()

		# 跳过空行和注释
		if stripped.is_empty() or stripped.begins_with("#"):
			continue

		# Section 头: [signal_id]
		if stripped.begins_with("[") and stripped.ends_with("]"):
			# 保存上一个信号
			if current_signal != null:
				current_signal.id = current_id
				signals.append(current_signal)

			current_id = stripped.substr(1, stripped.length() - 2).strip_edges()
			current_signal = RadioSignal.new()
			continue

		# 键值对: key = "value" 或 key = value
		if current_signal == null:
			continue

		var eq_pos: int = stripped.find("=")
		if eq_pos == -1:
			continue

		var key: String = stripped.substr(0, eq_pos).strip_edges()
		var value: String = stripped.substr(eq_pos + 1).strip_edges()

		# 去除引号
		if value.begins_with("\"") and value.ends_with("\""):
			value = value.substr(1, value.length() - 2)

		_apply_signal_property(current_signal, key, value)

	# 保存最后一个信号
	if current_signal != null:
		current_signal.id = current_id
		signals.append(current_signal)

	# 加载内容文件
	for sig in signals:
		var s: RadioSignal = sig as RadioSignal
		if s.content_file.is_empty():
			continue

		var content_path: String = s.content_file
		if not content_path.begins_with("/"):
			content_path = _join_path(cfg_dir, content_path)
		content_path = fs.normalize_path(content_path)

		if s.type == "morse":
			var node = fs.get_node_at_path(content_path)
			if node != null and node.type == "file":
				s.content_text = str(node.content)
		elif s.type == "sstv":
			if fs.has_method("get_binary_data"):
				s.content_image = fs.get_binary_data(content_path)

	print("[RadioConfigParser] 解析完成，共 ", signals.size(), " 个信号源")
	return signals

## 设置信号属性
static func _apply_signal_property(sig: RadioSignal, key: String, value: String) -> void:
	match key:
		"type":
			sig.type = value
		"frequency":
			sig.frequency = value.to_float()
		"band":
			sig.band = value.to_upper()
		"azimuth":
			sig.azimuth = value.to_float()
		"elevation":
			sig.elevation = value.to_float()
		"tolerance_freq":
			sig.tolerance_freq = value.to_float()
		"tolerance_dir":
			sig.tolerance_dir = int(value.to_float())
		"content_file":
			sig.content_file = value
		"loop":
			sig.loop = value.to_lower() == "true"
		"speed_wpm":
			sig.speed_wpm = int(value.to_float())
		"label":
			sig.label = value
		"hint":
			sig.hint = value
		"sstv_mode":
			sig.sstv_mode = value
		"transmit_duration":
			sig.transmit_duration = value.to_float()
		"character_set":
			sig.character_set = value
		"ephemeral":
			sig.ephemeral = value.to_lower() == "true"
		"reappear_interval":
			sig.reappear_interval = value.to_float()
		"discovered_flag":
			sig.discovered_flag = value
		# ★ 第一阶段扩展（旧版 signals.cfg 兼容）
		"beacon_id":
			sig.beacon_id = value
		"cipher_type":
			sig.cipher_type = value
		"cipher_key_file":
			sig.cipher_key_file = value
		"group_size":
			sig.group_size = int(value.to_float())
		"group_pause_ms":
			sig.group_pause_ms = value.to_float()
		"repeat_count":
			sig.repeat_count = int(value.to_float())


static func _join_path(base: String, relative: String) -> String:
	if base.ends_with("/"):
		return base + relative
	return base + "/" + relative



# ══════════════════════════════════════════
# ★ 新增：从 manifest.json 的 radio_signals 数组解析
# ══════════════════════════════════════════
static func parse_signals_from_manifest(manifest: Dictionary, fs) -> Array:
	var signals: Array = []
	if not manifest.has("radio_signals"):
		return signals

	var radio_cfg = manifest["radio_signals"]

	# ── 格式1：radio_signals.signals 是一个 { id: { props } } 字典 ──
	if radio_cfg is Dictionary and radio_cfg.has("signals"):
		var sig_dict = radio_cfg["signals"]
		if sig_dict is Dictionary:
			for sig_id in sig_dict:
				var entry = sig_dict[sig_id]
				if not (entry is Dictionary):
					continue
				var sig := RadioSignal.new()
				sig.id = str(sig_id)
				_apply_manifest_entry(sig, entry)
				signals.append(sig)

	# ── 格式2：radio_signals 直接是一个 Array[{ id, ... }] ──
	elif radio_cfg is Array:
		for entry in radio_cfg:
			if not (entry is Dictionary):
				continue
			var sig := RadioSignal.new()
			sig.id = str(entry.get("id", ""))
			_apply_manifest_entry(sig, entry)
			signals.append(sig)

	else:
		push_warning("[RadioConfigParser] radio_signals 格式无法识别")
		return signals

	# 加载内容文件
	for sig_item in signals:
		var s: RadioSignal = sig_item as RadioSignal
		if s.content_file.is_empty():
			continue
		var content_path: String = s.content_file
		if not content_path.begins_with("/"):
			content_path = "/" + content_path
		content_path = fs.normalize_path(content_path)

		if s.type == "morse":
			var node = fs.get_node_at_path(content_path)
			if node != null and node.type == "file":
				s.content_text = str(node.content)
		elif s.type == "sstv":
			if fs.has_method("get_binary_data"):
				s.content_image = fs.get_binary_data(content_path)

	print("[RadioConfigParser] 从 manifest 解析完成，共 ", signals.size(), " 个信号源")
	return signals


## ★ 从 manifest 字典条目填充信号属性
static func _apply_manifest_entry(sig: RadioSignal, entry: Dictionary) -> void:
	sig.type = str(entry.get("type", "morse"))
	sig.frequency = float(entry.get("frequency", 14.3))
	sig.band = str(entry.get("band", "HF")).to_upper()
	sig.azimuth = float(entry.get("azimuth", 0.0))
	sig.elevation = float(entry.get("elevation", 0.0))
	sig.tolerance_freq = float(entry.get("tolerance_freq", 0.05))
	sig.tolerance_dir = int(entry.get("tolerance_dir", 20))
	sig.content_file = str(entry.get("content_file", ""))
	sig.loop = bool(entry.get("loop", false))
	sig.speed_wpm = int(entry.get("speed_wpm", 15))
	sig.label = str(entry.get("label", ""))
	sig.hint = str(entry.get("hint", ""))
	sig.sstv_mode = str(entry.get("sstv_mode", "Martin M1"))
	sig.transmit_duration = float(entry.get("transmit_duration", 114.0))
	sig.character_set = str(entry.get("character_set", ""))
	sig.ephemeral = bool(entry.get("ephemeral", false))
	sig.reappear_interval = float(entry.get("reappear_interval", 0.0))
	sig.discovered_flag = str(entry.get("discovered_flag", ""))
	sig.beacon_id = str(entry.get("beacon_id", ""))
	sig.cipher_type = str(entry.get("cipher_type", ""))
	sig.cipher_key_file = str(entry.get("cipher_key_file", ""))
	sig.group_size = int(entry.get("group_size", 5))
	sig.group_pause_ms = float(entry.get("group_pause_ms", 1500.0))
	sig.repeat_count = int(entry.get("repeat_count", 2))



	
