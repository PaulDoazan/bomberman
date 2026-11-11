extends Node
# Autoload: the online game seen from this player (connection, room, lobby) and the scene
# changes it drives. Inert until create_game or join_game, and on the server process.

const Msg := Protocol.Msg
const Status := NetClient.Status

const PROD_URL := "wss://cafenavette-7qgq.onrender.com"
const LOCAL_URL := "ws://localhost:9080"
const INVITE_BASE := "https://pauldoazan.github.io/bomberman/"
const HOME_SCENE := "res://src/ui/home_screen.tscn"
const LOBBY_SCENE := "res://src/ui/lobby_screen.tscn"
const GAME_SCENE := "res://src/game/game.tscn"
const PING_EVERY := 2.0
const LOST_MESSAGE := "Connexion perdue"
const RECONNECTING_TEXT := "Reconnexion…"

signal lobby_changed
signal error_received(code: String)
signal snapshot_received(data: Dictionary)
signal status_changed(status: int)
signal reconnecting_changed(active: bool)

var url := server_url() # tests point it at a local server
var client := NetClient.new()
var code := ""
var my_id := -1
var lobby: Dictionary = {}
var ping_ms := -1
var config: SimConfig
var message := "" # shown once by the home screen, e.g. LOST_MESSAGE
var reconnect_for := 20.0 # seconds spent rejoining the room after a lost connection
var _hello: Array = [] # [type, body] sent as soon as the socket is open
var _requesting := false # a CREATE or JOIN was asked for and has not been answered yet
var _reconnect_until := -1.0 # while >= 0, the room is being rejoined after a lost connection
var _rejoin_due := false # rejoin on the next tick, not from inside the LOST signal
var _next_ping := 0.0
var _now := 0.0

# In a web build, the page's ?server= parameter if present, otherwise PROD_URL.
static func server_url() -> String:
	if OS.has_feature("web"):
		var param: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('server') || ''", true)
		return str(param) if str(param) != "" else PROD_URL
	return LOCAL_URL

# Where a LOBBY message sends this player: the game while a match runs and they have a team,
# otherwise the lobby (where a newcomer picks a team for the next round).
static func scene_for(state: Dictionary, p_my_id: int) -> String:
	if state.get("phase") != "playing":
		return LOBBY_SCENE
	for p: Variant in state.get("players", []):
		if p is Dictionary and int(p.get("id", -1)) == p_my_id:
			return GAME_SCENE if int(p.get("team", -1)) != -1 else LOBBY_SCENE
	return LOBBY_SCENE

func _init() -> void:
	client.message.connect(_on_message)
	client.status_changed.connect(_on_status)

func _ready() -> void:
	set_process(not Boot.is_server())

func _process(_delta: float) -> void:
	tick(Time.get_ticks_msec() / 1000.0)

func tick(now: float) -> void:
	_now = now
	if _rejoin_due:
		_rejoin_due = false
		join_game(code, OnlineStore.load_nickname()) # the saved token brings back the same player
	client.poll(now)
	if is_reconnecting() and now >= _reconnect_until:
		_give_up(LOST_MESSAGE)
		return
	if client.status == Status.ONLINE and now >= _next_ping:
		_next_ping = now + PING_EVERY
		client.send(Msg.PING, {"t": now})

func create_game(p_name: String) -> void:
	_requesting = true
	_hello_or_send(Msg.CREATE, {"name": p_name, "schema": SimCodec.schema_hash()})

func join_game(p_code: String, p_name: String) -> void:
	_requesting = true
	_hello_or_send(Msg.JOIN, {"code": p_code, "name": p_name, "token": OnlineStore.token_for(p_code), "schema": SimCodec.schema_hash()})

# Quitter: the server removes this player from the room, and this browser forgets the game
# (token and #CODE) so that nothing rejoins it on its own.
func leave() -> void:
	if code != "":
		client.send(Msg.LEAVE, null)
		OnlineStore.forget_token(code)
		if OS.has_feature("web"):
			JavaScriptBridge.eval("history.replaceState(null, '', location.pathname + location.search)", true)
	cancel()

# Drops the connection and whatever was asked, without a word (Solo, a refused request).
func cancel() -> void:
	_hello = []
	_requesting = false
	_rejoin_due = false
	_set_reconnecting(-1.0)
	client.close()
	_reset()

# Back home with a message, e.g. when the room could not be rejoined in time.
func _give_up(why: String) -> void:
	cancel()
	message = why
	_go(HOME_SCENE)

func send_action(type: int, body: Variant = {}) -> void:
	client.send(type, body)

