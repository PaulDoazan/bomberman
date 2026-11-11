extends TestCase
# NetClient and the Net autoload against a real ServerCore on localhost (ports 19090-19099).
# Waits run on the real clock with a deadline; the wake-up delays use a simulated clock.

const Msg := Protocol.Msg
const Status := NetClient.Status
const TIMEOUT := 3.0
const NetScript := preload("res://src/net/net.gd")

var core: ServerCore

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _start(port: int) -> bool:
	core = ServerCore.new()
	var err := core.listen(port)
	assert_eq(err, OK, "écoute sur %d" % port)
	return err == OK

# Polls the server (if any) and the client until cond() is true, with a deadline.
func _pump_until(poll: Callable, cond: Callable, what: String) -> bool:
	var end := _now() + TIMEOUT
	while _now() < end:
		if core != null:
			core.poll(_now())
		poll.call(_now())
		if cond.call():
			return true
		OS.delay_msec(5)
	failures.append("délai dépassé : " + what)
	return false

func _finish() -> void:
	if core != null:
		core.stop()

func test_retries_then_lost_when_nothing_listens() -> void:
	var client := NetClient.new()
	var seen: Array[int] = []
	client.status_changed.connect(func(s: int) -> void: seen.append(s))
	client.open("ws://127.0.0.1:19090", 0.0)
	assert_eq(client.status, Status.CONNECTING, "en connexion")
	client.poll(2.9)
	assert_eq(client.status, Status.CONNECTING, "toujours en connexion avant 3 s")
	client.poll(3.1)
	assert_eq(client.status, Status.WAKING, "réveil du serveur après 3 s")
	# Real time passes so the refused attempts are seen as closed and retried.
	for t in range(4, 90, 3):
		var end := _now() + 0.2
		while _now() < end:
			client.poll(float(t))
			OS.delay_msec(5)
		assert_eq(client.status, Status.WAKING, "on réessaie à %d s" % t)
	client.poll(90.1)
	assert_eq(client.status, Status.LOST, "abandon après 90 s")
	assert_eq(seen, [Status.CONNECTING, Status.WAKING, Status.LOST], "statuts émis")
	client.poll(200.0)
	assert_eq(client.status, Status.LOST, "reste perdu")

func test_online_then_welcome() -> void:
	if not _start(19091):
		return
	var client := NetClient.new()
	var inbox: Array = []
	client.message.connect(func(type: int, body: Variant) -> void: inbox.append([type, body]))
	client.open("ws://127.0.0.1:19091", _now())
	var online := _pump_until(client.poll, func() -> bool: return client.status == Status.ONLINE, "ONLINE")
	if online:
		client.send(Msg.CREATE, {"name": "Paul", "schema": SimCodec.schema_hash()})
		var welcomed := func() -> bool: return inbox.any(func(m: Array) -> bool: return m[0] == Msg.WELCOME)
		if _pump_until(client.poll, welcomed, "WELCOME"):
			var body: Dictionary = inbox.filter(func(m: Array) -> bool: return m[0] == Msg.WELCOME)[0][1]
			assert_eq(String(body["code"]).length(), 6, "code reçu")
	client.close()
	assert_eq(client.status, Status.OFFLINE, "fermé")
	_finish()

func test_server_gone_is_lost() -> void:
	if not _start(19092):
		return
	var client := NetClient.new()
	client.open("ws://127.0.0.1:19092", _now())
	if _pump_until(client.poll, func() -> bool: return client.status == Status.ONLINE, "ONLINE"):
		core.stop()
		core = null
		_pump_until(client.poll, func() -> bool: return client.status == Status.LOST, "LOST")
	client.close()
	_finish()

func test_net_creates_a_game() -> void:
	if not _start(19093):
		return
	var saved_path := OnlineStore.path
	OnlineStore.path = "user://test_net_client.cfg"
	DirAccess.remove_absolute(OnlineStore.path)
	var net: Node = NetScript.new()
	net.url = "ws://127.0.0.1:19093"
	var lobbies: Array = []
	net.lobby_changed.connect(func() -> void: lobbies.append(net.lobby))
	net.create_game("Paul")
	var tick := func(now: float) -> void: net.tick(now)
	if _pump_until(tick, func() -> bool: return not lobbies.is_empty(), "LOBBY"):
		assert_eq(String(net.code).length(), 6, "code retenu")
		assert_true(net.my_id >= 0, "id retenu")
		assert_true(net.is_online(), "en ligne")
		assert_true(OnlineStore.token_for(net.code) != "", "jeton enregistré")
		assert_true(net.config is SimConfig, "réglages décodés")
		assert_eq(net.lobby["phase"], "lobby", "dans le salon")
		_pump_until(tick, func() -> bool: return net.ping_ms >= 0, "PONG")
	var left: String = net.code
	net.leave()
	assert_eq(OnlineStore.token_for(left), "", "jeton oublié après Quitter")
	assert_false(net.is_online(), "parti")
	assert_eq(net.code, "", "code oublié")
	net.free()
	DirAccess.remove_absolute(OnlineStore.path)
	OnlineStore.path = saved_path
	_finish()

