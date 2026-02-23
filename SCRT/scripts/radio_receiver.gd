# ============================================================
# radio_receiver.gd - 无线电接收器主控
# 参考 oscilloscope.gd 架构：RefCounted + overlay + 自定义绘制
# ============================================================
class_name RadioReceiver
extends RefCounted

# ══════════════════════════════════════════
#  模块引用
# ══════════════════════════════════════════
var main = null
var audio_manager = null
var T = null

# 子模块
var signal_mgr: RadioSignalManager = null
var morse_engine: MorseEngine = null
var sstv_decoder: SSTVDecoder = null
var audio_gen: RadioAudioGenerator = null

# ══════════════════════════════════════════
#  模式
# ══════════════════════════════════════════
enum RadioMode { MORSE, SSTV, WATERFALL }
var current_mode: RadioMode = RadioMode.MORSE

# ══════════════════════════════════════════
#  调谐状态
# ══════════════════════════════════════════
var current_band: String = "HF"
var current_frequency: float = 14.000    # MHz
var current_azimuth: float = 0.0         # 0-359°（连续值）
var current_elevation: float = 15.0      # 0-90°（连续值）
var current_volume: float = 0.4          # 0.0-1.0（初始音量降低）

# 信号状态
var current_signal_quality: float = 0.0
var current_signal = null                # RadioConfigParser.RadioSignal or null

# 显示锁定：按频率距离锁定最近的信号源（不依赖实时质量，彻底防闪烁）
var _nearest_signal = null               # 当前频率最近的同波段信号源
var _signal_lock_timer: float = 0.0      # 信号锁定计时
const SIGNAL_LOCK_THRESHOLD: float = 0.5
const SIGNAL_LOCK_TIME: float = 3.0      # 锁定需持续秒数

# 自动扫描
var _auto_scan_active: bool = false
var _auto_scan_timer: float = 0.0
const AUTO_SCAN_STEP_INTERVAL: float = 0.05

# ══════════════════════════════════════════
#  SSTV 状态
# ══════════════════════════════════════════
var _sstv_receiving: bool = false
var _sstv_detected: bool = false
var _sstv_waiting_start: bool = false
var _sstv_previewing: bool = false
var _sstv_target_id: String = ""   # 正在接收的目标信号 id，用于偏离判断

# ══════════════════════════════════════════
#  UI 节点
# ══════════════════════════════════════════
var is_active: bool = false
var overlay: Panel = null
var radio_canvas: Control = null
var nav_label: RichTextLabel = null

# 缓存
var _cached_input_visible: bool = true
var _cached_prompt_visible: bool = true
var _cached_output_text: String = ""

# 音频播放器（挂在 AudioManager 下）
var _noise_player: AudioStreamPlayer = null
var _tone_player: AudioStreamPlayer = null
var _sstv_player: AudioStreamPlayer = null

# ══════════════════════════════════════════
#  绘制参数
# ══════════════════════════════════════════
var draw_color: Color = Color(0.2, 1.0, 0.3, 1.0)
var draw_color_dim: Color = Color(0.1, 0.5, 0.15, 0.6)
var grid_color: Color = Color(0.1, 0.3, 0.1, 0.3)
var error_color: Color = Color(1.0, 0.3, 0.2, 1.0)
var warning_color: Color = Color(1.0, 0.7, 0.0, 1.0)
var bg_color: Color = Color(0.0, 0.02, 0.0, 0.95)

# UI 布局常量
const LEFT_PANEL_RATIO: float = 0.42
const MARGIN: float = 12.0
const LINE_HEIGHT: float = 16.0
const SECTION_GAP: float = 8.0

# 信号强度条动画
var _display_quality: float = 0.0
const QUALITY_SMOOTH: float = 8.0

# 鼠标拖拽调频
var _freq_ruler_rect: Rect2 = Rect2()    # 频率刻度条的屏幕区域
var _dragging_freq: bool = false

# 导航更新
var _nav_timer: float = 0.0

# ★ 信标日志显示开关
var _show_beacon_log: bool = false

# 瀑布图数据
var _waterfall_image: Image = null
var _waterfall_texture: ImageTexture = null
var _waterfall_width: int = 256        # 频谱分辨率（像素列数）
var _waterfall_height: int = 128       # 历史行数
var _waterfall_spectrum: PackedFloat32Array = PackedFloat32Array()  # 当前帧频谱
var _waterfall_update_timer: float = 0.0
const WATERFALL_UPDATE_INTERVAL: float = 0.05  # 50ms 更新一次

# HUD/标签可见性（仅影响 WATERFALL 模式右侧面板）
const WF_HIDE_BOTTOM_HUD := true
const WF_HIDE_LABELS := true

# 瀑布频谱采样范围（音频域，单位 Hz）
var _wf_min_freq: float = 100.0
var _wf_max_freq: float = 4000.0

# 瀑布行指针（滚动用）
var _waterfall_row: int = 0

# ══════════════════════════════════════════
#  方向常量
# ══════════════════════════════════════════
const DIR_ARROWS: Dictionary = {
	0: "↑", 45: "↗", 90: "→", 135: "↘",
	180: "↓", 225: "↙", 270: "←", 315: "↖"
}
const DIR_NAMES: Dictionary = {
	0: "N", 45: "NE", 90: "E", 135: "SE",
	180: "S", 225: "SW", 270: "W", 315: "NW"
}

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(p_main, p_audio_manager) -> void:
	main = p_main
	audio_manager = p_audio_manager
	T = ThemeManager.current
	signal_mgr = RadioSignalManager.new()
	morse_engine = MorseEngine.new()
	sstv_decoder = SSTVDecoder.new()
	audio_gen = RadioAudioGenerator.new()
	_update_colors()

func _update_colors() -> void:
	if T == null:
		return
	draw_color = T.primary
	draw_color.a = 1.0
	draw_color_dim = T.primary
	draw_color_dim.a = 0.4
	grid_color = T.primary
	grid_color.a = 0.15
	if T.get("error") != null:
		error_color = T.error
	if T.get("warning") != null:
		warning_color = T.warning
	bg_color = T.bg
	bg_color.a = 0.95

func has_signals() -> bool:
	return signal_mgr.has_signals()

## ★ 新增：从 manifest 加载信号源
func load_signals_from_manifest(manifest: Dictionary, fs) -> void:
	signal_mgr.load_signals_from_manifest(manifest, fs)

func load_signals_from_fs(fs) -> void:
	signal_mgr.load_signals(fs)

# ══════════════════════════════════════════
#  UI 构建
# ══════════════════════════════════════════
func _ensure_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		return
	overlay = Panel.new()
	overlay.name = "RadioReceiverOverlay"
	overlay.visible = false
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0)
	overlay.add_theme_stylebox_override("panel", bg_style)

	var root_control: Control = main as Control
	root_control.add_child(overlay)
	var crt_node: Node = root_control.get_node_or_null("CRTEffect")
	if crt_node:
		root_control.move_child(overlay, crt_node.get_index())

	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.offset_left = 0
	overlay.offset_top = 0
	overlay.offset_right = 0
	overlay.offset_bottom = 0

	# Margin
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	overlay.add_child(margin)

	# VBox
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	# 绘制画布
	radio_canvas = _RadioCanvas.new()
	radio_canvas.name = "RadioCanvas"
	radio_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	radio_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(radio_canvas as _RadioCanvas).radio = self
	vbox.add_child(radio_canvas)

	# 底部导航
	nav_label = RichTextLabel.new()
	nav_label.bbcode_enabled = true
	nav_label.fit_content = true
	nav_label.scroll_active = false
	nav_label.selection_enabled = false
	nav_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(nav_label)

func _align_overlay() -> void:
	if overlay == null:
		return
	var output_area: ScrollContainer = main.scroll_container
	var rect: Rect2 = output_area.get_global_rect()
	overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	overlay.position = rect.position
	overlay.size = rect.size

func _ensure_audio_players() -> void:
	if _noise_player == null:
		_noise_player = AudioStreamPlayer.new()
		_noise_player.name = "RadioNoisePlayer"
		_noise_player.bus = "Master"
		_noise_player.volume_db = -80.0
		audio_manager.add_child(_noise_player)
		var noise_stream: AudioStreamWAV = audio_gen.generate_noise_stream(2.0)
		_noise_player.stream = noise_stream

	if _tone_player == null:
		_tone_player = AudioStreamPlayer.new()
		_tone_player.name = "RadioTonePlayer"
		_tone_player.bus = "Master"
		_tone_player.volume_db = -80.0
		audio_manager.add_child(_tone_player)
		var tone_stream: AudioStreamWAV = audio_gen.generate_tone_stream(700.0, 1.0)
		_tone_player.stream = tone_stream

	if _sstv_player == null:
		_sstv_player = AudioStreamPlayer.new()
		_sstv_player.name = "RadioSSTVPlayer"
		_sstv_player.bus = "Master"
		_sstv_player.volume_db = -80.0
		audio_manager.add_child(_sstv_player)

