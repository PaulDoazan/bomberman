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
