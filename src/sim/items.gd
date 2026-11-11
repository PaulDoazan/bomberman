class_name Items
extends RefCounted

# Items, as in Bomberman 64: hidden in blocks, revealed when the block goes (blown up or lifted),
# picked up by walking over them; blasts leave them be. Crates bring more down during a round, and a
# player who dies spills their Bomb items around. The Café navette makes whoever picks it up
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
	for item in _pool(world):
		pool.append(item)
		total += SimConfig.ITEM_WEIGHTS[item]
	if total > 0:
		for c in blocks:
			if world.rng.randf() < SimConfig.ITEM_CHANCE:
				world.hidden[c] = _draw(world, pool, total)

# One of the pool's items, drawn by ITEM_WEIGHTS (total: theirs summed).
static func _draw(world: World, pool: Array[int], total: int) -> int:
	var roll := world.rng.randi_range(0, total - 1)
	for item in pool:
		roll -= SimConfig.ITEM_WEIGHTS[item]
		if roll < 0:
			return item
	return pool[-1]

# The block at c is gone: what it hid now lies there.
static func reveal(world: World, c: Vector2i) -> void:
	if world.hidden.has(c):
		world.items[c] = world.hidden[c]
		world.hidden.erase(c)

# The items turned on that blocks and crates can hold.
static func _pool(world: World) -> Array[int]:
	var pool: Array[int] = []
	for item: int in SimConfig.ITEM_WEIGHTS:
		if world.cfg.item_enabled(item):
			pool.append(item)
	return pool

# A crate comes down every CRATE_EVERY seconds on a free cell; it and the spilt items in flight
# land, each on its cell, or the nearest free one if that has been taken meanwhile (lost if none).
static func update_drops(world: World) -> void:
	world.crate_timer -= SimConfig.DT
	if world.crate_timer <= 1e-6:
		world.crate_timer += SimConfig.CRATE_EVERY
		_drop_crate(world)
	var landed: Array = []
	for d: Drop in world.drops:
		d.elapsed += SimConfig.DT
		if d.elapsed >= d.duration() - 1e-6:
			landed.append(d)
	for d: Drop in landed:
		world.drops.erase(d)
		var c: Variant = _nearest_free(world, d.cell)
		if c != null:
			world.items[c] = d.item
			world.events.append({"type": "drop_landed", "cell": c, "item": d.item, "kind": d.kind})

static func _drop_crate(world: World) -> void:
	var pool := _pool(world)
	var cells := _free_cells(world, Vector2i.ZERO, maxi(world.arena.width, world.arena.height))
	if pool.is_empty() or cells.is_empty():
		return
	var total := 0
	for item in pool:
		total += SimConfig.ITEM_WEIGHTS[item]
	var d := Drop.new()
	d.uid = world.next_uid()
	d.kind = Drop.Kind.CRATE
	d.item = _draw(world, pool, total)
	d.cell = cells[world.rng.randi_range(0, cells.size() - 1)]
	world.drops.append(d)
	world.events.append({"type": "crate", "cell": d.cell})

# A cell an item can come down on: dry floor with no item lying there or on its way.
static func is_free_for_item(world: World, c: Vector2i) -> bool:
	if not world.arena.in_bounds(c) or world.arena.is_solid(c) or world.is_submerged(c) or world.items.has(c):
		return false
	for d: Drop in world.drops:
		if d.cell == c:
			return false
	return true

# The free cells within reach of around (in rows, then columns), all of them for a reach that
# covers the arena.
static func _free_cells(world: World, around: Vector2i, reach: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(around.y - reach, around.y + reach + 1):
		for x in range(around.x - reach, around.x + reach + 1):
			if is_free_for_item(world, Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out

static func _nearest_free(world: World, c: Vector2i) -> Variant:
	if is_free_for_item(world, c):
		return c
	var best: Variant = null
	for f in _free_cells(world, c, SimConfig.DROP_REACH):
		if best == null or (f - c).length_squared() < (best - c).length_squared():
			best = f
	return best

# A dying player loses their Bomb items: they burst out of them to free cells around.
static func spill_bombs(world: World, p: PlayerState) -> void:
	var extra := p.max_bombs - SimConfig.MAX_BOMBS
	p.max_bombs = SimConfig.MAX_BOMBS
	if extra <= 0:
		return
	var cells := _free_cells(world, p.cell(), SimConfig.DROP_REACH)
	cells.erase(p.cell())
	for i in range(cells.size() - 1, 0, -1): # shuffled
		var j := world.rng.randi_range(0, i)
		var t := cells[i]
		cells[i] = cells[j]
		cells[j] = t
	for i in mini(extra, cells.size()):
		var d := Drop.new()
		d.uid = world.next_uid()
		d.kind = Drop.Kind.SPILL
		d.item = SimConfig.Item.BOMB
		d.from = p.pos
		d.cell = cells[i]
		world.drops.append(d)

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

# Losing a life loses the Remote and the sickness and spills the Bomb items; the other items stay.
static func on_death(world: World, p: PlayerState) -> void:
	cure(p)
	spill_bombs(world, p)
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
