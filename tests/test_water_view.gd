extends TestCase

func _world(round_time: float) -> World:
	var cfg := SimConfig.new()
	cfg.round_time = round_time
	var ids: Array[int] = [0]
	return World.new(Fixtures.flat(5, 3), ids, cfg, RandomNumberGenerator.new())

# The drawn water is never below the simulated water: players never drown in visibly dry cells.
func test_water_view_never_lags_the_sim() -> void:
	var w := _world(1.0)
	for _t in 70 * SimConfig.TICK_RATE:
		w.step({})
		var y := ArenaView.water_y_for(w)
		if y < ArenaView.water_y(w.water_h2) - 1e-4:
			assert_true(false, "eau dessinée sous l'eau simulée au tick %d" % w.tick)
			return

func test_water_view_rises_during_warning_and_lands_on_the_step() -> void:
	var w := _world(100.0)
	w.time_left = SimConfig.WATER_WARNING * 0.5
	w.water_warning = true
	var mid := ArenaView.water_y_for(w)
	assert_true(mid > ArenaView.water_y(w.water_h2) and mid < ArenaView.water_y(-1), "à mi-chemin pendant l'alerte")
	w.water_warning = false
	w.time_left = 10.0
	assert_almost(ArenaView.water_y_for(w), ArenaView.water_y(w.water_h2), 1e-4, "immobile hors alerte")
