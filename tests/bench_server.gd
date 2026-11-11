extends SceneTree
# Server load bench, outside the test suite: 600 ticks of a 12-player match on the immense map
# with random intents, a snapshot encoded every SNAPSHOT_EVERY ticks as the server does.
# godot --headless --path . -s res://tests/bench_server.gd

const TICKS := 600
const PLAYERS := 12

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var room := Room.new("BENCH2", rng)
	for i in PLAYERS:
		room.join("Joueur %d" % (i + 1), "", 0.0)
	for team in Room.MAX_TEAMS:
		room.create_team(room.host_id, "Équipe %d" % (team + 1))
	for id in range(1, PLAYERS + 1):
		room.join_team(id, (id - 1) % Room.MAX_TEAMS)
	var cfg := SimConfig.new()
	cfg.map_size = "immense"
	room.set_config(room.host_id, cfg)
	var err := room.start(room.host_id)
	if err != "":
		print("Démarrage impossible : ", err)
		quit(1)
		return
	var size := room.match_state.cfg.grid_size()
	var total_us := 0
	var max_us := 0
	var snap_bytes := 0
	var snaps := 0
	var now := 0.0
	for t in TICKS:
		var intents := {}
		for id in range(1, PLAYERS + 1):
			var i := PlayerIntent.new()
			i.moving = rng.randf() < 0.8
			i.target = Vector2(rng.randf_range(0, size.x), rng.randf_range(0, size.y))
			i.place_bomb = rng.randf() < 0.05
			i.action = rng.randf() < 0.03
			i.action_held = rng.randf() < 0.1
			i.detonate = rng.randf() < 0.02
			intents[id] = i
		now += SimConfig.DT
		var start := Time.get_ticks_usec()
		room.tick(now, intents)
		if t % ServerCore.SNAPSHOT_EVERY == 0:
			var bytes := Protocol.encode(Protocol.Msg.SNAPSHOT, SimCodec.encode_match(room.match_state))
			snap_bytes += bytes.size()
			snaps += 1
		var us := Time.get_ticks_usec() - start
		total_us += us
		max_us = maxi(max_us, us)
	print("%d ticks, %d joueurs, carte %dx%d" % [TICKS, PLAYERS, size.x, size.y])
	print("ms/tick : moyenne %.3f, max %.3f" % [total_us / 1000.0 / TICKS, max_us / 1000.0])
	print("instantané moyen : %d octets" % (snap_bytes / snaps))
	quit(0)
