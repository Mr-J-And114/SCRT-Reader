# ============================================================
# video_player_viewer.gd - CRT 风格全屏视频播放器
# 支持格式:
#   原生: .ogv (Ogg Theora) — Godot 4.x 内置支持
#   扩展: .mp4, .mkv, .avi, .webm 等 (需要 ffmpeg-gdextension)
# ============================================================
class_name VideoPlayerViewer
extends RefCounted

var main = null
var audio_manager = null
var T = null

var is_active: bool = false
var _file_name: String = ""
var _file_path: String = ""
var _is_paused: bool = false
var _update_timer: float = 0.0
var _temp_file_path: String = ""
var _video_ended: bool = false

# ★ 简化的时长管理
var _known_length: float = 0.0       # 已确认的总时长（播完后才确定）
var _max_seen_position: float = 0.0  # 播放过程中见过的最大位置

# UI 节点
var overlay: Panel = null
var video_player: VideoStreamPlayer = null
var controls_label: RichTextLabel = null
var info_label: RichTextLabel = null
var progress_bar_bg: Panel = null
var progress_bar_fill: Panel = null

const SEEK_STEP: float = 5.0
const VOLUME_STEP: float = 0.1
const PROGRESS_BAR_HEIGHT: int = 6

# ★ 支持的视频扩展名（分两类）
const NATIVE_VIDEO_EXT: Array[String] = [".ogv"]
const FFMPEG_VIDEO_EXT: Array[String] = [".mp4", ".mkv", ".avi", ".webm", ".mov", ".wmv", ".flv"]

# ══════════════════════════════════════════
#  FFmpeg 检测
# ══════════════════════════════════════════

# ★ 检测 ffmpeg-gdextension 是否可用
static var _ffmpeg_available: int = -1
static var _ffmpeg_class_name: String = ""

static func is_ffmpeg_available() -> bool:
	if _ffmpeg_available == -1:
		var possible_names: Array[String] = [
			"FFmpegVideoStream",
			"VideoStreamFFmpeg",
			"FFmpegMediaStream",
		]
		_ffmpeg_available = 0
		for cname in possible_names:
			if ClassDB.class_exists(cname):
				_ffmpeg_available = 1
				_ffmpeg_class_name = cname
				print("[VideoPlayer] FFmpeg GDExtension 已检测到，类名: ", cname)
				break
		if _ffmpeg_available == 0:
			for cname in ClassDB.get_class_list():
				if "ffmpeg" in cname.to_lower() or "FFmpeg" in cname:
					if ClassDB.is_parent_class(cname, "VideoStream") or "Stream" in cname:
						_ffmpeg_available = 1
						_ffmpeg_class_name = cname
						print("[VideoPlayer] FFmpeg GDExtension 已检测到（自动发现），类名: ", cname)
						break
		if _ffmpeg_available == 0:
			print("[VideoPlayer] FFmpeg GDExtension 未检测到，仅支持 .ogv (Ogg Theora) 格式")
	return _ffmpeg_available == 1

## 获取所有支持的视频扩展名
static func get_supported_extensions() -> Array[String]:
	var exts: Array[String] = NATIVE_VIDEO_EXT.duplicate()
	if is_ffmpeg_available():
		exts.append_array(FFMPEG_VIDEO_EXT)
	return exts

## 判断文件是否是支持的视频格式
static func is_supported_video(file_name: String) -> bool:
	var ext: String = "." + file_name.get_extension().to_lower()
	return ext in get_supported_extensions()

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════

func setup(p_main, p_audio_manager) -> void:
	main = p_main
	audio_manager = p_audio_manager
	T = ThemeManager.current

# ══════════════════════════════════════════
#  构建 UI
# ══════════════════════════════════════════

