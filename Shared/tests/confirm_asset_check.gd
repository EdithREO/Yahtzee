extends SceneTree
func _initialize(): _run.call_deferred()
func _run():
	var game = load("res://game.gd").new()
	root.add_child(game)
	await process_frame
	assert(game.sounds.confirm is AudioStreamWAV)
	assert(game.sounds.confirm.resource_path == "res://audio/score-confirm.wav")
	assert(game.sounds.confirm.get_length() > 0.13 and game.sounds.confirm.get_length() < 0.15)
	game._play("confirm")
	assert(game.confirm_player.stream == game.sounds.confirm)
	assert(FileAccess.file_exists("res://audio/ATTRIBUTION.md"))
	var credit := FileAccess.get_file_as_string("res://audio/ATTRIBUTION.md")
	assert(credit.contains("Christopherderp") and credit.contains("CC0"))
	print("CONFIRM_ASSET_CHECK passed: supplied WAV selected, duration ",game.sounds.confirm.get_length(),", author/license packed")
	game.queue_free()
	await process_frame
	quit()
