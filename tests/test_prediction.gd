extends TestCase

const STEP := SimConfig.PLAYER_SPEED * SimConfig.DT

# A server match on a flat 9x5 arena: player 0 at (1.5, 2.5), player 1 at (6.5, 2.5).
func _server() -> MatchState:
	var cfg := SimConfig.new()
	var rng := RandomNumberGenerator.new()
	var roster: Array[MatchState.MatchPlayer] = []
	for id in 2:
		var mp := MatchState.MatchPlayer.new()
		mp.id = id
		roster.append(mp)
	var m := MatchState.new(cfg, rng, roster, false)
	var ids: Array[int] = [0, 1]
	m.world = World.new(Fixtures.flat(9, 5), ids, cfg, rng)
	m.world.players[0].pos = Vector2(1.5, 2.5)
	m.world.players[1].pos = Vector2(6.5, 2.5)
	return m

func _mirror(server: MatchState, mirror: MatchState = null) -> MatchState:
	return SimCodec.apply_match(SimCodec.encode_match(server), mirror, server.cfg)

func _intent(pred: Prediction, moving := false, bomb := false) -> PlayerIntent:
	var i := PlayerIntent.new()
	i.moving = moving
	i.target = Vector2(8.5, 2.5)
	i.place_bomb = bomb
	i.seq = pred.next_seq()
	return i

func test_bomb_shows_at_once_and_stays_when_confirmed() -> void:
	var server := _server()
	var mirror := _mirror(server)
	var pred := Prediction.new()
	pred.on_snapshot(mirror, 0, Vector2.INF)
	var bomb := _intent(pred, false, true)
	pred.record(mirror, 0, bomb)
	assert_eq(mirror.world.bombs.size(), 1, "la bombe est là sans attendre le serveur")
	var predicted: BombState = mirror.world.bombs.values()[0]
	pred.record(mirror, 0, _intent(pred))
	# The server applies the bomb, but not the second intent yet.
	server.world.step({0: bomb})
	mirror = _mirror(server, mirror)
	pred.on_snapshot(mirror, 0, Vector2.INF)
	assert_eq(mirror.world.bombs.size(), 1, "une seule bombe, celle du serveur")
	assert_true(mirror.world.bombs.has(predicted.id), "même numéro : l'affichage la garde")
	assert_eq(pred.pending_count(), 1, "il reste l'intention non appliquée")

func test_refused_bomb_disappears() -> void:
	var server := _server()
	var mirror := _mirror(server)
	var pred := Prediction.new()
	pred.on_snapshot(mirror, 0, Vector2.INF)
	var bomb := _intent(pred, false, true)
	pred.record(mirror, 0, bomb)
	# The server applied it while the player could not act.
	server.world.players[0].stun_timer = 1.0
	server.world.step({0: bomb})
	mirror = _mirror(server, mirror)
	pred.on_snapshot(mirror, 0, Vector2.INF)
	assert_true(mirror.world.bombs.is_empty(), "le serveur a dit non")

func test_replays_what_the_server_has_not_applied() -> void:
	var server := _server()
	var mirror := _mirror(server)
	var pred := Prediction.new()
	pred.on_snapshot(mirror, 0, Vector2.INF)
	var sent: Array[PlayerIntent] = []
	for _n in 3:
		sent.append(_intent(pred, true))
		pred.record(mirror, 0, sent[-1])
	assert_almost(mirror.world.players[0].pos.x, 1.5 + 3.0 * STEP, 1e-4, "trois pas sans attendre")
	server.world.step({0: sent[0]})
	server.world.step({0: sent[1]})
	var shown: Vector2 = mirror.world.players[0].pos
	mirror = _mirror(server, mirror)
	pred.on_snapshot(mirror, 0, shown)
	assert_almost(mirror.world.players[0].pos.x, 1.5 + 3.0 * STEP, 1e-4, "le troisième rejoué")
	assert_almost(pred.offset.length(), 0.0, 1e-4, "d'accord : aucun écart")