# ══════════════════════════════════════════
#  打开 / 关闭
# ══════════════════════════════════════════
func open() -> void:
	_ensure_overlay()
	_ensure_audio_players()
	T = ThemeManager.current
	_update_colors()
	_align_overlay()

	is_active = true
	current_mode = RadioMode.MORSE

	# 加载信号（如果尚未加载）
	if not signal_mgr.has_signals() and main.fs != null:
		signal_mgr.load_signals(main.fs)

	# 缓存终端
	_cached_input_visible = main.input_field.visible
	_cached_prompt_visible = main.prompt_label.visible
	main.input_field.visible = false
	main.prompt_label.visible = false
	_cached_output_text = main.output_text.text
	main.output_text.text = ""
	main.path_label.text = "RADIO RECEIVER | Q/Esc 退出"

	_init_waterfall()

	overlay.visible = true
	radio_canvas.set_process(true)

	# 启动噪音与基准音
	_noise_player.play()
	_tone_player.play()

	_update_nav()
	# 初始查找最近信号
	_update_nearest_signal()

func close() -> void:
	if not is_active:
		return
	is_active = false

	# 停止音频
	if _noise_player and _noise_player.playing:
		_noise_player.stop()
	if _tone_player and _tone_player.playing:
		_tone_player.stop()
	if _sstv_player and _sstv_player.playing:
		_sstv_player.stop()
	_sstv_previewing = false

	# 停止摩斯引擎
	morse_engine.stop()

	# 停止 SSTV
	if sstv_decoder.is_receiving:
		sstv_decoder.interrupt()
	_sstv_receiving = false
	_sstv_detected = false
	_sstv_waiting_start = false

	_auto_scan_active = false

	if overlay and is_instance_valid(overlay):
		overlay.visible = false
	if radio_canvas:
		radio_canvas.set_process(false)

	# 恢复终端
	main.output_text.clear()
	main.output_text.append_text(_cached_output_text)
	_cached_output_text = ""
	main.input_field.visible = _cached_input_visible
	main.prompt_label.visible = _cached_prompt_visible
	main._update_status_bar()
	main.input_field.grab_focus()
	if main.has_method("_on_radio_closed"):
		main._on_radio_closed()

# ══════════════════════════════════════════
#  瀑布图初始化与更新
# ══════════════════════════════════════════
func _init_waterfall() -> void:
	_waterfall_width = 512
	_waterfall_height = 256
	_waterfall_image = Image.create(_waterfall_width, _waterfall_height, false, Image.FORMAT_RGB8)
	_waterfall_image.fill(Color.BLACK)
	_waterfall_texture = ImageTexture.create_from_image(_waterfall_image)
	_waterfall_spectrum.resize(_waterfall_width)
	_waterfall_spectrum.fill(0.0)
	_waterfall_row = 0


func _update_waterfall(delta: float) -> void:
	_waterfall_update_timer += delta
	if _waterfall_update_timer < WATERFALL_UPDATE_INTERVAL:
		return
	_waterfall_update_timer = 0.0
	if _waterfall_image == null:
		return

	# 显式类型，避免类型推断失败
	var analyzer: AudioEffectSpectrumAnalyzerInstance = audio_manager.get_spectrum_analyzer_instance()  # [1]
	if analyzer == null:
		return

	var min_f: float = maxf(_wf_min_freq, 20.0)
	var max_f: float = maxf(_wf_max_freq, min_f + 10.0)
	var bars: int = _waterfall_width

	# 对数分桶采样
	for i in range(bars):
		var t0: float = float(i) / float(bars)
		var t1: float = float(i + 1) / float(bars)
		var f0: float = min_f * pow(max_f / min_f, t0)
		var f1: float = min_f * pow(max_f / min_f, t1)
		var mag: Vector2 = analyzer.get_magnitude_for_frequency_range(
			f0, f1, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE
		)
		var m: float = (mag.x + mag.y) * 0.5
		var e: float = clampf((linear_to_db(maxf(m, 0.00001)) + 80.0) / 80.0, 0.0, 1.0)
		_waterfall_spectrum[i] = e

	# 下滚 1 行（Godot 4 的 Image 无需 lock/unlock）
	_waterfall_image.blit_rect(
		_waterfall_image,
		Rect2i(0, 0, _waterfall_width, _waterfall_height - 1),
		Vector2i(0, 1)
	)
	for x in range(_waterfall_width):
		_waterfall_image.set_pixel(x, 0, _spectrum_to_color(_waterfall_spectrum[x]))

	# 刷新纹理
	_waterfall_texture.update(_waterfall_image)


func _spectrum_to_color(value: float) -> Color:
	# 冷-热色彩映射：黑 → 深蓝 → 青 → 绿 → 黄 → 红 → 白
	if value < 0.1:
		return Color(0.0, 0.0, value * 3.0)
	elif value < 0.25:
		var t: float = (value - 0.1) / 0.15
		return Color(0.0, t * 0.5, 0.3 + t * 0.4)
	elif value < 0.45:
		var t2: float = (value - 0.25) / 0.2
		return Color(0.0, 0.5 + t2 * 0.5, 0.7 * (1.0 - t2))
	elif value < 0.65:
		var t3: float = (value - 0.45) / 0.2
		return Color(t3, 1.0, 0.0)
	elif value < 0.85:
		var t4: float = (value - 0.65) / 0.2
		return Color(1.0, 1.0 - t4, 0.0)
	else:
		var t5: float = clampf((value - 0.85) / 0.15, 0.0, 1.0)
		return Color(1.0, t5, t5)

# ══════════════════════════════════════════
#  输入处理
# ══════════════════════════════════════════
func handle_input(event: InputEvent) -> bool:
	if not is_active:
		return false

	# 鼠标事件处理
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var local_pos: Vector2 = event.position - overlay.global_position
				if _freq_ruler_rect.has_point(local_pos):
					_dragging_freq = true
					_set_freq_from_mouse(local_pos.x)
					return true
			else:
				if _dragging_freq:
					_dragging_freq = false
					return true
		return false

	if event is InputEventMouseMotion:
		if _dragging_freq:
			var local_pos2: Vector2 = event.position - overlay.global_position
			_set_freq_from_mouse(local_pos2.x)
			return true
		return false

	if not (event is InputEventKey and event.pressed):
		return false

	var shift: bool = event.shift_pressed
	match event.keycode:
		KEY_Q, KEY_ESCAPE:
			close()
			return true
		KEY_TAB:
			# 记住切换前的模式，用于退出 SSTV 时清理预听
			var prev_mode: RadioMode = current_mode
			match current_mode:
				RadioMode.MORSE:
					current_mode = RadioMode.SSTV
				RadioMode.SSTV:
					current_mode = RadioMode.WATERFALL
				RadioMode.WATERFALL:
					current_mode = RadioMode.MORSE

			# 若从 SSTV 切出，立即停止预听音（接收不中断，因接收推进已与模式解耦）
			if prev_mode == RadioMode.SSTV and current_mode != RadioMode.SSTV:
				if _sstv_previewing and _sstv_player and _sstv_player.playing:
					_sstv_player.stop()
				_sstv_previewing = false
			_update_nav()
			return true
		KEY_LEFT:
			var step: float = _get_freq_step()
			if shift:
				step *= 10.0
			current_frequency = maxf(current_frequency - step, _get_band_min())
			_on_tuning_changed()
			return true
		KEY_RIGHT:
			var step2: float = _get_freq_step()
			if shift:
				step2 *= 10.0
			current_frequency = minf(current_frequency + step2, _get_band_max())
			_on_tuning_changed()
			return true
		KEY_UP:
			var az_step: float = 30.0 if shift else 3.0
			current_azimuth = fmod(current_azimuth + az_step, 360.0)
			_on_tuning_changed()
			return true
		KEY_DOWN:
			var az_step2: float = 30.0 if shift else 3.0
			current_azimuth = fmod(current_azimuth - az_step2 + 360.0, 360.0)
			_on_tuning_changed()
			return true
		KEY_COMMA:  # < 键（仰角减）
			var el_step: float = 10.0 if shift else 2.0
			current_elevation = maxf(current_elevation - el_step, 0.0)
			_on_tuning_changed()
			return true
		KEY_PERIOD:  # > 键（仰角加）
			var el_step2: float = 10.0 if shift else 2.0
			current_elevation = minf(current_elevation + el_step2, 90.0)
			_on_tuning_changed()
			return true
		KEY_EQUAL:  # + 键（音量加）
			current_volume = minf(current_volume + 0.05, 1.0)
			return true
		KEY_MINUS:  # - 键（音量减）
			current_volume = maxf(current_volume - 0.05, 0.0)
			return true
		KEY_1:
			_switch_band("LF")
			return true
		KEY_2:
			_switch_band("HF")
			return true
		KEY_3:
			_switch_band("VHF")
			return true
		KEY_4:
			_switch_band("UHF")
			return true
		KEY_B:
			signal_mgr.add_bookmark(
				current_frequency, current_band,
				current_azimuth, current_elevation,
				"%.3f MHz %s" % [current_frequency, current_band]
			)
			return true
		KEY_S:
			_auto_scan_active = not _auto_scan_active
			_auto_scan_timer = 0.0
			return true
		KEY_SPACE:
			if current_mode == RadioMode.SSTV and _sstv_detected and not _sstv_receiving:
				_start_sstv_receive()
			return true
		KEY_R:
			if current_mode == RadioMode.MORSE:
				morse_engine.reset()
			elif current_mode == RadioMode.SSTV:
				if sstv_decoder.is_receiving:
					sstv_decoder.interrupt()
				_sstv_receiving = false
				_sstv_detected = false
				if _sstv_player and _sstv_player.playing:
					_sstv_player.stop()
				_sstv_previewing = false
			return true
		KEY_P:
			if current_mode == RadioMode.SSTV and sstv_decoder.is_complete:
				_save_sstv_image()
			return true
		KEY_L:
			_show_beacon_log = not _show_beacon_log
			return true

	return false

