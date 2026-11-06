extends Node3D

const D4Dice = preload("res://room/d4_dice.gd")
const MatchSkills = preload("res://match_skills.gd")
var turn_skills: MatchSkills
var biohazard_before_roll: Array = []

var stack_assist = preload("res://room/dice_stack_assist.gd").new()

signal completed(result: Dictionary)
signal sampled(state: Dictionary)
@export_range(5,60) var sample_hz := 20.0
var sample_elapsed := 0.0
var sequence := 0
var physics_cost_sum := 0.0
var physics_cost_max := 0.0
var physics_steps := 0
const START := [Vector3(-3.8,3,-0.75),Vector3(-3.8,3,0.75),Vector3(-3.8,1.45,-1.3),Vector3(-3.8,1.45,0),Vector3(-3.8,1.45,1.3)]
var dice: Array[DiceDie3D] = []
var held := [false,false,false,false,false]
var busy := false
var over := false
var rolls := 0
var physics_elapsed := 0.0
var total_elapsed := 0.0
var attempts := {}
var paused: Array[DiceDie3D] = []
var recovery_die: DiceDie3D
var slow := {}
var box: DiceRollBox3D
var entering: Array[DiceDie3D] = []
var entry_wall: StaticBody3D
var roll_id := ""
var last_result := {}
var contacts := {"dice":0,"environment":0}
var audio_hit_id := 0
var audio_last_hit_ms := -170
var log_file: FileAccess
var before_roll: Array[Transform3D] = []
var group_settle_pending := false
var group_settle_elapsed := 0.0
var hold_parked := {}
func set_held(index: int,selected: bool):
	_set_dice_contacts(false)
	var die := dice[index]
	die.freeze = true
	die.linear_velocity = Vector3.ZERO
	die.angular_velocity = Vector3.ZERO
	if selected:
		hold_parked[index] = die.global_transform
		die.global_position = Vector3(4.1,1.1,(index-2)*1.0)
	else:
		if hold_parked.has(index): die.global_transform = hold_parked[index]
		hold_parked.erase(index)
	held[index] = selected

func _ready():
	var configured := OS.get_environment("YACHT_SAMPLE_HZ")
	if configured.is_valid_float(): sample_hz = clampf(configured.to_float(),5,60)
	var folder := OS.get_user_data_dir().path_join("physics_logs")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("rolls-%s-%s.jsonl" % [Time.get_unix_time_from_system(), get_instance_id()])
	log_file = FileAccess.open(path, FileAccess.WRITE)
	print("Physics log: ", path)
	_setup_physics()

func request_roll(hold_mask: Array = []) -> bool:
	if busy: return false
	_cancel_roll()
	biohazard_before_roll = _biohazard_state().get("infected", [])
	held = hold_mask.duplicate() if hold_mask.size() == 5 else [false,false,false,false,false]
	before_roll.clear()
	for die in dice: before_roll.append(die.global_transform)
	busy = true
	rolls = 1
	roll_id = Crypto.new().generate_random_bytes(16).hex_encode()
	sample_elapsed = 0
	sequence = 0
	physics_cost_sum = 0
	physics_cost_max = 0
	physics_steps = 0
	physics_elapsed = 0
	total_elapsed = 0
	contacts = {"dice":0,"environment":0}
	audio_hit_id = 0
	audio_last_hit_ms = -170
	_launch.call_deferred()
	return true

func _launch():
	await get_tree().physics_frame
	for i in range(5):
		if held[i]: continue
		var die := dice[i]
		die.freeze = false
		die.sleeping = false
		die.add_collision_exception_with(entry_wall)
		entering.append(die)
		var options := DiceRollOptions.new()
		options.spawn_position = START[i]
		die.global_basis = _random_basis(die)
		options.randomize_rotation = false
		options.impulse = Vector3(randf_range(17,20),randf_range(-2,-0.8),randf_range(-0.8,0.8))
		box.roll(die,options)
		die.angular_velocity = Vector3(randf_range(-13,13),randf_range(-13,13),randf_range(-13,13))

	_set_dice_contacts(true)

