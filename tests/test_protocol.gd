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
	var back := Protocol.intent_from_array(bytes_to_var(var_to_bytes(Protocol.intent_to_array(i))))
	assert_true(back != null, "intention lue")
	assert_true(back.moving and back.place_bomb and back.action_held, "booléens")
	assert_false(back.action or back.detonate, "booléens éteints")
	assert_eq(back.target, Vector2(3.5, 4.25), "cible")
	assert_eq(back.struggle, 2.0, "struggle")

func test_intent_bad_shape() -> void:
	assert_eq(Protocol.intent_from_array([true, "x"]), null, "trop court")
	assert_eq(Protocol.intent_from_array("nope"), null, "pas un tableau")
	assert_eq(Protocol.intent_from_array(["a", 1.0, 1.0, false, false, false, false, 0.0]), null, "mauvais type")
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

func test_buffer_merges_one_shots() -> void:
	var buf := IntentBuffer.new()
	var a := _intent(true, Vector2(1, 1))
	a.place_bomb = true
	buf.push(5, a)
	buf.push(5, _intent(true, Vector2(7, 8)))
	var out := buf.take()
	var got: PlayerIntent = out[5]
	assert_true(got.place_bomb, "bombe conservée")
	assert_eq(got.target, Vector2(7, 8), "cible du dernier")

func test_buffer_sums_struggle() -> void:
	var buf := IntentBuffer.new()
	var a := PlayerIntent.new()
	a.struggle = 1.0
	var b := PlayerIntent.new()
	b.struggle = 2.0
	buf.push(1, a)
	buf.push(1, b)
	assert_eq((buf.take()[1] as PlayerIntent).struggle, 3.0, "1 + 2")

func test_buffer_keeps_state_resets_one_shots() -> void:
	var buf := IntentBuffer.new()
	var a := _intent(true, Vector2(2, 3))
	a.place_bomb = true
	a.action = true
	a.action_held = true
	a.detonate = true
	a.struggle = 4.0
	buf.push(2, a)
	buf.take()
	var got: PlayerIntent = buf.take()[2]
	assert_true(got.moving and got.action_held, "état gardé")
	assert_eq(got.target, Vector2(2, 3), "cible gardée")
	assert_false(got.place_bomb or got.action or got.detonate, "ponctuels remis à zéro")
	assert_eq(got.struggle, 0.0, "struggle remis à zéro")
	assert_eq(buf.take().size(), 1, "joueur gardé")

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
