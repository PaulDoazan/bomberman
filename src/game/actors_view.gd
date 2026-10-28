class_name ActorsView
extends Node3D

const GHOST_HOVER := 1.5
const CARRY_HEIGHT := 1.5
const THROW_ARC := 1.5
const STAR_COUNT := 3
const STAR_ORBIT := 0.4
const STAR_HEIGHT := 1.4
const SIT_STAR_HEIGHT := 1.2 # stars above a player sitting knocked out
const HOP_HEIGHT := 0.35 # top of the hop of a player knocked back by a bomb
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
const ONE_SHOT_ANIMS := ["Lift", "Kick"] # played to the end before going back to the others
# Moves built from the Idle pose (the model has none of its own). Each key is [time, turns],
# a turn being a bone's rotation in degrees about the body's axes, on top of its parent's:
# about X (sideways) negative swings a leg forward or leans back, positive bends a knee; about
# Z (forward) it tilts sideways. "Hips_y" lowers the hips (skeleton units). Bones a move turns
# somewhere are back to the Idle pose in the keys that leave them out.
const KICK := {"loop": false, "keys": [
	[0.0, {}],
	[0.1, {"RightUpLeg": Vector3(25, 0, 0), "RightLeg": Vector3(70, 0, 0)}],
	[0.2, {"RightUpLeg": Vector3(-85, 0, 0), "RightLeg": Vector3(5, 0, 0), "Spine": Vector3(-12, 0, 0)}],
	[0.3, {"RightUpLeg": Vector3(-70, 0, 0), "RightLeg": Vector3(15, 0, 0), "Spine": Vector3(-10, 0, 0)}],
	[0.45, {}],
]}
# Sitting on the ground, knocked out, the head lolling from side to side.
const SIT := {"Hips_y": -0.3, "RightUpLeg": Vector3(-80, 0, 0), "LeftUpLeg": Vector3(-80, 0, 0),
		"RightLeg": Vector3(15, 0, 0), "LeftLeg": Vector3(15, 0, 0), "Spine": Vector3(-15, 0, 0)}
const STUNNED := {"loop": true, "keys": [
	[0.0, {"Head": Vector3(15, 0, 18), "Spine1": Vector3(0, 0, 4)}],
	[0.7, {"Head": Vector3(15, 0, -18), "Spine1": Vector3(0, 0, -4)}],
	[1.4, {"Head": Vector3(15, 0, 18), "Spine1": Vector3(0, 0, 4)}],
]}

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
	var seen_kick := -1 # kick_tick already animated

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
	if not ap.has_animation("Kick"): # the library is shared by every instance
		var sk: Skeleton3D = model.find_child("Skeleton3D", true, false)
		var lib := ap.get_animation_library("")
		lib.add_animation("Kick", _make_move(ap, sk, KICK))
		lib.add_animation("Stunned", _make_move(ap, sk, STUNNED, SIT))
	return model

# The Idle pose at its first frame, every track keyed once, turned per the move's keys (and
# per base at every key).
static func _make_move(ap: AnimationPlayer, sk: Skeleton3D, move: Dictionary, base := {}) -> Animation:
	var idle := ap.get_animation("Idle")
	var prefix := String(idle.track_get_path(0)).get_slice(":", 0) + ":mixamorig_"
	var keys: Array = move["keys"]
	var anim := Animation.new()
	anim.length = keys[-1][0]
	if move["loop"]:
		anim.loop_mode = Animation.LOOP_LINEAR
	for t in idle.get_track_count():
		var k := anim.add_track(idle.track_get_type(t))
		anim.track_set_path(k, idle.track_get_path(t))
		match idle.track_get_type(t):
			Animation.TYPE_POSITION_3D:
				anim.position_track_insert_key(k, 0.0, idle.position_track_interpolate(t, 0.0))
			Animation.TYPE_ROTATION_3D:
				anim.rotation_track_insert_key(k, 0.0, idle.rotation_track_interpolate(t, 0.0))
			Animation.TYPE_SCALE_3D:
				anim.scale_track_insert_key(k, 0.0, idle.scale_track_interpolate(t, 0.0))
	var turned := {}
	for key: Array in keys:
		turned.merge(key[1])
	turned.merge(base)
	for bone: String in turned:
		var is_pos := bone == "Hips_y"
		var path := NodePath(prefix + ("Hips" if is_pos else bone))
		var type := Animation.TYPE_POSITION_3D if is_pos else Animation.TYPE_ROTATION_3D
		var k := anim.find_track(path, type)
		var rest := sk.get_bone_rest(sk.find_bone("mixamorig_" + ("Hips" if is_pos else bone)))
		var start: Variant = rest.origin if is_pos else rest.basis.get_rotation_quaternion()
		if k < 0:
			k = anim.add_track(type)
			anim.track_set_path(k, path)
		else:
			start = anim.track_get_key_value(k, 0)
			anim.track_remove_key(k, 0)
		for key: Array in keys:
			var turn: Variant = key[1].get(bone, base.get(bone, 0.0 if is_pos else Vector3.ZERO))
			if is_pos:
				anim.position_track_insert_key(k, key[0], start + Vector3(0, turn, 0))
			else:
				var parent := _idle_global(idle, sk, prefix, sk.get_bone_parent(sk.find_bone("mixamorig_" + bone)))
				anim.rotation_track_insert_key(k, key[0], _turned(parent, start, turn))
	return anim

