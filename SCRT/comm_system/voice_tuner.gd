class_name VoiceTuner
extends RefCounted
## 编辑器调音面板。修改立即作用于角色，试听使用独立播放通道。
var CHARACTER_IDS: Array[String] = []
const TONES: Array[String] = ["warm", "clear", "sharp", "chime", "sine", "square", "saw", "noise"]
var _main: Control
var _manager
var _root: Control
var _preview_voice: CommVoice
var _character_select: OptionButton
var _tone_select: OptionButton
var _text_input: LineEdit
var _loop: CheckBox
var _status: Label
var _sliders: Dictionary = {}
var _spins: Dictionary = {}
var _saved: Dictionary = {}
var _selected_id: String = ""
var _preview_token: int = 0

func open(main: Control, manager) -> void:
	_main = main
	_manager = manager
	CHARACTER_IDS.assign(manager.get_registry()._characters.keys())
	if CHARACTER_IDS.is_empty():
		return
	_selected_id = CHARACTER_IDS[0]
	if _root == null:
		_build()
	for cid in CHARACTER_IDS:
		var character: CommCharacter = _manager.get_registry().get_character(cid)
		if character:
			_saved[cid] = character.voice_config.duplicate(true)
	_root.show()
	_refresh()
	_text_input.grab_focus()

func is_open() -> bool:
	return _root != null and _root.visible

func close() -> void:
	_preview_token += 1
	if _preview_voice:
		_preview_voice.stop()
	if _root:
		_root.hide()
	if _main and _main.input_field:
		_main.input_field.grab_focus()

func _build() -> void:
	_preview_voice = CommVoice.new()
	_preview_voice.setup(_main)
	_root = Control.new()
	_root.name = "VoiceTuner"
	_root.z_index = 100
	_main.add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0, 0, 0, 0.90)
	_root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	_root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	var scroll := ScrollContainer.new()
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	var title := Label.new()
	title.text = "角色说话声 · 实时调音（Esc 关闭）"
	box.add_child(title)
	_character_select = OptionButton.new()
	for cid in CHARACTER_IDS:
		var character: CommCharacter = _manager.get_registry().get_character(cid)
		_character_select.add_item(character.display_name if character else cid)
	box.add_child(_character_select)
	_character_select.item_selected.connect(_select_character)
	_tone_select = OptionButton.new()
	for tone_label in ["柔和：正弦 + 三角", "清亮：正弦 + 二次谐波", "尖锐：锯齿谐波", "铃音：泛音组合", "纯正弦", "方波", "锯齿", "噪声"]:
		_tone_select.add_item(tone_label)
	box.add_child(_tone_select)
	_tone_select.item_selected.connect(_select_tone)
	var fields: Array = [
		["base_frequency_hz", "音高 / Hz", 140, 700, 1],
		["brightness", "明亮 / 尖锐度", 0, 1, 0.01],
		["pitch_variance", "音高波动", 0, 0.25, 0.005],
		["char_sound_duration", "单音时长 / ms", 25, 180, 1],
		["attack_ms", "起音柔和度 / ms", 1, 30, 1],
		["release_ms", "尾音长度 / ms", 2, 100, 1],
		["volume_db", "音量 / dB", -40, 0, 1],
		["punctuation_pause", "标点停顿 / ms", 0, 600, 10],
		["voice_every_n", "每几个字发声一次", 1, 4, 1],
	]
	for spec in fields:
		var key: String = str(spec[0])
		var row := HBoxContainer.new()
		box.add_child(row)
		var label := Label.new()
		label.text = str(spec[1])
		label.custom_minimum_size.x = 180
		row.add_child(label)
		var slider := HSlider.new()
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.min_value = float(spec[2])
		slider.max_value = float(spec[3])
		slider.step = float(spec[4])
		row.add_child(slider)
		var spin := SpinBox.new()
		spin.min_value = slider.min_value
		spin.max_value = slider.max_value
		spin.step = slider.step
		spin.custom_minimum_size.x = 110
		row.add_child(spin)
		_sliders[key] = slider
		_spins[key] = spin
		slider.value_changed.connect(_change_value.bind(key))
		spin.value_changed.connect(_change_value.bind(key))
	_text_input = LineEdit.new()
	_text_input.text = "你好，今天的工作准备好了吗？先听听我的声音。"
	box.add_child(_text_input)
	_loop = CheckBox.new()
	_loop.text = "循环试听（播放时拖动滑块，下一字立即使用新参数）"
	box.add_child(_loop)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_add_button(buttons, "试听", _preview)
	_add_button(buttons, "停止", _stop_preview)
	_add_button(buttons, "保存三人配置", _save)
	_add_button(buttons, "恢复当前角色", _reset)
	_add_button(buttons, "复制当前 JSON", _copy)
	_add_button(buttons, "关闭", close)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "变化立即生效；保存后写入 comm_system/voice_presets.json。恢复回到本次打开或最近保存的设置。"
	box.add_child(_status)

