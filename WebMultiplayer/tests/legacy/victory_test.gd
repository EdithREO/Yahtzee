extends SceneTree

func _initialize(): _run.call_deferred()

func final_state(a: int,b: int) -> Dictionary:
	var match_state = load("res://room/match_state.gd").new(0)
	for category in range(12):
		match_state.scores[0][category] = YachtRules.score(category,[a,a,a,a,a])
		match_state.scores[1][category] = YachtRules.score(category,[b,b,b,b,b])
	match_state.scores[1][11] = null
	match_state.current_player = 1
	match_state.turn_id = 24
	match_state.values = [b,b,b,b,b]
	match_state.rolls = 1
	assert(match_state.operate("commit_score",1,{"turn_id":24,"category":11}) == "")
	assert(match_state.over)
	return match_state.snapshot()

func ui(game: Dictionary) -> Dictionary:
	return {"game":game,"seat":0,"can_act":false,"rolling":false,"pending":false,"error":"","restart":null}

func _run():
	var view = load("res://room/trajectory_view.gd").new()
	root.add_child(view)
	await process_frame
	assert(is_equal_approx(view.victory_player.stream.get_length(),5.0))
	var data: PackedByteArray = view.victory_player.stream.data
	var tail_peak := 0
	for i in range(22050*4,22050*4+11025): tail_peak = maxi(tail_peak,absi(data.decode_s16(i*2)))
	assert(tail_peak > 500) # The last second contains sound, not silent padding.
	var a := final_state(6,1)
	view._apply_ui(ui(a))
	assert(view.victory_label.text == "玩家 1 胜利" and view.victory_overlay.visible)
	assert(view.player_label.text == "玩家 1 胜利")
	assert(view.victory_player.playing)
	view.victory_overlay.hide()
	var repeated := ui(a)
	repeated.seat = 1 # A changed peer/UI state must not reopen the closed dialog.
	view._apply_ui(repeated)
	assert(not view.victory_overlay.visible)
	var next = load("res://room/match_state.gd").new(0).snapshot()
	view._apply_ui(ui(next))
	assert(not view.victory_overlay.visible and not view.victory_player.playing)
	var b := final_state(1,6)
	view._apply_ui(ui(b))
	assert(view.victory_label.text == "玩家 2 胜利" and view.victory_overlay.visible)
	view._apply_ui(ui(next))
	var tie := final_state(1,1)
	view._apply_ui(ui(tie))
	assert(view.victory_label.text == "平局" and view.victory_overlay.visible)
	assert(not view.victory_player.playing)
	var file := FileAccess.open("res://victory-fixtures.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"a":ui(a),"b":ui(b),"tie":ui(tie),"reset":ui(next)}))
	file.close()
	view._apply_ui({"game":null,"seat":-1,"can_act":false})
	assert(not view.victory_overlay.visible and not view.victory_player.playing)
	print("VICTORY_TEST passed: authoritative final score produces both winners/tie, one-shot popup, close survives repeated state, restart/leave cleanup, five-second audible tail")
	view.queue_free()
	await process_frame
	quit()
