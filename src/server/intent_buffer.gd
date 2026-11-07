class_name IntentBuffer
extends RefCounted
# Merges the intents received between two ticks, one per player: one-shot
# presses are kept, struggle is summed, the rest is the latest value.

var _pending: Dictionary = {} # id -> PlayerIntent

func push(id: int, intent: PlayerIntent) -> void:
	var cur: PlayerIntent = _pending.get(id)
	if cur == null:
		cur = PlayerIntent.new()
		_pending[id] = cur
	cur.moving = intent.moving
	cur.target = intent.target
	cur.action_held = intent.action_held
	cur.place_bomb = cur.place_bomb or intent.place_bomb
	cur.action = cur.action or intent.action
	cur.detonate = cur.detonate or intent.detonate
	cur.struggle += intent.struggle

# Returns id -> PlayerIntent for this tick, then clears the one-shot fields so
# a silent player keeps moving/target/action_held.
func take() -> Dictionary:
	var out := {}
	for id: int in _pending:
		var cur: PlayerIntent = _pending[id]
		var copy := PlayerIntent.new()
		copy.moving = cur.moving
		copy.target = cur.target
		copy.action_held = cur.action_held
		copy.place_bomb = cur.place_bomb
		copy.action = cur.action
		copy.detonate = cur.detonate
		copy.struggle = cur.struggle
		out[id] = copy
		cur.place_bomb = false
		cur.action = false
		cur.detonate = false
		cur.struggle = 0.0
	return out
