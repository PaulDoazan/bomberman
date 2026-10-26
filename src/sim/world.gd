class_name World
extends RefCounted

var arena: Arena
var cfg: SimConfig
var rng: RandomNumberGenerator
var players: Dictionary = {} # id -> PlayerState
var bombs: Dictionary = {} # id -> BombState
var explosions: Array = []
var flying: Array = []
var events: Array[Dictionary] = []
var tick := 0
var time_left: float
var water_h2 := SimConfig.WATER_START_H2
var water_warning := false
var finished := false
var winners: Array[int] = []

var _next_bomb_id := 0
var _water_index := 0

func _init(p_arena: Arena, player_ids: Array[int], p_cfg: SimConfig, p_rng: RandomNumberGenerator) -> void:
	arena = p_arena
	cfg = p_cfg
	rng = p_rng
	time_left = cfg.round_time
	for i in player_ids.size():
		var p := PlayerState.new()
		p.id = player_ids[i]
		# Arenas without spawns (hand-built fixtures) fall back to the centre of cell (0, 0).
		p.pos = Arena.center_of(arena.spawns[i] if i < arena.spawns.size() else Vector2i.ZERO)
		p.lives = cfg.lives
		players[p.id] = p

func step(intents: Dictionary) -> void:
	if finished:
		return
	tick += 1
	events.clear()
	for id: int in players:
		var p: PlayerState = players[id]
		var intent: PlayerIntent = intents.get(id, null)
		if intent == null:
			intent = PlayerIntent.new()
		p.stun_timer = maxf(0.0, p.stun_timer - SimConfig.DT - intent.struggle * SimConfig.STRUGGLE_TIME)
		p.invulnerable_timer = maxf(0.0, p.invulnerable_timer - SimConfig.DT)
		Ghosts.tick_timers(p)
		if p.life == PlayerState.Life.GHOST:
			if p.possess_target != -1:
				Ghosts.drive_victim(self, p, intent)
			elif intent.moving:
				Movement.move_free(self, p, intent.target, SimConfig.GHOST_SPEED, SimConfig.DT)
			continue
		if p.life != PlayerState.Life.ALIVE:
			continue
		if intent.place_bomb:
			_try_place_bomb(p)
		if intent.action and p.can_act():
			if p.held == PlayerState.Held.NONE:
				Carry.pick_up(self, p)
			else:
				Carry.throw(self, p)
		if p.can_act() and intent.moving:
			Movement.move(self, p, intent.target, SimConfig.PLAYER_SPEED, SimConfig.DT)
		Kick.update_push(self, p, p.can_act() and intent.moving)
	Carry.update_carried(self)
	Carry.update_flying(self)
	Ghosts.update(self)
	Kick.update_rolling(self)
	_update_explosions()
	_update_bombs()
	_apply_explosion_damage()
	_update_water()
	_apply_drowning()
	_update_respawns()
	_check_round_end()

func is_submerged(c: Vector2i) -> bool:
	return not arena.in_bounds(c) or arena.h2_at(c) <= water_h2

# Water level of the next rise; null once the last step is reached.
func next_water_h2() -> Variant:
	if _water_index >= SimConfig.WATER_STEPS.size():
		return null
	return SimConfig.WATER_STEPS[_water_index]

# True when the next rise is the last one (it covers every cell).
func next_rise_is_final() -> bool:
	return _water_index == SimConfig.WATER_STEPS.size() - 1

# Seconds until the next rise; INF once the last step is reached.
# Rise k is scheduled WATER_STEP_INTERVAL * k seconds after the timer hits 0.
func seconds_to_next_rise() -> float:
	if _water_index >= SimConfig.WATER_STEPS.size():
		return INF
	return time_left + _water_index * SimConfig.WATER_STEP_INTERVAL

func _update_water() -> void:
	time_left -= SimConfig.DT
	if next_water_h2() == null:
		water_warning = false
		return
	if seconds_to_next_rise() <= 0.0:
		water_h2 = next_water_h2()
		_water_index += 1
		events.append({"type": "water_rise", "h2": water_h2})
	water_warning = next_water_h2() != null and seconds_to_next_rise() <= SimConfig.WATER_WARNING

