extends TestCase

# The drawn stairs have a low step on the side of the lower level and a high step on the
# side of the higher level; players are drawn on the highest step under their feet.
func test_surface_follows_the_two_steps() -> void:
	var a := Fixtures.flat(5, 5)
	a.set_cell(Vector2i(2, 2), Arena.Tile.STAIRS, 1, Arena.Axis.X)
	a.set_cell(Vector2i(3, 2), Arena.Tile.FLOOR, 2)
	assert_almost(ArenaView.surface_y(a, Vector2(2.25, 2.5)), 0.25, 0.001, "marche basse")
	assert_almost(ArenaView.surface_y(a, Vector2(2.75, 2.5)), 0.5, 0.001, "marche haute")
	assert_almost(ArenaView.surface_y(a, Vector2(1.5, 2.5)), 0.0, 0.001, "sol")
