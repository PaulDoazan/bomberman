class_name ItemsView
extends Node3D

# Items lying on the ground, bobbing a little above it, and Evil's twister. Each item is a
# coloured tile with a short label; the Skull is a little skull.

const COLORS := {
	SimConfig.Item.FIRE: Color("ff5a1f"),
	SimConfig.Item.BOMB: Color("2a3550"),
	SimConfig.Item.POWER: Color("9b30d9"),
	SimConfig.Item.REMOTE: Color("1e7be0"),
	SimConfig.Item.HEART: Color("ff4f9a"),
	SimConfig.Item.EVIL: Color("3a0d4f"),
}
const TEXTS := {
	SimConfig.Item.FIRE: "FEU",
	SimConfig.Item.BOMB: "+1",
	SimConfig.Item.POWER: "PUIS",
	SimConfig.Item.REMOTE: "TÉLÉ",
	SimConfig.Item.HEART: "CŒUR",
	SimConfig.Item.EVIL: "MAL",
}
const HOVER := 0.3 # height of an item above the ground
const BOB := 0.08
const TWISTER_SPIN := 9.0 # radians per second

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
