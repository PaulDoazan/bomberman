class_name InputController
extends Node

var _bomb_pressed := false
var _action_pressed := false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("place_bomb"):
		_bomb_pressed = true
	if event.is_action_pressed("action"):
		_action_pressed = true

func consume_intent(p: PlayerState, rig: CameraRig) -> PlayerIntent:
	var intent := PlayerIntent.new()
	intent.moving = Input.is_action_pressed("move")
	var plane_h2 := 0
	var arena: Arena = rig.arena_ref
	if arena != null and arena.in_bounds(p.cell()):
		plane_h2 = arena.h2_at(p.cell())
	if p.life == PlayerState.Life.GHOST:
		plane_h2 += 3 # 1.5 above the cell
	var hit: Variant = rig.mouse_to_tile(rig.get_viewport().get_mouse_position(), plane_h2)
	if hit == null:
		intent.moving = false
	else:
		intent.target = hit
	intent.place_bomb = _bomb_pressed
	intent.action = _action_pressed
	_bomb_pressed = false
	_action_pressed = false
	return intent
