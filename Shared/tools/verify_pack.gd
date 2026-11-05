extends SceneTree
func _initialize():
	var file := FileAccess.open("res://project.binary",FileAccess.READ)
	if file == null or file.get_length() == 0:
		printerr("PACK_VERIFY_FAILED: missing or empty project.binary")
		quit(1)
		return
	var scene: String = ProjectSettings.get_setting("application/run/main_scene","")
	if scene.is_empty() or not ResourceLoader.exists(scene) or load(scene) == null:
		printerr("PACK_VERIFY_FAILED: main scene unavailable: ",scene)
		quit(1)
		return
	print("PACK_VERIFY_OK: project.binary=",file.get_length()," bytes; main=",scene)
	quit()
