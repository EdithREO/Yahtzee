extends "res://game.gd"

var samples := []
var current_roll := ""
var last_seq := -1
var clock_ms := 0.0
var buffer_ms := 150.0
var playhead := 0.0
var final_applied := false
var displayed := false
var metric_elapsed := 0.0
var frame_times := []
var played_hit_id := 0
var heard_score_event := -1

func _ready():
	_setup_theme()
	_setup_audio()
	# Sample playback avoids main-thread mixer latency in single-threaded Web.
	if OS.has_feature("web"):
		sound_player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE
		hit_player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE
		confirm_player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE
	_setup_ui()
	_setup_world()
	_setup_victory()
	get_node("NewGameConfirm").canceled.connect(func():
		if restart_requester != ui_seat: _intent("restart_reply",0))
	box.set_physics_process(false)
	for i in range(5):
		dice[i].freeze = true
		dice[i].collision_layer = 1 << 20
		dice[i].collision_mask = 0
		dice[i].set_physics_process(false)
	if OS.has_feature("web"): JavaScriptBridge.eval("window.parent.yachtViewerReady=true",true)

func _process(delta):
	if not OS.has_feature("web"): return
	clock_ms += delta*1000
	var raw = JavaScriptBridge.eval("JSON.stringify(window.parent.yachtConsume())",true)
	var data = JSON.parse_string(str(raw))
	if data is Dictionary:
		clock_ms = data.now_ms
		buffer_ms = data.buffer_ms
		for packet in data.packets: _receive(packet)
		if data.has("ui"): _apply_ui(data.ui)
	if not samples.is_empty():
		playhead = clock_ms-buffer_ms
		if playhead < samples[0].server_ms: return
		while samples.size() > 1 and samples[1].server_ms <= playhead: samples.pop_front()
		var a: Dictionary = samples[0]
		var b: Dictionary = samples[1] if samples.size()>1 else a
		var alpha := clampf((playhead-a.server_ms)/maxf(1,b.server_ms-a.server_ms),0,1)
		for i in range(5):
			D4Dice.set_active(dice[i], a.dice[i].get("d4", false))
			var pa: Array = a.dice[i].position
			var pb: Array = b.dice[i].position
			var qa: Array = a.dice[i].rotation
			var qb: Array = b.dice[i].rotation
			dice[i].global_position = Vector3(pa[0],pa[1],pa[2]).lerp(Vector3(pb[0],pb[1],pb[2]),alpha)
			dice[i].global_basis = Basis(Quaternion(qa[0],qa[1],qa[2],qa[3]).normalized().slerp(Quaternion(qb[0],qb[1],qb[2],qb[3]).normalized(),alpha))
		_apply_biohazard_view(a.get("biohazard", {}))
		if not displayed:
			displayed = true
			if not a.get("ended",false): _play("roll")
			else: played_hit_id = int(a.get("audio_hit_id",0))
			_report({"first_display":true,"roll_id":current_roll})
		_play_sample_hit(a)
		if a.get("ended",false) and not final_applied:
			final_applied = true
			var rendered_values := []
			var max_error := 0.0
			var actual_poses := []
			for i in range(5):
				rendered_values.append(a.dice[i].value)
				var result := box.get_result(dice[i])
				if result.value != a.dice[i].value: max_error += 1
				var p := dice[i].global_position
				var q := dice[i].global_basis.get_rotation_quaternion()
				actual_poses.append({"id":i,"position":[p.x,p.y,p.z],"rotation":[q.x,q.y,q.z,q.w]})
			_report({"final":true,"roll_id":current_roll,"values":rendered_values,"face_mismatches":max_error,"poses":actual_poses,"last_seq":last_seq})
	frame_times.append(delta*1000)
	if frame_times.size()>240: frame_times.pop_front()
	metric_elapsed += delta
	if metric_elapsed >= 1:
		metric_elapsed = 0
		var sorted := frame_times.duplicate()
		sorted.sort()
		_report({"roll_id":current_roll,"fps":Engine.get_frames_per_second(),"frame_ms_mean":frame_times.reduce(func(a,b):return a+b,0.0)/max(1,frame_times.size()),"frame_ms_p95":sorted[int((sorted.size()-1)*0.95)],"playhead_ms":playhead,"finished":final_applied})