func _on_hit(body: Node, _index: int):
	if busy: contacts["dice" if body is DiceDie3D else "environment"] += 1
	if busy and turn_skills != null and body is DiceDie3D:
		turn_skills.infect_contact(_index, dice.find(body))
	if not busy or dice[_index].linear_velocity.length() < 1.8: return
	var now := Time.get_ticks_msec()
	if now - audio_last_hit_ms < 170: return
	audio_last_hit_ms = now
	audio_hit_id += 1

func _on_all_settled(_results: Dictionary):
	if not busy: return
	group_settle_pending = true
	group_settle_elapsed = 0

func _publish_settled_result():
	if not busy: return
	var output := []
	for i in range(5):
		var die := dice[i]
		var result := box.get_result(die)
		if result == null or not result.is_flat or result.value < 1 or result.value > 6:
			_recover_one(die)
			return
		var p := die.global_position
		var q := die.global_basis.get_rotation_quaternion()
		output.append({"id":i,"value":result.value,"position":[p.x,p.y,p.z],"rotation":[q.x,q.y,q.z,q.w],"d4":die.die_shape == DiceDie3D.DieShape.D4,"linear_speed":die.linear_velocity.length(),"angular_speed":die.angular_velocity.length()})
	_finish({"ok":true,"dice":output})

func _roll_failed():
	var debug_dice := []
	for i in range(5):
		debug_dice.append({"id":i,"held":held[i],"frozen":dice[i].freeze,"rolling":dice[i].is_rolling(),"sleeping":dice[i].sleeping,"linear_speed":dice[i].linear_velocity.length(),"angular_speed":dice[i].angular_velocity.length(),"tracked":box._rolling_dice.has(dice[i])})
	for i in range(before_roll.size()): dice[i].global_transform = before_roll[i]
	_finish({"ok":false,"error":"Dice failed to settle within recovery limits","dice_debug":debug_dice})

func reset_turn():
	hold_parked.clear()
	_cancel_roll()
	held = [false,false,false,false,false]
	for i in range(5):
		dice[i].max_contacts_reported = 4
		D4Dice.set_active(dice[i], false)
		dice[i].linear_velocity = Vector3.ZERO
		dice[i].angular_velocity = Vector3.ZERO
		dice[i].global_transform = Transform3D(_random_basis(dice[i]),Vector3(i-2,0.41,0))
	last_result = {}

func activate_d4(indices: Array[int]) -> void:
	for index in indices:
		held[index] = false
		hold_parked.erase(index)
		D4Dice.prepare_for_roll(dice[index], index)

func clear_d4() -> bool:
	var changed := false
	for die in dice:
		if die.die_shape != DiceDie3D.DieShape.D4:
			continue
		D4Dice.set_active(die, false)
		die.global_basis = _random_basis(die)
		die.position.y = D4Dice.resting_height(die)
		changed = true
	return changed

func board_state(turn: int) -> Dictionary:
	var poses := []
	for i in range(5):
		var p := dice[i].global_position
		var q := dice[i].global_basis.get_rotation_quaternion()
		poses.append({"id":i,"position":[p.x,p.y,p.z],"rotation":[q.x,q.y,q.z,q.w],"d4":dice[i].die_shape == DiceDie3D.DieShape.D4})
	return {"turn_id":turn,"dice":poses,"biohazard":_biohazard_state()}

func _biohazard_state() -> Dictionary:
	return turn_skills.biohazard_snapshot() if turn_skills != null else {}

