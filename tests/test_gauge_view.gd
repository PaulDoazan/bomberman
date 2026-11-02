extends TestCase

# En chargeant un lancer, une jauge en triangle, comme un volume, se remplit depuis sa pointe.
func test_the_throw_gauge_fills_like_a_volume_control() -> void:
	var w := World.new(Fixtures.flat(9, 5), [0], SimConfig.new(), RandomNumberGenerator.new())
	var p: PlayerState = w.players[0]
	var ms := MatchState.new(SimConfig.new(), RandomNumberGenerator.new())
	var view := ActorsView.new()
	view._ready()
	view._sync_players(w, ms)
	var n: ActorsView.PlayerNode = view._players[0]
	assert_false(n.gauge.visible, "cachée sans lancer")
	p.held = PlayerState.Held.BLOCK
	p.charging = true
	p.charge = 0.5
	view._sync_players(w, ms)
	assert_true(n.gauge.visible, "visible en chargeant")
	var fill: AABB = n.gauge_fill.mesh.get_aabb()
	assert_almost(fill.size.x, ActorsView.GAUGE_SIZE.x, 1e-4, "un triangle aussi large que la jauge")
	assert_almost(fill.size.y, ActorsView.GAUGE_SIZE.y, 1e-4)
	assert_almost(n.gauge_fill.scale.x, 0.5, 1e-4, "à moitié")
	assert_almost(n.gauge_fill.scale.y, 0.5, 1e-4, "rétréci depuis la pointe")
	view.free()
