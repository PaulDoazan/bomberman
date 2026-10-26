class_name CameraRig
extends Node3D

const PITCH_DEG := 55.0
const FOV := 40.0
const BASE_Y := -1.5
const TOP_Y := 2.5
const MARGIN := 0.95

@onready var camera: Camera3D = $Camera3D

var arena_ref: Arena = null # last framed arena

func _ready() -> void:
	get_viewport().size_changed.connect(_on_size_changed)

func _on_size_changed() -> void:
	if arena_ref != null:
		frame(arena_ref)

func _aspect() -> float:
	var s := get_viewport().get_visible_rect().size
	return s.x / s.y if s.y > 0.0 else 16.0 / 9.0

# Fixed tilted camera looking from the +z side towards -z, far enough to fit the whole arena.
func frame(arena: Arena) -> void:
	arena_ref = arena
	var pitch := deg_to_rad(PITCH_DEG)
	var look := Vector3(arena.width * 0.5, 0.0, arena.height * 0.5)
	var back := Vector3(0.0, sin(pitch), cos(pitch))
	var aspect := _aspect()
	var tan_v := tan(deg_to_rad(FOV) * 0.5) * MARGIN
	var tan_h := tan_v * aspect
	var corners: Array[Vector3] = []
	for x in [0.0, float(arena.width)]:
		for z in [0.0, float(arena.height)]:
			for y in [BASE_Y, TOP_Y]:
				corners.append(Vector3(x, y, z))
	var xf := Transform3D.IDENTITY
	var dist := 5.0
	for i in 400:
		xf = Transform3D(Basis.IDENTITY, look + back * dist).looking_at(look, Vector3.UP)
		var inv := xf.affine_inverse()
		var ok := true
		for c in corners:
			var v := inv * c
			if v.z >= -0.1 or absf(v.x / -v.z) > tan_h or absf(v.y / -v.z) > tan_v:
				ok = false
				break
		if ok:
			break
		dist += 0.5
	camera.fov = FOV
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.global_transform = xf

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