func _finish(result: Dictionary):
	if not result.ok and turn_skills != null:
		turn_skills.restore_infections(biohazard_before_roll)
	result["biohazard"] = _biohazard_state()
	result["roll_id"] = roll_id
	result["stack_assist_impulses_total"] = stack_assist.impulse_events
	result["duration"] = total_elapsed
	result["server_ms"] = Time.get_ticks_msec()
	result["seq"] = sequence + 1
	result["ended"] = true
	result["audio_hit_id"] = audio_hit_id
	result["physics_frame_ms_mean"] = physics_cost_sum / max(1,physics_steps)
	result["physics_frame_ms_max"] = physics_cost_max
	result["contacts"] = contacts.duplicate()
	result["recoveries"] = attempts.values().reduce(func(a,b): return a+b,0)
	_cancel_roll()
	for die in dice:
		die.linear_velocity = Vector3.ZERO
		die.angular_velocity = Vector3.ZERO
	busy = false
	last_result = result
	if log_file != null:
		log_file.store_line(JSON.stringify(result))
		log_file.flush()
	completed.emit(result)

func _setup_physics():

	box = DiceRollBox3D.new()
	box.size = Vector3(5.5, 6, 5.5)
	box.position = Vector3(0, 3, 0)
	box.debug_visible = false
	box.gravity_strength = 20
	box.dice_friction = 0.38
	box.dice_bounce = 0.28
	box.flat_result_threshold = 0.985
	box.reroll_unflat_results = false
	add_child(box)
	entry_wall = box.get_node("_DiceEnvironment/Wall_NegX")
	var rim := PhysicsMaterial.new()
	rim.friction = 0.25
	rim.bounce = 0.80
	for side in ["Wall_NegX","Wall_PosX","Wall_NegZ","Wall_PosZ"]:
		box.get_node("_DiceEnvironment/" + side).physics_material_override = rim
	box.all_dice_settled.connect(_on_all_settled)
	box.roll_finished.connect(_on_die_settled)
	var definition := DiceDieDefinition3D.numbered_d6()
	definition.edge_length = 0.8
	definition.body_color = Color.WHITE
	definition.body_clearcoat = 0.0
	definition.settle_duration = 0.35
	definition.settle_linear_velocity = 0.1
	definition.settle_angular_velocity = 0.15
	for face in definition.faces: face.texture = load("res://pips/%d.svg" % face.value)
	for i in range(5):
		var die := box.create_die(definition)
		die.wait_for_flat_result = true
		die.continuous_cd = true
		die.linear_damp = 0.55
		die.angular_damp = 0.9
		die.contact_monitor = true
		die.max_contacts_reported = 4
		die.body_entered.connect(_on_hit.bind(i))
		dice.append(die)
		die.freeze = true


func _random_basis(die: DiceDie3D) -> Basis:
	var slots := die.get_face_slots()
	var slot: StringName = slots[randi_range(0, slots.size() - 1)]
	return Basis(Vector3.UP, randi_range(0, 3) * PI * 0.5) * Basis(Quaternion(die.get_local_result_direction(slot), Vector3.UP))

func _cancel_roll() -> void:
	stack_assist.reset()
	if box == null: return
	_set_dice_contacts(false)
	group_settle_pending = false
	group_settle_elapsed = 0
	for d in entering: d.remove_collision_exception_with(entry_wall)
	entering.clear()
	for die in dice:
		die.freeze = true
		die._rolling = false
		die._settle_elapsed = 0
	box._rolling_dice.clear()
	box._settled_results.clear()
	box._unflat_reroll_counts.clear()
	box._gravity_suspended_dice.clear()
	attempts.clear()
	paused.clear()
	recovery_die = null
	slow.clear()

