extends RefCounted

const Rules = preload("res://rules.gd")
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
	if seat != current_player: return "尚未轮到您，只能观看。"
	if busy: return "骰子尚未停止，请稍候。"
	if kind == "roll":
		if rolls >= 3: return "本回合最多投掷三次。"
		if held.count(true) == 5: return "五颗骰子都已保留，请取消保留或记分。"
		rolls += 1
		busy = true
	elif kind == "hold":
		if rolls == 0 or values.has(0): return "请先完成一次投掷。"
		var index: int = data.index
		if held[index] == data.held: return "保留状态没有变化。"
		held[index] = data.held
	elif kind == "commit_score":
		if rolls == 0 or values.has(0): return "请先完成一次投掷。"
		var category: int = data.category
		if scores[seat][category] != null: return "该计分项目已填写。"
		scores[seat][category] = Rules.score(category,values)
		last_scored[seat] = category
		score_revision += 1
		if scores[0].count(null) == 0 and scores[1].count(null) == 0:
			over = true
		else:
			current_player = 1-current_player
			turn_id += 1
			rolls = 0
			held = [false,false,false,false,false]
			values = [0,0,0,0,0]
	return ""

func finish_roll(result: Dictionary):
	busy = false
	if result.ok:
		for die in result.dice: values[int(die.id)] = int(die.value)
	else:
		rolls = maxi(0,rolls-1)

func snapshot() -> Dictionary:
	var previews := []
	for category in range(12): previews.append(Rules.score(category,values) if rolls > 0 and not busy and not values.has(0) else null)
	var totals := [Rules.total(scores[0]),Rules.total(scores[1])]
	return {"last_scored":last_scored.duplicate(),"score_revision":score_revision,"current_player":current_player,"turn_id":turn_id,"rolls":rolls,"held":held.duplicate(),"values":values.duplicate(),"busy":busy,"over":over,"scores":scores.duplicate(true),"categories":Rules.CATEGORIES,"previews":previews,"totals":totals,"winner":(-1 if totals[0] == totals[1] else (0 if totals[0]>totals[1] else 1)) if over else null}
