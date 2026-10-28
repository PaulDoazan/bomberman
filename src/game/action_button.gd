class_name ActionButton
extends Control

# On-screen pick up / throw button for touch screens: one button for both, labelled with what
# a tap will do. The input controller reads the touches on it; this control only draws, and
# stops the emulated mouse click.

var holding := false:
	set(v):
		if v != holding:
			holding = v
			queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _draw() -> void:
	var r := minf(size.x, size.y) * 0.46
	var c := size * 0.5
	draw_circle(c, r, Color(0.95, 0.55, 0.15, 0.85) if holding else Color(0.2, 0.45, 0.85, 0.85))
	draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.6), 3.0, true)
	var font := get_theme_default_font()
	var text := "LANCER" if holding else "PRENDRE"
	var font_size := int(r * 0.42)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	draw_string(font, c + Vector2(-w * 0.5, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