func test_server_url_off_web() -> void:
	assert_eq(NetScript.server_url(), "ws://localhost:9080", "serveur local hors web")

func test_invite_link_points_at_the_server_in_production() -> void:
	var page := "https://pauldoazan.github.io/bomberman/"
	assert_eq(NetScript.invite_link_for(NetScript.PROD_URL, page, "K7P2QX"),
		"https://cafenavette.com/K7P2QX", "le site")
	assert_eq(NetScript.invite_link_for("ws://localhost:9080", page, "K7P2QX"),
		page + "#K7P2QX", "autre serveur : la page elle-même")

func test_page_path_drops_the_code() -> void:
	assert_eq(NetScript.page_path("/K7P2QX"), "/", "code seul")
	assert_eq(NetScript.page_path("/k7p2qx/"), "/", "barre finale")
	assert_eq(NetScript.page_path("/"), "/", "racine")
	assert_eq(NetScript.page_path("/bomberman/"), "/bomberman/", "sous-dossier")
	assert_eq(NetScript.page_path("/bomberman/K7P2QX"), "/bomberman/", "code sous un dossier")

func test_scene_for() -> void:
	var players := [{"id": 1, "team": 0}, {"id": 2, "team": -1}]
	var lobby := {"phase": "lobby", "players": players}
	var playing := {"phase": "playing", "players": players}
	assert_eq(NetScript.scene_for(lobby, 1), NetScript.LOBBY_SCENE, "salon")
	assert_eq(NetScript.scene_for(playing, 1), NetScript.GAME_SCENE, "en équipe : la partie")
	assert_eq(NetScript.scene_for(playing, 2), NetScript.LOBBY_SCENE, "sans équipe : choisir une équipe")
	assert_eq(NetScript.scene_for(playing, 9), NetScript.LOBBY_SCENE, "absent de la liste : salon")
	var each_for_themselves := {"phase": "playing", "players": [{"id": 1, "team": -1}, {"id": 2, "team": -1}]}
	assert_eq(NetScript.scene_for(each_for_themselves, 1), NetScript.GAME_SCENE, "personne en équipe : chacun pour soi, la partie")
	assert_eq(NetScript.scene_for(each_for_themselves, 2), NetScript.GAME_SCENE, "personne en équipe : l'invité aussi")

# A Net pointed at the local server, with a scratch OnlineStore; body(net) runs, then cleanup.
func _with_net(port: int, body: Callable) -> void:
	var saved_path := OnlineStore.path
	OnlineStore.path = "user://test_net_client.cfg"
	DirAccess.remove_absolute(OnlineStore.path)
	var net: Node = NetScript.new()
	net.url = "ws://127.0.0.1:%d" % port
	body.call(net)
	net.cancel()
	net.free()
	DirAccess.remove_absolute(OnlineStore.path)
	OnlineStore.path = saved_path

# Ticks the server and net on the real clock for `seconds`.
func _pump_for(net: Node, seconds: float) -> void:
	var end := _now() + seconds
	while _now() < end:
		if core != null:
			core.poll(_now())
		net.tick(_now())
		OS.delay_msec(5)

func test_refused_join_closes_quietly() -> void:
	if not _start(19094):
		return
	core.join_timeout = 0.3 # an open socket left behind would be dropped, and seen as LOST
	_with_net(19094, func(net: Node) -> void:
		var errors: Array[String] = []
		var seen: Array[int] = []
		net.error_received.connect(func(e: String) -> void: errors.append(e))
		net.status_changed.connect(func(st: int) -> void: seen.append(st))
		net.join_game("ZZZZZZ", "Paul")
		var tick := func(now: float) -> void: net.tick(now)
		if _pump_until(tick, func() -> bool: return not errors.is_empty(), "ERROR"):
			assert_eq(errors, ["unknown_code"] as Array[String], "code inconnu")
			assert_eq(net.client.status, Status.OFFLINE, "socket fermé sans bruit")
			_pump_for(net, 0.6)
			assert_false(seen.has(Status.LOST), "jamais perdu")
			assert_eq(net.message, "", "pas de « Connexion perdue »"))
	_finish()

