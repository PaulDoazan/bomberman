extends TestCase

func _world(a: Arena, positions: Array[Vector2], lives := 3, round_time := 1.0) -> World:
	var ids: Array[int] = []
	for i in positions.size():
		ids.append(i)
	var cfg := SimConfig.new()
	cfg.round_time = round_time
	cfg.lives = lives
	var w := World.new(a, ids, cfg, RandomNumberGenerator.new())
	for i in positions.size():
		w.players[i].pos = positions[i]
	return w

func _go(w: World, seconds: float) -> void:
	for i in roundi(seconds * SimConfig.TICK_RATE):
		w.step({})

func _two_survivors() -> World:
	# Two players parked on a h2 = 6 plateau (above every water step): nobody ever drowns.
	var a := Fixtures.flat(9, 3)
	for y in 3:
		for x in 9:
			a.set_cell(Vector2i(x, y), Arena.Tile.FLOOR, 6)
	return _world(a, [Vector2(1.5, 1.5), Vector2(7.5, 1.5)])

func test_water_rises_by_steps_after_timer() -> void:
	var w := _two_survivors()
	_go(w, 0.9)
	assert_eq(w.water_h2, -3, "avant le chrono")
	_go(w, 0.2)
	assert_eq(w.water_h2, -1, "premier palier")
	_go(w, 19.8) # t = 20.9
	assert_eq(w.water_h2, -1, "pas encore le 2e")
	_go(w, 0.2) # t = 21.1
	assert_eq(w.water_h2, 1)
	_go(w, 20.0) # t = 41.1
	assert_eq(w.water_h2, 3)
	_go(w, 20.0) # t = 61.1
	assert_eq(w.water_h2, 4)
	_go(w, 30.0)
	assert_eq(w.water_h2, 4, "dernier palier")

func test_rise_emits_event() -> void:
	var w := _two_survivors()
	var seen := 0
	for i in 40:
		w.step({})
		for e: Dictionary in w.events:
			if e["type"] == "water_rise":
				seen += 1
				assert_eq(e["h2"], -1)
	assert_eq(seen, 1)

func test_warning_before_each_rise() -> void:
	var w := _two_survivors()
	_go(w, 0.5)
	assert_true(w.water_warning, "avant le premier palier")
	_go(w, 14.5) # t = 15
	assert_false(w.water_warning, "t = 15 s")
	_go(w, 3.5) # t = 18.5
	assert_true(w.water_warning, "t = 18,5 s")
	_go(w, 2.5) # t = 21 + 
	_go(w, 0.1)
	assert_false(w.water_warning, "juste après la montée")

func test_no_warning_after_last_step() -> void:
	var w := _two_survivors()
	_go(w, 62.0)
	assert_eq(w.water_h2, 4)
	assert_false(w.water_warning)

func test_submerged_player_drowns_and_respawns_on_lowest_dry_cell() -> void:
	var a := Fixtures.flat(9, 3)
	for y in 3:
		a.set_cell(Vector2i(4, y), Arena.Tile.FLOOR, 2)
		for x in range(5, 9):
			a.set_cell(Vector2i(x, y), Arena.Tile.FLOOR, 4)
	var w := _world(a, [Vector2(1.5, 1.5), Vector2(8.5, 1.5)], 3, 100.0)
	w.water_h2 = 1
	assert_true(w.is_submerged(Vector2i(1, 1)))
	assert_false(w.is_submerged(Vector2i(4, 1)))
	assert_true(w.is_submerged(Vector2i(-1, 0)), "hors grille")
	w.players[0].invulnerable_timer = 5.0 # la noyade ignore l'invulnérabilité
	w.step({})
	assert_eq(w.players[0].lives, 2)
	assert_eq(w.players[0].life, PlayerState.Life.WAITING_RESPAWN)
	_go(w, 1.8)
	assert_eq(w.players[0].life, PlayerState.Life.WAITING_RESPAWN, "pas encore")
	_go(w, 0.4)
	var p: PlayerState = w.players[0]
	assert_eq(p.life, PlayerState.Life.ALIVE)
	assert_eq(a.h2_at(p.cell()), 2, "case sèche la plus basse")
	assert_true(p.invulnerable_timer > 0.0)