func _physics_process(delta: float) -> void:
	if not busy or over or rolls == 0: return
	stack_assist.step(dice,held,box,delta)
	var cost := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	physics_cost_sum += cost
	physics_cost_max = maxf(physics_cost_max,cost)
	physics_steps += 1
	sample_elapsed += delta
	if sample_elapsed >= 1.0 / sample_hz:
		sample_elapsed = fmod(sample_elapsed,1.0/sample_hz)
		sequence += 1
		var poses := []
		for i in range(5):
			var p := dice[i].global_position
			var q := dice[i].global_basis.get_rotation_quaternion()
			poses.append({"id":i,"position":[p.x,p.y,p.z],"rotation":[q.x,q.y,q.z,q.w],"d4":dice[i].die_shape == DiceDie3D.DieShape.D4})
		sampled.emit({"roll_id":roll_id,"seq":sequence,"server_ms":Time.get_ticks_msec(),"dice":poses,"audio_hit_id":audio_hit_id,"biohazard":_biohazard_state()})
	for j in range(entering.size()-1, -1, -1):
		var incoming := entering[j]
		if incoming.position.x > -2.05:
			incoming.remove_collision_exception_with(entry_wall)
			entering.remove_at(j)
	total_elapsed += delta
	if total_elapsed > 120.0:
		_roll_failed()
		return
	physics_elapsed += delta
	if group_settle_pending:
		var all_stable := true
		for die in dice:
			if die.linear_velocity.length() > die.settle_linear_velocity or die.angular_velocity.length() > die.settle_angular_velocity or not box.get_result(die).is_flat or stack_assist.support_for(die,dice,held) != null:
				all_stable = false
				# A previously settled die can be awakened by a later collision.
				# Resume the existing settle detector without changing its pose or impulse.
				if held[dice.find(die)]:
					_roll_failed()
					return
				die.freeze = false
				die._rolling = true
				die._settle_elapsed = 0
				die.sleeping = false
				box._rolling_dice[die] = true
				box._settled_results.erase(die)
		if all_stable:
			group_settle_elapsed += delta
			if group_settle_elapsed >= 0.35:
				_publish_settled_result()
			return
		group_settle_pending = false
		group_settle_elapsed = 0
	if physics_elapsed > 6.0:
		_recover_one()
	for i in range(5):
		var die := dice[i]
		if held[i] or die.freeze or not die.is_rolling(): continue
		var result := box.get_result(die)
		if result.is_flat or die.linear_velocity.length() >= 0.22 or die.angular_velocity.length() >= 0.65:
			slow.erase(die)
			continue
		slow[die] = slow.get(die, 0.0) + delta
		if slow[die] >= 0.3:
			die.sleeping = false
			die.apply_torque_impulse(result.top_normal.cross(Vector3.UP) * 0.16)
			var away := Vector3.ZERO
			for other in dice:
				if other != die and die.global_position.distance_to(other.global_position) < 1.35:
					away += die.global_position - other.global_position
			if maxf(absf(die.position.x),absf(die.position.z)) > 1.95: away -= die.position
			away.y = 0
			die.apply_central_impulse(away.normalized() * 0.13)
			slow[die] = 0.0

func _recover_one(stuck_override: DiceDie3D = null) -> void:
	physics_elapsed = 0
	var die := recovery_die if recovery_die != null else stuck_override
	if die == null:
		for candidate in dice:
			if candidate.is_rolling() and not candidate.freeze:
				die = candidate
				break
	if die == null: return
	attempts[die] = attempts.get(die, 0) + 1
	if attempts[die] > 3:
		_roll_failed()
		return
	if recovery_die == null:
		paused.clear()
		for other in dice:
			if other == die: continue
			if other.is_rolling() and not other.freeze: paused.append(other)
			other.freeze = true
		recovery_die = die
	var options := DiceRollOptions.new()
	options.spawn_position = Vector3(0, 2.2, 0)
	box.roll(die, options)

func _on_die_settled(result: DiceRollResult) -> void:
	if result.die != recovery_die or recovery_die == null: return
	recovery_die = null
	physics_elapsed = 0
	for die in paused:
		die.freeze = false
		die.sleeping = false
	paused.clear()


func _set_dice_contacts(enabled: bool):
	for i in range(dice.size()):
		for j in range(i+1,dice.size()):
			if enabled and not held[i] and not held[j]:
				dice[i].remove_collision_exception_with(dice[j])
			else:
				dice[i].add_collision_exception_with(dice[j])

