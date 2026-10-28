class_name Movement
extends RefCounted

const EPS := 1e-4

# True when the player's box (centre pos, half-side PLAYER_HALF) overlaps cell c.
static func box_overlaps_cell(pos: Vector2, c: Vector2i) -> bool:
	var h := SimConfig.PLAYER_HALF
	return pos.x + h > c.x + EPS and pos.x - h < c.x + 1.0 - EPS \
		and pos.y + h > c.y + EPS and pos.y - h < c.y + 1.0 - EPS

# Distance from a player's box at pos to the round body of a bomb at centre (< 0: overlap).
static func bomb_gap(pos: Vector2, centre: Vector2) -> float:
	var h := SimConfig.PLAYER_HALF
	var d := Vector2(maxf(absf(centre.x - pos.x) - h, 0.0), maxf(absf(centre.y - pos.y) - h, 0.0))
	return d.length() - SimConfig.BOMB_BODY_RADIUS

# True when moving the box from old_pos to pos pushes it further into a bomb it cannot pass.
static func _bomb_blocks(world: World, p: PlayerState, old_pos: Vector2, pos: Vector2) -> bool:
	for b: BombState in world.bombs.values():
		if b.state != BombState.State.PLACED or p.id in b.passable_for:
			continue
		var c := b.pos()
		var gap := bomb_gap(pos, c)
		if gap < -EPS and gap < bomb_gap(old_pos, c) - EPS:
			return true
	return false

# Only cells the box newly enters (not already overlapped at old_pos) can block, so a
# player never gets stuck because of an overlap they already have (e.g. off-lane on stairs).
static func _blocked_at(world: World, p: PlayerState, old_pos: Vector2, pos: Vector2, cur: Vector2i) -> bool:
	var h := SimConfig.PLAYER_HALF
	var lo := Vector2i(floori(pos.x - h + EPS), floori(pos.y - h + EPS))
	var hi := Vector2i(floori(pos.x + h - EPS), floori(pos.y + h - EPS))
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var c := Vector2i(cx, cy)
			if c != cur and not box_overlaps_cell(old_pos, c) and not world.arena.can_step(cur, c):
				return true
	return _bomb_blocks(world, p, old_pos, pos)

# Moves p.pos along one axis (0 = x, 1 = y) by delta, stopping against the first
# blocking cell. Returns true when the full delta was applied.
static func _move_axis(world: World, p: PlayerState, axis: int, delta: float) -> bool:
	if delta == 0.0:
		return true
	var cur := p.cell()
	var np := p.pos
	np[axis] += delta
	if not _blocked_at(world, p, p.pos, np, cur):
		p.pos = np
		return true
	# Snap against the edge of the blocking cell.
	var h := SimConfig.PLAYER_HALF
	var c: float = cur.x if axis == 0 else cur.y
	var snapped: float
	if delta > 0.0:
		snapped = c + 1.0 - h
		if snapped < p.pos[axis]:
			snapped = p.pos[axis]
	else:
		snapped = c + h
		if snapped > p.pos[axis]:
			snapped = p.pos[axis]
	# The snap position may itself overlap a blocked cell (cur is not the only cell touched).
	var sp := p.pos
	sp[axis] = snapped
	if snapped != p.pos[axis] and absf(snapped - p.pos[axis]) < absf(delta) and not _blocked_at(world, p, p.pos, sp, cur):
		p.pos = sp
		return false
	# Blocked by a bomb's round body: advance as far as it allows.
	var lo := 0.0
	var hi := 1.0
	for _i in 12:
		var mid := (lo + hi) * 0.5
		var tp := p.pos
		tp[axis] += delta * mid
		if _blocked_at(world, p, p.pos, tp, cur):
			hi = mid
		else:
			lo = mid
	p.pos[axis] += delta * lo
	return false

static func _dominant_dir(d: Vector2) -> Vector2i:
	if absf(d.x) >= absf(d.y):
		return Vector2i(1 if d.x >= 0.0 else -1, 0)
	return Vector2i(0, 1 if d.y >= 0.0 else -1)

# The nearest of the 8 directions (45 degree sectors).
static func _aim_dir(d: Vector2) -> Vector2i:
	var a := roundi(d.angle() / (PI / 4.0)) * (PI / 4.0)
	return Vector2i(roundi(cos(a)), roundi(sin(a)))

static func _toward(from: float, to: float, max_step: float) -> float:
	var diff := to - from
	if absf(diff) <= max_step:
		return to
	return from + signf(diff) * max_step

static func move(world: World, p: PlayerState, target: Vector2, speed: float, dt: float) -> void:
	var to_target := target - p.pos
	var dist := to_target.length()
	if dist <= SimConfig.STOP_DISTANCE:
		return
	var d := to_target / dist
	var step := d * speed * dt
	if step.length() > dist:
		step = d * dist
	var dom := _dominant_dir(d)
	p.facing = dom
	p.aim = _aim_dir(d)
	var dom_axis := 0 if dom.x != 0 else 1
	var perp_axis := 1 - dom_axis

	var ok_x := _move_axis(world, p, 0, step.x)
	var ok_y := _move_axis(world, p, 1, step.y)
	# Recomputed after the moves: the X move may have changed the current cell.
	var cur := p.cell()
	var center := Arena.center_of(cur)
	var dom_ok := ok_x if dom_axis == 0 else ok_y
	var max_perp := speed * dt
	var offset: float = p.pos[perp_axis] - center[perp_axis]
	if not dom_ok:
		# Corner assist: slide towards the lane centre if the lane ahead is open.
		if absf(offset) <= SimConfig.CORNER_ASSIST and absf(offset) > EPS \
				and world.is_passable_for(p, cur, cur + dom):
			var np := p.pos
			np[perp_axis] = _toward(p.pos[perp_axis], center[perp_axis], max_perp)
			if not _blocked_at(world, p, p.pos, np, cur):
				p.pos = np
	elif absf(offset) <= SimConfig.CORNER_ASSIST and absf(offset) > EPS \
			and absf(target[perp_axis] - center[perp_axis]) <= 0.5:
		# Gentle re-centring on the lane while advancing.
		var np2 := p.pos
		np2[perp_axis] = _toward(p.pos[perp_axis], center[perp_axis], 0.5 * max_perp)
		if not _blocked_at(world, p, p.pos, np2, p.cell()):
			p.pos = np2

	# Owners stop being exempt from a bomb once their box has left its round body.
	for b: BombState in world.bombs.values():
		if p.id in b.passable_for and bomb_gap(p.pos, b.pos()) >= 0.0:
			b.passable_for.erase(p.id)

# Ghosts: no collision, only clamped to the grid.
static func move_free(world: World, p: PlayerState, target: Vector2, speed: float, dt: float) -> void:
	var to_target := target - p.pos
	var dist := to_target.length()
	if dist <= SimConfig.STOP_DISTANCE:
		return
	var d := to_target / dist
	p.facing = _dominant_dir(d)
	p.aim = _aim_dir(d)
	p.pos += d * minf(speed * dt, dist)
	var h := 0.01
	p.pos.x = clampf(p.pos.x, h, world.arena.width - h)
	p.pos.y = clampf(p.pos.y, h, world.arena.height - h)
