class_name NetClient
extends RefCounted
# A WebSocket to the game server. The free server sleeps when idle and takes about a minute
# to wake, so a failed attempt is retried every RETRY_EVERY seconds until WAKE_TIMEOUT.
# Time is passed in (open, poll) so tests can simulate it.

enum Status { OFFLINE, CONNECTING, WAKING, ONLINE, LOST }

const WAKE_TIMEOUT := 90.0
const RETRY_EVERY := 3.0
const WAKING_AFTER := 3.0 # "the server is waking up" is shown past this delay

signal message(type: int, body: Variant)
signal status_changed(status: int)

var status := Status.OFFLINE
var _ws: WebSocketPeer = null
var _url := ""
var _opened_at := 0.0
var _attempt_at := 0.0

func open(url: String, now: float) -> void:
	close()
	_url = url
	_opened_at = now
	_set_status(Status.CONNECTING)
	_attempt(now)

func poll(now: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if status == Status.ONLINE:
		_receive()
		if _ws != null and state == WebSocketPeer.STATE_CLOSED: # null: closed by a message handler
			_ws = null
			_set_status(Status.LOST)
		return
	if state == WebSocketPeer.STATE_OPEN:
		_set_status(Status.ONLINE)
		_receive()
		return
	if now - _opened_at > WAKE_TIMEOUT:
		_ws.close()
		_ws = null
		_set_status(Status.LOST)
		return
	if status == Status.CONNECTING and now - _opened_at > WAKING_AFTER:
		_set_status(Status.WAKING)
	if state == WebSocketPeer.STATE_CLOSED and now - _attempt_at >= RETRY_EVERY:
		_attempt(now)

# Dropped unless ONLINE: nothing is queued.
func send(type: int, body: Variant) -> void:
	if status == Status.ONLINE:
		_ws.send(Protocol.encode(type, body))

func close() -> void:
	if _ws != null:
		_ws.close()
		_ws = null
	_set_status(Status.OFFLINE)

func _attempt(now: float) -> void:
	_attempt_at = now
	_ws = WebSocketPeer.new()
	_ws.connect_to_url(_url) # on failure the peer stays closed and is retried

func _receive() -> void:
	while _ws != null and _ws.get_available_packet_count() > 0:
		var msg := Protocol.decode(_ws.get_packet())
		if not msg.is_empty():
			message.emit(msg[0], msg[1])

func _set_status(s: Status) -> void:
	if s != status:
		status = s
		status_changed.emit(s)
