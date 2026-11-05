extends RefCounted
class_name YachtRules

const CATEGORIES := ["一 点", "二 点", "三 点", "四 点", "五 点", "六 点", "全 选", "四 条", "葫 芦", "小 顺", "大 顺", "快 艇"]

static func score(category: int, values: Array) -> int:
	var counts := [0, 0, 0, 0, 0, 0, 0]
	var total := 0
	for v in values:
		if v < 1 or v > 6: return 0
		counts[v] += 1
		total += v
	if category < 6:
		return counts[category + 1] * (category + 1)
	match category:
		6: return total
		7:
			return total if counts.max() >= 4 else 0
		8:
			return total if counts.has(3) and counts.has(2) else 0
		9:
			for start in range(1, 4):
				if counts[start] and counts[start+1] and counts[start+2] and counts[start+3]: return 15
			return 0
		10:
			return 30 if (counts[1] and counts[2] and counts[3] and counts[4] and counts[5]) or (counts[2] and counts[3] and counts[4] and counts[5] and counts[6]) else 0
		11: return 50 if counts.max() == 5 else 0
	return 0

static func subtotal(scores: Array) -> int:
	var sum := 0
	for i in range(6):
		if scores[i] != null: sum += int(scores[i])
	return sum

static func total(scores: Array) -> int:
	var sum := 0
	for value in scores:
		if value != null: sum += int(value)
	return sum + (35 if subtotal(scores) >= 63 else 0)
