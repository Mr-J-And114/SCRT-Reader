extends Control
## 同一字符栅格中的云、水面、贴墙水体抬升与脱离水面的小水花。
## 云限于顶部 2/5；水花与水体共用字号、格距和一次绘制，不另画喷泉层。

const DESIGN_SIZE := Vector2(1920, 1080)
const SAMPLE_RATE := 22050
const FONT := preload("res://fonts/SarasaMonoSC-Regular.ttf")
const CoverMorse := preload("res://preview/cover_morse.gd")
const IMPACT_PHASE := 0.62
const GRAVITY := 260.0
# 三种不同外形：团状积云、扁长层云、带高耸云头的不对称碎云。
const CLOUD_FORMS := [
	[Vector4(6, 4.9, 5, 2.5), Vector4(13, 3.2, 7.4, 3.1), Vector4(21, 4.2, 5.4, 2.8), Vector4(26, 5.2, 3.4, 1.8)],
	[Vector4(5, 5.5, 5, 1.3), Vector4(14, 5, 10, 2), Vector4(24, 5.4, 6, 1.45), Vector4(17, 3.5, 4, 1.6)],
	[Vector4(4, 5.6, 3.6, 1.8), Vector4(10, 4.6, 5.7, 2.7), Vector4(16, 2.6, 4.6, 2.5), Vector4(20, 4, 3.3, 2.4), Vector4(25, 5.2, 4.4, 1.7)]
]

class WaterDrop:
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var age: float = 0.0
	var glyph: String = "*"

class SurfaceRipple:
	var x: float = 0.0
	var age: float = 0.0

var _config: Dictionary = {}
var _time: float = 0.0
var _wait: float = 1.0
var _wave_age: float = -1.0
var _wave_direction: float = 1.0
var _active: bool = true
var _random := RandomNumberGenerator.new()
var _sound: AudioStreamPlayer
var _morse: Node
var _surf_level: float = 0.0
var _drops: Array[WaterDrop] = []
var _ripples: Array[SurfaceRipple] = []
var _impact_age: float = -1.0
var _has_impacted: bool = false
var _has_detached: bool = false
var _draw_age: float = 0.0
var _glyph_size: int = 28
var _grid_step := Vector2(16.0, 22.96)

func _ready() -> void:
	size = DESIGN_SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_random.randomize()
	_sound = AudioStreamPlayer.new()
	_sound.bus = "Master"
	_sound.stream = _make_surf_noise()
	add_child(_sound)
	_morse = CoverMorse.new()
	add_child(_morse)
	set_process(false)

func configure(layout: Dictionary, _theme_color: Color) -> void:
	_config = layout.duplicate()
	_glyph_size = maxi(10, roundi(_value("atmosphere_char_size", 28.0)))
	_grid_step = Vector2(FONT.get_string_size("#", HORIZONTAL_ALIGNMENT_LEFT, -1, _glyph_size).x + 2.0, float(_glyph_size) * 0.82)
	_morse.configure(_config)
	if bool(_config.get("atmosphere_motion_off", false)):
		_wave_age = -1.0
		_impact_age = -1.0
		_surf_level = 0.0
		_drops.clear()
		_ripples.clear()
	_update_sound()
	queue_redraw()

func set_active(active: bool) -> void:
	_active = active
	_morse.set_active(active)
	if not active:
		_wave_age = -1.0
		_wait = 1.0
		_impact_age = -1.0
		_drops.clear()
		_ripples.clear()
		_surf_level = 0.0
		_sound.stop()
	queue_redraw()

func trigger_wave(direction: float = 0.0) -> void:
	if not _active or bool(_config.get("atmosphere_motion_off", false)):
		return
	_wave_direction = signf(direction) if direction != 0.0 else -_wave_direction
	_wave_age = 0.0
	_has_impacted = false
	_has_detached = false
	_impact_age = -1.0
	_drops.clear()
	_ripples.clear()
	_update_sound()
	queue_redraw()

