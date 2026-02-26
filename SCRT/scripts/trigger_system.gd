# ============================================================
# trigger_system.gd
# 触发器系统核心：条件检测、动作执行、触发链、一次性/重复
#
# ---- .meta.cfg 中 [triggers] 段格式 ----
#
# 基础条件:
#   on_enter = "动作"                          每次进入此目录
#   on_first_enter = "动作"                    仅首次进入此目录
#   on_open_file:filename.txt = "动作"         打开指定文件（一次性）
#
# 高级条件:
#   on_level_reach:3 = "动作"                  权限到达等级3时
#   on_read_complete:docs/report.txt = "动作"  指定文件被阅读后
#   on_command:scan = "动作"                   在此目录执行指定命令
#   on_idle:30 = "动作"                        空闲30秒后
#
# 修饰符（加在条件后面）:
#   on_enter.once = "动作"                    改为一次性（on_enter 默认可重复）
#   on_first_enter — 本身就是一次性，无需修饰符
#   on_command:scan.once = "动作"             改为一次性（on_command 默认可重复）
#
# 动作格式（分号分隔多动作）:
#   new_mail:mail_id                投递邮件
#   level_up:N                      提升权限到等级N
#   sound:path/sfx.ogg              播放音效
#   text:消息内容                   终端输出文字
#   redirect:/path                  自动 cd 到目录
#   glitch:0.8                      故障效果（0.1~2.0）
#   screen_off:2000                 屏幕关闭（毫秒）
#   reboot                          模拟重启
#   lock_folder:/path               锁定目录
#   unlock_folder:/path             解锁目录
#   delay:2000:其它动作             延迟后执行
# ============================================================
class_name TriggerSystem
extends RefCounted

var main: Control = null
var fs: FileSystem = null
var T: Variant = null
var mail_system = null  # MailSystem 引用（延迟注入）

# ── 已触发事件（用于一次性触发器判定 & 存档） ──
var _triggered_events: Dictionary = {}

# ── 触发链深度限制 ──
const MAX_CHAIN_DEPTH: int = 8
var _chain_depth: int = 0

# ── 同帧触发去重（防止 redirect → on_enter → redirect 循环） ──
var _firing_this_frame: Dictionary = {}  # "dir::key" -> true
var _frame_counter: int = 0

# ── 空闲检测 ──
var _idle_timer: float = 0.0
var _idle_fired: Dictionary = {}  # "path::on_idle:N" -> true

# ── 延迟动作队列 ──
var _delayed_queue: Array[Dictionary] = []

# ── meta 缓存（避免每帧重复解析） ──
var _meta_cache: Dictionary = {}   # dir_path -> { triggers: {}, ts: int }
const META_CACHE_TTL_MS: int = 5000

# ── manifest 触发器映射（目录 -> 触发器字典） ──
var _triggers_map: Dictionary = {}  # "/path" -> { "on_enter.once": "..." , ... }

# ============================================================
# 初始化
# ============================================================
func setup(p_main: Control, p_fs: FileSystem, p_theme: Variant) -> void:
	main = p_main
	fs = p_fs
	T = p_theme

func set_mail_system(p_mail: Variant) -> void:
	mail_system = p_mail

# ============================================================
# 存档
# ============================================================
func get_save_data() -> Dictionary:
	return _triggered_events.duplicate()

func load_save_data(data: Dictionary) -> void:
	_triggered_events = data.duplicate()

# ============================================================
# 每帧驱动（由 main._process 调用）
# ============================================================
func process(delta: float) -> void:
	_idle_timer += delta
	# 每帧清空同帧去重表
	_frame_counter += 1
	_firing_this_frame.clear()
	_check_idle_triggers()
	_tick_delayed_queue(delta)

## 任何用户交互后调用
func reset_idle() -> void:
	_idle_timer = 0.0
	_idle_fired.clear()

