class_name Arena
extends RefCounted

enum Tile { FLOOR, PILLAR, BLOCK, STAIRS }
enum Axis { NONE, X, Y }

const ORTHOGONAL: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var width: int
var height: int
var h2: PackedInt32Array
var tiles: PackedInt32Array
var stair_axis: PackedInt32Array
var spawns: Array[Vector2i] = []
var goal: Vector2i = Vector2i.ZERO

static func create(w: int, h: int) -> Arena:
	var a := Arena.new()
	a.width = w
	a.height = h
	a.h2 = PackedInt32Array()
	a.h2.resize(w * h)
	a.tiles = PackedInt32Array()
	a.tiles.resize(w * h)
	a.stair_axis = PackedInt32Array()
	a.stair_axis.resize(w * h)
	return a

static func level_of(h2v: int) -> int:
	return floori(h2v / 2.0)

static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))

static func center_of(c: Vector2i) -> Vector2:
	return Vector2(c.x + 0.5, c.y + 0.5)

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height

func h2_at(c: Vector2i) -> int:
	return h2[c.y * width + c.x]

func tile_at(c: Vector2i) -> int:
	return tiles[c.y * width + c.x]

func axis_at(c: Vector2i) -> int:
	return stair_axis[c.y * width + c.x]

func set_cell(c: Vector2i, tile: int, h2v: int, axis: int = Axis.NONE) -> void:
	var i := c.y * width + c.x
	tiles[i] = tile
	h2[i] = h2v
	stair_axis[i] = axis

func set_tile(c: Vector2i, tile: int) -> void:
	tiles[c.y * width + c.x] = tile

func is_solid(c: Vector2i) -> bool:
	if not in_bounds(c):
		return true
	var t := tile_at(c)
	return t == Tile.PILLAR or t == Tile.BLOCK

# Terrain only: b must be adjacent (Chebyshev 1) to a. Ignores bombs and players.
# Climbing is limited to one half-level, so going up only works through stairs (in any
# direction). Jumping down from a ledge is allowed whatever the drop.
func can_step(a: Vector2i, b: Vector2i) -> bool:
	if not in_bounds(a) or is_solid(b):
		return false
	return h2_at(b) - h2_at(a) <= 1

# Orthogonal neighbours reachable by can_step.
func walkable_neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in ORTHOGONAL:
		if can_step(c, c + d):
			out.append(c + d)
	return out
