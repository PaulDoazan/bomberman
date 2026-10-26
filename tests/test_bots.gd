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
	# A and B are BOMB_RADIUS apart: A sets B off, so B's cells explode at A's fuse.
	var r := int(SimConfig.BOMB_RADIUS)
	w.add_bomb(1, Vector2i(3, 3), 0.5)
	w.add_bomb(1, Vector2i(3 + r, 3), 2.0)
	var d := DangerMap.build(w)
	assert_almost(d.get(Vector2i(3 + 2 * r, 3), -1.0), 0.5, 0.001, "B-only cell takes A's fuse")
	assert_almost(d.get(Vector2i(3 - r, 3), -1.0), 0.5, 0.001, "A-only cell")
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

func _assert_never_enters_danger(w: World, brain: BotBrain, seconds: float, msg: String) -> void:
	for _t in roundi(seconds * SimConfig.TICK_RATE):
		w.step({0: brain.decide(w, 0)})
		if w.bombs.is_empty():
			return
		var c: Vector2i = w.players[0].cell()
		if DangerMap.build(w).has(c):
			assert_true(false, "%s : entre dans %s au tick %d" % [msg, str(c), w.tick])
			return

func test_seek_path_avoids_danger() -> void:
	# The only way to the block crosses a blast that is still 2 s away: the bot waits outside.
	var a := Fixtures.flat(9, 3)
	a.set_cell(Vector2i(8, 1), Arena.Tile.BLOCK, 0)
	var w := _world(a, [Vector2(0.5, 1.5)])
	w.add_bomb(1, Vector2i(4, 0), 2.0)
	assert_false(DangerMap.build(w).has(Vector2i(0, 1)), "départ hors danger")
	_assert_never_enters_danger(w, _brain(), 2.0, "seek")

func test_bot_does_not_reenter_own_blast() -> void:
	# Two-row corridor ending in two blocks. The bot bombs (13, 0) and flees left; its next goal,
	# (12, 1) beside the block (13, 1), lies inside the blast. It must wait outside instead of
	# ping-ponging back in. A far long-fused bomb takes its second bomb slot.
	var a := Fixtures.flat(14, 2)
	a.set_cell(Vector2i(13, 0), Arena.Tile.BLOCK, 0)
	a.set_cell(Vector2i(13, 1), Arena.Tile.BLOCK, 0)
	var w := _world(a, [Vector2(12.5, 0.5)])
	w.add_bomb(0, Vector2i(0, 0), 99.0)
	var brain := _brain()
	w.step({0: brain.decide(w, 0)})
	assert_eq(w.bombs.size(), 2, "bombe posée")
	var bomb := w.bomb_at(Vector2i(12, 0))
	var blast := Explosion.hit_cells(a, bomb.cell, SimConfig.BOMB_RADIUS)
	var left := false
	for _t in roundi(SimConfig.FUSE * SimConfig.TICK_RATE):
		w.step({0: brain.decide(w, 0)})
		if not w.bombs.has(bomb.id):
			break
		var inside: bool = w.players[0].cell() in blast
		if not inside:
			left = true
		elif left:
			assert_true(false, "revient dans le souffle au tick %d" % w.tick)
			break
	assert_true(left, "a quitté le souffle")
	assert_eq(w.players[0].lives, 3, "survit")

func test_flee_prefers_cells_above_next_water_step() -> void:
	# Ground x 0-3 (h2 0), stair x 4 (h2 1), upper floor x 5-12 (h2 2). Water phase, water at -1,
	# next step 1 is 19 s away: dodging down the stair would strand the bot below the next step.
	var a := Fixtures.flat(13, 7)
	for y in 7:
		a.set_cell(Vector2i(4, y), Arena.Tile.STAIRS, 1, Arena.Axis.X)
		for x in range(5, 13):
			a.set_cell(Vector2i(x, y), Arena.Tile.FLOOR, 2)
	var w := _world(a, [Vector2(5.5, 3.5)], 1.0)
	_go_water_phase(w)
	w.add_bomb(1, Vector2i(6, 3), SimConfig.FUSE)
	var i := _brain().decide(w, 0)
	assert_true(i.moving, "fuit")
	assert_true(i.target.x > 5.0, "fuit en restant en haut (cible %s)" % str(i.target))

func _go_water_phase(w: World) -> void:
	while w.water_h2 < -1:
		w.step({})
	assert_true(w.time_left <= 0.0 and not w.water_warning, "phase d'eau hors alerte")

# Heading reversals (dot < -0.5 with the previous tick's movement) over moving ticks, all seats bots.
func _reversal_rate(seed_v: int, seconds: float) -> float:
	var cfg := SimConfig.new()
	cfg.bot_count = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var ms := MatchState.new(cfg, rng)
	var brains: Dictionary = {}
	for mp in ms.players:
		brains[mp.id] = BotBrain.new(rng)
	var prev_pos: Dictionary = {}
	var prev_dir: Dictionary = {}
	var moving := 0
	var reversals := 0
	for _t in roundi(seconds * SimConfig.TICK_RATE):
		var w := ms.world
		var intents: Dictionary = {}
		for id: int in w.players:
			intents[id] = brains[id].decide(w, id)
		ms.step(intents)
		for p: PlayerState in w.players.values():
			if p.life != PlayerState.Life.ALIVE:
				prev_pos.erase(p.id)
				prev_dir.erase(p.id)
				continue
			if prev_pos.has(p.id):
				var d: Vector2 = p.pos - prev_pos[p.id]
				if d.length() > 1e-4:
					d = d.normalized()
					moving += 1
					if prev_dir.has(p.id) and d.dot(prev_dir[p.id]) < -0.5:
						reversals += 1
					prev_dir[p.id] = d
			prev_pos[p.id] = p.pos
	return float(reversals) / maxi(1, moving)

func test_bot_heading_reversals_stay_low() -> void:
	var rate := _reversal_rate(42, 60.0)
	print("       heading reversals: %.1f %%" % (rate * 100.0))
	assert_true(rate < 0.08, "demi-tours < 8 %% (obtenu %.1f %%)" % (rate * 100.0))

# Seeded 4-bot rounds: how many living players drown when the water reaches h2 3 (floods level 1).
func test_bots_survive_level_one_flood() -> void:
	var alive := 0
	var drowned := 0
	for seed_v in [7, 8, 9]:
		var cfg := SimConfig.new()
		cfg.bot_count = 3
		cfg.round_time = 30.0
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		var ms := MatchState.new(cfg, rng)
		var brains: Dictionary = {}
		for mp in ms.players:
			brains[mp.id] = BotBrain.new(rng)
		var w := ms.world
		while not w.finished and w.water_h2 < 3:
			var intents: Dictionary = {}
			for id: int in w.players:
				intents[id] = brains[id].decide(w, id)
			var before := 0
			for p: PlayerState in w.players.values():
				if p.life == PlayerState.Life.ALIVE:
					before += 1
			ms.step(intents)
			if w.water_h2 == 3:
				alive += before
				for e: Dictionary in w.events:
					if e["type"] == "death" and e["cause"] == "drown":
						drowned += 1
	print("       level-1 flood: %d drowned of %d alive" % [drowned, alive])
	assert_true(alive > 0, "des joueurs vivants avant la montée")
	assert_true(drowned * 4 <= alive, "au plus un quart noyé (%d / %d)" % [drowned, alive])
