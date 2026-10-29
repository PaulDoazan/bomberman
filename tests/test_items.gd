extends TestCase

# Monde 9×3 sans objets cachés : chaque test pose ce qu'il veut.
func _world(positions: Array[Vector2], a: Arena = null) -> World:
	var ids: Array[int] = []
	for i in positions.size():
		ids.append(i)
	var cfg := SimConfig.new()
	for item: int in SimConfig.ITEM_LABELS:
		cfg.items[item] = false
	var w := World.new(a if a != null else Fixtures.flat(9, 3), ids, cfg, RandomNumberGenerator.new())
	for i in positions.size():
		w.players[i].pos = positions[i]
	return w

func _wait(w: World, seconds: float, intents := {}) -> void:
	for _t in roundi(seconds * SimConfig.TICK_RATE):
		w.step(intents)

func _intent(place := false, action := false, detonate := false) -> PlayerIntent:
	var i := PlayerIntent.new()
	i.place_bomb = place
	i.action = action
	i.detonate = detonate
	return i

func _go(target: Vector2) -> PlayerIntent:
	var i := PlayerIntent.new()
	i.moving = true
	i.target = target
	return i

func test_blocks_hide_items_only_when_turned_on() -> void:
	var a := Fixtures.flat(9, 9)
	for y in 9:
		for x in 9:
			if (x + y) % 2 == 0:
				a.set_tile(Vector2i(x, y), Arena.Tile.BLOCK)
	var cfg := SimConfig.new()
	var w := World.new(a, [0] as Array[int], cfg, RandomNumberGenerator.new())
	var evils := 0
	for item: int in w.hidden.values():
		if item == SimConfig.Item.EVIL:
			evils += 1
	assert_true(w.hidden.size() > 5, "des objets cachés")
	assert_eq(evils, 1, "un seul Mal par manche")
	for item: int in SimConfig.ITEM_LABELS:
		cfg.items[item] = false
	var w2 := World.new(Fixtures.flat(9, 9), [0] as Array[int], cfg, RandomNumberGenerator.new())
	assert_true(w2.hidden.is_empty(), "aucun objet quand tout est désactivé")
	cfg.items = {SimConfig.Item.FIRE: false, SimConfig.Item.BOMB: false, SimConfig.Item.POWER: false,
			SimConfig.Item.REMOTE: false, SimConfig.Item.SKULL: false, SimConfig.Item.EVIL: false}
	var w3 := World.new(a, [0] as Array[int], cfg, RandomNumberGenerator.new())
	for item: int in w3.hidden.values():
		assert_eq(item, SimConfig.Item.HEART, "seulement les objets activés")

# Un bloc détruit révèle son objet, intact ; une explosion suivante le détruit.
func test_blown_block_reveals_its_item_and_a_later_blast_burns_it() -> void:
	var a := Fixtures.flat(9, 3)
	a.set_tile(Vector2i(4, 1), Arena.Tile.BLOCK)
	var w := _world([Vector2(8.5, 0.5)], a)
	w.hidden[Vector2i(4, 1)] = SimConfig.Item.FIRE
	w.add_bomb(0, Vector2i(3, 1), 0.1)
	_wait(w, 0.2)
	assert_eq(w.items.get(Vector2i(4, 1)), SimConfig.Item.FIRE, "objet révélé")
	_wait(w, 1.0)
	w.add_bomb(0, Vector2i(3, 1), 0.1)
	_wait(w, 0.2)
	assert_false(w.items.has(Vector2i(4, 1)), "brûlé par l'explosion suivante")

func test_lifting_a_block_reveals_its_item() -> void:
	var a := Fixtures.flat(9, 3)
	a.set_tile(Vector2i(4, 1), Arena.Tile.BLOCK)
	var w := _world([Vector2(3.5, 1.5)], a)
	w.players[0].facing = Vector2i(1, 0)
	w.hidden[Vector2i(4, 1)] = SimConfig.Item.BOMB
	w.step({0: _intent(false, true)})
	assert_eq(w.items.get(Vector2i(4, 1)), SimConfig.Item.BOMB, "reste au sol")

