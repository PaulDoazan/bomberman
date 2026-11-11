class_name Prediction
extends RefCounted
# Online: everything the local player does shows at once instead of a round trip later (walking,
# bombs, picking up, throwing, kicking, detonating). The client's mirror of the match is the
# server's last snapshot moved forward by the local player's intents the server has not applied
# yet, through the same simulation (World.step): its bombs tick, explode and roll on time.
# Each intent sent is numbered and kept; every snapshot says the number of the last one the server
# applied (PlayerState.input_seq). After a snapshot the mirror replays the intents still pending,
# and every local tick steps it once more with the new intent.
# The other players stay as the server last showed them (their intents are not known here): a
# predicted step neither moves, hurts nor kills them, except a player the local one carries or
# possesses. Where the server ends up disagreeing about the local player's position, the gap is
# shown as an offset that fades over a few ticks rather than as a jump.

const MAX_PENDING := 90 # intents kept, 3 s: more means the server stopped answering
const SNAP_DISTANCE := 1.5 # cells: a bigger gap is shown at once (a respawn, a throw)
const CORRECTION_KEEP := 0.7 # share of the offset left after each tick

var offset := Vector2.ZERO # shown position minus simulated position of the local player, fading
var _seq := 0
var _pending: Array[PlayerIntent] = [] # sent, not yet applied by the server, oldest first
var _others: Dictionary = {} # id -> the other players' state in the last snapshot
var _finished := false # the round's end in the last snapshot: only the server ends a round
var _winners: Array[int] = []

# The number for the next intent sent.
func next_seq() -> int:
	_seq += 1
	return _seq

# A new round or match: nothing sent before applies to it.
func reset() -> void:
	offset = Vector2.ZERO
	_pending.clear()
	_others.clear()

func pending_count() -> int:
	return _pending.size()

# m was just set to the server's snapshot: drop the intents it has applied, replay the others.
# shown_before: where the local player was shown just before (INF when nowhere).
func on_snapshot(m: MatchState, my_id: int, shown_before: Vector2) -> void:
	var w := m.world
	var me: PlayerState = w.players.get(my_id)
	if me != null:
		while not _pending.is_empty() and _pending[0].seq <= me.input_seq:
			_pending.pop_front()
	_others.clear()
	_finished = w.finished
	_winners.assign(w.winners)
	for id: int in w.players:
		if id != my_id:
			_others[id] = SimCodec.values_of(w.players[id], PlayerState)
	for intent in _pending:
		_step(m, my_id, intent)
	me = w.players.get(my_id)
	if me == null or shown_before == Vector2.INF:
		offset = Vector2.ZERO
		return
	offset = shown_before - me.pos
	if offset.length() > SNAP_DISTANCE:
		offset = Vector2.ZERO

# An intent just sent: kept until the server applies it, and played at once.
func record(m: MatchState, my_id: int, intent: PlayerIntent) -> void:
	_pending.append(intent)
	if _pending.size() > MAX_PENDING:
		_pending.pop_front()
	_step(m, my_id, intent)
	offset *= CORRECTION_KEEP
	if offset.length() < 0.001:
		offset = Vector2.ZERO

func _step(m: MatchState, my_id: int, intent: PlayerIntent) -> void:
	var w := m.world
	if m.phase != MatchState.Phase.PLAYING or w.finished or not w.players.has(my_id):
		return
	w.step({my_id: intent})
	for id: int in _others:
		var p: PlayerState = w.players.get(id)
		if p != null and p.carried_by != my_id and p.possessed_by != my_id:
			SimCodec.set_values(p, PlayerState, _others[id])
	w.finished = _finished
	w.winners.assign(_winners)
