extends Control

var stack_assist = preload("res://room/dice_stack_assist.gd").new()

const CAT := YachtRules.CATEGORIES
const MatchSkills = preload("res://match_skills.gd")
const D4Dice = preload("res://room/d4_dice.gd")
const HOLD_X := 4.1
var skills := MatchSkills.new()
var skill_overlay: ColorRect
var skill_prompt: Label
var skill_summary: Label
var skill_buttons: Array[Button] = []
var d4_button: Button
var dice_picker_actions: HBoxContainer
var dice_picker_confirm: Button
var dice_picking := false
var dice_picker_selected: Array[int] = []
var dice_picker_outline: StandardMaterial3D
var dice_picker_skill := ""
var biohazard_button: Button
var biohazard_view: Dictionary = {}
var biohazard_before_roll: Array = []
var blackout_button: Button
var blackout_notice: Label
var blackout_indices: Array = []
var dice: Array[DiceDie3D] = []
var held := [false, false, false, false, false]
var values := [0, 0, 0, 0, 0]
var parked: Array[Transform3D] = []
var scores := [[], []]
var player := 0
var rolls := 0
var busy := false
var over := false
var last_scored := [-1,-1]
var victory_overlay: Control
var victory_label: Label
var victory_player: AudioStreamPlayer
var confirm_player: AudioStreamPlayer
var generation := 0
var physics_elapsed := 0.0
var attempts := {}
var paused: Array[DiceDie3D] = []
var recovery_die: DiceDie3D
var slow := {}
var box: DiceRollBox3D
var camera: Camera3D
var world: Node3D
var stage_view: SubViewport
var stage_container: SubViewportContainer
var roll_button: Button
var hint: Label
var round_label: Label
var player_label: Label
var result_label: Label
var score_buttons := [[], []]
var icons: Array[Button] = []
var icon_order := [0, 1, 2, 3, 4]
var hold_buttons: Array[Button] = []
var subtotal_labels: Array[Label] = []
var bonus_labels: Array[Label] = []
var total_labels: Array[Label] = []
var sound_player: AudioStreamPlayer
var sounds := {}
var hold_tween: Tween
var rules_dialog: AcceptDialog
var last_hit := 0
var entering: Array[DiceDie3D] = []
var entry_wall: StaticBody3D
var hit_player := AudioStreamPlayer.new()
const START := [Vector3(-3.8,3,-0.75),Vector3(-3.8,3,0.75),Vector3(-3.8,1.45,-1.3),Vector3(-3.8,1.45,0),Vector3(-3.8,1.45,1.3)]

func _ready() -> void:
	randomize()
	_setup_theme()
	_setup_audio()
	_setup_ui()
	_setup_world()
	_setup_victory()
	_new_game()

func _setup_theme() -> void:
	var theme := Theme.new()
	var font := FontVariation.new()
	font.base_font = load("res://NotoSansSC.ttf")
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):600.0}
	font.variation_embolden = 0.6
	theme.default_font = font
	theme.default_font_size = 17
	self.theme = theme

