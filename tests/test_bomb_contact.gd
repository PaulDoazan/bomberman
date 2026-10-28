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

func _place(w: World, id: int) -> void:
	var i := PlayerIntent.new()
	i.place_bomb = true
	w.step({id: i})

# La bombe est posée exactement là où se tient le joueur, quelle que soit sa direction.
func test_bomb_is_placed_exactly_under_the_player() -> void:
	for at: Vector2 in [Vector2(2.1, 1.5), Vector2(2.9, 1.5), Vector2(2.5, 1.15), Vector2(2.8, 1.8)]:
		var w := _world(Fixtures.flat(9, 3), [at])
		_place(w, 0)
		var b: BombState = w.bombs.values()[0]
		assert_eq(b.cell, Vector2i(2, 1), "case de la bombe (%s)" % at)
		assert_almost(b.pos().distance_to(at), 0.0, 0.001, "posée sous le joueur (%s)" % at)

# Un joueur s'arrête au contact de la bombe ronde, pas au bord de sa case.
func test_player_stops_against_the_round_bomb() -> void:
	var w := _world(Fixtures.flat(9, 3), [Vector2(3.5, 1.5), Vector2(8.5, 0.5)])
	w.add_bomb(1, Vector2i(5, 1), 100.0)
	var contact := 5.5 - SimConfig.BOMB_BODY_RADIUS - SimConfig.PLAYER_HALF
	# Juste assez pour arriver au contact, pas assez pour kicker.
	_go(w, 0, Vector2(5.5, 1.5), (contact - 3.5) / SimConfig.PLAYER_SPEED + SimConfig.KICK_PUSH_TIME / 2.0)
	assert_almost(w.players[0].pos.x, contact, 0.01, "au contact de la bombe")

# Frôler le coin de la case d'une bombe ne bloque pas : seule sa forme ronde compte.
func test_box_beside_the_bomb_corner_is_not_blocked() -> void:
	var w := _world(Fixtures.flat(9, 4), [Vector2(3.9, 2.3), Vector2(8.5, 0.5)])
	w.add_bomb(1, Vector2i(4, 1), 100.0)
	var p: PlayerState = w.players[0]
	assert_false(Movement._blocked_at(w, p, p.pos, Vector2(4.1, 2.3), p.cell()), "pas bloqué par le coin")
	assert_true(Movement._blocked_at(w, p, p.pos, Vector2(4.1, 2.1), p.cell()), "bloqué par la bombe elle-même")
