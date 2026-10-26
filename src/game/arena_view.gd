class_name ArenaView
extends Node3D

const BASE_Y := -1.5
const COLOR_PIT := Color("6b5d50")
const COLOR_FLOOR := Color("c29a52")
const COLOR_TIER := Color("dcbd72")
const COLOR_TOP := Color("f1e3b8")
const COLOR_GOAL := Color("e58bb0")
const COLOR_PILLAR := Color("5a4020")
const COLOR_BLOCK := Color("9a6a35")

var _box := BoxMesh.new()
var _materials: Dictionary = {} # Color -> StandardMaterial3D
var _groups: Array[MultiMeshInstance3D] = []
var _blocks: Dictionary = {} # Vector2i -> MeshInstance3D
var _block_mesh := BoxMesh.new()
var _block_mat: StandardMaterial3D
var _water: MeshInstance3D
var _arena: Arena = null

func _ready() -> void:
	_box.size = Vector3.ONE
	_block_mesh.size = Vector3(0.94, 0.94, 0.94)
	_block_mat = _material(COLOR_BLOCK)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.2, 0.5, 0.85, 0.7)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plane.material = wm
	_water = MeshInstance3D.new()
	_water.mesh = plane
	_water.name = "Water"
	add_child(_water)

func _material(c: Color) -> StandardMaterial3D:
	if not _materials.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		_materials[c] = m
	return _materials[c]

func _level_color(h2v: int) -> Color:
	if h2v <= -2:
		return COLOR_PIT
	if h2v <= 1:
		return COLOR_FLOOR if h2v <= 0 else COLOR_TIER
	return COLOR_TIER if h2v <= 2 else COLOR_TOP

func _cell_color(arena: Arena, c: Vector2i) -> Color:
	if c == arena.goal:
		return COLOR_GOAL
	var h := arena.h2_at(c)
	if arena.tile_at(c) == Arena.Tile.STAIRS:
		return _level_color(h + 1)
	return _level_color(h)

func _box_xf(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> Transform3D:
	var b := Basis.from_scale(Vector3(x1 - x0, y1 - y0, z1 - z0))
	return Transform3D(b, Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5))

# Direction (in tile units) towards the higher neighbour of a stairs cell.
static func stairs_up_dir(arena: Arena, c: Vector2i) -> Vector2i:
	var best := Vector2i.ZERO
	var best_h := arena.h2_at(c)
	for d in Arena.ORTHOGONAL:
		var n := c + d
		if arena.in_bounds(n) and arena.h2_at(n) > best_h:
			best_h = arena.h2_at(n)
			best = d
	return best

# Height of the drawn surface at a point: a stairs cell has a lower step (h - 0.25) and an
# upper step (h) on the half towards its higher neighbour.
static func surface_y(arena: Arena, pt: Vector2) -> float:
	var c := Arena.cell_of(pt)
	var h := arena.h2_at(c) * 0.5
	if arena.tile_at(c) != Arena.Tile.STAIRS:
		return h
	var up := stairs_up_dir(arena, c)
	var local := pt - Vector2(c) - Vector2(0.5, 0.5)
	return h if local.dot(Vector2(up)) > 0.0 else h - 0.25

func build(arena: Arena) -> void:
	_arena = arena
	for g in _groups:
		g.queue_free()
	_groups.clear()
	for b: MeshInstance3D in _blocks.values():
		b.queue_free()
	_blocks.clear()
	var xfs: Dictionary = {} # Color -> Array[Transform3D]
	for y in arena.height:
		for x in arena.width:
			var c := Vector2i(x, y)
			var h := arena.h2_at(c) * 0.5
			var col := _cell_color(arena, c)
			if not xfs.has(col):
				xfs[col] = [] as Array[Transform3D]
			var list: Array[Transform3D] = xfs[col]
			if arena.tile_at(c) == Arena.Tile.STAIRS:
				# Two steps: a lower slab over the whole cell, and a second one over the upper half.
				list.append(_box_xf(x, x + 1, BASE_Y, h - 0.25, y, y + 1))
				var up := stairs_up_dir(arena, c)
				var x0 := x + (0.5 if up.x > 0 else 0.0)
				var x1 := x + (0.5 if up.x < 0 else 1.0)
				var z0 := y + (0.5 if up.y > 0 else 0.0)
				var z1 := y + (0.5 if up.y < 0 else 1.0)
				list.append(_box_xf(x0 if up.x != 0 else x, x1 if up.x != 0 else x + 1, h - 0.25, h, z0 if up.y != 0 else y, z1 if up.y != 0 else y + 1))
			else:
				list.append(_box_xf(x, x + 1, BASE_Y, h, y, y + 1))
			if arena.tile_at(c) == Arena.Tile.PILLAR:
				if not xfs.has(COLOR_PILLAR):
					xfs[COLOR_PILLAR] = [] as Array[Transform3D]
				var pl: Array[Transform3D] = xfs[COLOR_PILLAR]
				pl.append(_box_xf(x + 0.03, x + 0.97, h, h + 1.0, y + 0.03, y + 0.97))
	for col: Color in xfs:
		var list: Array[Transform3D] = xfs[col]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _box
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.material_override = _material(col)
		add_child(inst)
		_groups.append(inst)
	# Water: a large plane that overflows the map.
	var span := maxf(arena.width, arena.height) * 4.0
	_water.scale = Vector3(span, 1.0, span)
	_water.position = Vector3(arena.width * 0.5, water_y(SimConfig.WATER_START_H2), arena.height * 0.5)

static func water_y(h2v: int) -> float:
	return h2v * 0.5 + 0.25

# Drawn water height, derived from the sim state: it rises during the warning so that it reaches
# the next step exactly on the rise tick, and is never below the simulated water.
static func water_y_for(world: World) -> float:
	var y := water_y(world.water_h2)
	var nxt: Variant = world.next_water_h2()
	if world.water_warning and nxt != null:
		var t := clampf(1.0 - world.seconds_to_next_rise() / SimConfig.WATER_WARNING, 0.0, 1.0)
		y = lerpf(y, water_y(nxt), t)
	return y

func sync(world: World) -> void:
	var arena := world.arena
	for c: Vector2i in _blocks.keys():
		if arena.tile_at(c) != Arena.Tile.BLOCK:
			_blocks[c].queue_free()
			_blocks.erase(c)
	for y in arena.height:
		for x in arena.width:
			var c := Vector2i(x, y)
			if arena.tile_at(c) == Arena.Tile.BLOCK and not _blocks.has(c):
				var m := MeshInstance3D.new()
				m.mesh = _block_mesh
				m.material_override = _block_mat
				m.position = Vector3(x + 0.5, arena.h2_at(c) * 0.5 + 0.47, y + 0.5)
				add_child(m)
				_blocks[c] = m
	_water.position.y = water_y_for(world)
