class_name HomeScreen
extends Control

# The client's entry point: a nickname, then create a game, join one with its code (or the
# #CODE of an invitation link), or play solo. Laid out like the settings screen: one column,
# zoomed to fill a phone held in portrait.

const SOLO_SCENE := "res://src/ui/settings_screen.tscn"
const NICKNAME_MAX := 12

var nickname_edit: LineEdit
var code_edit: LineEdit
var create_button: Button
var join_button: Button
var solo_button: Button
var status_label: Label
var _net: Node # the Net autoload, looked up in the tree (not a global for scripts run with -s)
var _pending := false # a create / join was sent and nothing has come back yet

# The room code in an invitation link's hash ("#k7p2qx"), or "" when there is none.
static func code_from_hash(h: String) -> String:
	return RoomCodes.normalize(h)

# A page reloaded (or reopened) on a game this browser is in rejoins it at once. Not after
# coming back with a message (e.g. a connection given up on), and never after Quitter, which
# forgets the token and clears the hash.
static func should_rejoin(code: String, nickname: String, token: String, message: String) -> bool:
	return code != "" and nickname != "" and token != "" and message == ""

static func status_text(status: int) -> String:
	match status:
		NetClient.Status.CONNECTING:
			return "Connexion…"
		NetClient.Status.WAKING:
			return "Réveil du serveur… (jusqu'à une minute)"
		NetClient.Status.LOST:
			return "Serveur injoignable, réessaie dans un instant"
	return ""

func _ready() -> void:
	build()
	var linked_code := code_from_hash(_location_hash())
	code_edit.text = linked_code
	_net = get_node_or_null(^"/root/Net")
	var rejoin := false
	if _net != null:
		var shown := str(_net.get("message"))
		status_label.text = shown
		_net.set("message", "") # shown once
		_net.connect("status_changed", _on_status)
		_net.connect("error_received", show_error)
		var status: int = (_net.get("client") as NetClient).status
		if status == NetClient.Status.CONNECTING or status == NetClient.Status.WAKING:
			status_label.text = status_text(status)
		rejoin = status == NetClient.Status.OFFLINE and should_rejoin(linked_code,
				nickname_edit.text.strip_edges(), OnlineStore.token_for(linked_code), shown)
	_refresh()
	if rejoin:
		_on_join()
		status_label.text = str(_net.get("RECONNECTING_TEXT"))
	get_viewport().size_changed.connect(_fit)
	_fit()
	nickname_edit.grab_focus()

# Creates the controls (no tree needed, so tests can look at them).
func build() -> void:
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
	page.custom_minimum_size = Vector2(SettingsLayout.COLUMN_WIDTH - 32, 0)
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)

	var title := Label.new()
	title.text = "Bomberman"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	page.add_child(title)

	nickname_edit = _line_edit("Ton pseudo", NICKNAME_MAX)
	nickname_edit.text = OnlineStore.load_nickname()
	nickname_edit.text_changed.connect(func(_t: String) -> void: _refresh())
	page.add_child(nickname_edit)

	create_button = _button("Créer une partie")
	create_button.pressed.connect(_on_create)
	page.add_child(create_button)

	var or_label := Label.new()
	or_label.text = "ou"
	or_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(or_label)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	code_edit = _line_edit("Code", 0) # no max_length: a pasted link is cleaned, then cut
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.text_changed.connect(_on_code_changed)
	join_row.add_child(code_edit)
	join_button = _button("Rejoindre")
	join_button.pressed.connect(_on_join)
	join_row.add_child(join_button)
	page.add_child(join_row)

	solo_button = _button("Solo")
	solo_button.pressed.connect(_on_solo)
	page.add_child(solo_button)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(status_label)

func _exit_tree() -> void:
	get_viewport().size_changed.disconnect(_fit) # or unzooming would zoom again
	get_tree().root.content_scale_factor = 1.0 # the next screen lays itself out unzoomed

func show_error(code: String) -> void:
	_pending = false
	status_label.text = str(Protocol.ERROR_LABELS.get(code, code))
	_refresh()

# Keeps what a player typed or pasted ("#k7p2 qx/", a whole link) as an upper-case code.
static func clean_code(t: String) -> String:
	var out := t.get_slice("#", t.count("#")) if t.contains("#") else t
	out = out.replace("/", "").replace(" ", "").strip_edges().to_upper()
	return out.substr(0, RoomCodes.LENGTH)

func _on_code_changed(t: String) -> void:
	var cleaned := clean_code(t)
	if cleaned != t:
		var caret := code_edit.caret_column
		code_edit.text = cleaned
		code_edit.caret_column = mini(caret, cleaned.length())
	_refresh()

func _on_status(status: int) -> void:
	if status == NetClient.Status.LOST:
		_pending = false
		_net.set("message", "") # this screen already says it
	if status == NetClient.Status.OFFLINE:
		pass # closed on purpose, e.g. after a refusal whose message stays on screen
	elif status != NetClient.Status.ONLINE:
		status_label.text = status_text(status)
	elif status_label.text == status_text(NetClient.Status.CONNECTING) or status_label.text == status_text(NetClient.Status.WAKING):
		status_label.text = ""
	_refresh()

# A connection still being made must not pull the player out of solo later on.
func _on_solo() -> void:
	if _net != null:
		_net.call("cancel")
	get_tree().change_scene_to_file(SOLO_SCENE)

func _on_create() -> void:
	if _net == null or not _can_send():
		return
	_start_request()
	_net.call("create_game", nickname_edit.text.strip_edges())

func _on_join() -> void:
	var code := RoomCodes.normalize(code_edit.text)
	if _net == null or not _can_send() or code == "":
		return
	_start_request()
	_net.call("join_game", code, nickname_edit.text.strip_edges())

func _start_request() -> void:
	OnlineStore.save_nickname(nickname_edit.text.strip_edges())
	_pending = true
	status_label.text = ""
	_refresh()

func _can_send() -> bool:
	return nickname_edit.text.strip_edges() != "" and not _busy()

# A connection is being made, or a request is waiting for its answer.
func _busy() -> bool:
	if _pending:
		return true
	if _net == null:
		return false
	var status: int = (_net.get("client") as NetClient).status
	return status == NetClient.Status.CONNECTING or status == NetClient.Status.WAKING

# Buttons follow the form; the main one is Rejoindre when a valid code is there (from a link).
func _refresh() -> void:
	var has_name := nickname_edit.text.strip_edges() != ""
	var has_code := RoomCodes.normalize(code_edit.text) != ""
	var busy := _busy()
	create_button.disabled = not has_name or busy
	join_button.disabled = not has_name or not has_code or busy
	for state in ["normal", "hover", "pressed"]:
		_clear_accent(create_button, state)
		_clear_accent(join_button, state)
		SettingsForm.accent(join_button if has_code else create_button, state)

static func _clear_accent(b: Button, state: String) -> void:
	b.remove_theme_stylebox_override(state)
	for font_state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.remove_theme_color_override(font_state)

func _line_edit(placeholder: String, max_length: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = max_length
	e.custom_minimum_size = Vector2(0, SettingsForm.ROW_HEIGHT)
	return e

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, SettingsForm.ROW_HEIGHT)
	return b

func _location_hash() -> String:
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("window.location.hash", true))
	return ""

func _fit() -> void:
	get_tree().root.content_scale_factor = SettingsLayout.zoom_for(Vector2(DisplayServer.window_get_size()))