func _receive(packet: Dictionary):
	if packet.get("type") == "roll_started" and hold_tween != null and hold_tween.is_valid(): hold_tween.kill()
	if packet.get("type") == "board_state":
		if packet.get("animate",false): _play("select")
		samples.clear()
		current_roll = ""
		last_seq = -1
		final_applied = false
		displayed = false
		for pose in packet.state.dice:
			var p: Array = pose.position
			var q: Array = pose.rotation
			var die := dice[int(pose.id)]
			D4Dice.set_active(die, pose.get("d4", false))
			die.global_basis = Basis(Quaternion(q[0],q[1],q[2],q[3]).normalized())
			if packet.get("animate",false) and int(pose.id) == int(packet.index):
				if hold_tween != null and hold_tween.is_valid(): hold_tween.kill()
				hold_tween = create_tween()
				hold_tween.tween_property(die,"global_position",Vector3(p[0],p[1],p[2]),0.3)
			else: die.global_position = Vector3(p[0],p[1],p[2])
		_apply_biohazard_view(packet.state.get("biohazard", {}))
		return
	if packet.get("type") == "reset":
		samples.clear()
		current_roll = ""
		last_seq = -1
		return
	if packet.get("type") == "roll_started":
		samples.clear()
		current_roll = packet.roll_id
		last_seq = -1
		final_applied = false
		displayed = false
		played_hit_id = 0
		return
	var state: Dictionary = packet.state if packet.type == "roll_state" else packet.result
	if state.roll_id != current_roll:
		samples.clear()
		current_roll = state.roll_id
		last_seq = -1
		final_applied = false
		displayed = false
		played_hit_id = 0
	if state.seq <= last_seq: return
	last_seq = state.seq
	if not state.get("ok",true):
		_report({"failed":true,"roll_id":current_roll})
		return
	samples.append(state)
	if samples.size()>120: samples.pop_front()

func _play_sample_hit(state: Dictionary):
	var hit_id := int(state.get("audio_hit_id",0))
	if hit_id <= played_hit_id: return
	played_hit_id = hit_id
	# Both peers select the same existing clip/pitch at the sampled playback time.
	hit_player.stream = sounds["hits"][(hit_id-1)%sounds["hits"].size()]
	hit_player.pitch_scale = 0.90 + float(hit_id%9)*0.02
	hit_player.play()

func _report(data: Dictionary):
	JavaScriptBridge.eval("window.parent.yachtReport("+JSON.stringify(data)+")",true)

func _refresh_stage():
	if stage_view: stage_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _on_all_settled(_results): pass
func _on_die_settled(_result): pass
func _on_die_hit(_body,_die): pass

var ui_can_act := false
var ui_seat := -1
var d4_equipped := false
var d4_spent := false
var match_view_state: Dictionary = {}
var restart_requester := -1
var last_ui := ""
func _physics_process(_delta): pass
func _apply_ui(ui: Dictionary):
	var signature := JSON.stringify(ui)
	if signature == last_ui: return
	last_ui = signature
	var score_event := int(ui.get("score_sound_event",0))
	if heard_score_event >= 0 and score_event > heard_score_event: _play("confirm")
	heard_score_event = score_event
	ui_seat = int(ui.seat)
	ui_can_act = ui.can_act
	var g = ui.game
	if not g is Dictionary:
		_render_skills([], -1, false)
		_render_d4_button(false, false, false)
		match_view_state = {}
		_render_blackout(false, false, false, [], "")
		_render_biohazard_button(false, false, false)
		_render_rescue(false, false, false, false, 0, -1)
		_apply_biohazard_view({})
		_clear_victory()
		over = false
		return
	last_scored = g.get("last_scored",[-1,-1]).duplicate()
	match_view_state = g
	_render_skills(g.get("selected_skills", []), ui_seat, ui.get("can_select_skill", false))
	d4_equipped = ui_seat in [0, 1] and g.get("selected_skills", ["", ""])[ui_seat] == MatchSkills.D4
	d4_spent = d4_equipped and g.get("skill_used", [false, false])[ui_seat]
	player = int(g.current_player)
	rolls = int(g.rolls)
	held = g.held.duplicate()
	values = g.values.map(func(x):return int(x))
	scores = g.scores.map(func(row):return row.map(func(x):return null if x == null else int(x)))
	busy = g.busy or ui.rolling or ui.pending
	var just_finished: bool = g.over and not over
	over = g.over
	if just_finished: _show_victory(int(g.winner))
	elif not over: _clear_victory()
	super._update_ui()
	if over: player_label.text = victory_label.text
	roll_button.disabled = roll_button.disabled or not ui_can_act
	for icon in icons: icon.disabled = icon.disabled or not ui_can_act
	for p in range(2):
		for i in range(12): score_buttons[p][i].disabled = score_buttons[p][i].disabled or not ui_can_act or p != ui_seat
	var request = ui.get("restart",null)
	var dialog: ConfirmationDialog = get_node("NewGameConfirm")
	if request == null:
		restart_requester = -1
		dialog.hide()
	elif restart_requester != int(request):
		restart_requester = int(request)
		dialog.title = "等待对方确认" if restart_requester == ui_seat else "重新开始请求"
		dialog.dialog_text = "已向对方发出请求。" if restart_requester == ui_seat else "对方请求重新开始，是否同意？"
		dialog.get_ok_button().visible = restart_requester != ui_seat
		dialog.get_cancel_button().visible = restart_requester != ui_seat
		dialog.popup_centered()
	if ui.get("error","") != "":
		var alert := AcceptDialog.new()
		alert.dialog_text = ui.error
		add_child(alert)
		alert.popup_centered()
		alert.confirmed.connect(alert.queue_free)
