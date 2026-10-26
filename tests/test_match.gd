extends TestCase

func _match(bots := 4, seed_value := 1) -> MatchState:
	var cfg := SimConfig.new()
	cfg.bot_count = bots
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return MatchState.new(cfg, rng)

func test_creates_human_and_bots() -> void:
	var m := _match(4)
	assert_eq(m.players.size(), 5, "5 joueurs")
	assert_false(m.players[0].is_bot, "l'humain n'est pas un bot")
	assert_eq(m.players[0].name, "Toi", "nom humain")
	assert_eq(m.players[1].name, "Bot 1", "nom bot")
	for i in 5:
		assert_eq(m.players[i].id, i, "id %d" % i)
		assert_eq(m.players[i].color, SimConfig.PLAYER_COLORS[i], "couleur %d" % i)
	for i in range(1, 5):
		assert_true(m.players[i].is_bot, "bot %d" % i)
	assert_eq(m.world.players.size(), 5, "joueurs du monde")
	assert_eq(m.round_number, 1, "manche 1")
	assert_eq(m.phase, MatchState.Phase.PLAYING, "phase")

func test_winner_scores_then_new_round_starts() -> void:
	var m := _match(4)
	for id in m.world.players.keys():
		if id == 2:
			continue
		var p: PlayerState = m.world.players[id]
		var guard := 0
		while p.lives > 0 and guard < 20:
			m.world.kill(id, "test")
			guard += 1
		assert_eq(p.lives, 0, "vies de %d" % id)
	m.step({})
	assert_eq(m.player(2).wins, 1, "victoire du 2")
	assert_eq(m.phase, MatchState.Phase.ROUND_OVER, "phase fin de manche")
	assert_eq(m.last_winners, [2] as Array[int], "last_winners")
	assert_almost(m.phase_timer, SimConfig.SCOREBOARD_DURATION, 0.001, "timer")
	for i in roundi(SimConfig.SCOREBOARD_DURATION * SimConfig.TICK_RATE) + 2:
		m.step({})
	assert_eq(m.phase, MatchState.Phase.PLAYING, "nouvelle manche")
	assert_eq(m.round_number, 2, "manche 2")
	for pl in m.players:
		assert_eq(m.world.players[pl.id].lives, m.cfg.lives, "vies rétablies %d" % pl.id)
	assert_eq(m.player(2).wins, 1, "victoires conservées")

func test_ex_aequo_both_score() -> void:
	var cfg := SimConfig.new()
	cfg.bot_count = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var m := MatchState.new(cfg, rng)
	for i in m.world.arena.h2.size():
		m.world.arena.h2[i] = -2
	assert_eq(m.world.arena.h2[0], -2, "h2 modifié")
	m.world.time_left = 0.0
	var guard := 0
	while m.phase != MatchState.Phase.ROUND_OVER and guard < 5 * SimConfig.TICK_RATE:
		m.step({})
		guard += 1
	assert_eq(m.phase, MatchState.Phase.ROUND_OVER, "manche finie")
	assert_eq(m.player(0).wins, 1, "humain marque")
	assert_eq(m.player(1).wins, 1, "bot marque")

func test_new_round_reshuffles_blocks() -> void:
	var m := _match(3, 7)
	var first: PackedInt32Array = PackedInt32Array(m.world.arena.tiles)
	m.start_round()
	assert_eq(m.round_number, 2, "manche 2")
	assert_true(first != PackedInt32Array(m.world.arena.tiles), "tuiles différentes")
