extends TestCase

func _click(pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	return e

# A left click consumed by a GUI control (Quitter, end-of-round panel) never reaches
# _unhandled_input: the player must not move even though the button is held.
func test_click_held_over_gui_does_not_move() -> void:
	var c := InputController.new()
	Input.action_press("move")
	assert_false(c.wants_move(), "clic pris par l'interface")
	Input.action_release("move")
	c.free()

func test_click_on_world_moves_until_release() -> void:
	var c := InputController.new()
	Input.action_press("move")
	c._unhandled_input(_click(true))
	assert_true(c.wants_move(), "clic sur le monde")
	c._unhandled_input(_click(false))
	assert_false(c.wants_move(), "relâché")
	c._unhandled_input(_click(true))
	Input.action_release("move") # released over a control: the release event never arrives
	assert_false(c.wants_move(), "relâché au-dessus de l'interface")
	c.free()

func test_arrow_keys_steer_ahead_of_player() -> void:
	var ic := InputController.new()
	var p := PlayerState.new()
	p.pos = Vector2(4.5, 6.5)
	Input.action_press("move_up")
	Input.action_press("move_right")
	var intent: PlayerIntent = ic.consume_intent(p, null)
	Input.action_release("move_up")
	Input.action_release("move_right")
	ic.free()
	assert_true(intent.moving)
	var d := (intent.target - p.pos).normalized()
	assert_almost(d.x, sqrt(0.5)); assert_almost(d.y, -sqrt(0.5))

func test_arrow_presses_and_mouse_shaking_count_as_struggle() -> void:
	var ic := InputController.new()
	var p := PlayerState.new()
	for i in 3:
		var e := InputEventAction.new()
		e.action = "move_left"
		e.pressed = true
		ic._input(e)
	var m := InputEventMouseMotion.new()
	m.relative = Vector2(InputController.MOUSE_SHAKE_PX * 2.5, 0.0)
	ic._input(m)
	Input.action_press("move_right") # flèche tenue : pas besoin de caméra pour viser
	var intent: PlayerIntent = ic.consume_intent(p, null)
	var next: PlayerIntent = ic.consume_intent(p, null)
	Input.action_release("move_right")
	ic.free()
	assert_almost(intent.struggle, 5.0, 0.001, "3 appuis + 2 secousses")
	assert_almost(next.struggle, 0.0, 0.001, "remis à zéro")
