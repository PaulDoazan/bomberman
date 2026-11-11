class_name Prediction
extends RefCounted
# Online: the local player's own moves, shown as soon as they are made instead of a round trip
# later. Each intent sent is numbered and kept; every snapshot says the number of the last one the
# server applied (PlayerState.input_seq). The predicted player is the server's, with the intents
# not applied yet replayed on it. When a snapshot disagrees with what was shown, the gap is
# carried as an offset that fades over a few ticks rather than as a jump.
# Only walking is predicted; while stunned, knocked back, carried, possessed or ejected the
# server's position is shown as is.

const MAX_PENDING := 90 # intents kept, 3 s: more means the server stopped answering
const SNAP_DISTANCE := 1.5 # cells: a bigger gap is shown at once (a respawn, a teleport)
const CORRECTION_KEEP := 0.7 # share of the offset left after each tick

var me: PlayerState = null # the predicted player, null while not predicting
var offset := Vector2.ZERO # shown position minus predicted position, fading
var _seq := 0
var _pending: Array[PlayerIntent] = [] # sent, not yet applied by the server, oldest first

# The number for the next intent sent.
func next_seq() -> int:
	_seq += 1
	return _seq

# Where the player is shown.
func shown_pos() -> Vector2:
	return me.pos + offset

# An intent just sent: kept until the server applies it, and played at once on the prediction.
func record(world: World, intent: PlayerIntent) -> void:
	_pending.append(intent)
	if _pending.size() > MAX_PENDING:
		_pending.pop_front()
	if me != null:
		apply(world, me, intent)
	offset *= CORRECTION_KEEP
	if offset.length() < 0.001:
		offset = Vector2.ZERO

# A snapshot was applied: start again from the server's player and replay what it has not seen.
func reconcile(world: World, server_me: PlayerState) -> void:
	if server_me == null:
		reset()
		return
	var before := shown_pos() if me != null else server_me.pos
	while not _pending.is_empty() and _pending[0].seq <= server_me.input_seq:
		_pending.pop_front()
	if not predictable(server_me):
		me = null
		offset = Vector2.ZERO
		return
	me = _copy(server_me)
	for intent in _pending:
		apply(world, me, intent)
	offset = before - me.pos
	if offset.length() > SNAP_DISTANCE:
		offset = Vector2.ZERO

# A new round or match: nothing sent before applies to it.
func reset() -> void:
	me = null
	offset = Vector2.ZERO
	_pending.clear()

# True when the player only walks (or floats, as a free ghost): moves the client can foresee.
static func predictable(p: PlayerState) -> bool:
	if p.life == PlayerState.Life.GHOST:
		return p.eject_timer <= 0.0 and p.possess_target == -1
	return p.life == PlayerState.Life.ALIVE and p.can_act() and p.knock_timer <= 0.0

# One tick of the player's own movement, as World.step does it.
static func apply(world: World, p: PlayerState, intent: PlayerIntent) -> void:
	if not intent.moving:
		return
	if p.life == PlayerState.Life.GHOST:
		Movement.move_free(world, p, intent.target, SimConfig.GHOST_SPEED, SimConfig.DT)
		return
	if not p.can_act():
		return
	var target := intent.target
	if p.sick == SimConfig.Sick.REVERSE:
		target = p.pos * 2.0 - target
	Movement.move(world, p, target, Items.speed_of(world, p), SimConfig.DT)

static func _copy(p: PlayerState) -> PlayerState:
	var c := PlayerState.new()
	for key in SimCodec.keys_of(PlayerState):
		c.set(key, p.get(key))
	return c
