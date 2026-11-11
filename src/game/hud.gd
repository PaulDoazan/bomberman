class_name Hud
extends CanvasLayer

var _timer_label: Label
var _bar: Control # one square chip per player, in a staircase in the top left corner
var _chips: Dictionary = {} # id -> Label
var _warning: Label
var _status: Label # the local player's items and sickness
var _evil: Label # what Evil is doing to everyone
var _panel: PanelContainer
var _panel_text: Label
var _fullscreen: Button
var _ping: Label # online only, top right
var _spectator: Label # online only: joining at the next round
var _to_lobby: Button # online only, host only
var bomb_button: BombButton # touch screens only; the input controller reads touches on it
var joystick: TouchJoystick # touch screens only
var action_button: ActionButton # touch screens only: pick up / throw
var detonate_button: DetonateButton # touch screens only, while the local player has the Remote

const TOUCH_LEVEL := 1.0 / 3.0 # fraction of the screen height, from the top, of the buttons' centre
const JOYSTICK_LEVEL := 0.5 # same for the joystick: mid-height
const CHIP_SIZE := 64.0
const CHIP_GAP := 4.0

# Column and row of each of n chips, in a staircase hugging the corner: columns of k, k - 1, ...
# chips, filled one after the other, with k the fewest that fit them all (6 players: 3, 2, 1).
static func staircase(n: int) -> Array[Vector2i]:
	var k := 0
	while k * (k + 1) / 2 < n:
		k += 1
	var out: Array[Vector2i] = []
	var col := 0
	while out.size() < n:
		for row in k - col:
			if out.size() < n:
				out.append(Vector2i(col, row))
		col += 1
	return out

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Touch controls, under the rest of the HUD, like Among Us: a fixed joystick mid-height on the left,
	# and on the right the pick up / throw button above the bomb button, around a third of the way
	# down, with the detonate button left of the bomb button. The layer stops mouse events so the
	# click emulated from a touch never steers the player: on touch screens only the joystick does.
	var touch := Control.new()
	touch.set_anchors_preset(Control.PRESET_FULL_RECT)
	touch.mouse_filter = Control.MOUSE_FILTER_STOP
	touch.visible = DisplayServer.is_touchscreen_available()
	root.add_child(touch)
	joystick = TouchJoystick.new()
	joystick.custom_minimum_size = Vector2(280, 280) # grab area, larger than the drawn base
	joystick.anchor_top = JOYSTICK_LEVEL
	joystick.anchor_bottom = JOYSTICK_LEVEL
	joystick.grow_vertical = Control.GROW_DIRECTION_BOTH
	joystick.offset_left = -30 # the drawn base 20 px from the edge
	touch.add_child(joystick)
	var buttons := VBoxContainer.new()
	buttons.anchor_left = 1.0
	buttons.anchor_right = 1.0
	buttons.anchor_top = TOUCH_LEVEL
	buttons.anchor_bottom = TOUCH_LEVEL
	buttons.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	buttons.grow_vertical = Control.GROW_DIRECTION_BOTH # centred on TOUCH_LEVEL
	buttons.offset_right = -24
	buttons.add_theme_constant_override("separation", 12)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch.add_child(buttons)
	action_button = ActionButton.new()
	action_button.custom_minimum_size = Vector2(150, 150)
	action_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buttons.add_child(action_button)
	bomb_button = BombButton.new()
	bomb_button.custom_minimum_size = Vector2(190, 190)
	buttons.add_child(bomb_button)
	# Left of the bomb button, level with it: the buttons' column is 150 + 12 + 190 tall, centred on
	# TOUCH_LEVEL, so the bomb button's centre is 81 below it.
	detonate_button = DetonateButton.new()
	detonate_button.custom_minimum_size = Vector2(130, 130)
	detonate_button.anchor_left = 1.0
	detonate_button.anchor_right = 1.0
	detonate_button.anchor_top = TOUCH_LEVEL
	detonate_button.anchor_bottom = TOUCH_LEVEL
	detonate_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	detonate_button.offset_right = -24 - 190 - 12
	detonate_button.offset_top = 81 - 65
	detonate_button.visible = false
	touch.add_child(detonate_button)

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 8
	top.offset_top = 6
	top.offset_right = -8
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)

	# The timer at the top centre: the top left corner holds the players.
	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 28)
	_timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_timer_label.add_theme_constant_override("outline_size", 6)
	_timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_timer_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_timer_label.offset_top = 6
	root.add_child(_timer_label)

	# The local player's items and sickness, centred under the timer.
	_status = _outlined(20)
	_status.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.offset_top = 44
	root.add_child(_status)

	_bar = Control.new()
	_bar.position = Vector2(8.0, 8.0)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bar)

	# Phones: browsers only allow fullscreen from a tap, which the button press is.
	_fullscreen = Button.new()
	_fullscreen.focus_mode = Control.FOCUS_NONE
	_fullscreen.visible = DisplayServer.is_touchscreen_available()
	_fullscreen.pressed.connect(_on_fullscreen)
	top.add_child(_fullscreen)
	_update_fullscreen_text()
	# Leaving fullscreen with the browser's own gesture or back button updates the label too.
	get_viewport().size_changed.connect(_update_fullscreen_text)

	# Online extras: ping, back to the lobby (host), and the spectator note.
	_ping = _outlined(16)
	_ping.visible = false
	top.add_child(_ping)
	if _net() != null:
		_net().reconnecting_changed.connect(_on_reconnecting)
	_to_lobby = Button.new()
	_to_lobby.text = "Retour au salon"
	_to_lobby.focus_mode = Control.FOCUS_NONE
	_to_lobby.visible = false
	_to_lobby.pressed.connect(_on_to_lobby)
	top.add_child(_to_lobby)
	_spectator = _outlined(24)
	_spectator.text = "Tu joues à la prochaine manche"
	_spectator.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_spectator.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_spectator.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_spectator.offset_bottom = -24
	_spectator.visible = false
	root.add_child(_spectator)

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

	_evil = _outlined(34)
	_evil.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_evil.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_evil.offset_top = 150
	_evil.add_theme_color_override("font_color", Color(0.85, 0.55, 1.0))
	_evil.visible = false
	root.add_child(_evil)

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

