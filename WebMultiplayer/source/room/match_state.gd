extends RefCounted

const Rules = preload("res://rules.gd")
const MatchSkills = preload("res://match_skills.gd")
var skills := MatchSkills.new()
var current_player := 0
var turn_id := 1
var rolls := 0
var held := [false,false,false,false,false]
var values := [0,0,0,0,0]
var scores := [[],[]]
var busy := false
var over := false
var last_scored := [-1,-1]
var score_revision := 0

func _init(first_player: int):
	current_player = first_player
	for p in range(2): scores[p].resize(12)

func operate(kind: String, seat: int, data: Dictionary) -> String:
	if over: return "对局已结束。"
	if int(data.get("turn_id",-1)) != turn_id: return "回合已变化，请使用最新状态。"
	if kind == "select_skill": return skills.select_skill(seat, data.skill_id)
	if not skills.is_ready(): return "请等待两位玩家选好技能。"
	if seat != current_player: return "尚未轮到您，只能观看。"
	if busy: return "骰子尚未停止，请稍候。"
	if kind == "use_d4":
		var error := skills.use_d4(seat, rolls, data.indices)
		if not error.is_empty(): return error
		for index in skills.d4_dice():
			held[index] = false
			values[index] = 0
	elif kind == "use_blackout":
		if not scores[1 - seat].has(null): return "对方没有下一回合。"
		return skills.use_blackout(seat)
	elif kind == "use_biohazard":
		return skills.use_biohazard(seat, rolls, int(data.index))
	elif kind == "use_rescue":
		if rolls == 0 or values.has(0): return "请先完成一次投掷。"
		if scores[seat].count(null) <= 1: return "本局已没有你的下一回合。"
		return skills.use_rescue(seat, values[int(data.index)])
	elif kind == "set_rescue_discard":
		if rolls == 0 or values.has(0): return "请先完成一次投掷。"
		return skills.discard_for_rescue(int(data.index))
	elif kind == "roll":
		if rolls >= skills.roll_limit(): return "本回合最多投掷 %d 次。" % skills.roll_limit()
		if held.count(true) == 5: return "五颗骰子都已保留，请取消保留或记分。"
		rolls += 1
		busy = true
	elif kind == "hold":
		if rolls == 0 or values[int(data.index)] == 0: return "请先掷出这颗骰子的点数。"
		var index: int = data.index
		if held[index] == data.held: return "保留状态没有变化。"
		held[index] = data.held
	elif kind == "commit_score":
		if rolls == 0 or values.has(0): return "请先完成一次投掷。"
		var category: int = data.category
		if scores[seat][category] != null: return "该计分项目已填写。"
		var scored_values := MatchSkills.scoring_values(values, skills.biohazard_snapshot(), skills.rescue_value, skills.rescue_discard)
		if scored_values.is_empty(): return "请选择一颗骰子不参与计分。"
		scores[seat][category] = Rules.score(category, scored_values)
		last_scored[seat] = category
		score_revision += 1
		skills.end_turn()
		if scores[0].count(null) == 0 and scores[1].count(null) == 0:
			over = true
		else:
			current_player = 1-current_player
			skills.begin_turn(current_player)
			turn_id += 1
			rolls = 0
			held = [false,false,false,false,false]
			values = [0,0,0,0,0]
	return ""

func finish_roll(result: Dictionary):
	busy = false
	if result.ok:
		for die in result.dice: values[int(die.id)] = int(die.value)
		skills.rescue_discard = -1
	else:
		rolls = maxi(0,rolls-1)

func snapshot() -> Dictionary:
	var previews := []
	var biohazard := skills.biohazard_snapshot()
	var scored_values := MatchSkills.scoring_values(values, biohazard, skills.rescue_value, skills.rescue_discard)
	for category in range(12): previews.append(Rules.score(category,scored_values) if rolls > 0 and not busy and not values.has(0) and not scored_values.is_empty() else null)
	var totals := [Rules.total(scores[0]),Rules.total(scores[1])]
	return {
		"selected_skills": skills.snapshot(),
		"skills_ready": skills.is_ready(),
		"skill_used": skills.used_snapshot(),
		"blackout_target": skills.blackout_target(),
		"blackout_dice": skills.active_blackout(),
		"biohazard": biohazard,
		"rescue_value": skills.rescue_value,
		"rescue_discard": skills.rescue_discard,
		"last_scored": last_scored.duplicate(),
		"score_revision": score_revision,
		"current_player": current_player,
		"turn_id": turn_id,
		"rolls": rolls,
		"roll_limit": skills.roll_limit(),
		"held": held.duplicate(),
		"values": values.duplicate(),
		"busy": busy,
		"over": over,
		"scores": scores.duplicate(true),
		"categories": Rules.CATEGORIES,
		"previews": previews,
		"totals": totals,
		"winner": (-1 if totals[0] == totals[1] else (0 if totals[0] > totals[1] else 1)) if over else null,
	}
