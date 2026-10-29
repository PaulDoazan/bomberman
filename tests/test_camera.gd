extends TestCase

func test_ray_plane_hits_level_height() -> void:
	var t = CameraRig.ray_plane_to_tile(Vector3(5, 10, 20), Vector3(0, -1, -1).normalized(), 1.0)
	assert_almost(t.x, 5.0); assert_almost(t.y, 11.0)

func test_ray_plane_parallel_returns_null() -> void:
	assert_eq(CameraRig.ray_plane_to_tile(Vector3(0, 5, 0), Vector3(1, 0, 0), 0.0), null)

func test_ray_plane_behind_camera_returns_null() -> void:
	assert_eq(CameraRig.ray_plane_to_tile(Vector3(0, 5, 0), Vector3(0, 1, 0), 0.0), null)

# La map est cadrée centrée, aussi grande que possible, avec la même marge en haut et en bas :
# toute la hauteur sur un écran allongé, sinon c'est la largeur qui limite et elle reste centrée.
func _seen(w: int, h: int, aspect: float) -> Array[Rect2]:
	var box := CameraRig.target_box(aspect)
	var tan_v := tan(deg_to_rad(CameraRig.FOV) * 0.5)
	var seen := CameraRig._screen_bounds(CameraRig.fit(w, h, aspect, box), CameraRig._corners(w, h), tan_v * aspect, tan_v)
	return [box, seen]

func test_arena_fills_the_height_centred() -> void:
	var r := _seen(23, 15, 19.5 / 9.0)
	assert_almost(r[1].position.y, -1.0 + CameraRig.EDGE, 1e-4, "marge du bas")
	assert_almost(r[1].end.y, 1.0 - CameraRig.EDGE, 1e-4, "même marge en haut")
	assert_almost(r[1].get_center().x, 0.0, 1e-4, "centrée")
	assert_true(r[1].position.x >= r[0].position.x - 1e-4, "dans l'écran")

func test_narrower_screen_limits_by_width_and_centres() -> void:
	var r := _seen(23, 15, 16.0 / 9.0)
	assert_almost(r[1].size.x, r[0].size.x, 1e-4, "la largeur limite")
	assert_almost(r[1].get_center().x, 0.0, 1e-4, "centrée en largeur")
	assert_almost(r[1].get_center().y, 0.0, 1e-4, "centrée en hauteur")
	assert_true(r[1].size.y <= r[0].size.y + 1e-4, "tient en hauteur")

# Les carrés des joueurs font un escalier dans l'angle : 6 joueurs, colonnes de 3, 2 puis 1.
func test_player_squares_make_a_staircase() -> void:
	assert_eq(Hud.staircase(6), [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 0)] as Array[Vector2i])
	assert_eq(Hud.staircase(4), [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 0)] as Array[Vector2i], "4 : 3 puis 1")
	var ten := Hud.staircase(10)
	assert_eq(ten.size(), 10)
	assert_eq(ten[9], Vector2i(3, 0), "10 : 4, 3, 2, 1")
	assert_eq(Hud.staircase(1), [Vector2i(0, 0)] as Array[Vector2i])
