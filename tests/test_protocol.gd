extends TestCase

func _intent(moving: bool, target: Vector2) -> PlayerIntent:
	var i := PlayerIntent.new()
	i.moving = moving
	i.target = target
	return i

func test_encode_decode_dictionary() -> void:
	var body := {"a": 1, "b": [1, 2, "x"], "c": Vector2(1.5, 2)}
	var out := Protocol.decode(Protocol.encode(Protocol.Msg.LOBBY, body))
	assert_eq(out.size(), 2, "type et corps")
	assert_eq(out[0], Protocol.Msg.LOBBY, "type")
	assert_eq(out[1], body, "corps")

func test_encode_decode_array() -> void:
	var out := Protocol.decode(Protocol.encode(Protocol.Msg.INTENT, [true, 1.5, 2.5]))
	assert_eq(out[0], Protocol.Msg.INTENT, "type")
	assert_eq(out[1], [true, 1.5, 2.5], "corps")

func test_decode_garbage() -> void:
	assert_eq(Protocol.decode(PackedByteArray([1, 2, 3])), [], "octets invalides")
	assert_eq(Protocol.decode(PackedByteArray()), [], "vide")
	var unknown := Protocol.encode(Protocol.Msg.PING, null)
	unknown[0] = 99
	assert_eq(Protocol.decode(unknown), [], "type inconnu")

func test_decode_rejects_objects() -> void:
	var top := var_to_bytes_with_objects(RefCounted.new())
	var packed := PackedByteArray([Protocol.Msg.LOBBY])
	packed.append_array(top.compress(FileAccess.COMPRESSION_DEFLATE))
	assert_eq(Protocol.decode(packed), [], "objet refusé")

func test_intent_roundtrip() -> void:
	var i := _intent(true, Vector2(3.5, 4.25))
	i.place_bomb = true
	i.action_held = true
	i.struggle = 2.0
	i.seq = 42
	var back := Protocol.intent_from_array(bytes_to_var(var_to_bytes(Protocol.intent_to_array(i))))
	assert_true(back != null, "intention lue")
	assert_true(back.moving and back.place_bomb and back.action_held, "booléens")
	assert_false(back.action or back.detonate, "booléens éteints")
	assert_eq(back.target, Vector2(3.5, 4.25), "cible")
	assert_eq(back.struggle, 2.0, "struggle")
	assert_eq(back.seq, 42, "numéro")

func test_intent_bad_shape() -> void:
	assert_eq(Protocol.intent_from_array([true, "x"]), null, "trop court")
	assert_eq(Protocol.intent_from_array("nope"), null, "pas un tableau")
	assert_eq(Protocol.intent_from_array(["a", 1.0, 1.0, false, false, false, false, 0.0, 1]), null, "mauvais type")
	assert_eq(Protocol.intent_from_array([true, 1.0, 1.0, false, false, false, false, 0.0, 1.5]), null, "numéro pas entier")
	assert_eq(Protocol.intent_from_array([true, 1.0, 1.0, false, false, false, false, 0.0, -1]), null, "numéro négatif")
	var long := Protocol.intent_to_array(PlayerIntent.new())
	long.append(1)
	assert_eq(Protocol.intent_from_array(long), null, "trop long")

func test_intent_struggle_clamped() -> void:
	var i := PlayerIntent.new()
	i.struggle = 99.0
	assert_eq(Protocol.intent_from_array(Protocol.intent_to_array(i)).struggle, 10.0, "borné haut")
	i.struggle = -4.0
	assert_eq(Protocol.intent_from_array(Protocol.intent_to_array(i)).struggle, 0.0, "borné bas")

func test_error_labels_cover_codes() -> void:
	for code in [Protocol.ERR_UNKNOWN_CODE, Protocol.ERR_FULL, Protocol.ERR_NAME_TAKEN, Protocol.ERR_BAD_NAME,
			Protocol.ERR_TEAMS_FULL, Protocol.ERR_HOST_ONLY, Protocol.ERR_CANNOT_START, Protocol.ERR_NOT_NOW,
			Protocol.ERR_VERSION, Protocol.ERR_SERVER_FULL]:
		assert_true(Protocol.ERROR_LABELS.has(code), "libellé pour %s" % code)

