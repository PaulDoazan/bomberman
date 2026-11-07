class_name ItemsView
extends Node3D

# Items lying on the ground, bobbing a little above it, and Evil's twister. Each item is a
# coloured tile with a short label; the Skull is a little skull, Evil a fly agaric, the Heart a big pink heart and
# the Fire a little fire.

const COLORS := {
	SimConfig.Item.FIRE: Color("ff5a1f"),
	SimConfig.Item.BOMB: Color("2a3550"),
	SimConfig.Item.REMOTE: Color("1e7be0"),
	SimConfig.Item.HEART: Color("ff4f9a"),
	SimConfig.Item.EVIL: Color("e0201b"), # the fly agaric's cap
}
const TEXTS := {
	SimConfig.Item.FIRE: "FEU",
	SimConfig.Item.BOMB: "+1",
	SimConfig.Item.REMOTE: "TÉLÉ",
	SimConfig.Item.HEART: "CŒUR",
}
const HOVER := 0.3 # height of an item above the ground
const BOB := 0.08
const TWISTER_SPIN := 9.0 # radians per second
const HEART_HEIGHT := 0.6 # half a player
const HEART_DEPTH := 0.14 # how far each face bulges, like an emoji
const FIRE_HEIGHT := 0.6
const MUSHROOM_CAP := 0.3 # radius of the fly agaric's cap
const MUSHROOM_STEM := 0.3 # height of its stem
const PUFFY_SIDES := 48
const FLICKER := 0.08 # how much a fire stretches and squashes as it flickers

var _ground: Dictionary = {} # cell -> Node3D
var _twister: Node3D
var _time := 0.0

func _init() -> void:
	_twister = _make_twister()
	_twister.visible = false
	add_child(_twister)

func reset() -> void:
	for n: Node3D in _ground.values():
		n.queue_free()
	_ground.clear()
	_twister.visible = false

# dt: the sim time since the previous sync, one tick in solo, a snapshot interval online.
func sync(world: World, dt: float = SimConfig.DT) -> void:
	_time += dt
	for c: Vector2i in _ground.keys():
		if not world.items.has(c) or _ground[c].get_meta("item") != world.items[c]:
			_ground[c].queue_free()
			_ground.erase(c)
	for c: Vector2i in world.items:
		var n: Node3D = _ground.get(c, null)
		if n == null:
			n = make_item(world.items[c])
			add_child(n)
			_ground[c] = n
		var bob := sin(_time * 3.0 + c.x + c.y) * BOB
		n.position = Vector3(c.x + 0.5, world.arena.h2_at(c) * 0.5 + HOVER + bob, c.y + 0.5)
		if world.items[c] == SimConfig.Item.FIRE: # flickers
			var f := sin(_time * 17.0 + c.x * 3.0) * 0.6 + sin(_time * 29.0 + c.y) * 0.4
			n.scale = Vector3(1.0 - f * FLICKER * 0.5, 1.0 + f * FLICKER, 1.0)
	_twister.visible = world.evil == SimConfig.Evil.TWISTER
	if _twister.visible:
		var at := world.twister_pos
		var c := Arena.cell_of(at)
		var y := world.arena.h2_at(c) * 0.5 if world.arena.in_bounds(c) else 0.0
		_twister.position = Vector3(at.x, y, at.y)
		_twister.rotation.y = _time * TWISTER_SPIN

# A new drawing of an item, centred on its middle.
static func make_item(item: int) -> Node3D:
	var n := Node3D.new()
	n.set_meta("item", item)
	if item == SimConfig.Item.SKULL:
		n.add_child(_make_skull())
		return n
	if item == SimConfig.Item.HEART:
		n.add_child(_make_heart())
		return n
	if item == SimConfig.Item.FIRE:
		n.add_child(_make_fire())
		return n
	if item == SimConfig.Item.EVIL:
		n.add_child(_make_mushroom())
		return n
	var tile := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.75, 0.18, 0.75)
	tile.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLORS[item]
	mat.emission_enabled = true
	mat.emission = COLORS[item] * 0.35
	tile.material_override = mat
	n.add_child(tile)
	var label := Label3D.new()
	label.text = TEXTS[item]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.outline_size = 14
	label.pixel_size = 0.009 # readable from the far, fixed camera
	label.position.y = 0.3
	label.no_depth_test = true
	n.add_child(label)
	return n

static func _make_skull() -> Node3D:
	var skull := Node3D.new()
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("eeeae0")
	var black := StandardMaterial3D.new()
	black.albedo_color = Color("111111")
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.55
	head.mesh = sphere
	head.material_override = white
	skull.add_child(head)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var e := SphereMesh.new()
		e.radius = 0.08
		e.height = 0.16
		eye.mesh = e
		eye.material_override = black
		eye.position = Vector3(0.11 * side, 0.04, 0.25) # facing +Z, the camera's side
		skull.add_child(eye)
	return skull

