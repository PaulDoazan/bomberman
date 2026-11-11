extends TestCase

# The lobby screen: team cards, the buttons each role sees, the settings form kept in step.

const SCENE := "res://src/ui/lobby_screen.tscn"

# 3 teams, 6 players (id 5 has no team and id 4 is offline), host = 0.
func _state(team_count := 3) -> Dictionary:
	var teams := []
	for i in team_count:
		teams.append({"id": i, "name": "Équipe %d" % i, "color_index": i})
	var players := [
		{"id": 0, "name": "Paul", "team": 0, "connected": true, "color": TeamColors.BASES[0]},
		{"id": 1, "name": "Ana", "team": 0, "connected": true, "color": TeamColors.tint(0, 1, 2)},
		{"id": 2, "name": "Bob", "team": 1, "connected": true, "color": TeamColors.BASES[1]},
		{"id": 3, "name": "Cy", "team": 2, "connected": true, "color": TeamColors.BASES[2]},
		{"id": 4, "name": "Dan", "team": 1, "connected": false, "color": TeamColors.tint(1, 1, 2)},
		{"id": 5, "name": "Eve", "team": -1, "connected": true, "color": Color.GRAY},
	]
	return {
		"code": "K7P2QX", "host": 0, "phase": "lobby", "can_start": false,
		"config": SimCodec.encode_config(SimConfig.new()), "teams": teams, "players": players,
	}

var sent_log: Array = []

func _with_lobby(body: Callable) -> void:
	sent_log.clear()
	var lobby: LobbyScreen = (load(SCENE) as PackedScene).instantiate()
	lobby.send_fn = func(type: int, body: Variant) -> void: sent_log.append([type, body])
	lobby.build() # tests run before the main loop exists: no tree, so no _ready
	body.call(lobby)
	lobby.free()

func test_host_view() -> void:
	_with_lobby(func(lobby: LobbyScreen) -> void:
		lobby.show_state(_state(), 0)
		assert_eq(lobby.team_cards.get_child_count(), 3, "3 cartes d'équipe")
		assert_true(lobby.start_button.visible, "Lancer visible pour l'host")
		assert_true(lobby.start_button.disabled, "Lancer désactivé : un joueur sans équipe")
		assert_true(lobby.start_button.text.contains("6/12"), "compteur de joueurs")
		assert_true(lobby.form.editable, "formulaire éditable")
		assert_eq(lobby.code_label.text, "K7P2QX", "code")
		assert_true(lobby.host_label.text.contains("Paul"), "nom de l'host")
		assert_true(lobby.no_team_label.text.contains("Eve"), "joueur sans équipe"))

func test_start_enabled_when_can_start() -> void:
	_with_lobby(func(lobby: LobbyScreen) -> void:
		var s := _state()
		s["can_start"] = true
		lobby.show_state(s, 0)
		assert_false(lobby.start_button.disabled, "Lancer actif"))

func test_guest_view() -> void:
	_with_lobby(func(lobby: LobbyScreen) -> void:
		lobby.show_state(_state(), 4)
		assert_false(lobby.start_button.visible, "Lancer masqué")
		assert_false(lobby.form.editable, "formulaire verrouillé")
		assert_false(lobby.form.visible, "réglages masqués")
		assert_false(lobby.host_label.visible, "titre masqué")
		assert_false(lobby.code_label.visible, "code masqué")
		assert_false(lobby.share_row.visible, "partage masqué")
		assert_false(lobby.leave_button.visible, "Quitter masqué")
		assert_true(lobby.waiting_label.visible, "message d'attente")
		assert_eq(lobby.waiting_label.text, "En attente du host pour lancer la partie")
		assert_eq(lobby.team_cards.get_child_count(), 3, "équipes visibles")
		assert_true(lobby.no_team_label.visible, "joueurs sans équipe visibles"))

func test_guest_sees_no_waiting_message_during_a_match() -> void:
	_with_lobby(func(lobby: LobbyScreen) -> void:
		var s := _state()
		s["phase"] = "playing"
		lobby.show_state(s, 5)
		assert_false(lobby.waiting_label.visible, "pas d'attente du host")
		assert_true(lobby.playing_label.visible, "partie en cours"))

