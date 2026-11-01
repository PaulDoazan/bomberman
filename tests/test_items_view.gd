extends TestCase

# Le Cœur est un gros cœur rose, sans étiquette, haut comme la moitié d'un perso.
func test_the_heart_is_a_big_pink_heart_half_a_player_tall() -> void:
	var n := ItemsView.make_item(SimConfig.Item.HEART)
	var heart: MeshInstance3D = n.find_child("Heart", true, false)
	assert_true(heart != null, "un cœur")
	assert_true(n.find_children("*", "Label3D", true, false).is_empty(), "pas d'étiquette")
	assert_almost(heart.mesh.get_aabb().size.y, ActorsView.MODEL_SCALE * 1.75 * 0.5, 1e-3, "moitié d'un perso")
	assert_eq(heart.material_override.albedo_color, ItemsView.COLORS[SimConfig.Item.HEART], "rose")
	n.free()
