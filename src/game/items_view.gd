class_name ItemsView
extends Node3D

# Items lying on the ground, bobbing a little above it, and those on their way down: crates under
# a parachute, Bomb items bursting out of a dead player. Each item is a coloured tile with a short
# label; the Bomb is a little blue bomb, the Café navette a cup of coffee with a navette, the Heart a big pink heart and the Fire a little fire.

const COLORS := {
	SimConfig.Item.FIRE: Color("ff5a1f"),
	SimConfig.Item.BOMB: Color("2f7bff"), # a bright blue, apart from the dark blue of remote bombs
	SimConfig.Item.REMOTE: Color("1e7be0"),
	SimConfig.Item.HEART: Color("ff4f9a"),
}
const TEXTS := {
	SimConfig.Item.FIRE: "FEU",
	SimConfig.Item.REMOTE: "TÉLÉ",
	SimConfig.Item.HEART: "CŒUR",
}
const HOVER := 0.3 # height of an item above the ground
const CRATE_START := 9.0 # height a crate starts coming down from
const CRATE_SIZE := 0.5
const CANOPY_RADIUS := 0.55
const CANOPY_ABOVE := 0.85 # from the crate's middle to the parachute's rim
const SPILL_ARC := 1.4 # top of a spilt item's flight
const SWAY := 0.12 # radians a crate swings under its parachute
const BOB := 0.08
const HEART_HEIGHT := 0.6 # half a player
const HEART_DEPTH := 0.14 # how far each face bulges, like an emoji
const FIRE_HEIGHT := 0.6
const BOMB_ITEM_SCALE := 0.55 # the Bomb item: a real bomb, this much smaller
const CUP_HEIGHT := 0.3
const CUP_RADIUS := 0.16 # at the rim
const SAUCER_RADIUS := 0.3
const NAVETTE_LENGTH := 0.52 # the Marseille biscuit, a little boat
const NAVETTE_RADIUS := 0.075
const NAVETTE_COLOR := Color("e9c27e")
const PUFFY_SIDES := 48
const FLICKER := 0.08 # how much a fire stretches and squashes as it flickers

var _ground: Dictionary = {} # cell -> Node3D
var _drops: Dictionary = {} # Drop -> Node3D
var _time := 0.0

func reset() -> void:
	for n: Node3D in _ground.values():
		n.queue_free()
	_ground.clear()
	for n: Node3D in _drops.values():
		n.queue_free()
	_drops.clear()

func sync(world: World) -> void:
	_time += SimConfig.DT
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
	_sync_drops(world)

func _sync_drops(world: World) -> void:
	for d: Drop in _drops.keys():
		if not d in world.drops:
			_drops[d].queue_free()
			_drops.erase(d)
	for d: Drop in world.drops:
		var n: Node3D = _drops.get(d, null)
		if n == null:
			n = make_crate() if d.kind == Drop.Kind.CRATE else make_item(d.item)
			add_child(n)
			_drops[d] = n
		var t := d.progress()
		var ground := world.arena.h2_at(d.cell) * 0.5 if world.arena.in_bounds(d.cell) else 0.0
		var to := Vector3(d.cell.x + 0.5, ground, d.cell.y + 0.5)
		if d.kind == Drop.Kind.CRATE:
			var body: Node3D = n.get_node("Body")
			body.position.y = lerpf(CRATE_START, 0.5 * CRATE_SIZE, t)
			body.rotation.z = sin(_time * 2.5 + d.cell.x) * SWAY
			body.rotation.x = sin(_time * 1.9 + d.cell.y) * SWAY * 0.6
			var shadow: Node3D = n.get_node("Shadow")
			shadow.scale = Vector3.ONE * lerpf(0.4, 1.0, t) # grows as the crate nears
			n.position = to
		else:
			var from := Vector3(d.from.x, ground, d.from.y)
			n.position = from.lerp(to, t) + Vector3.UP * (HOVER + 4.0 * SPILL_ARC * t * (1.0 - t))
			n.rotation.y = t * TAU

# A new drawing of an item, centred on its middle.
static func make_item(item: int) -> Node3D:
	var n := Node3D.new()
	n.set_meta("item", item)
	if item == SimConfig.Item.BOMB:
		n.add_child(_make_small_bomb())
		return n
	if item == SimConfig.Item.COFFEE:
		n.add_child(_make_coffee())
		return n
	if item == SimConfig.Item.HEART:
		n.add_child(_make_heart())
		return n
	if item == SimConfig.Item.FIRE:
		n.add_child(_make_fire())
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

