extends SceneTree
# End-to-end check of an online match, outside the suite (not a test_*.gd file):
#   godot --headless --path . -s res://tests/e2e_online.gd
# With `-- --url=ws://localhost:9080` it targets an already running server instead of its own.
# With `-- --clients=N` (at most 12, the room's limit) N clients play in all: A, B and N-2 bots
# that join a team each (split between the two) and send random moves at 30 Hz, for LOAD_DURATION
# seconds. Every client reports the largest gap between two snapshots it received (jitter).
# A real ServerCore on localhost and two raw WebSocket clients: create, join, two teams, start.
# For DURATION seconds client A sends a moving intent once per sim tick, and each client plays
# the snapshots back as the game does (SnapshotQueue, then SimCodec.apply_match on a mirror).
# Prints PASS or FAIL and quits with 0 or 1.

const Msg := Protocol.Msg
const PORT := 19140
const TIMEOUT := 3.0
const DURATION := 3.0
const LOAD_DURATION := 15.0 # with bots: long enough to read the server's CPU
const MAX_CLIENTS := 12
const PING_EVERY := 2.0 # like the game: the server drops a client silent for 6 s
const MIN_TRAVEL := 0.5 # cells A must have moved, as seen by both mirrors
const MAX_CORRECTION := 0.05 # cells: what A's prediction may be off by, on a local network

class Client:
	var name := ""
	var ws := WebSocketPeer.new()
	var inbox: Array = [] # [type, body] not consumed yet
	var id := -1
	var config: SimConfig = null
	var queue := SnapshotQueue.new()
	var mirror: MatchState = null
	var world_of_round: Dictionary = {} # round -> the World instance seen for it
	var world_swaps := 0 # times the World changed within a round
	var applied := 0
	var a_start := Vector2.INF # A's position in the first snapshot applied
	var last_snapshot := -1.0 # when the last snapshot arrived
	var max_gap := 0.0 # seconds between two snapshots, at most
	var gaps: Array[float] = [] # every gap, for the mean and the 95th percentile
	var target := Vector2.ZERO # bots: where they are heading
	var prediction := Prediction.new() # A: its own moves, as the game predicts them
	var max_correction := 0.0 # cells: the largest gap between prediction and server

var core := ServerCore.new()
var url := "ws://127.0.0.1:%d" % PORT
var external := false # true when a server is already running at url
var clients: Array[Client] = []
var errors: Array[String] = []
var bots: Array[Client] = []
var bot_count := 0
var rng := RandomNumberGenerator.new()

func _init() -> void:
	_run()
	_close_all()
	if errors.is_empty():
		print("PASS")
		quit(0)
	else:
		for e in errors:
			print("  ", e)
		print("FAIL")
		quit(1)

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--url="):
			url = arg.trim_prefix("--url=")
			external = true
		elif arg.begins_with("--clients="):
			bot_count = clampi(arg.trim_prefix("--clients=").to_int(), 2, MAX_CLIENTS) - 2
	if not external and core.listen(PORT) != OK:
		errors.append("le serveur n'écoute pas sur %d" % PORT)
		return
	var a := _connect("A")
	var b := _connect("B")
	if a == null or b == null:
		return
	_send(a, Msg.CREATE, {"name": "Alice", "schema": SimCodec.schema_hash()})
	var welcome_a: Variant = _expect(a, Msg.WELCOME, "WELCOME de A")
	if welcome_a == null:
		return
	a.id = welcome_a["id"]
	_send(b, Msg.JOIN, {"code": welcome_a["code"], "name": "Bob", "token": "", "schema": SimCodec.schema_hash()})
	var welcome_b: Variant = _expect(b, Msg.WELCOME, "WELCOME de B")
	if welcome_b == null:
		return
	b.id = welcome_b["id"]
	for i in bot_count:
		var bot := _connect("Bot %d" % (i + 1))
		if bot == null:
			return
		_send(bot, Msg.JOIN, {"code": welcome_a["code"], "name": bot.name, "token": "", "schema": SimCodec.schema_hash()})
		if _expect(bot, Msg.WELCOME, "WELCOME de " + bot.name) == null:
			return
		bots.append(bot)
	_send(a, Msg.CREATE_TEAM, {"name": "Rouge"})
	_send(a, Msg.CREATE_TEAM, {"name": "Bleu"})
	var two_teams: Variant = _expect(a, Msg.LOBBY, "deux équipes", func(body: Variant) -> bool: return body["teams"].size() == 2)
	if two_teams == null:
		return
	_send(a, Msg.JOIN_TEAM, {"team": two_teams["teams"][0]["id"]})
	_send(b, Msg.JOIN_TEAM, {"team": two_teams["teams"][1]["id"]})
	for i in bots.size():
		_send(bots[i], Msg.JOIN_TEAM, {"team": two_teams["teams"][i % 2]["id"]})
	if _expect(a, Msg.LOBBY, "tout le monde en équipe", func(body: Variant) -> bool:
			return body["can_start"] and (body["players"] as Array).all(
				func(p: Dictionary) -> bool: return p["team"] != -1)) == null:
		return
	_send(a, Msg.START, null)
	for c in [a, b]:
		var lobby: Variant = _expect(c, Msg.LOBBY, "LOBBY playing pour " + c.name,
				func(body: Variant) -> bool: return body["phase"] == "playing")
		if lobby == null:
			return
		c.config = SimCodec.decode_config(lobby["config"])
	_play(a, b)
	_check(a, b)

