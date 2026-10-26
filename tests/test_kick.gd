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
	for _t in roundi(seconds * SimConfig.TICK_RATE):
		w.step({id: intent})

func _wait(w: World, seconds: float) -> void:
	for _t in roundi(seconds * SimConfig.TICK_RATE):
		w.step({})

func _bomb(w: World, cell: Vector2i) -> BombState:
	return w.add_bomb(0, cell, 100.0) # pas d'explosion pendant ces tests

# Arène 9×3 avec un pilier en (7,1) : la bombe kickée roule jusqu'à la case avant lui.
func _lane() -> Arena:
	var a := Fixtures.flat(9, 3)
	a.set_tile(Vector2i(7, 1), Arena.Tile.PILLAR)
	return a

func test_pushing_against_a_bomb_kicks_it_until_an_obstacle() -> void:
	var w := _world(_lane(), [Vector2(1.5, 1.5)])
	var b := _bomb(w, Vector2i(3, 1))
	_go(w, 0, Vector2(3.5, 1.5), 1.0)  # le joueur force contre la bombe
	_wait(w, 1.0)
	assert_eq(b.cell, Vector2i(6, 1), "arrêtée devant le pilier")
	assert_eq(b.roll_dir, Vector2i.ZERO, "ne roule plus")
	assert_almost(b.roll_offset, 0.0, 0.001, "centrée sur sa case")

func test_brief_contact_does_not_kick() -> void:
	var w := _world(_lane(), [Vector2(2.5, 1.5)])
	var b := _bomb(w, Vector2i(3, 1))
	_go(w, 0, Vector2(4.5, 1.5), 0.1)  # touche à peine la bombe
	_wait(w, 1.0)
	assert_eq(b.cell, Vector2i(3, 1))
	assert_eq(b.roll_dir, Vector2i.ZERO)

func test_rolling_bomb_stops_before_a_player() -> void:
	var w := _world(_lane(), [Vector2(1.5, 1.5), Vector2(5.5, 1.5)])
	var b := _bomb(w, Vector2i(3, 1))
	_go(w, 0, Vector2(3.5, 1.5), 1.0)
	_wait(w, 1.0)
	assert_eq(b.cell, Vector2i(4, 1))

func test_rolling_bomb_does_not_climb_but_drops_down() -> void:
	var a := Fixtures.flat(9, 3)
	for y in 3: a.set_cell(Vector2i(6, y), Arena.Tile.FLOOR, 2)
	var w := _world(a, [Vector2(1.5, 1.5)])
	var b := _bomb(w, Vector2i(3, 1))
	_go(w, 0, Vector2(3.5, 1.5), 1.0)
	_wait(w, 1.0)
	assert_eq(b.cell, Vector2i(5, 1), "ne monte pas sur l'étage")

	var a2 := Fixtures.flat(9, 3)
	for y in 3: for x in 4: a2.set_cell(Vector2i(x, y), Arena.Tile.FLOOR, 2)
	var w2 := _world(a2, [Vector2(0.5, 1.5)])
	var b2 := _bomb(w2, Vector2i(2, 1))
	_go(w2, 0, Vector2(2.5, 1.5), 1.0)
	_wait(w2, 2.0)
	assert_eq(b2.cell, Vector2i(8, 1), "tombe de l'étage et continue jusqu'au bord")

func test_owner_standing_on_own_bomb_does_not_kick_it() -> void:
	var w := _world(_lane(), [Vector2(3.5, 1.5)])
	var i := PlayerIntent.new(); i.place_bomb = true
	w.step({0: i})
	var b: BombState = w.bombs.values()[0]
	b.fuse = 100.0
	_go(w, 0, Vector2(5.5, 1.5), 0.6)
	assert_eq(b.cell, Vector2i(3, 1))
	assert_eq(b.roll_dir, Vector2i.ZERO)