static func _outlined(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# What p has picked up, and the sickness they have: "Feu 2 · Bombes 3 · Télécommande · …".
static func status_text(p: PlayerState) -> String:
	var parts: Array[String] = []
	if p.fire > 1:
		parts.append("Feu %d" % p.fire)
	if p.max_bombs > SimConfig.MAX_BOMBS:
		parts.append("Bombes %d" % p.max_bombs)
	if p.remote:
		parts.append("Télécommande (E)")
	if p.heart:
		parts.append("Cœur")
	if p.sick != SimConfig.Sick.NONE:
		parts.append("Malade : %s %d s" % [SimConfig.SICK_LABELS[p.sick], ceili(p.sick_timer)])
	return " · ".join(parts)

func _is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN

func _on_fullscreen() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if _is_fullscreen() else DisplayServer.WINDOW_MODE_FULLSCREEN)
	_update_fullscreen_text()

func _update_fullscreen_text() -> void:
	_fullscreen.text = "Quitter le plein écran" if _is_fullscreen() else "Plein écran"

# The autoloads are reached through the tree: scripts run by the test harness cannot name them.
func _net() -> Node:
	return get_node_or_null(^"/root/Net")

func _is_online() -> bool:
	var net := _net()
	return net != null and net.is_online()

func _local_id() -> int:
	var session := get_node_or_null(^"/root/Session")
	return session.local_id if session != null else 0

# While the connection is being remade, the ping line says so (snapshots resume after).
func _on_reconnecting(active: bool) -> void:
	if active:
		_ping.visible = true
		_ping.text = str(_net().get("RECONNECTING_TEXT"))

func _on_to_lobby() -> void:
	_net().send_action(Protocol.Msg.TO_LOBBY)

# Online: leaves the room (a clean departure, not a lost connection) and goes home.
func _on_quit() -> void:
	if _net() != null and _net().in_room():
		var net := _net()
		net.leave()
		get_tree().change_scene_to_file(net.HOME_SCENE)
		return
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
	var local_id := _local_id()
	var me: PlayerState = world.players.get(local_id, null) # the local player
	var online := _is_online()
	_sync_online(online, local_id, me)
	action_button.holding = me != null and me.held != PlayerState.Held.NONE
	detonate_button.visible = me != null and me.remote
	_status.text = status_text(me) if me != null and me.life == PlayerState.Life.ALIVE else ""
	_evil.visible = world.evil != SimConfig.Evil.NONE
	if _evil.visible:
		_evil.text = "Le Mal : %s ! %d s" % [SimConfig.EVIL_LABELS[world.evil], ceili(world.evil_timer)]
	_warning.visible = world.water_warning and match_state.phase == MatchState.Phase.PLAYING
	_panel.visible = match_state.phase == MatchState.Phase.ROUND_OVER
	if _panel.visible:
		_panel_text.text = team_scoreboard_text(match_state, _team_names()) if online and _has_teams(match_state) else player_scoreboard_text(match_state)