## 切换磁盘/故事后清空缓存
func clear_cache() -> void:
	_meta_cache.clear()
	_idle_fired.clear()
	_delayed_queue.clear()

## 完全重置（清除缓存 + 已触发记录 + 延迟队列）
func reset() -> void:
	clear_cache()
	_triggered_events.clear()
	_idle_timer = 0.0


# ============================================================
# ── 事件入口 ──
# ============================================================

## 进入目录
func on_enter_directory(dir_path: String) -> void:
	var triggers: Dictionary = _get_triggers(dir_path)
	if triggers.is_empty():
		return
	# on_enter（默认可重复，每次进入都触发）
	_try_fire(triggers, "on_enter", dir_path, true)
	# on_first_enter（仅首次，永远一次性）
	_try_fire(triggers, "on_first_enter", dir_path, false)


## 打开文件
func on_open_file(file_path: String) -> void:
	var dir_path: String = _parent(file_path)
	var filename: String = file_path.get_file()
	var triggers: Dictionary = _get_triggers(dir_path)
	if triggers.is_empty():
		return
	_try_fire(triggers, "on_open_file:" + filename, dir_path, false)

## 文件阅读完成（viewer 关闭后调用）
func on_read_complete(file_path: String) -> void:
	_scan_all_for_key_prefix("on_read_complete:", file_path)

## 权限等级变化
func on_level_change(new_level: int) -> void:
	var all: Dictionary = _collect_all_triggers()
	for dir_path in all:
		var triggers: Dictionary = all[dir_path]
		for key in triggers:
			var ks: String = str(key)
			if ks.begins_with("on_level_reach:"):
				var required: int = _after_colon(ks).to_int()
				if new_level >= required:
					_try_fire(triggers, ks, dir_path, false)

## 执行命令（命令名，不含参数）
func on_command(command: String) -> void:
	var dir_path: String = main.current_path
	var triggers: Dictionary = _get_triggers(dir_path)
	if triggers.is_empty():
		return
	# on_command 默认可重复
	_try_fire(triggers, "on_command:" + command, dir_path, true)

# ============================================================
# ── 核心：尝试触发 ──
# ============================================================
## repeatable_default: 该条件类型默认是否可重复
func _try_fire(triggers: Dictionary, key: String, dir_path: String, repeatable_default: bool) -> void:
	var action_str: String = ""
	var is_repeat: bool = repeatable_default
	
	# ★ 优先匹配带修饰符的版本（明确意图优先）
	if triggers.has(key + ".once"):
		action_str = str(triggers[key + ".once"])
		is_repeat = false
	elif triggers.has(key + ".repeat"):
		action_str = str(triggers[key + ".repeat"])
		is_repeat = true
	elif triggers.has(key):
		action_str = str(triggers[key])
		# is_repeat 保持 repeatable_default
	else:
		return
	
	if action_str.is_empty():
		return
	
	var trigger_id: String = dir_path + "::" + key
	
	# ★ 同帧去重：防止 redirect → on_enter → redirect 无限循环
	var frame_key: String = trigger_id
	if _firing_this_frame.has(frame_key):
		return
	_firing_this_frame[frame_key] = true
	
	if not is_repeat and _triggered_events.has(trigger_id):
		return
	
	if not is_repeat:
		_triggered_events[trigger_id] = true
	
	_execute(action_str, {"path": dir_path, "trigger": key})


# ============================================================
# ── 空闲触发 ──
# ============================================================
func _check_idle_triggers() -> void:
	var dir_path: String = main.current_path
	var triggers: Dictionary = _get_triggers(dir_path)
	for key in triggers:
		var ks: String = str(key)
		if not ks.begins_with("on_idle:"):
			continue
		var seconds: int = _after_colon(ks).to_int()
		if seconds <= 0:
			continue
		if _idle_timer < float(seconds):
			continue
		var idle_id: String = dir_path + "::" + ks
		if _idle_fired.has(idle_id):
			continue
		_idle_fired[idle_id] = true
		_execute(str(triggers[key]), {"path": dir_path, "trigger": ks})