func _set_freq_from_mouse(mouse_x: float) -> void:
	if _freq_ruler_rect.size.x <= 0:
		return
	var ratio: float = clampf((mouse_x - _freq_ruler_rect.position.x) / _freq_ruler_rect.size.x, 0.0, 1.0)
	var band_min: float = _get_band_min()
	var band_max: float = _get_band_max()
	current_frequency = band_min + ratio * (band_max - band_min)
	var step: float = _get_freq_step()
	current_frequency = snapped(current_frequency, step)
	current_frequency = clampf(current_frequency, band_min, band_max)
	_on_tuning_changed()

# ══════════════════════════════════════════
#  波段切换
# ══════════════════════════════════════════
func _switch_band(band: String) -> void:
	if not RadioConfigParser.BAND_RANGES.has(band):
		return
	current_band = band
	var band_info: Dictionary = RadioConfigParser.BAND_RANGES[band]
	current_frequency = float(band_info["min"])
	_nearest_signal = null
	_on_tuning_changed()

func _get_freq_step() -> float:
	if RadioConfigParser.BAND_RANGES.has(current_band):
		return float(RadioConfigParser.BAND_RANGES[current_band]["step"])
	return 0.005

func _get_band_min() -> float:
	if RadioConfigParser.BAND_RANGES.has(current_band):
		return float(RadioConfigParser.BAND_RANGES[current_band]["min"])
	return 0.1

func _get_band_max() -> float:
	if RadioConfigParser.BAND_RANGES.has(current_band):
		return float(RadioConfigParser.BAND_RANGES[current_band]["max"])
	return 3000.0

# ══════════════════════════════════════════
#  查找频率最近的信号源（防闪烁核心）
# ══════════════════════════════════════════
func _update_nearest_signal() -> void:
	_nearest_signal = signal_mgr.get_nearest_signal_by_freq(current_frequency, current_band)

# ══════════════════════════════════════════
#  调谐变化回调
# ══════════════════════════════════════════
func _on_tuning_changed() -> void:
	_auto_scan_active = false
	_update_signal_lock()
	_update_nearest_signal()

	var result: Dictionary = signal_mgr.get_best_signal(
		current_frequency, current_band, current_azimuth, current_elevation
	)

	# 接收中：若偏离接收目标或质量过低，则中断并停止音频
	if _sstv_receiving:
		var sig = result["signal"]
		var off_target: bool = true
		if sig != null:
			off_target = (sig.id != _sstv_target_id)
		if off_target or result["quality"] < 0.15:
			sstv_decoder.interrupt()
			_sstv_receiving = false
			_sstv_target_id = ""
			if _sstv_player and _sstv_player.playing:
				_sstv_player.stop()

	# 预听中：若已不是 SSTV 或质量太低，停止预听音频
	if _sstv_previewing and _sstv_player and _sstv_player.playing:
		if current_signal == null or current_signal.type != "sstv" or result["quality"] < 0.01 or current_mode != RadioMode.SSTV:
			_sstv_player.stop()
			_sstv_previewing = false

	# 防止任何“非接收态且非预听态”的残留播放
	if not _sstv_receiving and not _sstv_previewing and _sstv_player and _sstv_player.playing:
		_sstv_player.stop()

	if radio_canvas:
		radio_canvas.queue_redraw()



func _update_signal_lock() -> void:
	var result: Dictionary = signal_mgr.get_best_signal(current_frequency, current_band, current_azimuth, current_elevation)
	var new_quality: float = result["quality"]
	var new_signal = result["signal"]

	if new_signal != current_signal:
		current_signal = new_signal
		_signal_lock_timer = 0.0
		morse_engine.stop()
		morse_engine.reset()

	current_signal_quality = new_quality

# ══════════════════════════════════════════
#  每帧更新
# ══════════════════════════════════════════
func process(delta: float) -> void:
	if not is_active:
		return

	signal_mgr.update(delta)

	# 重新评估信号
	var result: Dictionary = signal_mgr.get_best_signal(current_frequency, current_band, current_azimuth, current_elevation)
	current_signal_quality = result["quality"]
	var best_sig = result["signal"]
	if best_sig != current_signal:
		current_signal = best_sig
		_signal_lock_timer = 0.0
		morse_engine.stop()
		morse_engine.reset()

	# 平滑信号强度（仅用于显示）
	_display_quality = lerpf(_display_quality, current_signal_quality, QUALITY_SMOOTH * delta)

	# 信号锁定计时
	if current_signal != null and current_signal_quality >= SIGNAL_LOCK_THRESHOLD:
		_signal_lock_timer += delta
	else:
		_signal_lock_timer = maxf(_signal_lock_timer - delta * 2.0, 0.0)

	# 锁定后自动开始
	if _signal_lock_timer >= SIGNAL_LOCK_TIME and current_signal != null:
		_on_signal_locked(current_signal)

	# 自动扫描
	if _auto_scan_active:
		_auto_scan_timer += delta
		if _auto_scan_timer >= AUTO_SCAN_STEP_INTERVAL:
			_auto_scan_timer = 0.0
			_do_auto_scan_step()

	# 摩斯引擎更新
	if current_mode == RadioMode.MORSE and morse_engine.is_playing:
		var morse_result: Dictionary = morse_engine.process(delta, current_signal_quality)
		_update_tone(morse_result.get("tone_on", false))
	else:
		_update_tone(false)

	# —— SSTV：接收推进与音频管理（与模式无关）——
	if _sstv_receiving and sstv_decoder.is_receiving:
		sstv_decoder.process(delta, current_signal_quality)

	# 仅在“接收态”允许启动接收音频；否则不允许因为 is_audio_ready 而启动
	if _sstv_receiving and sstv_decoder.is_audio_ready() and _sstv_player != null:
		if not _sstv_player.playing and sstv_decoder.has_sstv_audio():
			_sstv_player.stream = sstv_decoder.get_sstv_audio_stream()
			_sstv_player.volume_db = linear_to_db(maxf(current_volume * 0.6, 0.001))
			_sstv_player.play()

		# 接收态下随质量动态调音量
		if _sstv_player.playing:
			var sstv_vol: float = current_signal_quality * current_volume * 0.6
			_sstv_player.volume_db = linear_to_db(maxf(sstv_vol, 0.001))

	# 接收完成后，标记结束并停播（is_complete 为 bool 属性）
	if sstv_decoder.is_complete:
		if _sstv_receiving:
			_sstv_receiving = false
			_sstv_target_id = ""
		if _sstv_player and _sstv_player.playing:
			_sstv_player.stop()
	# 非接收又非预听时，防止任何残留播放
	if not _sstv_receiving and not _sstv_previewing and _sstv_player and _sstv_player.playing:
		_sstv_player.stop()

	# SSTV 检测（仅用于预听触发）
	if not _sstv_receiving:
		if current_signal != null and current_signal.type == "sstv" and current_signal_quality >= 0.08:
			_sstv_detected = true
		elif current_signal == null or current_signal.type != "sstv" or current_signal_quality < 0.01:
			_sstv_detected = false

	# SSTV 预听：仅在 SSTV 模式有效；离开该模式或质量太低不维持预听
	if current_mode == RadioMode.SSTV and not _sstv_receiving and _sstv_player != null:
		if _sstv_detected:
			if not _sstv_player.playing or not _sstv_previewing:
				var header: AudioStreamWAV = audio_gen.generate_sstv_header_stream()
				header.loop_mode = AudioStreamWAV.LOOP_FORWARD
				_sstv_player.stream = header
				_sstv_player.play()
				_sstv_previewing = true
			var pv_vol: float = current_signal_quality * current_volume * 0.4
			_sstv_player.volume_db = linear_to_db(maxf(pv_vol, 0.001))
		elif _sstv_previewing and _sstv_player.playing:
			_sstv_player.stop()
			_sstv_previewing = false
	else:
		# 非 SSTV 模式，若仍在预听则停止
		if _sstv_previewing and _sstv_player and _sstv_player.playing:
			_sstv_player.stop()
			_sstv_previewing = false

	# 瀑布图更新
	_update_waterfall(delta)

	# 噪音音量
	_update_noise_volume()

	# 导航栏
	_nav_timer += delta
	if _nav_timer >= 0.5:
		_nav_timer = 0.0
		_update_nav()

	# 重绘
	if radio_canvas:
		radio_canvas.queue_redraw()



