extends TestCase

func _world(a: Arena, positions: Array[Vector2]) -> World:
	var ids: Array[int] = []
	for i in positions.size():
		ids.append(i)
	var w := World.new(a, ids, SimConfig.new(), RandomNumberGenerator.new())
	for i in positions.size():
		w.players[i].pos = positions[i]
	return w

func _count(events: Array, type: String) -> int:
	var n := 0
	for e: Dictionary in events:
		if e["type"] == type:
			n += 1
	return n

func test_dome_is_round_including_diagonals() -> void:
	var cells := Explosion.hit_cells(Fixtures.flat(9, 9), Vector2i(4, 4), 3.0)
	assert_eq(cells.size(), 29)
	assert_true(Vector2i(6, 6) in cells, "diagonale à 2,83")
	assert_false(Vector2i(7, 6) in cells, "hors rayon à 3,6")

func test_pillar_and_block_shield() -> void:
	var a := Fixtures.flat(9, 9)
	a.set_tile(Vector2i(5, 4), Arena.Tile.PILLAR)
	a.set_tile(Vector2i(4, 5), Arena.Tile.BLOCK)
	var cells := Explosion.hit_cells(a, Vector2i(4, 4), 3.0)
	assert_false(Vector2i(5, 4) in cells); assert_false(Vector2i(6, 4) in cells)
	assert_true(Vector2i(4, 5) in cells, "le bloc est touché"); assert_false(Vector2i(4, 6) in cells, "mais protège derrière lui")

func test_dome_rises_but_never_goes_down() -> void:
	var a := Fixtures.flat(9, 9)
	for y in 9: for x in range(6, 9): a.set_cell(Vector2i(x, y), Arena.Tile.FLOOR, 2)
	a.set_cell(Vector2i(5, 4), Arena.Tile.STAIRS, 1, Arena.Axis.X)
	assert_true(Vector2i(6, 4) in Explosion.hit_cells(a, Vector2i(4, 4), 3.0), "monte à l'étage")
	var down := Explosion.hit_cells(a, Vector2i(6, 4), 3.0)
	assert_false(Vector2i(4, 4) in down, "ne descend pas au sol")
	assert_false(Vector2i(5, 4) in down, "ni sur l'escalier plus bas")
	assert_true(Vector2i(4, 4) in Explosion.hit_cells(a, Vector2i(5, 4), 3.0), "bombe sur l'escalier : niveau 0")

func test_bomb_explodes_after_fuse_and_destroys_block() -> void:
	var a := Fixtures.flat(9, 3)
	a.set_tile(Vector2i(3, 1), Arena.Tile.BLOCK)
	var w := _world(a, [Vector2(1.5, 1.5)])
	var i := PlayerIntent.new(); i.place_bomb = true
	w.step({0: i})
	assert_eq(w.bombs.size(), 1)
	w.players[0].pos = Vector2(7.5, 1.5)
	var explosions := 0
	var destroyed := 0
	for _t in roundi(2.5 * 30) + 2:
		w.step({})
		explosions += _count(w.events, "explosion")
		destroyed += _count(w.events, "block_destroyed")
	assert_eq(a.tile_at(Vector2i(3, 1)), Arena.Tile.FLOOR)
	assert_eq(explosions, 1)
	assert_eq(destroyed, 1)
	assert_eq(w.players[0].lives, 3, "hors de portée")

func test_max_two_bombs() -> void:
	var w := _world(Fixtures.flat(9, 3), [Vector2(1.5, 1.5)])
	var i := PlayerIntent.new(); i.place_bomb = true
	for x in [1.5, 4.5, 7.5]:
		w.players[0].pos = Vector2(x, 1.5)
		w.step({0: i})
	assert_eq(w.bombs.size(), 2)

func test_chain_reaction_same_tick() -> void:
	var w := _world(Fixtures.flat(9, 3), [Vector2(8.5, 0.5)])
	var a := w.add_bomb(0, Vector2i(1, 1), 0.1)
	var b := w.add_bomb(0, Vector2i(3, 1), 2.0)
	var first_tick_events := 0
	for _t in 4:
		w.step({})
		var n := _count(w.events, "explosion")
		if n > 0 and first_tick_events == 0:
			first_tick_events = n
	assert_eq(first_tick_events, 2, "A et B explosent au même tick")
	assert_false(w.bombs.has(a.id))
	assert_false(w.bombs.has(b.id))

