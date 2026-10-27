class_name MapGen
extends RefCounted

# Where the left-half pillars go, as fractions of the map size (each is mirrored on the right).
const PILLAR_ANCHORS: Array[Vector2] = [Vector2(0.1, 0.2), Vector2(0.1, 0.55), Vector2(0.3, 0.7), Vector2(0.15, 0.9)]

static func generate(size: Vector2i, player_count: int, rng: RandomNumberGenerator) -> Arena:
	var w := size.x
	var h := size.y
	var a := Arena.create(w, h)
	var cx := w / 2

	# Raised levels and pit (inclusive bounds). The temple backs onto the far edge (y = 0),
	# so nobody can walk behind the summit.
	var a1 := roundi(w * 0.22)
	var l1_y0 := 0
	var l1_y1 := roundi(h * 0.44)
	var a2 := maxi(1, roundi(w * 0.09))
	var l2_y0 := 0
	var l2_y1 := maxi(2, roundi(h * 0.2)) - 1
	var ap := roundi(w * 0.13)
	var pit_y0 := roundi(h * 0.6) + 3
	var pit_y1 := h - 2
	var l1_x0 := cx - a1
	var l1_x1 := cx + a1
	var l2_x0 := cx - a2
	var l2_x1 := cx + a2
	var pit_x0 := cx - ap
	var pit_x1 := cx + ap

	_fill(a, l1_x0, l1_x1, l1_y0, l1_y1, 2)
	_fill(a, l2_x0, l2_x1, l2_y0, l2_y1, 4)
	_fill(a, pit_x0, pit_x1, pit_y0, pit_y1, -2)

	# Stairs. Cells just outside a stair on the ground lose their pillar.
	var cleared := {}
	var ym := (l1_y0 + l1_y1) / 2
	for dy in 2:
		_stair(a, Vector2i(l1_x0 - 1, ym + dy), 1, Arena.Axis.X)
		_stair(a, Vector2i(l1_x1 + 1, ym + dy), 1, Arena.Axis.X)
		cleared[Vector2i(l1_x0 - 2, ym + dy)] = true
		cleared[Vector2i(l1_x1 + 2, ym + dy)] = true
	for x in range(cx - 1, cx + 2):
		_stair(a, Vector2i(x, l1_y1 + 1), 1, Arena.Axis.Y)
		cleared[Vector2i(x, l1_y1 + 2)] = true
	_stair(a, Vector2i(cx, l2_y1 + 1), 3, Arena.Axis.Y)
	var pit_ym := (pit_y0 + pit_y1) / 2
	_stair(a, Vector2i(pit_x0 - 1, pit_ym), -1, Arena.Axis.X)
	_stair(a, Vector2i(pit_x1 + 1, pit_ym), -1, Arena.Axis.X)
	cleared[Vector2i(pit_x0 - 2, pit_ym)] = true
	cleared[Vector2i(pit_x1 + 2, pit_ym)] = true

	# A few pillars on ground cells with odd x and odd y: the one nearest each anchor on the
	# left half, mirrored on the right half.
	var candidates: Array[Vector2i] = []
	for y in range(1, h, 2):
		for x in range(1, cx, 2):
			var c := Vector2i(x, y)
			if a.h2_at(c) == 0 and a.tile_at(c) == Arena.Tile.FLOOR and not cleared.has(c):
				candidates.append(c)
	for anchor in PILLAR_ANCHORS:
		if candidates.is_empty():
			break
		var target := Vector2(anchor.x * w, anchor.y * h)
		var best := candidates[0]
		for c in candidates:
			if Vector2(c).distance_squared_to(target) < Vector2(best).distance_squared_to(target):
				best = c
		candidates.erase(best)
		a.set_tile(best, Arena.Tile.PILLAR)
		a.set_tile(Vector2i(w - 1 - best.x, best.y), Arena.Tile.PILLAR)

	a.goal = Vector2i(cx, (l2_y0 + l2_y1) / 2)

	# Spawns: evenly spaced along the clockwise ground perimeter.
	var perim: Array[Vector2i] = []
	for x in w:
		perim.append(Vector2i(x, 0))
	for y in range(1, h):
		perim.append(Vector2i(w - 1, y))
	for x in range(w - 2, -1, -1):
		perim.append(Vector2i(x, h - 1))
	for y in range(h - 2, 0, -1):
		perim.append(Vector2i(0, y))
	perim = perim.filter(func(c: Vector2i) -> bool: return a.h2_at(c) == 0)
	for i in player_count:
		a.spawns.append(perim[i * perim.size() / player_count])

	# Destructible blocks.
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			if a.tile_at(c) != Arena.Tile.FLOOR or a.h2_at(c) == 4 or c == a.goal:
				continue
			var near_spawn := false
			for s in a.spawns:
				if absi(s.x - x) + absi(s.y - y) <= SimConfig.SPAWN_CLEARANCE:
					near_spawn = true
					break
			if near_spawn:
				continue
			if rng.randf() < SimConfig.BLOCK_DENSITY:
				a.set_tile(c, Arena.Tile.BLOCK)
	return a

static func _fill(a: Arena, x0: int, x1: int, y0: int, y1: int, h2v: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			a.set_cell(Vector2i(x, y), Arena.Tile.FLOOR, h2v)

static func _stair(a: Arena, c: Vector2i, h2v: int, axis: int) -> void:
	a.set_cell(c, Arena.Tile.STAIRS, h2v, axis)
