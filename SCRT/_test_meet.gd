extends SceneTree

var _main: Node = null

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await create_timer(2.0).timeout
	_main = scene
	var dm = _main.daily_dialogue_mgr
	var cm = _main.comm_mgr
	dm.load_main_storyline()
	dm.load_story_save()
	dm.trigger_day_start(0)
	print("[T] ids: ", cm.get_dialogue_ids())
	# A) d0_04 结束 → next 链应检测 d0_05 的 call_mode 并响铃
	print("[T] A1 trigger d0_04")
	cm.trigger_dialogue("d0_04", true)
	await create_timer(0.5).timeout
	print("[T] A2 finished: ", cm.get_dialogue_ids().has("d0_04"), " ringing=", cm.is_call_ringing())
	await create_timer(1.0).timeout
	print("[T] A3 ringing=", cm.is_call_ringing(), " has_pending_answer=", cm._call_handler.has_pending_answer())
	# B) 模拟接听 → d0_05 播放 → choice 等待
	if cm._call_handler.has_pending_answer():
		cm._call_handler.accept_call()
	await create_timer(1.0).timeout
	print("[T] B1 active=", cm.is_active, " player_lines=", cm._player.current_lines.size())
	print("[T] B2 waiting=", cm._player._waiting, " cond=", cm._player._wait_condition)
	# C) 模拟玩家选择 1 → 跳转 d0_meeting_1 会议模式
	cm._handle_choice_selection(1)
	await create_timer(1.0).timeout
	print("[T] C1 active=", cm.is_active, " display_mode=", cm._ui._display_mode)
	print("[T] C2 meeting_chars=", cm._ui._meeting_chars.keys())
	print("[T] C3 player_line0_char=", cm._player.current_lines[0].get("character") if cm._player.current_lines.size() > 0 else "NONE")
	quit()