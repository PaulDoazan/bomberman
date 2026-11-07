extends TestCase
# A real ServerCore on localhost with raw WebSocketPeer clients. Every wait has a deadline,
# and every test stops the server so its port is free again.

const Msg := Protocol.Msg
const TIMEOUT := 3.0

class Client:
	var ws := WebSocketPeer.new()
	var inbox: Array = [] # [type, body] in arrival order

var core: ServerCore
var clients: Array[Client] = []

func _start(port: int) -> bool:
	core = ServerCore.new()
	var err := core.listen(port)
	assert_eq(err, OK, "écoute sur %d" % port)
	return err == OK

func _client(port: int) -> Client:
	var c := Client.new()
	c.ws.connect_to_url("ws://127.0.0.1:%d" % port)
	clients.append(c)
	_pump_until(func() -> bool: return c.ws.get_ready_state() == WebSocketPeer.STATE_OPEN, "connexion")
	return c

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

# Polls the server and every client once, filling the inboxes.
func _pump_once() -> void:
	core.poll(_now())
	for c in clients:
		c.ws.poll()
		while c.ws.get_available_packet_count() > 0:
			var msg := Protocol.decode(c.ws.get_packet())
			if not msg.is_empty():
				c.inbox.append(msg)
	OS.delay_msec(5)

# Pumps until cond() is true; false (and a failure) after TIMEOUT seconds.
func _pump_until(cond: Callable, what: String, timeout := TIMEOUT) -> bool:
	var end := _now() + timeout
	while _now() < end:
		_pump_once()
		if cond.call():
			return true
	failures.append("délai dépassé : " + what)
	return false

# Waits for a message of the given type that satisfies pred; earlier messages are dropped.
# Returns its body, or null on timeout.
func _expect(c: Client, type: int, what: String, pred := Callable(), timeout := TIMEOUT) -> Variant:
	var found: Array = []
	var match_found := func() -> bool:
		while not c.inbox.is_empty():
			var msg: Array = c.inbox.pop_front()
			if msg[0] == type and (not pred.is_valid() or pred.call(msg[1])):
				found.append(msg[1])
				return true
		return false
	if _pump_until(match_found, what, timeout):
		return found[0]
	return null

func _send(c: Client, type: int, body: Variant) -> void:
	c.ws.send(Protocol.encode(type, body))

# Closes every client cleanly, then the server.
func _finish() -> void:
	for c in clients:
		if c.ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
			c.ws.close()
	var end := _now() + TIMEOUT
	while _now() < end and clients.any(func(c: Client) -> bool:
			return c.ws.get_ready_state() != WebSocketPeer.STATE_CLOSED):
		_pump_once()
	core.stop()
	clients.clear()

func _players(lobby: Variant) -> Array:
	return lobby["players"] if lobby is Dictionary else []

# A creates a room; returns [A, its WELCOME body], or [] on failure.
func _create(port: int, p_name := "Paul") -> Array:
	var a := _client(port)
	_send(a, Msg.CREATE, {"name": p_name, "schema": SimCodec.schema_hash()})
	var welcome: Variant = _expect(a, Msg.WELCOME, "WELCOME")
	if welcome == null:
		return []
	return [a, welcome]

func _join(port: int, code: String, p_name: String, token := "") -> Client:
	var b := _client(port)
	_send(b, Msg.JOIN, {"code": code, "name": p_name, "token": token, "schema": SimCodec.schema_hash()})
	return b

func test_create_then_join() -> void:
	if not _start(19080):
		return
	var created := _create(19080)
	if not created.is_empty():
		var a: Client = created[0]
		var welcome: Dictionary = created[1]
		assert_eq(String(welcome["code"]).length(), 6, "code de 6 caractères")
		assert_true(welcome["id"] is int, "id")
		assert_true(welcome["token"] is String and welcome["token"] != "", "jeton")
		var lobby: Variant = _expect(a, Msg.LOBBY, "LOBBY après création")
		assert_eq(_players(lobby).size(), 1, "seul dans le salon")
		assert_eq(core.rooms.size(), 1, "une partie")
		var b := _join(19080, welcome["code"], "Bob")
		var two := func(body: Variant) -> bool: return _players(body).size() == 2
		assert_true(_expect(b, Msg.WELCOME, "WELCOME de B") != null, "B accueilli")
		assert_true(_expect(a, Msg.LOBBY, "LOBBY à 2 pour A", two) != null, "A voit B")
		assert_true(_expect(b, Msg.LOBBY, "LOBBY à 2 pour B", two) != null, "B voit A")
	_finish()

