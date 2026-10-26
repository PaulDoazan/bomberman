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

# carried_by of a player in flight: neither free (-1) nor carried by anyone. Such a player
# cannot act, be hit, drown or be possessed until they land.
const THROWN := -2

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
		p.stun_timer = maxf(0.0, p.stun_timer - SimConfig.DT)
		p.invulnerable_timer = maxf(0.0, p.invulnerable_timer - SimConfig.DT)
		if p.life != PlayerState.Life.ALIVE:
			continue
		if intent.place_bomb:
			_try_place_bomb(p)
		if intent.action and p.can_act():
			if p.held == PlayerState.Held.NONE:
				_try_pick_up(p)
			else:
				_throw(p)
		if p.can_act() and intent.moving:
			Movement.move(self, p, intent.target, SimConfig.PLAYER_SPEED, SimConfig.DT)
	_update_carried()
	_update_flying()
	_update_explosions()
	_update_bombs()
	_apply_explosion_damage()
	_update_water()
	_apply_drowning()
	_update_respawns()
	_check_round_end()

func is_submerged(c: Vector2i) -> bool:
	return not arena.in_bounds(c) or arena.h2_at(c) <= water_h2

func _update_water() -> void:
	time_left -= SimConfig.DT
	if _water_index >= SimConfig.WATER_STEPS.size():
		water_warning = false
		return
	# Rise k is scheduled WATER_STEP_INTERVAL * k seconds after the timer hits 0.
	var until_rise := time_left + _water_index * SimConfig.WATER_STEP_INTERVAL
	if until_rise <= 0.0:
		water_h2 = SimConfig.WATER_STEPS[_water_index]
		_water_index += 1
		events.append({"type": "water_rise", "h2": water_h2})
		until_rise += SimConfig.WATER_STEP_INTERVAL
	water_warning = _water_index < SimConfig.WATER_STEPS.size() and until_rise <= SimConfig.WATER_WARNING

func _apply_drowning() -> void:
	for p: PlayerState in players.values():
		if p.life != PlayerState.Life.ALIVE or p.carried_by == THROWN or not is_submerged(p.cell()):
			continue
		if find_respawn_cell() == null:
			_eliminate(p, "drown")
		else:
			kill(p.id, "drown")

func _eliminate(p: PlayerState, cause: String) -> void:
	if p.life != PlayerState.Life.WAITING_RESPAWN:
		events.append({"type": "death", "id": p.id, "cause": cause})
	_release_links(p)
	p.lives = 0
	p.life = PlayerState.Life.GHOST
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
func find_respawn_cell() -> Variant:
	var best: Array[Vector2i] = []
	var best_h2 := 0
	for y in arena.height:
		for x in arena.width:
			var c := Vector2i(x, y)
			if arena.is_solid(c) or is_submerged(c) or bomb_at(c) != null:
				continue
			var hit := false
			for e: Explosion in explosions:
				if c in e.cells:
					hit = true
					break
			if hit:
				continue
			var h := arena.h2_at(c)
			if best.is_empty() or h < best_h2:
				best = [c]
				best_h2 = h
			elif h == best_h2:
				best.append(c)
	if best.is_empty():
		return null
	return best[rng.randi_range(0, best.size() - 1)]

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
				return Arena.cell_of(_flight_pos(f))
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
			if p.life == PlayerState.Life.ALIVE and p.carried_by != THROWN and p.invulnerable_timer <= 0.0 and p.cell() in e.cells:
				kill(p.id, "explosion")

func kill(id: int, cause: String) -> void:
	var p: PlayerState = players[id]
	_release_links(p)
	p.lives -= 1
	p.died_tick = tick
	events.append({"type": "death", "id": id, "cause": cause})
	if p.lives > 0:
		p.life = PlayerState.Life.WAITING_RESPAWN
		p.respawn_timer = SimConfig.RESPAWN_DELAY
	else:
		p.life = PlayerState.Life.GHOST

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

# Current position of a flying object; a null landing keeps it at its origin.
func _flight_pos(f: FlyingObject) -> Vector2:
	if f.landing == null:
		return f.from
	return f.from.lerp(Arena.center_of(f.landing), f.progress())

# What p holds drops on their cell, and p stops being carried (their carrier's hands are freed).
func _release_links(p: PlayerState) -> void:
	match p.held:
		PlayerState.Held.BOMB:
			var b: BombState = bombs.get(p.held_id, null)
			if b != null and b.state == BombState.State.HELD:
				b.state = BombState.State.PLACED
				b.cell = p.cell()
				b.passable_for.clear()
		PlayerState.Held.PLAYER:
			var c: PlayerState = players[p.held_id]
			c.carried_by = -1
			c.pos = Arena.center_of(p.cell())
	p.held = PlayerState.Held.NONE
	p.held_id = -1
	if p.carried_by >= 0:
		var carrier: PlayerState = players[p.carried_by]
		carrier.held = PlayerState.Held.NONE
		carrier.held_id = -1
		p.carried_by = -1

