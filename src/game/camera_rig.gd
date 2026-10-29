class_name CameraRig
extends Node3D

const PITCH_DEG := 55.0
const FOV := 40.0
const BASE_Y := -1.5
const TOP_Y := 2.0 # top of the summit (h2 4), at the back
const FRONT_Y := 0.0 # front edge: the ground (blocks and players there poke into the margin)
# Margin left around the arena, in normalised screen units (2 = the screen height): the same at
# the top and the bottom, about 21 px on a 720 px tall screen.
const EDGE := 0.058

@onready var camera: Camera3D = $Camera3D

var arena_ref: Arena = null # last framed arena
var side_inset := 0.0 # screen width, in canvas pixels, kept clear on each side (the HUD column)

func _ready() -> void:
	get_viewport().size_changed.connect(_on_size_changed)

func _on_size_changed() -> void:
	if arena_ref != null:
		frame(arena_ref)

# Fixed tilted camera looking from the +z side towards -z, framing the whole arena centred on
# screen, as large as fits between the side insets, with EDGE margins.
func frame(arena: Arena) -> void:
	arena_ref = arena
	var s := get_viewport().get_visible_rect().size
	var aspect := s.x / s.y if s.y > 0.0 else 16.0 / 9.0
	var side := 2.0 * side_inset / s.x if s.x > 0.0 else 0.0
	camera.fov = FOV
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.global_transform = fit(arena.width, arena.height, aspect, target_box(aspect, side))

# Where the arena goes on screen, in normalised coordinates (x right, y up, both in [-1, 1]):
# centred, side clear on both sides, inside EDGE margins as many pixels wide on every side.
static func target_box(aspect: float, side: float) -> Rect2:
	var x := 1.0 - side - EDGE / aspect
	return Rect2(-x, -1.0 + EDGE, 2.0 * x, 2.0 - 2.0 * EDGE)

# The camera transform (fixed pitch) whose view of the arena, from its floor's lowest point to its
# top, fills box as much as fits: it touches both ends of box on one axis, centred on the other.
static func fit(width: float, height: float, aspect: float, box: Rect2) -> Transform3D:
	var pitch := deg_to_rad(PITCH_DEG)
	var look := Vector3(width * 0.5, 0.0, height * 0.5)
	var back := Vector3(0.0, sin(pitch), cos(pitch))
	var basis := Transform3D(Basis.IDENTITY, back).looking_at(Vector3.ZERO, Vector3.UP).basis
	var tan_v := tan(deg_to_rad(FOV) * 0.5)
	var tan_h := tan_v * aspect
	var corners := _corners(width, height)
	var dist := 3.0 * maxf(width, height) # start far enough to see everything
	var pos := look + back * dist
	for i in 100:
		var bounds := _screen_bounds(Transform3D(basis, pos), corners, tan_h, tan_v)
		var scale := maxf(bounds.size.x / box.size.x, bounds.size.y / box.size.y)
		var shift := bounds.get_center() - box.get_center()
		# Slide sideways to centre the view on box, then move along the view to scale it.
		pos += basis.x * shift.x * tan_h * dist + basis.y * shift.y * tan_v * dist
		pos += basis.z * dist * (scale - 1.0)
		dist *= scale
		if absf(scale - 1.0) < 1e-6 and shift.length() < 1e-6:
			break
	return Transform3D(basis, pos)

static func _corners(width: float, height: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for x in [0.0, width]:
		for z in [0.0, height]:
			# Only the temple, at the back, rises to TOP_Y.
			for y in [BASE_Y, TOP_Y if z == 0.0 else FRONT_Y]:
				out.append(Vector3(x, y, z))
	return out

# Normalised screen rectangle covered by points seen from xf.
static func _screen_bounds(xf: Transform3D, points: Array[Vector3], tan_h: float, tan_v: float) -> Rect2:
	var inv := xf.affine_inverse()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in points:
		var v := inv * c
		var q := Vector2(v.x / -v.z / tan_h, v.y / -v.z / tan_v)
		lo = lo.min(q)
		hi = hi.max(q)
	return Rect2(lo, hi - lo)

# Intersection of a ray with the horizontal plane y = plane_y, as Vector2(x, z); null when
# the ray is parallel to the plane or the plane is behind the origin.
static func ray_plane_to_tile(origin: Vector3, dir: Vector3, plane_y: float) -> Variant:
	if absf(dir.y) < 1e-4:
		return null
	var t := (plane_y - origin.y) / dir.y
	if t < 0.0:
		return null
	var p := origin + dir * t
	return Vector2(p.x, p.z)

func mouse_to_tile(screen_pos: Vector2, plane_h2: int) -> Variant:
	return ray_plane_to_tile(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos), plane_h2 * 0.5)
