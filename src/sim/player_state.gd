class_name PlayerState
extends RefCounted

enum Life { ALIVE, WAITING_RESPAWN, GHOST }
enum Held { NONE, BOMB, PLAYER, BLOCK }

var id: int
var pos: Vector2
var facing := Vector2i(0, 1)
var aim := Vector2i(0, 1) # like facing but in 8 directions: where throws go and the body looks
var lives: int
var life := Life.ALIVE
var respawn_timer := 0.0
var invulnerable_timer := 0.0
var stun_timer := 0.0
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
var died_tick := -1

func cell() -> Vector2i:
	return Arena.cell_of(pos)

func is_alive() -> bool:
	return life != Life.GHOST

func can_act() -> bool:
	return life == Life.ALIVE and carried_by == -1 and stun_timer <= 0.0 and possessed_by == -1
