extends SceneTree
func _initialize():
	create_timer(600).timeout.connect(func(): printerr("STACK_TEST timeout");quit(1))
	_run.call_deferred()
func inject(dice: Array,kind: String):
	var positions := [Vector3(0,1.22,0),Vector3(0,0.41,0),Vector3(-1.7,0.41,-1.7),Vector3(1.7,0.41,-1.7),Vector3(1.7,0.41,1.7)]
	if kind == "bridge":
		positions[1]=Vector3(-0.45,0.41,0)
		positions[2]=Vector3(0.45,0.41,0)
	if kind == "wall": positions[0]=Vector3(2.2,0.6,0)
	for i in range(5):
		dice[i].global_transform=Transform3D(Basis.IDENTITY,positions[i])
		dice[i].linear_velocity=Vector3.ZERO
		dice[i].angular_velocity=Vector3.ZERO
		dice[i].sleeping=false
		dice[i]._rolling=true
		dice[i]._settle_elapsed=0
	if kind == "wall": dice[0].global_basis=Basis(Vector3.FORWARD,PI/4)
func _run():
	var world=load("res://room/physics_world.gd").new()
	root.add_child(world)
	await physics_frame
	for kind in ["stack","bridge","wall"]:
		var before: int=world.stack_assist.impulse_events
		world.request_roll()
		await physics_frame
		await physics_frame
		inject(world.dice,kind)
		if kind == "stack": assert(world.stack_assist.support_for(world.dice[0],world.dice,[true,false,false,false,false]) == null)
		var result: Dictionary=await world.completed
		assert(result.ok)
		for die in result.dice: assert(die.position[1]<0.75)
		if kind != "wall": assert(world.stack_assist.impulse_events>before)
		assert(world.stack_assist.original_materials.is_empty())
		print("STACK_CASE ",kind," ok duration=",result.duration," gentle_impulses=",world.stack_assist.impulse_events-before," recoveries=",result.recoveries)
	world.queue_free()
	await process_frame
	var game=load("res://game.gd").new()
	root.add_child(game)
	game._roll()
	await physics_frame
	await physics_frame
	inject(game.dice,"stack")
	while game.busy: await physics_frame
	assert(not game.values.has(0))
	for die in game.dice: assert(die.global_position.y<0.75)
	assert(game.stack_assist.impulse_events>0)
	assert(game.stack_assist.original_materials.is_empty())
	print("STACK_NATIVE_CASE passed; helper skips held dice and temporary materials restored")
	game.queue_free()
	await create_timer(0.4).timeout
	quit()
