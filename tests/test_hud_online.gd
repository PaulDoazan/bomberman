extends TestCase

func _match() -> MatchState:
	var ms := MatchState.new(SimConfig.new(), RandomNumberGenerator.new())
	for mp in ms.players:
		mp.team = mp.id % 2
	ms.team_wins = {0: 2, 1: 1}
	ms.last_winners = [0]
	ms.phase_timer = 4.0
	return ms

func test_team_scoreboard_sorted_by_wins() -> void:
	var ms := _match()
	var text := Hud.team_scoreboard_text(ms, {0: "Les Pétards", 1: "Team Mèche"})
	assert_true(text.find("Les Pétards : 🏆 2") >= 0, "équipe 0")
	assert_true(text.find("Les Pétards : 🏆 2") < text.find("Team Mèche : 🏆 1"), "triées")
	assert_true(text.find("Vainqueur : Les Pétards") >= 0, "vainqueur")
	assert_true(text.find("Manche suivante dans 4 s") >= 0, "compte à rebours")

func test_team_scoreboard_waits_for_server() -> void:
	var ms := _match()
	ms.hold_next_round = true
	var text := Hud.team_scoreboard_text(ms, {0: "A", 1: "B"})
	assert_true(text.find("En attente d'une autre équipe") >= 0, "attente")
	assert_true(text.find("Manche suivante") < 0, "pas de compte à rebours")

func test_team_scoreboard_tie_lists_teams() -> void:
	var ms := _match()
	ms.last_winners = [0, 1]
	var text := Hud.team_scoreboard_text(ms, {0: "A", 1: "B"})
	assert_true(text.find("Ex aequo : A, B") >= 0, "ex aequo")

func test_team_scoreboard_skips_deleted_teams() -> void:
	var ms := _match()
	ms.team_wins[7] = 3 # a team whose members all left
	var text := Hud.team_scoreboard_text(ms, {0: "A", 1: "B"})
	assert_true(text.find("Équipe 7") < 0, "équipe disparue absente")
	assert_true(text.find("A : 🏆 2") >= 0, "les autres restent")
