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

# Le Feu est un petit feu façon emoji, sans étiquette : trois flammes, rouge, orange et jaune,
# chacune plus petite et devant la précédente.
func test_the_fire_is_a_little_fire_of_three_flames() -> void:
	var n := ItemsView.make_item(SimConfig.Item.FIRE)
	var fire: Node3D = n.find_child("Fire", true, false)
	assert_true(fire != null, "un feu")
	assert_true(n.find_children("*", "Label3D", true, false).is_empty(), "pas d'étiquette")
	var flames := fire.get_children()
	assert_eq(flames.size(), 3)
	var outer: MeshInstance3D = flames[0]
	assert_almost(outer.mesh.get_aabb().size.y, ItemsView.FIRE_HEIGHT, 1e-3)
	for i in range(1, 3):
		var f: MeshInstance3D = flames[i]
		var prev: MeshInstance3D = flames[i - 1]
		assert_true(f.mesh.get_aabb().size.y < prev.mesh.get_aabb().size.y, "plus petite")
		assert_true(f.position.z > prev.position.z, "devant")
	assert_eq(outer.material_override.albedo_color, Color("ff3d1a"), "rouge dehors")
	assert_eq((flames[2] as MeshInstance3D).material_override.albedo_color, Color("ffe14d"), "jaune dedans")
	n.free()

# Le Mal est une amanite tue-mouche : un chapeau rouge à pois blancs sur un pied blanc.
func test_evil_is_a_fly_agaric() -> void:
	var n := ItemsView.make_item(SimConfig.Item.EVIL)
	var cap: MeshInstance3D = n.find_child("Cap", true, false)
	assert_true(cap != null, "un champignon")
	assert_true(n.find_children("*", "Label3D", true, false).is_empty(), "pas d'étiquette")
	assert_eq(cap.material_override.albedo_color, ItemsView.COLORS[SimConfig.Item.EVIL], "chapeau rouge")
	assert_true(cap.get_child_count() > 3, "des pois blancs")
	n.free()
