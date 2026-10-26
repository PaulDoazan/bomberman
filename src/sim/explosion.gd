class_name Explosion
extends RefCounted

var origin: Vector2i
var cells: Array[Vector2i] = []
var timer := SimConfig.EXPLOSION_DURATION
var owner_id: int

# Hemisphere: round, never goes below the origin's level, blocked by pillars and blocks.
static func hit_cells(arena: Arena, origin: Vector2i, radius: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var min_h2 := 2 * Arena.level_of(arena.h2_at(origin))
	var r := ceili(radius)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if Vector2(dx, dy).length() > radius:
				continue
			var c := origin + Vector2i(dx, dy)
			if not arena.in_bounds(c) or arena.tile_at(c) == Arena.Tile.PILLAR:
				continue
			if arena.h2_at(c) < min_h2:
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