func test_walking_over_items_picks_them_up() -> void:
	var w := _world([Vector2(1.5, 1.5)])
	w.items[Vector2i(2, 1)] = SimConfig.Item.FIRE
	w.items[Vector2i(3, 1)] = SimConfig.Item.BOMB
	w.items[Vector2i(4, 1)] = SimConfig.Item.POWER
	w.items[Vector2i(5, 1)] = SimConfig.Item.HEART
	w.items[Vector2i(6, 1)] = SimConfig.Item.REMOTE
	_wait(w, 2.0, {0: _go(Vector2(6.5, 1.5))})
	var p := w.players[0] as PlayerState
	assert_true(w.items.is_empty(), "tout ramassé")
	assert_eq(p.fire, 2, "portée +1")
	assert_eq(p.max_bombs, SimConfig.MAX_BOMBS + 1, "une bombe de plus")
	assert_true(p.power and p.heart and p.remote, "puissance, cœur, télécommande")

func test_fire_and_bomb_items_are_capped() -> void:
	var w := _world([Vector2(1.5, 1.5)])
	var p := w.players[0] as PlayerState
	for _i in 10:
		Items.apply(w, p, SimConfig.Item.FIRE)
		Items.apply(w, p, SimConfig.Item.BOMB)
	assert_eq(p.fire, SimConfig.FIRE_MAX)
	assert_eq(p.max_bombs, SimConfig.MAX_BOMBS_CAP)

# Plus de feu, plus grande explosion ; une bombe gonflée monte au-delà, jusqu'au niveau 6.
func test_fire_and_pumping_make_bigger_blasts() -> void:
	var w := _world([Vector2(1.5, 1.5)])
	var p := w.players[0] as PlayerState
	p.fire = 3
	w.step({0: _intent(true)})
	var b: BombState = w.bombs.values()[0]
	assert_eq(Items.level_of(w, b), 3)
	w.step({0: _intent(false, true)}) # soulève sa bombe
	for _i in 5:
		w.step({0: _intent(true)}) # gonfle
	assert_eq(b.pump, SimConfig.PUMP_MAX, "gonflée au maximum")
	assert_eq(Items.level_of(w, b), SimConfig.LEVEL_MAX)
	assert_almost(Items.radius_of(w, b), SimConfig.blast_radius(SimConfig.LEVEL_MAX), 0.001)

func test_bomb_item_allows_more_bombs() -> void:
	var w := _world([Vector2(1.5, 1.5)])
	var p := w.players[0] as PlayerState
	p.max_bombs = 3
	for x in [1.5, 3.5, 5.5, 7.5]:
		p.pos = Vector2(x, 1.5)
		w.step({0: _intent(true)})
	assert_eq(w.bombs.size(), 3)

# Avec Puissance, l'explosion traverse les blocs.
func test_power_blasts_go_through_blocks() -> void:
	var a := Fixtures.flat(9, 3)
	a.set_tile(Vector2i(3, 1), Arena.Tile.BLOCK)
	a.set_tile(Vector2i(4, 1), Arena.Tile.BLOCK)
	assert_false(Vector2i(4, 1) in Explosion.hit_cells(a, Vector2i(2, 1), 2.0), "le premier bloc protège")
	assert_true(Vector2i(4, 1) in Explosion.hit_cells(a, Vector2i(2, 1), 2.0, true), "traversé")

func test_remote_bombs_wait_for_the_button() -> void:
	var w := _world([Vector2(1.5, 1.5)])
	var p := w.players[0] as PlayerState
	p.remote = true
	w.step({0: _intent(true)})
	p.pos = Vector2(5.5, 1.5)
	w.step({0: _intent(true)})
	_wait(w, SimConfig.FUSE + 1.0)
	assert_eq(w.bombs.size(), 2, "n'explosent pas seules")
	w.step({0: _intent(false, false, true)})
	assert_eq(w.bombs.size(), 1, "la plus ancienne saute")
	assert_true(w.bombs.values()[0].cell == Vector2i(5, 1), "la seconde attend")