func test_cancel_drops_a_pending_request() -> void:
	if not _start(19095):
		return
	_with_net(19095, func(net: Node) -> void:
		var lobbies := [0]
		net.lobby_changed.connect(func() -> void: lobbies[0] += 1)
		net.create_game("Paul")
		var tick := func(now: float) -> void: net.tick(now)
		_pump_until(tick, func() -> bool: return net.client.status == Status.ONLINE, "ONLINE")
		net.cancel() # Solo pressed right after the CREATE went out
		_pump_for(net, 0.4)
		assert_eq(lobbies[0], 0, "aucun salon reçu")
		assert_eq(net.code, "", "pas de partie")
		assert_eq(net.client.status, Status.OFFLINE, "hors ligne")
		assert_eq(net.message, "", "rien à dire"))
	_finish()

func test_net_ignores_what_it_did_not_ask_for() -> void:
	var net: Node = NetScript.new()
	var lobbies := [0]
	net.lobby_changed.connect(func() -> void: lobbies[0] += 1)
	net._on_message(Msg.WELCOME, {"code": "K7P2QX", "id": 3, "token": "t"})
	assert_eq(net.code, "", "WELCOME sans demande ignoré")
	net._on_message(Msg.LOBBY, {"phase": "lobby", "players": [], "config": {}})
	assert_eq(lobbies[0], 0, "LOBBY hors partie ignoré")
	net._on_status(Status.LOST)
	assert_eq(net.message, "", "perdu sans partie ni demande : rien")
	net._requesting = true
	net._on_status(Status.LOST)
	assert_eq(net.message, NetScript.LOST_MESSAGE, "perdu pendant une demande")
	net.free()

# Net creates a game and a team; returns true once the LOBBY with the team is in.
func _created_with_team(net: Node) -> bool:
	OnlineStore.save_nickname("Paul")
	net.create_game("Paul")
	var tick := func(now: float) -> void: net.tick(now)
	if not _pump_until(tick, func() -> bool: return not net.lobby.is_empty(), "LOBBY"):
		return false
	net.send_action(Msg.CREATE_TEAM, {"name": "Rouge"})
	return _pump_until(tick, func() -> bool: return net.lobby["teams"].size() == 1, "équipe créée")

func test_reconnects_after_a_drop() -> void:
	if not _start(19096):
		return
	_with_net(19096, func(net: Node) -> void:
		if not _created_with_team(net):
			return
		var id: int = net.my_id
		var room_code: String = net.code
		var room: Room = core.rooms[room_code]
		var team: int = room.players[id].team
		var flags: Array[bool] = []
		net.reconnecting_changed.connect(func(active: bool) -> void: flags.append(active))
		for peer: ServerCore.Peer in core._peers:
			if peer.player_id == id and peer.room_code == room_code:
				core._drop(peer, _now()) # what the server does to a silent phone
		var tick := func(now: float) -> void: net.tick(now)
		var back := func() -> bool: return flags.size() == 2 and not flags[1] and net.is_online()
		if _pump_until(tick, back, "reconnexion"):
			assert_true(flags[0], "reconnexion annoncée")
			assert_eq(net.my_id, id, "même joueur")
			assert_eq(net.code, room_code, "même partie")
			assert_true(room.players[id].connected, "connecté côté serveur")
			assert_eq(room.players[id].team, team, "même équipe")
			assert_eq(room.players.size(), 1, "pas de doublon")
			assert_eq(net.message, "", "pas de « Connexion perdue »"))
	_finish()

func test_reconnect_gives_up() -> void:
	if not _start(19097):
		return
	_with_net(19097, func(net: Node) -> void:
		net.reconnect_for = 0.5
		if not _created_with_team(net):
			return
		core.stop()
		core = null
		var tick := func(now: float) -> void: net.tick(now)
		if _pump_until(tick, func() -> bool: return net.message != "", "abandon"):
			assert_eq(net.message, NetScript.LOST_MESSAGE, "Connexion perdue")
			assert_eq(net.code, "", "plus de partie")
			assert_false(net.is_reconnecting(), "plus de reconnexion")
			assert_eq(net.client.status, Status.OFFLINE, "hors ligne"))
	_finish()