func test_explosion_costs_one_life() -> void:
	var w := _world(Fixtures.flat(9, 3), [Vector2(1.8, 1.5), Vector2(2.1, 1.5), Vector2(8.5, 0.5)]) # within the dome as it appears
	w.players[1].invulnerable_timer = 1.0
	w.add_bomb(2, Vector2i(1, 1), 0.0)
	w.step({})
	assert_eq(w.players[0].lives, 2)
	assert_eq(w.players[0].life, PlayerState.Life.WAITING_RESPAWN)
	assert_almost(w.players[0].respawn_timer, SimConfig.RESPAWN_DELAY, 0.001)
	assert_eq(w.players[0].died_tick, w.tick)
	assert_eq(w.players[1].lives, 3)
	assert_eq(w.players[1].life, PlayerState.Life.ALIVE)
	for _t in 20:
		w.step({})
	assert_eq(w.players[0].lives, 2, "une seule vie perdue par explosion")

func test_last_life_becomes_ghost() -> void:
	var w := _world(Fixtures.flat(9, 3), [Vector2(1.8, 1.5)])
	w.players[0].lives = 1
	w.add_bomb(0, Vector2i(1, 1), 0.0)
	w.step({})
	assert_eq(w.players[0].life, PlayerState.Life.GHOST)
	assert_eq(w.players[0].lives, 0)

func test_explosion_expires() -> void:
	var w := _world(Fixtures.flat(9, 3), [Vector2(8.5, 0.5)])
	w.add_bomb(0, Vector2i(1, 1), 0.0)
	w.step({})
	assert_eq(w.explosions.size(), 1)
	for _t in roundi(SimConfig.EXPLOSION_DURATION * 30) + 1:
		w.step({})
	assert_eq(w.explosions.size(), 0)

func test_held_bomb_explodes_at_holder_cell() -> void:
	var w := _world(Fixtures.flat(9, 3), [Vector2(6.5, 1.5)])
	var b := w.add_bomb(0, Vector2i(0, 0), 0.0)
	b.state = BombState.State.HELD
	w.players[0].held = PlayerState.Held.BOMB
	w.players[0].held_id = b.id
	w.step({})
	assert_eq(w.players[0].lives, 2)
	var found := false
	for e: Dictionary in w.events:
		if e["type"] == "explosion":
			found = e["cell"] == Vector2i(6, 1)
	assert_true(found)

func test_bomb_entering_lingering_blast_explodes() -> void:
	var w := _world(Fixtures.flat(9, 3), [Vector2(8.5, 0.5)])
	w.add_bomb(0, Vector2i(1, 1), 0.0)
	w.step({})
	assert_eq(w.bombs.size(), 0)
	var late := w.add_bomb(0, Vector2i(2, 1), 2.0)
	w.step({})
	assert_false(w.bombs.has(late.id), "la bombe posée dans les flammes explose")
	assert_eq(_count(w.events, "explosion"), 1)

func test_rolling_bomb_explodes_in_lingering_blast() -> void:
	var w := _world(Fixtures.flat(12, 3), [Vector2(11.5, 0.5)])
	w.add_bomb(0, Vector2i(1, 1), 0.0)
	w.step({})
	var b := w.add_bomb(0, Vector2i(6, 1), 2.0)
	b.roll_dir = Vector2i(-1, 0)
	var exploded := false
	for _t in roundi(SimConfig.EXPLOSION_DURATION * 30):
		w.step({})
		if not w.bombs.has(b.id):
			exploded = true
			break
	assert_true(exploded, "la bombe qui roule explose en entrant dans les flammes")

func test_death_only_when_the_growing_dome_touches() -> void:
	# Player 1.5 cells away (in a hit cell): alive while the dome is still small.
	var w := _world(Fixtures.flat(9, 3), [Vector2(3.0, 1.5), Vector2(8.5, 0.5)])
	w.add_bomb(1, Vector2i(1, 1), 0.0)
	w.step({})
	assert_eq(w.players[0].life, PlayerState.Life.ALIVE, "pas encore touché")
	var died := false
	for _t in roundi(SimConfig.EXPLOSION_DURATION * 30):
		w.step({})
		died = died or w.players[0].life != PlayerState.Life.ALIVE
	assert_true(died, "touché quand le dôme l'atteint")

func test_edge_of_a_hit_cell_out_of_reach_survives() -> void:
	# Cell (3,1) is in the blast, but the player stands at its far edge, beyond the full dome.
	var w := _world(Fixtures.flat(9, 3), [Vector2(3.95, 1.5), Vector2(8.5, 0.5)])
	w.add_bomb(1, Vector2i(1, 1), 0.0)
	for _t in roundi(SimConfig.EXPLOSION_DURATION * 30) + 2:
		w.step({})
	assert_eq(w.players[0].lives, 3)

func test_dome_radius_grows_to_full() -> void:
	var e := Explosion.new()
	assert_true(e.radius() < SimConfig.BOMB_RADIUS * 0.5)
	e.timer = 0.0
	assert_almost(e.radius(), SimConfig.BOMB_RADIUS, 0.001)