func test_losing_a_life_loses_the_remote_and_the_sickness() -> void:
	var w := _world([Vector2(1.5, 1.5), Vector2(7.5, 1.5)])
	var p := w.players[0] as PlayerState
	p.remote = true
	p.fire = 3
	p.sick = SimConfig.Sick.BIG
	p.sick_timer = 5.0
	w.step({0: _intent(true)})
	w.kill(0, "drown")
	assert_false(p.remote, "plus de télécommande")
	assert_eq(p.sick, SimConfig.Sick.NONE, "guéri")
	assert_eq(p.fire, 3, "le feu reste")
	assert_false(w.bombs.values()[0].remote, "sa bombe redevient à mèche")

func test_heart_takes_one_blast() -> void:
	var w := _world([Vector2(3.5, 1.5), Vector2(8.5, 0.5)])
	var p := w.players[0] as PlayerState
	p.heart = true
	w.add_bomb(1, Vector2i(3, 1), 0.05)
	_wait(w, 0.3)
	assert_eq(p.lives, 3, "le cœur encaisse")
	assert_false(p.heart, "cœur perdu")
	_wait(w, SimConfig.INVULNERABLE_TIME)
	w.add_bomb(1, Vector2i(3, 1), 0.05)
	_wait(w, 0.3)
	assert_eq(p.lives, 2, "le coup suivant tue")

func test_skull_makes_sick_then_wears_off() -> void:
	var w := _world([Vector2(1.5, 1.5)])
	w.items[Vector2i(2, 1)] = SimConfig.Item.SKULL
	_wait(w, 0.5, {0: _go(Vector2(2.5, 1.5))})
	var p := w.players[0] as PlayerState
	assert_true(p.sick != SimConfig.Sick.NONE, "malade")
	_wait(w, SimConfig.SICK_TIME)
	if p.life == PlayerState.Life.ALIVE:
		assert_eq(p.sick, SimConfig.Sick.NONE, "guéri")

func test_sicknesses() -> void:
	var w := _world([Vector2(1.5, 1.5)])
	var p := w.players[0] as PlayerState
	p.sick_timer = 10.0
	p.sick = SimConfig.Sick.BIG
	assert_almost(Items.speed_of(w, p), SimConfig.PLAYER_SPEED * SimConfig.BIG_SPEED, 0.001, "lent")
	p.sick = SimConfig.Sick.TINY
	assert_almost(Items.speed_of(w, p), SimConfig.PLAYER_SPEED * SimConfig.TINY_SPEED, 0.001, "rapide")
	p.sick = SimConfig.Sick.DISARMED
	w.step({0: _intent(true)})
	assert_true(w.bombs.is_empty(), "désarmé")
	p.sick = SimConfig.Sick.REVERSE
	_wait(w, 0.3, {0: _go(Vector2(5.5, 1.5))})
	assert_true(p.pos.x < 1.5, "part à l'opposé")
	p.pos = Vector2(4.5, 1.5)
	p.sick = SimConfig.Sick.INSTANT
	w.step({0: _intent(true)})
	assert_almost(w.bombs.values()[0].fuse, SimConfig.INSTANT_FUSE, 0.05, "mèche courte")
	p.pos = Vector2(8.5, 1.5) # out of its blast
	_wait(w, 1.5)
	p.sick = SimConfig.Sick.DISGUISE
	w.step({0: _intent(true)})
	assert_eq(Items.level_of(w, w.bombs.values()[0]), SimConfig.LEVEL_MAX, "puissance d'une bombe gonflée")

# En feu : il faut éliminer quelqu'un avant la fin, sinon on brûle.
func test_on_fire_burns_unless_killing_someone() -> void:
	var w := _world([Vector2(1.5, 1.5), Vector2(7.5, 1.5), Vector2(4.5, 0.5)])
	var p := w.players[0] as PlayerState
	p.sick = SimConfig.Sick.FIRE
	p.sick_timer = 0.5
	_wait(w, 0.6)
	assert_eq(p.lives, 2, "brûlé")
	var q := w.players[1] as PlayerState
	q.sick = SimConfig.Sick.FIRE
	q.sick_timer = 5.0
	w.kill(2, "explosion", 1)
	assert_eq(q.sick, SimConfig.Sick.NONE, "guéri en éliminant quelqu'un")

