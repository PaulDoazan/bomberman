extends TestCase

func _world(a: Arena, positions: Array[Vector2]) -> World:
	var ids: Array[int] = []
	for i in positions.size():
		ids.append(i)
	var w := World.new(a, ids, SimConfig.new(), RandomNumberGenerator.new())
	for i in positions.size():
		w.players[i].pos = positions[i]
		w.players[i].facing = Vector2i(1, 0)
		w.players[i].aim = Vector2i(1, 0)
	return w

func _act() -> Dictionary:
	var i := PlayerIntent.new()
	i.action = true
	return {0: i}

func _go(w: World, seconds: float) -> void:
	for _t in roundi(seconds * 30):
		w.step({})

func _flight(w: World) -> void:
	_go(w, SimConfig.THROW_FLIGHT + 1.0 / 30.0)

func _has_event(w: World, type: String) -> bool:
	for e: Dictionary in w.events:
		if e["type"] == type:
			return true
	return false

func _explosion_origin(w: World) -> Variant:
	for e: Dictionary in w.events:
		if e["type"] == "explosion":
			return e["cell"]
	return null

func test_pick_up_and_throw_block() -> void:
	var a := Fixtures.flat(9, 5)
	a.set_tile(Vector2i(2, 2), Arena.Tile.BLOCK)
	var w := _world(a, [Vector2(1.5, 2.5)])
	w.step(_act())
	assert_eq(a.tile_at(Vector2i(2, 2)), Arena.Tile.FLOOR)
	assert_eq(w.players[0].held, PlayerState.Held.BLOCK)
	w.step(_act())
	_flight(w)
	assert_eq(a.tile_at(Vector2i(4, 2)), Arena.Tile.BLOCK)
	assert_eq(w.players[0].held, PlayerState.Held.NONE)

func test_throw_skips_blocked_landing() -> void:
	var a := Fixtures.flat(9, 5)
	a.set_tile(Vector2i(4, 2), Arena.Tile.PILLAR)
	var w := _world(a, [Vector2(1.5, 2.5)])
	w.players[0].held = PlayerState.Held.BLOCK
	w.step(_act())
	_flight(w)
	assert_eq(a.tile_at(Vector2i(5, 2)), Arena.Tile.BLOCK)

func test_throw_off_map_splashes() -> void:
	var a := Fixtures.flat(9, 5)
	var w := _world(a, [Vector2(7.5, 2.5)])
	w.players[0].held = PlayerState.Held.BLOCK
	var splash := false
	w.step(_act())
	for _t in 20:
		w.step({})
		splash = splash or _has_event(w, "splash")
	assert_true(splash, "splash")
	for x in 9:
		assert_eq(a.tile_at(Vector2i(x, 2)), Arena.Tile.FLOOR)

# Comme dans Bomberman 64 : la mèche d'une bombe tenue s'arrête (on peut la garder autant qu'on
# veut), et reprend où elle en était une fois la bombe lancée.
func test_held_bomb_fuse_stops_and_resumes_once_thrown() -> void:
	var w := _world(Fixtures.flat(9, 5), [Vector2(1.5, 2.5)])
	var b := w.add_bomb(0, Vector2i(1, 2), 0.5)
	w.step(_act())
	assert_eq(w.players[0].held, PlayerState.Held.BOMB)
	_go(w, 3.0)
	assert_true(w.bombs.has(b.id), "n'explose pas tant qu'on la tient")
	assert_almost(b.fuse, 0.5, 0.001, "mèche arrêtée")
	w.step(_act())
	_go(w, 0.4)
	assert_true(w.bombs.has(b.id), "pas encore")
	_go(w, 0.2)
	assert_false(w.bombs.has(b.id), "la mèche a repris après le lancer")

func test_cannot_place_bomb_while_holding() -> void:
	var w := _world(Fixtures.flat(9, 5), [Vector2(1.5, 2.5)])
	w.players[0].held = PlayerState.Held.BLOCK
	var i := PlayerIntent.new()
	i.place_bomb = true
	w.step({0: i})
	assert_eq(w.bombs.size(), 0)

func test_carry_player_then_escape() -> void:
	var w := _world(Fixtures.flat(9, 5), [Vector2(1.5, 2.5), Vector2(2.5, 2.5)])
	w.step(_act())
	assert_eq(w.players[1].carried_by, 0)
	var m := PlayerIntent.new()
	m.moving = true
	m.target = Vector2(8.5, 0.5)
	for _t in 10:
		w.step({1: m})
	assert_eq(w.players[1].pos, w.players[0].pos, "suit le porteur")
	_go(w, SimConfig.CARRY_ESCAPE)
	assert_eq(w.players[1].carried_by, -1)
	assert_eq(w.players[0].held, PlayerState.Held.NONE)
	assert_eq(w.players[1].cell(), w.players[0].cell())