func _flat(color: Color, radius: int = 0, border: Color = Color.TRANSPARENT, width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", Color("efe7d5"))
	b.add_theme_color_override("font_disabled_color", Color("bfd3c1"))
	b.add_theme_stylebox_override("normal", _flat(Color("47775e"), 5, Color("4b6556"), 1))
	b.add_theme_stylebox_override("hover", _flat(Color("3b5c4b"), 5, Color("d1b469"), 1))
	b.add_theme_stylebox_override("pressed", _flat(Color("a38649"), 5))
	b.add_theme_stylebox_override("disabled", _flat(Color("385849"), 5))
	return b

func _label(text: String, size: int = 17, color: Color = Color("e9e2d1")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _table_cell(row: HBoxContainer, control: Control, width: float = 0):
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_flat(Color("345849"),0,Color("91ad97"),1))
	panel.get_theme_stylebox("panel").set("border_width_bottom",2)
	panel.get_theme_stylebox("panel").set("border_width_top",2)
	panel.get_theme_stylebox("panel").set("content_margin_top",2.0)
	panel.get_theme_stylebox("panel").set("content_margin_bottom",2.0)
	panel.custom_minimum_size = Vector2(width,42)
	if width == 0: panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(panel)
	panel.add_child(control)

func _setup_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("e8e0c7")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]: margin.add_theme_constant_override(side,16)
	add_child(margin)
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation",14)
	margin.add_child(layout)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 310
	panel.add_theme_stylebox_override("panel",_flat(Color("345849"),10))
	layout.add_child(panel)
	var pad := MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]: pad.add_theme_constant_override(side,12)
	panel.add_child(pad)
	var board := VBoxContainer.new()
	board.add_theme_constant_override("separation",0)
	pad.add_child(board)
	board.add_child(_label("快艇骰子",29,Color("f3e5bc")))
	board.add_child(_label("YACHT / 双人计分",13,Color("a5b7a7")))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation",0)
	board.add_child(head)
	_table_cell(head,_label("计分项目",17))
	for text in ["玩家 1","玩家 2"]:
		var label := _label(text,17,Color("dfcb91"))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_table_cell(head,label,76)
	for category in range(12):
		if category == 6:
			_add_totals_row(board,"上栏小计",subtotal_labels)
			_add_totals_row(board,"奖励 +35",bonus_labels)
			var spacer := Control.new()
			spacer.custom_minimum_size.y = 25
			board.add_child(spacer)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",0)
		board.add_child(row)
		_table_cell(row,_label(CAT[category],18))
		for player_index in range(2):
			var button := _button("—")
			button.pressed.connect(_commit_score.bind(player_index,category))
			_table_cell(row,button,76)
			score_buttons[player_index].append(button)
	_add_totals_row(board,"总分",total_labels,true)
	
	var empty := Control.new()
	empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.add_child(empty)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation",10)
	board.add_child(footer)
	var rules_button := _button("规则")
	rules_button.custom_minimum_size = Vector2(120,46)
	rules_button.pressed.connect(_show_rules)
	footer.add_child(rules_button)
	var restart := _button("重新开始")
	restart.custom_minimum_size = Vector2(120,46)
	restart.pressed.connect(_confirm_new_game)
	footer.add_child(restart)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation",10)
	layout.add_child(right)
	var title := HBoxContainer.new()
	right.add_child(title)
	player_label = _label("玩家 1 的回合",27,Color("244937"))
	player_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(player_label)
	_setup_dice_picker(title)
	blackout_button = _button("黑幕啊")
	blackout_button.custom_minimum_size.y = 32
	blackout_button.pressed.connect(_use_blackout)
	blackout_button.hide()
	title.add_child(blackout_button)
	round_label = _label("第 1 / 12 回合",16,Color("355746"))
	title.add_child(round_label)
	skill_summary = _label("",16,Color("355746"))
	skill_summary.hide()
	right.add_child(skill_summary)
	blackout_notice = _label("", 18, Color("852b28"))
	blackout_notice.hide()
	right.add_child(blackout_notice)
	var strip := Control.new()
	strip.custom_minimum_size.y = 96
	right.add_child(strip)
	roll_button = _button("投 掷\n剩余 3 次")
	roll_button.custom_minimum_size = Vector2(140,96)
	roll_button.add_theme_font_size_override("font_size",22)
	roll_button.pressed.connect(_roll)
	strip.add_child(roll_button)
	var icon_strip := HBoxContainer.new()
	icon_strip.anchor_left = 0.5
	icon_strip.anchor_right = 0.5
	icon_strip.anchor_bottom = 1.0
	icon_strip.offset_left = -268
	icon_strip.offset_right = 268
	icon_strip.add_theme_constant_override("separation",14)
	strip.add_child(icon_strip)
	for slot in range(5):
		var icon := Button.new()
		icon.custom_minimum_size = Vector2(96,96)
		icon.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.add_theme_constant_override("icon_max_width",82)
		icon.pressed.connect(_on_icon_pressed.bind(slot))
		icon_strip.add_child(icon)
		icons.append(icon)
	stage_container = SubViewportContainer.new()
	stage_container.stretch = true
	stage_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_container.gui_input.connect(_on_stage_input)
	right.add_child(stage_container)
	stage_view = SubViewport.new()
	stage_view.size = Vector2i(1100,700)
	stage_view.own_world_3d = true
	stage_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage_container.add_child(stage_view)
	stage_view.size_changed.connect(_refresh_stage)
	rules_dialog = AcceptDialog.new()
	rules_dialog.title = "游戏规则"
	rules_dialog.dialog_text = "两名玩家轮流，每回合最多投掷三次。点击骰子可保留或取消保留；也可以提前在左侧选择一个空白项目记分。\n\n一至六点：对应点数之和；上栏达到 63 分奖励 35 分。\n全选：五颗点数之和；四条：至少四颗相同，记五颗之和。\n葫芦：恰好三颗相同加一对，记五颗之和；小顺：四个连续点数，15 分；大顺：五个连续点数，30 分；快艇：五颗相同，50 分。\n不满足条件时可以填 0；每个项目每人只能使用一次。12 轮结束，总分高者获胜。"
	add_child(rules_dialog)
	var confirm := ConfirmationDialog.new()
	confirm.title = "重新开始"
	confirm.dialog_text = "结束当前对局并重新开始？"
	confirm.confirmed.connect(_new_game)
	confirm.name = "NewGameConfirm"
	add_child(confirm)

	confirm.get_ok_button().text = "同意并重新开始"
	confirm.get_cancel_button().text = "不同意"
	hint = _label("")
	hint.hide()
	add_child(hint)
	result_label = _label("")
	result_label.hide()
	add_child(result_label)
	_setup_skill_selection()