func _apply_drowning() -> void:
	for p: PlayerState in players.values():
		if p.life != PlayerState.Life.ALIVE or p.carried_by == Carry.THROWN or not is_submerged(p.cell()):
			continue
		if not has_dry_cell():
			_eliminate(p, "drown")
		else:
			kill(p.id, "drown")

func _eliminate(p: PlayerState, cause: String) -> void:
	if p.life != PlayerState.Life.WAITING_RESPAWN:
		events.append({"type": "death", "id": p.id, "cause": cause})
	Carry.release_links(self, p)
	Ghosts.end_possession(self, p)
	p.lives = 0
	p.life = PlayerState.Life.GHOST
	Ghosts.on_became_ghost(self, p)
	p.died_tick = tick

func _update_respawns() -> void:
	for p: PlayerState in players.values():
		if p.life != PlayerState.Life.WAITING_RESPAWN or p.died_tick == tick:
			continue
		p.respawn_timer -= SimConfig.DT
		if p.respawn_timer > 0.0:
			continue
		var c: Variant = find_respawn_cell()
		if c == null:
			_eliminate(p, "drown")
			continue
		p.pos = Arena.center_of(c)
		p.life = PlayerState.Life.ALIVE
		p.invulnerable_timer = SimConfig.INVULNERABLE_TIME
		p.respawn_timer = 0.0
		events.append({"type": "respawn", "id": p.id, "cell": c})

# Random lowest dry cell that is walkable, bomb-free and not under an explosion; null when none.
# When the next rise comes before the respawn invulnerability and a warning would let the player
# react, cells flooded by that rise are avoided (unless nothing else is left).
func find_respawn_cell() -> Variant:
	var best: Array[Vector2i] = []
	var nxt: Variant = next_water_h2()
	if nxt != null and seconds_to_next_rise() <= SimConfig.INVULNERABLE_TIME + SimConfig.WATER_WARNING:
		best = _lowest_respawn_cells(nxt)
	if best.is_empty():
		best = _lowest_respawn_cells(water_h2)
	if best.is_empty():
		return null
	return best[rng.randi_range(0, best.size() - 1)]

# Same filter as find_respawn_cell at the current water level, without drawing from the rng.
func has_dry_cell() -> bool:
	for y in arena.height:
		for x in arena.width:
			if _can_respawn_at(Vector2i(x, y), water_h2):
				return true
	return false

func _can_respawn_at(c: Vector2i, floor_h2: int) -> bool:
	if arena.is_solid(c) or arena.h2_at(c) <= floor_h2 or bomb_at(c) != null:
		return false
	for e: Explosion in explosions:
		if c in e.cells:
			return false
	return true

func _lowest_respawn_cells(floor_h2: int) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var best_h2 := 0
	for y in arena.height:
		for x in arena.width:
			var c := Vector2i(x, y)
			if not _can_respawn_at(c, floor_h2):
				continue
			var h := arena.h2_at(c)
			if best.is_empty() or h < best_h2:
				best = [c]
				best_h2 = h
			elif h == best_h2:
				best.append(c)
	return best

func _check_round_end() -> void:
	var alive: Array[int] = []
	for p: PlayerState in players.values():
		if p.life != PlayerState.Life.GHOST:
			alive.append(p.id)
	# A lone player (hand-built test worlds) is not a "single survivor": the round only ends once they die.
	if alive.size() == 1 and players.size() > 1:
		finished = true
		winners = alive
	elif alive.is_empty():
		finished = true
		for p: PlayerState in players.values():
			if p.died_tick == tick and p.lives == 0:
				winners.append(p.id)

func _try_place_bomb(p: PlayerState) -> void:
	if not p.can_act() or p.held != PlayerState.Held.NONE:
		return
	var c := p.cell()
	if not arena.in_bounds(c) or bomb_at(c) != null:
		return
	var owned := 0
	for b: BombState in bombs.values():
		if b.owner_id == p.id:
			owned += 1
	if owned >= SimConfig.MAX_BOMBS:
		return
	var b := add_bomb(p.id, c, SimConfig.FUSE)
	for other: PlayerState in players.values():
		if other.is_alive() and Movement.box_overlaps_cell(other.pos, c):
			b.passable_for.append(other.id)