# A wooden crate hanging under a red and white parachute ("Body", the crate's middle at its
# origin), and its shadow on the ground ("Shadow") where it will land.
static func make_crate() -> Node3D:
	var n := Node3D.new()
	n.name = "Crate"
	var shadow := MeshInstance3D.new()
	shadow.name = "Shadow"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.38
	disc.bottom_radius = 0.38
	disc.height = 0.01
	shadow.mesh = disc
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0, 0, 0, 0.35)
	dark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = dark
	shadow.position.y = 0.02
	n.add_child(shadow)
	var body := Node3D.new()
	body.name = "Body"
	n.add_child(body)
	var wood := MeshInstance3D.new()
	wood.name = "Box"
	var box := BoxMesh.new()
	box.size = Vector3.ONE * CRATE_SIZE
	wood.mesh = box
	wood.material_override = _flat(Color("b07a3c"))
	body.add_child(wood)
	var plank := _flat(Color("7a4f22"))
	var h := CRATE_SIZE * 0.5
	for axis in 3: # a dark frame along its twelve edges
		for u in [-1.0, 1.0]:
			for v in [-1.0, 1.0]:
				var edge := MeshInstance3D.new()
				var bar := BoxMesh.new()
				var size := Vector3.ONE * 0.07
				size[axis] = CRATE_SIZE + 0.07
				bar.size = size
				edge.mesh = bar
				edge.material_override = plank
				var at := Vector3(u * h, v * h, 0.0) if axis == 2 else (Vector3(u * h, 0.0, v * h) if axis == 1 else Vector3(0.0, u * h, v * h))
				edge.position = at
				wood.add_child(edge)
	var canopy := MeshInstance3D.new()
	canopy.name = "Parachute"
	var dome := SphereMesh.new()
	dome.radius = CANOPY_RADIUS
	dome.height = CANOPY_RADIUS * 0.9
	dome.is_hemisphere = true
	dome.radial_segments = 8 # panels
	canopy.mesh = dome
	var cloth := _flat(Color("e8322b"))
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	canopy.material_override = cloth
	canopy.position.y = CANOPY_ABOVE
	body.add_child(canopy)
	var stripe := MeshInstance3D.new()
	var band := SphereMesh.new()
	band.radius = CANOPY_RADIUS * 1.01
	band.height = CANOPY_RADIUS * 0.9 * 1.01
	band.is_hemisphere = true
	band.radial_segments = 8
	stripe.mesh = band
	var white := _flat(Color("f4f1ea"))
	white.cull_mode = BaseMaterial3D.CULL_DISABLED
	stripe.material_override = white
	stripe.scale = Vector3(1.0, 0.45, 1.0) # a white crown on the red canopy
	stripe.position.y = CANOPY_RADIUS * 0.9 * 0.55
	canopy.add_child(stripe)
	var cord := _flat(Color("dddddd"))
	for i in 4: # cords from the crate's top corners to the canopy's rim
		var a := TAU * (i + 0.5) / 4.0
		var low := Vector3(cos(a), 0.0, sin(a)) * CRATE_SIZE * 0.7 + Vector3.UP * CRATE_SIZE * 0.5
		var high := Vector3(cos(a), 0.0, sin(a)) * CANOPY_RADIUS * 0.95 + Vector3.UP * CANOPY_ABOVE
		var line := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.01
		cyl.bottom_radius = 0.01
		cyl.height = low.distance_to(high)
		line.mesh = cyl
		line.material_override = cord
		line.position = (low + high) * 0.5
		line.basis = Basis(Quaternion(Vector3.UP, (high - low).normalized()))
		body.add_child(line)
	return n

# A real bomb, smaller and blue: round body, grey cap, fuse and its spark.
static func _make_small_bomb() -> Node3D:
	var bomb := Node3D.new()
	bomb.name = "SmallBomb"
	var r := SimConfig.BOMB_BODY_RADIUS
	var top := r + 0.04 + ActorsView.FUSE_LENGTH + 0.08 # the spark's top
	bomb.scale = Vector3.ONE * BOMB_ITEM_SCALE
	bomb.position.y = -0.5 * (top - r) * BOMB_ITEM_SCALE # centred on its middle
	var blue := StandardMaterial3D.new()
	blue.albedo_color = COLORS[SimConfig.Item.BOMB]
	blue.emission_enabled = true
	blue.emission = COLORS[SimConfig.Item.BOMB] * 0.25
	blue.roughness = 0.3
	var ball := SphereMesh.new()
	ball.radius = r
	ball.height = 2.0 * r
	_part(bomb, "Body", ball, blue, 0.0)
	var cap := CylinderMesh.new()
	cap.top_radius = 0.11
	cap.bottom_radius = 0.11
	cap.height = 0.09
	_part(bomb, "Cap", cap, _flat(Color("6b6b6b")), r + 0.01)
	var fuse := CylinderMesh.new()
	fuse.top_radius = 0.04
	fuse.bottom_radius = 0.04
	fuse.height = ActorsView.FUSE_LENGTH
	_part(bomb, "Fuse", fuse, _flat(Color("e8c48a")), r + 0.04 + ActorsView.FUSE_LENGTH * 0.5)
	var spark := SphereMesh.new()
	spark.radius = 0.08
	spark.height = 0.16
	var glow := _flat(Color("ffb02e"))
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_part(bomb, "Spark", spark, glow, r + 0.04 + ActorsView.FUSE_LENGTH)
	return bomb