func test_join_refusals() -> void:
	if not _start(19081):
		return
	var created := _create(19081)
	if not created.is_empty():
		var code: String = created[1]["code"]
		var b := _client(19081)
		_send(b, Msg.JOIN, {"code": code, "name": "Bob", "token": "", "schema": 1})
		var err: Variant = _expect(b, Msg.ERROR, "ERROR version")
		assert_eq(err["error"] if err != null else null, Protocol.ERR_VERSION, "version")
		_send(b, Msg.JOIN, {"code": "ZZZZZZ" if code != "ZZZZZZ" else "YYYYYY", "name": "Bob", "token": "", "schema": SimCodec.schema_hash()})
		err = _expect(b, Msg.ERROR, "ERROR unknown_code")
		assert_eq(err["error"] if err != null else null, Protocol.ERR_UNKNOWN_CODE, "code inconnu")
		_send(b, Msg.JOIN, {"code": code, "name": "Paul", "token": "", "schema": SimCodec.schema_hash()})
		err = _expect(b, Msg.ERROR, "ERROR name_taken")
		assert_eq(err["error"] if err != null else null, Protocol.ERR_NAME_TAKEN, "pseudo pris")
		assert_eq(core.rooms[code].players.size(), 1, "personne de plus")
	_finish()

func test_malformed_bodies() -> void:
	if not _start(19082):
		return
	var c := _client(19082)
	# Before CREATE/JOIN only PING is answered.
	_send(c, Msg.START, null)
	_send(c, Msg.PING, {"t": 1.5})
	_pump_until(func() -> bool: return not c.inbox.is_empty(), "PONG")
	# Messages arrive in order: an answer to START would come before the PONG.
	assert_eq(c.inbox, [[Msg.PONG, {"t": 1.5}]], "START ignoré, PONG renvoie le corps")
	c.inbox.clear()
	for body: Variant in [null, 3, [], {"name": 4, "schema": SimCodec.schema_hash()}, {"name": "Paul", "schema": "x"}]:
		_send(c, Msg.CREATE, body)
		var err: Variant = _expect(c, Msg.ERROR, "ERROR pour %s" % str(body))
		assert_eq(err["error"] if err != null else null, Protocol.ERR_NOT_NOW, "corps %s" % str(body))
	assert_true(core.rooms.is_empty(), "aucune partie")
	_send(c, Msg.CREATE, {"name": "Paul", "schema": SimCodec.schema_hash()})
	assert_true(_expect(c, Msg.WELCOME, "WELCOME") != null, "créée")
	for pair: Array in [[Msg.CREATE_TEAM, {"name": 1}], [Msg.JOIN_TEAM, {"team": "0"}], [Msg.SETTINGS, {"config": []}], [Msg.INTENT, [1, 2]]]:
		_send(c, pair[0], pair[1])
		var err: Variant = _expect(c, Msg.ERROR, "ERROR pour %s" % str(pair))
		assert_eq(err["error"] if err != null else null, Protocol.ERR_NOT_NOW, "corps %s" % str(pair))
	assert_true(c.ws.get_ready_state() == WebSocketPeer.STATE_OPEN, "toujours connecté")
	_finish()

func test_start_sends_snapshots() -> void:
	if not _start(19083):
		return
	var created := _create(19083)
	if not created.is_empty():
		var a: Client = created[0]
		var b := _join(19083, created[1]["code"], "Bob")
		assert_true(_expect(b, Msg.WELCOME, "WELCOME de B") != null, "B accueilli")
		_send(a, Msg.SETTINGS, {"config": {"map_size": "petite"}})
		var small := func(body: Variant) -> bool: return body["config"]["map_size"] == "petite"
		assert_true(_expect(b, Msg.LOBBY, "réglages", small) != null, "réglages appliqués")
		_send(a, Msg.CREATE_TEAM, {"name": "Rouge"})
		_send(b, Msg.CREATE_TEAM, {"name": "Bleu"})
		var ready := func(body: Variant) -> bool: return body["can_start"]
		assert_true(_expect(a, Msg.LOBBY, "deux équipes", ready) != null, "prêts")
		_send(a, Msg.START, null)
		var playing := func(body: Variant) -> bool: return body["phase"] == "playing"
		assert_true(_expect(a, Msg.LOBBY, "LOBBY playing pour A", playing) != null, "A en partie")
		assert_true(_expect(b, Msg.LOBBY, "LOBBY playing pour B", playing) != null, "B en partie")
		var snap: Variant = _expect(a, Msg.SNAPSHOT, "SNAPSHOT pour A", Callable(), 1.0)
		assert_true(snap is Dictionary and snap["roster"].size() == 2, "instantané à 2")
		assert_true(_expect(b, Msg.SNAPSHOT, "SNAPSHOT pour B", Callable(), 1.0) != null, "B reçoit")
		var intent := PlayerIntent.new()
		intent.moving = true
		_send(b, Msg.INTENT, Protocol.intent_to_array(intent))
		_send(a, Msg.TO_LOBBY, null)
		var lobby := func(body: Variant) -> bool: return body["phase"] == "lobby"
		assert_true(_expect(b, Msg.LOBBY, "retour au salon", lobby) != null, "salon")
	_finish()

