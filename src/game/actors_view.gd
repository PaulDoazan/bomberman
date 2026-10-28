class_name ActorsView
extends Node3D

const GHOST_HOVER := 1.5
const CARRY_HEIGHT := 1.5
const THROW_ARC := 1.5
const STAR_COUNT := 3
const STAR_ORBIT := 0.4
const STAR_HEIGHT := 1.4
const STAR_SPIN := 6.0 # radians per second
const CORPSE_TIME := 2.5 # seconds a burnt body stays on screen
const CORPSE_FADE := 0.6 # last part of CORPSE_TIME, spent fading out
const CORPSE_COLOR := Color(0.06, 0.05, 0.05)
const CHARACTER := preload("res://assets/characters/bomberman.glb")
const PALETTE := preload("res://assets/characters/bomberman_palette.png")
const TINT_SHADER := preload("res://src/game/player_tint.gdshader")
const MODEL_SCALE := 1.2 / 1.75 # the model is 1.75 units tall; players stand about 1.2 cells
const TURN_SPEED := 0.35 # fraction of the remaining angle turned per tick
const LIFT_TIME := 0.3 # seconds the lift animation is squeezed into
const LOOPED_ANIMS := ["Idle", "Walk", "Run", "Carry"]

class PlayerNode:
	extends Node3D
	var model: Node3D # the character, turned towards the aim
	var body: MeshInstance3D
	var anim: AnimationPlayer
	var held_bomb: MeshInstance3D
	var held_block: MeshInstance3D
	var stars: Node3D # spins above the head while stunned
	var mat: ShaderMaterial
	var last_pos := Vector2.INF
	var last_held := PlayerState.Held.NONE
	var y_smooth := 0.0
	var placed := false
	var seen_death := -1 # died_tick already handled, so each death leaves one body

var _players: Dictionary = {} # id -> PlayerNode
var _bombs: Dictionary = {} # id -> MeshInstance3D
var _blocks_flying: Dictionary = {} # FlyingObject instance id -> MeshInstance3D
var _domes: Dictionary = {} # Explosion instance id -> MeshInstance3D
var _corpses: Array[Dictionary] = [] # {node: Node3D, mat: StandardMaterial3D, born: float}

var _bomb_mesh := SphereMesh.new()
var _block_mesh := BoxMesh.new()
var _dome_mesh := SphereMesh.new()
var _ghost_mat := StandardMaterial3D.new()
var _bomb_mat := StandardMaterial3D.new()
var _block_mat := StandardMaterial3D.new()
var _dome_mat := StandardMaterial3D.new()
var _star_mesh := _make_star_mesh(0.16, 0.07)
var _star_mat := StandardMaterial3D.new()
var _time := 0.0
var _tracks: Dictionary = {} # Node3D -> [prev: Vector3, cur: Vector3]
const SNAP_DISTANCE := 1.2
# Half-size of the footprint used to find the ground under a player: slightly inside the
# collision box so merely brushing a step does not lift the player.
const FOOT_HALF := 0.3

# Remembers the previous and current sim position of a node; render() interpolates between them.
func _track(node: Node3D, pos: Vector3, snap: bool = false) -> void:
	var t: Array = _tracks.get(node, [])
	if t.is_empty() or snap or (t[1] as Vector3).distance_to(pos) > SNAP_DISTANCE:
		_tracks[node] = [pos, pos]
		node.position = pos
	else:
		t[0] = t[1]
		t[1] = pos

func _untrack(node: Node3D) -> void:
	_tracks.erase(node)
	node.queue_free()

# Called every rendered frame with alpha in [0, 1] = progress towards the next sim tick.
func render(alpha: float) -> void:
	for node: Node3D in _tracks:
		var t: Array = _tracks[node]
		node.position = (t[0] as Vector3).lerp(t[1], alpha)

# Drops all actors (new round) so nothing interpolates across worlds.
func reset() -> void:
	for d: Dictionary in [_players, _bombs, _blocks_flying, _domes]:
		for n: Node3D in d.values():
			n.queue_free()
		d.clear()
	for c: Dictionary in _corpses:
		c["node"].queue_free()
	_corpses.clear()
	_tracks.clear()