func test_thrown_player_is_stunned_and_thrown_into_water_loses_life() -> void:
	var w := _world(Fixtures.flat(9, 5), [Vector2(1.5, 2.5), Vector2(2.5, 2.5)])
	w.step(_act())
	w.step(_act())
	assert_false(w.players[1].can_act(), "en vol")
	_flight(w)
	assert_eq(w.players[1].cell(), Vector2i(4, 2))
	assert_true(w.players[1].stun_timer > 0.0, "étourdi")
	assert_eq(w.players[1].carried_by, -1)
	var w2 := _world(Fixtures.flat(9, 5), [Vector2(7.5, 2.5), Vector2(8.5, 2.5)])
	w2.step(_act())
	w2.step(_act())
	_flight(w2)
	assert_eq(w2.players[1].lives, 2)

func test_thrown_bomb_stuns_player_on_landing() -> void:
	var w := _world(Fixtures.flat(9, 5), [Vector2(1.5, 2.5), Vector2(4.5, 2.5)])
	w.players[0].held = PlayerState.Held.BOMB
	var b := w.add_bomb(0, Vector2i(1, 2), 2.5)
	b.state = BombState.State.HELD
	w.players[0].held_id = b.id
	w.step(_act())
	_flight(w)
	assert_eq(b.state, BombState.State.PLACED)
	assert_true(w.players[1].stun_timer > SimConfig.BOMB_HIT_STUN_TIME - 0.1, "assommé")

func test_throw_lands_on_upper_level() -> void:
	var a := Fixtures.flat(9, 5)
	for y in 5: for x in range(4, 9): a.set_cell(Vector2i(x, y), Arena.Tile.FLOOR, 2)
	var w := _world(a, [Vector2(1.5, 2.5)])
	var b := w.add_bomb(0, Vector2i(1, 2), 0.7)
	w.step(_act())
	w.step(_act())
	_flight(w)
	assert_eq(b.cell, Vector2i(4, 2))
	assert_eq(b.state, BombState.State.PLACED)
	var origin: Variant = null
	for _t in 15:
		w.step({})
		origin = origin if origin != null else _explosion_origin(w)
	assert_eq(origin, Vector2i(4, 2), "explosion en (4,2)")
	assert_eq(w.players[0].lives, 3, "hors de portée")

func test_flying_bomb_explodes_in_flight_when_fuse_ends() -> void:
	var w := _world(Fixtures.flat(9, 5), [Vector2(1.5, 2.5)])
	w.add_bomb(0, Vector2i(1, 2), 0.35)
	w.step(_act())
	w.step(_act())
	var origin: Variant = null
	for _t in 12:
		w.step({})
		origin = origin if origin != null else _explosion_origin(w)
	assert_true(origin != null, "événement explosion")
	assert_eq(origin, Vector2i(3, 2), "cellule interpolée en vol (x = 3,3), pas `from`")
	assert_eq(w.bombs.size(), 0)
	assert_eq(w.flying.size(), 0)

func test_carrier_death_releases_carried_player_and_bomb() -> void:
	var w := _world(Fixtures.flat(9, 5), [Vector2(1.5, 2.5), Vector2(2.5, 2.5)])
	w.step(_act())
	w.kill(0, "test")
	assert_eq(w.players[1].carried_by, -1)
	assert_eq(w.players[0].held, PlayerState.Held.NONE)
	var w2 := _world(Fixtures.flat(9, 5), [Vector2(1.5, 2.5)])
	var b := w2.add_bomb(0, Vector2i(1, 2), 2.5)
	w2.step(_act())
	assert_eq(b.state, BombState.State.HELD)
	w2.kill(0, "test")
	assert_eq(b.state, BombState.State.PLACED)