# ============================================================
# ── 延迟队列 ──
# ============================================================
func _tick_delayed_queue(delta: float) -> void:
	var next: Array[Dictionary] = []
	for item in _delayed_queue:
		item["t"] = item["t"] - delta
		if item["t"] <= 0:
			_exec_single(str(item["a"]), item.get("ctx", {}) as Dictionary)
		else:
			next.append(item)
	_delayed_queue = next

# ============================================================
# ── 执行触发字符串（分号分隔多动作） ──
# ============================================================
func _execute(trigger_str: String, ctx: Dictionary) -> void:
	_chain_depth += 1
	if _chain_depth > MAX_CHAIN_DEPTH:
		push_warning("[TriggerSystem] 触发链深度超限: " + str(ctx))
		_chain_depth -= 1
		return

	for part in trigger_str.split(";"):
		var s: String = part.strip_edges()
		if s.is_empty():
			continue
		# delay:N:action 语法
		if s.begins_with("delay:"):
			var rest: String = s.substr(6)
			var c2: int = rest.find(":")
			if c2 > 0:
				var ms: int = rest.substr(0, c2).strip_edges().to_int()
				var act: String = rest.substr(c2 + 1).strip_edges()
				_delayed_queue.append({"t": float(ms) / 1000.0, "a": act, "ctx": ctx})
				continue
		_exec_single(s, ctx)

	_chain_depth -= 1

# ============================================================
# ── 执行单个动作 ──
# ============================================================
func _exec_single(raw: String, ctx: Dictionary) -> void:
	var c: int = raw.find(":")
	var name: String = raw.strip_edges().to_lower() if c <= 0 else raw.substr(0, c).strip_edges().to_lower()
	var param: String = "" if c <= 0 else raw.substr(c + 1).strip_edges()

	match name:
		"new_mail":     _act_new_mail(param, ctx)
		"level_up":     _act_level_up(param)
		"sound":        _act_sound(param)
		"text":         _act_text(param)
		"redirect":     _act_redirect(param)
		"glitch":       _act_glitch(param)
		"shake":        _act_shake(param)
		"tear":         _act_tear(param)
		"noise_burst":  _act_noise_burst(param)
		"play_effect": _act_play_effect(param)
		"preset_effect": _act_preset_effect(param)
		"screen_off":   _act_screen_off(param)
		"reboot":       _act_reboot()
		"lock_folder":  _act_lock_folder(param)
		"unlock_folder": _act_unlock_folder(param)
		"color_scheme": _act_color_scheme(param)
		_:
			push_warning("[TriggerSystem] 未知动作: " + raw)

# ── 动作实现 ──
func _act_new_mail(mail_id: String, ctx: Dictionary) -> void:
	if mail_system == null:
		push_warning("[TriggerSystem] 邮件系统未初始化，无法投递: " + mail_id)
		return
	# 支持 new_mail:id:persistent 语法
	var persistent: bool = false
	var actual_id: String = mail_id
	if mail_id.ends_with(":persistent"):
		actual_id = mail_id.substr(0, mail_id.length() - ":persistent".length())
		persistent = true
	mail_system.deliver_mail(actual_id, str(ctx.get("path", "")), persistent)



func _act_level_up(param: String) -> void:
	var level: int = param.to_int()
	if level <= 0 or fs.player_clearance >= level:
		return
	var old: int = fs.player_clearance
	fs.player_clearance = level
	var w: String = T.warning_hex if T else "#FFFF80"
	main.append_output("\n[color=" + w + "][SYSTEM] Security clearance upgraded: " + str(old) + " -> " + str(level) + "[/color]\n", false)
	main._update_status_bar()
	# ★ 等级变化可能触发更多事件 — 通过 _execute 间接调用，链深度自动受保护
	on_level_change(level)