static func _part(parent: Node3D, part_name: String, mesh: Mesh, mat: Material, y: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = part_name
	m.mesh = mesh
	m.material_override = mat
	m.position.y = y
	parent.add_child(m)
	return m

static func _flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat

# A café navette: a white cup of black coffee on its saucer, and a navette, the boat-shaped
# Marseille biscuit, lying across the front of the saucer, against the cup.
static func _make_coffee() -> Node3D:
	var root := Node3D.new()
	root.name = "CafeNavette"
	var china := StandardMaterial3D.new()
	china.albedo_color = Color("f6f3ec")
	china.roughness = 0.2
	var bottom := -0.5 * (CUP_HEIGHT + 0.03) # centred on its middle
	var saucer := MeshInstance3D.new()
	saucer.name = "Saucer"
	var plate := CylinderMesh.new()
	plate.top_radius = SAUCER_RADIUS
	plate.bottom_radius = SAUCER_RADIUS * 0.75
	plate.height = 0.03
	saucer.mesh = plate
	saucer.material_override = china
	saucer.position.y = bottom + 0.015
	root.add_child(saucer)
	var cup := MeshInstance3D.new()
	cup.name = "Cup"
	var body := CylinderMesh.new()
	body.top_radius = CUP_RADIUS
	body.bottom_radius = CUP_RADIUS * 0.72
	body.height = CUP_HEIGHT
	cup.mesh = body
	cup.material_override = china
	cup.position = Vector3(0.0, bottom + 0.03 + 0.5 * CUP_HEIGHT, -0.06)
	root.add_child(cup)
	var coffee := MeshInstance3D.new()
	coffee.name = "Coffee"
	var surface := CylinderMesh.new()
	surface.top_radius = CUP_RADIUS * 0.85 # a white rim shows around it
	surface.bottom_radius = CUP_RADIUS * 0.85
	surface.height = 0.006
	coffee.mesh = surface
	var brown := StandardMaterial3D.new()
	brown.albedo_color = Color("3a2114")
	brown.roughness = 0.1
	coffee.material_override = brown
	coffee.position.y = 0.5 * CUP_HEIGHT + 0.003
	cup.add_child(coffee)
	var handle := MeshInstance3D.new()
	handle.name = "Handle"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.045
	ring.outer_radius = 0.075
	handle.mesh = ring
	handle.material_override = china
	handle.rotation.x = PI * 0.5 # standing up, facing the camera
	handle.position = Vector3(CUP_RADIUS * 0.95, 0.02, 0.0)
	cup.add_child(handle)
	var navette := _make_navette()
	navette.position = Vector3(0.0, bottom + 0.03 + NAVETTE_RADIUS * 0.85, CUP_RADIUS + NAVETTE_RADIUS - 0.04)
	navette.rotation.y = deg_to_rad(-12.0)
	root.add_child(navette)
	return root

# A navette lying along X: a golden stick narrowing to rounded ends, a little flattened,
# with the long slit of a darker crust open along its top.
static func _make_navette() -> Node3D:
	var gold := StandardMaterial3D.new()
	gold.albedo_color = NAVETTE_COLOR
	gold.roughness = 0.7
	var navette := MeshInstance3D.new()
	navette.name = "Navette"
	navette.mesh = _spindle(NAVETTE_LENGTH, NAVETTE_RADIUS, 0.8, 0.3)
	navette.material_override = gold
	var crust := StandardMaterial3D.new()
	crust.albedo_color = Color("c98a3c")
	crust.roughness = 0.8
	var slit := MeshInstance3D.new()
	slit.name = "Slit"
	slit.mesh = _spindle(NAVETTE_LENGTH * 0.66, NAVETTE_RADIUS * 0.45, 0.35, 0.8) # pointed, like an eye
	slit.material_override = crust
	slit.position.y = NAVETTE_RADIUS * 0.8 * 0.9 # sunk a little into the top
	navette.add_child(slit)
	return navette

# A solid of revolution along X, length long and radius wide at its middle, narrowing to rounded
# ends (pointier as sharp grows); flat squashes its height.
static func _spindle(length: float, radius: float, flat: float, sharp: float) -> ArrayMesh:
	const ALONG := 40
	const AROUND := 16
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for i in ALONG + 1:
		var t := float(i) / ALONG
		var r := radius * pow(sin(PI * t), sharp)
		var ring: Array[Vector3] = []
		for j in AROUND:
			var a := TAU * j / AROUND
			ring.append(Vector3((t - 0.5) * length, sin(a) * r * flat, cos(a) * r))
		rings.append(ring)
	for i in ALONG:
		for j in AROUND:
			var k := (j + 1) % AROUND
			var quad: Array[Vector3] = [rings[i][j], rings[i + 1][j], rings[i + 1][k], rings[i][k]]
			for q in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(quad[q])
	st.generate_normals()
	return st.commit()

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
