class_name BotBrain
extends RefCounted

# Stateless-ish bot: every decision is recomputed from the world, except a short wander
# commitment. Only the injected rng is used.

const WANDER_RATE := 0.5 # wanders started per second, on average
const WANDER_TIME := 1.0 # seconds a wander target is kept at most
const SAFETY_MARGIN := 0.2

var _rng: RandomNumberGenerator
# Scratch results of the last _search: cell -> steps, cell -> first cell of the path.
var _dist: Dictionary = {}
var _first: Dictionary = {}
# Wander commitment: the adjacent cell being wandered to and the ticks left (reset on a new world).
var _wander_cell: Variant = null
var _wander_ticks := 0
var _last_world: World = null

func _init(rng: RandomNumberGenerator) -> void:
	_rng = rng

func decide(world: World, id: int) -> PlayerIntent:
	var bot: PlayerState = world.players[id]
	var intent := PlayerIntent.new()
	if world != _last_world:
		_last_world = world
		_wander_cell = null
	var wander: Variant = _wander_cell
	_wander_cell = null # kept only if the seek step below re-commits to it
	# 1. Ghosts chase the nearest free living player.
	if bot.life == PlayerState.Life.GHOST:
		var best: PlayerState = null
		for p: PlayerState in world.players.values():
			if p.life == PlayerState.Life.ALIVE and p.possessed_by == -1 \
					and (best == null or p.pos.distance_squared_to(bot.pos) < best.pos.distance_squared_to(bot.pos)):
				best = p
		if best != null:
			intent.moving = true
			intent.target = best.pos
		return intent
	# 2. Cannot act.
	if not bot.can_act():
		return intent
	var cell := bot.cell()
	var bomb_cells := _bomb_cells(world)
	var danger := DangerMap.build(world)
	# 3. Flee: prefer cells above the next water step, then anything dry.
	if danger.has(cell):
		var safe: Variant = _search(world, bot, bomb_cells, danger, false, func(c: Vector2i) -> bool: return _is_safe(world, danger, c))
		if safe == null:
			safe = _search(world, bot, bomb_cells, danger, false, func(c: Vector2i) -> bool: return not danger.has(c) and not world.is_submerged(c))
		if safe != null:
			_head_to(intent, bot, _first[safe])
		else:
			_head_to_least_dangerous(world, intent, bot, bomb_cells, danger)
		return intent
	# 4. Climb (never through a blast: wait outside it instead).
	if world.water_warning or world.time_left <= 0.0:
		var top: Variant = _search_highest(world, bot, bomb_cells, danger)
		if top != null and world.arena.h2_at(top) > world.arena.h2_at(cell):
			_head_to(intent, bot, _first[top])
			return intent
	# 5. Bomb.
	if _wants_bomb(world, bot) and _can_escape_own_bomb(world, bot, bomb_cells):
		intent.place_bomb = true
		return intent
	# 6. Seek.
	var strict := not _water_unsafe(world, cell)
	var arena := world.arena
	var opponents: Dictionary = {}
	for p: PlayerState in world.players.values():
		if p.id != bot.id and p.life == PlayerState.Life.ALIVE:
			opponents[p.cell()] = true
	var goal := func(c: Vector2i) -> bool:
		if c == cell:
			return false
		for d in Arena.ORTHOGONAL:
			var n: Vector2i = c + d
			if arena.in_bounds(n) and (arena.tile_at(n) == Arena.Tile.BLOCK or opponents.has(n)):
				return true
		return false
	# Keep walking to the committed wander cell until reached, unsafe or timed out.
	if wander != null and _wander_ticks > 0 and not danger.has(wander) \
			and (wander == cell or _can_enter(world, bot, bomb_cells, cell, wander, strict)) \
			and bot.pos.distance_to(Arena.center_of(wander)) > SimConfig.STOP_DISTANCE:
		_wander_cell = wander
		_wander_ticks -= 1
		_head_to(intent, bot, wander)
		return intent
	# Already beside an opponent but no safe bomb: hold still rather than circle around them.
	for d in Arena.ORTHOGONAL:
		if opponents.has(cell + d) and arena.can_step(cell, cell + d):
			return intent
	if _rng.randf() < WANDER_RATE * SimConfig.DT:
		var options: Array[Vector2i] = []
		for d in Arena.ORTHOGONAL:
			var n := cell + d
			if _can_enter(world, bot, bomb_cells, cell, n, strict) and not danger.has(n):
				options.append(n)
		if not options.is_empty():
			_wander_cell = options[_rng.randi_range(0, options.size() - 1)]
			_wander_ticks = roundi(WANDER_TIME * SimConfig.TICK_RATE) - 1
			_head_to(intent, bot, _wander_cell)
			return intent
	var found: Variant = _search(world, bot, bomb_cells, danger, strict, goal, true)
	if found != null:
		_head_to(intent, bot, _first[found])
	return intent