func _act_sound(path: String) -> void:
	if main.audio_manager == null or path.is_empty():
		return
	# 规范化到虚拟FS路径（允许传相对路径）
	var norm_fs_path: String = fs.normalize_path("/" + path.lstrip("/"))
	var stream: AudioStream = null
	# 方式1：从虚拟文件系统读取二进制并解析
	var data: PackedByteArray = fs.get_binary_data(norm_fs_path)
	if not data.is_empty():
		stream = main.audio_manager.load_audio_from_bytes(norm_fs_path, data)
	# 方式2：从工程资源加载（备用）
	if stream == null and ResourceLoader.exists("res://" + path):
		stream = load("res://" + path) as AudioStream
	if stream != null and main.audio_manager.has_method("play_sfx"):
		main.audio_manager.play_sfx(stream)
	else:
		push_warning("[TriggerSystem] 无法加载音效: " + path)


func _act_text(msg: String) -> void:
	var text: String = _replace_vars(msg)
	var p: String = T.primary_hex if T else "#A0FFA0"
	main.append_output("\n[color=" + p + "]" + text + "[/color]\n", false)


func _act_redirect(target: String) -> void:
	var norm: String = fs.normalize_path(target)
	var node = fs.get_node_at_path(norm)
	if node == null or node.type != "folder":
		return
	main.current_path = norm
	main._update_status_bar()
	var m: String = T.muted_hex if T else "#888888"
	main.append_output("[color=" + m + "][SYSTEM] Auto-redirect: " + norm + "[/color]\n", false)
	if main.has_method("update_ambient_sound"):
		main.update_ambient_sound()
	# ★ 记录已访问目录
	if "visited_paths" in main and not main.visited_paths.has(norm):
		main.visited_paths.append(norm)
	# ★ redirect 触发目标目录的 on_enter — 链深度由 _execute 内部保护
	on_enter_directory(norm)


func _act_glitch(param: String) -> void:
	# 格式: glitch:强度 或 glitch:强度:持续时间ms 或 glitch:预设名
	var presets: Array[String] = ["subtle", "moderate", "heavy", "chaos"]
	var stripped: String = param.strip_edges().to_lower()
	if stripped in presets:
		var preset_intensity: float = 0.5
		match stripped:
			"subtle": preset_intensity = 0.2
			"moderate": preset_intensity = 0.5
			"heavy": preset_intensity = 0.8
			"chaos": preset_intensity = 1.0
		print("[TriggerSystem] _act_glitch preset=", stripped, " intensity=", preset_intensity)
		if main.has_method("trigger_glitch"):
			main.trigger_glitch(preset_intensity, 1.0, stripped)
		return
	# 数值模式
	var parts: PackedStringArray = param.split(":")
	var intensity: float = 0.8
	var duration_ms: int = 1000
	if parts.size() >= 1 and not parts[0].strip_edges().is_empty():
		intensity = clampf(parts[0].strip_edges().to_float(), 0.1, 2.0)
	if parts.size() >= 2:
		duration_ms = parts[1].strip_edges().to_int()
	print("[TriggerSystem] _act_glitch numeric intensity=", intensity, " duration_ms=", duration_ms)
	if main.has_method("trigger_glitch"):
		main.trigger_glitch(intensity, float(duration_ms) / 1000.0)


func _act_shake(param: String) -> void:
	var parts: PackedStringArray = param.split(":")
	var intensity: float = 0.01
	var duration_ms: int = 500
	if parts.size() >= 1 and not parts[0].strip_edges().is_empty():
		intensity = clampf(parts[0].strip_edges().to_float(), 0.001, 0.1)
	if parts.size() >= 2:
		duration_ms = parts[1].strip_edges().to_int()
	print("[TriggerSystem] _act_shake intensity=", intensity, " duration_ms=", duration_ms)
	if main.has_method("trigger_shake"):
		main.trigger_shake(intensity, float(duration_ms) / 1000.0)

