class_name InputController
extends Node

var _bomb_pressed := false
var _action_pressed := false
# Latched from _unhandled_input so a click taken by a GUI control (Quitter, end-of-round panel)
# never steers the player.
var _move_held := false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("move"):
		_move_held = true
	elif event.is_action_released("move"):
		_move_held = false
	if event.is_action_pressed("place_bomb"):
		_bomb_pressed = true
	if event.is_action_pressed("action"):
		_action_pressed = true

func wants_move() -> bool:
	# A release over a GUI control never reaches _unhandled_input: also check the button state.
	if not Input.is_action_pressed("move"):
		_move_held = false
	return _move_held

# Arrow keys steer towards a point a little ahead of the player; they take priority over the mouse.
const KEY_LOOKAHEAD := 2.0

func consume_intent(p: PlayerState, rig: CameraRig) -> PlayerIntent:
	var intent := PlayerIntent.new()
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir != Vector2.ZERO:
		intent.moving = true
		intent.target = p.pos + dir.normalized() * KEY_LOOKAHEAD
		_consume_buttons(intent)
		return intent
	intent.moving = wants_move()
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
	_consume_buttons(intent)
	return intent

func _consume_buttons(intent: PlayerIntent) -> void:
	intent.place_bomb = _bomb_pressed
	intent.action = _action_pressed
	_bomb_pressed = false
	_action_pressed = false
