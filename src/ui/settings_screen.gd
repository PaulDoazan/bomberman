class_name SettingsScreen
extends Control

var bots_spin: SpinBox
var size_option: OptionButton
var time_spin: SpinBox
var lives_spin: SpinBox
var play_button: Button

var _size_keys: Array[String] = []

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.16, 0.24)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = "Bomberman"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	box.add_child(title)

	var cfg := Session.config
	bots_spin = _spin(1, 9, 1, cfg.bot_count)
	box.add_child(_row("Bots", bots_spin))

	size_option = OptionButton.new()
	var i := 0
	for key: String in SimConfig.MAP_SIZE_LABELS:
		size_option.add_item(SimConfig.MAP_SIZE_LABELS[key])
		_size_keys.append(key)
		if key == cfg.map_size:
			size_option.select(i)
		i += 1
	box.add_child(_row("Taille de la map", size_option))

	time_spin = _spin(30, 300, 10, cfg.round_time)
	box.add_child(_row("Chrono (s)", time_spin))

	lives_spin = _spin(1, 9, 1, cfg.lives)
	box.add_child(_row("Vies", lives_spin))

	play_button = Button.new()
	play_button.text = "Jouer"
	play_button.custom_minimum_size = Vector2(0, 52)
	play_button.add_theme_font_size_override("font_size", 24)
	play_button.pressed.connect(_on_play)
	box.add_child(play_button)

func _spin(lo: float, hi: float, step: float, value: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(200, 0)
	return s

func _row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	control.custom_minimum_size.x = 200
	row.add_child(control)
	return row

func build_config() -> SimConfig:
	var cfg := SimConfig.new()
	cfg.bot_count = int(bots_spin.value)
	cfg.map_size = _size_keys[size_option.selected]
	cfg.round_time = time_spin.value
	cfg.lives = int(lives_spin.value)
	return cfg

func _on_play() -> void:
	Session.config = build_config()
	get_tree().change_scene_to_file("res://src/game/game.tscn")
