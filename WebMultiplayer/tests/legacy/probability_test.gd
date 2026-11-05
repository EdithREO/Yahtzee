extends SceneTree

const THROWS := 5000
var counts := []
var failures := 0
var invalid := 0
var recoveries := 0
var successful := 0
var baseline := {}
var simulation_seconds := 0.0
var started := 0

func _initialize():
	for i in range(5): counts.append([0,0,0,0,0,0])
	_run.call_deferred()

func snapshot():
	return {"memory":Performance.get_monitor(Performance.MEMORY_STATIC),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)}

func _run():
	var world = load("res://room/physics_world.gd").new()
	root.add_child(world)
	await physics_frame
	started = Time.get_ticks_msec()
	for i in range(THROWS):
		if not world.request_roll():
			printerr("Unexpected concurrent roll")
			quit(2)
			return
		var result: Dictionary = await world.completed
		simulation_seconds += result.duration
		recoveries += result.recoveries
		if not result.ok:
			failures += 1
		else:
			var valid: bool = result.dice.size() == 5
			for die in result.dice:
				if die.id < 0 or die.id > 4 or die.value < 1 or die.value > 6 or die.linear_speed > 0.11 or die.angular_speed > 0.16: valid = false
			if not valid: invalid += 1
			else:
				successful += 1
				for die in result.dice: counts[int(die.id)][int(die.value)-1] += 1
		if i == 249: baseline = snapshot()
		if (i+1)%250 == 0: print("PROBABILITY_PROGRESS ",i+1,"/",THROWS," failures=",failures," invalid=",invalid)
	var report := {"attempts":THROWS,"successful":successful,"failures":failures,"invalid":invalid,"counts":counts,"recoveries":recoveries,"simulation_seconds":simulation_seconds,"elapsed_seconds":(Time.get_ticks_msec()-started)/1000.0,"baseline_after_250":baseline,"after_5000":snapshot()}
	var path := OS.get_user_data_dir().path_join("physics_logs/probability-5000-%s.json" % Time.get_unix_time_from_system())
	var output := FileAccess.open(path,FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify(report,"  "));output.close()
	print("PROBABILITY_REPORT_PATH ",path)
	print("PROBABILITY_SUMMARY ",JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 and invalid == 0 else 1)
