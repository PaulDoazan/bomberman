extends Node
# Autoload: the online game seen from this player (connection, room, lobby) and the scene
# changes it drives. Inert until create_game or join_game, and on the server process.

const Msg := Protocol.Msg
const Status := NetClient.Status

const PROD_URL := "wss://bomberman-pauldoazan.onrender.com"
const LOCAL_URL := "ws://localhost:9080"
const INVITE_BASE := "https://pauldoazan.github.io/bomberman/"
const HOME_SCENE := "res://src/ui/home_screen.tscn"
const LOBBY_SCENE := "res://src/ui/lobby_screen.tscn"
const GAME_SCENE := "res://src/game/game.tscn"
const PING_EVERY := 2.0
const LOST_MESSAGE := "Connexion perdue"

signal lobby_changed
signal error_received(code: String)
signal snapshot_received(data: Dictionary)
signal status_changed(status: int)

var url := server_url() # tests point it at a local server
var client := NetClient.new()
var code := ""
var my_id := -1
var lobby: Dictionary = {}
var ping_ms := -1
var config: SimConfig
var message := "" # shown once by the home screen, e.g. LOST_MESSAGE
var _hello: Array = [] # [type, body] sent as soon as the socket is open
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
	client.poll(now)
	if client.status == Status.ONLINE and now >= _next_ping:
		_next_ping = now + PING_EVERY
		client.send(Msg.PING, {"t": now})

func create_game(p_name: String) -> void:
	_hello_or_send(Msg.CREATE, {"name": p_name, "schema": SimCodec.schema_hash()})

func join_game(p_code: String, p_name: String) -> void:
	_hello_or_send(Msg.JOIN, {"code": p_code, "name": p_name, "token": OnlineStore.token_for(p_code), "schema": SimCodec.schema_hash()})

# Quitter: the server removes this player from the room, and this browser forgets the game
# (token and #CODE) so that nothing rejoins it on its own.
func leave() -> void:
	if code != "":
		client.send(Msg.LEAVE, null)
		OnlineStore.forget_token(code)
		if OS.has_feature("web"):
			JavaScriptBridge.eval("history.replaceState(null, '', location.pathname + location.search)", true)
	client.close()
	_hello = []
	_reset()

func send_action(type: int, body: Variant = {}) -> void:
	client.send(type, body)

# Called at most once per simulation tick by the game.
func send_intent(i: PlayerIntent) -> void:
	client.send(Msg.INTENT, Protocol.intent_to_array(i))

# Connected and in a room.
func is_online() -> bool:
	return client.status == Status.ONLINE and code != ""

func invite_link() -> String:
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("location.origin + location.pathname", true)) + "#" + code
	return INVITE_BASE + "#" + code

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
		_reset()
		message = LOST_MESSAGE
		_go(HOME_SCENE)
	status_changed.emit(status)

func _on_message(type: int, body: Variant) -> void:
	match type:
		Msg.WELCOME:
			if body is Dictionary:
				code = str(body.get("code", ""))
				my_id = int(body.get("id", -1))
				_set_session("local_id", my_id)
				OnlineStore.save_token(code, str(body.get("token", "")))
				if OS.has_feature("web"):
					JavaScriptBridge.eval("history.replaceState(null, '', %s)" % JSON.stringify("#" + code), true)
		Msg.LOBBY:
			if body is Dictionary:
				lobby = body
				config = SimCodec.decode_config(body.get("config", {}))
				_set_session("config", config)
				lobby_changed.emit()
				_go(scene_for(body, my_id))
		Msg.ERROR:
			if body is Dictionary:
				error_received.emit(str(body.get("error", "")))
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
