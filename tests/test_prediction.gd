extends TestCase

func _world() -> World:
	var ids: Array[int] = [0]
	var w := World.new(Fixtures.flat(9, 5), ids, SimConfig.new(), RandomNumberGenerator.new())
	w.players[0].pos = Vector2(1.5, 2.5)
	return w

func _right(pred: Prediction) -> PlayerIntent:
	var i := PlayerIntent.new()
	i.moving = true
	i.target = Vector2(8.5, 2.5)
	i.seq = pred.next_seq()
	return i

const STEP := SimConfig.PLAYER_SPEED * SimConfig.DT

func test_moves_at_once() -> void:
	var w := _world()
	var pred := Prediction.new()
	pred.reconcile(w, w.players[0])
	pred.record(w, _right(pred))
	assert_almost(pred.shown_pos().x, 1.5 + STEP, 1e-4, "un pas sans attendre le serveur")
	assert_eq(w.players[0].pos.x, 1.5, "le joueur du serveur n'a pas bougé")

func test_replays_what_the_server_has_not_applied() -> void:
	var w := _world()
	var pred := Prediction.new()
	pred.reconcile(w, w.players[0])
	var sent: Array[PlayerIntent] = []
	for _n in 3:
		sent.append(_right(pred))
		pred.record(w, sent[-1])
	# The server applies the first two.
	w.step({0: sent[0]})
	w.step({0: sent[1]})
	assert_eq(w.players[0].input_seq, 2, "accusé du deuxième")
	pred.reconcile(w, w.players[0])
	assert_almost(pred.me.pos.x, 1.5 + 3.0 * STEP, 1e-4, "le troisième rejoué")
	assert_almost(pred.offset.length(), 0.0, 1e-4, "d'accord : aucun écart")

func test_small_disagreement_fades() -> void:
	var w := _world()
	var pred := Prediction.new()
	pred.reconcile(w, w.players[0])
	pred.record(w, _right(pred))
	w.players[0].input_seq = 1
	w.players[0].pos = Vector2(1.5, 2.8) # the server saw it otherwise
	pred.reconcile(w, w.players[0])
	assert_almost(pred.shown_pos().y, 2.5, 1e-4, "pas de saut")
	var still := PlayerIntent.new()
	still.seq = pred.next_seq()
	for _n in 20:
		pred.record(w, still)
	assert_almost(pred.shown_pos().y, 2.8, 0.01, "rejoint la position du serveur")

func test_big_disagreement_jumps() -> void:
	var w := _world()
	var pred := Prediction.new()
	pred.reconcile(w, w.players[0])
	w.players[0].pos = Vector2(7.5, 2.5) # a respawn far away
	pred.reconcile(w, w.players[0])
	assert_eq(pred.shown_pos(), Vector2(7.5, 2.5))

func test_not_predicted_while_stunned() -> void:
	var w := _world()
	var pred := Prediction.new()
	w.players[0].stun_timer = 1.0
	pred.reconcile(w, w.players[0])
	assert_eq(pred.me, null, "position du serveur telle quelle")
	pred.record(w, _right(pred))
	w.players[0].stun_timer = 0.0
	pred.reconcile(w, w.players[0])
	assert_almost(pred.me.pos.x, 1.5 + STEP, 1e-4, "reprend avec l'intention pas encore appliquée")

func test_stops_against_walls_like_the_server() -> void:
	var w := _world()
	w.arena.set_tile(Vector2i(2, 2), Arena.Tile.PILLAR)
	var pred := Prediction.new()
	pred.reconcile(w, w.players[0])
	for _n in 30:
		pred.record(w, _right(pred))
	assert_almost(pred.me.pos.x, 2.0 - SimConfig.PLAYER_HALF, 1e-3, "contre le pilier")

func test_world_step_records_the_seq() -> void:
	var w := _world()
	var i := PlayerIntent.new()
	i.seq = 9
	w.step({0: i})
	assert_eq(w.players[0].input_seq, 9)
	w.step({})
	assert_eq(w.players[0].input_seq, 9, "sans intention : inchangé")
