class_name SnapshotQueue
extends RefCounted
# Jitter buffer for the server's snapshots: plays them back one per INTERVAL of local time,
# one snapshot behind the newest so a late packet does not stall the picture. Starts once one
# is ahead, drops the backlog past MAX_BACKLOG, and starts over (waits for one ahead) when it
# runs dry.

const INTERVAL := SimConfig.DT * 2 # the server sends one every 2 ticks
const MAX_BACKLOG := 3

var _pending: Array[Dictionary] = []
var _playing := false
var _clock := 0.0 # local time since the last snapshot handed out

func push(data: Dictionary) -> void:
	_pending.append(data)

# The snapshot to apply now, or null.
func advance(delta: float) -> Variant:
	_clock = minf(_clock + delta, INTERVAL * 2.0) # a long hitch is not caught up in one go
	if _pending.size() > MAX_BACKLOG:
		_pending = _pending.slice(_pending.size() - 2)
		return _restart()
	if not _playing:
		return _restart() if _pending.size() >= 2 else null
	if _clock < INTERVAL:
		return null
	if _pending.is_empty():
		_playing = false # starved: wait for one ahead again
		return null
	_clock -= INTERVAL # keep the remainder so playback keeps the server's pace
	return _pending.pop_front()

# Progress from the last snapshot handed out towards the next, in [0, 1].
func alpha() -> float:
	return minf(_clock / INTERVAL, 1.0) if _playing else 1.0

# Hands out the oldest pending snapshot and restarts the clock from it.
func _restart() -> Dictionary:
	_playing = true
	_clock = 0.0
	return _pending.pop_front()
