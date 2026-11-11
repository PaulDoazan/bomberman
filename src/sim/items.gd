class_name Items
extends RefCounted

# Items, as in Bomberman 64: hidden in blocks, revealed when the block goes (blown up or lifted),
# picked up by walking over them; blasts leave them be. The Café navette makes whoever picks it up
# sick for a while (it can also be lifted from the front and thrown at someone). Static helpers
# over a World.

# Draws what each block hides, among the items turned on: about ITEM_CHANCE of them hide one
# (by ITEM_WEIGHTS).
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

# The block at c is gone: what it hid now lies there.
static func reveal(world: World, c: Vector2i) -> void:
	if world.hidden.has(c):
		world.items[c] = world.hidden[c]
		world.hidden.erase(c)

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
		SimConfig.Item.REMOTE:
			p.remote = true
		SimConfig.Item.HEART:
			p.heart = true
		SimConfig.Item.COFFEE:
			infect(world, p)

# A random sickness for SICK_TIME, replacing the one p may have.
static func infect(world: World, p: PlayerState) -> void:
	p.sick = world.rng.randi_range(SimConfig.Sick.BIG, SimConfig.Sick.FIRE)
	p.sick_timer = SimConfig.SICK_TIME
	world.events.append({"type": "sick", "id": p.id, "sick": p.sick})

# Sicknesses wear off; a player still on fire when it does burns.
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
	if p.sick == SimConfig.Sick.BIG:
		return SimConfig.PLAYER_SPEED * SimConfig.BIG_SPEED
	if p.sick == SimConfig.Sick.TINY:
		return SimConfig.PLAYER_SPEED * SimConfig.TINY_SPEED
	return SimConfig.PLAYER_SPEED

# Power level a bomb goes off with.
static func level_of(world: World, b: BombState) -> int:
	if b.disguised:
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
