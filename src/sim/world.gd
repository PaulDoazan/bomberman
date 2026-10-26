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
	tick += 1
	events.clear()
	for id: int in players:
		var p: PlayerState = players[id]
		var intent: PlayerIntent = intents.get(id, null)
		if intent == null:
			intent = PlayerIntent.new()
		p.stun_timer = maxf(0.0, p.stun_timer - SimConfig.DT)
		if p.life != PlayerState.Life.ALIVE:
			continue
		if intent.place_bomb:
			_try_place_bomb(p)
		if p.can_act() and intent.moving:
			Movement.move(self, p, intent.target, SimConfig.PLAYER_SPEED, SimConfig.DT)
	_update_explosions()
	_update_bombs()
	_apply_explosion_damage()

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
	return b.cell

func _update_explosions() -> void:
	for e: Explosion in explosions:
		e.timer -= SimConfig.DT
	explosions = explosions.filter(func(e: Explosion) -> bool: return e.timer > 0.0)

func _update_bombs() -> void:
	var queue: Array[BombState] = []
	for b: BombState in bombs.values():
		if b.state == BombState.State.FLYING:
			continue
		b.fuse -= SimConfig.DT
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
			if p.life == PlayerState.Life.ALIVE and p.invulnerable_timer <= 0.0 and p.cell() in e.cells:
				kill(p.id, "explosion")

func kill(id: int, cause: String) -> void:
	var p: PlayerState = players[id]
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
		if b.cell == c:
			return b
	return null

func is_passable_for(p: PlayerState, from: Vector2i, to: Vector2i) -> bool:
	if not arena.can_step(from, to):
		return false
	var b := bomb_at(to)
	return b == null or p.id in b.passable_for
