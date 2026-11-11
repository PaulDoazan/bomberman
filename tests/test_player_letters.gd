extends TestCase

# Players carry no name in the game: nothing is written on the characters.
func test_players_wear_no_letters() -> void:
	var ms := MatchState.new(SimConfig.new(), RandomNumberGenerator.new())
	ms.player(0).name = "Paul"
	var view := ActorsView.new()
	view._ready()
	view.sync(ms.world, ms)
	assert_true(view._players[0].find_children("*", "Label3D", true, false).is_empty(), "pas de lettres")
	view.free()