func _add_button(row: HBoxContainer, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	row.add_child(button)

func _select_character(index: int) -> void:
	_stop_preview()
	_selected_id = CHARACTER_IDS[index]
	_refresh()

func _refresh() -> void:
	var character: CommCharacter = _manager.get_registry().get_character(_selected_id)
	if character == null:
		return
	_preview_voice.apply_config(character.voice_config)
	var cfg: Dictionary = _preview_voice.config
	for key in _sliders:
		(_sliders[key] as HSlider).set_value_no_signal(float(cfg.get(key, 0)))
		(_spins[key] as SpinBox).set_value_no_signal(float(cfg.get(key, 0)))
	var tone_index: int = TONES.find(str(cfg.get("tone", "warm")))
	_tone_select.select(maxi(0, tone_index))

func _change_value(value: float, key: String) -> void:
	(_sliders[key] as HSlider).set_value_no_signal(value)
	(_spins[key] as SpinBox).set_value_no_signal(value)
	var character: CommCharacter = _manager.get_registry().get_character(_selected_id)
	character.voice_config[key] = int(value) if key in ["voice_every_n", "char_sound_duration", "punctuation_pause"] else value
	_apply(character)

func _select_tone(index: int) -> void:
	var character: CommCharacter = _manager.get_registry().get_character(_selected_id)
	character.voice_config["tone"] = TONES[index]
	_apply(character)

func _apply(character: CommCharacter) -> void:
	_preview_voice.apply_config(character.voice_config)
	_manager.refresh_character_voice(character.id)
	_status.text = "已即时更新 " + character.display_name + "；满意后点击保存。"

func _preview() -> void:
	_preview_token += 1
	var token: int = _preview_token
	_preview_voice.apply_config(_manager.get_registry().get_character(_selected_id).voice_config)
	while token == _preview_token and is_open():
		var text: String = _text_input.text
		if text.strip_edges().is_empty():
			return
		for index in range(text.length()):
			var ch: String = text[index]
			if token != _preview_token or not is_open():
				return
			_preview_voice.speak_char(ch)
			var delay: float = _preview_voice.get_char_delay() + _preview_voice.get_punctuation_pause(ch)
			await _main.get_tree().create_timer(delay).timeout
		if token != _preview_token or not is_open():
			return
		if not _loop.button_pressed:
			return
		await _main.get_tree().create_timer(0.7).timeout

func _stop_preview() -> void:
	_preview_token += 1
	_preview_voice.stop()

func _save() -> void:
	var error: Error = _manager.save_voice_presets()
	if error != OK:
		_status.text = "保存失败：" + error_string(error)
		return
	for cid in CHARACTER_IDS:
		_saved[cid] = _manager.get_registry().get_character(cid).voice_config.duplicate(true)
	_status.text = "已保存到 comm_system/voice_presets.json，下次启动及导出游戏会使用这些配置。"

func _reset() -> void:
	var character: CommCharacter = _manager.get_registry().get_character(_selected_id)
	character.voice_config = _saved[_selected_id].duplicate(true)
	_manager.refresh_character_voice(_selected_id)
	_refresh()
	_status.text = "已恢复当前角色；其他角色的调整保留。"

func _copy() -> void:
	var cfg: Dictionary = _manager.get_registry().get_character(_selected_id).voice_config
	DisplayServer.clipboard_set(JSON.stringify({_selected_id: cfg}, "\t"))
	_status.text = "已复制当前角色的音色 JSON。"

func cleanup() -> void:
	close()
	if _preview_voice:
		_preview_voice.cleanup()
	if _root:
		_root.queue_free()
	_root = null
