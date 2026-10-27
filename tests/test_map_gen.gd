extends TestCase

func _reachable(a: Arena, from: Vector2i) -> Dictionary:
	# Les blocs sont destructibles : on les traite comme du sol sur une copie.
	var open := Arena.create(a.width, a.height)
	open.h2 = a.h2.duplicate()
	open.stair_axis = a.stair_axis.duplicate()
	open.tiles = a.tiles.duplicate()
	for i in open.tiles.size():
		if open.tiles[i] == Arena.Tile.BLOCK:
			open.tiles[i] = Arena.Tile.FLOOR
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for n in open.walkable_neighbors(c):
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen

func test_default_layout_has_all_levels() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var a := MapGen.generate(Vector2i(19, 15), 4, rng)
	var seen := {}
	for v in a.h2:
		seen[v] = true
	for v in [-2, -1, 0, 1, 2, 3, 4]:
		assert_true(seen.has(v), "h2 %d présent" % v)
	assert_eq(a.h2_at(a.goal), 4)

func test_generate_all_sizes_ten_players() -> void:
	for k in SimConfig.MAP_SIZES:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var a := MapGen.generate(SimConfig.MAP_SIZES[k], 10, rng)
		assert_eq(a.spawns.size(), 10, k)
		var uniq := {}
		for s in a.spawns:
			uniq[s] = true
			assert_eq(a.h2_at(s), 0, k + " départ au sol")
			var r := _reachable(a, s)
			assert_true(r.has(a.goal), k + " sommet atteignable depuis %s" % s)
			for other in a.spawns:
				assert_true(r.has(other), k + " départs reliés")
		assert_eq(uniq.size(), 10, k + " départs distincts")

func test_spawn_clearance_and_no_blocks_on_summit_or_stairs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var a := MapGen.generate(Vector2i(19, 15), 10, rng)
	for y in a.height:
		for x in a.width:
			var c := Vector2i(x, y)
			if a.tile_at(c) != Arena.Tile.BLOCK:
				continue
			assert_true(a.h2_at(c) != 4, "pas de bloc au sommet")
			for s in a.spawns:
				assert_true(absi(s.x - x) + absi(s.y - y) > SimConfig.SPAWN_CLEARANCE, "bloc trop près d'un départ")

func test_block_layout_changes_with_seed() -> void:
	var r1 := RandomNumberGenerator.new()
	r1.seed = 1
	var r2 := RandomNumberGenerator.new()
	r2.seed = 2
	assert_true(MapGen.generate(Vector2i(19, 15), 4, r1).tiles != MapGen.generate(Vector2i(19, 15), 4, r2).tiles)

# Le temple est adossé au fond de la map : impossible de passer derrière le sommet.
func test_temple_backs_onto_the_far_edge() -> void:
	for k in SimConfig.MAP_SIZES:
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var a := MapGen.generate(SimConfig.MAP_SIZES[k], 10, rng)
		var summit_on_back_row := false
		for x in a.width:
			if a.h2_at(Vector2i(x, 0)) == 4:
				summit_on_back_row = true
		assert_true(summit_on_back_row, k + " sommet sur la rangée du fond")
		for y in a.height:
			for x in a.width:
				if a.h2_at(Vector2i(x, y)) == 4:
					var behind := Vector2i(x, y - 1)
					assert_true(not a.in_bounds(behind) or a.h2_at(behind) == 4, k + " rien derrière le sommet")