func test_a_thrown_skull_makes_its_target_sick() -> void:
	var w := _world([Vector2(1.5, 1.5), Vector2(4.5, 1.5)]) # a throw lands 3 cells ahead
	var p := w.players[0] as PlayerState
	p.facing = Vector2i(1, 0)
	p.aim = Vector2i(1, 0)
	w.items[Vector2i(2, 1)] = SimConfig.Item.SKULL
	w.step({0: _intent(false, true)})
	assert_eq(p.held, PlayerState.Held.ITEM, "tête de mort en main")
	assert_eq(p.sick, SimConfig.Sick.NONE, "sans tomber malade")
	w.step({0: _intent(false, true)})
	_wait(w, SimConfig.THROW_FLIGHT + 0.1)
	assert_true((w.players[1] as PlayerState).sick != SimConfig.Sick.NONE, "la cible tombe malade")

func test_evil_happens_to_everyone_for_a_while() -> void:
	var w := _world([Vector2(1.5, 1.5), Vector2(7.5, 1.5)])
	w.items[Vector2i(2, 1)] = SimConfig.Item.EVIL
	_wait(w, 0.5, {0: _go(Vector2(2.5, 1.5))})
	assert_true(w.evil != SimConfig.Evil.NONE, "le Mal se déclenche")
	_wait(w, SimConfig.EVIL_TIME)
	assert_eq(w.evil, SimConfig.Evil.NONE, "puis s'arrête")

func test_evil_effects() -> void:
	var w := _world([Vector2(1.5, 1.5), Vector2(7.5, 1.5)])
	var p := w.players[0] as PlayerState
	w.evil = SimConfig.Evil.GULLIVER
	w.evil_timer = 5.0
	assert_almost(Items.speed_of(w, p), SimConfig.PLAYER_SPEED * SimConfig.BIG_SPEED, 0.001, "Gulliver : lents")
	w.evil = SimConfig.Evil.MAXIMUM
	w.step({0: _intent(true)})
	assert_eq(Items.level_of(w, w.bombs.values()[0]), SimConfig.LEVEL_MAX, "Maximum")
	w.bombs.clear()
	w.evil = SimConfig.Evil.THROW
	p.aim = Vector2i(1, 0)
	w.step({0: _intent(true)})
	assert_eq(w.flying.size(), 1, "Lancers : la bombe part en l'air")
	var swapped := false
	for _i in 10:
		Items._shuffle(w)
		var spots := [w.players[0].pos, w.players[1].pos]
		assert_true(Vector2(1.5, 1.5) in spots and Vector2(7.5, 1.5) in spots, "Mélange : mêmes places")
		swapped = swapped or w.players[0].pos == Vector2(7.5, 1.5)
	assert_true(swapped, "Mélange : places échangées")

func test_twister_flings_whoever_it_touches() -> void:
	var w := _world([Vector2(4.5, 4.5)], Fixtures.flat(9, 9)) # flung 3 cells any way, it lands
	w.evil = SimConfig.Evil.TWISTER
	w.evil_timer = 5.0
	w.twister_pos = Vector2(4.5, 4.5)
	w.twister_dir = Vector2.RIGHT
	w.step({})
	var p := w.players[0] as PlayerState
	assert_eq(p.carried_by, Carry.THROWN, "projeté")
	_wait(w, SimConfig.THROW_FLIGHT + 0.1)
	assert_true(p.stun_timer > 0.0, "assommé à l'atterrissage")

func test_plague_makes_someone_dizzy() -> void:
	var w := _world([Vector2(1.5, 1.5)])
	w.evil = SimConfig.Evil.PLAGUE
	w.evil_timer = 5.0
	w.step({})
	assert_true((w.players[0] as PlayerState).stun_timer > 0.0, "pris de vertige")
