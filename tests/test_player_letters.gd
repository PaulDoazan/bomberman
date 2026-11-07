extends TestCase

func _labels(view: ActorsView, id: int) -> Array[Label3D]:
	var out: Array[Label3D] = []
	for c in view._players[id].find_children("*", "Label3D", true, false):
		out.append(c)
	return out

# Online, the first letters of the nickname are written on the chest and on the back.
func test_tagged_player_wears_letters_front_and_back() -> void:
	var ms := MatchState.new(SimConfig.new(), RandomNumberGenerator.new())
	ms.player(0).tag = "PAU"
	var view := ActorsView.new()
	view._ready()
	view.sync(ms.world, ms)
	var labels := _labels(view, 0)
	assert_eq(labels.size(), 2, "deux étiquettes")
	for l in labels:
		assert_eq(l.text, "PAU", "texte")
		assert_eq(l.billboard, BaseMaterial3D.BILLBOARD_DISABLED, "tourne avec le corps")
		assert_true(view._players[0].model.is_ancestor_of(l), "suit le corps")
	var n: ActorsView.PlayerNode = view._players[0]
	assert_true(n.front_label.position.z > 0.0, "devant")
	assert_true(n.back_label.position.z < 0.0, "derrière")
	assert_almost(absf(n.back_label.rotation.y), PI, 0.001, "dos lisible de derrière")
	for l in labels:
		assert_true(l.rotation.x < 0.0, "penchées vers la caméra haute")
		assert_true(l.position.y < 0.8, "sur le ventre, sous la tête")
	view.free()

func test_solo_player_has_no_letters() -> void:
	var ms := MatchState.new(SimConfig.new(), RandomNumberGenerator.new())
	var view := ActorsView.new()
	view._ready()
	view.sync(ms.world, ms)
	assert_eq(_labels(view, 0).size(), 0, "pas d'étiquette en solo")
	view.free()
