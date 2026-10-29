class_name Items
extends RefCounted

# Items, as in Bomberman 64: hidden in blocks, revealed when the block goes (blown up or lifted),
# picked up by walking over them, destroyed by a later blast. The Skull makes whoever picks it up
# sick for a while (it can also be lifted from the front and thrown at someone); Evil, once per
# round, sets off something that happens to everyone. Static helpers over a World.

const ALL_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]

# Draws what each block hides, among the items turned on: about ITEM_CHANCE of them hide one
# (by ITEM_WEIGHTS), and one block hides Evil.
static func hide_in_blocks(world: World) -> void:
	var blocks: Array[Vector2i] = []
	for y in world.arena.height:
		for x in world.arena.width:
			if world.arena.tile_at(Vector2i(x, y)) == Arena.Tile.BLOCK:
				blocks.append(Vector2i(x, y))
	var pool: Array[int] = []
	var total := 0
	for item: int in SimConfig.ITEM_WEIGHTS:
		if world.cfg.item_enabled(item):
			pool.append(item)
			total += SimConfig.ITEM_WEIGHTS[item]
	if total > 0:
		for c in blocks:
			if world.rng.randf() >= SimConfig.ITEM_CHANCE:
				continue
			var roll := world.rng.randi_range(0, total - 1)
			for item in pool:
				roll -= SimConfig.ITEM_WEIGHTS[item]
				if roll < 0:
					world.hidden[c] = item
					break
	if world.cfg.item_enabled(SimConfig.Item.EVIL) and not blocks.is_empty():
		world.hidden[blocks[world.rng.randi_range(0, blocks.size() - 1)]] = SimConfig.Item.EVIL

# The block at c is gone: what it hid now lies there.
static func reveal(world: World, c: Vector2i) -> void:
	if world.hidden.has(c):
		world.items[c] = world.hidden[c]
		world.hidden.erase(c)

# A blast destroys the items lying in its cells.
static func burn(world: World, cells: Array[Vector2i]) -> void:
	for c in cells:
		if world.items.has(c):
			world.items.erase(c)
			world.events.append({"type": "item_burnt", "cell": c})

# Players walking over an item pick it up (a carried or flying player does not touch the ground).
static func update_pickups(world: World) -> void:
	for p: PlayerState in world.players.values():
		if p.life != PlayerState.Life.ALIVE or p.carried_by != -1:
			continue
		var c := p.cell()
		if world.items.has(c):
			var item: int = world.items[c]
			world.items.erase(c)
			apply(world, p, item)

static func apply(world: World, p: PlayerState, item: int) -> void:
	world.events.append({"type": "item", "id": p.id, "item": item})
	match item:
		SimConfig.Item.FIRE:
			p.fire = mini(p.fire + 1, SimConfig.FIRE_MAX)
		SimConfig.Item.BOMB:
			p.max_bombs = mini(p.max_bombs + 1, SimConfig.MAX_BOMBS_CAP)
		SimConfig.Item.POWER:
			p.power = true
		SimConfig.Item.REMOTE:
			p.remote = true
		SimConfig.Item.HEART:
			p.heart = true
		SimConfig.Item.SKULL:
			infect(world, p)
		SimConfig.Item.EVIL:
			start_evil(world)

# A random sickness for SICK_TIME, replacing the one p may have.
static func infect(world: World, p: PlayerState) -> void:
	p.sick = world.rng.randi_range(SimConfig.Sick.BIG, SimConfig.Sick.FIRE)
	p.sick_timer = SimConfig.SICK_TIME
	world.events.append({"type": "sick", "id": p.id, "sick": p.sick})

static func start_evil(world: World) -> void:
	world.evil = world.rng.randi_range(SimConfig.Evil.GULLIVER, SimConfig.Evil.PLAGUE)
	world.evil_timer = SimConfig.EVIL_TIME
	world.events.append({"type": "evil", "evil": world.evil})
	match world.evil:
		SimConfig.Evil.SHUFFLE:
			_shuffle(world)
		SimConfig.Evil.TWISTER:
			var free := _free_cells(world)
			world.twister_pos = Arena.center_of(free[world.rng.randi_range(0, free.size() - 1)]) if not free.is_empty() else Vector2.ZERO
			world.twister_dir = Vector2.RIGHT.rotated(world.rng.randf() * TAU)
		SimConfig.Evil.PLAGUE:
			world.plague_timer = 0.0

