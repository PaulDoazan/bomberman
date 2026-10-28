class_name BombButton
extends Control

# On-screen bomb button for touch screens, drawn as a bomb with its fuse. The input controller
# reads the touches on it; this control only draws, and stops the emulated mouse click.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _draw() -> void:
	var r := minf(size.x, size.y) * 0.36
	var c := Vector2(size.x * 0.46, size.y * 0.56)
	var up := Vector2(0.6, -0.8) # fuse direction, towards the top right
	# Fuse cap, fuse and spark.
	var cap := c + up * r * 0.92
	draw_line(cap, cap + up * r * 0.22, Color("6b6b6b"), r * 0.34)
	var tip := cap + up * r * 0.22 + Vector2(r * 0.3, -r * 0.18)
	draw_line(cap + up * r * 0.2, tip, Color("c9a26b"), r * 0.08, true)
	for i in 8:
		var a := TAU * i / 8.0
		draw_line(tip, tip + Vector2(cos(a), sin(a)) * r * (0.22 if i % 2 == 0 else 0.13), Color("ffb02e"), r * 0.06, true)
	draw_circle(tip, r * 0.08, Color("fff3b0"))
	# Body, with a shine.
	draw_circle(c, r, Color("161616"))
	draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 3.0, true)
	draw_circle(c + Vector2(-0.38, -0.38) * r, r * 0.18, Color(1, 1, 1, 0.55))