func test_bomb_explodes_on_time_without_hurting_others() -> void:
	var server := _server()
	server.world.players[1].pos = Vector2(2.5, 2.5) # next to the bomb
	var mirror := _mirror(server)
	var pred := Prediction.new()
	pred.on_snapshot(mirror, 0, Vector2.INF)
	pred.record(mirror, 0, _intent(pred, false, true))
	var exploded := false
	for _t in roundi(SimConfig.FUSE / SimConfig.DT) + 5:
		pred.record(mirror, 0, _intent(pred))
		exploded = exploded or not mirror.world.explosions.is_empty()
	assert_true(exploded, "l'explosion se voit à l'heure, sans le serveur")
	var other: PlayerState = mirror.world.players[1]
	assert_eq(other.life, PlayerState.Life.ALIVE, "l'autre joueur : seul le serveur dit s'il est touché")
	assert_eq(other.lives, server.world.players[1].lives, "vies inchangées")
	assert_eq(other.pos, Vector2(2.5, 2.5), "pas déplacé")

func test_small_disagreement_fades() -> void:
	var server := _server()
	var mirror := _mirror(server)
	var pred := Prediction.new()
	pred.on_snapshot(mirror, 0, Vector2.INF)
	var still := _intent(pred)
	pred.record(mirror, 0, still)
	server.world.players[0].pos = Vector2(1.5, 2.8) # the server saw it otherwise
	server.world.step({0: still})
	var shown: Vector2 = mirror.world.players[0].pos
	mirror = _mirror(server, mirror)
	pred.on_snapshot(mirror, 0, shown)
	assert_almost((mirror.world.players[0].pos + pred.offset).y, 2.5, 1e-4, "pas de saut")
	for _n in 20:
		pred.record(mirror, 0, _intent(pred))
	assert_almost((mirror.world.players[0].pos + pred.offset).y, 2.8, 0.01, "rejoint la position du serveur")

func test_big_disagreement_jumps() -> void:
	var server := _server()
	var mirror := _mirror(server)
	var pred := Prediction.new()
	pred.on_snapshot(mirror, 0, Vector2.INF)
	server.world.players[0].pos = Vector2(7.5, 2.5) # a respawn far away
	var shown: Vector2 = mirror.world.players[0].pos
	mirror = _mirror(server, mirror)
	pred.on_snapshot(mirror, 0, shown)
	assert_eq(pred.offset, Vector2.ZERO)

func test_only_the_server_ends_a_round() -> void:
	var server := _server()
	var mirror := _mirror(server)
	var pred := Prediction.new()
	pred.on_snapshot(mirror, 0, Vector2.INF)
	mirror.world.players[1].lives = 0
	mirror.world.players[1].life = PlayerState.Life.GHOST # as if a predicted blast had killed them
	pred.record(mirror, 0, _intent(pred))
	assert_false(mirror.world.finished, "la manche continue")

func test_world_step_records_the_seq() -> void:
	var w := _server().world
	var i := PlayerIntent.new()
	i.seq = 9
	w.step({0: i})
	assert_eq(w.players[0].input_seq, 9)
	w.step({})
	assert_eq(w.players[0].input_seq, 9, "sans intention : inchangé")

# Seule la caisse du serveur descend : le client ne tire ni sa case ni son objet.
func test_only_the_server_brings_crates_down() -> void:
	var server := _server()
	server.world.crate_timer = SimConfig.DT * 0.5 # due at the next step
	var mirror := _mirror(server)
	var pred := Prediction.new()
	pred.on_snapshot(mirror, 0, Vector2.INF)
	pred.record(mirror, 0, _intent(pred))
	assert_true(mirror.world.drops.is_empty(), "pas de caisse prédite")
	server.world.step({})
	assert_eq(server.world.drops.size(), 1, "le serveur en fait descendre une")
	mirror = _mirror(server, mirror)
	pred.on_snapshot(mirror, 0, Vector2.INF)
	assert_eq(mirror.world.drops.size(), 1, "le client la reçoit")
	var crate: Drop = mirror.world.drops[0]
	assert_eq(crate.cell, server.world.drops[0].cell, "à la même case")
	assert_eq(crate.item, server.world.drops[0].item, "avec le même objet")
	pred.record(mirror, 0, _intent(pred))
	assert_true(mirror.world.drops[0] == crate, "même instance : l'affichage la garde")
	assert_true(crate.elapsed > 0.0, "elle continue de descendre")
