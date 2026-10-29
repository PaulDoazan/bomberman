class_name PlayerState
extends RefCounted

enum Life { ALIVE, WAITING_RESPAWN, GHOST }
enum Held { NONE, BOMB, PLAYER, BLOCK, ITEM } # ITEM: a skull, held_id its SimConfig.Item

var id: int
var pos: Vector2
var facing := Vector2i(0, 1)
var aim := Vector2i(0, 1) # like facing but in 8 directions: where throws go and the body looks
var lives: int
var life := Life.ALIVE
var respawn_timer := 0.0
var invulnerable_timer := 0.0
var stun_timer := 0.0
var knock_dir := Vector2.ZERO # unit direction of the knock-back after a bomb hit
var knock_timer := 0.0
var push_timer := 0.0 # time spent pushing against a bomb, for kicking
var death_cause := "" # cause of the last death
var held := Held.NONE
var held_id := -1
var carried_by := -1
var carried_timer := 0.0
var possessed_by := -1
var possess_target := -1
var possess_timer := 0.0
var possess_cooldown := 0.0
var eject_dir := Vector2.ZERO # a ghost thrown off its victim flies this way
var eject_timer := 0.0
var died_tick := -1
var kick_tick := -1 # tick of the last kick, for the view
var kick_underfoot := false # the last kick sent off the bomb the player stood on
var throw_tick := -1 # tick of the last throw, for the view
# Items picked up: they last the round, except Remote and the sickness, lost with a life.
var fire := 1 # power level of the bombs placed
var max_bombs := SimConfig.MAX_BOMBS
var power := false # blasts go through blocks
var remote := false # bombs wait for the detonate button
var heart := false # survives one blast
var sick := SimConfig.Sick.NONE
var sick_timer := 0.0

func cell() -> Vector2i:
	return Arena.cell_of(pos)

func is_alive() -> bool:
	return life != Life.GHOST

func can_act() -> bool:
	return life == Life.ALIVE and carried_by == -1 and stun_timer <= 0.0 and possessed_by == -1