func test_closing_socket_disconnects() -> void:
	if not _start(19084):
		return
	var created := _create(19084)
	if not created.is_empty():
		var a: Client = created[0]
		var b := _join(19084, created[1]["code"], "Bob")
		var welcome: Variant = _expect(b, Msg.WELCOME, "WELCOME de B")
		var two := func(body: Variant) -> bool: return _players(body).size() == 2
		_expect(a, Msg.LOBBY, "LOBBY à 2", two)
		b.ws.close()
		var b_gone := func(body: Variant) -> bool:
			return _players(body).any(func(p: Dictionary) -> bool:
				return welcome != null and p["id"] == welcome["id"] and not p["connected"])
		assert_true(_expect(a, Msg.LOBBY, "LOBBY avec B déconnecté", b_gone) != null, "B déconnecté")
	_finish()

func test_same_token_closes_old_socket() -> void:
	if not _start(19085):
		return
	var created := _create(19085)
	if not created.is_empty():
		var a: Client = created[0]
		var welcome: Dictionary = created[1]
		var a2 := _join(19085, welcome["code"], "", welcome["token"])
		var back: Variant = _expect(a2, Msg.WELCOME, "WELCOME de retour")
		assert_eq(back["id"] if back != null else null, welcome["id"], "même joueur")
		_pump_until(func() -> bool: return a.ws.get_ready_state() == WebSocketPeer.STATE_CLOSED, "ancien socket fermé")
		var room: Room = core.rooms[welcome["code"]]
		_pump_once()
		assert_true(room.players[welcome["id"]].connected, "toujours connecté")
	_finish()

func test_flood_is_dropped() -> void:
	if not _start(19086):
		return
	var created := _create(19086)
	if not created.is_empty():
		var a: Client = created[0]
		var room: Room = core.rooms[created[1]["code"]]
		for i in 1000:
			_send(a, Msg.PING, {"t": i})
		_pump_until(func() -> bool: return a.ws.get_ready_state() == WebSocketPeer.STATE_CLOSED, "socket coupé")
		assert_false(room.players[created[1]["id"]].connected, "déconnecté")
	_finish()

func test_honest_burst_is_kept() -> void:
	if not _start(19087):
		return
	var created := _create(19087)
	if not created.is_empty():
		var a: Client = created[0]
		# A stalled network delivering a few seconds of intents and pings at once.
		for i in 150:
			_send(a, Msg.PING, {"t": i})
		var pongs := func() -> bool:
			return a.inbox.filter(func(m: Array) -> bool: return m[0] == Msg.PONG).size() == 150
		assert_true(_pump_until(pongs, "150 PONG"), "toutes les réponses")
		assert_eq(a.ws.get_ready_state(), WebSocketPeer.STATE_OPEN, "toujours connecté")
		assert_true(core.rooms[created[1]["code"]].players[created[1]["id"]].connected, "toujours dans la partie")
	_finish()

func test_bound_peer_cannot_create_or_join() -> void:
	if not _start(19088):
		return
	var created := _create(19088)
	if not created.is_empty():
		var a: Client = created[0]
		_send(a, Msg.CREATE, {"name": "Paul", "schema": SimCodec.schema_hash()})
		var err: Variant = _expect(a, Msg.ERROR, "ERROR pour CREATE")
		assert_eq(err["error"] if err != null else null, Protocol.ERR_NOT_NOW, "CREATE refusé")
		_send(a, Msg.JOIN, {"code": created[1]["code"], "name": "Zoé", "token": "", "schema": SimCodec.schema_hash()})
		err = _expect(a, Msg.ERROR, "ERROR pour JOIN")
		assert_eq(err["error"] if err != null else null, Protocol.ERR_NOT_NOW, "JOIN refusé")
		assert_eq(core.rooms.size(), 1, "pas de nouvelle partie")
		assert_eq(core.rooms[created[1]["code"]].players.size(), 1, "pas de nouveau joueur")
	_finish()