func test_host_view_keeps_everything() -> void:
	_with_lobby(func(lobby: LobbyScreen) -> void:
		lobby.show_state(_state(), 0)
		assert_true(lobby.form.visible, "réglages")
		assert_true(lobby.code_label.visible, "code")
		assert_true(lobby.share_row.visible, "partage")
		assert_true(lobby.leave_button.visible, "Quitter")
		assert_false(lobby.waiting_label.visible, "pas d'attente"))

func test_players_listed_in_a_column() -> void:
	_with_lobby(func(lobby: LobbyScreen) -> void:
		lobby.show_state(_state(), 4)
		for chip in lobby.chips:
			assert_true(chip.get_parent() is VBoxContainer, "un joueur par ligne"))

func test_join_buttons_skip_my_team() -> void:
	_with_lobby(func(lobby: LobbyScreen) -> void:
		lobby.show_state(_state(), 2) # in team 1
		assert_eq(lobby.join_buttons.size(), 2, "3 équipes moins la mienne")
		lobby.show_state(_state(), 5) # no team
		assert_eq(lobby.join_buttons.size(), 3, "sans équipe : toutes")
		lobby.show_state(_state(), 2)
		assert_eq(lobby.team_cards.get_child_count(), 3, "pas de carte en double"))

func test_create_team_hidden_at_four_teams() -> void:
	_with_lobby(func(lobby: LobbyScreen) -> void:
		lobby.show_state(_state(3), 0)
		assert_true(lobby.create_toggle.visible, "créer visible à 3")
		lobby.show_state(_state(4), 0)
		assert_false(lobby.create_toggle.visible, "créer masqué à 4")
		assert_false(lobby.create_row.visible, "ligne masquée à 4"))

func test_create_row_toggles_and_limits_name() -> void:
	_with_lobby(func(lobby: LobbyScreen) -> void:
		lobby.show_state(_state(), 0)
		assert_false(lobby.create_row.visible, "ligne fermée au départ")
		lobby.create_toggle.pressed.emit()
		assert_true(lobby.create_row.visible, "ligne ouverte")
		assert_eq(lobby.name_edit.max_length, 16, "16 caractères"))

func test_disconnected_chip_is_greyed_and_host_starred() -> void:
	_with_lobby(func(lobby: LobbyScreen) -> void:
		lobby.show_state(_state(), 0)
		var greyed := 0
		var starred := 0
		for chip: Control in lobby.chips:
			if chip.modulate.a < 0.5:
				greyed += 1
			if (chip as Label).text.begins_with("★"):
				starred += 1
		assert_eq(greyed, 1, "un joueur grisé")
		assert_eq(starred, 1, "une étoile"))

func test_form_reloads_only_when_config_differs() -> void:
	_with_lobby(func(lobby: LobbyScreen) -> void:
		lobby.show_state(_state(), 0)
		var sent := []
		lobby.form.changed.connect(func() -> void: sent.append(1))
		var echo := _state()
		var mine := SimConfig.new()
		mine.lives = 7
		echo["config"] = SimCodec.encode_config(mine)
		lobby.form.lives.set_value(7) # the host's edit, echoed back by the server
		lobby.show_state(echo, 0)
		assert_eq(int(lobby.form.lives.value), 7, "l'écho de ma config ne recharge rien")
		assert_eq(sent.size(), 0, "load_config n'émet pas changed")
		var s := _state()
		var cfg := SimConfig.new()
		cfg.lives = 3
		cfg.round_time = 90.0
		s["config"] = SimCodec.encode_config(cfg)
		lobby.show_state(s, 0)
		assert_eq(int(lobby.form.lives.value), 3, "une config reçue différente est chargée")
		assert_almost(lobby.form.time.value, 90.0, 0.01, "chrono chargé"))

