class_name SettingsForm
extends GridContainer

# The game settings as touch-friendly controls: big − / + steppers, the map sizes as buttons, a
# switch per item. Shared by the solo screen and the online lobby (where only the host edits and
# there are no bots). The two columns (the game, the items) are laid out by `columns`:
# side by side, or stacked.

signal changed # a control was touched (not emitted by load_config)

const ROW_HEIGHT := 56.0 # touch-friendly
const ACCENT := Color(0.95, 0.55, 0.15)

class Stepper:
	extends HBoxContainer
	signal stepped # a button was pressed
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
		b.pressed.connect(func() -> void:
			set_value(value + sign_v * step)
			stepped.emit())
		return b

	func set_value(v: float) -> void:
		value = clampf(v, lo, hi)
		_label.text = format.call(value)

var editable := true:
	set(v):
		editable = v
		_apply_editable(self)

var bots: Stepper # null without the bots row
var time: Stepper
var lives: Stepper
var size_buttons: Dictionary = {} # map size key -> Button (toggle, one pressed)
var item_switches: Dictionary = {} # SimConfig.Item -> CheckButton
var _bot_count: int # kept when there is no bots row
var _loading := false

func _init(cfg: SimConfig, show_bots: bool) -> void:
	_bot_count = cfg.bot_count
	add_theme_constant_override("h_separation", 32)
	add_theme_constant_override("v_separation", 12)
	columns = 2
	var cols: Array[VBoxContainer] = []
	for _i in 2:
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(SettingsLayout.COLUMN_WIDTH - 32.0, 0)
		col.add_theme_constant_override("separation", 12)
		add_child(col)
		cols.append(col)
	var box := cols[0]

	box.add_child(_heading("Partie"))
	if show_bots:
		bots = Stepper.new(1, 9, 1, cfg.bot_count, func(v: float) -> String: return str(int(v)))
		bots.stepped.connect(_emit_changed)
		box.add_child(_row("Bots", bots))
	time = Stepper.new(30, 300, 10, cfg.round_time, func(v: float) -> String: return Hud.format_time(v))
	time.stepped.connect(_emit_changed)
	box.add_child(_row("Chrono", time))
	lives = Stepper.new(1, 9, 1, cfg.lives, func(v: float) -> String: return str(int(v)))
	lives.stepped.connect(_emit_changed)
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
		b.toggled.connect(func(on: bool) -> void: # the button that gets deselected is not a change
			if on:
				_emit_changed())
		accent(b, "pressed")
		sizes.add_child(b)
		size_buttons[key] = b
	box.add_child(sizes)

	box = cols[1]
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
		sw.toggled.connect(func(_on: bool) -> void: _emit_changed())
		grid.add_child(sw)
		item_switches[item] = sw
	box.add_child(grid)

# Fills the button with the accent colour in the given state (the selected size, Jouer).
static func accent(b: Button, state: String) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = ACCENT if state != "hover" else ACCENT.lightened(0.15)
	sb.set_corner_radius_all(4)
	b.add_theme_stylebox_override(state, sb)
	for font_state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(font_state, Color.WHITE)
	if state == "pressed":
		b.add_theme_stylebox_override("hover_pressed", sb)

func _emit_changed() -> void:
	if not _loading:
		changed.emit()

func _apply_editable(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).disabled = not editable
	for child in node.get_children():
		_apply_editable(child)

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

# Shows these settings, without emitting `changed`.
func load_config(cfg: SimConfig) -> void:
	_loading = true
	_bot_count = cfg.bot_count
	if bots != null:
		bots.set_value(cfg.bot_count)
	time.set_value(cfg.round_time)
	lives.set_value(cfg.lives)
	for key: String in size_buttons:
		size_buttons[key].button_pressed = key == cfg.map_size
	for item: int in item_switches:
		item_switches[item].button_pressed = cfg.item_enabled(item)
	_loading = false

func build_config() -> SimConfig:
	var cfg := SimConfig.new()
	cfg.bot_count = int(bots.value) if bots != null else _bot_count
	cfg.round_time = time.value
	cfg.lives = int(lives.value)
	for key: String in size_buttons:
		if size_buttons[key].button_pressed:
			cfg.map_size = key
	for item: int in item_switches:
		cfg.items[item] = item_switches[item].button_pressed
	return cfg