# A fly agaric, the poisonous toadstool: a white stem under a red dome dotted with white spots.
static func _make_mushroom() -> Node3D:
	var m := Node3D.new()
	m.name = "Mushroom"
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("f4f1e6")
	var red := StandardMaterial3D.new()
	red.albedo_color = COLORS[SimConfig.Item.EVIL]
	red.emission_enabled = true
	red.emission = COLORS[SimConfig.Item.EVIL] * 0.3
	red.roughness = 0.35
	var bottom := -0.5 * (MUSHROOM_STEM + MUSHROOM_CAP * 0.7) # centred on its middle
	var stem := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.11
	cyl.height = MUSHROOM_STEM
	stem.mesh = cyl
	stem.material_override = white
	stem.position.y = bottom + 0.5 * MUSHROOM_STEM
	m.add_child(stem)
	var cap := MeshInstance3D.new()
	cap.name = "Cap"
	var dome := SphereMesh.new()
	dome.radius = MUSHROOM_CAP
	dome.height = MUSHROOM_CAP
	dome.is_hemisphere = true
	cap.mesh = dome
	cap.material_override = red
	cap.scale.y = 0.7
	cap.position.y = bottom + MUSHROOM_STEM - 0.03
	m.add_child(cap)
	# White spots on the dome: a ring around it, one on top.
	var spots: Array[Vector2] = [Vector2(0.0, 1.0)] # (angle round, angle up from the rim)
	for i in 7:
		spots.append(Vector2(TAU * i / 7.0 + 0.3, 0.45 + 0.15 * (i % 2)))
	for s in spots:
		var spot := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.05
		ball.height = 0.04
		spot.mesh = ball
		spot.material_override = white
		var up := s.y * PI * 0.5
		var normal := Vector3(cos(s.x) * cos(up), sin(up), sin(s.x) * cos(up))
		spot.position = Vector3(normal.x * MUSHROOM_CAP, normal.y * MUSHROOM_CAP * 0.7, normal.z * MUSHROOM_CAP)
		spot.basis = Basis(Quaternion(Vector3.UP, normal.normalized()))
		cap.add_child(spot)
	return m

# A puffy heart standing up and tilted back to face the camera.
static func _make_heart() -> Node3D:
	var outline: Array[Vector2] = []
	for i in PUFFY_SIDES:
		var t := TAU * i / PUFFY_SIDES
		outline.append(Vector2(16.0 * pow(sin(t), 3.0),
				13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)))
	var heart := _puffy(outline, HEART_HEIGHT, HEART_DEPTH, COLORS[SimConfig.Item.HEART])
	heart.name = "Heart"
	heart.rotation.x = -deg_to_rad(CameraRig.PITCH_DEG)
	return heart

# A little fire, like an emoji: three puffy flames, red, orange and yellow, each smaller, lower
# and a little in front of the last, tilted back to face the camera.
static func _make_fire() -> Node3D:
	var fire := Node3D.new()
	fire.name = "Fire"
	fire.rotation.x = -deg_to_rad(CameraRig.PITCH_DEG)
	var layers := [[1.0, Color("ff3d1a")], [0.74, Color("ff9a1f")], [0.48, Color("ffe14d")]]
	for i in layers.size():
		var size: float = layers[i][0]
		var flame := _puffy(_flame_outline(), FIRE_HEIGHT * size, HEART_DEPTH * size, layers[i][1])
		flame.name = "Flame%d" % i
		# Bottoms nearly level, so the inner flames sit in the belly of the outer ones.
		flame.position = Vector3(0.0, -0.5 * FIRE_HEIGHT * (1.0 - size) * 0.9, 1.1 * HEART_DEPTH * (1.0 - size))
		fire.add_child(flame)
	return fire

# A teardrop, round at the bottom and drawn to a tip leaning a little to the right at the top.
static func _flame_outline() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in PUFFY_SIDES:
		var t := TAU * i / PUFFY_SIDES
		var y := cos(t) # 1 at the tip, -1 at the bottom
		var x := sin(t) * pow(absf(sin(t * 0.5)), 1.3) * 1.05
		out.append(Vector2(x + 0.18 * pow((y + 1.0) * 0.5, 3.0), y))
	return out

# A shape standing in the XY plane made puffy: its outline shrunk ring by ring towards the middle
# while bulging out to depth, on both faces, scaled to height and centred.
static func _puffy(outline: Array[Vector2], height: float, depth: float, color: Color) -> MeshInstance3D:
	const RINGS := 6
	var lo := Vector2.INF
	var hi := -Vector2.INF
	for v in outline:
		lo = lo.min(v)
		hi = hi.max(v)
	var centre := (lo + hi) * 0.5
	var k := height / (hi.y - lo.y)
	var n := outline.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in [1.0, -1.0]:
		var rings: Array = []
		for r in RINGS + 1:
			var a := PI * 0.5 * r / RINGS # 0 at the rim, a quarter turn at the middle
			var ring: Array[Vector3] = []
			for v in outline:
				var q := (v - centre) * k * cos(a)
				ring.append(Vector3(q.x, q.y, face * depth * sin(a)))
			rings.append(ring)
		for r in RINGS:
			for i in n:
				var j := (i + 1) % n
				var quad: Array[Vector3] = [rings[r][i], rings[r][j], rings[r + 1][j], rings[r + 1][i]]
				if face < 0.0:
					quad.reverse()
				for q in [0, 1, 2, 0, 2, 3]:
					st.add_vertex(quad[q])
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.35
	mat.roughness = 0.25
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	m.material_override = mat
	return m

# Stacked, widening grey rings: spun around, they read as a whirlwind.
static func _make_twister() -> Node3D:
	var t := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.78, 0.82, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 6:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		var r := 0.15 + 0.1 * i
		torus.inner_radius = r
		torus.outer_radius = r + 0.08
		ring.mesh = torus
		ring.material_override = mat
		ring.position = Vector3(0.05 * sin(i * 1.3), 0.25 * i + 0.1, 0.05 * cos(i * 1.3))
		t.add_child(ring)
	return t
