extends TestCase

# Player 0 is a ghost; the others are alive. A far-away bystander keeps the round going.
func _world(a: Arena, positions: Array[Vector2]) -> World:
	var ids: Array[int] = []
	for i in positions.size():
		ids.append(i)
	var cfg := SimConfig.new()
	cfg.round_time = 100.0
	var w := World.new(a, ids, cfg, RandomNumberGenerator.new())
	for i in positions.size():
		w.players[i].pos = positions[i]
	var g: PlayerState = w.players[0]
	g.life = PlayerState.Life.GHOST
	g.lives = 0
	return w

func _go(w: World, seconds: float, intents := {}) -> void:
	for _t in roundi(seconds * SimConfig.TICK_RATE):
		w.step(intents)

func _intent_to(t: Vector2) -> PlayerIntent:
	var i := PlayerIntent.new()
	i.moving = true
	i.target = t
	return i

func test_ghost_passes_through_pillars_and_levels() -> void:
	var a := Fixtures.flat(7, 5)
	a.set_cell(Vector2i(2, 2), Arena.Tile.PILLAR, 0)
	a.set_cell(Vector2i(3, 2), Arena.Tile.FLOOR, 2)
	var w := _world(a, [Vector2(0.5, 2.5), Vector2(0.5, 0.5), Vector2(6.5, 0.5)])
	_go(w, 1.5, {0: _intent_to(Vector2(4.5, 2.5))})
	assert_almost(w.players[0].pos.x, 4.5, 0.15, "fantôme arrivé")
	assert_eq(w.players[0].life, PlayerState.Life.GHOST)

func test_ghost_stays_in_grid() -> void:
	var w := _world(Fixtures.flat(5, 5), [Vector2(0.5, 2.5), Vector2(4.5, 0.5), Vector2(4.5, 4.5)])
	_go(w, 2.0, {0: _intent_to(Vector2(-10.0, 2.5))})
	assert_true(w.players[0].pos.x >= 0.0, "dans la grille")

func test_ghost_cannot_place_bomb() -> void:
	var w := _world(Fixtures.flat(5, 5), [Vector2(0.5, 2.5), Vector2(4.5, 0.5), Vector2(4.5, 4.5)])
	var i := PlayerIntent.new()
	i.place_bomb = true
	i.action = true
	_go(w, 0.2, {0: i})
	assert_true(w.bombs.is_empty(), "pas de bombe")

func test_ghost_immune_to_water_and_explosions() -> void:
	var w := _world(Fixtures.flat(5, 5), [Vector2(2.5, 2.5), Vector2(4.5, 0.5), Vector2(4.5, 4.5)])
	w.water_h2 = 10
	w.add_bomb(1, Vector2i(2, 2), 0.0)
	var deaths := 0
	for _t in 5:
		w.step({})
		for e: Dictionary in w.events:
			if e["type"] == "death" and e["id"] == 0:
				deaths += 1
	assert_eq(w.players[0].life, PlayerState.Life.GHOST, "toujours fantôme")
	assert_eq(deaths, 0, "aucune mort du fantôme")

func test_possession_moves_victim_with_ghost_target() -> void:
	var w := _world(Fixtures.flat(9, 5), [Vector2(2.5, 2.5), Vector2(2.5, 2.5), Vector2(8.5, 0.5)])
	var victim_intent := _intent_to(Vector2(0.5, 2.5))
	_go(w, 1.0, {0: _intent_to(Vector2(6.5, 2.5)), 1: victim_intent})
	assert_eq(w.players[1].possessed_by, 0, "possédé")
	assert_eq(w.players[0].possess_target, 1)
	assert_true(w.players[1].pos.x > 3.0, "la victime suit le fantôme")
	assert_almost(w.players[0].pos.x, w.players[1].pos.x, 0.001, "fantôme collé")

func test_possession_victim_cannot_place_bomb() -> void:
	var w := _world(Fixtures.flat(9, 5), [Vector2(2.5, 2.5), Vector2(2.5, 2.5), Vector2(8.5, 0.5)])
	var vi := PlayerIntent.new()
	vi.place_bomb = true
	_go(w, 0.1) # possession starts
	_go(w, 0.5, {1: vi})
	assert_true(w.bombs.is_empty(), "la victime ne pose pas de bombe")

