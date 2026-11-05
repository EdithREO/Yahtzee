extends SceneTree
func _initialize(): _run.call_deferred()
func _run():
	var game = load("res://game.gd").new()
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	var icon_center: float = (game.icons[0].global_position.x+game.icons[4].global_position.x+game.icons[4].size.x)/2.0
	var stage_center: float = game.stage_container.global_position.x+game.stage_container.size.x/2.0
	assert(absf(icon_center-stage_center)<2)
	game._roll()
	while game.busy: await physics_frame
	for i in range(5):
		assert(game.dice[i].freeze)
		for j in range(i+1,5): assert(game.dice[i].get_collision_exceptions().has(game.dice[j]))
	# Reproduce a hold path through an adjacent body's position.
	game.dice[2].global_position=Vector3(-1,0.41,0)
	game.dice[1].global_position=Vector3(0,0.41,0)
	var neighbor: Transform3D = game.dice[1].global_transform
	game._toggle_hold(2)
	await game.hold_tween.finished
	assert(game.dice[1].global_transform.is_equal_approx(neighbor))
	game._toggle_hold(2)
	await game.hold_tween.finished
	assert(game.dice[1].global_transform.is_equal_approx(neighbor))
	game._toggle_hold(0)
	await game.hold_tween.finished
	game._roll()
	await physics_frame
	await physics_frame
	assert(not game.dice[1].get_collision_exceptions().has(game.dice[2]))
	assert(game.dice[0].get_collision_exceptions().has(game.dice[1]))
	while game.busy: await physics_frame
	for die in game.dice: assert(die.freeze and die.linear_velocity.length()<0.001)
	print("SETTLED_CONTACTS_TEST passed: centered icons, all settled contacts off, crossing hold/cancel cannot move neighbor, next roll restores active contacts only")
	game.queue_free()
	await create_timer(0.4).timeout
	quit()