func _ensure_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		return

	var root_control: Control = main as Control

	overlay = Panel.new()
	overlay.name = "VideoPlayerOverlay"
	overlay.visible = false
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	# ★ 修复：使用不透明黑色背景，防止终端内容透出
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.0, 0.0, 0.0, 1.0)
	overlay.add_theme_stylebox_override("panel", bg_style)

	root_control.add_child(overlay)

	# ★ 把 overlay 移到 CRTEffect 之前（这样 CRT shader 仍然覆盖在上面）
	var crt_node: Node = root_control.get_node_or_null("CRTEffect")
	if crt_node:
		root_control.move_child(overlay, crt_node.get_index())

	# ── 确保锚点完全展开 ──
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.offset_left = 0
	overlay.offset_top = 0
	overlay.offset_right = 0
	overlay.offset_bottom = 0

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 0)
	margin.add_theme_constant_override("margin_right", 0)
	margin.add_theme_constant_override("margin_top", 0)
	margin.add_theme_constant_override("margin_bottom", 0)
	overlay.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 0)
	margin.add_child(vbox)

	# ── 顶部信息栏 ──
	info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.fit_content = true
	info_label.scroll_active = false
	info_label.selection_enabled = false
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_label.custom_minimum_size = Vector2(0, 28)
	# ★ 应用 CRT-ML 字体
	CrtmlParser.apply_fonts(info_label)

	var info_margin := MarginContainer.new()
	info_margin.add_theme_constant_override("margin_left", 12)
	info_margin.add_theme_constant_override("margin_right", 12)
	info_margin.add_theme_constant_override("margin_top", 4)
	info_margin.add_theme_constant_override("margin_bottom", 2)
	info_margin.add_child(info_label)
	vbox.add_child(info_margin)

	# ── 视频播放区域 ──
	video_player = VideoStreamPlayer.new()
	video_player.name = "VideoStreamPlayer"
	video_player.expand = true
	video_player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	video_player.size_flags_vertical = Control.SIZE_EXPAND_FILL
	video_player.volume_db = 0.0
	video_player.finished.connect(_on_video_finished)
	vbox.add_child(video_player)

	# ── 进度条区域 ──
	var progress_container := Control.new()
	progress_container.custom_minimum_size = Vector2(0, PROGRESS_BAR_HEIGHT + 12)
	progress_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(progress_container)

	progress_bar_bg = Panel.new()
	progress_bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	progress_bar_bg.offset_left = 20
	progress_bar_bg.offset_right = -20
	progress_bar_bg.offset_top = 4
	progress_bar_bg.offset_bottom = -4
	var bg_bar_style := StyleBoxFlat.new()
	bg_bar_style.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	bg_bar_style.corner_radius_top_left = 2
	bg_bar_style.corner_radius_top_right = 2
	bg_bar_style.corner_radius_bottom_left = 2
	bg_bar_style.corner_radius_bottom_right = 2
	progress_bar_bg.add_theme_stylebox_override("panel", bg_bar_style)
	progress_container.add_child(progress_bar_bg)

	progress_bar_fill = Panel.new()
	progress_bar_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	progress_bar_fill.anchor_right = 0.0
	progress_bar_fill.offset_left = 0
	progress_bar_fill.offset_top = 0
	progress_bar_fill.offset_right = 0
	progress_bar_fill.offset_bottom = 0
	var fill_style := StyleBoxFlat.new()
	if T:
		fill_style.bg_color = T.primary
	else:
		fill_style.bg_color = Color(0.1, 1.0, 0.2, 1.0)
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
	progress_bar_fill.add_theme_stylebox_override("panel", fill_style)
	progress_bar_bg.add_child(progress_bar_fill)

	# ── 底部控制栏 ──
	controls_label = RichTextLabel.new()
	controls_label.bbcode_enabled = true
	controls_label.fit_content = true
	controls_label.scroll_active = false
	controls_label.selection_enabled = false
	controls_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls_label.custom_minimum_size = Vector2(0, 28)
	# ★ 应用 CRT-ML 字体
	CrtmlParser.apply_fonts(controls_label)

	var ctrl_margin := MarginContainer.new()
	ctrl_margin.add_theme_constant_override("margin_left", 12)
	ctrl_margin.add_theme_constant_override("margin_right", 12)
	ctrl_margin.add_theme_constant_override("margin_top", 2)
	ctrl_margin.add_theme_constant_override("margin_bottom", 4)
	ctrl_margin.add_child(controls_label)
	vbox.add_child(ctrl_margin)