func test_leave_removes_player() -> void:
	if not _start(19089):
		return
	var created := _create(19089)
	if not created.is_empty():
		var a: Client = created[0]
		var b := _join(19089, created[1]["code"], "Bob")
		var welcome: Variant = _expect(b, Msg.WELCOME, "WELCOME de B")
		_send(b, Msg.CREATE_TEAM, {"name": "Bleu"})
		_expect(a, Msg.LOBBY, "équipe de B", func(body: Variant) -> bool: return body["teams"].size() == 1)
		_send(b, Msg.LEAVE, null)
		var b_gone := func(body: Variant) -> bool: return _players(body).size() == 1
		var lobby: Variant = _expect(a, Msg.LOBBY, "LOBBY après LEAVE", b_gone)
		assert_true(lobby != null, "B retiré du salon")
		assert_true(lobby != null and lobby["teams"].is_empty(), "son équipe vide supprimée")
		assert_false(core.rooms[created[1]["code"]].players.has(welcome["id"] if welcome != null else -1), "plus dans la partie")
		assert_eq(b.ws.get_ready_state(), WebSocketPeer.STATE_OPEN, "le socket reste ouvert")
	_finish()

func test_idle_peer_is_dropped() -> void:
	if not _start(19080):
		return
	core.join_timeout = 0.3
	var c := _client(19080)
	_pump_until(func() -> bool: return c.ws.get_ready_state() == WebSocketPeer.STATE_CLOSED, "pair inactif coupé")
	_finish()

func test_peer_cap() -> void:
	if not _start(19081):
		return
	core.max_peers = 1
	var a := _client(19081)
	var b := Client.new()
	b.ws.connect_to_url("ws://127.0.0.1:19081")
	clients.append(b)
	_pump_until(func() -> bool: return b.ws.get_ready_state() == WebSocketPeer.STATE_CLOSED, "connexion refusée")
	assert_eq(a.ws.get_ready_state(), WebSocketPeer.STATE_OPEN, "le premier reste")
	_finish()

func test_lobby_change_in_tick_is_broadcast() -> void:
	if not _start(19082):
		return
	var created := _create(19082)
	if not created.is_empty():
		var a: Client = created[0]
		var b := _join(19082, created[1]["code"], "Bob")
		var welcome: Variant = _expect(b, Msg.WELCOME, "WELCOME de B")
		var two := func(body: Variant) -> bool: return _players(body).size() == 2
		_expect(a, Msg.LOBBY, "LOBBY à 2", two)
		# What Room.tick does on its own (forgetting a player) is not tied to any message.
		var room: Room = core.rooms[created[1]["code"]]
		room.players.erase(welcome["id"] if welcome != null else -1)
		var one := func(body: Variant) -> bool: return _players(body).size() == 1
		assert_true(_expect(a, Msg.LOBBY, "LOBBY après changement dans tick", one, 2.0) != null, "diffusé")
	_finish()

# Two players in two teams, match started: returns [A, B, code, B's id], or [] on failure.
func _started_match(port: int) -> Array:
	var created := _create(port)
	if created.is_empty():
		return []
	var a: Client = created[0]
	var b := _join(port, created[1]["code"], "Bob")
	var welcome: Variant = _expect(b, Msg.WELCOME, "WELCOME de B")
	if welcome == null:
		return []
	_send(a, Msg.CREATE_TEAM, {"name": "Rouge"})
	_send(b, Msg.CREATE_TEAM, {"name": "Bleu"})
	if _expect(a, Msg.LOBBY, "deux équipes", func(body: Variant) -> bool: return body["can_start"]) == null:
		return []
	_send(a, Msg.START, null)
	if _expect(b, Msg.LOBBY, "LOBBY playing", func(body: Variant) -> bool: return body["phase"] == "playing") == null:
		return []
	return [a, b, created[1]["code"], welcome["id"]]

func _moving() -> Array:
	var intent := PlayerIntent.new()
	intent.moving = true
	intent.target = Vector2(3, 3)
	return Protocol.intent_to_array(intent)

