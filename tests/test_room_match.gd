extends TestCase

const DT := SimConfig.DT

# Started room: players 1, 2 in team 0 and 3, 4 in team 1.
func _started() -> Room:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var r := Room.new("K7P2QX", rng)
	for n in ["Ann", "Bob", "Cid", "Dan"]:
		r.join(n, "", 0.0)
	r.create_team(1, "Rouge")
	r.create_team(1, "Bleu")
	for id in [1, 2]:
		r.join_team(id, 0)
	for id in [3, 4]:
		r.join_team(id, 1)
	assert_eq(r.start(1), "")
	return r

# Runs ticks from `from` for `seconds`; returns the final time.
func _run(r: Room, from: float, seconds: float, intents := {}) -> float:
	var now := from
	var end := from + seconds
	while now < end:
		now += DT
		r.tick(now, intents)
	return now

func _life(r: Room, id: int) -> int:
	return r.match_state.world.players[id].life

func _finish_round(r: Room) -> void:
	r.match_state.phase = MatchState.Phase.ROUND_OVER
	r.match_state.phase_timer = SimConfig.SCOREBOARD_DURATION

func test_reconnect_within_grace_keeps_character() -> void:
	var r := _started()
	var token: String = r.players[2].token
	r.disconnect_player(2, 0.0)
	var now := _run(r, 0.0, 5.0)
	r.join("", token, now)
	var ps: PlayerState = r.match_state.world.players[2]
	var intent := PlayerIntent.new()
	intent.moving = true
	# A free row: the target is a few cells away along the player's own row.
	var cell := ps.cell()
	var best := cell
	for dx in [1, -1]:
		var c: Vector2i = cell + Vector2i(dx * 3, 0)
		if r.match_state.world.arena.in_bounds(c):
			best = c
			break
	intent.target = Arena.center_of(Vector2i(best.x, cell.y))
	var before := ps.pos
	now = _run(r, now, 0.5, {2: intent})
	assert_true(_life(r, 2) != PlayerState.Life.GHOST, "pas fantôme")
	assert_true(ps.pos != before, "il bouge")

func test_grace_expires_into_ghost() -> void:
	var r := _started()
	r.disconnect_player(2, 0.0)
	var now := _run(r, 0.0, 9.9)
	assert_true(_life(r, 2) != PlayerState.Life.GHOST, "pas encore")
	_run(r, now, 0.4)
	assert_eq(_life(r, 2), PlayerState.Life.GHOST)
	assert_true(r.players[2].forfeited)

func test_newcomer_joins_next_round() -> void:
	var r := _started()
	var j := r.join("Eve", "", 1.0)
	assert_eq(r.join_team(j["id"], 0), "")
	var now := _run(r, 1.0, 1.0)
	assert_false(r.match_state.world.players.has(j["id"]))
	assert_false(r.in_match(j["id"]))
	assert_true(r.in_match(1))
	var round_before := r.match_state.round_number
	_finish_round(r)
	_run(r, now, SimConfig.SCOREBOARD_DURATION + 1.0)
	assert_eq(r.match_state.round_number, round_before + 1)
	assert_true(r.match_state.world.players.has(j["id"]))
	assert_true(r.in_match(j["id"]))

func test_next_round_held_without_two_teams() -> void:
	var r := _started()
	r.disconnect_player(3, 0.0)
	r.disconnect_player(4, 0.0)
	_finish_round(r)
	var round_before := r.match_state.round_number
	var now := _run(r, 0.0, SimConfig.SCOREBOARD_DURATION + 2.0)
	assert_eq(r.match_state.round_number, round_before, "figée")
	r.join("", r.players[3].token, now)
	_run(r, now, 1.0)
	assert_eq(r.match_state.round_number, round_before + 1)

func test_single_team_plays_each_for_themselves() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var r := Room.new("K7P2QX", rng)
	r.join("Ann", "", 0.0)
	r.join("Bob", "", 0.0)
	r.create_team(1, "Rouge")
	r.join_team(1, 0)
	r.join_team(2, 0)
	assert_eq(r.start(1), "")
	assert_true(r.match_state.world.teams.is_empty(), "chacun pour soi")
	_run(r, 0.0, 0.5)
	assert_false(r.match_state.hold_next_round, "deux joueurs : on joue")
	r.disconnect_player(2, 0.5)
	_run(r, 0.5, 0.5)
	assert_true(r.match_state.hold_next_round, "seul connecté : on attend")

func test_forgotten_after_181_seconds() -> void:
	var r := _started()
	r.disconnect_player(3, 0.0)
	r.disconnect_player(4, 0.0)
	r.disconnect_player(1, 0.0) # the host
	r.tick(181.0, {})
	assert_false(r.players.has(3))
	assert_false(r.players.has(4))
	assert_false(r.lobby_state()["teams"].any(func(t: Dictionary) -> bool: return t["name"] == "Bleu"))
	assert_eq(r.teams.size(), 1)
	assert_eq(r.host_id, 2, "l'host est réélu")

func test_forgetting_in_lobby() -> void:
	var r := _started()
	r.back_to_lobby(1)
	r.disconnect_player(2, 0.0)
	r.tick(181.0, {})
	assert_false(r.players.has(2))

func test_back_to_lobby_keeps_teams() -> void:
	var r := _started()
	r.match_state.team_wins[0] = 2
	assert_eq(r.back_to_lobby(1), "")
	assert_eq(r.phase, Room.Phase.LOBBY)
	assert_eq(r.teams.size(), 2)
	assert_eq(r.start(1), "")
	assert_true(r.match_state.team_wins.is_empty())

func test_is_dead() -> void:
	var r := _started()
	assert_false(r.is_dead(1000.0), "des joueurs connectés")
	for id in [1, 2, 3, 4]:
		r.disconnect_player(id, 100.0)
	assert_false(r.is_dead(159.0))
	assert_true(r.is_dead(161.0))
	r.join("", r.players[2].token, 162.0)
	assert_false(r.is_dead(1000.0), "quelqu'un est revenu")

func test_tick_in_lobby_does_nothing_to_match() -> void:
	var r := _started()
	r.back_to_lobby(1)
	r.tick(1.0, {})
	assert_eq(r.match_state, null)
	assert_false(r.in_match(1))

func test_remove_player_forfeits_in_round() -> void:
	var r := _started()
	r.remove_player(2, 1.0)
	assert_eq(_life(r, 2), PlayerState.Life.GHOST, "éliminé tout de suite")
	assert_false(r.players.has(2), "plus dans la partie")
	_finish_round(r)
	_run(r, 1.0, SimConfig.SCOREBOARD_DURATION + 0.5)
	assert_eq(r.match_state.round_number, 2, "manche suivante")
	assert_false(r.match_state.world.players.has(2), "absent de la manche suivante")
