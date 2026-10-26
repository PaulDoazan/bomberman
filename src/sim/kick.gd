class_name Kick
extends RefCounted

# Kicking: a player who keeps pushing against a bomb for KICK_PUSH_TIME sends it rolling
# in their facing direction until an obstacle. Static helper, like Movement and Carry.

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
		b.roll_dir = p.facing
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
		var nxt := b.cell + b.roll_dir
		var off := b.roll_offset + SimConfig.KICK_SPEED * SimConfig.DT
		if off >= 0.0 and not _can_roll(world, b.cell, nxt):
			b.roll_dir = Vector2i.ZERO
			b.roll_offset = 0.0
			continue
		b.roll_offset = off
		if b.roll_offset >= 0.5:
			b.cell = nxt
			b.roll_offset -= 1.0
			b.passable_for.clear()

# A bomb rolls on flat ground or off a ledge, never up, and stops before solids, bombs,
# water and players.
static func _can_roll(world: World, from: Vector2i, to: Vector2i) -> bool:
	var arena := world.arena
	if not arena.in_bounds(to) or arena.is_solid(to):
		return false
	if arena.h2_at(to) > arena.h2_at(from) or world.is_submerged(to):
		return false
	if world.bomb_at(to) != null:
		return false
	for p: PlayerState in world.players.values():
		if p.life == PlayerState.Life.ALIVE and p.carried_by == -1 and Movement.box_overlaps_cell(p.pos, to):
			return false
	return true