func test_possession_ends_after_duration_then_cooldown() -> void:
	var w := _world(Fixtures.flat(9, 5), [Vector2(2.5, 2.5), Vector2(2.5, 2.5), Vector2(8.5, 0.5)])
	_go(w, 1.0)
	assert_eq(w.players[1].possessed_by, 0, "possession en cours")
	_go(w, 4.2) # t = 5.2 s
	assert_eq(w.players[1].possessed_by, -1, "terminée")
	assert_eq(w.players[0].possess_target, -1)
	var back := {0: _intent_to(w.players[1].pos)} # ejected: the ghost comes back to its victim
	_go(w, 9.0, back) # cooldown still running
	assert_eq(w.players[1].possessed_by, -1, "pas avant la recharge")
	_go(w, 2.0, back)
	assert_eq(w.players[1].possessed_by, 0, "nouvelle possession")

func test_possessed_victim_can_be_walked_into_water() -> void:
	var a := Fixtures.flat(9, 5)
	for y in 5:
		for x in range(4, 9):
			a.set_cell(Vector2i(x, y), Arena.Tile.FLOOR, -1)
	var w := _world(a, [Vector2(2.5, 2.5), Vector2(2.5, 2.5), Vector2(0.5, 0.5)])
	w.water_h2 = -1
	_go(w, 1.5, {0: _intent_to(Vector2(7.5, 2.5))})
	assert_eq(w.players[1].lives, 2, "la victime a perdu une vie")
	assert_eq(w.players[1].possessed_by, -1, "possession terminée par la mort")
	assert_true(w.players[0].possess_cooldown > 0.0, "recharge lancée")

func test_victim_carried_ends_possession() -> void:
	var w := _world(Fixtures.flat(9, 5), [Vector2(2.5, 2.5), Vector2(2.5, 2.5), Vector2(3.5, 2.5)])
	_go(w, 0.1)
	assert_eq(w.players[1].possessed_by, 0)
	w.players[1].carried_by = 2
	w.players[1].carried_timer = 3.0
	w.players[2].held = PlayerState.Held.PLAYER
	w.players[2].held_id = 1
	_go(w, 0.1)
	assert_eq(w.players[1].possessed_by, -1, "portée")
	assert_true(w.players[0].possess_cooldown > 0.0)

func test_invulnerable_victim_not_possessed() -> void:
	var w := _world(Fixtures.flat(9, 5), [Vector2(2.5, 2.5), Vector2(2.5, 2.5), Vector2(8.5, 0.5)])
	w.players[1].invulnerable_timer = 1.0
	_go(w, 0.5)
	assert_eq(w.players[1].possessed_by, -1)
	_go(w, 0.7)
	assert_eq(w.players[1].possessed_by, 0, "possédé après l'invulnérabilité")

func test_nearest_victim_chosen() -> void:
	var w := _world(Fixtures.flat(9, 5), [Vector2(2.5, 2.5), Vector2(2.9, 2.5), Vector2(2.7, 2.5), Vector2(8.5, 0.5)])
	_go(w, 0.1)
	assert_eq(w.players[2].possessed_by, 0)
	assert_eq(w.players[1].possessed_by, -1)

# Secouer (stick, flèches, souris) fait lâcher le fantôme bien avant la fin de la possession.
func test_shaking_throws_the_ghost_off() -> void:
	var w := _world(Fixtures.flat(9, 5), [Vector2(4.5, 2.5), Vector2(4.5, 2.5), Vector2(8.5, 0.5)])
	_go(w, 0.1)
	assert_eq(w.players[1].possessed_by, 0, "possédé")
	var shake := PlayerIntent.new()
	shake.struggle = 1.0
	_go(w, 1.0, {1: shake})
	assert_eq(w.players[1].possessed_by, -1, "fantôme lâché")
	assert_true(w.players[0].possess_cooldown > 0.0, "recharge lancée")

# Le fantôme qui lâche sa victime est éjecté : il recule d'EJECT_DISTANCE sans pouvoir se diriger.
func test_released_ghost_is_ejected() -> void:
	var w := _world(Fixtures.flat(9, 5), [Vector2(4.5, 2.5), Vector2(4.5, 2.5), Vector2(8.5, 0.5)])
	w.players[1].aim = Vector2i(1, 0)
	_go(w, 0.1)
	w.players[0].possess_timer = 0.0 # la possession finit au prochain tick
	w.step({})
	assert_true(w.players[0].eject_timer > 0.0, "éjection en cours")
	_go(w, SimConfig.EJECT_TIME, {0: _intent_to(Vector2(8.5, 2.5))})
	assert_almost(w.players[0].pos.x, 4.5 - SimConfig.EJECT_DISTANCE, 0.01, "projeté en arrière de la victime")
	assert_eq(w.players[0].eject_timer, 0.0)
	assert_eq(w.players[1].possessed_by, -1, "pas repossédée en retombant")
