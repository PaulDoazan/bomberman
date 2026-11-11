class_name IntentBuffer
extends RefCounted
# Each player's intents, played in the order they were sent, so the server takes the same steps
# the player's own prediction did (Prediction). One step per tick: a tick with nothing waiting (a
# late intent) does not move the player, and the step it did not use is a credit spent as soon
# as intents wait, by walking several of them in one tick (PlayerIntent.catch_up). The credit
# keeps a player from walking faster than one step per tick by sending more intents; ticks the
# server skipped after a long stall are granted as credit too. Past MAX_QUEUED still waiting once
# the credit is spent, the oldest are merged into the next: their presses kept, their step lost.

const MAX_QUEUED := 10 # as many as the server catches up after a stall (ServerCore.MAX_CATCH_UP)

var _pending: Dictionary = {} # id -> Array[PlayerIntent], oldest first
var _last: Dictionary = {} # id -> PlayerIntent, the last one played
var _credit: Dictionary = {} # id -> ticks not used for a step: at most MAX_QUEUED, or more when granted

func push(id: int, intent: PlayerIntent) -> void:
	if not _pending.has(id):
		_pending[id] = []
	(_pending[id] as Array).append(intent)

# Returns id -> PlayerIntent for this tick.
func take() -> Dictionary:
	var out := {}
	for id: int in _pending:
		var queue: Array = _pending[id]
		var before: int = _credit.get(id, 0)
		var credit := before + 1 # this tick's step
		if queue.is_empty():
			if _last.has(id):
				out[id] = _waiting(_last[id])
		else:
			var head: PlayerIntent = queue.pop_front()
			credit -= 1
			while credit > 0 and not queue.is_empty():
				var next: PlayerIntent = queue.pop_front()
				credit -= 1
				_merge_into(head, next)
				head.catch_up.append(next)
				head.action_held = next.action_held
				head.seq = next.seq
			_last[id] = head
			out[id] = head
		while queue.size() > MAX_QUEUED:
			_merge_into(queue[1], queue[0])
			queue.pop_front()
		_credit[id] = mini(credit, maxi(before, MAX_QUEUED)) # waiting adds up to MAX_QUEUED at most
	return out

# Ticks the server skipped (it fell too far behind): steps everyone may still take.
func grant(ticks: int) -> void:
	for id: int in _pending:
		_credit[id] = mini(_credit.get(id, 0) + ticks, MAX_QUEUED * 3)

# A player who left or dropped out: their last continuous intent must not keep them moving.
func forget(id: int) -> void:
	_pending.erase(id)
	_last.erase(id)
	_credit.erase(id)

# A new match or round starts from nobody moving.
func clear() -> void:
	_pending.clear()
	_last.clear()
	_credit.clear()

# The other intent's presses carried into this one.
static func _merge_into(into: PlayerIntent, other: PlayerIntent) -> void:
	into.place_bomb = into.place_bomb or other.place_bomb
	into.action = into.action or other.action
	into.detonate = into.detonate or other.detonate
	into.struggle += other.struggle

# A tick without a new intent: no step (it comes late, as a catch-up), the button still held.
static func _waiting(last: PlayerIntent) -> PlayerIntent:
	var i := PlayerIntent.new()
	i.late = true
	i.moving = last.moving
	i.target = last.target
	i.action_held = last.action_held
	i.seq = last.seq
	return i
