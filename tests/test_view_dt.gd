extends TestCase
# Online, the views are synced once per snapshot (every 2 ticks), so their clocks move on by the
# dt they are given rather than by one tick per sync.

func test_actors_clock_moves_on_by_dt() -> void:
	var ms := MatchState.new(SimConfig.new(), RandomNumberGenerator.new())
	var solo := ActorsView.new()
	solo._ready()
	var online := ActorsView.new()
	online._ready()
	solo.sync(ms.world, ms)
	online.sync(ms.world, ms, SimConfig.DT * 2.0)
	assert_almost(solo._time, SimConfig.DT, 1e-6, "un tick par défaut")
	assert_almost(online._time, SimConfig.DT * 2.0, 1e-6, "deux fois plus loin")
	solo.free()
	online.free()

func test_items_clock_moves_on_by_dt() -> void:
	var w := MatchState.new(SimConfig.new(), RandomNumberGenerator.new()).world
	var solo := ItemsView.new()
	var online := ItemsView.new()
	solo.sync(w)
	online.sync(w, SimConfig.DT * 2.0)
	assert_almost(solo._time, SimConfig.DT, 1e-6, "un tick par défaut")
	assert_almost(online._time, SimConfig.DT * 2.0, 1e-6, "deux fois plus loin")
	solo.free()
	online.free()

# A ledge jump synced every 2 ticks falls as fast, in sim time, as one synced every tick.
func test_fall_speed_follows_dt() -> void:
	var every_tick := ActorsView.PlayerNode.new()
	var every_two := ActorsView.PlayerNode.new()
	for n in [every_tick, every_two]:
		n.y_smooth = 5.0
	for _i in 10:
		ActorsView._fall(every_tick, 0.0)
		ActorsView._fall(every_tick, 0.0)
		ActorsView._fall(every_two, 0.0, SimConfig.DT * 2.0)
	assert_almost(every_two.fall_v, every_tick.fall_v, 1e-6, "même vitesse")
	assert_almost(every_two.y_smooth, every_tick.y_smooth, 1e-6, "même hauteur")
	assert_true(every_tick.falling and every_tick.y_smooth < 5.0, "en pleine chute")
	every_tick.free()
	every_two.free()

# Easing per sync: one sync of 2 ticks lands where two syncs of one tick do.
func test_easing_follows_dt() -> void:
	var k := ActorsView.TURN_SPEED
	var twice := 1.0 - (1.0 - k) * (1.0 - k)
	assert_almost(ActorsView._per_tick(k, SimConfig.DT), k, 1e-9, "un tick")
	assert_almost(ActorsView._per_tick(k, SimConfig.DT * 2.0), twice, 1e-9, "deux ticks")