func advance(delta: float) -> void:
	if not _active or _config.is_empty():
		return
	_time += delta
	_morse.advance()
	if bool(_config.get("atmosphere_motion_off", false)):
		_time -= delta
		return
	for index in range(_ripples.size() - 1, -1, -1):
		_ripples[index].age += delta
		if _ripples[index].age >= 2.0:
			_ripples.remove_at(index)
	if _impact_age >= 0.0:
		_impact_age += delta
		if _impact_age > 3.0:
			_impact_age = -1.0
	if _wave_age >= 0.0:
		_wave_age += delta
		if not _has_impacted and _wave_progress() >= IMPACT_PHASE:
			_has_impacted = true
			_impact_age = 0.0
		if _has_impacted and not _has_detached and _wall_progress() >= 0.5:
			_has_detached = true
			_detach_surface_cells()
		if _wave_age >= _duration():
			_wave_age = -1.0
			_wait = _value("wave_interval", 15.0) * _random.randf_range(0.8, 1.2)
	else:
		_wait -= delta
		if _wait <= 0.0:
			trigger_wave()
	for index in range(_drops.size() - 1, -1, -1):
		var drop: WaterDrop = _drops[index]
		drop.age += delta
		# 脱离的浪尖保存峰值时的字符位置，之后只受速度／重力驱动。
		drop.position += drop.velocity * delta + Vector2(0.0, 0.5 * GRAVITY * delta * delta)
		drop.velocity.y += GRAVITY * delta
		drop.velocity.x *= exp(-0.22 * delta)
		# 回到当前水面即重新融入水体，不在空中凭空淡掉。
		if drop.velocity.y > 0.0 and drop.position.y >= _surface_y(drop.position.x):
			_add_landing_ripple(drop.position.x)
			_drops.remove_at(index)
		elif drop.age > 4.0:
			_drops.remove_at(index)
	_update_sound(delta)
	_draw_age += delta
	if _draw_age >= 1.0 / 24.0:
		_draw_age = fmod(_draw_age, 1.0 / 24.0)
		queue_redraw()

func _value(key: String, fallback: float) -> float:
	return float(_config.get(key, fallback))

func _font_size() -> int:
	return _glyph_size

func _cell_size() -> Vector2:
	return _grid_step

func _duration() -> float:
	return maxf(0.5, _value("wave_duration", 3.8))

func _wave_progress() -> float:
	return clampf(_wave_age / _duration(), 0.0, 1.0)

func _wall_progress() -> float:
	return clampf((_wave_progress() - IMPACT_PHASE) / (1.0 - IMPACT_PHASE), 0.0, 1.0)

func _wall_strength() -> float:
	if _wave_age < 0.0 or not _has_impacted:
		return 0.0
	return pow(maxf(0.0, sin(PI * _wall_progress())), 0.8)

func _baseline() -> float:
	return DESIGN_SIZE.y - _value("wave_bottom", 80.0)

func _surface_y(x: float) -> float:
	var amplitude: float = maxf(0.0, _value("wave_amplitude", 54.0))
	var wavelength: float = maxf(8.0, _value("wave_wavelength", 150.0))
	var progress: float = _wave_progress()
	var cell: Vector2 = _cell_size()
	# 浪头从屏幕外进入；到边缘后留在墙边抬升并退去，不向内画第二个浪头。
	var crest_x: float = lerpf(-240.0, DESIGN_SIZE.x - cell.x * 0.5, minf(1.0, progress / IMPACT_PHASE))
	if _wave_direction < 0.0:
		crest_x = DESIGN_SIZE.x - crest_x
	var distance: float = (x - crest_x) / 145.0
	var strength: float = (1.0 - _wall_progress()) * smoothstep(0.0, 0.06, progress) if _wave_age >= 0.0 else 0.0
	var packet: float = exp(-distance * distance * 0.5) * strength
	var phase: float = TAU * x / wavelength - _time * _wave_direction * 6.0
	var moving_height: float = amplitude * packet * (0.75 + 0.25 * sin(phase))
	var edge_distance: float = DESIGN_SIZE.x - x if _wave_direction > 0.0 else x
	# 四分之一椭圆的凹弧连接水面与墙边；上方回卷用同一字符栅格补齐。
	var height: float = maxf(0.0, _value("wave_wall_height", 240.0)) * _wall_strength()
	var width: float = maxf(cell.x * 6.0, height * 0.95)
	var u: float = clampf(1.0 - maxf(0.0, edge_distance - cell.x * 0.5) / width, 0.0, 1.0)
	var wall_height: float = height * 0.72 * (1.0 - sqrt(maxf(0.0, 1.0 - u * u)))
	var ripple_height: float = 0.0
	for ripple in _ripples:
		var ripple_distance: float = (absf(x - ripple.x) - ripple.age * 150.0) / 34.0
		ripple_height += 8.0 * exp(-ripple.age * 2.5 - ripple_distance * ripple_distance * 0.5)
	return _baseline() - maxf(moving_height, wall_height) - amplitude * sin(phase * 0.4) * 0.04 - ripple_height

