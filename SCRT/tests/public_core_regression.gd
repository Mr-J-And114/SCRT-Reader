extends SceneTree
## Only synthetic content and accounts in a runner-provided isolated project.
var checks: int = 0
var failures: Array[String] = []
var game = null

func _initialize() -> void:
	_run.call_deferred()

func expect(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		print("ASSERT_FAIL: " + label)
	return ok

func wait_until(predicate: Callable, seconds: float = 15.0) -> bool:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if predicate.call(): return true
		await create_timer(0.05).timeout
	return false

func submit(text: String) -> void:
	await wait_until(func(): return not game._command_running, 20.0)
	while game.tw.is_typing:
		game._on_input_submitted("")
		await create_timer(0.05).timeout
	game.input_field.text = text
	game._on_input_submitted(text)
	await process_frame
	await wait_until(func(): return not game._command_running, 20.0)
	while game.tw.is_typing:
		game._on_input_submitted("")
		await create_timer(0.05).timeout

func _run() -> void:
	var root_path: String = ProjectSettings.globalize_path("res://").replace("\\", "/")
	var user_path: String = ProjectSettings.globalize_path("user://").replace("\\", "/")
	if not expect(root_path.begins_with(OS.get_environment("SCRT_PUBLIC_TEST_ROOT").replace("\\", "/")), "isolated project root"):
		_finish(); return
	if not expect(user_path.begins_with(OS.get_environment("SCRT_PUBLIC_TEST_ROOT").replace("\\", "/")), "isolated user root"):
		_finish(); return
	for directory in ["scripts", "comm_system", "radio", "env_system", "camera_system", "settings", "templates", "modder", "preview"]:
		for file in DirAccess.get_files_at("res://" + directory):
			if file.ends_with(".gd"):
				var script = load("res://" + directory + "/" + file)
				if not expect(script is GDScript and script.can_instantiate(), "script loads: " + directory + "/" + file):
					_finish(); return
	var scene: PackedScene = load("res://scenes/startup.tscn")
	if not expect(scene != null, "startup scene loads"):
		_finish(); return
	var cover = scene.instantiate()
	root.add_child(cover)
	current_scene = cover
	await process_frame
	await process_frame
	if not expect(cover._menu.size() == 3, "neutral cover builds"):
		_finish(); return
	cover._menu[0].pressed.emit()
	if not expect(await wait_until(func(): return current_scene != cover and current_scene != null), "cover hands off to main"):
		_finish(); return
	game = current_scene
	if not expect(await wait_until(func(): return is_instance_valid(game) and game.input_field != null and game.input_field.editable and (game._register_mode or game._login_mode)), "boot reaches account flow"):
		_finish(); return
	var repeat: bool = game.user_mgr.user_exists("core01")
	if repeat:
		await submit("core01")
		await submit("synthetic-pass")
	else:
		if not expect(game._register_mode, "first run registration wizard"):
			_finish(); return
		for value in ["core01", "synthetic-pass", "synthetic-pass", "Synthetic", "X", "2000-01-01"]:
			await submit(value)
	if not expect(await wait_until(func(): return game.user_mgr.is_logged_in), "normal account input logs in"):
		_finish(); return
	await create_timer(0.5).timeout
	expect(game.user_mgr.get_username() == "core01", "synthetic account selected")
	expect(game.user_mgr.current_user.get("nickname", "") == "Synthetic", "profile persists")
	expect(game.comm_mgr.get_registry().is_empty(), "zero built-in characters")
	expect(game.daily_dialogue_mgr._dialogues.is_empty(), "zero built-in dialogues")
	expect(game.daily_dialogue_mgr._daily_config.is_empty(), "zero built-in schedules")
	expect(game.daily_dialogue_mgr._pending_dialogues.is_empty(), "no narrative scheduled")
	expect(game.vdisc_task_mgr.definitions.is_empty(), "no built-in tasks")
	expect(not game.camera_mgr.has_cameras(), "no built-in cameras")
	await submit("help")
	expect(await wait_until(func(): return game.output_text.get_parsed_text().contains("scan"), 1.0), "help command displays available scan command")
	if not repeat:
		await submit("scan")
		expect(game.disc_mgr.available_stories.is_empty(), "empty content directory works")
		var pack := ZIPPacker.new()
		var path: String = root_path.path_join("vdisc/example.scp")
		if not expect(pack.open(path) == OK, "synthetic ZIP created"):
			_finish(); return
		var content: Dictionary = {
			"manifest.json": JSON.stringify({"story": {"id": "example", "title": "Example", "version": "1.0"}}),
			"welcome.txt": "Synthetic document. [b]Reader Core[/b]",
			"示例.txt": "UTF-8 example document.",
			"loading_screen.json": JSON.stringify({"total_duration": 0.3, "keyframes": [{"time": 0.1, "action": "complete"}]})
		}
		for name in content:
			pack.start_file(name)
			pack.write_file(str(content[name]).to_utf8_buffer())
			pack.close_file()
		pack.close()
	await submit("scan")
	expect(game.disc_mgr.available_stories.size() == 1, "synthetic package scanned")
	await submit("load 1")
	if not expect(game.story_id == "example" and not game._desktop_mode, "normal load command mounts package"):
		_finish(); return
	expect(game.fs.file_system.has("/示例.txt"), "UTF-8 filename preserved")
	await submit("ls")
	await submit("open welcome.txt")
	expect("/welcome.txt" in game.read_files, "normal open records reading")
	var pages: Array[Dictionary] = [{"left": "Synthetic reader page", "right": "Second page"}]
	game.doc_viewer.open("document", pages, "Example")
	await process_frame
	expect(game.doc_viewer.is_active and game.doc_viewer.overlay != null, "generic document UI builds")
	game.doc_viewer.close()
	var rendered: String = game.crtml.parse("[b]Synthetic[/b]")
	expect(rendered.contains("Synthetic"), "CRTML parser")
	await submit("save")
	var saved = game.save_mgr.load_save("example")
	expect(saved is Dictionary and not saved.is_empty(), "saved data reloads")
	if saved is Dictionary: expect("/welcome.txt" in saved.get("read_files", []), "reading progress saved")
	var loader := StoryLoader.new()
	expect(not FileAccess.file_exists("res://gbk_unicode.bin"), "full GBK table deliberately omitted")
	expect(loader._decode_gbk_bytes(PackedByteArray([0xa3, 0xc1])) == "Ａ", "GBK subset full-width character")
	expect(loader._decode_gbk_bytes(PackedByteArray([0xd6, 0xd0])) == "?", "unmapped GBK Chinese explicitly degrades")
	expect(not game.video_player_viewer.is_ffmpeg_available(), "optional native video extension absent")
	await create_timer(2.0).timeout
	expect(game.daily_dialogue_mgr._pending_dialogues.is_empty() and not game.comm_mgr.is_active, "no erroneous narrative during runtime")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://public-core.png")
	print("TEST_MODE: " + ("reload" if repeat else "first-run"))
	_finish()

func _finish() -> void:
	for shape in [Input.CURSOR_ARROW, Input.CURSOR_IBEAM, Input.CURSOR_POINTING_HAND]:
		Input.set_custom_mouse_cursor(null, shape)
	if is_instance_valid(game): game.queue_free()
	game = null
	await process_frame
	await process_frame
	print("PUBLIC_CORE_RESULT: " + JSON.stringify({"checks": checks, "failures": failures, "status": "PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
