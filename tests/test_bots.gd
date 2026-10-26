extends TestCase

# Players are placed at the given centres; player 0 is the bot under test.
func _world(a: Arena, positions: Array[Vector2], round_time := 100.0) -> World:
	var ids: Array[int] = []
	for i in positions.size():
		ids.append(i)
	var cfg := SimConfig.new()
	cfg.round_time = round_time
	var w := World.new(a, ids, cfg, RandomNumberGenerator.new())
	for i in positions.size():
		w.players[i].pos = positions[i]
	return w

func _brain() -> BotBrain:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	return BotBrain.new(rng)

func _run_bot(w: World, brain: BotBrain, seconds: float) -> void:
	for _t in roundi(seconds * SimConfig.TICK_RATE):
		w.step({0: brain.decide(w, 0)})

func test_danger_map_chain_takes_shortest_fuse() -> void:
	var w := _world(Fixtures.flat(11, 7), [Vector2(0.5, 0.5)])
	w.add_bomb(1, Vector2i(3, 3), 0.5)
	w.add_bomb(1, Vector2i(5, 3), 2.0)
	var d := DangerMap.build(w)
	assert_almost(d.get(Vector2i(8, 3), -1.0), 0.5, 0.001, "B-only cell takes A's fuse")
	assert_almost(d.get(Vector2i(0, 3), -1.0), 0.5, 0.001, "A-only cell")
	assert_false(d.has(Vector2i(10, 0)), "far cell is safe")

func test_danger_map_extra_bomb_and_explosions() -> void:
	var w := _world(Fixtures.flat(11, 7), [Vector2(0.5, 0.5)])
	var e := Explosion.new()
	e.cells = [Vector2i(9, 5)]
	w.explosions.append(e)
	var d := DangerMap.build(w, Vector2i(5, 3))
	assert_almost(d.get(Vector2i(5, 3), -1.0), SimConfig.FUSE, 0.001, "extra bomb fuse")
	assert_almost(d.get(Vector2i(9, 5), -1.0), 0.0, 0.001, "active explosion")

func test_bot_flees_bomb() -> void:
	var w := _world(Fixtures.flat(9, 9), [Vector2(4.5, 4.5), Vector2(8.5, 8.5)])
	w.add_bomb(1, Vector2i(5, 4), 1.5)
	_run_bot(w, _brain(), 2.0)
	assert_eq(w.players[0].lives, 3, "bot survived")

func test_bot_bombs_block_when_escape_exists() -> void:
	var a := Fixtures.flat(9, 9)
	a.set_cell(Vector2i(2, 1), Arena.Tile.BLOCK, 0)
	var w := _world(a, [Vector2(1.5, 1.5)])
	assert_true(_brain().decide(w, 0).place_bomb, "bombs the block")

func test_bot_does_not_bomb_in_dead_end() -> void:
	var a := Fixtures.flat(9, 9)
	a.set_cell(Vector2i(0, 1), Arena.Tile.PILLAR, 0)
	a.set_cell(Vector2i(1, 0), Arena.Tile.PILLAR, 0)
	a.set_cell(Vector2i(1, 2), Arena.Tile.PILLAR, 0)
	a.set_cell(Vector2i(2, 1), Arena.Tile.BLOCK, 0)
	var w := _world(a, [Vector2(1.5, 1.5)])
	assert_false(_brain().decide(w, 0).place_bomb, "no escape, no bomb")

func test_bot_climbs_when_water_warns() -> void:
	var a := Fixtures.flat(9, 5)
	for y in 5:
		a.set_cell(Vector2i(4, y), Arena.Tile.STAIRS, 1, Arena.Axis.X)
		for x in range(5, 9):
			a.set_cell(Vector2i(x, y), Arena.Tile.FLOOR, 2)
	# The warning is naturally on from t = 0 when the first rise is 2 s away.
	var w := _world(a, [Vector2(1.5, 2.5)], 2.0)
	_run_bot(w, _brain(), 4.0)
	assert_true(a.h2_at(w.players[0].cell()) >= 2, "bot reached the upper level")

func test_ghost_bot_heads_to_nearest_living() -> void:
	var w := _world(Fixtures.flat(9, 9), [Vector2(0.5, 0.5), Vector2(2.5, 0.5), Vector2(8.5, 8.5)])
	var g: PlayerState = w.players[0]
	g.life = PlayerState.Life.GHOST
	g.lives = 0
	var i := _brain().decide(w, 0)
	assert_true(i.moving, "ghost moves")
	assert_true(i.target.distance_to(Vector2(2.5, 0.5)) < 0.5, "towards nearest living")

func test_trapped_bot_returns_intent() -> void:
	var a := Fixtures.flat(9, 9)
	for c in [Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 0), Vector2i(1, 2)]:
		a.set_cell(c, Arena.Tile.PILLAR, 0)
	var w := _world(a, [Vector2(1.5, 1.5)])
	w.add_bomb(0, Vector2i(1, 1), 2.0)
	var i := _brain().decide(w, 0)
	assert_true(i != null, "intent returned")
	assert_false(i.place_bomb, "no suicidal bomb")

func test_bot_performance_nine_bots() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var a := MapGen.generate(Vector2i(31, 23), 10, rng)
	var ids: Array[int] = []
	for i in 10:
		ids.append(i)
	var w := World.new(a, ids, SimConfig.new(), rng)
	for i in 6:
		w.add_bomb(i, a.spawns[i], 2.0)
	var brains: Array[BotBrain] = []
	for i in 9:
		brains.append(BotBrain.new(rng))
	var t0 := Time.get_ticks_msec()
	for _n in 30:
		for i in 9:
			brains[i].decide(w, i + 1)
	var ms := Time.get_ticks_msec() - t0
	print("       270 decides: %d ms" % ms)
	assert_true(ms < 1000, "270 decides under 1000 ms (took %d)" % ms)
