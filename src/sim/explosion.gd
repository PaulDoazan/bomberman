class_name Explosion
extends RefCounted

var origin: Vector2i
var centre: Vector2 # where the bomb was when it went off; the sphere grows from here
var cells: Array[Vector2i] = []
var timer := SimConfig.EXPLOSION_DURATION
var owner_id: int

const GROW_START := 0.2 # sphere size when it appears, as a fraction of its full radius
const BODY_HEIGHT := 1.0 # a player's body height, for a blast from above reaching their head

# Current sphere radius: grows from GROW_START to full over the explosion's duration.
func radius() -> float:
	var t := clampf(1.0 - timer / SimConfig.EXPLOSION_DURATION, 0.0, 1.0)
	return SimConfig.BOMB_RADIUS * lerpf(GROW_START, 1.0, t)

# True if the sphere, at its current size, reaches the body of a player standing at pos (feet
# on the ground of their cell, box of PLAYER_HALF around pos, BODY_HEIGHT tall).
func touches(arena: Arena, pos: Vector2) -> bool:
	var flat := maxf(0.0, pos.distance_to(centre) - SimConfig.PLAYER_HALF)
	var dz := (arena.h2_at(Arena.cell_of(pos)) - arena.h2_at(origin)) * 0.5 # feet above the bomb
	var up := dz if dz > 0.0 else maxf(0.0, -(dz + BODY_HEIGHT))
	return Vector2(flat, up).length() <= radius()

# Full sphere around the bomb's ground: reaches up and down, the height difference counting
# in the distance; pillars and blocks shield what is behind them.
static func hit_cells(arena: Arena, origin: Vector2i, radius: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := ceili(radius)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := origin + Vector2i(dx, dy)
			if not arena.in_bounds(c) or arena.tile_at(c) == Arena.Tile.PILLAR:
				continue
			var dz := (arena.h2_at(c) - arena.h2_at(origin)) * 0.5
			if Vector3(dx, dy, dz).length() > radius:
				continue
			if _shielded(arena, origin, c):
				continue
			out.append(c)
	return out

static func _is_shield(arena: Arena, c: Vector2i) -> bool:
	if not arena.in_bounds(c):
		return true
	var t := arena.tile_at(c)
	return t == Arena.Tile.PILLAR or t == Arena.Tile.BLOCK

# Supercover walk from centre to centre; true if a cell strictly between is a shield.
static func _shielded(arena: Arena, from: Vector2i, to: Vector2i) -> bool:
	var d := to - from
	var nx := absi(d.x)
	var ny := absi(d.y)
	var s := Vector2i(signi(d.x), signi(d.y))
	var p := from
	var ix := 0
	var iy := 0
	while ix < nx or iy < ny:
		var decision := (1 + 2 * ix) * ny - (1 + 2 * iy) * nx
		if decision == 0:
			# Exact corner crossing: both side cells are touched.
			if _is_shield(arena, Vector2i(p.x + s.x, p.y)) or _is_shield(arena, Vector2i(p.x, p.y + s.y)):
				return true
			p += s
			ix += 1
			iy += 1
		elif decision < 0:
			p.x += s.x
			ix += 1
		else:
			p.y += s.y
			iy += 1
		if p != to and _is_shield(arena, p):
			return true
	return false
