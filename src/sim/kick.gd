class_name Kick
extends RefCounted

# Kicking: a player who keeps pushing against a bomb for KICK_PUSH_TIME sends it rolling
# in their aim direction (8 directions). It rolls in a straight line from exactly where it is,
# as a ball: it stops against walls met head on, against bombs (passing its motion on) and
# players (stunning them), right at contact. A diagonal bomb that meets a wall on one side
# slides along it and goes diagonal again past its end, and stops in a corner; a straight bomb
# that only clips a corner glides off it. Static helper, like Movement and Carry.

const TOUCH := 0.02
const EPS := 1e-4 # contact tolerance
const NOISE := 1e-7 # float noise when comparing an overlap before and after a move
const BISECT_STEPS := 12

# Called after a player's movement for the tick.
static func update_push(world: World, p: PlayerState, moving: bool) -> void:
	var b := _bomb_pushed(world, p) if moving else null
	if b == null or b.roll_dir != Vector2i.ZERO:
		p.push_timer = 0.0
		return
	p.push_timer += SimConfig.DT
	if p.push_timer + 1e-6 >= SimConfig.KICK_PUSH_TIME:
		p.push_timer = 0.0
		kick(world, p, b)

# Sends b rolling in p's aim direction; underfoot when p stands on it.
static func kick(world: World, p: PlayerState, b: BombState, underfoot := false) -> void:
	b.roll_heading = p.aim
	b.roll_dir = p.aim
	p.kick_tick = world.tick
	p.kick_underfoot = underfoot
	world.events.append({"type": "kick", "id": p.id, "bomb": b.id})

# A bomb ahead (within 60 degrees of facing) whose round body the player's box is touching,
# if they cannot walk through it.
static func _bomb_pushed(world: World, p: PlayerState) -> BombState:
	for b: BombState in world.bombs.values():
		if b.state != BombState.State.PLACED or p.id in b.passable_for:
			continue
		var to := b.pos() - p.pos
		if Movement.bomb_gap(p.pos, b.pos()) <= TOUCH and to.dot(Vector2(p.facing)) > to.length() * 0.5:
			return b
	return null

# Moves every rolling bomb by one tick.
static func update_rolling(world: World) -> void:
	for b: BombState in world.bombs.values():
		if b.state != BombState.State.PLACED:
			b.roll_dir = Vector2i.ZERO
			continue
		if b.roll_dir != Vector2i.ZERO:
			_roll(world, b)

static func _roll(world: World, b: BombState) -> void:
	var dist := SimConfig.KICK_SPEED * SimConfig.DT
	var from := b.pos()
	var step := Vector2(b.roll_heading).normalized() * dist
	var hit := _obstacle(world, b, from, from + step)
	if hit.is_empty():
		_move_to(world, b, from + step)
		b.roll_dir = b.roll_heading
		return
	if hit["kind"] == "wall":
		var slide := _around_wall(world, b, from, dist, hit["cell"])
		if slide != Vector2.ZERO and _obstacle(world, b, from, from + slide).is_empty():
			_move_to(world, b, from + slide)
			var main := 0 if absf(slide.x) > absf(slide.y) else 1 # the axis it runs along
			b.roll_dir = Vector2i.ZERO
			b.roll_dir[main] = roundi(signf(slide[main]))
			return
	# Stop right at the contact; a diagonal bomb in a corner closes the gap on each axis.
	var h := b.roll_heading
	var here := Arena.cell_of(from)
	if hit["kind"] == "wall" and h.x != 0 and h.y != 0 \
			and _is_wall(world, here, here + Vector2i(h.x, 0)) and _is_wall(world, here, here + Vector2i(0, h.y)):
		for axis_step: Vector2 in [Vector2(h.x, 0.0) * dist, Vector2(0.0, h.y) * dist]:
			var at := b.pos()
			_move_to(world, b, at + axis_step * _free_fraction(world, b, at, axis_step))
	else:
		_move_to(world, b, from + step * _free_fraction(world, b, from, step))
	match hit["kind"]:
		"player":
			for p: PlayerState in world.players.values():
				if _blocks_player(b, p) and Movement.bomb_gap(p.pos, b.pos()) <= TOUCH \
						and p.stun_timer <= 0.0: # no stun-lock by kicking again into a stunned player
					world.hit_by_bomb(p, Vector2(b.roll_dir))
		"bomb":
			var other: BombState = hit["bomb"]
			if other.roll_dir == Vector2i.ZERO:
				other.roll_heading = b.roll_heading # the motion passes on to the bomb it hits
				other.roll_dir = b.roll_heading
	b.roll_dir = Vector2i.ZERO

