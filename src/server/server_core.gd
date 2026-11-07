class_name ServerCore
extends RefCounted
# The authoritative game server without nodes: accepts WebSocket peers, routes their messages
# to the rooms, ticks the rooms at SimConfig.TICK_RATE and broadcasts lobbies and snapshots.

signal logged(text: String)

const MAX_ROOMS := 20
const SNAPSHOT_EVERY := 2
const MAX_CATCH_UP := 4 # ticks run in one poll at most; the rest of the backlog is dropped
# Flood guard, a token bucket per peer: a burst of FLOOD_BURST messages, refilled at
# FLOOD_RATE per second. Honest clients send about 31 a second (intents and pings), and a
# network or server stall delivering seconds of backlog at once stays within the burst.
const FLOOD_BURST := 200.0
const FLOOD_RATE := 60.0
const CLOSE_TIMEOUT := 5.0 # seconds a closed peer may take to finish the close handshake

const Msg := Protocol.Msg

class Peer:
	var ws := WebSocketPeer.new()
	var room_code := "" # "" until CREATE or JOIN succeeds
	var player_id := -1
	var unbound_since := 0.0 # when it connected or left its room
	var budget := FLOOD_BURST
	var budget_at := 0.0
	var dropped := false # closing: whatever it still sends is ignored
	var dropped_at := 0.0

var rooms: Dictionary = {} # code -> Room
var max_peers := 300 # connections beyond that are refused
var join_timeout := 10.0 # seconds a peer may stay without a room before it is dropped

var _tcp := TCPServer.new()
var _peers: Array[Peer] = []
var _intents: Dictionary = {} # code -> IntentBuffer
var _rng := RandomNumberGenerator.new()
var _last_now := -1.0
var _accumulator := 0.0
var _tick_count := 0
var _lobby_hashes: Dictionary = {} # code -> hash of the last LOBBY sent

func _init() -> void:
	_rng.randomize()

func listen(port: int) -> Error:
	return _tcp.listen(port)

func poll(now: float) -> void:
	_accept(now)
	for peer: Peer in _peers.duplicate():
		_poll_peer(peer, now)
	if _last_now < 0.0:
		_last_now = now
	_accumulator += now - _last_now
	_last_now = now
	var steps := 0
	while _accumulator >= SimConfig.DT and steps < MAX_CATCH_UP:
		_accumulator -= SimConfig.DT
		steps += 1
		_tick_rooms(now)
	if _accumulator >= SimConfig.DT:
		_accumulator = 0.0

func stop() -> void:
	for peer in _peers:
		peer.ws.close()
		peer.ws.poll()
	_peers.clear()
	_tcp.stop()

func _accept(now: float) -> void:
	while _tcp.is_connection_available():
		var conn := _tcp.take_connection()
		if _peers.size() >= max_peers:
			conn.disconnect_from_host()
			continue
		var peer := Peer.new()
		peer.unbound_since = now
		peer.budget_at = now
		if peer.ws.accept_stream(conn) == OK:
			_peers.append(peer)

func _poll_peer(peer: Peer, now: float) -> void:
	peer.ws.poll()
	var state := peer.ws.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED or (peer.dropped and now - peer.dropped_at >= CLOSE_TIMEOUT):
		_leave_room(peer, now)
		_peers.erase(peer)
		return
	if not peer.dropped and peer.room_code == "" and now - peer.unbound_since >= join_timeout:
		_drop(peer, now)
		return
	while not peer.dropped and peer.ws.get_available_packet_count() > 0:
		var bytes := peer.ws.get_packet()
		if _flooding(peer, now):
			logged.emit("Connexion coupée : trop de messages")
			_drop(peer, now)
			return
		var msg := Protocol.decode(bytes)
		if not msg.is_empty():
			_handle(peer, msg[0], msg[1], now)

func _flooding(peer: Peer, now: float) -> bool:
	peer.budget = minf(FLOOD_BURST, peer.budget + (now - peer.budget_at) * FLOOD_RATE)
	peer.budget_at = now
	if peer.budget < 1.0:
		return true
	peer.budget -= 1.0
	return false

# Detaches the peer from its room (a disconnection) and closes its socket.
func _drop(peer: Peer, now: float) -> void:
	_leave_room(peer, now)
	_close(peer, now)

# Closes the socket; the peer is forgotten once closed, or after CLOSE_TIMEOUT at the latest.
func _close(peer: Peer, now: float) -> void:
	peer.dropped = true
	peer.dropped_at = now
	peer.ws.close()

func _handle(peer: Peer, type: int, body: Variant, now: float) -> void:
	if type == Msg.PING:
		_send(peer, Msg.PONG, body)
		return
	if peer.room_code == "":
		if type == Msg.CREATE:
			_create(peer, body, now)
		elif type == Msg.JOIN:
			_join(peer, body, now)
		return # anything else before joining is ignored
	var room: Room = rooms.get(peer.room_code)
	if room == null:
		peer.room_code = ""
		return
	var id := peer.player_id
	var d: Dictionary = body if body is Dictionary else {}
	var err := Protocol.ERR_NOT_NOW
	match type:
		Msg.CREATE, Msg.JOIN:
			pass # already in a room
		Msg.CREATE_TEAM:
			if d.get("name") is String:
				err = room.create_team(id, d["name"])
		Msg.JOIN_TEAM:
			if d.get("team") is int:
				err = room.join_team(id, d["team"])
		Msg.LEAVE_TEAM:
			err = room.leave_team(id)
		Msg.SETTINGS:
			if d.get("config") is Dictionary:
				err = room.set_config(id, SimCodec.decode_config(d["config"]))
		Msg.START:
			err = room.start(id)
			if err == "":
				_intents[peer.room_code].clear()
		Msg.TO_LOBBY:
			err = room.back_to_lobby(id)
		Msg.INTENT:
			var intent := Protocol.intent_from_array(body)
			if intent == null:
				_send_error(peer, Protocol.ERR_NOT_NOW)
			elif room.in_match(id):
				_intents[peer.room_code].push(id, intent)
			return
		Msg.LEAVE:
			_leave_room(peer, now)
			return
		_:
			return # a server-to-client type: ignored
	if err == "":
		_broadcast_lobby(room)
	else:
		_send_error(peer, err)

