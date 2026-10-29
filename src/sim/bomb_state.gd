class_name BombState
extends RefCounted

enum State { PLACED, HELD, FLYING }

var id: int
var owner_id: int
var cell: Vector2i
var fuse := SimConfig.FUSE
var state := State.PLACED
var passable_for: Array[int] = []
var roll_dir := Vector2i.ZERO # non-zero while kicked: the way it is going now, 8 directions
var roll_heading := Vector2i.ZERO # direction it was kicked in; roll_dir leaves it to slide along walls
var level := 1 # power level from its placer's Fire
var pump := 0 # pumps while held, each adding a level
var pierce := false # placed with Power: its blast goes through blocks
var remote := false # its fuse does not burn: it waits for its owner's detonate button
var disguised := false # placed with the Disguise sickness: a pumped bomb's power, a plain look
var offset := Vector2.ZERO # from its cell centre: a bomb is exactly where it was placed or rolled

# Where the bomb is on the grid plane.
func pos() -> Vector2:
	return Arena.center_of(cell) + offset