func _intent(kind: String,index: int = -1):
	if kind in ["restart_request","restart_reply"]: _play("select")
	if OS.has_feature("web"): JavaScriptBridge.eval("window.parent.yachtUiAction("+JSON.stringify(kind)+","+str(index)+")",true)
func _choose_skill(skill_id: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.parent.yachtUiAction('select_skill',"+JSON.stringify(skill_id)+")",true)
func _refresh_d4_button() -> void:
	_render_d4_button(d4_equipped, d4_spent, d4_equipped and not d4_spent and ui_can_act and rolls < 3)
func _use_d4(indices: Array) -> void:
	if OS.has_feature("web") and not d4_button.disabled:
		JavaScriptBridge.eval("window.parent.yachtUiAction('use_d4',"+JSON.stringify(indices)+")",true)
func _refresh_blackout() -> void:
	var affected: Array = match_view_state.get("blackout_dice", [])
	var equipped: bool = ui_seat in [0, 1] and match_view_state.get("selected_skills", ["", ""])[ui_seat] == MatchSkills.BLACKOUT
	var spent: bool = equipped and match_view_state.get("skill_used", [false, false])[ui_seat]
	var warned: bool = ui_seat in [0, 1] and (match_view_state.get("blackout_target", -1) == ui_seat or (player == ui_seat and not affected.is_empty()))
	_render_blackout(equipped, spent, equipped and not spent and ui_can_act and scores[1 - ui_seat].has(null), affected, "你被黑幕了" if warned else "")
func _use_blackout() -> void:
	if not blackout_button.disabled:
		_intent("use_blackout")
func _refresh_biohazard() -> void:
	var equipped: bool = ui_seat in [0, 1] and match_view_state.get("selected_skills", ["", ""])[ui_seat] == MatchSkills.BIOHAZARD
	var spent: bool = equipped and match_view_state.get("skill_used", [false, false])[ui_seat]
	_render_biohazard_button(equipped, spent, equipped and not spent and ui_can_act and rolls < 2)
	if samples.is_empty():
		_apply_biohazard_view(match_view_state.get("biohazard", {}))
func _use_biohazard(index: int) -> void:
	if not biohazard_button.disabled:
		_intent("use_biohazard", index)
func _roll_limit() -> int:
	return int(match_view_state.get("roll_limit", 3))
func _scoring_values() -> Array:
	return MatchSkills.scoring_values(values, match_view_state.get("biohazard", {}), int(match_view_state.get("rescue_value", 0)), int(match_view_state.get("rescue_discard", -1)))
func _refresh_rescue() -> void:
	var equipped: bool = ui_seat in [0, 1] and match_view_state.get("selected_skills", ["", ""])[ui_seat] == MatchSkills.RESCUE
	var spent: bool = equipped and match_view_state.get("skill_used", [false, false])[ui_seat]
	var can_act := ui_can_act and rolls > 0 and not values.has(0)
	var can_record := equipped and not spent and can_act and _filled(ui_seat) < 11
	_render_rescue(equipped, spent, can_record, can_act, int(match_view_state.get("rescue_value", 0)), int(match_view_state.get("rescue_discard", -1)))
func _use_rescue(index: int) -> void:
	if not rescue_button.disabled:
		_intent("use_rescue", index)
func _discard_for_rescue(index: int) -> void:
	if not rescue_discard_button.disabled:
		_intent(PICK_RESCUE_DISCARD, index)
func _roll():
	if ui_can_act and not dice_picking: _intent("roll")
func _toggle_hold(index: int):
	if ui_can_act and not dice_picking and rolls>0 and values[index] != 0 and not busy: _intent("hold",index)
func _commit_score(p: int,category: int):
	if ui_can_act and not dice_picking and p == ui_seat: _intent("commit_score",category)
func _on_stage_input(event: InputEvent):
	if ui_can_act: super._on_stage_input(event)
func _show_rules(): super._show_rules()
func _confirm_new_game(): _intent("restart_request")
func _new_game(): _intent("restart_reply",1)

