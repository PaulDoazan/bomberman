class_name DangerMap
extends RefCounted

# Maps each endangered cell to the seconds left before it is hit: 0.0 under an active
# explosion, otherwise the (chain-adjusted) fuse of the earliest bomb reaching it (a remote bomb
# counts as a full fuse). extra_bomb (Vector2i) adds a hypothetical bomb of the given player's
# with a full fuse.
static func build(world: World, extra_bomb: Variant = null, extra_owner: PlayerState = null) -> Dictionary:
	var danger: Dictionary = {}
	for e: Explosion in world.explosions:
		for c in e.cells:
			danger[c] = 0.0
	var fuses: Array[float] = []
	var blasts: Array[Array] = []
	var origins: Array[Vector2i] = []
	for b: BombState in world.bombs.values():
		if b.state == BombState.State.FLYING:
			continue # airborne: it lands somewhere unknown
		var origin := world.bomb_cell(b)
		origins.append(origin)
		fuses.append(SimConfig.FUSE if b.remote else b.fuse)
		blasts.append(Explosion.hit_cells(world.arena, origin, Items.radius_of(world, b), b.pierce))
	if extra_bomb != null:
		origins.append(extra_bomb)
		fuses.append(SimConfig.FUSE)
		var level := extra_owner.fire if extra_owner != null else 1
		blasts.append(Explosion.hit_cells(world.arena, extra_bomb, SimConfig.blast_radius(level),
				extra_owner != null and extra_owner.power))
	# Chain reactions: a bomb inside a blast with a shorter fuse inherits that fuse.
	var changed := true
	while changed:
		changed = false
		for i in origins.size():
			for j in origins.size():
				if i != j and fuses[j] < fuses[i] and origins[i] in blasts[j]:
					fuses[i] = fuses[j]
					changed = true
	for i in origins.size():
		for c: Vector2i in blasts[i]:
			danger[c] = minf(danger.get(c, INF), fuses[i])
	return danger
