class_name LobbyScreen
extends Control

# The online lobby (mockup A): the room code and how to share it, one card per team, the
# settings (editable by the host only) and the host's Lancer button. While a match runs, it is
# where a newcomer picks a team ("Partie en cours"), without Lancer and with settings read-only.
# Laid out like the home screen: one column, zoomed to fill a phone held in portrait.
# `show_state` is fed by Net.lobby_changed and needs no Net, so tests drive it directly.

const HOME_SCENE := "res://src/ui/home_screen.tscn"
const MAX_PLAYERS := 12
const MAX_TEAMS := 4
const TEAM_NAME_MAX := 16
const MSG := Protocol.Msg
const BG := Color(0.12, 0.16, 0.24)
const CARD_BG := Color(0.17, 0.22, 0.32)
const PLAYING_TEXT := "Partie en cours : choisis ou crée une équipe pour jouer à la manche suivante"

var host_label: Label
var playing_label: Label # "Partie en cours…": shown to a newcomer while a match runs
var code_label: Label
var copy_button: Button
var share_button: Button
var team_cards: VBoxContainer
var join_buttons: Array[Button] = []
var chips: Array[Label] = []
var create_toggle: Button
var create_row: HBoxContainer
var name_edit: LineEdit
var create_button: Button
var no_team_label: Label
var form: SettingsForm
var start_button: Button
var leave_button: Button
var status_label: Label
var send_fn: Callable # (type, body): Net.send_action once in the tree; tests inject a recorder
var _net: Node # the Net autoload, looked up in the tree (not a global for scripts run with -s)
var _pending_sent: Array = [] # settings sent and not echoed yet, as encode_config dictionaries

func _ready() -> void:
	build()
	_net = get_node_or_null(^"/root/Net")
	if _net != null:
		if not send_fn.is_valid():
			send_fn = Callable(_net, "send_action")
		_net.connect("lobby_changed", _on_lobby_changed)
		_net.connect("error_received", show_error)
		_net.connect("reconnecting_changed", _on_reconnecting)
		_on_lobby_changed()
		_on_reconnecting(_net.call("is_reconnecting"))
	get_viewport().size_changed.connect(_fit)
	_fit()

# Creates the controls (no tree needed, so tests can look at them).
func build() -> void:
	theme = Theme.new()
	theme.default_font_size = 22
	var bg := ColorRect.new()
	bg.color = BG
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
	page.custom_minimum_size = Vector2(SettingsLayout.COLUMN_WIDTH - 32, 0)
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)

	host_label = Label.new()
	host_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	host_label.add_theme_font_size_override("font_size", 28)
	page.add_child(host_label)

	code_label = Label.new()
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_label.add_theme_font_size_override("font_size", 72)
	code_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	page.add_child(code_label)

	var share_row := HBoxContainer.new()
	share_row.add_theme_constant_override("separation", 8)
	copy_button = _button("Copier le lien")
	copy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_button.pressed.connect(_on_copy)
	share_row.add_child(copy_button)
	share_button = _button("Partager")
	share_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share_button.pressed.connect(_on_share)
	share_row.add_child(share_button)
	page.add_child(share_row)

	playing_label = Label.new()
	playing_label.text = PLAYING_TEXT
	playing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	playing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	playing_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	playing_label.visible = false
	page.add_child(playing_label)

	team_cards = VBoxContainer.new()
	team_cards.add_theme_constant_override("separation", 10)
	page.add_child(team_cards)

	create_toggle = _button("+ Créer une équipe")
	create_toggle.pressed.connect(func() -> void:
		create_row.visible = not create_row.visible
		if create_row.visible and is_inside_tree():
			name_edit.grab_focus())
	page.add_child(create_toggle)

	create_row = HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 8)
	create_row.visible = false
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Nom de l'équipe"
	name_edit.max_length = TEAM_NAME_MAX
	name_edit.custom_minimum_size = Vector2(0, SettingsForm.ROW_HEIGHT)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(func(_t: String) -> void: _on_create_team())
	create_row.add_child(name_edit)
	create_button = _button("Créer et rejoindre")
	create_button.pressed.connect(_on_create_team)
	create_row.add_child(create_button)
	page.add_child(create_row)

	no_team_label = Label.new()
	no_team_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(no_team_label)

	form = SettingsForm.new(SimConfig.new(), false)
	form.changed.connect(_on_form_changed)
	page.add_child(form)

	start_button = _button("Lancer")
	start_button.custom_minimum_size = Vector2(0, 64)
	start_button.add_theme_font_size_override("font_size", 28)
	for state in ["normal", "hover", "pressed"]:
		SettingsForm.accent(start_button, state)
	start_button.pressed.connect(func() -> void: _send(MSG.START))
	page.add_child(start_button)

	leave_button = _button("Quitter")
	leave_button.pressed.connect(_on_leave)
	page.add_child(leave_button)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(status_label)

func _exit_tree() -> void:
	get_viewport().size_changed.disconnect(_fit) # or unzooming would zoom again
	get_tree().root.content_scale_factor = 1.0 # the next screen lays itself out unzoomed

