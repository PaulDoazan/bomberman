class_name TeamColors
extends RefCounted

# One base colour per team, in the order teams are numbered: red, blue, green, yellow.
const BASES: Array[Color] = [Color("e6194b"), Color("4363d8"), Color("3cb44b"), Color("ffe119")]
const LABELS := ["Rouge", "Bleu", "Vert", "Jaune"]

# Members of a team share the base hue. Each one takes a cell of a grid over value (darker
# by column) and saturation (paler by row), so no two teammates look alike. Only darker
# steps are used, since yellow is already at full value.
const GRID_COLUMNS := 4
const VALUE_STEP := 0.08
const SATURATION_STEP := 0.15

# Tint of a team member: the first member keeps the base colour.
static func tint(color_index: int, member_index: int, member_count: int) -> Color:
	assert(member_index >= 0 and member_index < member_count)
	var base := BASES[color_index]
	if member_index == 0:
		return base
	var column := member_index % GRID_COLUMNS
	var row := member_index / GRID_COLUMNS
	var v := clampf(base.v - column * VALUE_STEP, 0.0, 1.0)
	var s := clampf(base.s - row * SATURATION_STEP, 0.0, 1.0)
	return Color.from_hsv(base.h, s, v)

# First team index not in used, or -1 when all are taken.
static func free_index(used: Array[int]) -> int:
	for i in BASES.size():
		if not used.has(i):
			return i
	return -1
