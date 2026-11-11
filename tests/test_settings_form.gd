extends TestCase

# The settings controls shared by the solo screen and the online lobby.

func _custom() -> SimConfig:
	var cfg := SimConfig.new()
	cfg.bot_count = 5
	cfg.round_time = 90.0
	cfg.lives = 2
	cfg.map_size = "grande"
	cfg.items[SimConfig.Item.COFFEE] = false
	return cfg

func _labels(node: Node, out: Array[String] = []) -> Array[String]:
	if node is Label:
		out.append((node as Label).text)
	for child in node.get_children():
		_labels(child, out)
	return out

func _buttons(node: Node, out: Array[BaseButton] = []) -> Array[BaseButton]:
	if node is BaseButton:
		out.append(node as BaseButton)
	for child in node.get_children():
		_buttons(child, out)
	return out

func test_bots_row_only_when_asked() -> void:
	var with_bots := SettingsForm.new(SimConfig.new(), true)
	var without := SettingsForm.new(SimConfig.new(), false)
	assert_true("Bots" in _labels(with_bots), "ligne Bots présente")
	assert_false("Bots" in _labels(without), "pas de ligne Bots")
	assert_true("Chrono" in _labels(without), "le reste est là")
	with_bots.free()
	without.free()

func test_load_then_build_round_trips() -> void:
	var form := SettingsForm.new(SimConfig.new(), true)
	form.load_config(_custom())
	var cfg := form.build_config()
	assert_eq(cfg.bot_count, 5, "bots")
	assert_almost(cfg.round_time, 90.0, 0.01, "chrono")
	assert_eq(cfg.lives, 2, "vies")
	assert_eq(cfg.map_size, "grande", "taille")
	assert_false(cfg.item_enabled(SimConfig.Item.COFFEE), "malus coupé")
	assert_true(cfg.item_enabled(SimConfig.Item.FIRE), "autres actifs")
	form.free()

func test_build_keeps_the_bot_count_without_the_row() -> void:
	var form := SettingsForm.new(_custom(), false)
	assert_eq(form.build_config().bot_count, 5, "bot_count d'origine conservé")
	form.load_config(SimConfig.new())
	assert_eq(form.build_config().bot_count, SimConfig.new().bot_count, "load_config remplace la valeur gardée")
	form.free()

func test_not_editable_disables_every_button() -> void:
	var form := SettingsForm.new(SimConfig.new(), false)
	form.editable = false
	var buttons := _buttons(form)
	assert_true(buttons.size() > 0, "il y a des boutons")
	for b in buttons:
		assert_true(b.disabled, "bouton désactivé : " + b.text)
	form.editable = true
	for b in _buttons(form):
		assert_false(b.disabled, "réactivé : " + b.text)
	form.free()

func test_changes_emit_changed_but_load_does_not() -> void:
	var form := SettingsForm.new(SimConfig.new(), true)
	var count := [0]
	form.changed.connect(func() -> void: count[0] += 1)
	form.load_config(_custom())
	assert_eq(count[0], 0, "load_config sans changed")
	form.lives.get_child(2).pressed.emit() # the + button
	assert_eq(count[0], 1, "stepper")
	form.item_switches[SimConfig.Item.COFFEE].button_pressed = true
	assert_eq(count[0], 2, "interrupteur")
	form.size_buttons["petite"].button_pressed = true
	assert_eq(count[0], 3, "taille")
	form.free()