func test_intents_cleared_on_new_round_and_start() -> void:
	if not _start(19083):
		return
	var m := _started_match(19083)
	if not m.is_empty():
		var a: Client = m[0]
		var b: Client = m[1]
		var buf: IntentBuffer = core._intents[m[2]]
		var room: Room = core.rooms[m[2]]
		_send(b, Msg.INTENT, _moving())
		_pump_until(func() -> bool: return buf._pending.has(m[3]), "intention reçue")
		room.match_state.phase = MatchState.Phase.ROUND_OVER
		room.match_state.phase_timer = 0.0
		_pump_until(func() -> bool: return room.match_state.round_number == 2, "manche 2")
		assert_true(buf._pending.is_empty(), "rien ne passe à la manche suivante")
		_send(b, Msg.INTENT, _moving())
		_pump_until(func() -> bool: return buf._pending.has(m[3]), "intention reçue")
		_send(a, Msg.TO_LOBBY, null)
		_expect(b, Msg.LOBBY, "retour au salon", func(body: Variant) -> bool: return body["phase"] == "lobby")
		_send(a, Msg.START, null)
		_expect(b, Msg.LOBBY, "relancé", func(body: Variant) -> bool: return body["phase"] == "playing")
		assert_true(buf._pending.is_empty(), "rien ne passe au nouveau lancement")
	_finish()

func test_intents_forgotten_on_disconnect() -> void:
	if not _start(19084):
		return
	var m := _started_match(19084)
	if not m.is_empty():
		var b: Client = m[1]
		var buf: IntentBuffer = core._intents[m[2]]
		var room: Room = core.rooms[m[2]]
		_send(b, Msg.INTENT, _moving())
		_pump_until(func() -> bool: return buf._pending.has(m[3]), "intention reçue")
		b.ws.close()
		_pump_until(func() -> bool: return not room.players[m[3]].connected, "B déconnecté")
		assert_false(buf._pending.has(m[3]), "B ne continue pas de marcher")
	_finish()

func test_silent_peer_in_room_is_dropped() -> void:
	if not _start(19085):
		return
	core.silence_timeout = 0.4
	core.lobby_silence_timeout = 0.4
	var created := _create(19085)
	if not created.is_empty():
		var a: Client = created[0]
		var b := _join(19085, created[1]["code"], "Bob")
		var welcome: Variant = _expect(b, Msg.WELCOME, "WELCOME de B")
		var room: Room = core.rooms[created[1]["code"]]
		# A pings on and stays; B says nothing more.
		var end := _now() + 1.0
		while _now() < end:
			_send(a, Msg.PING, {"t": 0})
			_pump_once()
			OS.delay_msec(50)
		assert_true(room.players[created[1]["id"]].connected, "A, qui parle, reste")
		assert_eq(a.ws.get_ready_state(), WebSocketPeer.STATE_OPEN, "socket de A ouvert")
		assert_false(room.players[welcome["id"] if welcome != null else -1].connected, "B, muet, déconnecté")
		_pump_until(func() -> bool: return b.ws.get_ready_state() == WebSocketPeer.STATE_CLOSED, "socket de B fermé")
	_finish()

# In the lobby, a host who leaves the app a while to share the link keeps their seat and role.
func test_silent_peer_in_lobby_is_kept_longer() -> void:
	if not _start(19087):
		return
	core.silence_timeout = 0.4
	core.lobby_silence_timeout = 30.0
	var created := _create(19087)
	if not created.is_empty():
		var a: Client = created[0]
		var b := _join(19087, created[1]["code"], "Bob")
		_expect(b, Msg.WELCOME, "WELCOME de B")
		var room: Room = core.rooms[created[1]["code"]]
		# B pings on; A, the host, says nothing for a second.
		var end := _now() + 1.0
		while _now() < end:
			_send(b, Msg.PING, {"t": 0})
			_pump_once()
			OS.delay_msec(50)
		assert_true(room.players[created[1]["id"]].connected, "l'host muet reste connecté au salon")
		assert_eq(room.host_id, created[1]["id"], "l'host garde son rôle")
		assert_eq(a.ws.get_ready_state(), WebSocketPeer.STATE_OPEN, "socket de l'host ouvert")
	_finish()

func test_server_full_past_max_rooms() -> void:
	if not _start(19086):
		return
	for i in ServerCore.MAX_ROOMS:
		_create(19086, "P%d" % i)
	assert_eq(core.rooms.size(), ServerCore.MAX_ROOMS, "%d parties" % ServerCore.MAX_ROOMS)
	var c := _client(19086)
	_send(c, Msg.CREATE, {"name": "Zoé", "schema": SimCodec.schema_hash()})
	var err: Variant = _expect(c, Msg.ERROR, "ERROR server_full")
	assert_eq(err["error"] if err != null else null, Protocol.ERR_SERVER_FULL, "serveur plein")
	_finish()
