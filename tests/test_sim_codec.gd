extends TestCase

func _cfg() -> SimConfig:
	var cfg := SimConfig.new()
	cfg.map_size = "immense"
	return cfg

# 12 players in 4 teams of 3.
func _match() -> MatchState:
	var roster: Array[MatchState.MatchPlayer] = []
	for i in 12:
		var mp := MatchState.MatchPlayer.new()
		mp.id = i
		mp.name = "P%d" % i
		mp.color = TeamColors.tint(i / 3, i % 3, 3)
		mp.team = i / 3
		roster.append(mp)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	return MatchState.new(_cfg(), rng, roster)

# Random intents, bombs and throws included, from a seeded rng.
func _step_random(m: MatchState, dice: RandomNumberGenerator) -> void:
	var intents := {}
	for id: int in m.world.players:
		var p: PlayerState = m.world.players[id]
		var it := PlayerIntent.new()
		it.moving = dice.randf() < 0.8
		it.target = p.pos + Vector2(dice.randf_range(-2.0, 2.0), dice.randf_range(-2.0, 2.0))
		it.place_bomb = dice.randf() < 0.08
		it.action = dice.randf() < 0.05
		it.action_held = dice.randf() < 0.5
		intents[id] = it
	m.step(intents)

func _played(ticks: int) -> MatchState:
	var m := _match()
	var dice := RandomNumberGenerator.new()
	dice.seed = 3
	for i in ticks:
		_step_random(m, dice)
	return m

func test_roundtrip_same_state() -> void:
	var m := _played(90)
	assert_true(m.world.bombs.size() + m.world.explosions.size() > 0, "des bombes ou explosions à encoder")
	var data := SimCodec.encode_match(m)
	var mirror := SimCodec.apply_match(data, null, _cfg())
	assert_true(mirror != null and mirror != m, "nouveau miroir")
	assert_eq(SimCodec.encode_match(mirror), SimCodec.encode_match(m), "même état")
	assert_eq(mirror.world.players.size(), 12, "12 joueurs")
	assert_eq(mirror.world.arena.tiles, m.world.arena.tiles, "mêmes cases")
	assert_eq(mirror.world.next_water_h2(), m.world.next_water_h2(), "même prochaine montée")
	var wired := SimCodec.apply_match(bytes_to_var(var_to_bytes(data)), null, _cfg())
	assert_eq(SimCodec.encode_match(wired), SimCodec.encode_match(m), "même état après passage en octets")

func test_apply_keeps_identity() -> void:
	var m := _match()
	var dice := RandomNumberGenerator.new()
	dice.seed = 3
	var guard := 0
	while m.world.explosions.is_empty() and guard < 300:
		_step_random(m, dice)
		guard += 1
	assert_false(m.world.explosions.is_empty(), "une explosion en cours")
	var first := SimCodec.encode_match(m)
	_step_random(m, dice)
	var second := SimCodec.encode_match(m)
	var mirror := SimCodec.apply_match(first, null, _cfg())
	var world := mirror.world
	var arena := world.arena
	var uid: int = (m.world.explosions[0] as Explosion).uid
	var before: Explosion = null
	for e: Explosion in world.explosions:
		if e.uid == uid:
			before = e
	assert_true(before != null, "explosion dans le premier instantané")
	var again := SimCodec.apply_match(second, mirror, _cfg())
	assert_true(again == mirror, "même MatchState")
	assert_true(again.world == world, "même World")
	assert_true(again.world.arena == arena, "même Arena")
	var after: Explosion = null
	for e: Explosion in again.world.explosions:
		if e.uid == uid:
			after = e
	assert_true(after != null and after == before, "même instance d'explosion")
	assert_eq(SimCodec.encode_match(again), second, "état du second instantané")

func test_new_round_new_world() -> void:
	var m := _match()
	var mirror := SimCodec.apply_match(SimCodec.encode_match(m), null, _cfg())
	var world := mirror.world
	m.start_round()
	var next := SimCodec.apply_match(SimCodec.encode_match(m), mirror, _cfg())
	assert_true(next.world != world, "nouveau World")
	assert_eq(next.round_number, 2, "manche 2")

