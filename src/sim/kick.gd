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

# The bomb in the cell ahead that the player's box is touching, if they cannot walk into it.
static func _bomb_pushed(world: World, p: PlayerState) -> BombState:
	var cur := p.cell()
	var ahead := cur + p.facing
	var b := world.bomb_at(ahead)
	if b == null or p.id in b.passable_for:
		return null
	var axis := 0 if p.facing.x != 0 else 1
	var edge: float = p.pos[axis] + SimConfig.PLAYER_HALF * float(p.facing[axis])
	var boundary: float = float(cur[axis]) + (1.0 if p.facing[axis] > 0 else 0.0)
	return b if absf(edge - boundary) <= TOUCH else null

# Moves every rolling bomb; a bomb stops centred on its cell when the next one is blocked.
static func update_rolling(world: World) -> void:
	for b: BombState in world.bombs.values():
		if b.state != BombState.State.PLACED:
			b.roll_dir = Vector2i.ZERO
			b.roll_offset = 0.0
			continue
		if b.roll_dir == Vector2i.ZERO:
			continue
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
			for p: PlayerState in _players_in(world, nxt, b):
				if p.stun_timer <= 0.0: # no stun-lock by kicking again into a stunned player
					p.stun_timer = SimConfig.BOMB_HIT_STUN_TIME
			var hit := world.bomb_at(nxt)
			if hit != null and hit.roll_dir == Vector2i.ZERO:
				hit.roll_dir = b.roll_dir # the motion passes on to the bomb it hits
				hit.roll_heading = b.roll_dir
				hit.roll_offset = 0.0
			b.roll_dir = Vector2i.ZERO
			b.roll_offset = 0.0
			continue
		b.roll_offset = off
		if b.roll_offset >= 0.5:
			b.cell = nxt
			b.roll_offset -= 1.0
			b.passable_for.clear()

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

# A bomb rolls on flat ground or off a ledge, never up, and stops before solids, bombs,
# water and players.
static func _can_roll(world: World, b: BombState, to: Vector2i) -> bool:
	if _is_wall(world, b.cell, to):
		return false
	if world.bomb_at(to) != null:
		return false
	return _players_in(world, to, b).is_empty()

# Players in c the bomb would hit; those standing on the bomb (its layer, its kicker) never count.
static func _players_in(world: World, c: Vector2i, b: BombState) -> Array[PlayerState]:
	var out: Array[PlayerState] = []
	for p: PlayerState in world.players.values():
		if p.id in b.passable_for:
			continue
		if p.life == PlayerState.Life.ALIVE and p.carried_by == -1 and Movement.box_overlaps_cell(p.pos, c):
			out.append(p)
	return out
