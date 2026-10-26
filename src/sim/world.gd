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
	var b := BombState.new()
	b.id = _next_bomb_id
	_next_bomb_id += 1
	b.owner_id = p.id
	b.cell = c
	for other: PlayerState in players.values():
		if other.is_alive() and Movement.box_overlaps_cell(other.pos, c):
			b.passable_for.append(other.id)
	bombs[b.id] = b

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