func test_exploding_held_bomb_clears_invulnerable_holder() -> void:
	var w := _world(Fixtures.flat(9, 5), [Vector2(1.5, 2.5)])
	w.players[0].invulnerable_timer = 5.0
	w.add_bomb(0, Vector2i(1, 2), 0.0) # goes off the tick it is picked up
	w.step(_act())
	_go(w, 0.2 + SimConfig.EXPLOSION_DURATION) # until the flames are out
	assert_eq(w.bombs.size(), 0)
	assert_eq(w.players[0].held, PlayerState.Held.NONE)
	assert_eq(w.players[0].held_id, -1)
	var i := PlayerIntent.new()
	i.place_bomb = true
	w.step({0: i})
	assert_eq(w.bombs.size(), 1, "peut reposer une bombe")
	w.step(_act()) # picks the new bomb up: no error

func test_block_lands_further_when_player_walks_onto_landing_cell() -> void:
	var a := Fixtures.flat(9, 5)
	var w := _world(a, [Vector2(1.5, 2.5), Vector2(6.5, 0.5)])
	w.players[0].held = PlayerState.Held.BLOCK
	w.step(_act())
	w.players[1].pos = Vector2(4.5, 2.5)
	_flight(w)
	assert_eq(a.tile_at(Vector2i(4, 2)), Arena.Tile.FLOOR, "joueur pas emmuré")
	assert_eq(a.tile_at(Vector2i(5, 2)), Arena.Tile.BLOCK)

func test_bomb_lands_further_when_bomb_placed_on_landing_cell() -> void:
	var w := _world(Fixtures.flat(9, 5), [Vector2(1.5, 2.5)])
	var b := w.add_bomb(0, Vector2i(1, 2), 2.5)
	w.step(_act())
	w.step(_act())
	var other := w.add_bomb(1, Vector2i(4, 2), 2.5)
	_flight(w)
	assert_eq(other.cell, Vector2i(4, 2))
	assert_eq(b.cell, Vector2i(5, 2))
	assert_eq(b.state, BombState.State.PLACED)

func test_two_flights_to_same_cell_do_not_overlap() -> void:
	var a := Fixtures.flat(9, 5)
	var w := _world(a, [Vector2(1.5, 2.5)])
	w.players[0].held = PlayerState.Held.BLOCK
	w.step(_act())
	w.players[0].held = PlayerState.Held.BLOCK
	w.step(_act())
	_flight(w)
	assert_eq(a.tile_at(Vector2i(4, 2)), Arena.Tile.BLOCK)
	assert_eq(a.tile_at(Vector2i(5, 2)), Arena.Tile.BLOCK)

func test_thrown_block_skips_stairs() -> void:
	var a := Fixtures.flat(9, 5)
	a.set_cell(Vector2i(4, 2), Arena.Tile.STAIRS, 0, Arena.Axis.X)
	var w := _world(a, [Vector2(1.5, 2.5)])
	w.players[0].held = PlayerState.Held.BLOCK
	w.step(_act())
	_flight(w)
	assert_eq(a.tile_at(Vector2i(4, 2)), Arena.Tile.STAIRS, "l'escalier reste un escalier")
	assert_eq(a.tile_at(Vector2i(5, 2)), Arena.Tile.BLOCK, "le bloc atterrit après")

func test_throw_follows_diagonal_aim() -> void:
	var a := Fixtures.flat(9, 9)
	var w := _world(a, [Vector2(1.5, 1.5)])
	w.players[0].aim = Vector2i(1, 1)
	w.players[0].held = PlayerState.Held.BLOCK
	w.step(_act())
	_flight(w)
	var d := roundi(SimConfig.THROW_DISTANCE / sqrt(2.0))
	assert_eq(a.tile_at(Vector2i(1 + d, 1 + d)), Arena.Tile.BLOCK, "atterrit en diagonale")

# Un joueur assommé tout contre soi (même case, ou en biais devant) se saisit aussi.
func test_pick_up_a_stunned_player_standing_close() -> void:
	for at: Vector2 in [Vector2(2.9, 2.5), Vector2(3.2, 3.1)]:
		var w := _world(Fixtures.flat(9, 5), [Vector2(2.5, 2.5), at])
		w.players[1].stun_timer = SimConfig.BOMB_HIT_STUN_TIME
		w.step(_act())
		assert_eq(w.players[1].carried_by, 0, "saisi (%s)" % at)
		assert_eq(w.players[0].held, PlayerState.Held.PLAYER)

func test_no_pick_up_of_a_player_behind() -> void:
	var w := _world(Fixtures.flat(9, 5), [Vector2(2.5, 2.5), Vector2(1.6, 2.5)])
	w.players[1].stun_timer = SimConfig.BOMB_HIT_STUN_TIME
	w.step(_act())
	assert_eq(w.players[1].carried_by, -1)