# ══════════════════════════════════════════
#  核心：加载视频流
# ══════════════════════════════════════════

func _load_video_stream(file_path: String) -> VideoStream:
	var ext: String = "." + file_path.get_extension().to_lower()

	if ext in NATIVE_VIDEO_EXT:
		var stream := VideoStreamTheora.new()
		stream.file = _temp_file_path
		return stream

	if ext in FFMPEG_VIDEO_EXT:
		if not is_ffmpeg_available():
			push_error("[VideoPlayer] 需要 ffmpeg-gdextension 才能播放 " + ext + " 格式")
			return null
		var stream = ClassDB.instantiate(_ffmpeg_class_name)
		if stream == null:
			push_error("[VideoPlayer] 无法创建 " + _ffmpeg_class_name + " 实例")
			return null
		stream.file = _temp_file_path
		return stream

	push_error("[VideoPlayer] 不支持的视频格式: " + ext)
	return null

# ══════════════════════════════════════════
#  打开视频播放器
# ══════════════════════════════════════════

func open_with_file(file_path: String, file_name: String, data: PackedByteArray) -> void:
	_ensure_overlay()
	_update_colors()

	# ★ 修复：如果打开的是不同文件，重置已知时长
	var is_same_file: bool = (_file_path == file_path and not _file_path.is_empty())
	if not is_same_file:
		_known_length = 0.0

	_file_path = file_path
	_file_name = file_name
	_is_paused = false
	_video_ended = false
	_update_timer = 0.0
	_max_seen_position = 0.0

	# 写入临时文件
	var temp_dir: String = "user://temp_video/"
	if not DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.make_dir_recursive_absolute(temp_dir)

	# ★ 修复：文件名可能包含特殊字符，使用安全文件名
	var safe_name: String = file_name.validate_filename()
	if safe_name.is_empty():
		safe_name = "temp_video." + file_name.get_extension()
	_temp_file_path = temp_dir + safe_name

	var file := FileAccess.open(_temp_file_path, FileAccess.WRITE)
	if file == null:
		push_error("[VideoPlayer] 无法创建临时文件: " + _temp_file_path)
		main.append_output("[color=" + T.error_hex + "][ERROR] 无法创建临时视频文件。[/color]\n", false)
		return
	file.store_buffer(data)
	file.close()

	# 加载视频流
	var stream: VideoStream = _load_video_stream(file_path)
	if stream == null:
		var ext: String = "." + file_path.get_extension().to_lower()
		var hint: String = ""
		if ext in FFMPEG_VIDEO_EXT:
			hint = "\n[color=" + T.warning_hex + "]提示: 播放 " + ext + " 格式需要安装 ffmpeg-gdextension 插件。[/color]"
			hint += "\n[color=" + T.muted_hex + "]下载: https://github.com/EIRTeam/EIRTeam.FFmpeg[/color]"
		else:
			hint = "\n[color=" + T.muted_hex + "]Godot 4.x 原生仅支持 .ogv (Ogg Theora) 格式。[/color]"
		main.append_output("[color=" + T.error_hex + "][ERROR] 不支持的视频格式或缺少解码插件。[/color]" + hint + "\n", false)
		_cleanup_temp_file()
		return

	video_player.stream = stream
	video_player.play()
	is_active = true

	# ★ 隐藏终端元素（包括状态栏）
	main.output_text.visible = false
	main.scroll_container.visible = false
	main.input_field.visible = false
	main.prompt_label.visible = false
	if main.status_frame:
		main.status_frame.visible = false
	if main.input_frame:
		main.input_frame.visible = false

	# ★ 隐藏 COMM 按钮（避免遮挡）
	if main.comm_mgr and main.comm_mgr._ui and main.comm_mgr._ui._toggle_btn:
		main.comm_mgr._ui._toggle_btn.visible = false

	overlay.visible = true

	_update_info_display()
	_update_controls_display()

# ══════════════════════════════════════════
#  关闭
# ══════════════════════════════════════════

