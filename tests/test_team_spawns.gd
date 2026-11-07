extends TestCase

const SPLITS := [[6, 6], [11, 1], [3, 3, 3, 3], [4, 4, 4], [1, 1]]

func _dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func test_teams_spawn_together() -> void:
	for k in SimConfig.MAP_SIZES:
		for split in SPLITS:
			var sizes: Array[int] = []
			var total := 0
			for n in split:
				sizes.append(n)
				total += n
			var rng := RandomNumberGenerator.new()
			rng.seed = 11
			var a := MapGen.generate(SimConfig.MAP_SIZES[k], total, rng, sizes)
			var label := "%s %s" % [k, str(split)]
			assert_eq(a.spawns.size(), total, label + " nombre de départs")
			var uniq := {}
			for s in a.spawns:
				uniq[s] = true
				assert_eq(a.h2_at(s), 0, label + " départ au sol")
			assert_eq(uniq.size(), total, label + " départs distincts")
			# Spawns come out in team order: team t owns a contiguous slice.
			var team_of: Array[int] = []
			var members: Array = []
			for t in sizes.size():
				members.append([])
				for i in sizes[t]:
					members[t].append(a.spawns[team_of.size()])
					team_of.append(t)
			# (a) the nearest other spawn of a player in a team of 2+ is a teammate.
			for i in total:
				if sizes[team_of[i]] < 2:
					continue
				var best := 1 << 30
				var mate_best := 1 << 30
				for j in total:
					if i == j:
						continue
					var d := _dist(a.spawns[i], a.spawns[j])
					best = mini(best, d)
					if team_of[j] == team_of[i]:
						mate_best = mini(mate_best, d)
				assert_true(mate_best <= best, "%s joueur %d : coéquipier le plus proche %d > autre %d" % [label, i, mate_best, best])
			# (b) team centroids are farther apart than either team's mean spread.
			var centroids: Array[Vector2] = []
			var spreads: Array[float] = []
			for t in sizes.size():
				var sum := Vector2.ZERO
				for c in members[t]:
					sum += Vector2(c)
				var cen: Vector2 = sum / sizes[t]
				var spread := 0.0
				for c in members[t]:
					spread += Vector2(c).distance_to(cen)
				centroids.append(cen)
				spreads.append(spread / sizes[t])
			for t in sizes.size():
				for u in range(t + 1, sizes.size()):
					var d := centroids[t].distance_to(centroids[u])
					assert_true(d > spreads[t] and d > spreads[u], "%s équipes %d/%d : centres à %.1f, dispersions %.1f/%.1f" % [label, t, u, d, spreads[t], spreads[u]])

func test_no_teams_same_as_before() -> void:
	var expected := {
		["petite", 4]: [Vector2i(0, 0), Vector2i(16, 3), Vector2i(13, 12), Vector2i(1, 12)],
		["petite", 10]: [Vector2i(0, 0), Vector2i(4, 0), Vector2i(16, 0), Vector2i(16, 5), Vector2i(16, 10), Vector2i(13, 12), Vector2i(8, 12), Vector2i(3, 12), Vector2i(0, 10), Vector2i(0, 5)],
		["normale", 4]: [Vector2i(0, 0), Vector2i(22, 2), Vector2i(18, 14), Vector2i(2, 14)],
		["normale", 10]: [Vector2i(0, 0), Vector2i(6, 0), Vector2i(21, 0), Vector2i(22, 5), Vector2i(22, 12), Vector2i(18, 14), Vector2i(12, 14), Vector2i(5, 14), Vector2i(0, 13), Vector2i(0, 7)],
	}
	for key in expected:
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var a := MapGen.generate(SimConfig.MAP_SIZES[key[0]], key[1], rng)
		assert_eq(a.spawns, expected[key] as Array[Vector2i], "%s %d" % [key[0], key[1]])