func test_invulnerability_expires() -> void:
	var w := _world(Fixtures.flat(9, 3), [Vector2(1.5, 1.5), Vector2(7.5, 1.5)], 3, 100.0)
	w.players[0].invulnerable_timer = SimConfig.INVULNERABLE_TIME
	_go(w, SimConfig.INVULNERABLE_TIME - 0.2)
	assert_true(w.players[0].invulnerable_timer > 0.0)
	_go(w, 0.4)
	assert_eq(w.players[0].invulnerable_timer, 0.0)

func test_respawn_avoids_bombs_and_explosions() -> void:
	var a := Fixtures.flat(5, 1)
	for x in 5:
		a.set_cell(Vector2i(x, 0), Arena.Tile.FLOOR, 0)
	var w := _world(a, [Vector2(0.5, 0.5), Vector2(4.5, 0.5)], 3, 100.0)
	w.add_bomb(1, Vector2i(2, 0), 99.0)
	var e := Explosion.new()
	e.cells = [Vector2i(3, 0)]
	e.timer = 99.0
	w.explosions.append(e)
	var found: Variant = w.find_respawn_cell()
	assert_true(found != null)
	assert_false(found in [Vector2i(2, 0), Vector2i(3, 0)])

func test_no_dry_cell_eliminates_player() -> void:
	var w := _world(Fixtures.flat(5, 3), [Vector2(2.5, 1.5)], 3, 100.0)
	w.water_h2 = 1
	assert_true(w.find_respawn_cell() == null)
	w.step({})
	var p: PlayerState = w.players[0]
	assert_eq(p.life, PlayerState.Life.GHOST)
	assert_eq(p.lives, 0)
	_go(w, 3.0)
	assert_eq(p.life, PlayerState.Life.GHOST)

func test_no_dry_cell_at_respawn_eliminates() -> void:
	var a := Fixtures.flat(5, 3)
	for y in 3:
		a.set_cell(Vector2i(0, y), Arena.Tile.FLOOR, 3)
	var w := _world(a, [Vector2(2.5, 1.5), Vector2(0.5, 1.5)], 3, 100.0)
	w.water_h2 = 1
	w.step({}) # player 0 drowns, 1 dry cell column exists
	w.players[0].respawn_timer = 0.01
	w.water_h2 = 3 # now everything is submerged
	w.step({})
	var p: PlayerState = w.players[0]
	assert_eq(p.life, PlayerState.Life.GHOST)
	assert_eq(p.lives, 0)
	assert_eq(p.died_tick, w.tick)

func test_single_survivor_wins() -> void:
	var w := _world(Fixtures.flat(9, 3), [Vector2(1.5, 1.5), Vector2(4.5, 1.5), Vector2(7.5, 1.5)], 1, 100.0)
	w.kill(0, "test")
	w.step({})
	assert_false(w.finished)
	w.kill(2, "test")
	w.step({})
	assert_true(w.finished)
	assert_eq(w.winners, [1] as Array[int])
	var t := w.tick
	w.step({})
	assert_eq(w.tick, t, "plus rien après la fin")

func test_waiting_respawn_counts_as_alive() -> void:
	var w := _world(Fixtures.flat(9, 3), [Vector2(1.5, 1.5), Vector2(7.5, 1.5)], 3, 100.0)
	w.kill(0, "test")
	w.step({})
	assert_false(w.finished)

func test_last_players_drowning_together_are_ex_aequo() -> void:
	var a := Fixtures.flat(9, 3)
	var w := _world(a, [Vector2(1.5, 1.5), Vector2(4.5, 1.5)], 1, 100.0)
	w.water_h2 = 1
	w.step({})
	assert_true(w.finished)
	var ids: Array = w.winners.duplicate()
	ids.sort()
	assert_eq(ids, [0, 1])
