class_name Carry
extends RefCounted

# Picking up, carrying and throwing bombs, players and blocks. Static helpers over a World.

# carried_by of a player in flight: neither free (-1) nor carried by anyone. Such a player
# cannot act, be hit, drown or be possessed until they land.
const THROWN := -2

# ALIVE, not carried or in flight, standing in cell c.
static func _free_players_at(world: World, c: Vector2i) -> Array[PlayerState]:
	var out: Array[PlayerState] = []
	for p: PlayerState in world.players.values():
		if p.life == PlayerState.Life.ALIVE and p.carried_by == -1 and p.cell() == c:
			out.append(p)
	return out

# Current position of a flying object; a null landing keeps it at its origin.
static func flight_pos(f: FlyingObject) -> Vector2:
	if f.landing == null:
		return f.from
	return f.from.lerp(Arena.center_of(f.landing), f.progress())

# What p holds drops on their cell, and p stops being carried (their carrier's hands are freed).
static func release_links(world: World, p: PlayerState) -> void:
	match p.held:
		PlayerState.Held.BOMB:
			var b: BombState = world.bombs.get(p.held_id, null)
			if b != null and b.state == BombState.State.HELD:
				b.state = BombState.State.PLACED
				b.cell = p.cell()
				b.passable_for.clear()
		PlayerState.Held.PLAYER:
			var c: PlayerState = world.players[p.held_id]
			c.carried_by = -1
			c.pos = Arena.center_of(p.cell())
	p.held = PlayerState.Held.NONE
	p.held_id = -1
	if p.carried_by >= 0:
		var carrier: PlayerState = world.players[p.carried_by]
		carrier.held = PlayerState.Held.NONE
		carrier.held_id = -1
		p.carried_by = -1

# A block never lands on stairs: it would turn the stair into a plain floor cell once destroyed.
static func _is_free_landing(world: World, c: Vector2i, kind: int) -> bool:
	if not world.arena.in_bounds(c) or world.arena.is_solid(c) or world.bomb_at(c) != null:
		return false
	if kind == PlayerState.Held.BLOCK and world.arena.tile_at(c) == Arena.Tile.STAIRS:
		return false
	return kind == PlayerState.Held.BOMB or _free_players_at(world, c).is_empty()

# First free cell from `start` going along `dir`; Vector2i out of bounds when none.
static func _find_landing(world: World, start: Vector2i, dir: Vector2i, kind: int) -> Vector2i:
	var land := start
	while world.arena.in_bounds(land) and not _is_free_landing(world, land, kind):
		land += dir
	return land

static func pick_up(world: World, p: PlayerState) -> void:
	var own := world.bomb_at(p.cell())
	if own != null:
		_hold_bomb(p, own)
		return
	var front := p.cell() + p.facing
	if not world.arena.in_bounds(front):
		return
	var b := world.bomb_at(front)
	if b != null:
		_hold_bomb(p, b)
		return
	for other: PlayerState in _free_players_at(world, front):
		if other == p:
			continue
		other.carried_by = p.id
		other.carried_timer = SimConfig.CARRY_ESCAPE
		p.held = PlayerState.Held.PLAYER
		p.held_id = other.id
		return
	if world.arena.tile_at(front) == Arena.Tile.BLOCK:
		world.arena.set_tile(front, Arena.Tile.FLOOR)
		p.held = PlayerState.Held.BLOCK
		p.held_id = -1

static func _hold_bomb(p: PlayerState, b: BombState) -> void:
	b.state = BombState.State.HELD
	b.offset = Vector2.ZERO
	b.passable_for.clear()
	p.held = PlayerState.Held.BOMB
	p.held_id = b.id

static func throw(world: World, p: PlayerState) -> void:
	if p.aim == Vector2i.ZERO:
		return
	if (p.held == PlayerState.Held.BOMB and not world.bombs.has(p.held_id)) \
			or (p.held == PlayerState.Held.PLAYER and not world.players.has(p.held_id)):
		p.held = PlayerState.Held.NONE
		p.held_id = -1
		return
	var f := FlyingObject.new()
	f.kind = p.held
	f.ref_id = p.held_id
	f.from = p.pos
	f.dir = p.aim
	# Diagonal throws cover about the same distance as straight ones.
	var dist := SimConfig.THROW_DISTANCE if p.aim.x == 0 or p.aim.y == 0 else roundi(SimConfig.THROW_DISTANCE / sqrt(2.0))
	var land := _find_landing(world, p.cell() + p.aim * dist, p.aim, p.held)
	if world.arena.in_bounds(land):
		f.landing = land
	f.to = Arena.center_of(land)
	match p.held:
		PlayerState.Held.BOMB:
			world.bombs[p.held_id].state = BombState.State.FLYING
		PlayerState.Held.PLAYER:
			world.players[p.held_id].carried_by = THROWN
	world.flying.append(f)
	p.held = PlayerState.Held.NONE
	p.held_id = -1

# Carried players follow their carrier and break free when their timer runs out.
static func update_carried(world: World) -> void:
	for p: PlayerState in world.players.values():
		if p.carried_by < 0:
			continue
		var carrier: PlayerState = world.players[p.carried_by]
		p.pos = carrier.pos
		p.carried_timer -= SimConfig.DT
		if p.carried_timer <= 0.0:
			p.carried_by = -1
			p.pos = Arena.center_of(carrier.cell())
			carrier.held = PlayerState.Held.NONE
			carrier.held_id = -1

static func update_flying(world: World) -> void:
	var landed: Array[FlyingObject] = []
	for f: FlyingObject in world.flying:
		f.elapsed += SimConfig.DT
		if f.elapsed >= SimConfig.THROW_FLIGHT - 1e-6:
			landed.append(f)
	for f in landed:
		world.flying.erase(f)
		_land(world, f)

static func _land(world: World, f: FlyingObject) -> void:
	# The planned cell may have been taken during the flight: keep going along the throw direction.
	var c := Vector2i.ZERO
	var in_map := f.landing != null
	if in_map:
		c = _find_landing(world, f.landing, f.dir, f.kind)
		in_map = world.arena.in_bounds(c)
		if not in_map:
			f.to = Arena.center_of(c)
	if not in_map:
		world.events.append({"type": "splash", "pos": f.to})
		match f.kind:
			PlayerState.Held.BOMB:
				world.bombs.erase(f.ref_id)
			PlayerState.Held.PLAYER:
				var t: PlayerState = world.players[f.ref_id]
				t.carried_by = -1
				world.kill(t.id, "drown")
		return
	f.landing = c
	match f.kind:
		PlayerState.Held.BOMB:
			var b: BombState = world.bombs[f.ref_id]
			b.state = BombState.State.PLACED
			b.cell = c
			b.offset = Vector2.ZERO
			b.passable_for.clear()
			for hit: PlayerState in _free_players_at(world, c):
				world.hit_by_bomb(hit, Vector2(f.dir))
		PlayerState.Held.BLOCK:
			world.arena.set_tile(c, Arena.Tile.BLOCK)
		PlayerState.Held.PLAYER:
			var t: PlayerState = world.players[f.ref_id]
			t.carried_by = -1
			t.pos = Arena.center_of(c)
			t.stun_timer = SimConfig.STUN_TIME
