class_name FlyingObject
extends RefCounted

# Something thrown: a bomb, a player or a block, in flight from `from` to `landing`.
var kind: int # PlayerState.Held
var ref_id := -1 # bomb or player id, -1 for a block
var from := Vector2.ZERO
var landing: Variant = null # Vector2i, or null when the object falls into the water
var to := Vector2.ZERO # centre of the landing cell, or of the first off-map cell (view hint, splash position)
var elapsed := 0.0

func progress() -> float:
	return clampf(elapsed / SimConfig.THROW_FLIGHT, 0.0, 1.0)