# The move that gets a bomb past a wall it is running into, or zero when it must stop.
# Diagonal: along the wall on the blocked side (full speed), zero in a corner or when an
# obstacle is hit right on the diagonal. Straight: a sideways glide off a corner it only clips.
static func _around_wall(world: World, b: BombState, from: Vector2, dist: float, wall: Vector2i) -> Vector2:
	var h := b.roll_heading
	if h.x != 0 and h.y != 0:
		var along_x := Vector2(h.x, 0.0) * dist
		var along_y := Vector2(0.0, h.y) * dist
		var x_blocked := not _obstacle(world, b, from, from + along_x).is_empty()
		var y_blocked := not _obstacle(world, b, from, from + along_y).is_empty()
		# Close the gap to the wall, then run along it.
		if x_blocked and not y_blocked:
			return along_y + along_x * _free_fraction(world, b, from, along_x)
		if y_blocked and not x_blocked:
			return along_x + along_y * _free_fraction(world, b, from, along_y)
		return Vector2.ZERO
	var perp := 1 if h.x != 0 else 0
	var lo := float(wall[perp])
	if from[perp] >= lo and from[perp] <= lo + 1.0:
		return Vector2.ZERO # head on: its centre is in front of the wall
	var glide := Vector2.ZERO
	glide[perp] = signf(from[perp] - (lo + 0.5)) * dist
	return glide if _obstacle(world, b, from, from + glide).is_empty() else Vector2.ZERO

# What the bomb runs into when moving from old to new: {} when nothing, else {kind: "wall",
# cell}, {kind: "bomb", bomb} or {kind: "player"}. Only moves that push it further into
# something block, so it never gets stuck on an overlap it already has; and it can never sink
# deeper than EPS, so sliding along a wall never creeps into the next wall cell.
static func _obstacle(world: World, b: BombState, old: Vector2, new: Vector2) -> Dictionary:
	var r := SimConfig.BOMB_BODY_RADIUS
	for p: PlayerState in world.players.values():
		if _blocks_player(b, p):
			var gap := Movement.bomb_gap(p.pos, new)
			if gap < -EPS and gap < Movement.bomb_gap(p.pos, old) - NOISE:
				return {"kind": "player"}
	for o: BombState in world.bombs.values():
		if o != b and o.state == BombState.State.PLACED:
			var d := o.pos().distance_to(new)
			if d < 2.0 * r - EPS and d < o.pos().distance_to(old) - NOISE:
				return {"kind": "bomb", "bomb": o}
	var here := Arena.cell_of(old)
	for cy in range(floori(new.y - r), floori(new.y + r) + 1):
		for cx in range(floori(new.x - r), floori(new.x + r) + 1):
			var c := Vector2i(cx, cy)
			if c != here and _is_wall(world, here, c):
				var depth := _depth(c, new)
				if depth > EPS and depth > _depth(c, old) + NOISE:
					return {"kind": "wall", "cell": c}
	return {}

# How far a bomb body centred at at sinks into cell c (<= 0: not touching).
static func _depth(c: Vector2i, at: Vector2) -> float:
	var nearest := Vector2(clampf(at.x, c.x, c.x + 1.0), clampf(at.y, c.y, c.y + 1.0))
	return SimConfig.BOMB_BODY_RADIUS - at.distance_to(nearest)

# Largest fraction of step the bomb can move from from without running into anything.
static func _free_fraction(world: World, b: BombState, from: Vector2, step: Vector2) -> float:
	var lo := 0.0
	var hi := 1.0
	for _i in BISECT_STEPS:
		var mid := (lo + hi) * 0.5
		if _obstacle(world, b, from, from + step * mid).is_empty():
			lo = mid
		else:
			hi = mid
	return lo

# Players a rolling bomb stops against: alive, not carried, not standing on it (its kicker).
static func _blocks_player(b: BombState, p: PlayerState) -> bool:
	return p.life == PlayerState.Life.ALIVE and p.carried_by == -1 and not p.id in b.passable_for

static func _move_to(world: World, b: BombState, at: Vector2) -> void:
	b.cell = Arena.cell_of(at)
	b.offset = at - Arena.center_of(b.cell)
	for id: int in b.passable_for.duplicate():
		if Movement.bomb_gap(world.players[id].pos, at) >= 0.0:
			b.passable_for.erase(id)

# Static obstacles for a bomb in cell from: off the map, solids, higher ground and water.
static func _is_wall(world: World, from: Vector2i, to: Vector2i) -> bool:
	var arena := world.arena
	return not arena.in_bounds(to) or arena.is_solid(to) \
			or arena.h2_at(to) > arena.h2_at(from) or world.is_submerged(to)