func _setup_skill_selection() -> void:
	skill_overlay = ColorRect.new()
	skill_overlay.color = Color(0, 0, 0, 0.45)
	skill_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skill_overlay.z_index = 100
	add_child(skill_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skill_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 480
	panel.add_theme_stylebox_override("panel", _flat(Color("345849"), 12, Color("efdc9d"), 2))
	center.add_child(panel)
	var padding := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		padding.add_theme_constant_override(side, 24)
	panel.add_child(padding)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	padding.add_child(content)
	skill_prompt = _label("", 24)
	content.add_child(skill_prompt)
	for skill_id in MatchSkills.CATALOG:
		var skill: Dictionary = MatchSkills.CATALOG[skill_id]
		var button := _button("%s\n%s" % [skill.name, skill.description])
		button.custom_minimum_size.y = 68
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_choose_skill.bind(skill_id))
		content.add_child(button)
		skill_buttons.append(button)
	skill_overlay.hide()

func _render_skills(selected: Array, seat: int, can_select: bool) -> void:
	skill_overlay.visible = selected.has("")
	skill_summary.visible = selected.size() == 2
	if not skill_summary.visible:
		return
	var names := PackedStringArray()
	for skill_id in selected:
		names.append(MatchSkills.CATALOG.get(skill_id, {}).get("name", "待选择"))
	skill_summary.text = "玩家 1：%s　·　玩家 2：%s" % [names[0], names[1]]
	if not skill_overlay.visible:
		return
	var needs_choice: bool = seat >= 0 and seat < selected.size() and selected[seat] == ""
	skill_prompt.text = "玩家 %d · 请选择一项技能" % (seat + 1) if needs_choice else "等待另一位玩家选择技能"
	for button in skill_buttons:
		button.visible = needs_choice
		button.disabled = not can_select

func _choose_skill(skill_id: String) -> void:
	var seat := 0 if skills.skill_for(0).is_empty() else 1
	if not skills.select_skill(seat, skill_id).is_empty():
		return
	_render_skills(skills.snapshot(), 1, true)
	_update_ui()

func _setup_dice_picker(title: HBoxContainer) -> void:
	var controls := VBoxContainer.new()
	title.add_child(controls)
	d4_button = _button("四面骰？")
	d4_button.custom_minimum_size.y = 32
	d4_button.tooltip_text = "在骰盘上点选两颗骰子"
	d4_button.pressed.connect(_open_dice_picker.bind(MatchSkills.D4))
	d4_button.hide()
	controls.add_child(d4_button)
	biohazard_button = _button("生化危机")
	biohazard_button.custom_minimum_size.y = 32
	biohazard_button.tooltip_text = "点选一颗母体骰；发动回合最多投两次"
	biohazard_button.pressed.connect(_open_dice_picker.bind(MatchSkills.BIOHAZARD))
	biohazard_button.hide()
	controls.add_child(biohazard_button)
	dice_picker_actions = HBoxContainer.new()
	dice_picker_actions.add_theme_constant_override("separation", 6)
	dice_picker_actions.hide()
	controls.add_child(dice_picker_actions)
	dice_picker_confirm = _button("确定（0/2）")
	dice_picker_confirm.custom_minimum_size = Vector2(108, 32)
	dice_picker_confirm.pressed.connect(_confirm_dice_selection)
	dice_picker_actions.add_child(dice_picker_confirm)
	var cancel := _button("取消")
	cancel.custom_minimum_size = Vector2(60, 32)
	cancel.pressed.connect(_cancel_dice_selection)
	dice_picker_actions.add_child(cancel)
	dice_picker_outline = StandardMaterial3D.new()
	dice_picker_outline.albedo_color = Color("e43131")
	dice_picker_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dice_picker_outline.cull_mode = BaseMaterial3D.CULL_FRONT

func _open_dice_picker(skill: String) -> void:
	var button := d4_button if skill == MatchSkills.D4 else biohazard_button
	if button.disabled or dice_picking:
		return
	dice_picking = true
	dice_picker_skill = skill
	dice_picker_confirm.text = "确定（0/%d）" % _dice_picker_limit()
	dice_picker_confirm.disabled = true
	dice_picker_actions.show()
	_update_ui()

func _dice_picker_limit() -> int:
	return 2 if dice_picker_skill == MatchSkills.D4 else 1

func _toggle_picker_die(index: int) -> void:
	if dice_picker_selected.has(index):
		dice_picker_selected.erase(index)
		_set_picker_outline(dice[index], false)
	elif dice_picker_selected.size() < _dice_picker_limit():
		dice_picker_selected.append(index)
		_set_picker_outline(dice[index], true)
	dice_picker_confirm.text = "确定（%d/%d）" % [dice_picker_selected.size(), _dice_picker_limit()]
	dice_picker_confirm.disabled = dice_picker_selected.size() != _dice_picker_limit()
	_refresh_stage()