# Called at most once per simulation tick by the game.
func send_intent(i: PlayerIntent) -> void:
	client.send(Msg.INTENT, Protocol.intent_to_array(i))

# Connected and in a room.
func is_online() -> bool:
	return client.status == Status.ONLINE and code != ""

# In a room, connected or being reconnected.
func in_room() -> bool:
	return code != ""

func is_reconnecting() -> bool:
	return _reconnect_until >= 0.0

func _set_reconnecting(until: float) -> void:
	var was := is_reconnecting()
	_reconnect_until = until
	if is_reconnecting() != was:
		reconnecting_changed.emit(is_reconnecting())

func invite_link() -> String:
	var page := INVITE_BASE
	if OS.has_feature("web"):
		page = str(JavaScriptBridge.eval("location.origin + location.pathname", true))
	return invite_link_for(url, page, code)

# Against the production server, its own address (it redirects /CODE to the game page with
# #CODE); against any other server, the page itself with #CODE.
static func invite_link_for(server: String, page: String, p_code: String) -> String:
	if server == PROD_URL:
		return PROD_URL.replace("wss://", "https://") + "/" + p_code
	return page + "#" + p_code

# The phone's share sheet when there is one, otherwise the clipboard.
func share_link() -> void:
	var link := invite_link()
	if OS.has_feature("web") and JavaScriptBridge.eval("typeof navigator.share === 'function'", true):
		JavaScriptBridge.eval("navigator.share({url: %s}).catch(function () {})" % JSON.stringify(link), true)
		return
	DisplayServer.clipboard_set(link)

func _hello_or_send(type: int, body: Dictionary) -> void:
	if client.status == Status.ONLINE:
		client.send(type, body)
		return
	_hello = [type, body]
	if client.status != Status.CONNECTING and client.status != Status.WAKING:
		client.open(url, _now)

func _reset() -> void:
	code = ""
	my_id = -1
	lobby = {}
	ping_ms = -1
	_set_session("local_id", 0)

func _on_status(status: int) -> void:
	if status == Status.ONLINE:
		_next_ping = _now
		if not _hello.is_empty():
			client.send(_hello[0], _hello[1])
			_hello = []
	elif status == Status.LOST:
		_hello = []
		if code != "":
			# In a room (a phone woken up, a network switch): rejoin it for a while first.
			_requesting = false
			_rejoin_due = true
			if not is_reconnecting():
				_set_reconnecting(_now + reconnect_for)
		elif _requesting:
			# Only a request this player is waiting on is worth going home for.
			_give_up(LOST_MESSAGE)
	status_changed.emit(status)

func _on_message(type: int, body: Variant) -> void:
	match type:
		Msg.WELCOME:
			if body is Dictionary and _requesting:
				_requesting = false
				_set_reconnecting(-1.0)
				code = str(body.get("code", ""))
				my_id = int(body.get("id", -1))
				_set_session("local_id", my_id)
				OnlineStore.save_token(code, str(body.get("token", "")))
				if OS.has_feature("web"):
					JavaScriptBridge.eval("history.replaceState(null, '', %s)" % JSON.stringify("#" + code), true)
		Msg.LOBBY:
			if body is Dictionary and code != "": # only for the room this player is in
				lobby = body
				config = SimCodec.decode_config(body.get("config", {}))
				_set_session("config", config)
				lobby_changed.emit()
				_go(scene_for(body, my_id))
		Msg.ERROR:
			if body is Dictionary:
				var err := str(body.get("error", ""))
				if is_reconnecting():
					# The room is gone, or this client is out of date.
					_give_up(str(Protocol.ERROR_LABELS[err]) if err == Protocol.ERR_VERSION else LOST_MESSAGE)
					return
				if code == "":
					# A refused CREATE or JOIN: the socket has no use any more (the server would
					# drop it after a while, which would read as a lost connection).
					cancel()
				error_received.emit(err)
		Msg.SNAPSHOT:
			if body is Dictionary:
				snapshot_received.emit(body)
		Msg.PONG:
			if body is Dictionary and body.has("t"):
				ping_ms = int((_now - float(body["t"])) * 1000.0)

# Session is looked up in the tree: autoload names are not globals for scripts run with -s (tests).
func _set_session(key: String, value: Variant) -> void:
	var session := get_node_or_null(^"/root/Session") if is_inside_tree() else null
	if session != null:
		session.set(key, value)

# Deferred scene change, skipped without a current scene (tests) or before the scene exists.
func _go(path: String) -> void:
	if not is_inside_tree() or get_tree().current_scene == null:
		return
	if get_tree().current_scene.scene_file_path == path or not ResourceLoader.exists(path):
		return
	get_tree().change_scene_to_file.call_deferred(path)
