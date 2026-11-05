extends SceneTree
func _initialize(): _run.call_deferred()
func _run():
	var local = load("res://game.gd").new()
	root.add_child(local)
	local.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	assert(local.hold_buttons.is_empty())
	assert(local.icons.size()==5)
	assert(not local.hint.visible and not local.result_label.visible)
	assert(local.roll_button.get_global_rect().position.y < local.stage_container.get_global_rect().position.y)
	local.values=[6,2,2,4,1]
	local.rolls=1
	local._update_ui()
	assert(local.icon_order==[4,1,2,3,0])
	var original: Transform3D = local.dice[1].global_transform
	local._on_icon_pressed(1)
	await local.hold_tween.finished
	assert(local.held[1] and absf(local.dice[1].global_position.x-4.1)<0.001)
	local._toggle_hold(1)
	await local.hold_tween.finished
	assert(not local.held[1] and local.dice[1].global_position.distance_to(original.origin)<0.001)
	local._confirm_new_game()
	assert(local.get_node("NewGameConfirm").get_ok_button().text=="同意并重新开始")
	print("DESIGN_TEST passed: no bottom buttons/hints, top throw, stable sort, hold aside and restore, local consent")
	local.queue_free()
	await create_timer(0.4).timeout
	quit()