func _curl_points(strength_override: float = -1.0, complete: bool = false, start_angle: float = 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	var strength: float = _wall_strength() if strength_override < 0.0 else strength_override
	var height: float = maxf(0.0, _value("wave_wall_height", 240.0)) * strength
	if height < _cell_size().y * 0.5:
		return points
	var radius := Vector2(height * 0.32, height * 0.28)
	var center_y: float = _baseline() - height + radius.y
	# 从墙边向内拱起，再绕过最高点向下、向墙边回卷，形成真正的悬垂浪尖。
	var maturity: float = smoothstep(0.0, 0.35, _wall_progress())
	var end_angle: float = lerpf(PI * 0.5, PI * 1.25, maturity)
	# 峰值后仅保留仍与墙边相连的根部；回卷段已转为独立落下的水体。
	if _has_detached and not complete:
		end_angle = minf(end_angle, PI * 0.35)
	var samples: int = maxi(12, ceili(height * end_angle / (minf(_grid_step.x, _grid_step.y) * 0.4)))
	for index in range(samples + 1):
		var angle: float = lerpf(start_angle, end_angle, float(index) / float(samples))
		var distance: float = radius.x * (1.0 - cos(angle)) + _grid_step.x * 0.5
		var x: float = DESIGN_SIZE.x - distance if _wave_direction > 0.0 else distance
		points.append(Vector2(x, center_y - radius.y * sin(angle)))
	return points

func _curl_cells(points: PackedVector2Array, strength: float) -> Dictionary:
	var cells: Dictionary = {}
	var cell: Vector2 = _cell_size()
	var radius: float = maxf(cell.y * 0.7, _value("wave_wall_height", 240.0) * strength * 0.065)
	var columns: int = ceili(DESIGN_SIZE.x / cell.x)
	var last_row: int = floori((DESIGN_SIZE.y - 8.0) / cell.y)
	for point in points:
		for column in range(floori((point.x - radius) / cell.x), ceili((point.x + radius) / cell.x)):
			if column < 0 or column >= columns:
				continue
			for row in range(maxi(0, floori((point.y - radius) / cell.y)), mini(last_row + 1, ceili((point.y + radius) / cell.y))):
				var center := Vector2((float(column) + 0.5) * cell.x, (float(row) + 0.5) * cell.y)
				if center.distance_squared_to(point) <= radius * radius:
					cells[Vector2i(column, row)] = true
	return cells

func _add_landing_ripple(x: float) -> void:
	for ripple in _ripples:
		if ripple.age < 0.25 and absf(ripple.x - x) < 100.0:
			return
	if _ripples.size() < 8:
		var ripple := SurfaceRipple.new()
		ripple.x = x
		_ripples.append(ripple)

func _water_tint(blue: Color) -> Color:
	# 50% 保留原蓝色的一半饱和度，维持亮度；白色浪尖不经过此转换。
	var luminance: float = blue.r * 0.2126 + blue.g * 0.7152 + blue.b * 0.0722
	return Color(luminance, luminance, luminance).lerp(blue, clampf(_value("wave_blue_strength", 50.0) / 100.0, 0.0, 1.0))

func _update_sound(delta: float = 0.0) -> void:
	if _sound == null:
		return
	var volume: float = clampf(_value("wave_volume", 12.0) / 100.0, 0.0, 1.0)
	volume *= clampf(_value("audio_ambient_gain", 1.0), 0.0, 1.0)
	if not _active or volume <= 0.0:
		_surf_level = 0.0
		_sound.stop()
		return
	var envelope: float = pow(maxf(0.0, sin(PI * _wave_progress())), 1.2) * 0.5 if _wave_age >= 0.0 else 0.0
	if _impact_age >= 0.0:
		envelope = maxf(envelope, _wall_strength() * 0.9 + exp(-_impact_age * 2.2) * 0.25)
	# 声音单独释放，不随浪形结束／计时器到期突然停掉；默认约 4 秒降至 1%。
	if delta > 0.0:
		var fade: float = maxf(0.25, _value("wave_sound_fade", 4.0))
		var tau: float = 0.08 if envelope > _surf_level else fade / 4.6
		_surf_level = lerpf(_surf_level, envelope, 1.0 - exp(-delta / tau))
	if _surf_level < 0.0001 and envelope <= 0.0001:
		_sound.stop()
		return
	_sound.volume_db = linear_to_db(maxf(0.000001, volume * _surf_level))
	if not _sound.playing:
		_sound.play()

func _draw() -> void:
	if not _active or _config.is_empty():
		return
	_draw_clouds()
	_draw_water_grid()

func _draw_clouds() -> void:
	var count: int = clampi(int(_value("cloud_count", 3.0)), 0, 3)
	var font_size: int = _font_size()
	var ascent: float = FONT.get_ascent(font_size)
	var descent: float = FONT.get_descent(font_size)
	var cell: Vector2 = _cell_size()
	var band_height: float = DESIGN_SIZE.y * 0.4
	var cloud_scale: float = minf(maxf(0.05, _value("cloud_scale", 1.35)), maxf(0.05, (band_height - cell.y) / (8.0 * cell.y)))
	var rows: int = maxi(1, ceili(8.0 * cloud_scale))
	var columns: int = maxi(1, ceili(30.0 * cloud_scale))
	var height: float = float(rows + 1) * cell.y
	var speed: float = maxf(0.0, _value("cloud_speed", 8.0))
	var alpha: float = clampf(_value("cloud_opacity", 36.0) / 100.0, 0.0, 1.0)
	if alpha <= 0.0:
		return
	for index in range(count):
		var width: float = float(columns) * cell.x
		var span: float = DESIGN_SIZE.x + width
		var x: float = fposmod(450.0 + float(index) * span / maxf(1.0, float(count)) + _time * speed * (1.0 - float(index) * 0.07), span) - width
		var offsets: Array[float] = [0.0, 110.0, 55.0]
		var top: float = clampf(_value("cloud_top", 24.0) + offsets[index] + sin(_time * 0.08 + float(index)) * 6.0, 0.0, maxf(0.0, band_height - height))
		for row in range(rows):
			for column in range(columns):
				var nx: float = float(column) / cloud_scale
				var ny: float = float(row) / cloud_scale
				var distance: float = 99.0
				for puff in CLOUD_FORMS[index]:
					var dx: float = (nx - puff.x) / puff.z
					var dy: float = (ny - puff.y) / puff.w
					distance = minf(distance, dx * dx + dy * dy)
				if distance > 1.0:
					continue
				var y: float = top + float(row + 1) * cell.y
				if y - ascent < 0.0 or y + descent > band_height:
					continue
				var shade: int = (column * 17 + row * 11 + index * 7) % 10
				var glyph: String = "#" if distance < 0.55 and shade < 6 else ("*" if distance < 0.8 else ".")
				var tint: Color = Color(0.98, 0.99, 1.0).lerp(Color(0.7, 0.79, 0.88), ny / 12.0)
				var opacity: float = alpha * (0.3 + 0.7 * (1.0 - distance)) * (1.0 - ny * 0.06)
				draw_char(FONT, Vector2(x + float(column) * cell.x, y), glyph, font_size, Color(tint, opacity))

func _detach_surface_cells() -> void:
	var density: float = clampf(_value("wave_splash_density", 1.0), 0.0, 3.0)
	# 把整个悬垂浪尖移交给弹道水体，移除原轮廓；不是只额外生成几颗水花。
	var crest: PackedVector2Array = _curl_points(1.0, true, PI * 0.35)
	if crest.is_empty():
		return
	var cell: Vector2 = _cell_size()
	for key: Vector2i in _curl_cells(crest, 1.0):
		var piece := WaterDrop.new()
		piece.position = Vector2((float(key.x) + 0.5) * cell.x, (float(key.y) + 0.5) * cell.y)
		var inward: float = DESIGN_SIZE.x - piece.position.x if _wave_direction > 0.0 else piece.position.x
		var leading: float = clampf(inward / maxf(1.0, _value("wave_wall_height", 240.0) * 0.64), 0.0, 1.0)
		piece.velocity = Vector2(-_wave_direction * lerpf(28.0, 90.0, leading), lerpf(15.0, 65.0, leading))
		piece.glyph = "*" if (key.x + key.y) % 3 != 0 else "#"
		_drops.append(piece)
	# 额外的细碎水花可调数量；浪尖本身的坠落不受密度开关影响。
	for index in range(int(8.0 * density)):
		var drop := WaterDrop.new()
		var along_crest: float = _random.randf_range(0.4, 0.92)
		drop.position = crest[mini(crest.size() - 1, roundi(along_crest * float(crest.size() - 1)))]
		drop.velocity = Vector2(-_wave_direction * _random.randf_range(35.0, 85.0), -_random.randf_range(35.0, 75.0))
		drop.glyph = "*" if index % 3 != 0 else "#"
		_drops.append(drop)

func _draw_water_grid() -> void:
	var alpha: float = clampf(_value("wave_opacity", 65.0) / 100.0, 0.0, 1.0)
	if alpha <= 0.0:
		return
	var font_size: int = _font_size()
	var cell: Vector2 = _cell_size()
	var columns: int = ceili(DESIGN_SIZE.x / cell.x)
	var body_tint: Color = _water_tint(Color(0.28, 0.56, 0.94))
	var surface_tint: Color = _water_tint(Color(0.38, 0.7, 1.0))
	var last_row: int = floori((DESIGN_SIZE.y - 8.0) / cell.y)
	var detached: Dictionary = {}
	var curl: Dictionary = _curl_cells(_curl_points(), _wall_strength())
	var air_first_rows: Dictionary = {}
	for key: Vector2i in curl:
		air_first_rows[key.x] = mini(int(air_first_rows.get(key.x, key.y)), key.y)
	# 少量脱离水面的字符映射回同一栅格，不单独绘制喷射／泡沫柱。
	for drop in _drops:
		var column: int = floori(drop.position.x / cell.x)
		var row: int = floori(drop.position.y / cell.y)
		if column < 0 or column >= columns or row < 0 or row > last_row:
			continue
		detached[Vector2i(column, row)] = drop.glyph
		air_first_rows[column] = mini(int(air_first_rows.get(column, row)), row)
	for column in range(columns):
		var x: float = (float(column) + 0.5) * cell.x
		var surface: float = _surface_y(x)
		var lift: float = clampf((_baseline() - surface) / 60.0, 0.0, 1.0)
		var first_water: int = maxi(0, floori(surface / cell.y))
		var first: int = mini(first_water, int(air_first_rows.get(column, first_water)))
		for row in range(first, last_row + 1):
			var key := Vector2i(column, row)
			var depth: int = row - first_water
			var glyph: String
			var tint: Color
			var opacity: float
			if curl.has(key):
				glyph = "*" if (column + row) % 3 != 0 else "#"
				tint = Color(0.94, 0.98, 1.0)
				opacity = alpha * 0.85
			elif depth < 0:
				if not detached.has(key):
					continue
				glyph = str(detached[key])
				tint = Color(0.92, 0.97, 1.0)
				opacity = alpha * 0.85
			else:
				var pattern: int = (column * 13 + row * 7) % 11
				if depth > 2 and pattern < 3:
					continue
				glyph = ("*" if lift > 0.4 else "~") if depth == 0 else ("#" if depth < 3 else (":" if pattern < 8 else "."))
				tint = body_tint
				if depth < 2:
					tint = surface_tint.lerp(Color(0.94, 0.98, 1.0), lift)
				opacity = alpha * (0.42 + lift * 0.38) / (1.0 + float(depth) * 0.13)
			draw_char(FONT, Vector2(float(column) * cell.x, float(row + 1) * cell.y), glyph, font_size, Color(tint, opacity))

func _make_surf_noise() -> AudioStreamWAV:
	# 可重复、无外部素材的双声道带色噪声；动画控制浪声包络。
	var noise := RandomNumberGenerator.new()
	noise.seed = 4107
	var frames: int = SAMPLE_RATE * 3
	var data := PackedByteArray()
	data.resize(frames * 4)
	var slow := Vector2.ZERO
	var fast := Vector2.ZERO
	for index in range(frames):
		var white := Vector2(noise.randf_range(-1.0, 1.0), noise.randf_range(-1.0, 1.0))
		slow = slow.lerp(white, 0.025)
		fast = fast.lerp(white, 0.28)
		var sample: Vector2 = (fast - slow) * 0.8 + slow * 0.3
		# 循环两端短淡化，避免接缝爆音。
		var fade: float = minf(1.0, float(mini(index, frames - 1 - index)) / 220.0)
		data.encode_s16(index * 4, int(clampf(sample.x * fade, -1.0, 1.0) * 32767.0))
		data.encode_s16(index * 4 + 2, int(clampf(sample.y * fade, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = true
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	return stream
