extends TestCase

# Paysage : jeu et objets côte à côte ; portrait : une colonne zoomée qui remplit la largeur.
func test_layout_follows_the_screen() -> void:
	assert_eq(SettingsLayout.columns_for(Vector2(1280, 720)), 2, "ordinateur : deux colonnes")
	assert_almost(SettingsLayout.zoom_for(Vector2(1280, 720)), 1.0, 0.1, "ordinateur : sans zoom")
	assert_eq(SettingsLayout.columns_for(Vector2(2532, 1170)), 2, "téléphone en paysage : deux colonnes")
	assert_eq(SettingsLayout.columns_for(Vector2(1170, 2532)), 1, "téléphone en portrait : une colonne")
	assert_true(SettingsLayout.zoom_for(Vector2(1170, 2532)) > 2.0, "portrait : zoomé pour remplir la largeur")

func test_items_are_on_unless_turned_off() -> void:
	var cfg := SimConfig.new()
	assert_true(cfg.item_enabled(SimConfig.Item.SKULL), "activé par défaut")
	cfg.items[SimConfig.Item.SKULL] = false
	assert_false(cfg.item_enabled(SimConfig.Item.SKULL), "désactivé")
