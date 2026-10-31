extends TestCase

# Une bombe a une petite mèche, et on la voit rouler : immobile, la mèche reste en haut ; frappée
# du pied, la bombe tourne sur elle-même d'autant qu'elle a roulé.
func test_a_kicked_bomb_rolls_its_fuse_around() -> void:
	var w := World.new(Fixtures.flat(12, 3), [0], SimConfig.new(), RandomNumberGenerator.new())
	w.players[0].pos = Vector2(0.5, 0.5)
	var b := w.add_bomb(0, Vector2i(2, 1), 100.0)
	var ms := MatchState.new(SimConfig.new(), RandomNumberGenerator.new())
	var view := ActorsView.new()
	view._ready()
	view._sync_bombs(w)
	var m: Node3D = view._bombs[b.id]
	assert_true(m.find_child("Fuse", true, false) != null, "une mèche")
	for _t in 10:
		w.step({})
		view._sync_bombs(w)
	view.render(1.0)
	assert_almost(m.basis.y.normalized().dot(Vector3.UP), 1.0, 1e-4, "immobile : mèche en haut")
	var from := b.pos()
	b.roll_heading = Vector2i(1, 0)
	b.roll_dir = Vector2i(1, 0)
	for _t in 4:
		w.step({})
		view._sync_bombs(w)
	view.render(1.0)
	var rolled := b.pos().x - from.x
	assert_true(rolled > 0.3, "a roulé")
	var up := m.basis.y.normalized()
	assert_almost(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0)), rolled / SimConfig.BOMB_BODY_RADIUS, 1e-3, "tournée d'autant qu'elle a roulé")
	assert_true(up.x > 0.0, "roule vers l'avant : le haut part vers +x")
	view.free()
