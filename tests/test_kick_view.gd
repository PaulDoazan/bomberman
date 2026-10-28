extends TestCase

# A player who kicks a bomb plays the kick, a right leg swung forward from the Idle pose.
func test_kicking_plays_the_kick() -> void:
	var ms := MatchState.new(SimConfig.new(), RandomNumberGenerator.new())
	var w := ms.world
	var view := ActorsView.new()
	view._ready()
	view.sync(w, ms)
	var n: ActorsView.PlayerNode = view._players[0]
	assert_true(n.anim.has_animation("Kick"), "animation créée")
	assert_eq(n.anim.current_animation, "Idle", "au repos")
	var b := w.add_bomb(0, w.players[0].cell(), 100.0)
	w.step({})
	Kick.kick(w, w.players[0], b)
	assert_eq(w.players[0].kick_tick, w.tick, "tick du coup de pied")
	view.sync(w, ms)
	assert_eq(n.anim.current_animation, "Kick", "coup de pied joué")
	assert_eq((view._players[1] as ActorsView.PlayerNode).anim.current_animation, "Idle", "les autres non")
	view.free()

# Touched by a bomb, a player hops back then sits knocked out until the stun wears off.
func test_bomb_hit_hops_then_sits() -> void:
	var ms := MatchState.new(SimConfig.new(), RandomNumberGenerator.new())
	var w := ms.world
	var view := ActorsView.new()
	view._ready()
	view.sync(w, ms)
	var n: ActorsView.PlayerNode = view._players[0]
	var ground := n.position.y
	w.hit_by_bomb(w.players[0], Vector2(1, 0))
	var top := ground
	for _t in roundi(SimConfig.KNOCK_TIME * SimConfig.TICK_RATE):
		w.step({})
		view.sync(w, ms)
		view.render(1.0)
		top = maxf(top, n.position.y)
	assert_true(top > ground + 0.5 * ActorsView.HOP_HEIGHT, "petit saut")
	assert_almost(n.position.y, ground, 0.01, "retombé")
	assert_eq(n.anim.current_animation, "Stunned", "assis dans les pommes")
	assert_true(n.stars.visible, "étoiles")
	w.players[0].stun_timer = 0.0
	w.step({})
	view.sync(w, ms)
	assert_eq(n.anim.current_animation, "Idle", "relevé")
	view.free()
