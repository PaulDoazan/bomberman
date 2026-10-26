extends TestCase

func test_step_rules() -> void:
	var a := Fixtures.flat(5, 5)
	a.set_cell(Vector2i(2, 2), Arena.Tile.STAIRS, 1, Arena.Axis.X)
	a.set_cell(Vector2i(3, 2), Arena.Tile.FLOOR, 2)
	assert_true(a.can_step(Vector2i(1, 2), Vector2i(2, 2)), "monter sur l'escalier dans l'axe")
	assert_true(a.can_step(Vector2i(2, 2), Vector2i(3, 2)), "escalier vers l'étage")
	assert_false(a.can_step(Vector2i(2, 1), Vector2i(2, 2)), "entrer sur l'escalier par le côté")
	assert_false(a.can_step(Vector2i(3, 1), Vector2i(3, 2)), "sol vers l'étage sans escalier")
	assert_false(a.can_step(Vector2i(0, 0), Vector2i(-1, 0)), "hors grille")
	a.set_tile(Vector2i(1, 1), Arena.Tile.PILLAR)
	assert_false(a.can_step(Vector2i(0, 1), Vector2i(1, 1)), "pilier")

func test_level_of() -> void:
	assert_eq(Arena.level_of(-1), -1)
	assert_eq(Arena.level_of(1), 0)
	assert_eq(Arena.level_of(4), 2)

func test_diagonal_and_solid_rules() -> void:
	var a := Fixtures.flat(5, 5)
	a.set_cell(Vector2i(2, 2), Arena.Tile.STAIRS, 1, Arena.Axis.X)
	assert_false(a.can_step(Vector2i(1, 1), Vector2i(2, 2)), "diagonale vers escalier")
	assert_true(a.can_step(Vector2i(0, 0), Vector2i(1, 1)), "diagonale au sol")
	assert_true(a.is_solid(Vector2i(-1, 0)), "hors grille solide")
	a.set_tile(Vector2i(3, 3), Arena.Tile.BLOCK)
	assert_true(a.is_solid(Vector2i(3, 3)), "bloc solide")
	assert_false(a.is_solid(Vector2i(0, 0)), "sol non solide")

func test_walkable_neighbors_and_coords() -> void:
	var a := Fixtures.flat(3, 3)
	assert_eq(a.walkable_neighbors(Vector2i(0, 0)).size(), 2, "coin")
	assert_eq(a.walkable_neighbors(Vector2i(1, 1)).size(), 4, "centre")
	assert_eq(Arena.cell_of(Vector2(2.7, 1.2)), Vector2i(2, 1))
	assert_eq(Arena.cell_of(Vector2(-0.2, 0.5)), Vector2i(-1, 0))
	assert_eq(Arena.center_of(Vector2i(2, 1)), Vector2(2.5, 1.5))
