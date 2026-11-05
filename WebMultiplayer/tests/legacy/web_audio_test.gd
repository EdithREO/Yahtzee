extends SceneTree

func _initialize():
	_run.call_deferred()

func _run():
	var view = load("res://room/trajectory_view.gd").new()
	root.add_child(view)
	await process_frame
	assert(view.sound_player != null and view.hit_player != null)
	assert(view.sounds.hits.size() == 4)
	assert(view.sounds.select is AudioStreamOggVorbis)
	assert(view.sounds.roll is AudioStreamWAV and view.sounds.win is AudioStreamWAV)
	view._play_sample_hit({"audio_hit_id":1})
	assert(view.played_hit_id == 1 and view.hit_player.stream == view.sounds.hits[0])
	view._play_sample_hit({"audio_hit_id":1})
	assert(view.played_hit_id == 1)
	view._play_sample_hit({"audio_hit_id":4})
	assert(view.played_hit_id == 4 and view.hit_player.stream == view.sounds.hits[3])
	view._play_sample_hit({})
	assert(view.played_hit_id == 4)
	view._receive({"type":"roll_started","roll_id":"next"})
	assert(view.played_hit_id == 0)
	view._play("select")
	assert(view.sound_player.stream == view.sounds.select)
	var world = load("res://room/physics_world.gd").new()
	root.add_child(world)
	await physics_frame
	world.busy = true
	world.dice[0].linear_velocity = Vector3(3,0,0)
	world._on_hit(world.entry_wall,0)
	assert(world.audio_hit_id == 1)
	world._on_hit(world.entry_wall,0)
	assert(world.audio_hit_id == 1)
	world.audio_last_hit_ms = -170
	world.dice[0].linear_velocity = Vector3.ZERO
	world._on_hit(world.entry_wall,0)
	assert(world.audio_hit_id == 1)
	world.busy = false
	assert(world.request_roll())
	assert(world.audio_hit_id == 0)
	var result: Dictionary = await world.completed
	assert(result.ok and result.audio_hit_id > 0)
	print("WEB_AUDIO_TEST passed: original clips, deterministic hit selection, duplicate/missing event safety, roll reset, real collision events; audio output requires browser check")
	view.queue_free()
	world.queue_free()
	await process_frame
	quit()
