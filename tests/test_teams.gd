extends TestCase

func _roster(teams: Array[int]) -> Array[MatchState.MatchPlayer]:
	var out: Array[MatchState.MatchPlayer] = []
	for i in teams.size():
		var mp := MatchState.MatchPlayer.new()
		mp.id = i
		mp.name = "P%d" % i
		mp.color = SimConfig.PLAYER_COLORS[i]
		mp.team = teams[i]
		out.append(mp)
	return out

func _match(teams: Array[int]) -> MatchState:
	var cfg := SimConfig.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	return MatchState.new(cfg, rng, _roster(teams))

func _kill_all(m: MatchState, id: int) -> void:
	var p: PlayerState = m.world.players[id]
	var guard := 0
	while p.lives > 0 and guard < 20:
		m.world.kill(id, "test")
		guard += 1

func test_solo_unchanged() -> void:
	var cfg := SimConfig.new()
	cfg.bot_count = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var m := MatchState.new(cfg, rng)
	assert_eq(m.players.size(), 4, "4 joueurs")
	for i in 4:
		assert_eq(m.world.team_of(i), i, "équipe de %d" % i)
	assert_true(m.team_wins.is_empty(), "pas de victoires d'équipe")

func test_round_ends_when_one_team_left() -> void:
	var m := _match([0, 0, 1])
	_kill_all(m, 2)
	m.step({})
	assert_eq(m.phase, MatchState.Phase.ROUND_OVER, "manche finie")
	var w: Array[int] = [0, 1]
	assert_eq(m.last_winners, w, "survivants de l'équipe 0")
	assert_eq(m.team_wins[0], 1, "victoire d'équipe")
	assert_eq(m.player(0).wins, 1, "victoire du 0")
	assert_eq(m.player(1).wins, 1, "victoire du 1")

func test_teammates_alive_round_continues() -> void:
	var m := _match([0, 0, 1, 1])
	_kill_all(m, 0)
	_kill_all(m, 2)
	m.step({})
	assert_eq(m.phase, MatchState.Phase.PLAYING, "la manche continue")

func _finish_round(m: MatchState) -> void:
	_kill_all(m, 2)
	m.step({})

func test_hold_next_round() -> void:
	var m := _match([0, 0, 1])
	_finish_round(m)
	m.hold_next_round = true
	var round_before := m.round_number
	for i in int((SimConfig.SCOREBOARD_DURATION + 1.0) * SimConfig.TICK_RATE):
		m.step({})
	assert_eq(m.round_number, round_before, "manche inchangée")
	assert_true(m.phase_timer <= 0.0, "minuteur écoulé")
	m.hold_next_round = false
	m.step({})
	assert_eq(m.round_number, round_before + 1, "manche relancée")

func test_no_team_wins_without_teams() -> void:
	var m := _match([-1, -1])
	_kill_all(m, 1)
	m.step({})
	assert_eq(m.phase, MatchState.Phase.ROUND_OVER, "manche finie")
	assert_eq(m.player(0).wins, 1, "victoire du joueur")
	assert_true(m.team_wins.is_empty(), "pas de victoire d'équipe")

func test_sync_roster_adds_player_next_round() -> void:
	var m := _match([0, 0, 1])
	_finish_round(m)
	var roster := _roster([0, 0, 1, 1])
	m.sync_roster(roster)
	assert_eq(m.player(0).wins, 1, "le 0 garde ses victoires")
	assert_false(m.world.players.has(3), "pas encore dans le monde")
	m.phase_timer = 0.0
	m.step({})
	assert_true(m.world.players.has(3), "dans la manche suivante")
	assert_eq(m.world.team_of(3), 1, "équipe du nouveau")

func test_forfeit_makes_ghost() -> void:
	var m := _match([0, 0, 1])
	m.world.forfeit(1)
	var p: PlayerState = m.world.players[1]
	assert_eq(p.life, PlayerState.Life.GHOST, "fantôme")
	assert_eq(p.lives, 0, "plus de vies")
	assert_eq(p.death_cause, "déconnexion", "cause")
	m.world.forfeit(1)
	assert_eq(p.life, PlayerState.Life.GHOST, "toujours fantôme")

func test_tag_of() -> void:
	assert_eq(MatchState.tag_of(" paul "), "PAU", "3 lettres")
	assert_eq(MatchState.tag_of("Al"), "AL", "court")
