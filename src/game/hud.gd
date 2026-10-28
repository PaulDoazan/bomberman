class_name Hud
extends CanvasLayer

var _timer_label: Label
var _bar: HBoxContainer
var _chips: Dictionary = {} # id -> Label
var _warning: Label
var _panel: PanelContainer
var _panel_text: Label
var _fullscreen: Button
var bomb_button: BombButton # touch screens only; the input controller reads touches on it
var joystick: TouchJoystick # touch screens only

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Touch controls, under the rest of the HUD, like Among Us: a fixed joystick bottom left and
	# the bomb button bottom right. The layer stops mouse events so the click emulated from a
	# touch never steers the player: on touch screens only the joystick does.
	var touch := Control.new()
	touch.set_anchors_preset(Control.PRESET_FULL_RECT)
	touch.mouse_filter = Control.MOUSE_FILTER_STOP
	touch.visible = DisplayServer.is_touchscreen_available()
	root.add_child(touch)
	joystick = TouchJoystick.new()
	joystick.custom_minimum_size = Vector2(280, 280) # grab area, larger than the drawn base
	joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	joystick.grow_vertical = Control.GROW_DIRECTION_BEGIN
	joystick.offset_left = 10
	joystick.offset_bottom = -10
	touch.add_child(joystick)
	bomb_button = BombButton.new()
	bomb_button.custom_minimum_size = Vector2(190, 190)
	bomb_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bomb_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bomb_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bomb_button.offset_right = -24
	bomb_button.offset_bottom = -24
	touch.add_child(bomb_button)

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 8
	top.offset_top = 6
	top.offset_right = -8
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)

	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 28)
	_timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_timer_label.add_theme_constant_override("outline_size", 6)
	_timer_label.custom_minimum_size = Vector2(220, 0)
	top.add_child(_timer_label)

	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 4)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_bar)

	# Phones: browsers only allow fullscreen from a tap, which the button press is.
	_fullscreen = Button.new()
	_fullscreen.focus_mode = Control.FOCUS_NONE
	_fullscreen.visible = DisplayServer.is_touchscreen_available()
	_fullscreen.pressed.connect(_on_fullscreen)
	top.add_child(_fullscreen)
	_update_fullscreen_text()
	# Leaving fullscreen with the browser's own gesture or back button updates the label too.
	get_viewport().size_changed.connect(_update_fullscreen_text)

	var quit := Button.new()
	quit.text = "Quitter"
	quit.focus_mode = Control.FOCUS_NONE # arrows and Space must never reach the button
	quit.pressed.connect(_on_quit)
	top.add_child(quit)

	_warning = Label.new()
	_warning.text = "Attention, l'eau monte !"
	_warning.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_warning.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_warning.offset_top = 90
	_warning.add_theme_font_size_override("font_size", 40)
	_warning.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	_warning.add_theme_color_override("font_outline_color", Color.BLACK)
	_warning.add_theme_constant_override("outline_size", 10)
	_warning.visible = false
	root.add_child(_warning)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.visible = false
	root.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_panel.add_child(margin)
	_panel_text = Label.new()
	_panel_text.add_theme_font_size_override("font_size", 22)
	margin.add_child(_panel_text)

func _is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN

func _on_fullscreen() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if _is_fullscreen() else DisplayServer.WINDOW_MODE_FULLSCREEN)
	_update_fullscreen_text()

func _update_fullscreen_text() -> void:
	_fullscreen.text = "Quitter le plein écran" if _is_fullscreen() else "Plein écran"

func _on_quit() -> void:
	get_tree().change_scene_to_file("res://src/ui/settings_screen.tscn")

static func format_time(t: float) -> String:
	var s := maxi(ceili(t), 0)
	return "%d:%02d" % [s / 60, s % 60]

func sync(match_state: MatchState) -> void:
	var world := match_state.world
	if world.time_left <= 0.0:
		_timer_label.text = "L'EAU MONTE !"
	else:
		_timer_label.text = format_time(world.time_left)
	_sync_chips(match_state)
	_warning.visible = world.water_warning and match_state.phase == MatchState.Phase.PLAYING
	_panel.visible = match_state.phase == MatchState.Phase.ROUND_OVER
	if _panel.visible:
		_panel_text.text = _scoreboard_text(match_state)

func _sync_chips(m: MatchState) -> void:
	var small := m.players.size() > 6
	for mp in m.players:
		var chip: Label = _chips.get(mp.id)
		if chip == null:
			chip = Label.new()
			chip.add_theme_color_override("font_color", _text_color(mp.color))
			chip.add_theme_font_size_override("font_size", 16 if small else 20)
			chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			chip.clip_text = true
			var sb := StyleBoxFlat.new()
			sb.bg_color = mp.color
			sb.set_corner_radius_all(6)
			sb.content_margin_left = 6
			sb.content_margin_right = 6
			sb.content_margin_top = 2
			sb.content_margin_bottom = 2
			chip.add_theme_stylebox_override("normal", sb)
			_bar.add_child(chip)
			_chips[mp.id] = chip
		var ps: PlayerState = m.world.players.get(mp.id)
		var status := "♥ 0"
		if ps != null:
			status = "👻" if ps.life == PlayerState.Life.GHOST else "♥ %d" % ps.lives
		chip.text = "%s %s 🏆 %d" % [mp.name, status, mp.wins] if not small else "%s %s 🏆%d" % [mp.name.replace("Bot ", "B"), status, mp.wins]

static func _text_color(c: Color) -> Color:
	return Color.BLACK if c.get_luminance() > 0.45 else Color.WHITE

func _scoreboard_text(m: MatchState) -> String:
	var sorted: Array[MatchState.MatchPlayer] = m.players.duplicate()
	sorted.sort_custom(func(a: MatchState.MatchPlayer, b: MatchState.MatchPlayer) -> bool:
		return a.wins > b.wins if a.wins != b.wins else a.id < b.id)
	var lines: Array[String] = ["Fin de manche", ""]
	for mp in sorted:
		lines.append("%s : 🏆 %d" % [mp.name, mp.wins])
	lines.append("")
	var names: Array[String] = []
	for id in m.last_winners:
		names.append(m.player(id).name)
	if names.size() == 1:
		lines.append("Vainqueur : %s" % names[0])
	elif names.size() > 1:
		lines.append("Ex aequo : %s" % ", ".join(names))
	lines.append("Manche suivante dans %d s" % maxi(ceili(m.phase_timer), 0))
	return "\n".join(lines)
