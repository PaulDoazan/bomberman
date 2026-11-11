class_name Drop
extends RefCounted

# An item on its way to the ground: in a crate coming down under a parachute, or spilt by a
# player who died with Bomb items and flying out to a cell nearby. It lies at cell once landed.
enum Kind { CRATE, SPILL }

var uid := -1 # unique in its World (World.next_uid), so a client keeps the same instance
var kind: int # Kind
var item: int # SimConfig.Item
var from := Vector2.ZERO # where a spilt item flies from
var cell := Vector2i.ZERO
var elapsed := 0.0

func duration() -> float:
	return SimConfig.CRATE_FALL if kind == Kind.CRATE else SimConfig.SPILL_FLIGHT

func progress() -> float:
	return clampf(elapsed / duration(), 0.0, 1.0)
