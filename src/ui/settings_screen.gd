class_name SettingsScreen
extends Control

# Game setup, built for touch as much as for the mouse: big − / + steppers, the map sizes as
# buttons, a switch per item. A landscape screen shows the game and the items side by side; a
# portrait one stacks them in a column that scrolls, the whole page zoomed so it fills the width.
# The zoom is undone when the game starts.

const ROW_HEIGHT := 56.0 # touch-friendly
const ACCENT := Color(0.95, 0.55, 0.15)

class Stepper:
	extends HBoxContainer
	var value: float
	var lo: float
	var hi: float
	var step: float
	var format: Callable
	var _label: Label

	func _init(p_lo: float, p_hi: float, p_step: float, p_value: float, p_format: Callable) -> void:
		lo = p_lo
		hi = p_hi
		step = p_step
		format = p_format
		add_theme_constant_override("separation", 6)
		add_child(_button("−", -1.0))
		_label = Label.new()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.custom_minimum_size = Vector2(90, 0)
		_label.add_theme_font_size_override("font_size", 24)
		add_child(_label)
		add_child(_button("+", 1.0))
		set_value(p_value)

	func _button(text: String, sign_v: float) -> Button:
		var b := Button.new()
		b.text = text
		b.custom_minimum_size = Vector2(ROW_HEIGHT, ROW_HEIGHT)
		b.add_theme_font_size_override("font_size", 28)
		b.pressed.connect(func() -> void: set_value(value + sign_v * step))
		return b

	func set_value(v: float) -> void:
		value = clampf(v, lo, hi)
		_label.text = format.call(value)

var bots: Stepper
var time: Stepper
var lives: Stepper
var size_buttons: Dictionary = {} # map size key -> Button (toggle, one pressed)
var item_switches: Dictionary = {} # SimConfig.Item -> CheckButton
var play_button: Button
var _sections: GridContainer # the game and the items: side by side, or stacked
var _columns: Array[VBoxContainer] = []

func _ready() -> void:
	theme = Theme.new()
	theme.default_font_size = 22
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.16, 0.24)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	center.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)

	var title := Label.new()
	title.text = "Bomberman"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	page.add_child(title)
	_sections = GridContainer.new()
	_sections.add_theme_constant_override("h_separation", 32)
	_sections.add_theme_constant_override("v_separation", 12)
	page.add_child(_sections)
	for _i in 2:
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(SettingsLayout.COLUMN_WIDTH - 32.0, 0)
		col.add_theme_constant_override("separation", 12)
		_sections.add_child(col)
		_columns.append(col)
	var box := _columns[0]

	var cfg := Session.config
	box.add_child(_heading("Partie"))
	bots = Stepper.new(1, 9, 1, cfg.bot_count, func(v: float) -> String: return str(int(v)))
	box.add_child(_row("Bots", bots))
	time = Stepper.new(30, 300, 10, cfg.round_time, func(v: float) -> String: return Hud.format_time(v))
	box.add_child(_row("Chrono", time))
	lives = Stepper.new(1, 9, 1, cfg.lives, func(v: float) -> String: return str(int(v)))
	box.add_child(_row("Vies", lives))

	var size_label := Label.new()
	size_label.text = "Taille de la map"
	box.add_child(size_label)
	var sizes := HFlowContainer.new()
	sizes.add_theme_constant_override("h_separation", 6)
	sizes.add_theme_constant_override("v_separation", 6)
	var group := ButtonGroup.new()
	for key: String in SimConfig.MAP_SIZE_LABELS:
		var b := Button.new()
		b.text = SimConfig.MAP_SIZE_LABELS[key]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = key == cfg.map_size
		b.custom_minimum_size = Vector2(130, ROW_HEIGHT)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_accent(b, "pressed")
		sizes.add_child(b)
		size_buttons[key] = b
	box.add_child(sizes)

	box = _columns[1]
	box.add_child(_heading("Bonus et malus"))
	var all := HBoxContainer.new()
	all.add_theme_constant_override("separation", 6)
	all.add_child(_wide_button("Tout activer", func() -> void: _set_all_items(true)))
	all.add_child(_wide_button("Tout désactiver", func() -> void: _set_all_items(false)))
	box.add_child(all)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	for item: int in SimConfig.ITEM_LABELS:
		var sw := CheckButton.new()
		sw.text = SimConfig.ITEM_LABELS[item]
		sw.button_pressed = cfg.item_enabled(item)
		sw.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		sw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(sw)
		item_switches[item] = sw
	box.add_child(grid)

	play_button = Button.new()
	play_button.text = "Jouer"
	play_button.custom_minimum_size = Vector2(0, 64)
	play_button.add_theme_font_size_override("font_size", 28)
	play_button.pressed.connect(_on_play)
	for state in ["normal", "hover", "pressed"]:
		_accent(play_button, state)
	page.add_child(play_button)

	get_viewport().size_changed.connect(_fit)
	_fit()

func _exit_tree() -> void:
	get_viewport().size_changed.disconnect(_fit) # or unzooming would zoom again
	get_tree().root.content_scale_factor = 1.0 # the game lays itself out unzoomed

# Zooms the page so the column fills a narrow screen; wide screens stay at 1.
func _fit() -> void:
	var window := Vector2(DisplayServer.window_get_size())
	_sections.columns = SettingsLayout.columns_for(window)
	get_tree().root.content_scale_factor = SettingsLayout.zoom_for(window)

# Fills the button with the accent colour in the given state (the selected size, Jouer).
static func _accent(b: Button, state: String) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = ACCENT if state != "hover" else ACCENT.lightened(0.15)
	sb.set_corner_radius_all(4)
	b.add_theme_stylebox_override(state, sb)
	for font_state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(font_state, Color.WHITE)
	if state == "pressed":
		b.add_theme_stylebox_override("hover_pressed", sb)

func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	return l

func _row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	var l := Label.new()
	l.text = label_text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(control)
	return row

func _wide_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on_press)
	return b

func _set_all_items(on: bool) -> void:
	for sw: CheckButton in item_switches.values():
		sw.button_pressed = on

func build_config() -> SimConfig:
	var cfg := SimConfig.new()
	cfg.bot_count = int(bots.value)
	cfg.round_time = time.value
	cfg.lives = int(lives.value)
	for key: String in size_buttons:
		if size_buttons[key].button_pressed:
			cfg.map_size = key
	for item: int in item_switches:
		cfg.items[item] = item_switches[item].button_pressed
	return cfg

func _on_play() -> void:
	Session.config = build_config()
	get_tree().change_scene_to_file("res://src/game/game.tscn")
