extends SceneTree

func _initialize():
	_run.call_deferred()

func _run():
	var world = load("res://room/physics_world.gd").new()
	root.add_child(world)
	await physics_frame
	world.request_roll()
	var first: Dictionary = await world.completed
	assert(first.ok)
	# Inject the recovery edge case: an already frozen body retains nonzero velocity.
	world.busy = true
	world.physics_elapsed = 0
	world.total_elapsed = 0
	world.dice[0].linear_velocity = Vector3(0.18,0,0)
	world.dice[0].angular_velocity = Vector3(0,0.55,0)
	assert(world.dice[0].freeze)
	world._on_all_settled({})
	world._physics_process(1.0/60.0)
	assert(not world.dice[0].freeze)
	assert(world.dice[0].is_rolling())
	var recovered: Dictionary = await world.completed
	assert(recovered.ok)
	for die in recovered.dice:
		assert(die.linear_speed <= 0.1 and die.angular_speed <= 0.15)
	print("SETTLE_RECHECK_TEST passed: frozen moving die resumed and all five settled")
	world.queue_free()
	await process_frame
	quit()