func _update_tone(tone_on: bool) -> void:
	if _tone_player == null:
		return
	var db: float = audio_gen.get_tone_volume_db(current_signal_quality, tone_on, current_volume * 0.25)
	_tone_player.volume_db = db

func _update_noise_volume() -> void:
	if _noise_player == null:
		return
	var db: float = audio_gen.get_noise_volume_db(current_signal_quality, current_volume * 0.15)
	_noise_player.volume_db = db

# ══════════════════════════════════════════
#  信号锁定与自动行为
# ══════════════════════════════════════════
func _on_signal_locked(sig: RadioConfigParser.RadioSignal) -> void:
	signal_mgr.discover_signal(sig)
	if current_mode == RadioMode.MORSE and sig.type == "morse":
		if not morse_engine.is_playing and not sig.content_text.is_empty():
			# ★ 数字电台信号使用专用加载
			if sig.character_set == "numbers":
				morse_engine.load_numbers_text(
					sig.content_text, sig.speed_wpm, sig.loop,
					sig.group_size, sig.group_pause_ms, sig.repeat_count
				)
			else:
				morse_engine.load_text(sig.content_text, sig.speed_wpm, sig.loop)
			morse_engine.start_from_random()
	elif current_mode == RadioMode.SSTV and sig.type == "sstv":
		if not _sstv_receiving and not sig.content_image.is_empty():
			_sstv_detected = true


func _start_sstv_receive() -> void:
	if current_signal == null or current_signal.type != "sstv":
		return
	if current_signal.content_image.is_empty():
		return

	# 若在预听或已有播放，先停掉避免重叠
	if _sstv_player and _sstv_player.playing:
		_sstv_player.stop()
	_sstv_previewing = false

	var ok: bool = sstv_decoder.start_receive(
		current_signal.content_image,
		current_signal.sstv_mode,
		current_signal.transmit_duration
	)
	if ok:
		_sstv_receiving = true
		_sstv_detected = false
		_sstv_target_id = current_signal.id  # 记录接收目标
	# 音频不在此处立即播放，由 process() 中检测 is_audio_ready 后播放


func _save_sstv_image() -> void:
	if not sstv_decoder.is_complete:
		return
	var png_data: PackedByteArray = sstv_decoder.get_image_as_png()
	if png_data.is_empty():
		return
	if main.fs != null and main.fs.has_method("write_file"):
		var filename: String = "sstv_%s.png" % Time.get_unix_time_from_system()
		var save_path: String = "/radio/" + filename
		main.fs.write_file(save_path, png_data)
		print("[RadioReceiver] SSTV 图像已保存: ", save_path)

# ══════════════════════════════════════════
#  自动扫描
# ══════════════════════════════════════════
func _do_auto_scan_step() -> void:
	var step: float = _get_freq_step()
	current_frequency += step
	if current_frequency > _get_band_max():
		current_frequency = _get_band_min()
		_auto_scan_active = false
		return

	var result: Dictionary = signal_mgr.get_best_signal(current_frequency, current_band, current_azimuth, current_elevation)
	if result["quality"] > 0.3:
		_auto_scan_active = false
	_on_tuning_changed()

# ══════════════════════════════════════════
#  导航栏
# ══════════════════════════════════════════
func _update_nav() -> void:
	if nav_label == null:
		return
	var p: String = T.primary_hex if T else "#33ff33"
	var m: String = T.muted_hex if T else "#666666"
	var parts: Array[String] = []
	parts.append("[color=%s]←→[/color] 频率" % m)
	parts.append("[color=%s]↑↓[/color] 方位" % m)
	parts.append("[color=%s]<>[/color] 仰角" % m)
	parts.append("[color=%s]1-4[/color] 波段" % m)
	parts.append("[color=%s]+/-[/color] 音量" % m)
	parts.append("[color=%s]Tab[/color] 模式" % m)
	parts.append("[color=%s]S[/color] 扫描" % m)
	parts.append("[color=%s]L[/color] 日志" % m)
	if current_mode == RadioMode.SSTV:
		parts.append("[color=%s]Space[/color] 接收" % m)
	if sstv_decoder.is_complete:
		parts.append("[color=%s]P[/color] 保存" % m)
	parts.append("[color=%s]Q[/color] 退出" % m)

	# 使用 append_text 以启用 BBCode 颜色
	nav_label.text = ""
	nav_label.append_text(" | ".join(parts))

# ══════════════════════════════════════════
#  方位辅助
# ══════════════════════════════════════════
func _get_direction_name(azimuth: float) -> String:
	var snapped_val: int = (roundi(azimuth / 45.0) * 45) % 360
	return DIR_NAMES.get(snapped_val, "N")

func _get_direction_arrow(azimuth: float) -> String:
	var snapped_val: int = (roundi(azimuth / 45.0) * 45) % 360
	return DIR_ARROWS.get(snapped_val, "↑")

# ══════════════════════════════════════════
#  信号强度条生成
# ══════════════════════════════════════════
func _build_signal_bar(quality: float, width: int = 20) -> String:
	var filled: int = int(quality * float(width))
	var bar: String = ""
	for i in range(width):
		if i < filled:
			bar += "█"
		else:
			bar += "░"
	return bar

func _build_signal_bar_colored(quality: float, width: int = 20) -> String:
	var p: String = T.primary_hex if T else "#33ff33"
	var w: String = T.warning_hex if T else "#ffaa00"
	var e: String = T.error_hex if T else "#ff3333"
	var m: String = T.muted_hex if T else "#666666"
	var filled: int = int(quality * float(width))
	var bar: String = ""
	for i in range(width):
		if i < filled:
			var bar_ratio: float = float(i) / float(width)
			var color: String = p
			if bar_ratio < 0.3:
				color = e
			elif bar_ratio < 0.6:
				color = w
			bar += "[color=%s]█[/color]" % color
		else:
			bar += "[color=%s]░[/color]" % m
	return bar