func test_hold_next_round_roundtrip() -> void:
	var m := _match()
	m.hold_next_round = true
	var mirror := SimCodec.apply_match(SimCodec.encode_match(m), null, _cfg())
	assert_true(mirror.hold_next_round, "attente transmise")
	m.hold_next_round = false
	mirror = SimCodec.apply_match(SimCodec.encode_match(m), mirror, _cfg())
	assert_false(mirror.hold_next_round, "fin de l'attente transmise")

func _has_key(v: Variant, key: String) -> bool:
	if v is Dictionary:
		for k: Variant in v:
			if k is String and k == key:
				return true
			if _has_key(v[k], key):
				return true
	elif v is Array:
		for x: Variant in v:
			if _has_key(x, key):
				return true
	return false

func test_hidden_not_sent() -> void:
	var m := _played(10)
	assert_false(m.world.hidden.is_empty(), "des objets cachés côté serveur")
	assert_false(_has_key(SimCodec.encode_match(m), "hidden"), "aucune clé hidden")
	var mirror := SimCodec.apply_match(SimCodec.encode_match(m), null, _cfg())
	assert_true(mirror.world.hidden.is_empty(), "le miroir ne sait rien des objets cachés")

func test_config_roundtrip_and_clamp() -> void:
	var cfg := SimConfig.new()
	cfg.bot_count = 5
	cfg.map_size = "grande"
	cfg.round_time = 180.0
	cfg.lives = 4
	cfg.items[SimConfig.Item.COFFEE] = false
	var back := SimCodec.decode_config(SimCodec.encode_config(cfg))
	assert_eq(back.bot_count, 5, "bots")
	assert_eq(back.map_size, "grande", "taille")
	assert_eq(back.round_time, 180.0, "durée")
	assert_eq(back.lives, 4, "vies")
	assert_false(back.item_enabled(SimConfig.Item.COFFEE), "café navette désactivé")
	assert_true(back.item_enabled(SimConfig.Item.FIRE), "feu activé")
	var bad := SimCodec.decode_config({"lives": 99, "map_size": "xxl"})
	assert_eq(bad.lives, 9, "vies bornées")
	assert_eq(bad.map_size, "normale", "taille inconnue")
	var worse := SimCodec.decode_config({"round_time": 5, "bot_count": -3, "items": {99: false, SimConfig.Item.BOMB: "non"}})
	assert_eq(worse.round_time, 30.0, "durée bornée")
	assert_eq(worse.bot_count, 1, "bots bornés")
	assert_true(worse.items.is_empty(), "objets inconnus ignorés")

func test_schema_hash_is_stable() -> void:
	assert_eq(SimCodec.schema_hash(), SimCodec.schema_hash(), "même empreinte")
	assert_true(SimCodec.keys_of(PlayerState).has("pos"), "pos fait partie du schéma")

func test_snapshot_size_budget() -> void:
	var m := _played(90)
	var size := Protocol.encode(Protocol.Msg.SNAPSHOT, SimCodec.encode_match(m)).size()
	print("snapshot size: %d bytes" % size)
	assert_true(size < 2500, "instantané < 2500 octets, obtenu %d" % size)

# Les objets en route vers le sol (caisses, bombes qui jaillissent) passent dans l'instantané.
func test_drops_roundtrip() -> void:
	var m := _played(10)
	for kind in [Drop.Kind.CRATE, Drop.Kind.SPILL]:
		var d := Drop.new()
		d.uid = m.world.next_uid()
		d.kind = kind
		d.item = SimConfig.Item.BOMB
		d.from = Vector2(3.5, 2.5)
		d.cell = Vector2i(4, 2)
		d.elapsed = 0.2
		m.world.drops.append(d)
	var data := SimCodec.encode_match(m)
	var mirror := SimCodec.apply_match(bytes_to_var(var_to_bytes(data)), null, _cfg())
	assert_eq(mirror.world.drops.size(), 2)
	assert_eq(SimCodec.encode_match(mirror), SimCodec.encode_match(m), "même état")
	var kept: Drop = mirror.world.drops[0]
	SimCodec.apply_match(data, mirror, _cfg())
	assert_true(mirror.world.drops[0] == kept, "même instance d'un instantané à l'autre")
