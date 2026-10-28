extends TestCase

# A player blown up leaves a black body on screen for a few seconds; other deaths do not.
func test_burnt_body_stays_then_disappears() -> void:
	var ms := MatchState.new(SimConfig.new(), RandomNumberGenerator.new())
	var view := ActorsView.new()
	view._ready()
	view.sync(ms.world, ms)
	assert_eq(view._corpses.size(), 0, "pas de corps au départ")
	ms.world.kill(0, "explosion")
	view.sync(ms.world, ms)
	assert_eq(view._corpses.size(), 1, "corps calciné")
	ms.world.kill(1, "drown")
	view.sync(ms.world, ms)
	assert_eq(view._corpses.size(), 1, "pas de corps pour une noyade")
	for _t in roundi(ActorsView.CORPSE_TIME * 30):
		view.sync(ms.world, ms)
	assert_eq(view._corpses.size(), 0, "le corps disparaît")
	view.free()