func _set_picker_outline(die: DiceDie3D, visible_outline: bool) -> void:
	var visual := die.get_node("_DiceVisual") as MeshInstance3D
	var outline := visual.get_node_or_null("SkillSelectionOutline") as MeshInstance3D
	if outline == null:
		if not visible_outline:
			return
		outline = MeshInstance3D.new()
		outline.name = "SkillSelectionOutline"
		outline.mesh = visual.mesh
		outline.material_override = dice_picker_outline
		outline.scale = Vector3.ONE * 1.09
		outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.add_child(outline)
	outline.visible = visible_outline

func _end_dice_selection() -> void:
	if not dice_picking:
		return
	for index in dice_picker_selected:
		_set_picker_outline(dice[index], false)
	dice_picker_selected.clear()
	dice_picking = false
	dice_picker_skill = ""
	dice_picker_actions.hide()
	_refresh_stage()

func _cancel_dice_selection() -> void:
	_end_dice_selection()
	_update_ui()

func _confirm_dice_selection() -> void:
	if not dice_picking or dice_picker_selected.size() != _dice_picker_limit():
		return
	var skill := dice_picker_skill
	var indices := dice_picker_selected.duplicate()
	_end_dice_selection()
	if skill == MatchSkills.D4:
		_use_d4(indices)
	else:
		_use_biohazard(indices[0])
	_update_ui()

func _render_d4_button(equipped: bool, spent: bool, available: bool) -> void:
	d4_button.visible = equipped
	d4_button.disabled = not available
	d4_button.text = "四面骰？ · 已使用" if spent else "四面骰？"
	if not available and dice_picker_skill == MatchSkills.D4:
		_end_dice_selection()

func _refresh_d4_button() -> void:
	_render_d4_button(skills.skill_for(player) == MatchSkills.D4, skills.used_snapshot()[player], not busy and not over and skills.can_use_d4(player, rolls))

func _use_d4(indices: Array) -> void:
	if busy or over or not skills.use_d4(player, rolls, indices).is_empty():
		return
	for index in indices:
		held[index] = false
		values[index] = 0
		D4Dice.prepare_for_roll(dice[index], index)
		parked[index] = dice[index].global_transform
	_update_ui()

func _refresh_blackout() -> void:
	var affected := skills.active_blackout()
	var notified := skills.blackout_target()
	if notified == -1 and not affected.is_empty():
		notified = player
	var message := "玩家 %d：你被黑幕了" % (notified + 1) if notified >= 0 else ""
	var available: bool = not busy and not over and scores[1 - player].has(null) and skills.can_use_blackout(player)
	_render_blackout(skills.skill_for(player) == MatchSkills.BLACKOUT, skills.used_snapshot()[player], available, affected, message)

func _render_blackout(equipped: bool, spent: bool, available: bool, affected: Array, message: String) -> void:
	blackout_button.visible = equipped
	blackout_button.disabled = not available
	blackout_button.text = "黑幕啊 · 已使用" if spent else "黑幕啊"
	blackout_notice.text = message
	blackout_notice.visible = not message.is_empty()
	blackout_indices = affected
	for i in range(dice.size()):
		dice[i].set_points_hidden(blackout_indices.has(i))

func _use_blackout() -> void:
	if busy or over or not scores[1 - player].has(null) or not skills.use_blackout(player).is_empty():
		return
	_update_ui()

func _render_biohazard_button(equipped: bool, spent: bool, available: bool) -> void:
	biohazard_button.visible = equipped
	biohazard_button.disabled = not available
	biohazard_button.text = "生化危机 · 已使用" if spent else "生化危机"
	if not available and dice_picker_skill == MatchSkills.BIOHAZARD:
		_end_dice_selection()

func _refresh_biohazard() -> void:
	var equipped := skills.skill_for(player) == MatchSkills.BIOHAZARD
	_render_biohazard_button(equipped, skills.used_snapshot()[player], not busy and not over and skills.can_use_biohazard(player, rolls))
	_apply_biohazard_view(skills.biohazard_snapshot())

func _apply_biohazard_view(state: Dictionary) -> void:
	if biohazard_view == state:
		return
	biohazard_view = state
	var mother := int(state.get("mother", -1))
	var infected: Array = state.get("infected", [])
	for i in range(dice.size()):
		var role := DiceDie3D.BiohazardRole.NONE
		if i == mother: role = DiceDie3D.BiohazardRole.MOTHER
		elif infected.has(i): role = DiceDie3D.BiohazardRole.INFECTED
		dice[i].set_biohazard_role(role)

func _use_biohazard(index: int) -> void:
	if busy or over or not skills.use_biohazard(player, rolls, index).is_empty():
		return
	dice[index].max_contacts_reported = 16
	_update_ui()

func _roll_limit() -> int:
	return skills.roll_limit()

func _scoring_values() -> Array:
	return MatchSkills.scoring_values(values, biohazard_view)

