extends SceneTree

var world: Node3D
var failures := 0
var dice_hits := 0
var environment_hits := 0
var baseline := {}

func _initialize():
	_run.call_deferred()

func snapshot() -> Dictionary:
	return {"memory":Performance.get_monitor(Performance.MEMORY_STATIC),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)}

func _run():
	world = load("res://room/physics_world.gd").new()
	root.add_child(world)
	await physics_frame
	for i in range(100):
		if not world.request_roll():
			quit(2)
			return
		var result: Dictionary = await world.completed
		if not result.ok: failures += 1
		else:
			for d in result.dice:
				if d.value < 1 or d.value > 6 or d.linear_speed > 0.11 or d.angular_speed > 0.16: failures += 1
		dice_hits += result.contacts.dice
		environment_hits += result.contacts.environment
		if i == 9: baseline = snapshot()
		if (i+1) % 10 == 0: print("PHYSICS_PROGRESS ", i+1, " ", JSON.stringify(snapshot()))
	var report := {"throws":100,"failures":failures,"dice_contacts":dice_hits,"environment_contacts":environment_hits,"baseline_after_10":baseline,"after_100":snapshot()}
	print("PHYSICS_SUMMARY ", JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 and dice_hits > 0 and environment_hits > 0 else 1)