# The match itself: real time, pumped every few milliseconds like frames.
func _play(a: Client, b: Client) -> void:
	var start := _now()
	var last := start
	var acc := 0.0
	var intents := 0
	var ticks := 0
	var next_ping := start
	var duration := DURATION if bots.is_empty() else LOAD_DURATION
	while _now() - start < duration:
		var now := _now()
		var delta := now - last
		last = now
		_pump(now)
		for c in [a, b]:
			_play_back(c, delta, a.id)
		for bot in bots:
			bot.inbox.clear() # their snapshots only count for the gaps
		if now >= next_ping:
			next_ping = now + PING_EVERY
			for c in clients:
				_send(c, Msg.PING, {"t": now})
		acc += delta
		while acc >= SimConfig.DT:
			acc -= SimConfig.DT
			ticks += 1
			if a.mirror != null and a.mirror.world.players.has(a.id):
				var intent := _towards_centre(a.mirror, a.id)
				intent.seq = a.prediction.next_seq()
				_send(a, Msg.INTENT, Protocol.intent_to_array(intent))
				a.prediction.record(a.mirror.world, intent)
				intents += 1
			for bot in bots:
				_send(bot, Msg.INTENT, Protocol.intent_to_array(_wander(bot, a.mirror, ticks)))
		OS.delay_msec(5)
	print("intents envoyés par A : %d, instantanés appliqués : A %d, B %d" % [intents, a.applied, b.applied])
	print("prédiction de A : plus grande correction %.3f case, %s" % [a.max_correction,
		"active" if a.prediction.me != null else "inactive"])
	var worst: Client = null
	for c in clients:
		if worst == null or c.max_gap > worst.max_gap:
			worst = c
	print("%d clients, plus grand écart entre deux instantanés : %d ms (%s)" % [clients.size(), roundi(worst.max_gap * 1000.0), worst.name])
	var all: Array[float] = []
	for c in clients:
		all.append_array(c.gaps)
	if not all.is_empty():
		all.sort()
		var total := 0.0
		for g in all:
			total += g
		print("écart moyen %d ms, 95e percentile %d ms (%d instantanés)" % [
			roundi(total / all.size() * 1000.0), roundi(all[int(all.size() * 0.95)] * 1000.0), all.size()])

# A bot's random move: a new spot of the arena about once a second.
func _wander(bot: Client, m: MatchState, ticks: int) -> PlayerIntent:
	if ticks % SimConfig.TICK_RATE == 0 or bot.target == Vector2.ZERO:
		var size := Vector2(m.world.arena.width, m.world.arena.height) if m != null else Vector2(13, 11)
		bot.target = Vector2(rng.randf_range(0.0, size.x), rng.randf_range(0.0, size.y))
	var intent := PlayerIntent.new()
	intent.moving = rng.randf() < 0.9
	intent.target = bot.target
	return intent