func _ready() -> void:
	_bomb_mesh.radius = SimConfig.BOMB_BODY_RADIUS
	_bomb_mesh.height = 2.0 * SimConfig.BOMB_BODY_RADIUS
	_block_mesh.size = Vector3(0.8, 0.8, 0.8)
	_dome_mesh.radius = SimConfig.BOMB_RADIUS
	_dome_mesh.height = 2.0 * SimConfig.BOMB_RADIUS
	_ghost_mat.albedo_color = Color(1, 1, 1, 0.4)
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bomb_mat.albedo_color = Color("111111")
	_block_mat.albedo_color = Color("9a6a35")
	_dome_mat.albedo_color = Color(1.0, 0.5, 0.1, 0.55)
	_dome_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dome_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dome_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_star_mat.albedo_color = Color("ffe14d")
	_star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED # always faces the top-down camera

# Flat five-pointed star in the XY plane (billboarded by its material).
static func _make_star_mesh(outer: float, inner: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	for i in 10:
		var r := outer if i % 2 == 0 else inner
		var a := PI / 2.0 + TAU * i / 10.0
		pts.append(Vector3(cos(a), sin(a), 0.0) * r)
	for i in 10:
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(pts[i])
		st.add_vertex(pts[(i + 1) % 10])
	return st.commit()

func _mesh(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	return m

# A new instance of the character; its looping animations are set up on first use.
func _make_model() -> Node3D:
	var model: Node3D = CHARACTER.instantiate()
	model.scale = Vector3.ONE * MODEL_SCALE
	var ap: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	for a: String in LOOPED_ANIMS:
		ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	return model

func _make_player(color: Color) -> PlayerNode:
	var n := PlayerNode.new()
	n.mat = ShaderMaterial.new()
	n.mat.shader = TINT_SHADER
	n.mat.set_shader_parameter("palette", PALETTE)
	n.mat.set_shader_parameter("tint", color)
	n.model = _make_model()
	n.body = n.model.find_child("Body", true, false)
	n.body.material_override = n.mat
	n.anim = n.model.find_child("AnimationPlayer", true, false)
	n.anim.play("Idle")
	n.held_bomb = _mesh(_bomb_mesh, _bomb_mat)
	n.held_bomb.position.y = CARRY_HEIGHT
	n.held_block = _mesh(_block_mesh, _block_mat)
	n.held_block.position.y = CARRY_HEIGHT
	n.stars = Node3D.new()
	n.stars.position.y = STAR_HEIGHT
	for i in STAR_COUNT:
		var s := _mesh(_star_mesh, _star_mat)
		var a := TAU * i / STAR_COUNT
		s.position = Vector3(cos(a), 0.0, sin(a)) * STAR_ORBIT
		n.stars.add_child(s)
	for c in [n.model, n.held_bomb, n.held_block, n.stars]:
		n.add_child(c)
	add_child(n)
	return n

func _cell_y(world: World, pos: Vector2) -> float:
	var c := Arena.cell_of(pos)
	if not world.arena.in_bounds(c):
		return 0.0
	return world.arena.h2_at(c) * 0.5

# Highest drawn surface under the player's footprint, so the body never sinks into a step
# it is climbing onto and stays on a ledge until it has fully left it.
func _foot_y(world: World, pos: Vector2) -> float:
	var arena := world.arena
	var best := -INF
	for off in [Vector2.ZERO, Vector2(-FOOT_HALF, -FOOT_HALF), Vector2(FOOT_HALF, -FOOT_HALF),
			Vector2(-FOOT_HALF, FOOT_HALF), Vector2(FOOT_HALF, FOOT_HALF)]:
		var pt: Vector2 = pos + off
		var c := Arena.cell_of(pt)
		if arena.in_bounds(c) and not arena.is_solid(c):
			best = maxf(best, ArenaView.surface_y(arena, pt))
	return _cell_y(world, pos) if best == -INF else best

func _ground(world: World, pos: Vector2) -> Vector3:
	return Vector3(pos.x, _cell_y(world, pos), pos.y)

func sync(world: World, match_state: MatchState) -> void:
	_time += SimConfig.DT
	_sync_players(world, match_state)
	_sync_bombs(world)
	_sync_flying(world)
	_sync_explosions(world)
	_sync_corpses()

func _sync_players(world: World, match_state: MatchState) -> void:
	for id: int in _players.keys():
		if not world.players.has(id):
			_untrack(_players[id])
			_players.erase(id)
	for id: int in world.players:
		var p: PlayerState = world.players[id]
		var mp := match_state.player(id)
		var n: PlayerNode = _players.get(id, null)
		if n == null:
			n = _make_player(mp.color if mp != null else Color.WHITE)
			n.seen_death = p.died_tick
			_players[id] = n
		if p.died_tick != n.seen_death:
			n.seen_death = p.died_tick
			if p.death_cause == "explosion":
				_spawn_corpse(Vector3(p.pos.x, n.y_smooth, p.pos.y), n)
		var ghost := p.life == PlayerState.Life.GHOST
		n.visible = p.life != PlayerState.Life.WAITING_RESPAWN
		var thrown := p.carried_by == Carry.THROWN
		var pos := p.pos
		var y := _foot_y(world, pos)
		if thrown:
			var f := _flight_of(world, PlayerState.Held.PLAYER, id)
			if f != null:
				var a := _arc(world, f)
				pos = Vector2(a.x, a.z)
				y = a.y
		elif p.carried_by >= 0 and world.players.has(p.carried_by):
			var carrier: PlayerState = world.players[p.carried_by]
			pos = carrier.pos
			y = _cell_y(world, pos) + CARRY_HEIGHT
		if ghost:
			y += GHOST_HOVER
		if not n.placed or thrown or p.carried_by >= 0:
			n.y_smooth = y
			n.placed = true
		elif y >= n.y_smooth:
			n.y_smooth = y # climbing: never lag below the step
		else:
			n.y_smooth = lerpf(n.y_smooth, y, 0.35) # falling off a ledge
		_track(n, Vector3(pos.x, n.y_smooth, pos.y), p.life == PlayerState.Life.WAITING_RESPAWN)
		n.body.material_override = _ghost_mat if ghost else n.mat
		var stunned := p.stun_timer > 0.0
		n.stars.visible = stunned and not ghost
		if stunned:
			n.stars.rotation.y = _time * STAR_SPIN
		n.model.rotation.y = lerp_angle(n.model.rotation.y, _yaw(p.aim), TURN_SPEED)
		_animate(n, p)
		if p.invulnerable_timer > 0.0 and not ghost:
			n.model.visible = int(_time * 10.0) % 2 == 0
		else:
			n.model.visible = true
		n.held_bomb.visible = p.held == PlayerState.Held.BOMB
		n.held_block.visible = p.held == PlayerState.Held.BLOCK

# Yaw that turns the model (facing +Z) towards an aim direction on the grid (x -> X, y -> Z).
static func _yaw(aim: Vector2i) -> float:
	return atan2(float(aim.x), float(aim.y))

# Idle, run, lift then carry, from what the player is doing this tick.
func _animate(n: PlayerNode, p: PlayerState) -> void:
	var moved := n.last_pos != Vector2.INF and p.pos.distance_to(n.last_pos) > 0.01
	n.last_pos = p.pos
	var lifting := n.last_held == PlayerState.Held.NONE and p.held != PlayerState.Held.NONE
	n.last_held = p.held
	if lifting:
		var lift := n.anim.get_animation("Lift").length
		n.anim.play("Lift", 0.1, lift / LIFT_TIME)
		return
	if n.anim.current_animation == "Lift" and n.anim.is_playing():
		return
	var want := "Idle"
	if p.life == PlayerState.Life.ALIVE and p.carried_by < 0:
		if p.held != PlayerState.Held.NONE:
			want = "Carry"
		elif moved:
			want = "Run"
	if n.anim.current_animation != want:
		n.anim.play(want, 0.15)

# A charred, black copy of the body left where a player was blown up, frozen in the pose they
# died in; it fades out after a while.
func _spawn_corpse(at: Vector3, from: PlayerNode) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CORPSE_COLOR
	mat.roughness = 1.0
	var node := _make_model()
	node.position = at
	node.rotation.y = from.model.rotation.y
	add_child(node)
	var body: MeshInstance3D = node.find_child("Body", true, false)
	body.material_override = mat
	var ap: AnimationPlayer = node.find_child("AnimationPlayer", true, false)
	var posed := from.anim.current_animation != ""
	ap.play(from.anim.current_animation if posed else "Idle")
	ap.seek(from.anim.current_animation_position if posed else 0.0, true)
	ap.pause()
	_corpses.append({"node": node, "mat": mat, "born": _time})

func _sync_corpses() -> void:
	var kept: Array[Dictionary] = []
	for c: Dictionary in _corpses:
		var age: float = _time - c["born"]
		if age >= CORPSE_TIME:
			c["node"].queue_free()
			continue
		var fade := clampf((CORPSE_TIME - age) / CORPSE_FADE, 0.0, 1.0)
		var mat: StandardMaterial3D = c["mat"]
		if fade < 1.0:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = fade
		kept.append(c)
	_corpses = kept

func _flight_of(world: World, kind: int, ref_id: int) -> FlyingObject:
	for f: FlyingObject in world.flying:
		if f.kind == kind and f.ref_id == ref_id:
			return f
	return null

# Position on the parabolic arc of a flying object: x, y (height), z.
func _arc(world: World, f: FlyingObject) -> Vector3:
	var prog := f.progress()
	var dest: Vector2 = Arena.center_of(f.landing) if f.landing != null else f.to
	var pos := f.from.lerp(dest, prog)
	var y0 := _cell_y(world, f.from)
	var y1 := y0
	if f.landing != null:
		y1 = _cell_y(world, dest)
	var y := lerpf(y0, y1, prog) + 4.0 * THROW_ARC * prog * (1.0 - prog) + 0.2
	return Vector3(pos.x, y, pos.y)

func _sync_bombs(world: World) -> void:
	for id: int in _bombs.keys():
		if not world.bombs.has(id):
			_untrack(_bombs[id])
			_bombs.erase(id)
	for id: int in world.bombs:
		var b: BombState = world.bombs[id]
		var m: MeshInstance3D = _bombs.get(id, null)
		if m == null:
			m = _mesh(_bomb_mesh, _bomb_mat)
			add_child(m)
			_bombs[id] = m
			_track(m, Vector3.ZERO)
		m.visible = b.state != BombState.State.HELD # drawn on the holder instead
		if b.state == BombState.State.FLYING:
			var f := _flight_of(world, PlayerState.Held.BOMB, id)
			if f != null:
				_track(m, _arc(world, f))
		elif b.state == BombState.State.PLACED:
			var at := b.pos()
			_track(m, Vector3(at.x, world.arena.h2_at(b.cell) * 0.5 + SimConfig.BOMB_BODY_RADIUS, at.y))
		var s := 1.0
		if b.fuse < 0.5:
			s = 1.0 + 0.25 * (1.0 - b.fuse / 0.5)
		m.scale = Vector3.ONE * s

func _sync_flying(world: World) -> void:
	var alive: Dictionary = {}
	for f: FlyingObject in world.flying:
		if f.kind != PlayerState.Held.BLOCK:
			continue
		var key := f.get_instance_id()
		alive[key] = true
		var m: MeshInstance3D = _blocks_flying.get(key, null)
		if m == null:
			m = _mesh(_block_mesh, _block_mat)
			add_child(m)
			_blocks_flying[key] = m
			_track(m, _arc(world, f), true)
		else:
			_track(m, _arc(world, f))
	for key: int in _blocks_flying.keys():
		if not alive.has(key):
			_untrack(_blocks_flying[key])
			_blocks_flying.erase(key)

func _sync_explosions(world: World) -> void:
	var alive: Dictionary = {}
	for e: Explosion in world.explosions:
		var key := e.get_instance_id()
		alive[key] = true
		var m: MeshInstance3D = _domes.get(key, null)
		if m == null:
			m = _mesh(_dome_mesh, _dome_mat)
			add_child(m)
			_domes[key] = m
			m.position = Vector3(e.centre.x, world.arena.h2_at(e.origin) * 0.5, e.centre.y)
		m.scale = Vector3.ONE * (e.radius() / SimConfig.BOMB_RADIUS)
	for key: int in _domes.keys():
		if not alive.has(key):
			_domes[key].queue_free()
			_domes.erase(key)
