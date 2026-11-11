extends TestCase

const INTERVAL := SnapshotQueue.INTERVAL

func _snap(n: int) -> Dictionary:
	return {"n": n}

# Feeds snapshots n..m one per `gap` seconds, advancing the queue frame by frame in between;
# returns the snapshots it handed out.
func _feed(q: SnapshotQueue, from: int, to: int, gap: float) -> Array:
	var out := []
	for n in range(from, to + 1):
		q.push(_snap(n))
		var t := 0.0
		while t < gap - 0.0001:
			var step := minf(1.0 / 60.0, gap - t)
			t += step
			var d: Variant = q.advance(step)
			if d != null:
				out.append(d)
	return out

func test_nothing_pending_gives_nothing() -> void:
	var q := SnapshotQueue.new()
	assert_eq(q.advance(INTERVAL), null, "rien en attente")
	assert_eq(q.alpha(), 1.0, "alpha vide")

func test_thirty_a_second() -> void:
	assert_almost(INTERVAL, 1.0 / 30.0, 0.0001, "un instantané par tick")

func test_regular_arrivals_play_at_once() -> void:
	var q := SnapshotQueue.new()
	_feed(q, 1, 60, INTERVAL)
	assert_eq(q.depth, 1, "réseau régulier : pas de réserve")
	q.push(_snap(61))
	assert_eq(q.advance(INTERVAL), _snap(61), "joué dès son arrivée")

func test_frame_rounding_keeps_depth_at_one() -> void:
	var q := SnapshotQueue.new()
	for n in 60: # seen at 60 fps: gaps of 2 or 3 frames
		q.push(_snap(n))
		for f in (3 if n % 2 == 0 else 2):
			q.advance(1.0 / 60.0)
	assert_eq(q.depth, 1, "l'arrondi à l'image ne compte pas")

func test_one_late_snapshot_deepens_to_two() -> void:
	var q := SnapshotQueue.new()
	_feed(q, 1, 5, INTERVAL)
	_feed(q, 6, 6, INTERVAL * 2.0)
	_feed(q, 7, 7, INTERVAL)
	assert_eq(q.depth, 2, "un instantané en retard")

func test_bursts_deepen_the_buffer() -> void:
	var q := SnapshotQueue.new()
	for burst in 10: # three at once every 3 intervals, as a throttled server sends them
		q.push(_snap(burst * 3 + 1))
		q.push(_snap(burst * 3 + 2))
		_feed(q, burst * 3 + 3, burst * 3 + 3, INTERVAL * 3.0)
	assert_eq(q.depth, 3, "rafales de 3 : réserve de 3")

func test_depth_comes_back_down_on_a_steady_network() -> void:
	var q := SnapshotQueue.new()
	_feed(q, 1, 3, INTERVAL * 3.0)
	assert_true(q.depth >= 3, "réserve après des trous")
	_feed(q, 4, 4 + int(SnapshotQueue.JITTER_WINDOW / INTERVAL) + 2, INTERVAL)
	assert_eq(q.depth, 1, "revenue à 1 après la fenêtre")

func test_next_comes_one_interval_later() -> void:
	var q := SnapshotQueue.new()
	q.push(_snap(1))
	assert_eq(q.advance(0.0), _snap(1), "le premier")
	q.push(_snap(2))
	assert_eq(q.advance(INTERVAL * 0.5), null, "trop tôt")
	assert_eq(q.advance(INTERVAL * 0.5), _snap(2), "à l'intervalle")

func test_backlog_skips_ahead() -> void:
	var q := SnapshotQueue.new()
	for n in range(1, 7):
		q.push(_snap(n))
	assert_eq(q.advance(0.0), _snap(6), "saute au plus récent")

func test_catches_up_when_ahead_of_the_depth() -> void:
	var q := SnapshotQueue.new()
	q.push(_snap(1))
	q.advance(0.0)
	q.push(_snap(2))
	q.push(_snap(3)) # two waiting while the depth is 1: playback runs a little faster
	assert_eq(q.advance(INTERVAL * 0.95), _snap(2), "rattrape le retard")

func test_alpha_half_way() -> void:
	var q := SnapshotQueue.new()
	q.push(_snap(1))
	q.advance(0.0)
	assert_almost(q.alpha(), 0.0, 0.001, "juste appliqué")
	q.advance(INTERVAL * 0.5)
	assert_almost(q.alpha(), 0.5, 0.001, "mi-intervalle")

func test_starved_holds_alpha_at_one() -> void:
	var q := SnapshotQueue.new()
	q.push(_snap(1))
	q.advance(0.0)
	assert_eq(q.advance(INTERVAL * 3.0), null, "à sec")
	assert_eq(q.alpha(), 1.0, "alpha à 1")

# Run dry, it waits until `depth` snapshots are pending again.
func test_recovers_after_running_dry() -> void:
	var q := SnapshotQueue.new()
	q.push(_snap(1))
	q.advance(0.0)
	assert_eq(q.advance(INTERVAL * 3.0), null, "à sec")
	q.push(_snap(2)) # 3 intervals late: the depth goes up
	assert_true(q.depth >= 2, "réserve agrandie")
	assert_eq(q.advance(0.0), null, "attend la réserve")
	for n in range(3, 3 + q.depth - 1):
		q.push(_snap(n))
	assert_eq(q.advance(0.0), _snap(2), "repart avec le plus ancien")
	assert_almost(q.alpha(), 0.0, 0.001, "horloge repartie")
