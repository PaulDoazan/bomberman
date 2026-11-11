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
	assert_true(w.hidden.size() > 5, "des objets cachés")
	for item: int in SimConfig.ITEM_LABELS:
		cfg.items[item] = false
	var w2 := World.new(Fixtures.flat(9, 9), [0] as Array[int], cfg, RandomNumberGenerator.new())
	assert_true(w2.hidden.is_empty(), "aucun objet quand tout est désactivé")
	cfg.items = {SimConfig.Item.FIRE: false, SimConfig.Item.BOMB: false,
			SimConfig.Item.REMOTE: false, SimConfig.Item.COFFEE: false}
	var w3 := World.new(a, [0] as Array[int], cfg, RandomNumberGenerator.new())
	for item: int in w3.hidden.values():
		assert_eq(item, SimConfig.Item.HEART, "seulement les objets activés")

# Un bloc détruit révèle son objet, intact ; une explosion suivante le laisse aussi.
func test_blown_block_reveals_its_item_and_blasts_leave_it() -> void:
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
	assert_eq(w.items.get(Vector2i(4, 1)), SimConfig.Item.FIRE, "une explosion ne le détruit pas")

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
	w.items[Vector2i(5, 1)] = SimConfig.Item.HEART
	w.items[Vector2i(6, 1)] = SimConfig.Item.REMOTE
	_wait(w, 2.0, {0: _go(Vector2(6.5, 1.5))})
	var p := w.players[0] as PlayerState
	assert_true(w.items.is_empty(), "tout ramassé")
	assert_eq(p.fire, 2, "portée +1")
	assert_eq(p.max_bombs, SimConfig.MAX_BOMBS + 1, "une bombe de plus")
	assert_true(p.heart and p.remote, "cœur, télécommande")

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

func test_coffee_makes_sick_then_wears_off() -> void:
	var w := _world([Vector2(1.5, 1.5)])
	w.items[Vector2i(2, 1)] = SimConfig.Item.COFFEE
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

func test_a_thrown_coffee_makes_its_target_sick() -> void:
	var w := _world([Vector2(1.5, 1.5), Vector2(4.5, 1.5)]) # a throw lands 3 cells ahead
	var p := w.players[0] as PlayerState
	p.facing = Vector2i(1, 0)
	p.aim = Vector2i(1, 0)
	w.items[Vector2i(2, 1)] = SimConfig.Item.COFFEE
	w.step({0: _intent(false, true)})
	assert_eq(p.held, PlayerState.Held.ITEM, "café navette en main")
	assert_eq(p.sick, SimConfig.Sick.NONE, "sans tomber malade")
	w.step({0: _intent(false, true)})
	_wait(w, SimConfig.THROW_FLIGHT + 0.1)
	assert_true((w.players[1] as PlayerState).sick != SimConfig.Sick.NONE, "la cible tombe malade")

# Mort avec des bombes en plus : elles jaillissent autour, et les autres peuvent les ramasser.
func test_a_dead_player_spills_their_bomb_items() -> void:
	var w := _world([Vector2(4.5, 1.5), Vector2(0.5, 1.5)])
	var p := w.players[0] as PlayerState
	p.max_bombs = SimConfig.MAX_BOMBS + 3
	w.kill(0, "explosion")
	assert_eq(p.max_bombs, SimConfig.MAX_BOMBS, "il les perd")
	assert_eq(w.drops.size(), 3, "trois bombes jaillissent")
	for d: Drop in w.drops:
		assert_eq(d.item, SimConfig.Item.BOMB)
		assert_true(d.cell != p.cell() and absi(d.cell.x - 4) <= SimConfig.DROP_REACH, "autour du mort")
	assert_true(w.items.is_empty(), "encore en l'air")
	_wait(w, SimConfig.SPILL_FLIGHT + 0.05)
	assert_eq(w.items.size(), 3, "au sol")
	assert_true(w.drops.is_empty())
	var cells: Array = w.items.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	var q := w.players[1] as PlayerState
	_wait(w, 3.0, {1: _go(Arena.center_of(cells[-1]))})
	assert_true(q.max_bombs > SimConfig.MAX_BOMBS, "un autre les ramasse")

func test_dying_without_bomb_items_spills_nothing() -> void:
	var w := _world([Vector2(4.5, 1.5)])
	w.kill(0, "explosion")
	assert_true(w.drops.is_empty())

# Des caisses descendent en parachute pendant la partie, avec un objet dedans.
func test_crates_come_down_with_items() -> void:
	var w := _world([Vector2(0.5, 0.5)], Fixtures.flat(9, 9))
	w.cfg.items[SimConfig.Item.HEART] = true
	_wait(w, SimConfig.CRATE_FIRST - 0.1)
	assert_true(w.drops.is_empty(), "pas encore")
	_wait(w, 0.2)
	assert_eq(w.drops.size(), 1, "une caisse descend")
	var d: Drop = w.drops[0]
	assert_eq(d.kind, Drop.Kind.CRATE)
	assert_eq(d.item, SimConfig.Item.HEART, "un objet activé")
	_wait(w, SimConfig.CRATE_FALL)
	assert_eq(w.items.get(d.cell), SimConfig.Item.HEART, "posée, elle laisse son objet")
	_wait(w, SimConfig.CRATE_EVERY - SimConfig.CRATE_FALL)
	assert_eq(w.drops.size(), 1, "la suivante")

func test_no_crates_when_every_item_is_off() -> void:
	var w := _world([Vector2(0.5, 0.5)])
	_wait(w, SimConfig.CRATE_FIRST + 1.0)
	assert_true(w.drops.is_empty())

func test_a_drop_whose_cell_got_taken_lands_next_to_it() -> void:
	var w := _world([Vector2(0.5, 0.5)])
	var d := Drop.new()
	d.kind = Drop.Kind.CRATE
	d.item = SimConfig.Item.BOMB
	d.cell = Vector2i(4, 1)
	w.drops.append(d)
	w.items[Vector2i(4, 1)] = SimConfig.Item.FIRE
	_wait(w, SimConfig.CRATE_FALL + 0.05)
	assert_eq(w.items.size(), 2)
	assert_eq(w.items.get(Vector2i(4, 1)), SimConfig.Item.FIRE, "l'autre reste")
