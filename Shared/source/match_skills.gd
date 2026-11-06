extends RefCounted

const D4 := "d4"
const BLACKOUT := "blackout"
const BIOHAZARD := "biohazard"
const BIOHAZARD_INFECTION_LIMIT := 3
const CATALOG := {
	D4: {"name": "四面骰？", "description": "自己的回合投掷前，将两颗骰子换成 4、4、5、6 四面骰。\n持续到本回合结束，每局一次。"},
	BLACKOUT: {"name": "黑幕啊", "description": "自己的回合使用，随机遮住对手下一回合的三颗骰子。\n点数照常计分，每局一次。"},
	BIOHAZARD: {"name": "生化危机", "description": "点选母体，直接碰到的骰子与它同点，最多感染 3 颗。\n发动回合最多投两次，每局一次。"},
}

var _selected: Array[String] = ["", ""]
var _used: Array[bool] = [false, false]
var _d4_dice: Array[int] = []
var _blackout_target := -1
var _pending_blackout: Array[int] = []
var _active_blackout: Array[int] = []
var _biohazard_mother := -1
var _infected_dice: Array[int] = []

func select_skill(seat: int, skill_id: String) -> String:
	if seat < 0 or seat >= _selected.size():
		return "玩家座位无效。"
	if not CATALOG.has(skill_id):
		return "该技能不存在。"
	if not _selected[seat].is_empty():
		return "本局技能已锁定。"
	_selected[seat] = skill_id
	return ""

func skill_for(seat: int) -> String:
	return _selected[seat] if seat >= 0 and seat < _selected.size() else ""

func is_ready() -> bool:
	return not _selected.has("")

func snapshot() -> Array[String]:
	return _selected.duplicate()

func used_snapshot() -> Array[bool]:
	return _used.duplicate()

func can_use_d4(seat: int, rolls: int) -> bool:
	return is_ready() and skill_for(seat) == D4 and not _used[seat] and rolls < 3

func use_d4(seat: int, rolls: int, indices: Array) -> String:
	if not can_use_d4(seat, rolls):
		return "当前无法使用四面骰技能。"
	if indices.size() != 2 or not indices[0] is int or not indices[1] is int:
		return "请选择两颗骰子。"
	if indices[0] == indices[1] or indices.any(func(index): return index < 0 or index >= 5):
		return "请选择两颗不同的骰子。"
	_used[seat] = true
	_d4_dice.assign(indices)
	return ""

func d4_dice() -> Array[int]:
	return _d4_dice.duplicate()

func can_use_blackout(seat: int) -> bool:
	return is_ready() and skill_for(seat) == BLACKOUT and not _used[seat]

func use_blackout(seat: int) -> String:
	if not can_use_blackout(seat):
		return "当前无法使用黑幕啊。"
	var indices := [0, 1, 2, 3, 4]
	indices.shuffle()
	_pending_blackout.assign(indices.slice(0, 3))
	_blackout_target = 1 - seat
	_used[seat] = true
	return ""

func blackout_target() -> int:
	return _blackout_target

func active_blackout() -> Array[int]:
	return _active_blackout.duplicate()

func can_use_biohazard(seat: int, rolls: int) -> bool:
	return is_ready() and skill_for(seat) == BIOHAZARD and not _used[seat] and rolls < 2

func use_biohazard(seat: int, rolls: int, index: int) -> String:
	if not can_use_biohazard(seat, rolls):
		return "当前无法使用生化危机。"
	if index < 0 or index >= 5:
		return "请选择一颗骰子作为母体。"
	_biohazard_mother = index
	_used[seat] = true
	return ""

func roll_limit() -> int:
	return 2 if _biohazard_mother >= 0 else 3

func infect_contact(a: int, b: int) -> bool:
	if _biohazard_mother < 0 or _infected_dice.size() >= BIOHAZARD_INFECTION_LIMIT:
		return false
	var target := b if a == _biohazard_mother else (a if b == _biohazard_mother else -1)
	if target < 0 or target >= 5 or target == _biohazard_mother or _infected_dice.has(target):
		return false
	_infected_dice.append(target)
	return true

func biohazard_snapshot() -> Dictionary:
	return {"mother": _biohazard_mother, "infected": _infected_dice.duplicate()}

func restore_infections(previous: Array) -> void:
	_infected_dice.assign(previous)

static func scoring_values(values: Array, biohazard: Dictionary) -> Array:
	var mother: int = int(biohazard.get("mother", -1))
	var infected: Array = biohazard.get("infected", [])
	if mother < 0 or infected.is_empty():
		return values
	var effective := values.duplicate()
	for index in infected:
		effective[int(index)] = values[mother]
	return effective

func begin_turn(seat: int) -> void:
	if _blackout_target == seat:
		_active_blackout.assign(_pending_blackout)
		_pending_blackout.clear()
		_blackout_target = -1

func end_turn() -> void:
	_d4_dice.clear()
	_active_blackout.clear()
	_biohazard_mother = -1
	_infected_dice.clear()
