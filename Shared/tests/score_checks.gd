extends SceneTree
func _initialize(): _run.call_deferred()
func _run():
	var web := FileAccess.file_exists("res://room/trajectory_view.gd")
	var view = load("res://room/trajectory_view.gd" if web else "res://game.gd").new()
	root.add_child(view)
	await process_frame
	assert(view.sounds.roll is AudioStreamOggVorbis)
	assert(view.victory_player.stream.get_length() == 5.0)
	if web:
		var m = load("res://room/match_state.gd").new(0)
		assert(m.operate("select_skill",0,{"turn_id":1,"skill_id":"d4"}) == "")
		assert(m.operate("select_skill",1,{"turn_id":1,"skill_id":"blackout"}) == "")
		assert(m.operate("commit_score",0,{"turn_id":1,"category":1}) != "")
		assert(m.score_revision == 0)
		m.rolls = 1
		m.values = [1,1,1,1,1]
		var ui := {"game":m.snapshot(),"seat":1,"can_act":false,"rolling":false,"pending":false,"error":"","restart":null,"score_sound_event":0}
		view._apply_ui(ui)
		assert(view.score_buttons[0][1].text == "0" and view.score_buttons[0][1].disabled)
		assert(view.score_buttons[0][1].get_theme_color("font_disabled_color").a < 0.5)
		assert(m.operate("commit_score",0,{"turn_id":1,"category":1}) == "")
		ui.game = m.snapshot()
		ui.score_sound_event = 1
		view._apply_ui(ui)
		assert(view.confirm_player.playing)
		view.confirm_player.stop()
		ui.pending = true
		view._apply_ui(ui)
		assert(not view.confirm_player.playing)
		assert(m.scores[0][1] == 0 and m.scores[0][0] == null)
		m.rolls = 1
		m.values = [2,2,2,2,2]
		assert(m.operate("commit_score",1,{"turn_id":2,"category":0}) == "")
		ui.game = m.snapshot()
		ui.score_sound_event = 2
		view._apply_ui(ui)
		assert(view.last_scored == [1,0])
		var restored = load("res://room/trajectory_view.gd").new()
		root.add_child(restored)
		await process_frame
		restored._apply_ui(ui)
		assert(restored.last_scored == [1,0] and not restored.confirm_player.playing)
		restored.queue_free()
	else:
		view._choose_skill("d4")
		view._choose_skill("blackout")
		view.rolls = 1
		view.values = [1,1,1,1,1]
		view._update_ui()
		assert(view.scores[0][1] == null and view.score_buttons[0][1].text == "0")
		assert(view.score_buttons[0][1].get_theme_color("font_color").a < 0.5)
		view._commit_score(0,1)
		view.rolls = 1
		view.values = [2,2,2,2,2]
		view._commit_score(1,0)
		assert(view.last_scored == [1,0])
		view.confirm_player.stop()
		view._commit_score(1,0)
		assert(not view.confirm_player.playing)
	for pair in [[0,1],[1,0]]:
		var button: Button = view.score_buttons[pair[0]][pair[1]]
		assert(button.text == "0" and button.get_meta("score_state") == "confirmed")
		assert(button.get_theme_color("font_disabled_color") == Color.WHITE)
		assert(button.get_theme_stylebox("disabled").border_width_left == 2)
	assert(view.score_buttons[0][0].get_meta("score_state") == "empty")
	assert(view.score_buttons[0][0].text == "—")
	print("SCORE_CHECKS passed ","Web" if web else "Native",": null vs zero, preview opacity, independent highlights, confirmed-only audio, repeat/restore safety, original roll clip, 5s victory")
	view.queue_free()
	await process_frame
	quit()