func _is_free_landing(c: Vector2i, kind: int) -> bool:
	if not arena.in_bounds(c) or arena.is_solid(c) or bomb_at(c) != null:
		return false
	if kind != PlayerState.Held.BOMB:
		for p: PlayerState in players.values():
			if p.life == PlayerState.Life.ALIVE and p.carried_by == -1 and p.cell() == c:
				return false
	return true

func _try_pick_up(p: PlayerState) -> void:
	var own := bomb_at(p.cell())
	if own != null:
		_hold_bomb(p, own)
		return
	var front := p.cell() + p.facing
	if not arena.in_bounds(front):
		return
	var b := bomb_at(front)
	if b != null:
		_hold_bomb(p, b)
		return
	for other: PlayerState in players.values():
		if other != p and other.life == PlayerState.Life.ALIVE and other.carried_by == -1 and other.cell() == front:
			other.carried_by = p.id
			other.carried_timer = SimConfig.CARRY_ESCAPE
			p.held = PlayerState.Held.PLAYER
			p.held_id = other.id
			return
	if arena.tile_at(front) == Arena.Tile.BLOCK:
		arena.set_tile(front, Arena.Tile.FLOOR)
		p.held = PlayerState.Held.BLOCK
		p.held_id = -1

func _hold_bomb(p: PlayerState, b: BombState) -> void:
	b.state = BombState.State.HELD
	b.passable_for.clear()
	p.held = PlayerState.Held.BOMB
	p.held_id = b.id

func _throw(p: PlayerState) -> void:
	var f := FlyingObject.new()
	f.kind = p.held
	f.ref_id = p.held_id
	f.from = p.pos
	var land := p.cell() + p.facing * SimConfig.THROW_DISTANCE
	while arena.in_bounds(land) and not _is_free_landing(land, p.held):
		land += p.facing
	if arena.in_bounds(land):
		f.landing = land
	f.to = Arena.center_of(land)
	match p.held:
		PlayerState.Held.BOMB:
			bombs[p.held_id].state = BombState.State.FLYING
		PlayerState.Held.PLAYER:
			players[p.held_id].carried_by = THROWN
	flying.append(f)
	p.held = PlayerState.Held.NONE
	p.held_id = -1

# Carried players follow their carrier and break free when their timer runs out.
func _update_carried() -> void:
	for p: PlayerState in players.values():
		if p.carried_by < 0:
			continue
		var carrier: PlayerState = players[p.carried_by]
		p.pos = carrier.pos
		p.carried_timer -= SimConfig.DT
		if p.carried_timer <= 0.0:
			p.carried_by = -1
			p.pos = Arena.center_of(carrier.cell())
			carrier.held = PlayerState.Held.NONE
			carrier.held_id = -1

func _update_flying() -> void:
	var landed: Array[FlyingObject] = []
	for f: FlyingObject in flying:
		f.elapsed += SimConfig.DT
		if f.elapsed >= SimConfig.THROW_FLIGHT - 1e-6:
			landed.append(f)
	for f in landed:
		flying.erase(f)
		_land(f)

func _land(f: FlyingObject) -> void:
	if f.landing == null:
		events.append({"type": "splash", "pos": f.to})
		match f.kind:
			PlayerState.Held.BOMB:
				bombs.erase(f.ref_id)
			PlayerState.Held.PLAYER:
				var t: PlayerState = players[f.ref_id]
				t.carried_by = -1
				kill(t.id, "drown")
		return
	var c: Vector2i = f.landing
	match f.kind:
		PlayerState.Held.BOMB:
			var b: BombState = bombs[f.ref_id]
			b.state = BombState.State.PLACED
			b.cell = c
			b.passable_for.clear()
			for p: PlayerState in players.values():
				if p.life == PlayerState.Life.ALIVE and p.carried_by == -1 and p.cell() == c:
					p.stun_timer = SimConfig.STUN_TIME
		PlayerState.Held.BLOCK:
			arena.set_tile(c, Arena.Tile.BLOCK)
		PlayerState.Held.PLAYER:
			var t: PlayerState = players[f.ref_id]
			t.carried_by = -1
			t.pos = Arena.center_of(c)
			t.stun_timer = SimConfig.STUN_TIME