func test_buffer_plays_intents_in_order() -> void:
	var buf := IntentBuffer.new()
	var a := _intent(true, Vector2(1, 1))
	a.place_bomb = true
	a.seq = 1
	var b := _intent(true, Vector2(7, 8))
	b.seq = 2
	buf.push(5, a)
	buf.push(5, b)
	var first: PlayerIntent = buf.take()[5]
	assert_eq(first.target, Vector2(1, 1), "le premier d'abord")
	assert_true(first.place_bomb, "avec sa bombe")
	var second: PlayerIntent = buf.take()[5]
	assert_eq(second.target, Vector2(7, 8), "puis le second")
	assert_false(second.place_bomb, "la bombe n'est posée qu'une fois")
	assert_eq(second.seq, 2, "numéro du second")

func test_buffer_merges_a_backlog() -> void:
	var buf := IntentBuffer.new()
	for n in IntentBuffer.MAX_QUEUED + 2:
		var i := _intent(true, Vector2(n, n))
		i.seq = n + 1
		i.place_bomb = n == 1
		i.struggle = 1.0
		buf.push(1, i)
	assert_eq((buf.take()[1] as PlayerIntent).seq, 1, "le plus ancien d'abord")
	var got: PlayerIntent = buf.take()[1]
	assert_eq(got.seq, 3, "le deuxième, en trop, fusionné dans le troisième")
	assert_true(got.place_bomb, "sa bombe est gardée")
	assert_eq(got.struggle, 2.0, "struggle additionné")

func test_buffer_catches_up_a_late_intent() -> void:
	var buf := IntentBuffer.new()
	var first := _intent(true, Vector2(1, 1))
	first.seq = 1
	buf.push(3, first)
	buf.take()
	var waiting: PlayerIntent = buf.take()[3]
	assert_true(waiting.late and waiting.moving, "en retard : toujours en mouvement, sans pas")
	assert_eq(waiting.seq, 1, "rien de nouveau appliqué")
	for n in [2, 3]:
		var i := _intent(true, Vector2(n, n))
		i.seq = n
		i.place_bomb = n == 3
		buf.push(3, i)
	var caught: PlayerIntent = buf.take()[3]
	assert_eq(caught.target, Vector2(2, 2), "le pas du deuxième")
	assert_eq(caught.catch_up.size(), 1, "puis celui du troisième, dans le même tick")
	assert_eq(caught.seq, 3, "les deux appliqués")
	assert_true(caught.place_bomb, "la bombe du troisième posée")
	var four := _intent(true, Vector2(4, 4))
	four.seq = 4
	var five := _intent(true, Vector2(5, 5))
	five.seq = 5
	buf.push(3, four)
	buf.push(3, five)
	var next: PlayerIntent = buf.take()[3]
	assert_eq(next.seq, 4, "crédit dépensé : un pas par tick")
	assert_true(next.catch_up.is_empty(), "pas plus vite que les autres")

func test_buffer_walks_granted_ticks() -> void:
	var buf := IntentBuffer.new()
	for n in 15:
		var i := _intent(true, Vector2(n, n))
		i.seq = n + 1
		buf.push(4, i)
	buf.grant(5) # the server skipped 5 ticks
	var got: PlayerIntent = buf.take()[4]
	assert_eq(got.catch_up.size(), 5, "les 5 ticks sautés rattrapés")
	assert_eq(got.seq, 6, "aucun pas perdu")
	var seqs := []
	for _t in 9:
		seqs.append((buf.take()[4] as PlayerIntent).seq)
	assert_eq(seqs, [7, 8, 9, 10, 11, 12, 13, 14, 15], "puis un par tick")

