extends RefCounted

const VALUES := [4, 4, 5, 6]

static func set_active(die: DiceDie3D, active: bool) -> void:
	var shape := DiceDie3D.DieShape.D4 if active else DiceDie3D.DieShape.D6
	if die.die_shape == shape:
		return
	die.die_shape = shape
	if active:
		var faces: Array[DiceFace3D] = []
		for i in range(VALUES.size()):
			var value: int = VALUES[i]
			faces.append(DiceFace3D.new_face(value, StringName("d4_%d" % i), null, str(value)))
		die.set_faces(faces)
	else:
		var faces := DiceFace3D.numbered_d6()
		for face in faces:
			face.texture = load("res://pips/%d.svg" % face.value)
		die.set_faces(faces)

static func prepare_for_roll(die: DiceDie3D, index: int) -> void:
	set_active(die, true)
	var slot := die.get_default_idle_slot()
	die.global_transform = Transform3D(
		Basis(Quaternion(die.get_local_result_direction(slot), Vector3.UP)),
		Vector3(index - 2, resting_height(die), 0)
	)

static func resting_height(die: DiceDie3D) -> float:
	return DiceDieShape3D.get_face_center(die.die_shape, die.get_default_idle_slot()).length() * die.edge_length + 0.01