# Redraws the lobby from a LOBBY message, seen by player my_id.
func show_state(state: Dictionary, my_id: int) -> void:
	var is_host := int(state.get("host", -1)) == my_id
	var players: Array = state.get("players", [])
	var teams: Array = state.get("teams", [])
	var by_id := {}
	var my_team := -1
	for p: Dictionary in players:
		by_id[int(p["id"])] = p
		if int(p["id"]) == my_id:
			my_team = int(p["team"])

	var host_name := str((by_id.get(int(state.get("host", -1)), {}) as Dictionary).get("name", ""))
	host_label.text = "Partie de %s" % host_name
	code_label.text = str(state.get("code", ""))

	_clear_cards()
	var loners: Array[String] = []
	for p: Dictionary in players:
		if int(p["team"]) == -1:
			loners.append(_display_name(p, int(state.get("host", -1))))
	for t: Dictionary in teams:
		team_cards.add_child(_team_card(t, players, my_team, int(state.get("host", -1))))
	no_team_label.text = "Sans équipe : " + (", ".join(loners) if not loners.is_empty() else "personne")

	var full := teams.size() >= MAX_TEAMS
	create_toggle.visible = not full
	if full:
		create_row.visible = false

	# The form follows the host's settings, except that echoes of this player's own older edits
	# (still in flight) must not undo the newer ones.
	var received: Dictionary = state.get("config", {})
	var echoed := _pending_index(received)
	if echoed >= 0:
		_pending_sent = _pending_sent.slice(echoed + 1)
	elif not _pending_sent.is_empty():
		_pending_sent.clear() # someone else's change, or the server clamped ours
	if _pending_sent.is_empty() and received != SimCodec.encode_config(form.build_config()):
		form.load_config(SimCodec.decode_config(received))
	# While a match runs (a newcomer is here to pick a team), nobody changes settings or starts.
	var playing: bool = state.get("phase") == "playing"
	playing_label.visible = playing
	form.editable = is_host and not playing

	start_button.visible = is_host and not playing
	start_button.text = "Lancer · %d/%d" % [players.size(), MAX_PLAYERS]
	start_button.disabled = not bool(state.get("can_start", false))

# Position of the pending edit with these settings, or -1 (compared by value).
func _pending_index(cfg: Dictionary) -> int:
	for i in _pending_sent.size():
		if (_pending_sent[i] as Dictionary) == cfg:
			return i
	return -1

func show_error(code: String) -> void:
	status_label.text = str(Protocol.ERROR_LABELS.get(code, code))

func _display_name(p: Dictionary, host_id: int) -> String:
	return ("★ " if int(p["id"]) == host_id else "") + str(p["name"])

func _clear_cards() -> void:
	for card in team_cards.get_children():
		team_cards.remove_child(card)
		card.queue_free()
	join_buttons.clear()
	chips.clear()

func _team_card(t: Dictionary, players: Array, my_team: int, host_id: int) -> PanelContainer:
	var color: Color = TeamColors.BASES[int(t["color_index"]) % TeamColors.BASES.size()]
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = color
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)

	var members: Array = players.filter(func(p: Dictionary) -> bool: return int(p["team"]) == int(t["id"]))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "%s · %d" % [t["name"], members.size()]
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", color)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	head.add_child(title)
	if int(t["id"]) != my_team:
		var join := _button("Rejoindre")
		join.custom_minimum_size = Vector2(150, SettingsForm.ROW_HEIGHT)
		join.pressed.connect(func() -> void: _send(MSG.JOIN_TEAM, {"team": int(t["id"])}))
		head.add_child(join)
		join_buttons.append(join)
	box.add_child(head)

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for p: Dictionary in members:
		var chip := _chip(p, host_id)
		flow.add_child(chip)
		chips.append(chip)
	box.add_child(flow)
	return card

func _chip(p: Dictionary, host_id: int) -> Label:
	var color: Color = p["color"]
	var chip := Label.new()
	chip.text = _display_name(p, host_id)
	chip.add_theme_color_override("font_color", Color.BLACK if color.get_luminance() > 0.5 else Color.WHITE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	chip.add_theme_stylebox_override("normal", sb)
	if not bool(p["connected"]):
		chip.modulate.a = 0.4
	return chip

func _send(type: int, body: Variant = {}) -> void:
	if send_fn.is_valid():
		send_fn.call(type, body)

func _on_lobby_changed() -> void:
	var lobby: Dictionary = _net.get("lobby")
	if not lobby.is_empty():
		show_state(lobby, int(_net.get("my_id")))

func _on_reconnecting(active: bool) -> void:
	if active:
		status_label.text = str(_net.get("RECONNECTING_TEXT"))
	elif status_label.text == str(_net.get("RECONNECTING_TEXT")):
		status_label.text = ""

func _on_form_changed() -> void:
	var cfg := SimCodec.encode_config(form.build_config())
	_pending_sent.append(cfg)
	_send(MSG.SETTINGS, {"config": cfg})

func _on_create_team() -> void:
	var team_name := name_edit.text.strip_edges()
	if team_name == "":
		return
	_send(MSG.CREATE_TEAM, {"name": team_name})
	name_edit.text = ""
	create_row.visible = false

func _on_copy() -> void:
	if _net == null:
		return
	DisplayServer.clipboard_set(str(_net.call("invite_link")))
	status_label.text = "Lien copié"

func _on_share() -> void:
	if _net != null:
		_net.call("share_link")

func _on_leave() -> void:
	if _net != null:
		_net.call("leave")
	get_tree().change_scene_to_file(HOME_SCENE)

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, SettingsForm.ROW_HEIGHT)
	return b

func _fit() -> void:
	var window := Vector2(DisplayServer.window_get_size())
	form.columns = SettingsLayout.columns_for(window)
	get_tree().root.content_scale_factor = SettingsLayout.zoom_for(window)