func _sync_online(online: bool, local_id: int, me: PlayerState) -> void:
	_ping.visible = online
	_spectator.visible = online and me == null
	_to_lobby.visible = online and int(_net().lobby.get("host", -1)) == local_id
	if online:
		_ping.text = "ping %d ms" % _net().ping_ms if _net().ping_ms >= 0 else "ping …"

# Team id -> name, from the lobby.
func _team_names() -> Dictionary:
	var names := {}
	for t: Dictionary in _net().lobby.get("teams", []):
		names[int(t["id"])] = str(t["name"])
	return names

# Square chips: name, lives (or a ghost), wins, one under the other.
func _sync_chips(m: MatchState) -> void:
	var places := staircase(m.players.size())
	for i in m.players.size():
		var mp := m.players[i]
		var chip: Label = _chips.get(mp.id)
		if chip == null:
			chip = Label.new()
			chip.add_theme_color_override("font_color", _text_color(mp.color))
			chip.add_theme_font_size_override("font_size", 14)
			chip.add_theme_constant_override("line_spacing", -2)
			chip.custom_minimum_size = Vector2(CHIP_SIZE, CHIP_SIZE)
			chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			chip.clip_text = true
			var sb := StyleBoxFlat.new()
			sb.bg_color = mp.color
			sb.set_corner_radius_all(6)
			chip.add_theme_stylebox_override("normal", sb)
			chip.position = Vector2(places[i]) * (CHIP_SIZE + CHIP_GAP)
			chip.size = Vector2(CHIP_SIZE, CHIP_SIZE)
			_bar.add_child(chip)
			_chips[mp.id] = chip
		var ps: PlayerState = m.world.players.get(mp.id)
		var status := "♥ 0"
		if ps != null:
			status = "👻" if ps.life == PlayerState.Life.GHOST else "♥ %d" % ps.lives
		chip.text = "%s\n%s\n🏆 %d" % [mp.name, status, mp.wins]

static func _text_color(c: Color) -> Color:
	return Color.BLACK if c.get_luminance() > 0.45 else Color.WHITE

static func _has_teams(m: MatchState) -> bool:
	return m.players.any(func(mp: MatchState.MatchPlayer) -> bool: return mp.team >= 0)

# The scoreboard by player: solo, and online when the only team plays each for themselves.
static func player_scoreboard_text(m: MatchState) -> String:
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
	if m.hold_next_round:
		lines.append("En attente d'un autre joueur…")
	else:
		lines.append("Manche suivante dans %d s" % maxi(ceili(m.phase_timer), 0))
	return "\n".join(lines)

# The scoreboard of an online round: teams by wins, the winning team, then what comes next.
static func team_scoreboard_text(m: MatchState, team_names: Dictionary) -> String:
	# A team deleted since (all its members quit) is not listed any more.
	var ids: Array = m.team_wins.keys().filter(func(t: int) -> bool: return team_names.has(t))
	for mp in m.players:
		if mp.team >= 0 and not ids.has(mp.team) and team_names.has(mp.team):
			ids.append(mp.team)
	ids.sort_custom(func(a: int, b: int) -> bool:
		var wa: int = m.team_wins.get(a, 0)
		var wb: int = m.team_wins.get(b, 0)
		return wa > wb if wa != wb else a < b)
	var lines: Array[String] = ["Fin de manche", ""]
	for t: int in ids:
		lines.append("%s : 🏆 %d" % [team_names.get(t, "Équipe %d" % t), m.team_wins.get(t, 0)])
	lines.append("")
	var winners: Array[String] = []
	for id in m.last_winners:
		var mp := m.player(id)
		var name: String = team_names.get(mp.team, "Équipe %d" % mp.team) if mp != null else ""
		if name != "" and not winners.has(name):
			winners.append(name)
	if winners.size() == 1:
		lines.append("Vainqueur : %s" % winners[0])
	elif winners.size() > 1:
		lines.append("Ex aequo : %s" % ", ".join(winners))
	if m.hold_next_round:
		lines.append("En attente d'une autre équipe…")
	else:
		lines.append("Manche suivante dans %d s" % maxi(ceili(m.phase_timer), 0))
	return "\n".join(lines)