func close() -> void:
	if not is_active:
		return

	is_active = false

	# ★ 修复：先保存文件名，在回调之后再清空
	var closed_file_name: String = _file_name
	var closed_file_path: String = _file_path

	if video_player and is_instance_valid(video_player):
		video_player.stop()
		video_player.stream = null

	if overlay and is_instance_valid(overlay):
		overlay.visible = false

	_cleanup_temp_file()

	# ★ 恢复终端元素
	main.output_text.visible = true
	main.scroll_container.visible = true
	main.input_field.visible = true
	main.prompt_label.visible = true
	if main.status_frame:
		main.status_frame.visible = true
	if main.input_frame:
		main.input_frame.visible = true

	# ★ 恢复 COMM 按钮
	if main.comm_mgr and main.comm_mgr._ui and main.comm_mgr._ui._toggle_btn:
		main.comm_mgr._ui._toggle_btn.visible = true

	main._update_status_bar()
	main.input_field.grab_focus()

	# ★ 修复：回调在文件名清空之前执行
	if main.has_method("_on_video_player_closed"):
		main._on_video_player_closed()

	# ★ 最后才清空文件信息
	_file_name = ""
	_file_path = ""

func _cleanup_temp_file() -> void:
	if not _temp_file_path.is_empty() and FileAccess.file_exists(_temp_file_path):
		DirAccess.remove_absolute(_temp_file_path)
	_temp_file_path = ""

func _on_video_finished() -> void:
	_video_ended = true
	_is_paused = true

	# ★ 播完了！现在可以确定总时长了
	if video_player and is_instance_valid(video_player):
		var final_pos: float = video_player.stream_position
		if final_pos > 0.1:
			_known_length = final_pos
			print("[VideoPlayer] 视频播放完毕，确认总时长: ", _format_time(_known_length))
		elif _max_seen_position > 0.1:
			_known_length = _max_seen_position
			print("[VideoPlayer] 视频播放完毕，使用最大位置作为时长: ", _format_time(_known_length))

	_update_controls_display()
	_update_info_display()
	_update_progress_bar()

# ══════════════════════════════════════════
#  键盘输入
# ══════════════════════════════════════════

func handle_input(event: InputEvent) -> bool:
	if not is_active:
		return false

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE, KEY_Q:
				close()
				return true
			KEY_SPACE:
				_toggle_pause()
				return true
			KEY_LEFT:
				_seek_relative(-SEEK_STEP)
				return true
			KEY_RIGHT:
				_seek_relative(SEEK_STEP)
				return true
			KEY_UP:
				_adjust_volume(VOLUME_STEP)
				return true
			KEY_DOWN:
				_adjust_volume(-VOLUME_STEP)
				return true
			KEY_HOME:
				_seek_to(0.0)
				return true
			KEY_R:
				_restart()
				return true
	return false

# ══════════════════════════════════════════
#  播放控制
# ══════════════════════════════════════════

func _toggle_pause() -> void:
	if video_player == null or not is_instance_valid(video_player):
		return

	if _video_ended:
		_restart()
		return

	_is_paused = not _is_paused
	video_player.paused = _is_paused
	_update_controls_display()
	_update_info_display()

func _restart() -> void:
	if video_player == null or not is_instance_valid(video_player):
		return

	_video_ended = false
	_is_paused = false
	# ★ 注意：不重置 _max_seen_position，保留历史最大位置用于时长估算
	# 但如果 _known_length 已确定，_max_seen_position 只是辅助信息
	_max_seen_position = 0.0
	video_player.paused = false
	video_player.stream_position = 0.0
	if not video_player.is_playing():
		video_player.play()
	_update_controls_display()
	_update_info_display()

func _seek_relative(seconds: float) -> void:
	if video_player == null or not is_instance_valid(video_player):
		return

	var current: float = video_player.stream_position
	var target: float = current + seconds

	# ★ 不能后退到负数
	if target < 0.0:
		target = 0.0

	# ★ 如果已知时长，不超过时长；否则不设上限，让播放器自己处理
	if _known_length > 0.1 and target > _known_length:
		target = _known_length

	# ★ 强制设置位置
	video_player.stream_position = target

	# 如果视频已结束但用户按了后退，恢复播放
	if _video_ended and seconds < 0:
		_video_ended = false
		_is_paused = false
		video_player.paused = false
		if not video_player.is_playing():
			video_player.play()

	_update_info_display()
	_update_progress_bar()

