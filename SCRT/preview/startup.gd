extends "res://preview/cover_preview.gd"
## 正式封面入口；播片结束才创建 Main，让原游戏独占开机、登录及存档流程。

const MAIN_SCENE := "res://scenes/main.tscn"
var _handoff_in_progress: bool = false
var _error_panel: ColorRect
var _retry_button: Button

var _return_fading: bool = false

func _ready() -> void:
	var tree := get_tree()
	tree.auto_accept_quit = true
	_return_fading = bool(tree.get_meta("scrt_cover_fade_in", false))
	if tree.has_meta("scrt_cover_fade_in"):
		tree.remove_meta("scrt_cover_fade_in")
	var fade_layer: CanvasLayer
	var black: ColorRect
	if _return_fading:
		# 在公共封面初始化前遮黑，避免先闪出完整画面。
		fade_layer = CanvasLayer.new()
		fade_layer.layer = 200
		add_child(fade_layer)
		black = ColorRect.new()
		black.color = Color.BLACK
		black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		black.mouse_filter = Control.MOUSE_FILTER_STOP
		fade_layer.add_child(black)
	await super._ready()
	if _return_fading:
		_atmosphere.trigger_wave()
		var fade := create_tween()
		fade.tween_property(black, "color:a", 0.0, 1.0)
		await fade.finished
		fade_layer.queue_free()
		_return_fading = false
		_menu[0].grab_focus()

func _begin_boot() -> void:
	if not _starting or _handoff_in_progress:
		return
	_handoff_in_progress = true
	_intro.show_status("正在启动…")
	_cover.hide()
	# 先显示反馈，再加载主场景。
	await get_tree().process_frame
	var game: Control = _create_game()
	if game == null:
		_show_startup_error("无法加载主游戏场景：" + MAIN_SCENE)
		return
	# 黑幕留在原封面之上，遮住主游戏初始化以及两帧 deferred 节点准备。
	_intro.hold_black()
	_cover.hide()
	var tree: SceneTree = get_tree()
	tree.root.add_child(game)
	tree.current_scene = game
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame
	# Main._ready 已启动一次原有 BootSequence；不在封面另播一遍。
	var sequence: Variant = game.get("boot_sequence")
	if sequence == null or not sequence.is_active():
		tree.current_scene = self
		tree.root.remove_child(game)
		game.queue_free()
		_show_startup_error("主游戏开机流程未能初始化。")
		return
	_intro.cancel()
	queue_free()

func _create_game() -> Control:
	var scene: PackedScene = load(MAIN_SCENE) as PackedScene
	return scene.instantiate() as Control if scene != null else null

func _show_startup_error(reason: String) -> void:
	push_error("[Startup] " + reason)
	_handoff_in_progress = false
	_starting = false
	_intro.cancel()
	if _error_panel == null:
		_error_panel = ColorRect.new()
		_error_panel.color = Color.BLACK
		_error_panel.size = Vector2(1920, 1080)
		_canvas.add_child(_error_panel)
		var label: Label = _label("游戏未能启动，请重试或返回封面。", FONT)
		label.position = Vector2(260, 350)
		label.size = Vector2(1400, 140)
		label.add_theme_font_size_override("font_size", 38)
		_error_panel.add_child(label)
		for index in range(3):
			var button: Button = _button(["重试", "返回封面", "退出"][index])
			button.position = Vector2(480 + index * 330, 560)
			button.size = Vector2(300, 90)
			button.add_theme_font_size_override("font_size", 32)
			_error_panel.add_child(button)
			match index:
				0:
					_retry_button = button
					button.pressed.connect(_retry_startup)
				1: button.pressed.connect(_back_from_error)
				2: button.pressed.connect(func() -> void: get_tree().quit())
	_error_panel.show()
	_retry_button.grab_focus()

func _retry_startup() -> void:
	if _handoff_in_progress:
		return
	_error_panel.hide()
	_starting = true
	_begin_boot.call_deferred()

func _back_from_error() -> void:
	_error_panel.hide()
	_return_to_cover()

func _input(event: InputEvent) -> void:
	if _return_fading:
		get_viewport().set_input_as_handled()
		return
	if _error_panel != null and _error_panel.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			_back_from_error()
			get_viewport().set_input_as_handled()
		return
	super._input(event)
