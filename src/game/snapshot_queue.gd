class_name SnapshotQueue
extends RefCounted
# Jitter buffer for the server's snapshots: plays them back one per INTERVAL of local time.
# Playback starts once `depth` snapshots are pending, and `depth` follows the network: 1 (each
# snapshot shown as soon as its turn comes) while they arrive evenly, more when they come late
# or in bursts (a throttled server sends a few at once), judged on the last JITTER_WINDOW
# seconds. Ahead of the depth, playback runs a little faster to catch up; far ahead, it skips.

const INTERVAL := SimConfig.DT * Protocol.SNAPSHOT_EVERY
const MAX_DEPTH := 4
const JITTER_WINDOW := 2.0 # seconds of arrivals the depth is judged on
const SLACK := 0.6 # of an interval: lateness that does not count
const CATCH_UP := 1.1 # playback speed while more than `depth` snapshots wait

var depth := 1 # snapshots pending before playback (re)starts
var _pending: Array[Dictionary] = []
var _playing := false
var _clock := 0.0 # local time since the last snapshot handed out
var _time := 0.0 # local time, advanced by advance()
var _last_arrival := -1.0
var _gaps: Array[Vector2] = [] # (arrival time, gap since the previous one)

func push(data: Dictionary) -> void:
	if _last_arrival >= 0.0:
		_gaps.append(Vector2(_time, _time - _last_arrival))
	_last_arrival = _time
	_pending.append(data)
	_update_depth()

# The snapshot to apply now, or null.
func advance(delta: float) -> Variant:
	_time += delta
	var rate := CATCH_UP if _pending.size() > depth else 1.0
	_clock = minf(_clock + delta * rate, INTERVAL * 2.0) # a long hitch is not caught up in one go
	if _pending.size() > depth + 2:
		_pending = _pending.slice(_pending.size() - depth)
		return _restart()
	if not _playing:
		return _restart() if _pending.size() >= depth else null
	if _clock < INTERVAL:
		return null
	if _pending.is_empty():
		_playing = false # starved: wait for `depth` pending again
		return null
	_clock -= INTERVAL # keep the remainder so playback keeps the server's pace
	return _pending.pop_front()

# Progress from the last snapshot handed out towards the next, in [0, 1].
func alpha() -> float:
	return minf(_clock / INTERVAL, 1.0) if _playing else 1.0

# The largest gap between two arrivals in the window, in intervals, rounded up with some slack:
# arrivals are only seen once per frame, so on a steady network gaps already swing by a frame
# (33 to 50 ms at 60 fps) without deepening the buffer.
func _update_depth() -> void:
	while not _gaps.is_empty() and _time - _gaps[0].x > JITTER_WINDOW:
		_gaps.pop_front()
	var worst := 0.0
	for g in _gaps:
		worst = maxf(worst, g.y)
	depth = clampi(ceili(worst / INTERVAL - SLACK), 1, MAX_DEPTH)

# Hands out the oldest pending snapshot and restarts the clock from it.
func _restart() -> Dictionary:
	_playing = true
	_clock = 0.0
	return _pending.pop_front()