func _create(peer: Peer, body: Variant, now: float) -> void:
	if not (body is Dictionary and body.get("name") is String and body.get("schema") is int):
		_send_error(peer, Protocol.ERR_NOT_NOW)
		return
	if body["schema"] != SimCodec.schema_hash():
		_send_error(peer, Protocol.ERR_VERSION)
		return
	if rooms.size() >= MAX_ROOMS:
		_send_error(peer, Protocol.ERR_SERVER_FULL)
		return
	var room_rng := RandomNumberGenerator.new()
	room_rng.seed = _rng.randi()
	var room := Room.new(RoomCodes.generate(_rng, rooms), room_rng)
	# The room only exists once somebody is in it, so is_dead() can remove it later.
	var result := room.join(body["name"], "", now)
	if result.has("error"):
		_send_error(peer, result["error"])
		return
	rooms[room.code] = room
	_intents[room.code] = IntentBuffer.new()
	logged.emit("Partie %s créée (%d en cours)" % [room.code, rooms.size()])
	_welcome(peer, room, result)

func _join(peer: Peer, body: Variant, now: float) -> void:
	if not (body is Dictionary and body.get("code") is String and body.get("name", "") is String
			and body.get("token", "") is String and body.get("schema") is int):
		_send_error(peer, Protocol.ERR_NOT_NOW)
		return
	if body["schema"] != SimCodec.schema_hash():
		_send_error(peer, Protocol.ERR_VERSION)
		return
	var room: Room = rooms.get(RoomCodes.normalize(body["code"]))
	if room == null:
		_send_error(peer, Protocol.ERR_UNKNOWN_CODE)
		return
	var result := room.join(body.get("name", ""), body.get("token", ""), now)
	if result.has("error"):
		_send_error(peer, result["error"])
		return
	# A reconnection: the socket still holding this player is closed, without disconnecting them.
	for other in _peers:
		if other != peer and other.room_code == room.code and other.player_id == result["id"]:
			other.room_code = ""
			_close(other, now)
	_welcome(peer, room, result)

func _welcome(peer: Peer, room: Room, result: Dictionary) -> void:
	peer.room_code = room.code
	peer.player_id = result["id"]
	_send(peer, Msg.WELCOME, {"code": room.code, "id": result["id"], "token": result["token"]})
	_broadcast_lobby(room)
	logged.emit("%s arrive dans %s" % [room.players[peer.player_id].name, room.code])

func _leave_room(peer: Peer, now: float) -> void:
	if peer.room_code == "":
		return
	var room: Room = rooms.get(peer.room_code)
	peer.room_code = ""
	peer.unbound_since = now
	if room == null:
		return
	room.disconnect_player(peer.player_id, now)
	_intents[room.code].forget(peer.player_id)
	var p: Room.RoomPlayer = room.players.get(peer.player_id)
	logged.emit("%s quitte %s" % [p.name if p != null else "?", room.code])
	_broadcast_lobby(room)

func _tick_rooms(now: float) -> void:
	_tick_count += 1
	for code: String in rooms.keys():
		var room: Room = rooms[code]
		var before := room.phase
		var round_before := room.match_state.round_number if room.match_state != null else -1
		room.tick(now, _intents[code].take())
		if room.match_state != null and room.match_state.round_number != round_before:
			_intents[code].clear() # nobody carries a move or a held action into the new round
		# Changes made by the tick itself (players forgotten, host re-elected) are checked once a second.
		if room.phase != before or (_tick_count % SimConfig.TICK_RATE == 0 and _lobby_changed(room)):
			_broadcast_lobby(room)
		if room.phase == Room.Phase.PLAYING and room.match_state != null and _tick_count % SNAPSHOT_EVERY == 0:
			_broadcast(code, Protocol.encode(Msg.SNAPSHOT, SimCodec.encode_match(room.match_state)))
		if room.is_dead(now):
			rooms.erase(code)
			_intents.erase(code)
			_lobby_hashes.erase(code)
			logged.emit("Partie %s supprimée (%d en cours)" % [code, rooms.size()])

func _broadcast_lobby(room: Room) -> void:
	var state := room.lobby_state()
	_lobby_hashes[room.code] = hash(var_to_bytes(state))
	_broadcast(room.code, Protocol.encode(Msg.LOBBY, state))

func _lobby_changed(room: Room) -> bool:
	return hash(var_to_bytes(room.lobby_state())) != _lobby_hashes.get(room.code)

# Sends the same encoded message to every open peer of the room, spectators included.
func _broadcast(code: String, bytes: PackedByteArray) -> void:
	for peer in _peers:
		if peer.room_code == code and peer.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			peer.ws.send(bytes)

func _send(peer: Peer, type: int, body: Variant) -> void:
	if peer.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		peer.ws.send(Protocol.encode(type, body))

func _send_error(peer: Peer, err: String) -> void:
	_send(peer, Msg.ERROR, {"error": err})
