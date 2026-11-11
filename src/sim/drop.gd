class_name Drop
extends RefCounted

# An item on its way to the ground, in a crate coming down under a parachute. It lies at cell
# once landed.
var item: int # SimConfig.Item
var cell := Vector2i.ZERO
var elapsed := 0.0

func duration() -> float:
	return SimConfig.CRATE_FALL

func progress() -> float:
	return clampf(elapsed / duration(), 0.0, 1.0)