# Sicknesses and Evil wear off; a player still on fire when it does burns.
static func update(world: World) -> void:
	for p: PlayerState in world.players.values():
		if p.sick == SimConfig.Sick.NONE:
			continue
		p.sick_timer -= SimConfig.DT
		if p.sick_timer <= 1e-6:
			var burning := p.sick == SimConfig.Sick.FIRE
			cure(p)
			if burning and p.life == PlayerState.Life.ALIVE:
				world.kill(p.id, "burn")
	if world.evil == SimConfig.Evil.NONE:
		return
	match world.evil:
		SimConfig.Evil.TWISTER:
			_move_twister(world)
		SimConfig.Evil.PLAGUE:
			world.plague_timer -= SimConfig.DT
			if world.plague_timer <= 1e-6:
				world.plague_timer = SimConfig.PLAGUE_INTERVAL
				var free := _free_players(world)
				if not free.is_empty():
					var p := free[world.rng.randi_range(0, free.size() - 1)]
					p.stun_timer = maxf(p.stun_timer, SimConfig.DIZZY_TIME)
	world.evil_timer -= SimConfig.DT
	if world.evil_timer <= 1e-6:
		world.evil = SimConfig.Evil.NONE
		world.evil_timer = 0.0

static func cure(p: PlayerState) -> void:
	p.sick = SimConfig.Sick.NONE
	p.sick_timer = 0.0

# Losing a life loses the Remote and the sickness; the other items stay.
static func on_death(world: World, p: PlayerState) -> void:
	cure(p)
	if p.remote:
		p.remote = false
		for b: BombState in world.bombs.values():
			if b.owner_id == p.id:
				b.remote = false # its fuse burns from now on

# How fast p walks: slower when big, faster when tiny.
static func speed_of(world: World, p: PlayerState) -> float:
	if p.sick == SimConfig.Sick.BIG or world.evil == SimConfig.Evil.GULLIVER:
		return SimConfig.PLAYER_SPEED * SimConfig.BIG_SPEED
	if p.sick == SimConfig.Sick.TINY:
		return SimConfig.PLAYER_SPEED * SimConfig.TINY_SPEED
	return SimConfig.PLAYER_SPEED

# Power level a bomb goes off with.
static func level_of(world: World, b: BombState) -> int:
	if b.disguised or world.evil == SimConfig.Evil.MAXIMUM:
		return SimConfig.LEVEL_MAX
	return mini(b.level + b.pump, SimConfig.LEVEL_MAX)

static func radius_of(world: World, b: BombState) -> float:
	return SimConfig.blast_radius(level_of(world, b))

# Sets off p's oldest remote bomb lying on the ground (held or flying ones wait).
static func detonate(world: World, p: PlayerState) -> void:
	var oldest: BombState = null
	for b: BombState in world.bombs.values():
		if b.owner_id == p.id and b.remote and b.state == BombState.State.PLACED and (oldest == null or b.id < oldest.id):
			oldest = b
	if oldest != null:
		oldest.fuse = 0.0

# Alive players on the ground, free to move.
static func _free_players(world: World) -> Array[PlayerState]:
	var out: Array[PlayerState] = []
	for p: PlayerState in world.players.values():
		if p.life == PlayerState.Life.ALIVE and p.carried_by == -1:
			out.append(p)
	return out

static func _free_cells(world: World) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in world.arena.height:
		for x in world.arena.width:
			var c := Vector2i(x, y)
			if not world.arena.is_solid(c) and not world.is_submerged(c):
				out.append(c)
	return out

# Everyone on the ground swaps places at random.
static func _shuffle(world: World) -> void:
	var free := _free_players(world)
	var spots: Array[Vector2] = []
	for p in free:
		spots.append(p.pos)
	for i in range(spots.size() - 1, 0, -1):
		var j := world.rng.randi_range(0, i)
		var t := spots[i]
		spots[i] = spots[j]
		spots[j] = t
	for i in free.size():
		free[i].pos = spots[i]

# The twister wanders, bouncing off walls, and flings away whoever it touches.
static func _move_twister(world: World) -> void:
	var step := world.twister_dir * SimConfig.TWISTER_SPEED * SimConfig.DT
	var nxt := world.twister_pos + step
	var c := Arena.cell_of(nxt)
	if not world.arena.in_bounds(c) or world.arena.is_solid(c) or world.is_submerged(c):
		world.twister_dir = world.twister_dir.rotated(PI * (0.5 + world.rng.randf()))
	else:
		world.twister_pos = nxt
	for p in _free_players(world):
		if p.stun_timer <= 0.0 and p.pos.distance_to(world.twister_pos) < SimConfig.TWISTER_REACH:
			Carry.fling(world, p, ALL_DIRS[world.rng.randi_range(0, ALL_DIRS.size() - 1)])
