class_name TouchJoystick
extends Control

# Fixed thumb stick for touch screens, like Among Us: a base in the middle of this control and a
# knob that follows the thumb, steering in the direction pushed. Touching anywhere inside the
# control grabs it, so the thumb need not land exactly on the base.

const RADIUS := 90.0
const KNOB_RADIUS := 38.0
const DEAD_ZONE := 0.25 # fraction of RADIUS under which the stick does not steer

var vector := Vector2.ZERO # knob offset as a fraction of RADIUS (length <= 1)
var _index := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _index == -1 and visible and get_global_rect().has_point(t.position):
			_index = t.index
			_follow(t.position)
		elif not t.pressed and t.index == _index:
			_index = -1
			vector = Vector2.ZERO
			queue_redraw()
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _index:
		_follow((event as InputEventScreenDrag).position)

func _follow(at: Vector2) -> void:
	vector = (at - global_position - size * 0.5).limit_length(RADIUS) / RADIUS
	queue_redraw()

# Steering direction on screen (zero inside the dead zone), not normalised.
func direction() -> Vector2:
	return vector if vector.length() >= DEAD_ZONE else Vector2.ZERO

func _draw() -> void:
	var active := _index != -1
	var c := size * 0.5
	draw_circle(c, RADIUS, Color(1, 1, 1, 0.22 if active else 0.15))
	draw_arc(c, RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.6 if active else 0.4), 3.0, true)
	draw_circle(c + vector * RADIUS, KNOB_RADIUS, Color(1, 1, 1, 0.75 if active else 0.5))
