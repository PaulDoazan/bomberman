class_name Kick
extends RefCounted

# Kicking: a player who keeps pushing against a bomb for KICK_PUSH_TIME sends it rolling
# in their aim direction (8 directions) until an obstacle. A diagonal bomb that meets a wall
# on one side slides along it and goes diagonal again past its end; it stops in a corner.
# Static helper, like Movement and Carry.

const TOUCH := 0.02

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

# Sends b rolling in p's aim direction.
static func kick(world: World, p: PlayerState, b: BombState) -> void:
	b.roll_heading = p.aim
	b.roll_dir = p.aim
	b.roll_offset = 0.0
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

# Moves every rolling bomb; a bomb stops centred on its cell when the next one is blocked.
static func update_rolling(world: World) -> void:
	for b: BombState in world.bombs.values():
		if b.state != BombState.State.PLACED:
			b.roll_dir = Vector2i.ZERO
			b.roll_offset = 0.0
			continue
		if b.roll_dir == Vector2i.ZERO:
			continue
		# A bomb placed off-centre drifts back onto its lane while it rolls.
		b.offset = b.offset.move_toward(Vector2.ZERO, 0.5 * SimConfig.KICK_SPEED * SimConfig.DT)
		var step_len := Vector2(b.roll_dir).length() # sqrt(2) for a diagonal step
		var off := b.roll_offset + SimConfig.KICK_SPEED * SimConfig.DT / step_len
		if b.roll_offset <= 0.0 and off >= 0.0:
			# At the cell centre: pick the next step, sliding along a wall met at 45 degrees.
			var dir := _next_step(world, b)
			if dir == Vector2i.ZERO: # in a corner
				b.roll_dir = Vector2i.ZERO
				b.roll_offset = 0.0
				continue
			off *= step_len / Vector2(dir).length()
			b.roll_dir = dir
		var nxt := b.cell + b.roll_dir
		if off >= 0.0 and not _can_roll(world, b, nxt):
			var hit := world.bomb_at(nxt)
			if hit != null and hit.roll_dir == Vector2i.ZERO:
				hit.roll_dir = b.roll_dir # the motion passes on to the bomb it hits
				hit.roll_heading = b.roll_dir
				hit.roll_offset = 0.0
			b.roll_dir = Vector2i.ZERO
			b.roll_offset = 0.0
			continue
		# Players stop the bomb exactly where its body touches theirs, and are stunned.
		var contact := _player_contact(world, b, b.roll_offset, off)
		var touched: Array[PlayerState] = contact[1]
		if not touched.is_empty():
			b.roll_offset = contact[0]
			for p in touched:
				if p.stun_timer <= 0.0: # no stun-lock by kicking again into a stunned player
					p.stun_timer = SimConfig.BOMB_HIT_STUN_TIME
			_stop_where_it_is(b)
			continue
		b.roll_offset = off
		if b.roll_offset >= 0.5:
			b.cell = nxt
			b.roll_offset -= 1.0
			b.passable_for.clear()

# The furthest roll offset in [from, to] before b's body touches a player in its way, with the
# players touched there; [to, []] when nobody is in the way. Players it moves away from, and
# those it may pass through (its kicker standing on it), never count.
static func _player_contact(world: World, b: BombState, from: float, to: float) -> Array:
	var base := Arena.center_of(b.cell) + b.offset
	var dir := Vector2(b.roll_dir)
	var reach := SimConfig.BOMB_BODY_RADIUS + SimConfig.PLAYER_BODY_RADIUS
	var best := to
	var touched: Array[PlayerState] = []
	for p: PlayerState in world.players.values():
		if p.id in b.passable_for or p.life != PlayerState.Life.ALIVE or p.carried_by != -1:
			continue
		var end := base + dir * to
		if end.distance_to(p.pos) >= reach or (p.pos - end).dot(dir) <= 0.0:
			continue
		var lo := from
		var hi := to
		if (base + dir * lo).distance_to(p.pos) >= reach:
			for _i in 12:
				var mid := (lo + hi) * 0.5
				if (base + dir * mid).distance_to(p.pos) < reach:
					hi = mid
				else:
					lo = mid
		if lo < best - 1e-6:
			best = lo
			touched = [p]
		elif absf(lo - best) <= 1e-6:
			touched.append(p)
	return [best, touched]

# Stops a rolling bomb where it is, keeping its exact position (it may be between centres).
static func _stop_where_it_is(b: BombState) -> void:
	var at := b.pos()
	b.roll_dir = Vector2i.ZERO
	b.roll_offset = 0.0
	b.cell = Arena.cell_of(at)
	b.offset = at - Arena.center_of(b.cell)

# The step from b's cell following its heading: the heading itself, or along the wall on one
# side of a diagonal, or zero when walls close both sides (a corner).
static func _next_step(world: World, b: BombState) -> Vector2i:
	var h := b.roll_heading
	if h.x == 0 or h.y == 0:
		return h
	var wall_x := _is_wall(world, b.cell, b.cell + Vector2i(h.x, 0))
	var wall_y := _is_wall(world, b.cell, b.cell + Vector2i(0, h.y))
	if wall_x and wall_y:
		return Vector2i.ZERO
	if wall_x:
		return Vector2i(0, h.y)
	if wall_y:
		return Vector2i(h.x, 0)
	return h

# Static obstacles: off the map, solids, higher ground and water.
static func _is_wall(world: World, from: Vector2i, to: Vector2i) -> bool:
	var arena := world.arena
	return not arena.in_bounds(to) or arena.is_solid(to) \
			or arena.h2_at(to) > arena.h2_at(from) or world.is_submerged(to)

# A bomb rolls on flat ground or off a ledge, never up, and stops before solids, bombs and
# water. Players stop it on contact instead (see _player_contact).
static func _can_roll(world: World, b: BombState, to: Vector2i) -> bool:
	if _is_wall(world, b.cell, to):
		return false
	return world.bomb_at(to) == null
