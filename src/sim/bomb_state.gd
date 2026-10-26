class_name BombState
extends RefCounted

enum State { PLACED, HELD, FLYING }

var id: int
var owner_id: int
var cell: Vector2i
var fuse := SimConfig.FUSE
var state := State.PLACED
var passable_for: Array[int] = []