func _add_totals_row(parent: VBoxContainer, text: String, out: Array[Label], strong: bool = false) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",0)
	parent.add_child(row)
	_table_cell(row,_label(text,18,Color("dfcb91")))
	for p in range(2):
		var label := _label("0",18,Color("dfcb91"))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_table_cell(row,label,76)
		out.append(label)

func _setup_world() -> void:
	world = Node3D.new()
	stage_view.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("d3e4d9")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("f3ead5")
	env.environment.ambient_light_energy = 0.72
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -32, 0)
	light.light_energy = 1.1
	world.add_child(light)
	camera = Camera3D.new()
	camera.position = Vector3(0.55, 10, 2.5)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.9
	world.add_child(camera)
	camera.look_at(Vector3(0.55, 0, 0))
	camera.current = true
	_box_mesh(Vector3(30, 0.12, 30), Vector3(0, -0.3, 0), Color("bd8755"))
	_felt_surface()
	for side in [-1, 1]:
		_box_mesh(Vector3(5.9, 0.55, 0.22), Vector3(0, 0.275, side * 2.86), Color("374840"))
		_box_mesh(Vector3(0.22, 0.55, 5.5), Vector3(side * 2.86, 0.275, 0), Color("374840"))
	box = DiceRollBox3D.new()
	box.size = Vector3(5.5, 6, 5.5)
	box.position = Vector3(0, 3, 0)
	box.debug_visible = false
	box.gravity_strength = 20
	box.dice_friction = 0.38
	box.dice_bounce = 0.28
	box.flat_result_threshold = 0.985
	box.reroll_unflat_results = false
	world.add_child(box)
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
		die.body_entered.connect(_on_die_hit.bind(die))
		dice.append(die)
		parked.append(Transform3D.IDENTITY)

func _felt_surface() -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(5.5, 0.2, 5.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("52b584")
	material.roughness = 1.0
	var noise := FastNoiseLite.new()
	noise.frequency = 0.42
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.noise = noise
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.85, 0.85, 0.85))
	gradient.set_color(1, Color(1, 1, 1))
	texture.color_ramp = gradient
	texture.changed.connect(_refresh_stage)
	material.albedo_texture = texture
	mesh.material = material
	instance.mesh = mesh
	instance.position.y = -0.1
	world.add_child(instance)

