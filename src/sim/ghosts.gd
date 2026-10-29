class_name Ghosts
extends RefCounted

# Ghost possession of living players. Static helpers over a World.

const TIMER_EPS := 1e-6

# Ends the possession of victim p (if any): the ghost is thrown off backwards and its cooldown
# starts.
static func end_possession(world: World, p: PlayerState) -> void:
	if p.possessed_by == -1:
		return
	var ghost: PlayerState = world.players.get(p.possessed_by, null)
	if ghost != null:
		ghost.possess_target = -1
		ghost.possess_timer = 0.0
		ghost.possess_cooldown = SimConfig.POSSESS_COOLDOWN
		if ghost.life == PlayerState.Life.GHOST:
			ghost.eject_dir = -Vector2(p.aim).normalized()
			ghost.eject_timer = SimConfig.EJECT_TIME
	p.possessed_by = -1

# The victim shakes (spinning the stick, like in the original): each shake cuts the possession.
static func shake_off(world: World, victim: PlayerState, shakes: float) -> void:
	var ghost: PlayerState = world.players.get(victim.possessed_by, null)
	if ghost != null:
		ghost.possess_timer = maxf(0.0, ghost.possess_timer - shakes * SimConfig.STRUGGLE_TIME)

# One tick of a ghost's ejection: it flies EJECT_DISTANCE over EJECT_TIME, out of control.
static func update_eject(world: World, ghost: PlayerState) -> void:
	var dt := minf(SimConfig.DT, ghost.eject_timer)
	ghost.eject_timer = maxf(0.0, ghost.eject_timer - SimConfig.DT)
	if ghost.eject_timer <= TIMER_EPS:
		ghost.eject_timer = 0.0
	ghost.pos += ghost.eject_dir * SimConfig.EJECT_DISTANCE / SimConfig.EJECT_TIME * dt
	var h := 0.01
	ghost.pos.x = clampf(ghost.pos.x, h, world.arena.width - h)
	ghost.pos.y = clampf(ghost.pos.y, h, world.arena.height - h)

# p has just become a ghost: it can no longer be possessed, and starts with a clean slate.
static func on_became_ghost(world: World, p: PlayerState) -> void:
	end_possession(world, p)
	p.possess_target = -1
	p.possess_timer = 0.0
	p.possess_cooldown = 0.0
	p.eject_timer = 0.0

static func tick_timers(p: PlayerState) -> void:
	p.possess_timer = maxf(0.0, p.possess_timer - SimConfig.DT)
	p.possess_cooldown = maxf(0.0, p.possess_cooldown - SimConfig.DT)

# A possessed victim follows the ghost's intent; its own intent is ignored.
static func drive_victim(world: World, ghost: PlayerState, intent: PlayerIntent) -> void:
	var victim: PlayerState = world.players[ghost.possess_target]
	if intent.moving and victim.stun_timer <= 0.0:
		Movement.move(world, victim, intent.target, SimConfig.PLAYER_SPEED, SimConfig.DT)

static func _can_possess(victim: PlayerState) -> bool:
	return victim.life == PlayerState.Life.ALIVE and victim.carried_by == -1 \
		and victim.possessed_by == -1 and victim.invulnerable_timer <= 0.0

# After movement: ends finished possessions, glues ghosts to their victim, starts new ones.
static func update(world: World) -> void:
	for ghost: PlayerState in world.players.values():
		if ghost.life != PlayerState.Life.GHOST:
			continue
		if ghost.possess_target != -1:
			var victim: PlayerState = world.players[ghost.possess_target]
			if ghost.possess_timer <= TIMER_EPS or victim.life != PlayerState.Life.ALIVE or victim.carried_by != -1:
				end_possession(world, victim)
			else:
				ghost.pos = victim.pos
				continue
		if ghost.possess_cooldown > 0.0:
			continue
		var best: PlayerState = null
		var best_d := INF
		for id in world.players.keys():
			var c: PlayerState = world.players[id]
			if not _can_possess(c):
				continue
			var d := ghost.pos.distance_to(c.pos)
			if d <= SimConfig.POSSESS_REACH and (d < best_d - 1e-9 or (absf(d - best_d) <= 1e-9 and c.id < best.id)):
				best = c
				best_d = d
		if best != null:
			best.possessed_by = ghost.id
			ghost.possess_target = best.id
			ghost.possess_timer = SimConfig.POSSESS_DURATION
