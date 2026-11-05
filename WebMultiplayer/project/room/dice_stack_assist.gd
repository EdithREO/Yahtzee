extends RefCounted

var elapsed := {}
var original_materials := {}
var impulse_events := 0

func support_for(die: DiceDie3D, dice: Array, held: Array):
	var index := dice.find(die)
	if index < 0 or held[index] or die.global_position.y < 0.75: return null
	for j in range(dice.size()):
		if held[j] or dice[j] == die: continue
		var offset: Vector3 = die.global_position-dice[j].global_position
		if offset.y > 0.35 and offset.y < 1.25 and Vector2(offset.x,offset.z).length() < 0.87:
			return dice[j]
	return null

func has_stack(dice: Array,held: Array) -> bool:
	for die in dice:
		if support_for(die,dice,held) != null: return true
	return false

func step(dice: Array,held: Array,box: DiceRollBox3D,delta: float):
	for die in dice:
		var below = support_for(die,dice,held)
		if below == null:
			elapsed.erase(die)
			if original_materials.has(die) and die.global_position.y < 0.65:
				die.physics_material_override = original_materials[die]
				original_materials.erase(die)
			continue
		if die.freeze: continue
		if not die.is_rolling():
			die._rolling = true
			die._settle_elapsed = 0
			box._rolling_dice[die] = true
			box._settled_results.erase(die)
		if die.linear_velocity.length() > 0.3 or die.angular_velocity.length() > 0.8:
			elapsed.erase(die)
			continue
		elapsed[die] = elapsed.get(die,0.0)+delta
		if elapsed[die] < 0.2: continue
		if not original_materials.has(die):
			original_materials[die] = die.physics_material_override
			var material := PhysicsMaterial.new()
			material.friction = 0.06
			material.bounce = die.physics_material_override.bounce if die.physics_material_override != null else 0.28
			die.physics_material_override = material
		var direction: Vector3 = die.global_position-below.global_position
		direction.y = 0
		if direction.length() < 0.1:
			direction = Vector3(-die.position.x,0,-die.position.z)
		if direction.length() < 0.1:
			var angle: float = dice.find(die)*2.3999632297
			direction = Vector3(cos(angle),0,sin(angle))
		die.sleeping = false
		die._settle_elapsed = 0
		die.apply_central_impulse(direction.normalized()*0.4)
		elapsed[die] = 0
		impulse_events += 1

func reset():
	for die in original_materials:
		if is_instance_valid(die): die.physics_material_override = original_materials[die]
	original_materials.clear()
	elapsed.clear()
