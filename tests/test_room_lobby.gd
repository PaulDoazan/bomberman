extends TestCase

func _room() -> Room:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	return Room.new("K7P2QX", rng)

# Room with players a(1), b(2) in teams 0 and 1.
func _ready_room() -> Room:
	var r := _room()
	var a: int = r.join("Ann", "", 0.0)["id"]
	var b: int = r.join("Bob", "", 0.0)["id"]
	r.create_team(a, "Rouge")
	r.create_team(b, "Bleu")
	return r

func test_normalize() -> void:
	assert_eq(RoomCodes.normalize("#k7p2qx"), "K7P2QX")
	assert_eq(RoomCodes.normalize("k7p2 qx/"), "K7P2QX")
	assert_eq(RoomCodes.normalize("#K7P2QX/"), "K7P2QX")
	assert_eq(RoomCodes.normalize("K7P2Q0"), "")
	assert_eq(RoomCodes.normalize("ABC"), "")

func test_generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var taken := {}
	for i in 200:
		var c := RoomCodes.generate(rng, taken)
		assert_eq(c.length(), 6)
		assert_eq(RoomCodes.normalize(c), c, "alphabet")
		assert_false(taken.has(c), "évite les codes pris")
		taken[c] = true

func test_first_join_is_host() -> void:
	var r := _room()
	var j := r.join("Paul", "", 0.0)
	assert_eq(r.host_id, j["id"])
	assert_eq(String(j["token"]).length(), 16)
	var j2 := r.join("Zoé", "", 0.0)
	assert_eq(r.host_id, j["id"])
	assert_true(j2["id"] > j["id"])

func test_thirteenth_join_is_full_even_with_disconnected() -> void:
	var r := _room()
	for i in 12:
		var j := r.join("p%d" % i, "", 0.0)
		if i % 2 == 0:
			r.disconnect_player(j["id"], 1.0)
	assert_eq(r.join("extra", "", 2.0).get("error"), Protocol.ERR_FULL)

func test_names() -> void:
	var r := _room()
	r.join("Paul", "", 0.0)
	assert_eq(r.join(" paul ", "", 0.0).get("error"), Protocol.ERR_NAME_TAKEN)
	assert_eq(r.join("", "", 0.0).get("error"), Protocol.ERR_BAD_NAME)
	assert_eq(r.join("   ", "", 0.0).get("error"), Protocol.ERR_BAD_NAME)
	assert_eq(r.join("abcdefghijklm", "", 0.0).get("error"), Protocol.ERR_BAD_NAME)
	assert_false(r.join("abcdefghijkl", "", 0.0).has("error"))

func test_reconnect_by_token() -> void:
	var r := _ready_room()
	var j := r.join("Cid", "", 0.0)
	r.join_team(j["id"], 0)
	r.disconnect_player(j["id"], 5.0)
	assert_false(r.players[j["id"]].connected)
	var back := r.join("Autre", j["token"], 9.0)
	assert_eq(back["id"], j["id"])
	assert_eq(back["token"], j["token"])
	assert_true(r.players[j["id"]].connected)
	assert_eq(r.players[j["id"]].team, 0)
	assert_eq(r.players[j["id"]].name, "Cid")

func test_reconnect_when_full() -> void:
	var r := _room()
	var first := r.join("p0", "", 0.0)
	for i in range(1, 12):
		r.join("p%d" % i, "", 0.0)
	r.disconnect_player(first["id"], 1.0)
	assert_eq(r.join("x", first["token"], 2.0)["id"], first["id"])

func test_team_colors_and_limit() -> void:
	var r := _room()
	var ids: Array[int] = []
	for i in 5:
		ids.append(r.join("p%d" % i, "", 0.0)["id"])
	for i in 4:
		assert_eq(r.create_team(ids[i], "T%d" % i), "")
		assert_eq(r.teams[r.players[ids[i]].team].color_index, i)
	assert_eq(r.create_team(ids[4], "T5"), Protocol.ERR_TEAMS_FULL)
	assert_eq(r.create_team(ids[4], ""), Protocol.ERR_BAD_NAME)
	assert_eq(r.create_team(ids[4], "01234567890123456"), Protocol.ERR_BAD_NAME)
	# Leaving the last member removes the team and frees its colour.
	var t1: int = r.players[ids[1]].team
	assert_eq(r.leave_team(ids[1]), "")
	assert_false(r.teams.has(t1))
	assert_eq(r.create_team(ids[4], "Neuve"), "")
	assert_eq(r.teams[r.players[ids[4]].team].color_index, 1)

