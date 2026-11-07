class_name SettingsScreen
extends Control

# Game setup, built for touch as much as for the mouse: big − / + steppers, the map sizes as
# buttons, a switch per item. A landscape screen shows the game and the items side by side; a
# portrait one stacks them in a column that scrolls, the whole page zoomed so it fills the width.
# The zoom is undone when the game starts.

const HOME_SCENE := "res://src/ui/home_screen.tscn"

var form: SettingsForm
var play_button: Button
var back_button: Button

func _ready() -> void:
	theme = Theme.new()
	theme.default_font_size = 22
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.16, 0.24)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	center.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)

	var title := Label.new()
	title.text = "Bomberman"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	page.add_child(title)
	form = SettingsForm.new(Session.config, true)
	page.add_child(form)

	play_button = Button.new()
	play_button.text = "Jouer"
	play_button.custom_minimum_size = Vector2(0, 64)
	play_button.add_theme_font_size_override("font_size", 28)
	play_button.pressed.connect(_on_play)
	for state in ["normal", "hover", "pressed"]:
		SettingsForm.accent(play_button, state)
	page.add_child(play_button)

	# Back to the home screen, once it exists.
	back_button = Button.new()
	back_button.text = "Retour"
	back_button.custom_minimum_size = Vector2(0, SettingsForm.ROW_HEIGHT)
	back_button.visible = ResourceLoader.exists(HOME_SCENE)
	back_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(HOME_SCENE))
	page.add_child(back_button)

	get_viewport().size_changed.connect(_fit)
	_fit()

func _exit_tree() -> void:
	get_viewport().size_changed.disconnect(_fit) # or unzooming would zoom again
	get_tree().root.content_scale_factor = 1.0 # the game lays itself out unzoomed

# Zooms the page so the column fills a narrow screen; wide screens stay at 1.
func _fit() -> void:
	var window := Vector2(DisplayServer.window_get_size())
	form.columns = SettingsLayout.columns_for(window)
	get_tree().root.content_scale_factor = SettingsLayout.zoom_for(window)

func _on_play() -> void:
	Session.config = form.build_config()
	get_tree().change_scene_to_file("res://src/game/game.tscn")