func _act_tear(param: String) -> void:
	var parts: PackedStringArray = param.split(":")
	var strength: float = 0.08
	var duration_ms: int = 500
	if parts.size() >= 1 and not parts[0].strip_edges().is_empty():
		strength = clampf(parts[0].strip_edges().to_float(), 0.01, 0.15)
	if parts.size() >= 2:
		duration_ms = parts[1].strip_edges().to_int()
	print("[TriggerSystem] _act_tear strength=", strength, " duration_ms=", duration_ms)
	if main.has_method("trigger_tear"):
		main.trigger_tear(strength, float(duration_ms) / 1000.0)

func _act_noise_burst(param: String) -> void:
	var parts: PackedStringArray = param.split(":")
	var intensity: float = 0.8
	var duration_ms: int = 300
	if parts.size() >= 1 and not parts[0].strip_edges().is_empty():
		intensity = clampf(parts[0].strip_edges().to_float(), 0.1, 1.0)
	if parts.size() >= 2:
		duration_ms = parts[1].strip_edges().to_int()
	print("[TriggerSystem] _act_noise_burst intensity=", intensity, " duration_ms=", duration_ms)
	if main.has_method("trigger_noise_burst"):
		main.trigger_noise_burst(intensity, float(duration_ms) / 1000.0)

func _act_play_effect(param: String) -> void:
	var effect_id: String = param.strip_edges()
	if effect_id.is_empty():
		push_warning("[TriggerSystem] play_effect 缺少 effect_id")
		return
	print("[TriggerSystem] _act_play_effect: ", effect_id)
	if main.has_method("trigger_effect"):
		main.trigger_effect(effect_id)

func _act_preset_effect(param: String) -> void:
	var parts: PackedStringArray = param.split(":")
	var preset_name: String = parts[0].strip_edges() if parts.size() >= 1 else ""
	var duration_ms: int = 2000
	if parts.size() >= 2:
		duration_ms = parts[1].strip_edges().to_int()
	if preset_name.is_empty():
		push_warning("[TriggerSystem] preset_effect 缺少预设名称")
		return
	print("[TriggerSystem] _act_preset_effect: ", preset_name, " duration_ms=", duration_ms)
	if main.has_method("trigger_preset_effect"):
		main.trigger_preset_effect(preset_name, float(duration_ms) / 1000.0)



func _act_screen_off(param: String) -> void:
	var ms: int = param.to_int() if not param.is_empty() else 2000
	if main.has_method("trigger_screen_off"):
		main.trigger_screen_off(float(ms) / 1000.0)

func _act_reboot() -> void:
	if main.has_method("trigger_reboot"):
		main.trigger_reboot()

func _act_lock_folder(path: String) -> void:
	var norm: String = fs.normalize_path(path)
	if fs.has_method("set_required_clearance"):
		fs.set_required_clearance(norm, 99)
	var e: String = T.error_hex if T else "#FF6666"
	main.append_output("[color=" + e + "][SYSTEM] 目录已锁定: " + norm + "[/color]\n", false)

func _act_unlock_folder(path: String) -> void:
	var norm: String = fs.normalize_path(path)
	if fs.has_method("set_required_clearance"):
		fs.set_required_clearance(norm, 0)
	var p: String = T.primary_hex if T else "#A0FFA0"
	main.append_output("[color=" + p + "][SYSTEM] 目录已解锁: " + norm + "[/color]\n", false)


func _act_color_scheme(param: String) -> void:
	var theme_name: String = param.strip_edges().to_lower()
	if theme_name.is_empty():
		return
	# 可选后缀 :force（当前仅去掉标记，不做额外确认）
	if theme_name.ends_with(":force"):
		theme_name = theme_name.substr(0, theme_name.length() - 6)
	# 与 command_handler.gd 保持一致：直接调用 ThemeManager 的静态方法
	ThemeManager.request_theme_change(theme_name, main)