func add_bomb(owner_id: int, cell: Vector2i, fuse: float) -> BombState:
	var b := BombState.new()
	b.id = _next_bomb_id
	_next_bomb_id += 1
	b.owner_id = owner_id
	b.cell = cell
	b.fuse = fuse
	bombs[b.id] = b
	return b

# A held bomb is at its holder's cell; any other bomb is at its own cell.
func bomb_cell(b: BombState) -> Vector2i:
	if b.state == BombState.State.HELD:
		for p: PlayerState in players.values():
			if p.held == PlayerState.Held.BOMB and p.held_id == b.id:
				return p.cell()
	if b.state == BombState.State.FLYING:
		for f: FlyingObject in flying:
			if f.kind == PlayerState.Held.BOMB and f.ref_id == b.id:
				return Arena.cell_of(Carry.flight_pos(f))
	return b.cell

func _update_explosions() -> void:
	for e: Explosion in explosions:
		e.timer -= SimConfig.DT
	explosions = explosions.filter(func(e: Explosion) -> bool: return e.timer > 0.0)

func _update_bombs() -> void:
	var queue: Array[BombState] = []
	for b: BombState in bombs.values():
		b.fuse -= SimConfig.DT # a thrown bomb's fuse never stops
		if b.fuse <= 0.0:
			queue.append(b)
	if queue.is_empty():
		return
	var destroyed: Dictionary = {} # blocks are removed after the whole chain resolves
	while not queue.is_empty():
		var b: BombState = queue.pop_front()
		if not bombs.has(b.id):
			continue
		var origin := bomb_cell(b)
		for holder: PlayerState in players.values():
			if holder.held == PlayerState.Held.BOMB and holder.held_id == b.id:
				holder.held = PlayerState.Held.NONE
				holder.held_id = -1
		bombs.erase(b.id)
		flying = flying.filter(func(f: FlyingObject) -> bool: return not (f.kind == PlayerState.Held.BOMB and f.ref_id == b.id))
		var e := Explosion.new()
		e.origin = origin
		e.owner_id = b.owner_id
		e.cells = Explosion.hit_cells(arena, origin, SimConfig.BOMB_RADIUS)
		explosions.append(e)
		events.append({"type": "explosion", "cell": origin, "radius": SimConfig.BOMB_RADIUS, "cells": e.cells})
		for c in e.cells:
			if arena.tile_at(c) == Arena.Tile.BLOCK:
				destroyed[c] = true
		for other: BombState in bombs.values():
			if other.state != BombState.State.FLYING and bomb_cell(other) in e.cells and not other in queue:
				queue.append(other)
	for c: Vector2i in destroyed:
		arena.set_tile(c, Arena.Tile.FLOOR)
		events.append({"type": "block_destroyed", "cell": c})

func _apply_explosion_damage() -> void:
	for e: Explosion in explosions:
		for p: PlayerState in players.values():
			if p.life == PlayerState.Life.ALIVE and p.carried_by != Carry.THROWN and p.invulnerable_timer <= 0.0 and p.cell() in e.cells:
				kill(p.id, "explosion")

func kill(id: int, cause: String) -> void:
	var p: PlayerState = players[id]
	Carry.release_links(self, p)
	Ghosts.end_possession(self, p)
	p.lives -= 1
	p.died_tick = tick
	events.append({"type": "death", "id": id, "cause": cause})
	if p.lives > 0:
		p.life = PlayerState.Life.WAITING_RESPAWN
		p.respawn_timer = SimConfig.RESPAWN_DELAY
	else:
		p.life = PlayerState.Life.GHOST
		Ghosts.on_became_ghost(self, p)

func bomb_at(c: Vector2i) -> BombState:
	for b: BombState in bombs.values():
		if b.state == BombState.State.PLACED and b.cell == c:
			return b
	return null

func is_passable_for(p: PlayerState, from: Vector2i, to: Vector2i) -> bool:
	if not arena.can_step(from, to):
		return false
	var b := bomb_at(to)
	return b == null or p.id in b.passable_for
