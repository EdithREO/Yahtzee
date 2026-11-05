extends SceneTree

func _initialize():
	var Rules = load("res://rules.gd")
	assert(Rules.score(8,[3,3,3,4,4]) == 17)
	assert(Rules.score(8,[3,3,3,3,3]) == 0)
	assert(Rules.score(9,[1,2,3,4,6]) == 15)
	assert(Rules.score(10,[2,3,4,5,6]) == 30)
	for first in range(2):
		var match_state = load("res://room/match_state.gd").new(first)
		for turn in range(24):
			var player: int = match_state.current_player
			assert(player == (first+turn)%2)
			assert(match_state.operate("roll",1-player,{"turn_id":match_state.turn_id}) != "")
			assert(match_state.operate("roll",player,{"turn_id":match_state.turn_id}) == "")
			var result := {"ok":true,"dice":[]}
			for i in range(5): result.dice.append({"id":i,"value":i+1})
			match_state.finish_roll(result)
			assert(match_state.operate("commit_score",player,{"turn_id":match_state.turn_id,"category":turn/2}) == "")
		assert(match_state.over)
		assert(match_state.scores[0].count(null)==0 and match_state.scores[1].count(null)==0)
	print("MATCH_STATE_TEST passed: both first seats, 24 turns, existing rule scores")
	quit()