func _seek_to(position: float) -> void:
	if video_player == null or not is_instance_valid(video_player):
		return

	if position < 0.0:
		position = 0.0
	if _known_length > 0.1 and position > _known_length:
		position = _known_length

	video_player.stream_position = position

	if _video_ended:
		_video_ended = false
		_is_paused = false
		video_player.paused = false
		if not video_player.is_playing():
			video_player.play()

	_update_info_display()
	_update_progress_bar()

func _adjust_volume(delta: float) -> void:
	if video_player == null or not is_instance_valid(video_player):
		return

	var current_linear: float = db_to_linear(video_player.volume_db)
	current_linear = clampf(current_linear + delta, 0.0, 1.5)
	video_player.volume_db = linear_to_db(maxf(current_linear, 0.001))
	_update_controls_display()
	_update_info_display()

# ══════════════════════════════════════════
#  每帧更新
# ══════════════════════════════════════════

func process_frame(delta: float) -> void:
	if not is_active:
		return

	if video_player and is_instance_valid(video_player):
		var pos: float = video_player.stream_position
		if pos > _max_seen_position:
			_max_seen_position = pos

	_update_timer += delta
	if _update_timer < 0.2:
		return
	_update_timer = 0.0

	_update_info_display()
	_update_progress_bar()

# ══════════════════════════════════════════
#  UI 更新
# ══════════════════════════════════════════

func _update_colors() -> void:
	T = ThemeManager.current

	# ★ 修复：同步更新进度条填充色
	if progress_bar_fill and is_instance_valid(progress_bar_fill) and T:
		var fill_style := StyleBoxFlat.new()
		fill_style.bg_color = T.primary
		fill_style.corner_radius_top_left = 2
		fill_style.corner_radius_top_right = 2
		fill_style.corner_radius_bottom_left = 2
		fill_style.corner_radius_bottom_right = 2
		progress_bar_fill.add_theme_stylebox_override("panel", fill_style)

func _update_info_display() -> void:
	if info_label == null or not is_instance_valid(info_label):
		return

	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var w: String = T.warning_hex
	var s: String = T.success_hex

	var current_pos: float = 0.0
	if video_player and is_instance_valid(video_player):
		current_pos = video_player.stream_position

	var cur_str: String = _format_time(current_pos)

	# ★ 时长显示逻辑
	var len_str: String
	if _known_length > 0.1:
		len_str = _format_time(_known_length)
	else:
		len_str = "--:--"

	var status_icon: String
	if _video_ended:
		status_icon = "■"
	elif _is_paused:
		status_icon = "||"
	else:
		status_icon = "▶"

	var volume_pct: int = 100
	if video_player and is_instance_valid(video_player):
		volume_pct = int(db_to_linear(video_player.volume_db) * 100)

	var format_tag: String = _file_name.get_extension().to_upper()

	info_label.text = ""
	info_label.append_text(
		"[color=" + s + "]" + status_icon + "[/color]" +
		" [color=" + w + "]" + _file_name + "[/color]" +
		" [color=" + m + "][" + format_tag + "][/color]" +
		"  [color=" + p + "]" + cur_str + " / " + len_str + "[/color]" +
		"  [color=" + m + "]VOL:" + str(volume_pct) + "%[/color]"
	)

func _update_controls_display() -> void:
	if controls_label == null or not is_instance_valid(controls_label):
		return

	var p: String = T.primary_hex
	var m: String = T.muted_hex

	var pause_text: String
	if _video_ended:
		pause_text = "重播"
	elif _is_paused:
		pause_text = "播放"
	else:
		pause_text = "暂停"

	controls_label.text = ""
	controls_label.append_text(
		"[color=" + m + "]Space[/color][color=" + p + "] " + pause_text + "[/color]" +
		"  [color=" + m + "]←→[/color][color=" + p + "] ±" + str(int(SEEK_STEP)) + "s[/color]" +
		"  [color=" + m + "]↑↓[/color][color=" + p + "] 音量[/color]" +
		"  [color=" + m + "]R[/color][color=" + p + "] 重播[/color]" +
		"  [color=" + m + "]Home[/color][color=" + p + "] 回到开头[/color]" +
		"  [color=" + m + "]Q/Esc[/color][color=" + p + "] 退出[/color]"
	)

