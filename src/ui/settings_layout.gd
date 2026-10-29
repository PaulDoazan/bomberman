class_name SettingsLayout
extends RefCounted

# How the settings page fits the screen: two columns side by side on a landscape screen, one
# zoomed column on a portrait one.

const COLUMN_WIDTH := 600.0 # a column, and the narrowest width a page is laid out for
const BASE_SIZE := Vector2(1280, 720) # the project's viewport size
const SIDE_BY_SIDE_HEIGHT := 540.0 # height of the page laid out in two columns

# The viewport size at zoom 1 for a window of this size (the project stretches BASE_SIZE to fit).
static func _view(window: Vector2) -> Vector2:
	return window / minf(window.x / BASE_SIZE.x, window.y / BASE_SIZE.y)

# Two columns side by side on a landscape screen with room for them, else one.
static func columns_for(window: Vector2) -> int:
	if window.x <= 0.0 or window.y <= 0.0:
		return 2
	var view := _view(window)
	return 2 if window.x > window.y and view.x >= 2.0 * COLUMN_WIDTH else 1

# Zoom for a window of this size: how many times the columns fit across the width the
# viewport has at zoom 1, no more than the height allows for a usable page.
static func zoom_for(window: Vector2) -> float:
	if window.x <= 0.0 or window.y <= 0.0:
		return 1.0
	var view := _view(window)
	var columns := columns_for(window)
	var height := SIDE_BY_SIDE_HEIGHT if columns == 2 else BASE_SIZE.y
	return maxf(1.0, minf(view.x / (columns * COLUMN_WIDTH), view.y / height))