func test_join_team_moves_player() -> void:
	var r := _ready_room()
	var c: int = r.join("Cid", "", 0.0)["id"]
	assert_eq(r.join_team(c, 99), Protocol.ERR_NOT_NOW)
	assert_eq(r.join_team(c, 0), "")
	assert_eq(r.players[c].team, 0)
	assert_eq(r.join_team(c, 1), "")
	assert_eq(r.teams.size(), 2)

func test_start_rules() -> void:
	var r := _ready_room()
	assert_eq(r.start(2), Protocol.ERR_HOST_ONLY)
	assert_eq(r.start(99), Protocol.ERR_NOT_NOW)
	var c: int = r.join("Cid", "", 0.0)["id"]
	assert_false(r.can_start(), "joueur sans équipe")
	assert_eq(r.start(1), Protocol.ERR_CANNOT_START)
	r.join_team(c, 0)
	assert_true(r.can_start())
	r.leave_team(2)
	assert_eq(r.start(1), Protocol.ERR_CANNOT_START, "joueur sans équipe")
	r.join_team(2, 0)
	assert_true(r.can_start(), "une seule équipe suffit")

func test_start_needs_two_players() -> void:
	var r := _room()
	var a: int = r.join("Ann", "", 0.0)["id"]
	r.create_team(a, "Rouge")
	assert_false(r.can_start(), "seul")
	var b: int = r.join("Bob", "", 0.0)["id"]
	r.join_team(b, 0)
	assert_true(r.can_start(), "deux dans la même équipe")

func test_start_builds_match() -> void:
	var r := _ready_room()
	var c: int = r.join("Cid", "", 0.0)["id"]
	r.join_team(c, 0)
	assert_eq(r.start(1), "")
	assert_eq(r.phase, Room.Phase.PLAYING)
	assert_eq(r.match_state.players.size(), 3)
	for mp in r.match_state.players:
		var rp: Room.RoomPlayer = r.players[mp.id]
		assert_eq(mp.team, rp.team)
		assert_eq(mp.name, rp.name)
		assert_false(mp.is_bot)
		assert_eq(mp.tag, MatchState.tag_of(rp.name))
		assert_true(mp.tag != "")
		var rank := 1 if mp.id == c else 0
		var count := 2 if rp.team == 0 else 1
		assert_eq(mp.color, TeamColors.tint(r.teams[rp.team].color_index, rank, count))
	assert_eq(r.start(1), Protocol.ERR_NOT_NOW, "déjà en partie")

func test_team_changes_during_play() -> void:
	var r := _ready_room()
	r.start(1)
	assert_eq(r.leave_team(1), Protocol.ERR_NOT_NOW)
	assert_eq(r.join_team(1, 1), Protocol.ERR_NOT_NOW)
	var n: int = r.join("Neo", "", 5.0)["id"]
	assert_eq(r.join_team(n, 0), "")
	assert_eq(r.leave_team(n), "")
	assert_eq(r.join_team(n, 1), "")

func test_host_transfer() -> void:
	var r := _room()
	var a: int = r.join("A", "", 0.0)["id"]
	var tok: String = r.players[a].token
	var b: int = r.join("B", "", 0.0)["id"]
	r.join("C", "", 0.0)
	r.disconnect_player(a, 1.0)
	assert_eq(r.host_id, b)
	r.join("", tok, 2.0)
	assert_eq(r.host_id, b)

func test_set_config_host_only() -> void:
	var r := _room()
	var a: int = r.join("A", "", 0.0)["id"]
	var b: int = r.join("B", "", 0.0)["id"]
	var cfg := SimConfig.new()
	cfg.lives = 5
	assert_eq(r.set_config(b, cfg), Protocol.ERR_HOST_ONLY)
	assert_eq(r.set_config(99, cfg), Protocol.ERR_NOT_NOW)
	assert_eq(r.set_config(a, cfg), "")
	assert_eq(r.config.lives, 5)