# ══════════════════════════════════════════════════════════════
#  自定义绘制画布（内部类）
# ══════════════════════════════════════════════════════════════
class _RadioCanvas extends Control:
	var radio: RadioReceiver = null
	var _font: Font = null
	var _font_size: int = 16
	var _small_font_size: int = 14
	var _tiny_font_size: int = 11

	func _ready() -> void:
		_font = ThemeDB.fallback_font

	func _process(_delta: float) -> void:
		if radio and radio.is_active:
			radio.process(_delta)

	func _draw() -> void:
		if radio == null or not radio.is_active:
			return
		var rect: Rect2 = get_rect()
		var w: float = rect.size.x
		var h: float = rect.size.y

		# 背景
		draw_rect(Rect2(0, 0, w, h), radio.bg_color)

		# 左右分栏
		var left_w: float = w * LEFT_PANEL_RATIO
		var right_x: float = left_w + MARGIN
		var right_w: float = w - right_x - MARGIN

		# 分隔线
		draw_line(Vector2(left_w, MARGIN), Vector2(left_w, h - MARGIN), radio.grid_color, 1.0)

		_draw_left_panel(left_w, h)
		_draw_right_panel(right_x, right_w, h)

	# ══════════════════════════════════════════
	#  左面板
	# ══════════════════════════════════════════
	func _draw_left_panel(panel_w: float, panel_h: float) -> void:
		var x: float = MARGIN
		var y: float = MARGIN
		var col: Color = radio.draw_color
		var dim: Color = radio.draw_color_dim
		var gc: Color = radio.grid_color

		# ── 标题（三态模式字符串）──
		var mode_str: String
		match radio.current_mode:
			RadioMode.MORSE:
				mode_str = "MORSE/CW"
			RadioMode.SSTV:
				mode_str = "SSTV"
			RadioMode.WATERFALL:
				mode_str = "WATERFALL"
			_:
				mode_str = "UNKNOWN"

		var title: String = "RADIO RECEIVER — " + mode_str
		draw_string(_font, Vector2(x, y + _font_size), title, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, col)
		y += _font_size + SECTION_GAP
		draw_line(Vector2(x, y), Vector2(panel_w - MARGIN, y), gc, 1.0)
		y += SECTION_GAP

		# ── 波段选择 ──
		draw_string(_font, Vector2(x, y + _small_font_size), "BAND:", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, dim)
		y += _small_font_size + 2

		var band_x: float = x
		for band_name in RadioConfigParser.BAND_ORDER:
			var is_current: bool = (band_name == radio.current_band)
			var band_col: Color = col if is_current else dim
			var label: String = "[%s]" % band_name if is_current else " %s " % band_name
			draw_string(_font, Vector2(band_x, y + _small_font_size), label, HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, band_col)
			band_x += _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size).x + 8

		y += _small_font_size + SECTION_GAP

		# ── 频率显示 ──
		draw_string(_font, Vector2(x, y + _small_font_size), "FREQ:", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, dim)
		y += _small_font_size + 2
		var freq_str: String = "%.3f MHz" % radio.current_frequency
		draw_string(_font, Vector2(x + 8, y + _font_size + 4), freq_str, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size + 4, col)
		y += _font_size + 8 + SECTION_GAP

		# 频率刻度条
		var ruler_x: float = x
		var ruler_w: float = panel_w - MARGIN * 2
		var ruler_h: float = 16.0
		radio._freq_ruler_rect = Rect2(ruler_x, y, ruler_w, ruler_h)
		_draw_freq_ruler(ruler_x, y, ruler_w, ruler_h)
		y += 20 + SECTION_GAP

		# ── 方位 / 仰角 / 音量（紧凑显示） ──
		var arrow: String = radio._get_direction_arrow(radio.current_azimuth)
		var dir_name: String = radio._get_direction_name(radio.current_azimuth)
		draw_string(
			_font,
			Vector2(x, y + _small_font_size),
			"AZ: %05.1f° %s %s  EL: %04.1f°  VOL: %d%%" % [
				radio.current_azimuth, arrow, dir_name,
				radio.current_elevation, int(radio.current_volume * 100.0)
			],
			HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, col
		)
		y += _small_font_size + SECTION_GAP

		# ── 雷达 + 仰角并列（居中紧凑） ──
		var available_w: float = panel_w - MARGIN * 2
		var diagram_gap: float = 12.0
		var diagram_size: float = minf((available_w - diagram_gap) * 0.5, 140.0)
		var total_w: float = diagram_size * 2 + diagram_gap
		var start_x: float = x + (available_w - total_w) * 0.5

		# 左侧：雷达图
		var radar_cx: float = start_x + diagram_size * 0.5
		var radar_cy: float = y + diagram_size * 0.5
		_draw_radar(radar_cx, radar_cy, diagram_size * 0.45)

		# 右侧：天线仰角图
		var elev_x: float = start_x + diagram_size + diagram_gap
		var elev_h: float = diagram_size
		_draw_elevation_indicator(elev_x, y, diagram_size, elev_h)
		y += diagram_size + 4 + SECTION_GAP

		# ── 信号强度 ──
		draw_line(Vector2(x, y), Vector2(panel_w - MARGIN, y), gc, 1.0)
		y += 4
		draw_string(_font, Vector2(x, y + _small_font_size), "SIGNAL:", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, dim)
		y += _small_font_size + 2
		_draw_signal_meter(x, y, panel_w - MARGIN * 2, 14.0, radio._display_quality)
		y += 16 + 2

		var s_value: int = _quality_to_s(radio._display_quality)
		var s_str: String = "S%d" % s_value
		if radio._display_quality > 0.9:
			s_str += "+"

		draw_string(_font, Vector2(x, y + _small_font_size), s_str, HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, col)

		var quality_pct: String = "%d%%" % int(radio._display_quality * 100.0)
		var pct_w: float = _font.get_string_size(quality_pct, HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size).x
		draw_string(_font, Vector2(panel_w - MARGIN - pct_w, y + _small_font_size), quality_pct, HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, col)
		y += _small_font_size + SECTION_GAP

		# ── 当前信号信息（按频率距离锁定最近信号源，不闪烁） ──
		draw_line(Vector2(x, y), Vector2(panel_w - MARGIN, y), gc, 1.0)
		y += 4
		var ds = radio._nearest_signal
		if ds != null:
			var sig = ds as RadioConfigParser.RadioSignal
			var freq_dist: float = absf(radio.current_frequency - sig.frequency)
			var lock_label: String
			var label_col: Color
			if radio._signal_lock_timer >= SIGNAL_LOCK_TIME and radio.current_signal == ds:
				lock_label = "LOCKED: "
				label_col = col
			elif freq_dist <= sig.tolerance_freq * 0.5:
				lock_label = "TUNED: "
				label_col = col
			elif freq_dist <= sig.tolerance_freq:
				lock_label = "DETECT: "
				label_col = radio.warning_color
			else:
				lock_label = "NEARBY: "
				label_col = dim

			var label_text: String = sig.label if not sig.label.is_empty() else sig.id
			draw_string(_font, Vector2(x, y + _small_font_size), lock_label + label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, label_col)
			y += _small_font_size + 2

			draw_string(
				_font, Vector2(x, y + _small_font_size),
				"TYPE: %s  %.3f MHz  AZ:%.0f° EL:%.0f°" % [sig.type.to_upper(), sig.frequency, sig.azimuth, sig.elevation],
				HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, dim
			)
			y += _small_font_size + 2
			if not sig.hint.is_empty():
				draw_string(_font, Vector2(x, y + _small_font_size), "HINT: " + sig.hint, HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, radio.warning_color)
				y += _small_font_size + 2
		else:
			draw_string(_font, Vector2(x, y + _small_font_size), "NO SIGNAL", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, dim)
			y += _small_font_size + 2

		# ── ★ 发现统计 / 信标日志 ──
		y += 2
		var stats: Dictionary = radio.signal_mgr.get_discovery_stats()
		var beacon_stats: Dictionary = radio.signal_mgr.get_beacon_stats()

		if radio._show_beacon_log:
			# 完整信标日志视图
			draw_line(Vector2(x, y), Vector2(panel_w - MARGIN, y), gc, 1.0)
			y += 4
			draw_string(_font, Vector2(x, y + _small_font_size), "BEACON LOG:", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, col)
			y += _small_font_size + 2

			var blog: Array[Dictionary] = radio.signal_mgr.get_beacon_log()
			if blog.is_empty():
				draw_string(_font, Vector2(x + 4, y + _small_font_size), "(无记录)", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, dim)
				y += _small_font_size + 2
			else:
				for blog_entry in blog:
					if y + _small_font_size > panel_h - MARGIN * 4:
						draw_string(_font, Vector2(x + 4, y + _small_font_size), "...", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, dim)
						y += _small_font_size
						break
					var callsign: String = str(blog_entry.get("beacon_id", "???"))
					var freq_s: String = "%.3f" % float(blog_entry.get("freq, 0").replace(",", "")) if blog_entry.has("freq") else "%.3f" % 0.0
					var band_s: String = str(blog_entry.get("band", ""))
					var time_s: String = str(blog_entry.get("time", ""))
					draw_string(_font, Vector2(x + 4, y + _small_font_size), "%s  %s %s  [%s]" % [callsign, freq_s, band_s, time_s], HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, dim)
					y += _small_font_size + 1

		# 信标进度或紧凑统计
		if beacon_stats["total"] > 0:
			y += 2
			var pct_str: String = "%d/%d BEACONS" % [beacon_stats["found"], beacon_stats["total"]]
			var pct_col: Color = col if radio.signal_mgr.all_beacons_found() else dim
			draw_string(_font, Vector2(x, y + _small_font_size), pct_str, HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, pct_col)
			y += _small_font_size + 2
			if radio.signal_mgr.all_beacons_found():
				draw_string(_font, Vector2(x, y + _small_font_size), "★ ALL BEACONS LOGGED", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, radio.warning_color)
				y += _small_font_size + 2
		else:
			if stats["total"] > 0:
				var disc_str: String = "SIGNALS: %d/%d" % [stats["discovered"], stats["total"]]
				draw_string(_font, Vector2(x, y + _small_font_size), disc_str, HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, dim)
				y += _small_font_size + 2

		# ── 状态行 ──
		if radio._auto_scan_active:
			draw_string(_font, Vector2(x, y + _small_font_size), "◉ SCANNING...", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, radio.warning_color)
			y += _small_font_size + 2
		if radio._signal_lock_timer > 0 and radio._signal_lock_timer < SIGNAL_LOCK_TIME:
			var lock_pct: int = int((radio._signal_lock_timer / SIGNAL_LOCK_TIME) * 100.0)
			draw_string(_font, Vector2(x, y + _small_font_size), "LOCKING: %d%%" % lock_pct, HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, radio.warning_color)

	# ══════════════════════════════════════════
	#  雷达图
	# ══════════════════════════════════════════
	func _draw_radar(cx: float, cy: float, radius: float) -> void:
		var col: Color = radio.draw_color
		var dim: Color = radio.draw_color_dim
		var gc: Color = radio.grid_color

		draw_arc(Vector2(cx, cy), radius, 0, TAU, 64, gc, 1.0)
		draw_arc(Vector2(cx, cy), radius * 0.6, 0, TAU, 48, gc * 0.7, 1.0)
		draw_arc(Vector2(cx, cy), radius * 0.3, 0, TAU, 32, gc * 0.5, 1.0)
		draw_line(Vector2(cx - radius, cy), Vector2(cx + radius, cy), gc * 0.7, 1.0)
		draw_line(Vector2(cx, cy - radius), Vector2(cx, cy + radius), gc * 0.7, 1.0)

		draw_string(_font, Vector2(cx - 3, cy - radius - 4), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim)
		draw_string(_font, Vector2(cx - 3, cy + radius + 12), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim)
		draw_string(_font, Vector2(cx + radius + 4, cy + 4), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim)
		draw_string(_font, Vector2(cx - radius - 12, cy + 4), "W", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim)

		var az_rad: float = deg_to_rad(radio.current_azimuth - 90.0)
		var pointer_end: Vector2 = Vector2(cx, cy) + Vector2(cos(az_rad), sin(az_rad)) * radius * 0.85
		draw_line(Vector2(cx, cy), pointer_end, col, 2.0)

		var tip_size: float = 5.0
		var perp: Vector2 = Vector2(-sin(az_rad), cos(az_rad)) * tip_size
		var tri_pts := PackedVector2Array([
			pointer_end,
			pointer_end - Vector2(cos(az_rad), sin(az_rad)) * tip_size * 2 + perp,
			pointer_end - Vector2(cos(az_rad), sin(az_rad)) * tip_size * 2 - perp
		])
		draw_colored_polygon(tri_pts, col)

		var elev_ratio: float = radio.current_elevation / 90.0
		var elev_arc_radius: float = radius * (1.0 - elev_ratio * 0.7)
		draw_arc(Vector2(cx, cy), elev_arc_radius, 0, TAU, 48, col * 0.3, 1.5)

		for sig in radio.signal_mgr.signals:
			var s = sig as RadioConfigParser.RadioSignal
			if s.band != radio.current_band:
				continue
			var sig_az_rad: float = deg_to_rad(s.azimuth - 90.0)
			var sig_elev_ratio: float = s.elevation / 90.0
			var sig_r: float = radius * (1.0 - sig_elev_ratio * 0.7)
			var sig_pos: Vector2 = Vector2(cx, cy) + Vector2(cos(sig_az_rad), sin(sig_az_rad)) * sig_r
			var sig_col: Color = dim
			if radio.signal_mgr.is_discovered(s.id):
				sig_col = col * 0.7
			if s == radio.current_signal:
				sig_col = radio.warning_color
			draw_circle(sig_pos, 3.0, sig_col)

		var scan_angle: float = fmod(radio._display_quality * 100.0 + radio.signal_mgr._time_elapsed * 60.0, 360.0)
		var scan_rad: float = deg_to_rad(scan_angle - 90.0)
		var scan_end: Vector2 = Vector2(cx, cy) + Vector2(cos(scan_rad), sin(scan_rad)) * radius
		draw_line(Vector2(cx, cy), scan_end, Color(col.r, col.g, col.b, 0.15), 1.0)

		draw_string(_font, Vector2(cx - radius, cy + radius + 14), "AZIMUTH", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dim)

	# ══════════════════════════════════════════
	#  天线仰角图
	# ══════════════════════════════════════════
	func _draw_elevation_indicator(bx: float, by: float, bw: float, bh: float) -> void:
		var col: Color = radio.draw_color
		var dim: Color = radio.draw_color_dim
		var gc: Color = radio.grid_color

		draw_rect(Rect2(bx, by + bh * 0.7, bw, bh * 0.3), Color(gc.r, gc.g, gc.b, 0.12))
		draw_line(Vector2(bx, by + bh * 0.7), Vector2(bx + bw, by + bh * 0.7), dim, 1.0)

		var pivot_x: float = bx + bw * 0.2
		var pivot_y: float = by + bh * 0.7
		var arm_length: float = minf(bw * 0.6, bh * 0.65)

		for angle_deg in [0, 30, 60, 90]:
			var a_rad: float = deg_to_rad(float(angle_deg))
			var end_x: float = pivot_x + cos(a_rad) * arm_length
			var end_y: float = pivot_y - sin(a_rad) * arm_length
			draw_line(Vector2(pivot_x, pivot_y), Vector2(end_x, end_y), Color(gc.r, gc.g, gc.b, 0.2), 1.0)
			var lbl_x: float = pivot_x + cos(a_rad) * (arm_length + 4)
			var lbl_y: float = pivot_y - sin(a_rad) * (arm_length + 4)
			draw_string(_font, Vector2(lbl_x - 4, lbl_y + 3), "%d°" % angle_deg, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dim)

		draw_colored_polygon(PackedVector2Array([
			Vector2(pivot_x, pivot_y),
			Vector2(pivot_x - 6, pivot_y + 8),
			Vector2(pivot_x + 6, pivot_y + 8)
		]), dim)

		var elev_rad: float = deg_to_rad(radio.current_elevation)
		var arm_ex: float = pivot_x + cos(elev_rad) * arm_length
		var arm_ey: float = pivot_y - sin(elev_rad) * arm_length
		draw_line(Vector2(pivot_x, pivot_y), Vector2(arm_ex, arm_ey), col, 2.0)
		draw_circle(Vector2(arm_ex, arm_ey), 2.5, col)

		var perp_rad: float = elev_rad + PI * 0.5
		var cx1: float = cos(perp_rad) * 6.0
		var cy1: float = -sin(perp_rad) * 6.0
		draw_line(Vector2(arm_ex - cx1, arm_ey - cy1), Vector2(arm_ex + cx1, arm_ey + cy1), col, 1.5)

		var mx: float = pivot_x + cos(elev_rad) * arm_length * 0.7
		var my: float = pivot_y - sin(elev_rad) * arm_length * 0.7
		var cx2: float = cos(perp_rad) * 4.0
		var cy2: float = -sin(perp_rad) * 4.0
		draw_line(Vector2(mx - cx2, my - cy2), Vector2(mx + cx2, my + cy2), col, 1.5)

		var tx: float = pivot_x + cos(elev_rad) * arm_length * 0.4 + 4.0
		var ty: float = pivot_y - sin(elev_rad) * arm_length * 0.4 - 2.0
		draw_string(_font, Vector2(tx, ty), "%.1f°" % radio.current_elevation, HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, col)

		# 信号源仰角参考线（使用 _nearest_signal）
		if radio._nearest_signal != null:
			var sig = radio._nearest_signal as RadioConfigParser.RadioSignal
			var s_rad: float = deg_to_rad(sig.elevation)
			var s_len: float = arm_length * 0.85
			var dash_n: int = 10
			for i in range(dash_n):
				if i % 2 == 0:
					var t0: float = float(i) / float(dash_n)
					var t1: float = float(i + 1) / float(dash_n)
					draw_line(
						Vector2(pivot_x + cos(s_rad) * s_len * t0, pivot_y - sin(s_rad) * s_len * t0),
						Vector2(pivot_x + cos(s_rad) * s_len * t1, pivot_y - sin(s_rad) * s_len * t1),
						radio.warning_color * 0.5, 1.0
					)
			draw_string(_font, Vector2(pivot_x + cos(s_rad) * s_len + 3.0, pivot_y - sin(s_rad) * s_len), "SRC", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, radio.warning_color * 0.5)

		draw_string(_font, Vector2(bx, by + bh + 10), "ELEVATION", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dim)

	# ══════════════════════════════════════════
	#  右面板分发（三模式）
	# ══════════════════════════════════════════
	func _draw_right_panel(rx: float, rw: float, panel_h: float) -> void:
		var y: float = MARGIN
		var col: Color = radio.draw_color
		var dim: Color = radio.draw_color_dim

		# ── 模式标签页 ──
		var tab_names: Array[String] = ["MORSE", "SSTV", "WATERFALL"]
		var tab_w: float = rw / 3.0
		for i in range(3):
			var tx: float = rx + i * tab_w
			var is_active_tab: bool = (i == int(radio.current_mode))
			var tab_col: Color = col if is_active_tab else dim
			if is_active_tab:
				draw_rect(Rect2(tx, y, tab_w, _small_font_size + 4.0), Color(col.r, col.g, col.b, 0.15))
			draw_string(_font, Vector2(tx + 4, y + _small_font_size), tab_names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, tab_col)
		y += _small_font_size + 8.0

		# ── 分发到对应面板 ──
		match radio.current_mode:
			RadioMode.MORSE:
				_draw_morse_panel(rx, y, rw, panel_h)
			RadioMode.SSTV:
				_draw_sstv_panel(rx, y, rw, panel_h)
			RadioMode.WATERFALL:
				_draw_waterfall_panel(rx, y, rw, panel_h)

	# ══════════════════════════════════════════
	#  摩斯面板
	# ══════════════════════════════════════════
	func _draw_morse_panel(rx: float, y: float, rw: float, panel_h: float) -> void:
		var col: Color = radio.draw_color
		var dim: Color = radio.draw_color_dim

		# 数字电台模式标识
		var morse_title: String = "MORSE DECODER"
		if radio.morse_engine.numbers_mode:
			morse_title = "NUMBERS STATION DECODER"
		draw_string(_font, Vector2(rx, y + _font_size), morse_title, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, col)
		y += _font_size + SECTION_GAP

		# 数字电台提示信息
		if radio.morse_engine.numbers_mode and radio.current_signal != null:
			var sig = radio.current_signal as RadioConfigParser.RadioSignal
			if sig.has_method("cipher_type") and not sig.cipher_type.is_empty():
				draw_string(_font, Vector2(rx, y + _small_font_size), "CIPHER: " + sig.cipher_type.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, radio.warning_color)
				y += _small_font_size + 2
			if sig.has_method("cipher_key_file") and not sig.cipher_key_file.is_empty():
				draw_string(_font, Vector2(rx, y + _small_font_size), "KEY FILE: " + sig.cipher_key_file.get_file(), HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, radio.warning_color)
				y += _small_font_size + 2
			if (not sig.has_method("cipher_type") or sig.cipher_type.is_empty()) and (not sig.has_method("cipher_key_file") or sig.cipher_key_file.is_empty()):
				draw_string(_font, Vector2(rx, y + _small_font_size), "记录数字序列以获取线索", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, dim)
				y += _small_font_size + 2

		draw_string(_font, Vector2(rx, y + _small_font_size), "CODE:", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, dim)
		y += _small_font_size + 2

		var morse_text: String = radio.morse_engine.get_morse_display()
		if morse_text.length() > 60:
			morse_text = "..." + morse_text.right(57)
		draw_string(_font, Vector2(rx + 4, y + _small_font_size), morse_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, col)
		y += _small_font_size + SECTION_GAP

		draw_string(_font, Vector2(rx, y + _small_font_size), "DECODED:", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, dim)
		y += _small_font_size + 4

		var text_area_h: float = panel_h - y - MARGIN * 2
		draw_rect(Rect2(rx, y, rw, text_area_h), radio.grid_color)

		var decoded: String = radio.morse_engine.get_decoded_text()
		if decoded.is_empty():
			decoded = "等待信号..."
		var max_chars_per_line: int = int(rw / (_small_font_size * 0.6))
		if max_chars_per_line < 10:
			max_chars_per_line = 10

		var lines: PackedStringArray = _wrap_text(decoded, max_chars_per_line)
		var text_y: float = y + 4
		var max_lines: int = int(text_area_h / (_small_font_size + 2))
		var start_line: int = maxi(0, lines.size() - max_lines)
		for i in range(start_line, lines.size()):
			if text_y + _small_font_size > y + text_area_h:
				break
			draw_string(_font, Vector2(rx + 4, text_y + _small_font_size), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, col)
			text_y += _small_font_size + 2

		if radio.morse_engine.is_playing:
			var progress: float = radio.morse_engine.get_progress()
			var bar_y: float = y + text_area_h + 4
			var bar_w: float = rw * progress
			draw_rect(Rect2(rx, bar_y, rw, 3), dim)
			draw_rect(Rect2(rx, bar_y, bar_w, 3), col)

	# ══════════════════════════════════════════
	#  SSTV 面板
	# ══════════════════════════════════════════
	func _draw_sstv_panel(rx: float, y: float, rw: float, panel_h: float) -> void:
		var col: Color = radio.draw_color
		var dim: Color = radio.draw_color_dim

		draw_string(_font, Vector2(rx, y + _font_size), "SSTV RECEIVER", HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, col)
		y += _font_size + SECTION_GAP

		if radio._sstv_receiving and radio.sstv_decoder.is_receiving:
			# 音频准备中提示
			if not radio.sstv_decoder.is_audio_ready():
				var prep_pct: float = radio.sstv_decoder.get_audio_gen_progress()
				var prep_text: String = "PREPARING AUDIO... %.0f%%" % (prep_pct * 100.0)
				draw_string(_font, Vector2(rx, y + _small_font_size), prep_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, radio.warning_color)
				y += _small_font_size + 4
				draw_rect(Rect2(rx, y, rw, 4), dim)
				draw_rect(Rect2(rx, y, rw * prep_pct, 4), radio.warning_color)
				y += 8

			var progress: float = radio.sstv_decoder.get_progress()
			var remaining: float = radio.sstv_decoder.get_remaining_time()
			draw_string(_font, Vector2(rx, y + _small_font_size), "RECEIVING: %d%% | %.1fs left" % [int(progress * 100), remaining], HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, radio.warning_color)
			y += _small_font_size + 4
			draw_rect(Rect2(rx, y, rw, 4), dim)
			draw_rect(Rect2(rx, y, rw * progress, 4), col)
			y += 8

			var tex: ImageTexture = radio.sstv_decoder.get_received_texture()
			if tex != null:
				var img_h: float = panel_h - y - MARGIN * 2
				var img_w: float = rw
				var aspect: float = float(tex.get_width()) / maxf(float(tex.get_height()), 1.0)
				if img_w / aspect > img_h:
					img_w = img_h * aspect
				else:
					img_h = img_w / aspect
				var img_x: float = rx + (rw - img_w) * 0.5
				draw_texture_rect(tex, Rect2(img_x, y, img_w, img_h), false)
		elif radio.sstv_decoder.is_complete:
			var avg_q: float = radio.sstv_decoder.get_average_quality()
			draw_string(_font, Vector2(rx, y + _small_font_size), "COMPLETE — AVG QUALITY: %d%%" % int(avg_q * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, col)
			y += _small_font_size + 4
			draw_string(_font, Vector2(rx, y + _small_font_size), "Press P to save image", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, dim)
			y += _small_font_size + 8

			var tex2: ImageTexture = radio.sstv_decoder.get_received_texture()
			if tex2 != null:
				var img_h2: float = panel_h - y - MARGIN * 2
				var img_w2: float = rw
				var aspect2: float = float(tex2.get_width()) / maxf(float(tex2.get_height()), 1.0)
				if img_w2 / aspect2 > img_h2:
					img_w2 = img_h2 * aspect2
				else:
					img_h2 = img_w2 / aspect2
				var img_x2: float = rx + (rw - img_w2) * 0.5
				draw_texture_rect(tex2, Rect2(img_x2, y, img_w2, img_h2), false)
		elif radio._sstv_detected:
			draw_string(_font, Vector2(rx, y + _small_font_size), "◉ SSTV SIGNAL DETECTED", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, radio.warning_color)
			y += _small_font_size + 4
			if radio.current_signal != null:
				draw_string(_font, Vector2(rx, y + _small_font_size), "Mode: " + radio.current_signal.sstv_mode, HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, col)
				y += _small_font_size + 4
			draw_string(_font, Vector2(rx, y + _small_font_size), "Press SPACE to start receiving", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, dim)
		else:
			draw_string(_font, Vector2(rx, y + _small_font_size), "调谐到 SSTV 信号后按 SPACE 开始接收", HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, dim)

	# ══════════════════════════════════════════
	#  瀑布图面板
	# ══════════════════════════════════════════
	func _draw_waterfall_panel(rx: float, y: float, rw: float, panel_h: float) -> void:
		var col: Color = radio.draw_color
		var dim: Color = radio.draw_color_dim
		var gc: Color = radio.grid_color
		var base_y: float = y

		draw_string(_font, Vector2(rx, y + _font_size), "SPECTRUM WATERFALL", HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, col)
		y += _font_size + SECTION_GAP

		var band_min: float = radio._get_band_min()
		var band_max: float = radio._get_band_max()
		var band_range: float = band_max - band_min

		# 顶部实时柱状谱（能量条）
		var spectrum_h: float = minf(panel_h * 0.25, 80.0)
		draw_rect(Rect2(rx, y, rw, spectrum_h), Color(gc.r, gc.g, gc.b, 0.15))
		if not radio._waterfall_spectrum.is_empty() and rw > 0:
			var bar_count: int = mini(radio._waterfall_spectrum.size(), int(rw))
			var bar_w: float = rw / float(bar_count)
			for i in range(bar_count):
				var val: float = radio._waterfall_spectrum[i]
				if val < 0.05:
					continue
				var bar_h: float = val * spectrum_h
				var bar_x: float = rx + i * bar_w
				var bar_col: Color = radio._spectrum_to_color(val)
				bar_col.a = 0.8
				draw_rect(Rect2(bar_x, y + spectrum_h - bar_h, maxf(bar_w - 0.5, 1.0), bar_h), bar_col)

		# 频率标记线（顶部柱状谱）
		if band_range > 0.0:
			var freq_ratio: float = clampf((radio.current_frequency - band_min) / band_range, 0.0, 1.0)
			var marker_x: float = rx + freq_ratio * rw
			draw_line(Vector2(marker_x, y), Vector2(marker_x, y + spectrum_h), col, 1.5)
			draw_colored_polygon(PackedVector2Array([
				Vector2(marker_x, y),
				Vector2(marker_x - 3, y - 4),
				Vector2(marker_x + 3, y - 4)
			]), col)

		# 频率刻度
		var tick_y: float = y + spectrum_h
		var tick_count: int = 5
		for t_idx in range(tick_count + 1):
			var t_ratio: float = float(t_idx) / float(tick_count)
			var t_x: float = rx + t_ratio * rw
			var t_freq: float = band_min + t_ratio * band_range if band_range > 0.0 else 0.0
			draw_line(Vector2(t_x, tick_y), Vector2(t_x, tick_y + 3), dim, 1.0)
			var freq_str: String = "%.1f" % t_freq
			draw_string(_font, Vector2(t_x - 12, tick_y + 3 + _tiny_font_size), freq_str, HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, dim)

		y = tick_y + _tiny_font_size + 8.0

		# 瀑布图
		var remaining_h: float = maxf(base_y + panel_h - y - _tiny_font_size - 10.0, 40.0)
		if radio._waterfall_texture != null:
			draw_texture_rect(radio._waterfall_texture, Rect2(rx, y, rw, remaining_h), false)

			# 当前频率标记线（瀑布图）
			if band_range > 0.0:
				var freq_ratio2: float = clampf((radio.current_frequency - band_min) / band_range, 0.0, 1.0)
				var marker_x2: float = rx + freq_ratio2 * rw
				draw_line(Vector2(marker_x2, y), Vector2(marker_x2, y + remaining_h), Color(col.r, col.g, col.b, 0.5), 1.0)

			# 已发现信号标记（仅画竖线，隐藏标签文字）
			for sig in radio.signal_mgr.signals:
				var s = sig as RadioConfigParser.RadioSignal
				if s.band != radio.current_band:
					continue
				if not radio.signal_mgr.is_discovered(s.id):
					continue
				var sig_ratio: float = 0.0
				if band_range > 0.0:
					sig_ratio = clampf((s.frequency - band_min) / band_range, 0.0, 1.0)
				var sig_x: float = rx + sig_ratio * rw
				draw_line(Vector2(sig_x, y), Vector2(sig_x, y + 8), col, 1.0)
				if not WF_HIDE_LABELS:
					draw_string(_font, Vector2(sig_x + 2, y + _tiny_font_size), s.label.left(8), HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, col * 0.7)

		y += remaining_h + 4.0

		# 底部 HUD（按需隐藏）
		if not WF_HIDE_BOTTOM_HUD:
			var info_text: String = "BAND:%s  FREQ:%.3f  AZ:%d°  EL:%d°" % [
				radio.current_band, radio.current_frequency,
				int(radio.current_azimuth), int(radio.current_elevation)
			]
			draw_string(_font, Vector2(rx, y + _tiny_font_size), info_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _tiny_font_size, dim)

	# ══════════════════════════════════════════
	#  频率刻度条
	# ══════════════════════════════════════════
	func _draw_freq_ruler(rx: float, ry: float, rw: float, rh: float) -> void:
		var col: Color = radio.draw_color
		var dim: Color = radio.draw_color_dim
		var gc: Color = radio.grid_color

		var band_min: float = radio._get_band_min()
		var band_max: float = radio._get_band_max()
		var band_range: float = band_max - band_min
		if band_range <= 0.0:
			return

		# 背景
		draw_rect(Rect2(rx, ry, rw, rh), Color(gc.r, gc.g, gc.b, 0.2))

		# 信号源标记
		for sig in radio.signal_mgr.signals:
			var s = sig as RadioConfigParser.RadioSignal
			if s.band != radio.current_band:
				continue
			var sig_ratio: float = (s.frequency - band_min) / band_range
			var sig_x: float = rx + sig_ratio * rw
			var sig_col: Color = dim
			if radio.signal_mgr.is_discovered(s.id):
				sig_col = col * 0.6
			draw_line(Vector2(sig_x, ry), Vector2(sig_x, ry + rh), sig_col, 1.0)

		# 当前频率指针
		var freq_ratio: float = (radio.current_frequency - band_min) / band_range
		var pointer_x: float = rx + freq_ratio * rw
		draw_line(Vector2(pointer_x, ry - 2), Vector2(pointer_x, ry + rh + 2), col, 2.0)
		# 三角指针
		draw_colored_polygon(PackedVector2Array([
			Vector2(pointer_x, ry - 2),
			Vector2(pointer_x - 4, ry - 6),
			Vector2(pointer_x + 4, ry - 6)
		]), col)

	# ══════════════════════════════════════════
	#  信号强度表
	# ══════════════════════════════════════════
	func _draw_signal_meter(mx: float, my: float, mw: float, mh: float, quality: float) -> void:
		var gc: Color = radio.grid_color
		var col: Color = radio.draw_color

		# 背景
		draw_rect(Rect2(mx, my, mw, mh), Color(gc.r, gc.g, gc.b, 0.2))

		# 填充
		var fill_w: float = mw * clampf(quality, 0.0, 1.0)
		var fill_col: Color
		if quality >= 0.7:
			fill_col = col
		elif quality >= 0.4:
			fill_col = radio.warning_color
		else:
			fill_col = radio.error_color
		if fill_w > 0.0:
			draw_rect(Rect2(mx, my, fill_w, mh), fill_col)

		# 刻度线
		for i in range(1, 10):
			var tick_x: float = mx + mw * (float(i) / 10.0)
			draw_line(Vector2(tick_x, my), Vector2(tick_x, my + mh), Color(0, 0, 0, 0.3), 1.0)

	func _quality_to_s(quality: float) -> int:
		# S1-S9 映射
		return clampi(int(quality * 9.0) + 1, 1, 9)

	# ══════════════════════════════════════════
	#  文本自动换行
	# ══════════════════════════════════════════
	func _wrap_text(text: String, max_width: int) -> PackedStringArray:
		var result: PackedStringArray = PackedStringArray()
		if text.is_empty():
			return result
		var current_line: String = ""
		for ch in text:
			if ch == "\n":
				result.append(current_line)
				current_line = ""
				continue
			current_line += ch
			if current_line.length() >= max_width:
				result.append(current_line)
				current_line = ""
		if not current_line.is_empty():
			result.append(current_line)
		return result
