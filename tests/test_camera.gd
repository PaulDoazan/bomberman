extends TestCase

func test_ray_plane_hits_level_height() -> void:
	var t = CameraRig.ray_plane_to_tile(Vector3(5, 10, 20), Vector3(0, -1, -1).normalized(), 1.0)
	assert_almost(t.x, 5.0); assert_almost(t.y, 11.0)

func test_ray_plane_parallel_returns_null() -> void:
	assert_eq(CameraRig.ray_plane_to_tile(Vector3(0, 5, 0), Vector3(1, 0, 0), 0.0), null)

func test_ray_plane_behind_camera_returns_null() -> void:
	assert_eq(CameraRig.ray_plane_to_tile(Vector3(0, 5, 0), Vector3(0, 1, 0), 0.0), null)
