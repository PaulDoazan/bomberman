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

# Le Café navette est une tasse de café sur sa soucoupe, avec une navette dorée fendue sur le dessus.
func test_the_cafe_navette_is_a_cup_of_coffee_with_a_navette() -> void:
	var n := ItemsView.make_item(SimConfig.Item.COFFEE)
	assert_true(n.find_child("Cup", true, false) != null, "une tasse")
	assert_true(n.find_child("Coffee", true, false) != null, "du café dedans")
	assert_true(n.find_child("Handle", true, false) != null, "une anse")
	assert_true(n.find_child("Saucer", true, false) != null, "une soucoupe")
	var navette: MeshInstance3D = n.find_child("Navette", true, false)
	assert_true(navette != null, "une navette")
	assert_true(navette.find_child("Slit", true, false) != null, "fendue")
	var size := navette.mesh.get_aabb().size
	assert_almost(size.x, ItemsView.NAVETTE_LENGTH, 1e-3, "longue")
	assert_true(size.x > 3.0 * size.z, "allongée comme un petit bateau")
	assert_eq(navette.material_override.albedo_color, ItemsView.NAVETTE_COLOR, "dorée")
	assert_true(n.find_children("*", "Label3D", true, false).is_empty(), "pas d'étiquette")
	n.free()

# La Bombe est une vraie bombe en plus petit, bleue, sans étiquette.
func test_the_bomb_item_is_a_little_blue_bomb() -> void:
	var n := ItemsView.make_item(SimConfig.Item.BOMB)
	var bomb: Node3D = n.find_child("SmallBomb", true, false)
	assert_true(bomb != null, "une petite bombe")
	assert_true(bomb.scale.x < 1.0, "plus petite qu'une vraie")
	for part in ["Body", "Cap", "Fuse", "Spark"]:
		assert_true(bomb.find_child(part, true, false) != null, part)
	var body: MeshInstance3D = bomb.find_child("Body", true, false)
	assert_almost(body.mesh.radius, SimConfig.BOMB_BODY_RADIUS, 1e-6, "même forme qu'une vraie")
	var blue: Color = body.material_override.albedo_color
	assert_true(blue.b > blue.r and blue.b > blue.g, "bleue")
	assert_true(n.find_children("*", "Label3D", true, false).is_empty(), "pas d'étiquette")
	n.free()