func test_error_is_shown() -> void:
	_with_lobby(func(lobby: LobbyScreen) -> void:
		lobby.show_error("cannot_start")
		assert_eq(lobby.status_label.text, Protocol.ERROR_LABELS["cannot_start"], "libellé"))

func _config_state(lives: int) -> Dictionary:
	var s := _state()
	var cfg := SimConfig.new()
	cfg.lives = lives
	for item: int in SimConfig.Item.values(): # as the form (and so the server) has them
		cfg.items[item] = true
	s["config"] = SimCodec.encode_config(cfg)
	return s

func test_older_echo_does_not_undo_newer_edit() -> void:
	_with_lobby(func(lobby: LobbyScreen) -> void:
		lobby.show_state(_state(), 0)
		lobby.form.lives.set_value(4) # A
		lobby.form.changed.emit()
		lobby.form.lives.set_value(5) # B
		lobby.form.changed.emit()
		lobby.show_state(_config_state(4), 0) # echo of A
		assert_eq(int(lobby.form.lives.value), 5, "l'écho de A laisse B")
		assert_eq(lobby._pending_sent.size(), 1, "B reste en attente")
		lobby.show_state(_config_state(5), 0) # echo of B
		assert_eq(int(lobby.form.lives.value), 5, "l'écho de B ne change rien")
		assert_true(lobby._pending_sent.is_empty(), "plus rien en attente"))

func test_foreign_config_reloads_and_clears_pending() -> void:
	_with_lobby(func(lobby: LobbyScreen) -> void:
		lobby.show_state(_state(), 0)
		lobby.form.lives.set_value(5)
		lobby.form.changed.emit()
		lobby.show_state(_config_state(2), 0) # not ours
		assert_eq(int(lobby.form.lives.value), 2, "config étrangère chargée")
		assert_true(lobby._pending_sent.is_empty(), "attente vidée"))

func test_sent_messages() -> void:
	_with_lobby(func(lobby: LobbyScreen) -> void:
		lobby.show_state(_state(), 0)
		lobby.join_buttons[0].pressed.emit() # first team that is not mine (team 1)
		lobby.name_edit.text = "  Les Fous "
		lobby.create_toggle.pressed.emit()
		lobby.create_button.pressed.emit()
		lobby.form.lives.set_value(6)
		lobby.form.changed.emit()
		lobby.start_button.pressed.emit()
		assert_eq(sent_log.size(), 4, "4 messages")
		assert_eq(sent_log[0], [Protocol.Msg.JOIN_TEAM, {"team": 1}], "JOIN_TEAM")
		assert_eq(sent_log[1], [Protocol.Msg.CREATE_TEAM, {"name": "Les Fous"}], "CREATE_TEAM")
		assert_eq(sent_log[2][0], Protocol.Msg.SETTINGS, "SETTINGS")
		assert_eq((sent_log[2][1]["config"] as Dictionary)["lives"], 6, "config envoyée")
		assert_eq(sent_log[3], [Protocol.Msg.START, {}], "START")
		assert_false(lobby.create_row.visible, "ligne masquée après envoi"))

func test_match_running_view() -> void:
	_with_lobby(func(lobby: LobbyScreen) -> void:
		var s := _state()
		s["phase"] = "playing"
		lobby.show_state(s, 0) # the host
		assert_false(lobby.start_button.visible, "Lancer masqué pendant la partie")
		assert_false(lobby.form.editable, "réglages en lecture seule pour l'host")
		assert_true(lobby.playing_label.visible, "ligne Partie en cours")
		assert_true(lobby.playing_label.text.begins_with("Partie en cours"), "texte")
		lobby.show_state(s, 5) # the newcomer, without a team
		assert_eq(lobby.join_buttons.size(), 3, "Rejoindre sur chaque équipe")
		assert_true(lobby.create_toggle.visible, "+ Créer une équipe")
		assert_false(lobby.form.editable, "réglages en lecture seule")
		s["phase"] = "lobby"
		lobby.show_state(s, 0)
		assert_false(lobby.playing_label.visible, "ligne masquée au salon")
		assert_true(lobby.start_button.visible, "Lancer de retour"))
