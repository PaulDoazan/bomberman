extends TestCase

func test_defaults_match_spec() -> void:
	var c := SimConfig.new()
	assert_eq(c.lives, 3)
	assert_eq(c.round_time, 120.0)
	assert_eq(c.grid_size(), Vector2i(23, 15))
	assert_eq(c.player_count(), c.bot_count + 1)
	assert_eq(SimConfig.PLAYER_COLORS.size(), 10)

func test_all_map_sizes_are_odd() -> void:
	for k in SimConfig.MAP_SIZES:
		var s: Vector2i = SimConfig.MAP_SIZES[k]
		assert_true(s.x % 2 == 1 and s.y % 2 == 1, k)