# What the game does each frame with the snapshots received.
func _play_back(c: Client, delta: float, a_id: int) -> void:
	for msg: Array in c.inbox:
		if msg[0] == Msg.SNAPSHOT:
			c.queue.push(msg[1])
	c.inbox.clear()
	var data: Variant = c.queue.advance(delta)
	if data == null:
		return
	var world_before := c.mirror.world if c.mirror != null else null
	c.mirror = SimCodec.apply_match(data, c.mirror, c.config)
	c.applied += 1
	if c.mirror.world != world_before:
		c.prediction.reset()
	if c.id == a_id:
		c.prediction.reconcile(c.mirror.world, c.mirror.world.players.get(a_id))
		c.max_correction = maxf(c.max_correction, c.prediction.offset.length())
		if OS.get_environment("E2E_TRACE") != "" and c.prediction.offset.length() > 0.02:
			var me: PlayerState = c.mirror.world.players[a_id]
			print("  correction %.3f à %.2f s : accusé %d, %d en attente, serveur %s, vie %d, étourdi %.2f, recul %.2f" % [
				c.prediction.offset.length(), _now(), me.input_seq, c.prediction._pending.size(), me.pos, me.life, me.stun_timer, me.knock_timer])
	var w := c.mirror.world
	var seen: World = c.world_of_round.get(c.mirror.round_number)
	if seen == null:
		c.world_of_round[c.mirror.round_number] = w
	elif seen != w:
		c.world_swaps += 1
	if c.a_start == Vector2.INF and w.players.has(a_id):
		c.a_start = w.players[a_id].pos

static func _towards_centre(m: MatchState, _id: int) -> PlayerIntent:
	var arena := m.world.arena
	var intent := PlayerIntent.new()
	intent.moving = true
	intent.target = Vector2(arena.width, arena.height) * 0.5
	return intent

func _check(a: Client, b: Client) -> void:
	for c in [a, b]:
		if c.mirror == null:
			errors.append("%s n'a appliqué aucun instantané" % c.name)
			continue
		if c.world_swaps > 0:
			errors.append("%s : le World a changé %d fois dans une même manche" % [c.name, c.world_swaps])
		var p: PlayerState = c.mirror.world.players.get(a.id)
		if p == null:
			errors.append("%s ne voit pas A" % c.name)
			continue
		var travel := p.pos.distance_to(c.a_start)
		print("%s voit A passer de %s à %s (%.2f cases), manche %d" % [c.name, c.a_start, p.pos, travel, c.mirror.round_number])
		if c == a and c.max_correction > MAX_CORRECTION:
			errors.append("A : la prédiction a été corrigée de %.2f case" % c.max_correction)
		if travel < MIN_TRAVEL:
			errors.append("%s : A n'a pas assez bougé (%.2f cases)" % [c.name, travel])
	if a.mirror != null and b.mirror != null and a.mirror.round_number != b.mirror.round_number:
		errors.append("manches différentes : A %d, B %d" % [a.mirror.round_number, b.mirror.round_number])

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _connect(name: String) -> Client:
	var c := Client.new()
	c.name = name
	c.ws.connect_to_url(url)
	clients.append(c)
	var end := _now() + TIMEOUT
	while _now() < end:
		_pump(_now())
		if c.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			return c
		OS.delay_msec(5)
	errors.append("délai dépassé : connexion de " + name)
	return null

# Polls the server and every client once, filling the inboxes.
func _pump(now: float) -> void:
	if not external:
		core.poll(now)
	for c in clients:
		c.ws.poll()
		while c.ws.get_available_packet_count() > 0:
			var msg := Protocol.decode(c.ws.get_packet())
			if not msg.is_empty():
				c.inbox.append(msg)
				if msg[0] == Msg.SNAPSHOT:
					if c.last_snapshot >= 0.0:
						c.max_gap = maxf(c.max_gap, now - c.last_snapshot)
						c.gaps.append(now - c.last_snapshot)
					c.last_snapshot = now

# Waits for a message of the given type that satisfies pred; earlier messages are dropped.
func _expect(c: Client, type: int, what: String, pred := Callable()) -> Variant:
	var end := _now() + TIMEOUT
	while _now() < end:
		_pump(_now())
		while not c.inbox.is_empty():
			var msg: Array = c.inbox.pop_front()
			if msg[0] == type and (not pred.is_valid() or pred.call(msg[1])):
				return msg[1]
		OS.delay_msec(5)
	errors.append("délai dépassé : " + what)
	return null

func _send(c: Client, type: int, body: Variant) -> void:
	c.ws.send(Protocol.encode(type, body))

func _close_all() -> void:
	for c in clients:
		c.ws.close()
	var end := _now() + TIMEOUT
	while _now() < end and clients.any(func(c: Client) -> bool:
			return c.ws.get_ready_state() != WebSocketPeer.STATE_CLOSED):
		_pump(_now())
		OS.delay_msec(5)
	if not external:
		core.stop()