func test_world_walks_caught_up_intents() -> void:
	var ids: Array[int] = [0]
	var w := World.new(Fixtures.flat(9, 5), ids, SimConfig.new(), RandomNumberGenerator.new())
	w.players[0].pos = Vector2(1.5, 2.5)
	var a := _intent(true, Vector2(8.5, 2.5))
	a.catch_up.append(_intent(true, Vector2(8.5, 2.5)))
	w.step({0: a})
	assert_almost(w.players[0].pos.x, 1.5 + 2.0 * SimConfig.PLAYER_SPEED * SimConfig.DT, 1e-4, "deux pas")
	var late := _intent(true, Vector2(8.5, 2.5))
	late.late = true
	w.step({0: late})
	assert_almost(w.players[0].pos.x, 1.5 + 2.0 * SimConfig.PLAYER_SPEED * SimConfig.DT, 1e-4, "en attente : aucun pas")

func test_buffer_keeps_state_resets_one_shots() -> void:
	var buf := IntentBuffer.new()
	var a := _intent(true, Vector2(2, 3))
	a.place_bomb = true
	a.action = true
	a.action_held = true
	a.detonate = true
	a.struggle = 4.0
	a.seq = 7
	buf.push(2, a)
	buf.take()
	var got: PlayerIntent = buf.take()[2]
	assert_eq(got.seq, 7, "même numéro : rien de nouveau appliqué")
	assert_true(got.moving and got.action_held, "état gardé")
	assert_eq(got.target, Vector2(2, 3), "cible gardée")
	assert_false(got.place_bomb or got.action or got.detonate, "ponctuels remis à zéro")
	assert_eq(got.struggle, 0.0, "struggle remis à zéro")
	assert_eq(buf.take().size(), 1, "joueur gardé")

func test_buffer_forget_and_clear() -> void:
	var buf := IntentBuffer.new()
	buf.push(1, _intent(true, Vector2(2, 3)))
	buf.push(2, _intent(true, Vector2(4, 5)))
	buf.forget(1)
	var out := buf.take()
	assert_false(out.has(1), "joueur oublié")
	assert_true(out.has(2), "l'autre reste")
	buf.clear()
	assert_true(buf.take().is_empty(), "tout effacé")

func test_decode_rejects_bomb() -> void:
	var zeros := PackedByteArray()
	zeros.resize(30 * 1024 * 1024)
	var packed := PackedByteArray([Protocol.Msg.LOBBY])
	packed.append_array(zeros.compress(FileAccess.COMPRESSION_DEFLATE))
	assert_true(packed.size() < Protocol.MAX_PACKET_BYTES, "bombe sous la limite de paquet (%d)" % packed.size())
	assert_eq(Protocol.decode(packed), [], "bombe refusée")

func test_decode_rejects_big_packet() -> void:
	var big := PackedByteArray([Protocol.Msg.LOBBY])
	big.resize(Protocol.MAX_PACKET_BYTES + 1)
	assert_eq(Protocol.decode(big), [], "paquet trop gros")

func test_decode_large_body_under_cap() -> void:
	var body := PackedByteArray()
	body.resize(40000)
	var out := Protocol.decode(Protocol.encode(Protocol.Msg.LOBBY, body))
	assert_eq(out.size(), 2, "gros corps accepté")

func test_decode_malformed_variant() -> void:
	var raw := PackedByteArray([255, 255, 255, 255, 1, 2, 3, 4])
	var packed := PackedByteArray([Protocol.Msg.LOBBY])
	packed.append_array(raw.compress(FileAccess.COMPRESSION_DEFLATE))
	assert_eq(Protocol.decode(packed), [], "variant malformé")

func test_decode_null_body_ok() -> void:
	assert_eq(Protocol.decode(Protocol.encode(Protocol.Msg.PING, null)), [Protocol.Msg.PING, null], "null légitime")

func test_intent_non_finite_and_far() -> void:
	for idx in [1, 2, 7]:
		for bad in [NAN, INF, -INF]:
			var a := Protocol.intent_to_array(PlayerIntent.new())
			a[idx] = bad
			assert_eq(Protocol.intent_from_array(a), null, "slot %d = %s" % [idx, str(bad)])
	var far := Protocol.intent_to_array(PlayerIntent.new())
	far[1] = 1001.0
	assert_eq(Protocol.intent_from_array(far), null, "x trop loin")
	far[1] = 0.0
	far[2] = -1001.0
	assert_eq(Protocol.intent_from_array(far), null, "y trop loin")