# Placed bombs by cell, so BFS does not scan all bombs per step (same rule as World.is_passable_for).
func _bomb_cells(world: World) -> Dictionary:
	var out: Dictionary = {}
	for b: BombState in world.bombs.values():
		if b.state == BombState.State.PLACED:
			out[b.cell] = b
	return out

func _can_enter(world: World, bot: PlayerState, bomb_cells: Dictionary, from: Vector2i, to: Vector2i, strict: bool) -> bool:
	if not world.arena.can_step(from, to):
		return false
	var b: BombState = bomb_cells.get(to, null)
	if b != null and not bot.id in b.passable_for:
		return false
	return not (_water_unsafe(world, to) if strict else world.is_submerged(to))

# Water level at which a cell is unsafe: the next step's during the warning and the whole water
# phase, else the current one. The final step covers every cell, so it is not anticipated.
func _water_level(world: World) -> int:
	var nxt: Variant = world.next_water_h2()
	if nxt != null and (world.water_warning or world.time_left <= 0.0) and not world.next_rise_is_final():
		return nxt
	return world.water_h2

func _water_unsafe(world: World, c: Vector2i) -> bool:
	return world.is_submerged(c) or world.arena.h2_at(c) <= _water_level(world)

func _is_safe(world: World, danger: Dictionary, c: Vector2i) -> bool:
	return not danger.has(c) and not _water_unsafe(world, c)

# BFS over enterable cells; a cell is usable only if its danger outlasts the walk there
# (fleeing), or only if it is not endangered at all (avoid_danger: seeking, climbing).
# Returns the first cell satisfying stop (null if none); _dist/_first describe every visited cell.
func _search(world: World, bot: PlayerState, bomb_cells: Dictionary, danger: Dictionary, strict: bool, stop: Callable, avoid_danger := false) -> Variant:
	var start := bot.cell()
	_dist = {start: 0}
	_first = {start: start}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		if stop.is_valid() and stop.call(c):
			return c
		var steps: int = _dist[c] + 1
		for d in Arena.ORTHOGONAL:
			var n: Vector2i = c + d
			if _dist.has(n) or not _can_enter(world, bot, bomb_cells, c, n, strict):
				continue
			if danger.has(n) and (avoid_danger or danger[n] <= steps / SimConfig.PLAYER_SPEED + SAFETY_MARGIN):
				continue
			_dist[n] = steps
			_first[n] = n if c == start else _first[c]
			queue.append(n)
	return null

# The reachable cell with the greatest h2 (nearest on ties); null when nothing is reachable.
func _search_highest(world: World, bot: PlayerState, bomb_cells: Dictionary, danger: Dictionary) -> Variant:
	_search(world, bot, bomb_cells, danger, false, Callable(), true)
	var best: Variant = null
	var best_h2 := 0
	for c: Vector2i in _dist: # insertion order is BFS order
		var h := world.arena.h2_at(c)
		if best == null or h > best_h2:
			best = c
			best_h2 = h
	return best

func _head_to(intent: PlayerIntent, bot: PlayerState, cell: Vector2i) -> void:
	var t := Arena.center_of(cell)
	if cell == bot.cell() and bot.pos.distance_to(t) <= 0.1:
		return
	intent.moving = true
	intent.target = t

# No safe cell reachable: step to the neighbour that is hit latest, or stay if none is better.
func _head_to_least_dangerous(world: World, intent: PlayerIntent, bot: PlayerState, bomb_cells: Dictionary, danger: Dictionary) -> void:
	var cell := bot.cell()
	var best_time: float = danger.get(cell, INF)
	var best: Variant = null
	for d in Arena.ORTHOGONAL:
		var n: Vector2i = cell + d
		if not _can_enter(world, bot, bomb_cells, cell, n, false):
			continue
		var t: float = danger.get(n, INF)
		if t > best_time:
			best_time = t
			best = n
	if best != null:
		_head_to(intent, bot, best)

func _wants_bomb(world: World, bot: PlayerState) -> bool:
	if bot.held != PlayerState.Held.NONE or world.bomb_at(bot.cell()) != null:
		return false
	var owned := 0
	for b: BombState in world.bombs.values():
		if b.owner_id == bot.id:
			owned += 1
	if owned >= SimConfig.MAX_BOMBS:
		return false
	var cell := bot.cell()
	for d in Arena.ORTHOGONAL:
		var n: Vector2i = cell + d
		if world.arena.in_bounds(n) and world.arena.tile_at(n) == Arena.Tile.BLOCK:
			return true
	var hit := Explosion.hit_cells(world.arena, cell, SimConfig.BOMB_RADIUS)
	for p: PlayerState in world.players.values():
		if p.id != bot.id and p.life == PlayerState.Life.ALIVE and p.cell() in hit:
			return true
	return false

func _can_escape_own_bomb(world: World, bot: PlayerState, bomb_cells: Dictionary) -> bool:
	var danger := DangerMap.build(world, bot.cell())
	return _search(world, bot, bomb_cells, danger, false, func(c: Vector2i) -> bool: return _is_safe(world, danger, c)) != null
