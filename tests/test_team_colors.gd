extends TestCase

func _hue(c: Color) -> float:
	return c.h

func _hue_gap(a: float, b: float) -> float:
	var d := absf(a - b)
	return minf(d, 1.0 - d)

func _rgb_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

func test_first_member_gets_base() -> void:
	for i in TeamColors.BASES.size():
		assert_eq(TeamColors.tint(i, 0, 12), TeamColors.BASES[i], "base %d" % i)

func test_tints_are_distinct() -> void:
	for i in TeamColors.BASES.size():
		for a in 12:
			for b in range(a + 1, 12):
				var d := _rgb_distance(TeamColors.tint(i, a, 12), TeamColors.tint(i, b, 12))
				assert_true(d >= 0.06, "base %d, membres %d et %d : écart %f" % [i, a, b, d])

func test_hue_stays_close_to_base() -> void:
	for i in TeamColors.BASES.size():
		var base_hue := _hue(TeamColors.BASES[i])
		for m in 12:
			var gap := _hue_gap(_hue(TeamColors.tint(i, m, 12)), base_hue)
			assert_true(gap <= 0.04, "base %d, membre %d : écart de teinte %f" % [i, m, gap])

func test_tint_is_closest_to_its_own_base() -> void:
	for i in TeamColors.BASES.size():
		for m in 12:
			var t := TeamColors.tint(i, m, 12)
			var own := _rgb_distance(t, TeamColors.BASES[i])
			for j in TeamColors.BASES.size():
				if j == i:
					continue
				assert_true(own < _rgb_distance(t, TeamColors.BASES[j]),
					"base %d, membre %d plus proche de la base %d" % [i, m, j])

func test_free_index() -> void:
	assert_eq(TeamColors.free_index([0, 2]), 1)
	assert_eq(TeamColors.free_index([0, 1, 2, 3]), -1)
	assert_eq(TeamColors.free_index([]), 0)