# Rotation of a bone in skeleton space in the Idle pose's first frame (-1: the skeleton itself).
static func _idle_global(idle: Animation, sk: Skeleton3D, prefix: String, bone: int) -> Quaternion:
	if bone < 0:
		return Quaternion.IDENTITY
	var name := sk.get_bone_name(bone)
	var t := idle.find_track(NodePath(prefix + name.trim_prefix("mixamorig_")), Animation.TYPE_ROTATION_3D)
	var local := idle.rotation_track_interpolate(t, 0.0) if t >= 0 else sk.get_bone_rest(bone).basis.get_rotation_quaternion()
	return _idle_global(idle, sk, prefix, sk.get_bone_parent(bone)) * local

# Local rotation of a bone turned by deg (degrees about the skeleton's axes, the body's own),
# given its parent's rotation in skeleton space.
static func _turned(parent: Quaternion, local: Quaternion, deg: Vector3) -> Quaternion:
	var turn := Quaternion.from_euler(deg * PI / 180.0)
	return parent.inverse() * turn * parent * local

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
			n.seen_kick = p.kick_tick
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
		var hop := 0.0
		if p.knock_timer > 0.0 and not ghost:
			var s := 1.0 - p.knock_timer / SimConfig.KNOCK_TIME
			hop = 4.0 * HOP_HEIGHT * s * (1.0 - s)
		_track(n, Vector3(pos.x, n.y_smooth + hop, pos.y), p.life == PlayerState.Life.WAITING_RESPAWN)
		n.body.material_override = _ghost_mat if ghost else n.mat
		var stunned := p.stun_timer > 0.0
		n.stars.visible = stunned and not ghost
		if stunned:
			n.stars.rotation.y = _time * STAR_SPIN
			n.stars.position.y = SIT_STAR_HEIGHT if _sitting(p) else STAR_HEIGHT
		n.model.rotation.y = lerp_angle(n.model.rotation.y, _yaw(p.aim), TURN_SPEED)
		var kicked := p.kick_tick != n.seen_kick
		n.seen_kick = p.kick_tick
		_animate(n, p, kicked)
		if p.invulnerable_timer > 0.0 and not ghost:
			n.model.visible = int(_time * 10.0) % 2 == 0
		else:
			n.model.visible = true
		n.held_bomb.visible = p.held == PlayerState.Held.BOMB
		n.held_block.visible = p.held == PlayerState.Held.BLOCK

# Yaw that turns the model (facing +Z) towards an aim direction on the grid (x -> X, y -> Z).
static func _yaw(aim: Vector2i) -> float:
	return atan2(float(aim.x), float(aim.y))

# Knocked out on the ground: stunned, and neither carried nor flying.
static func _sitting(p: PlayerState) -> bool:
	return p.stun_timer > 0.0 and p.life == PlayerState.Life.ALIVE and p.carried_by < 0

# Idle, run, kick, lift, carry, then sitting knocked out, from what the player is doing this tick.
func _animate(n: PlayerNode, p: PlayerState, kicked: bool) -> void:
	var moved := n.last_pos != Vector2.INF and p.pos.distance_to(n.last_pos) > 0.01
	n.last_pos = p.pos
	var lifting := n.last_held == PlayerState.Held.NONE and p.held != PlayerState.Held.NONE
	n.last_held = p.held
	if kicked:
		if n.anim.current_animation == "Kick":
			n.anim.seek(0.0, true) # kicking again mid-kick replays it from the start
		else:
			n.anim.play("Kick", 0.05)
		return
	if lifting:
		var lift := n.anim.get_animation("Lift").length
		n.anim.play("Lift", 0.1, lift / LIFT_TIME)
		return
	var sitting := _sitting(p)
	if not sitting and n.anim.current_animation in ONE_SHOT_ANIMS and n.anim.is_playing():
		return
	var want := "Idle"
	if sitting:
		want = "Stunned"
	elif p.life == PlayerState.Life.ALIVE and p.carried_by < 0:
		if p.held != PlayerState.Held.NONE:
			want = "Carry"
		elif moved:
			want = "Run"
	if n.anim.current_animation != want:
		n.anim.play(want, 0.25 if sitting else 0.15)

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