func _update_progress_bar() -> void:
	if progress_bar_bg == null or not is_instance_valid(progress_bar_bg):
		return
	if progress_bar_fill == null or not is_instance_valid(progress_bar_fill):
		return

	var bar_width: float = progress_bar_bg.size.x
	if bar_width <= 0:
		return

	var current_pos: float = 0.0
	if video_player and is_instance_valid(video_player):
		current_pos = video_player.stream_position

	# 固定 anchor 设置
	progress_bar_fill.anchor_left = 0.0
	progress_bar_fill.anchor_top = 0.0
	progress_bar_fill.anchor_bottom = 1.0
	progress_bar_fill.anchor_right = 0.0
	progress_bar_fill.offset_top = 0
	progress_bar_fill.offset_bottom = 0

	if _video_ended:
		# ★ 播放结束：填满进度条
		progress_bar_fill.offset_left = 0
		progress_bar_fill.offset_right = bar_width
	elif _known_length > 0.1:
		# ★ 已知时长（第二次播放或之后）：显示真实进度
		var progress: float = clampf(current_pos / _known_length, 0.0, 1.0)
		progress_bar_fill.offset_left = 0
		progress_bar_fill.offset_right = bar_width * progress
	else:
		# ★ 未知时长（第一次播放）：来回跳动的指示器
		if _is_paused:
			progress_bar_fill.offset_left = 0
			progress_bar_fill.offset_right = 0
		else:
			var indicator_width: float = maxf(bar_width * 0.08, 6.0)
			# ★ 修复：用 sin 函数做平滑来回运动（原代码乘号被损坏）
			var cycle: float = sin(current_pos * 0.5) * 0.5 + 0.5
			var x_pos: float = (bar_width - indicator_width) * cycle
			progress_bar_fill.offset_left = x_pos
			progress_bar_fill.offset_right = x_pos + indicator_width

# ══════════════════════════════════════════
#  工具方法
# ══════════════════════════════════════════

func _format_time(seconds: float) -> String:
	if seconds <= 0:
		return "00:00"
	var total_sec: int = int(seconds)
	@warning_ignore("integer_division")
	var hrs: int = total_sec / 3600
	@warning_ignore("integer_division")
	var mins: int = (total_sec % 3600) / 60
	var secs: int = total_sec % 60
	if hrs > 0:
		return "%d:%02d:%02d" % [hrs, mins, secs]
	return "%02d:%02d" % [mins, secs]

# ============================================================
# ★ 公共状态查询方法（供 main.gd 内联视频系统调用）
# ============================================================

## 获取当前播放位置（秒）
func get_playback_position() -> float:
	if video_player != null and is_instance_valid(video_player):
		return video_player.stream_position
	return 0.0

## 获取视频总时长（秒）
## 注意：Godot 的 VideoStreamTheora 不提供预先获取时长的API，
## 所以第一次播放时返回 0，播完后才能确认准确时长。
func get_video_length() -> float:
	return _known_length

## 获取当前最大已播放位置（用于时长估算）
func get_max_seen_position() -> float:
	return _max_seen_position

## 检查是否暂停
func is_paused() -> bool:
	return _is_paused

## 检查视频是否已播放结束
func is_ended() -> bool:
	return _video_ended

## 获取当前播放的文件名
func get_file_name() -> String:
	return _file_name

## 获取当前播放的文件路径
func get_file_path() -> String:
	return _file_path

## 获取当前音量百分比
func get_volume_percent() -> int:
	if video_player != null and is_instance_valid(video_player):
		return int(db_to_linear(video_player.volume_db) * 100)
	return 100
