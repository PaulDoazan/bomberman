extends TestCase

func _world(a: Arena, positions: Array[Vector2]) -> World:
	var ids: Array[int] = []
	for i in positions.size():
		ids.append(i)
	var w := World.new(a, ids, SimConfig.new(), RandomNumberGenerator.new())
	for i in positions.size():
		w.players[i].pos = positions[i]
	return w

func _go(w: World, id: int, target: Vector2, seconds: float) -> void:
	var intent := PlayerIntent.new()
	intent.moving = true
	intent.target = target
	for _t in roundi(seconds * 30):
		w.step({id: intent})

func test_moves_straight_and_stops_at_target() -> void:
	var w := _world(Fixtures.flat(7, 5), [Vector2(0.5, 2.5)])
	_go(w, 0, Vector2(4.5, 2.5), 4.0 / SimConfig.PLAYER_SPEED + 0.2)
	assert_almost(w.players[0].pos.x, 4.5, SimConfig.STOP_DISTANCE)
	assert_almost(w.players[0].pos.y, 2.5, 0.05)
	assert_eq(w.players[0].facing, Vector2i(1, 0))

func test_no_jitter_when_target_is_reached() -> void:
	var w := _world(Fixtures.flat(5, 5), [Vector2(2.5, 2.5)])
	_go(w, 0, Vector2(2.53, 2.52), 0.5)
	assert_eq(w.players[0].pos, Vector2(2.5, 2.5))

func test_slides_along_wall() -> void:
	var a := Fixtures.flat(6, 6)
	for y in 6: a.set_tile(Vector2i(3, y), Arena.Tile.PILLAR)
	var w := _world(a, [Vector2(1.5, 1.5)])
	_go(w, 0, Vector2(5.5, 4.5), 1.0)
	assert_true(w.players[0].pos.x <= 3.0 - SimConfig.PLAYER_HALF + 0.01, "ne traverse pas")
	assert_true(w.players[0].pos.y > 3.0, "a glissé vers le bas")

func test_corner_assist_enters_corridor() -> void:
	var a := Fixtures.flat(6, 5)
	a.set_tile(Vector2i(2, 1), Arena.Tile.PILLAR); a.set_tile(Vector2i(2, 3), Arena.Tile.PILLAR)
	var w := _world(a, [Vector2(1.5, 2.25)])
	_go(w, 0, Vector2(5.5, 2.25), 1.0)
	assert_true(w.players[0].pos.x > 3.0, "est passé dans le couloir")

func test_blocked_by_level_without_stairs() -> void:
	var a := Fixtures.flat(5, 5)
	for y in 5: a.set_cell(Vector2i(3, y), Arena.Tile.FLOOR, 2)
	var w := _world(a, [Vector2(1.5, 2.5)])
	_go(w, 0, Vector2(4.5, 2.5), 1.0)
	assert_true(w.players[0].pos.x <= 3.0 - SimConfig.PLAYER_HALF + 0.01)

func test_climbs_stairs() -> void:
	var a := Fixtures.flat(5, 5)
	for y in 5: a.set_cell(Vector2i(3, y), Arena.Tile.FLOOR, 2)
	a.set_cell(Vector2i(2, 2), Arena.Tile.STAIRS, 1, Arena.Axis.X)
	var w := _world(a, [Vector2(0.5, 2.5)])
	_go(w, 0, Vector2(3.5, 2.5), 1.5)
	assert_eq(w.players[0].cell(), Vector2i(3, 2))

func test_jumps_down_from_ledge_but_cannot_climb_back() -> void:
	var a := Fixtures.flat(5, 5)
	for y in 5: a.set_cell(Vector2i(3, y), Arena.Tile.FLOOR, 2)
	var w := _world(a, [Vector2(3.5, 2.5)])
	_go(w, 0, Vector2(1.5, 2.5), 1.0)
	assert_eq(w.players[0].cell(), Vector2i(1, 2), "saut vers le bas")
	_go(w, 0, Vector2(3.5, 2.5), 1.0)
	assert_true(w.players[0].pos.x <= 3.0 - SimConfig.PLAYER_HALF + 0.01, "pas d'escalade")

func test_bomb_blocks_others_but_owner_can_leave() -> void:
	var w := _world(Fixtures.flat(7, 3), [Vector2(1.5, 1.5), Vector2(5.5, 1.5)])
	var i := PlayerIntent.new(); i.place_bomb = true
	w.step({0: i})
	w.bombs.values()[0].fuse = 100.0         # pas d'explosion pendant ce test
	_go(w, 0, Vector2(0.5, 1.5), 0.5)        # le poseur quitte sa bombe
	assert_eq(w.players[0].cell(), Vector2i(0, 1))
	_go(w, 0, Vector2(3.5, 1.5), 0.15)       # puis ne peut plus y revenir
	assert_true(w.players[0].pos.x <= 1.0 - SimConfig.PLAYER_HALF + 0.01)
	_go(w, 1, Vector2(0.5, 1.5), 0.85)       # l'autre joueur est bloqué (sans forcer assez pour kicker)
	assert_true(w.players[1].pos.x >= 2.0 + SimConfig.PLAYER_HALF - 0.01)

func test_stunned_player_does_not_move() -> void:
	var w := _world(Fixtures.flat(5, 5), [Vector2(1.5, 1.5)])
	w.players[0].stun_timer = 1.0
	_go(w, 0, Vector2(4.5, 1.5), 0.5)
	assert_eq(w.players[0].pos, Vector2(1.5, 1.5))

func _stairs_arena() -> Arena:
	var a := Fixtures.flat(5, 5)
	for y in 5: a.set_cell(Vector2i(3, y), Arena.Tile.FLOOR, 2)
	a.set_cell(Vector2i(2, 2), Arena.Tile.STAIRS, 1, Arena.Axis.X)
	return a

func test_climbs_stairs_from_off_lane_start_above() -> void:
	var w := _world(_stairs_arena(), [Vector2(0.5, 2.2)])
	_go(w, 0, Vector2(3.5, 2.5), 2.0)
	assert_eq(w.players[0].cell(), Vector2i(3, 2))

func test_climbs_stairs_from_off_lane_start_below() -> void:
	var w := _world(_stairs_arena(), [Vector2(0.5, 2.8)])
	_go(w, 0, Vector2(3.5, 2.5), 2.0)
	assert_eq(w.players[0].cell(), Vector2i(3, 2))

func test_can_move_along_stairs_when_off_lane() -> void:
	var w := _world(_stairs_arena(), [Vector2(2.5, 2.2)])
	_go(w, 0, Vector2(3.5, 2.5), 1.5)
	assert_eq(w.players[0].cell(), Vector2i(3, 2))

func test_aim_follows_eight_directions() -> void:
	var w := _world(Fixtures.flat(9, 9), [Vector2(4.5, 4.5)])
	_go(w, 0, Vector2(8.5, 0.5), 0.1)
	assert_eq(w.players[0].aim, Vector2i(1, -1), "diagonale")
	assert_eq(w.players[0].facing, Vector2i(1, 0), "facing reste orthogonal")
	w.players[0].pos = Vector2(4.5, 4.5)
	_go(w, 0, Vector2(4.8, 8.5), 0.1)
	assert_eq(w.players[0].aim, Vector2i(0, 1), "presque droit : orthogonal")
