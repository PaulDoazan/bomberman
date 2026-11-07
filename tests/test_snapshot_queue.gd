extends TestCase

const INTERVAL := SnapshotQueue.INTERVAL

func _snap(n: int) -> Dictionary:
	return {"n": n}

func test_nothing_pending_gives_nothing() -> void:
	var q := SnapshotQueue.new()
	assert_eq(q.advance(INTERVAL), null, "rien en attente")
	assert_eq(q.alpha(), 1.0, "alpha vide")

func test_waits_for_one_ahead() -> void:
	var q := SnapshotQueue.new()
	q.push(_snap(1))
	assert_eq(q.advance(INTERVAL), null, "un seul : on attend")

func test_two_pending_gives_the_first() -> void:
	var q := SnapshotQueue.new()
	q.push(_snap(1))
	q.push(_snap(2))
	assert_eq(q.advance(INTERVAL), _snap(1), "le premier")

func test_next_comes_one_interval_later() -> void:
	var q := SnapshotQueue.new()
	q.push(_snap(1))
	q.push(_snap(2))
	q.advance(INTERVAL)
	assert_eq(q.advance(INTERVAL * 0.5), null, "trop tôt")
	assert_eq(q.advance(INTERVAL * 0.5), _snap(2), "à l'intervalle")

func test_backlog_skips_to_newest_but_one() -> void:
	var q := SnapshotQueue.new()
	for n in range(1, 7):
		q.push(_snap(n))
	assert_eq(q.advance(0.0), _snap(5), "saute au 5e")
	assert_eq(q.advance(INTERVAL), _snap(6), "puis le 6e")

func test_alpha_half_way() -> void:
	var q := SnapshotQueue.new()
	q.push(_snap(1))
	q.push(_snap(2))
	q.advance(INTERVAL)
	assert_almost(q.alpha(), 0.0, 0.001, "juste appliqué")
	q.advance(INTERVAL * 0.5)
	assert_almost(q.alpha(), 0.5, 0.001, "mi-intervalle")

func test_starved_holds_alpha_at_one() -> void:
	var q := SnapshotQueue.new()
	q.push(_snap(1))
	q.push(_snap(2))
	q.advance(INTERVAL)
	q.advance(INTERVAL) # applies 2, nothing left
	assert_eq(q.advance(INTERVAL * 3.0), null, "à sec")
	assert_eq(q.alpha(), 1.0, "alpha à 1")

# Run dry, it waits for one ahead again: a single late snapshot is not played at once.
func test_recovers_after_running_dry() -> void:
	var q := SnapshotQueue.new()
	q.push(_snap(1))
	q.push(_snap(2))
	q.advance(INTERVAL)
	q.advance(INTERVAL)
	assert_eq(q.advance(INTERVAL), null, "à sec")
	q.push(_snap(3))
	assert_eq(q.advance(INTERVAL), null, "un seul : on attend")
	assert_eq(q.alpha(), 1.0, "alpha à 1 en attendant")
	q.push(_snap(4))
	assert_eq(q.advance(0.0), _snap(3), "repart avec le 3e")
	assert_almost(q.alpha(), 0.0, 0.001, "horloge repartie")
	assert_eq(q.advance(INTERVAL), _snap(4), "puis le 4e")