# ============================================================
# ── .meta.cfg 解析与缓存 ──
# ============================================================
func _get_triggers(dir_path: String) -> Dictionary:
	dir_path = fs.normalize_path(dir_path)
	if _triggers_map.has(dir_path):
		return _triggers_map[dir_path] as Dictionary
	return {}


func _parse_triggers_section(content: String) -> Dictionary:
	var result: Dictionary = {}
	var in_section: bool = false
	for line in content.split("\n"):
		var s: String = line.strip_edges()
		if s.is_empty() or s.begins_with("#"):
			continue
		if s.begins_with("[") and s.ends_with("]"):
			in_section = s.substr(1, s.length() - 2).strip_edges().to_lower() == "triggers"
			continue
		if not in_section:
			continue
		var eq: int = s.find("=")
		if eq <= 0:
			continue
		var key: String = s.substr(0, eq).strip_edges()
		var val: String = s.substr(eq + 1).strip_edges()
		# 去引号
		if val.length() >= 2:
			if (val.begins_with("\"") and val.ends_with("\"")) or (val.begins_with("'") and val.ends_with("'")):
				val = val.substr(1, val.length() - 2)
		result[key] = val
	return result

# ============================================================
# ── 辅助 ──
# ============================================================

## 对所有目录的触发器进行前缀扫描（on_read_complete:xxx 等）
func _scan_all_for_key_prefix(prefix: String, match_path: String) -> void:
	var all: Dictionary = _collect_all_triggers()
	for dir_path in all:
		var triggers: Dictionary = all[dir_path]
		for key in triggers:
			var ks: String = str(key)
			if not ks.begins_with(prefix):
				continue
			var target: String = _after_colon_full(ks, prefix.length())
			if match_path.ends_with(target) or match_path == target:
				_try_fire(triggers, ks, dir_path, false)

## 收集所有目录的触发器
func _collect_all_triggers() -> Dictionary:
	# 直接返回 manifest 中的触发器映射
	return _triggers_map

func _scan_dir_recursive(path: String, out: Dictionary) -> void:
	var triggers: Dictionary = _get_triggers(path)
	if not triggers.is_empty():
		out[path] = triggers
	# 使用 FileSystem 的枚举接口遍历子目录
	var names: Array[String] = fs.get_children_at_path(path)
	for child_name in names:
		var child_path: String = fs.join_path(path, child_name)
		var child_node = fs.get_node_at_path(child_path)
		if child_node != null and child_node.type == "folder":
			_scan_dir_recursive(child_path, out)


func _parent(path: String) -> String:
	return fs.get_parent_path(path)

func _after_colon(s: String) -> String:
	var pos: int = s.find(":")
	return s.substr(pos + 1) if pos >= 0 else s

func _after_colon_full(s: String, start: int) -> String:
	return s.substr(start)

func _replace_vars(text: String) -> String:
	if main.user_mgr != null and main.user_mgr.is_logged_in:
		text = text.replace("{username}", main.user_mgr.get_username())
	text = text.replace("{level}", str(fs.player_clearance))
	text = text.replace("{path}", main.current_path)
	return text


## disc_manager 加载故事包时调用（触发器从文件系统按需读取，这里只清缓存）
## 注意：不清空 _triggered_events，它由存档系统通过 load_save_data 管理
func load_from_manifest(manifest: Dictionary) -> void:
	clear_cache()
	_triggers_map.clear()
	# 从 manifest["triggers"] 载入（彻底停用 .meta.cfg）
	if manifest.has("triggers") and manifest["triggers"] is Dictionary:
		var raw: Dictionary = manifest["triggers"]
		for k in raw.keys():
			var dir_path: String = fs.normalize_path(str(k))
			var tdict_raw = raw[k]
			if tdict_raw is Dictionary:
				var tdict: Dictionary = {}
				for key2 in (tdict_raw as Dictionary).keys():
					# 统一转成字符串（动作字符串）
					tdict[str(key2)] = str(tdict_raw[key2])
				_triggers_map[dir_path] = tdict