func _box_mesh(size: Vector3, pos: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if size.x > 20:
		var grain := FastNoiseLite.new()
		grain.frequency = 0.08
		var tex := NoiseTexture2D.new()
		tex.noise = grain
		tex.seamless = true
		var ramp := Gradient.new()
		ramp.set_color(0, Color("c39165"))
		ramp.set_color(1, Color("fff2cf"))
		tex.color_ramp = ramp
		tex.changed.connect(_refresh_stage)
		material.albedo_texture = tex
		material.uv1_scale = Vector3(1, 12, 1)
	material.roughness = 0.95
	mesh.material = material
	instance.mesh = mesh
	instance.position = pos
	world.add_child(instance)

func _show_rules() -> void:
	_play("select")
	rules_dialog.popup_centered(Vector2i(600, 360))

func _confirm_new_game() -> void:
	_play("select")
	var dialog: ConfirmationDialog = get_node("NewGameConfirm")
	dialog.title = "玩家 %d 确认重新开始" % (2-player)
	dialog.dialog_text = "对方请求重新开始。不同意则保留当前对局。"
	dialog.popup_centered()

func _new_game() -> void:
	_play("select")
	_clear_victory()
	last_scored = [-1,-1]
	generation += 1
	if hold_tween != null and hold_tween.is_valid(): hold_tween.kill()
	_cancel_roll()
	scores = [[], []]
	for p in range(2):
		for i in range(12): scores[p].append(null)
	player = 0
	over = false
	skills = MatchSkills.new()
	_render_skills(skills.snapshot(), 0, true)
	_begin_turn()

func _begin_turn() -> void:
	_end_dice_selection()
	generation += 1
	_cancel_roll()
	busy = false
	rolls = 0
	values = [0, 0, 0, 0, 0]
	held = [false, false, false, false, false]
	skills.end_turn()
	skills.begin_turn(player)
	for i in range(5):
		var die := dice[i]
		die.max_contacts_reported = 4
		D4Dice.set_active(die, false)
		die.freeze = true
		die.linear_velocity = Vector3.ZERO
		die.angular_velocity = Vector3.ZERO
		die.global_transform = Transform3D(_random_basis(die), Vector3((i - 2) * 1.0, 0.41, 0))
		parked[i] = die.global_transform
	_update_ui()

func _random_basis(die: DiceDie3D) -> Basis:
	var slots := die.get_face_slots()
	var slot: StringName = slots[randi_range(0, slots.size() - 1)]
	return Basis(Vector3.UP, randi_range(0, 3) * PI * 0.5) * Basis(Quaternion(die.get_local_result_direction(slot), Vector3.UP))

func _cancel_roll() -> void:
	stack_assist.reset()
	if box == null: return
	_set_dice_contacts(false)
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

func _roll() -> void:
	if dice_picking or not skills.is_ready() or busy or over or rolls >= _roll_limit() or (rolls > 0 and held.count(true) == 5): return
	_play("roll")
	biohazard_before_roll = skills.biohazard_snapshot().infected
	busy = true
	rolls += 1
	physics_elapsed = 0
	attempts.clear()
	slow.clear()
	paused.clear()
	recovery_die = null
	var this_generation := generation
	for i in range(5):
		if not held[i]: dice[i].freeze = false
	_update_ui()
	await get_tree().physics_frame
	if generation != this_generation: return
	for i in range(5):
		if held[i]: continue
		var options := DiceRollOptions.new()
		dice[i].add_collision_exception_with(entry_wall)
		entering.append(dice[i])
		options.spawn_position = START[i]
		dice[i].global_basis = _random_basis(dice[i])
		options.randomize_rotation = false
		options.impulse = Vector3(randf_range(17.0, 20.0), randf_range(-2.0, -0.8), randf_range(-0.8, 0.8))
		box.roll(dice[i], options)
		dice[i].angular_velocity = Vector3(randf_range(-13, 13), randf_range(-13, 13), randf_range(-13, 13))

	_set_dice_contacts(true)

func _on_all_settled(_results: Dictionary) -> void:
	if stack_assist.has_stack(dice,held): return
	if not busy or over: return
	for i in range(5):
		var result := box.get_result(dice[i])
		if result == null:
			_roll_failed()
			return
		if not result.is_flat:
			_recover_one(dice[i])
			return
		values[i] = result.value
		if not held[i]: parked[i] = dice[i].global_transform
	_set_dice_contacts(false)
	for die in dice:
		die.freeze = true
		die.linear_velocity = Vector3.ZERO
		die.angular_velocity = Vector3.ZERO
	busy = false
	_update_ui()

func _roll_failed() -> void:
	_cancel_roll()
	skills.restore_infections(biohazard_before_roll)
	busy = false
	rolls = max(0, rolls - 1)
	values = [0, 0, 0, 0, 0]
	held = [false, false, false, false, false]
	for i in range(5):
		dice[i].global_transform = Transform3D(_random_basis(dice[i]), Vector3(i - 2, D4Dice.resting_height(dice[i]), 0))
		parked[i] = dice[i].global_transform
	_update_ui()
	hint.text = "有骰子未能落稳，请重新投掷。"

func _on_stage_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed: return
	if busy or over or (rolls == 0 and not dice_picking): return
	var point: Vector2 = event.position * Vector2(stage_view.size) / stage_container.size
	var origin := camera.project_ray_origin(point)
	var end := origin + camera.project_ray_normal(point) * 100
	var query := PhysicsRayQueryParameters3D.create(origin, end, 1 << 20)
	var excluded: Array[RID] = []
	for wall in box.get_node("_DiceEnvironment").get_children():
		if wall is CollisionObject3D: excluded.append(wall.get_rid())
	query.exclude = excluded
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.has("collider") and hit.collider is DiceDie3D:
		var index := dice.find(hit.collider)
		if index >= 0:
			if dice_picking:
				_toggle_picker_die(index)
			else:
				_toggle_hold(index)

func _toggle_hold(index: int) -> void:
	if dice_picking or not skills.is_ready() or busy or over or rolls == 0 or values[index] == 0: return
	_set_dice_contacts(false)
	_play("select")
	busy = true
	var die := dice[index]
	die.freeze = true
	die.linear_velocity = Vector3.ZERO
	die.angular_velocity = Vector3.ZERO
	if not held[index]:
		parked[index] = die.global_transform
		held[index] = true
	else:
		held[index] = false
	var target: Vector3 = Vector3(HOLD_X, 1.1, (index - 2) * 1.0) if held[index] else parked[index].origin
	var this_generation := generation
	_update_ui()
	hold_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	hold_tween.tween_property(die, "global_position", target, 0.30).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await hold_tween.finished
	if this_generation != generation: return
	busy = false
	_update_ui()

func _commit_score(p: int, category: int) -> void:
	if dice_picking or not skills.is_ready() or busy or over or rolls == 0 or values.has(0) or p != player or scores[p][category] != null: return
	scores[p][category] = YachtRules.score(category, _scoring_values())
	last_scored[p] = category
	_play("confirm")
	if _filled(0) == 12 and _filled(1) == 12:
		_reset_d4_dice()
		over = true
		_update_ui()
		var a := YachtRules.total(scores[0])
		var b := YachtRules.total(scores[1])
		player_label.text = "平局！" if a == b else ("玩家 1 获胜！" if a > b else "玩家 2 获胜！")
		hint.text = "对局结束 · 点击重新开始再玩一局。"
		_show_victory(-1 if a == b else (0 if a > b else 1))
		return
	player = 1 - player
	_begin_turn()

func _reset_d4_dice() -> void:
	for index in skills.d4_dice():
		var die := dice[index]
		D4Dice.set_active(die, false)
		die.global_basis = _random_basis(die)
		die.position.y = D4Dice.resting_height(die)
	skills.end_turn()

func _filled(p: int) -> int:
	var n := 0
	for score in scores[p]:
		if score != null: n += 1
	return n

func _on_icon_pressed(slot: int) -> void:
	_toggle_hold(icon_order[slot])

func _refresh_icons() -> void:
	icon_order.sort_custom(func(a, b):
		var hidden_a := blackout_indices.has(a)
		var hidden_b := blackout_indices.has(b)
		if hidden_a != hidden_b: return not hidden_a
		if hidden_a: return a < b
		return values[a] < values[b] or (values[a] == values[b] and a < b)
	)
	for slot in range(5):
		var i: int = icon_order[slot]
		var button := icons[slot]
		var concealed := blackout_indices.has(i)
		var infected: bool = biohazard_view.get("infected", []).has(i)
		var mother: bool = biohazard_view.get("mother", -1) == i
		button.disabled = dice_picking or busy or over or values[i] == 0
		button.text = "—" if values[i] == 0 and not concealed and not infected else ""
		button.icon = null
		if not concealed:
			if infected:
				button.icon = preload("res://pips/biohazard.svg")
			elif values[i] > 0:
				button.icon = load(("res://pips/biohazard-%d.svg" if mother else "res://pips/%d.svg") % values[i])
		button.tooltip_text = ("取消保留" if held[i] else "保留") + " · 骰子 %d" % (i + 1)
		var fill := Color.BLACK if concealed else (Color("f5d78b") if held[i] else Color("fffbed"))
		if not concealed and (mother or infected): fill = Color("57be70")
		var style := _flat(fill, 10, Color("906627") if held[i] else Color("b9c8b4"), 3)
		for state in ["normal","disabled","hover","pressed"]:
			button.add_theme_stylebox_override(state, style)

func _refresh_stage() -> void:
	stage_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if busy else SubViewport.UPDATE_ONCE

func _update_ui() -> void:
	if scores[0].size() != 12: return
	_refresh_stage()
	_refresh_d4_button()
	_refresh_blackout()
	_refresh_biohazard()
	_refresh_icons()
	player_label.text = "玩家 %d 的回合" % (player + 1)
	round_label.text = "第 %d / 12 回合" % min(_filled(player) + 1, 12)
	var can_score := not dice_picking and not skill_overlay.visible and not busy and not over and rolls > 0 and not values.has(0)
	var scored_values := _scoring_values()
	for p in range(2):
		for i in range(12):
			var b: Button = score_buttons[p][i]
			var committed = scores[p][i]
			b.disabled = not can_score or p != player or committed != null
			if committed != null:
				b.text = str(committed)
			elif can_score and p == player:
				b.text = str(YachtRules.score(i, scored_values))
			else:
				b.text = "—"
			_style_score_cell(b,committed != null,committed == null and can_score and p == player,last_scored[p] == i)
		subtotal_labels[p].text = "%d / 63" % YachtRules.subtotal(scores[p])
		bonus_labels[p].text = "+35" if YachtRules.subtotal(scores[p]) >= 63 else "—"
		total_labels[p].text = str(YachtRules.total(scores[p]))
	for i in range(hold_buttons.size()):
		hold_buttons[i].disabled = dice_picking or busy or over or rolls == 0
		var points := "?" if blackout_indices.has(i) else str(values[i] if values[i] > 0 else i + 1)
		hold_buttons[i].text = ("✓ " if held[i] else "骰 ") + points
	roll_button.disabled = dice_picking or skill_overlay.visible or busy or over or rolls >= _roll_limit() or (rolls > 0 and held.count(true) == 5)
	roll_button.text = "投 掷\n剩余 %d 次" % (_roll_limit() - rolls)
	if over: return
	if busy:
		hint.text = "骰子运动中……"
	elif rolls == 0:
		hint.text = "点击投掷开始本回合。"
	else:
		hint.text = "点击骰子或下方按钮保留；点击左侧分数确认。"
	var shown := PackedStringArray()
	for i in range(values.size()):
		shown.append("?" if blackout_indices.has(i) else ("☣" if biohazard_view.get("infected", []).has(i) else ("—" if values[i] == 0 else str(values[i]))))
	result_label.text = "本次点数：" + "  ".join(shown)

func _physics_process(delta: float) -> void:
	if not busy or over or rolls == 0: return
	stack_assist.step(dice,held,box,delta)
	for j in range(entering.size()-1, -1, -1):
		var incoming := entering[j]
		if incoming.position.x > -2.05:
			incoming.remove_collision_exception_with(entry_wall)
			entering.remove_at(j)
	physics_elapsed += delta
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

func _on_die_hit(body: Node, die: DiceDie3D) -> void:
	if not busy or rolls == 0: return
	if body is DiceDie3D and skills.infect_contact(dice.find(die), dice.find(body)):
		_update_ui.call_deferred()
	var now := Time.get_ticks_msec()
	if now - last_hit < 170 or die.linear_velocity.length() < 1.8: return
	last_hit = now
	hit_player.stream = sounds["hits"].pick_random()
	hit_player.pitch_scale = randf_range(0.90, 1.06)
	hit_player.play()

func _setup_audio() -> void:
	sound_player = AudioStreamPlayer.new()
	add_child(sound_player)
	sounds["select"] = preload("res://audio/dice-grab-1.ogg")
	sounds["hits"] = []
	for i in range(1,5): sounds["hits"].append(load("res://audio/die-throw-%d.ogg" % i))
	add_child(hit_player)
	hit_player.volume_db = -17
	sound_player.volume_db = -12
	sounds["roll"] = preload("res://audio/die-throw-1.ogg")
	sounds["confirm"] = preload("res://audio/score-confirm.wav")
	confirm_player = AudioStreamPlayer.new()
	confirm_player.volume_db = -10
	add_child(confirm_player)
	sounds["win"] = _tone(660.0, 0.35, 0.2, true)

func _tone(frequency: float, length: float, volume: float, chord: bool = false) -> AudioStreamWAV:
	var rate := 22050
	var count := int(length * rate)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var t := float(i) / rate
		var env := exp(-t * (10.0 if not chord else 4.0)) * minf(t * 100.0, 1.0)
		var signal_value := sin(TAU * frequency * t)
		if chord: signal_value = (signal_value + sin(TAU * frequency * 1.25 * t) + sin(TAU * frequency * 1.5 * t)) / 3.0
		data.encode_s16(i * 2, int(clampf(signal_value * env * volume, -1, 1) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream

func _play(name: String) -> void:
	if name == "confirm" and confirm_player != null:
		confirm_player.stream = sounds["confirm"]
		confirm_player.play()
		return
	if sound_player == null or not sounds.has(name): return
	sound_player.stream = sounds[name]
	sound_player.play()


func _set_dice_contacts(enabled: bool):
	for i in range(dice.size()):
		for j in range(i+1,dice.size()):
			if enabled and not held[i] and not held[j]:
				dice[i].remove_collision_exception_with(dice[j])
			else:
				dice[i].add_collision_exception_with(dice[j])


func _setup_victory():
	victory_player = AudioStreamPlayer.new()
	victory_player.stream = preload("res://room/victory_sound.gd").create()
	victory_player.volume_db = -12
	if OS.has_feature("web"): victory_player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE
	add_child(victory_player)
	victory_overlay = Control.new()
	victory_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	victory_overlay.z_index = 100
	add_child(victory_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0,0,0,0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	victory_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	victory_overlay.add_child(center)
	var panel := PanelContainer.new()
	var style := _flat(Color("345849"),20,Color("efdc9d"),2)
	style.shadow_color = Color(0,0,0,0.3)
	style.shadow_size = 14
	panel.add_theme_stylebox_override("panel",style)
	center.add_child(panel)
	var content := Control.new()
	content.custom_minimum_size = Vector2(560,240)
	panel.add_child(content)
	victory_label = _label("",62,Color("fff1c7"))
	victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	victory_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(victory_label)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size",34)
	close.add_theme_color_override("font_color",Color("efdc9d"))
	close.add_theme_color_override("font_hover_color",Color("fff1c7"))
	close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close.position = Vector2(-54,6)
	close.size = Vector2(46,46)
	close.pressed.connect(victory_overlay.hide)
	content.add_child(close)
	victory_overlay.hide()

func _show_victory(winner: int):
	if winner not in [-1,0,1]: return
	victory_label.text = "平局" if winner == -1 else "玩家 %d 胜利" % (winner+1)
	victory_overlay.show()
	if winner != -1: victory_player.play()

func _clear_victory():
	if victory_overlay != null: victory_overlay.hide()
	if victory_player != null: victory_player.stop()


func _style_score_cell(button: Button,confirmed: bool,preview: bool,recent: bool):
	var color := Color.WHITE if confirmed else Color(1,1,1,0.40 if preview else 0.25)
	for key in ["font_color","font_disabled_color","font_hover_color","font_pressed_color"]: button.add_theme_color_override(key,color)
	button.set_meta("score_state","confirmed" if confirmed else ("preview" if preview else "empty"))
	button.set_meta("recent_score",recent and confirmed)
	for state in ["normal","hover","pressed","disabled"]:
		var background := Color("47775e")
		var border := Color("4b6556")
		var width := 1
		if state == "hover":
			background = Color("3b5c4b")
			border = Color("d1b469")
		elif state == "pressed":
			background = Color("a38649")
			width = 0
		elif state == "disabled":
			background = Color("385849")
			width = 0
		if recent and confirmed:
			border = Color("efdc9d")
			width = 2
		button.add_theme_stylebox_override(state,_flat(background,5,border,width))
