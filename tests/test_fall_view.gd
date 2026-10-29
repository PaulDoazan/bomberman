extends TestCase

# Walking off a ledge draws a jump: the body first rises a little, then falls to the level below.
func test_walking_off_a_ledge_jumps() -> void:
	var a := Fixtures.flat(9, 3)
	for y in 3:
		for x in 4:
			a.set_cell(Vector2i(x, y), Arena.Tile.FLOOR, 2)
	var w := World.new(a, [0], SimConfig.new(), RandomNumberGenerator.new())
	w.players[0].pos = Vector2(3.0, 1.5)
	var ms := MatchState.new(SimConfig.new(), RandomNumberGenerator.new())
	var view := ActorsView.new()
	view._ready()
	view._sync_players(w, ms)
	var n: ActorsView.PlayerNode = view._players[0]
	var top := n.y_smooth
	assert_almost(top, 1.0, 0.001, "sur l'étage")
	var go := PlayerIntent.new()
	go.moving = true
	go.target = Vector2(8.5, 1.5)
	var highest := top
	var lowest := top
	var landed_at := -1
	for t in 30:
		w.step({0: go})
		view._sync_players(w, ms)
		highest = maxf(highest, n.y_smooth)
		lowest = minf(lowest, n.y_smooth)
		if landed_at == -1 and is_equal_approx(n.y_smooth, 0.0):
			landed_at = t
	assert_true(highest > top + 0.05, "monte d'abord (saut)")
	assert_almost(lowest, 0.0, 0.001, "jamais sous le sol d'arrivée")
	assert_true(landed_at > 3, "met quelques ticks à retomber (%d)" % landed_at)
	assert_almost(n.y_smooth, 0.0, 0.001, "posé en bas")
	view.free()
