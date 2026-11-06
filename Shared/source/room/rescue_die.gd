extends RefCounted

const PICK_LAYER := 1 << 21

static func create() -> DiceDie3D:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.13, 0.56, 0.94, 0.58)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.16
	glass.metallic_specular = 0.65
	var die := DiceDie3D.new()
	die.edge_length = 0.8
	die.body_shape = DiceDie3D.BodyShape.ROUNDED
	die.body_material = glass
	die.freeze = true
	die.collision_layer = PICK_LAYER
	die.collision_mask = 0
	die.hide()
	var faces := DiceFace3D.numbered_d6()
	for face in faces:
		var pips := StandardMaterial3D.new()
		pips.albedo_texture = load("res://pips/rescue-%d.svg" % face.value)
		pips.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		pips.alpha_scissor_threshold = 0.45
		pips.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		face.material = pips
	die.set_faces(faces)
	return die

static func show_value(die: DiceDie3D, value: int) -> void:
	die.visible = value > 0
	if not die.visible:
		return
	for slot in die.get_face_slots():
		if die.get_face(slot).value == value:
			die.basis = Basis(Vector3.UP, PI / 10) * Basis(Quaternion(die.get_local_face_normal(slot), Vector3.UP))
			return