func test_scores_reset_on_start() -> void:
	var r := _ready_room()
	r.start(1)
	r.match_state.team_wins[0] = 3
	assert_eq(r.back_to_lobby(2), Protocol.ERR_HOST_ONLY)
	assert_eq(r.back_to_lobby(1), "")
	assert_eq(r.phase, Room.Phase.LOBBY)
	assert_eq(r.back_to_lobby(1), Protocol.ERR_NOT_NOW)
	r.start(1)
	assert_true(r.match_state.team_wins.is_empty())

func test_lobby_state() -> void:
	var r := _ready_room()
	var c: int = r.join("Cid", "", 0.0)["id"]
	var s := r.lobby_state()
	assert_eq(s["code"], "K7P2QX")
	assert_eq(s["host"], 1)
	assert_eq(s["phase"], "lobby")
	assert_false(s["can_start"])
	assert_eq(s["teams"].size(), 2)
	assert_eq(s["teams"][0]["color_index"], 0)
	assert_eq(s["config"], SimCodec.encode_config(r.config))
	var by_id := {}
	for p in s["players"]:
		by_id[p["id"]] = p
	assert_eq(by_id[1]["color"], TeamColors.BASES[0])
	assert_eq(by_id[c]["team"], -1)
	assert_eq(by_id[c]["color"], Color(0.6, 0.6, 0.6))
	assert_true(by_id[c]["connected"])
	r.join_team(c, 0)
	r.start(1)
	assert_eq(r.lobby_state()["phase"], "playing")

func test_host_reelected_when_sole_host_left_and_someone_joins() -> void:
	var r := _room()
	var a: int = r.join("A", "", 0.0)["id"]
	r.disconnect_player(a, 1.0)
	assert_eq(r.host_id, a, "personne d'autre")
	var b: int = r.join("B", "", 2.0)["id"]
	assert_eq(r.host_id, b)

func test_host_reelected_when_other_reconnects() -> void:
	var r := _room()
	var a: int = r.join("A", "", 0.0)["id"]
	var b: Dictionary = r.join("B", "", 0.0)
	r.disconnect_player(b["id"], 1.0)
	r.disconnect_player(a, 2.0)
	assert_eq(r.host_id, a)
	r.join("", b["token"], 3.0)
	assert_eq(r.host_id, b["id"])

func test_disconnect_twice_keeps_first_time() -> void:
	var r := _room()
	var a: int = r.join("A", "", 0.0)["id"]
	r.disconnect_player(a, 5.0)
	r.disconnect_player(a, 50.0)
	assert_almost(r.players[a].disconnected_at, 5.0)

func test_control_characters_refused() -> void:
	var r := _room()
	assert_eq(r.join("Pa\nul", "", 0.0).get("error"), Protocol.ERR_BAD_NAME)
	assert_eq(r.join("Pa\u007ful", "", 0.0).get("error"), Protocol.ERR_BAD_NAME)
	var a: int = r.join("Paul", "", 0.0)["id"]
	assert_eq(r.create_team(a, "Ro\tuge"), Protocol.ERR_BAD_NAME)
	assert_eq(r.create_team(a, "Rouge"), "")

func test_remove_player_frees_place_team_and_host() -> void:
	var r := _ready_room()
	var c: int = r.join("Cid", "", 0.0)["id"]
	r.join_team(c, 1)
	r.remove_player(1, 5.0)
	assert_false(r.players.has(1), "plus dans la partie")
	assert_false(r.teams.has(0), "équipe vide supprimée")
	assert_eq(r.host_id, 2, "nouvel host")
	r.remove_player(2, 6.0)
	assert_eq(r.teams.size(), 1, "l'équipe de Cid reste")
	assert_eq(r.host_id, c, "Cid est host")
	assert_false(r.is_dead(100.0), "Cid est encore là")
	r.remove_player(c, 7.0)
	assert_true(r.players.is_empty(), "personne")
	assert_true(r.is_dead(7.0 + Room.EMPTY_ROOM_TTL), "partie vide oubliée")
