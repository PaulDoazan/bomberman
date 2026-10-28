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
	var contact := 5.5 - SimConfig.BOMB_BODY_RADIUS - SimConfig.PLAYER_BODY_RADIUS
	# Juste assez pour arriver au contact, pas assez pour kicker.
	_go(w, 0, Vector2(5.5, 1.5), (contact - 3.5) / SimConfig.PLAYER_SPEED + SimConfig.KICK_PUSH_TIME / 2.0)
	assert_almost(w.players[0].pos.x, contact, 0.01, "au contact de la bombe")

# Frôler le coin de la case d'une bombe ne bloque pas : seuls le corps rond de la bombe et celui
# du perso comptent.
func test_box_beside_the_bomb_corner_is_not_blocked() -> void:
	var w := _world(Fixtures.flat(9, 4), [Vector2(3.9, 2.3), Vector2(8.5, 0.5)])
	w.add_bomb(1, Vector2i(4, 1), 100.0)
	var p: PlayerState = w.players[0]
	assert_false(Movement._blocked_at(w, p, p.pos, Vector2(4.1, 2.3), p.cell()), "pas bloqué par le coin")
	assert_true(Movement._blocked_at(w, p, p.pos, Vector2(4.4, 2.0), p.cell()), "bloqué par la bombe elle-même")

# Rappuyer en s'éloignant ne kicke plus la bombe précédente : on n'est plus dessus. Plus loin,
# une deuxième bombe se pose, même dans la même case.
func test_pressing_again_after_walking_off_does_not_kick() -> void:
	var w := _world(Fixtures.flat(13, 5), [Vector2(4.1, 2.5)])
	_place(w, 0)
	var first: BombState = w.bombs.values()[0]
	var walk := PlayerIntent.new()
	walk.moving = true
	walk.target = Vector2(12.5, 2.5)
	while w.players[0].pos.x < 4.1 + SimConfig.BOMB_BODY_RADIUS + 0.05:
		w.step({0: walk})
	_place(w, 0)
	assert_eq(first.roll_dir, Vector2i.ZERO, "la première bombe ne part pas")
	while w.players[0].pos.x < 4.1 + 2.0 * SimConfig.BOMB_BODY_RADIUS + 0.05:
		w.step({0: walk})
	_place(w, 0)
	assert_eq(first.roll_dir, Vector2i.ZERO, "toujours pas")
	assert_eq(w.bombs.size(), 2, "deuxième bombe posée")
	var second: BombState = w.bombs.values()[1]
	assert_eq(second.cell, first.cell, "dans la même case")
	assert_almost(second.pos().distance_to(w.players[0].pos), 0.0, 0.001, "sous le joueur")

# En diagonale aussi, le perso s'arrête pile au contact : pas de coin de boîte qui dépasse.
func test_diagonal_approach_stops_at_contact() -> void:
	var w := _world(Fixtures.flat(9, 9), [Vector2(2.5, 2.5), Vector2(8.5, 0.5)])
	var b := w.add_bomb(1, Vector2i(5, 5), 100.0)
	_go(w, 0, Vector2(5.5, 5.5), 1.2)
	var reach := SimConfig.BOMB_BODY_RADIUS + SimConfig.PLAYER_BODY_RADIUS
	assert_almost(w.players[0].pos.distance_to(b.pos()), reach, 0.02, "au contact en diagonale")

# Une bombe qui roule s'arrête pile au contact du perso, et l'assomme.
func test_rolling_bomb_stops_exactly_at_the_player() -> void:
	var w := _world(Fixtures.flat(12, 3), [Vector2(1.5, 1.5), Vector2(7.3, 1.5)])
	var b := w.add_bomb(0, Vector2i(2, 1), 100.0)
	w.players[0].aim = Vector2i(1, 0)
	Kick.kick(w, w.players[0], b)
	for _t in 60:
		w.step({})
	var reach := SimConfig.BOMB_BODY_RADIUS + SimConfig.PLAYER_BODY_RADIUS
	assert_eq(b.roll_dir, Vector2i.ZERO, "arrêtée")
	assert_almost(b.pos().x, 7.3 - reach, 0.02, "pile au contact")
	assert_true(w.players[1].stun_timer > 0.0, "assommé")
