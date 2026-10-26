class_name BombState
extends RefCounted

enum State { PLACED, HELD, FLYING }

var id: int
var owner_id: int
var cell: Vector2i
var fuse := SimConfig.FUSE
var state := State.PLACED
var passable_for: Array[int] = []
var roll_dir := Vector2i.ZERO # non-zero while kicked
var roll_offset := 0.0 # in [-0.5, 0.5): position past the cell centre along roll_dir
