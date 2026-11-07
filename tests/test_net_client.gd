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
