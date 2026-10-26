# Bomberman POC solo : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** un Bomberman 64-like jouable dans le navigateur, en solo contre 1 à 9 bots. Il comprend la map temple à étages générée, le déplacement souris, les bombes en demi-sphère, soulever et lancer, la montée des eaux, les vies, les fantômes et des manches sans fin.

**Architecture :** toute la logique du jeu vit dans `src/sim/`, en classes `RefCounted` pures, sans aucun `Node`. Elle avance à pas fixe (30 ticks/s) à partir d'**intentions** (`PlayerIntent`) fournies par l'humain ou par les bots. La présentation 3D (`src/game/`) ne fait que lire l'état de la simulation et produire les intentions du joueur local. C'est ce découpage qui permettra plus tard de faire tourner `src/sim/` sur un serveur WebSocket.

**Tech Stack :** Godot 4.7.2 (GDScript typé, renderer Compatibility), export Web sans threads, tests via un mini-runner GDScript headless (aucun addon).

**Spec :** `docs/superpowers/specs/2026-10-26-bomberman-poc-solo-design.md`, avec la capture de référence `docs/reference/bomberman64-temple.png`.

## Global Constraints

- Binaire Godot : `GODOT=/Applications/Godot.app/Contents/MacOS/Godot` (version `4.7.2.stable`). Toutes les commandes de ce plan supposent `export GODOT=...`.
- GDScript uniquement : pas de C#, qui n'est pas supporté en export web.
- Renderer `gl_compatibility`, obligatoire pour le web.
- `src/sim/` et `src/bots/` n'utilisent **jamais** de `Node`, d'`Input` ni de scène. Toutes les valeurs de règles sont des constantes de `SimConfig`.
- Le hasard passe par un `RandomNumberGenerator` injecté, jamais par `randi()` global.
- Unités : 1 case = 1,0 unité. Une case `(i,j)` couvre `[i,i+1)×[j,j+1)`, et son centre est `(i+0.5, j+0.5)`. En 3D, `x = tile.x`, `z = tile.y`, `y = h2 * 0.5`.
- Hauteurs en **demi-niveaux** (`h2`, entier) : fosse `-2`, escalier fosse↔sol `-1`, sol `0`, escalier `1`, 1er étage `2`, escalier `3`, sommet `4`. `level_of(h2) = floori(h2 / 2.0)`.
- Valeurs de la spec : 3 vies par défaut (réglable 1 à 9), 1 à 9 bots, chrono 120 s par défaut (réglable 30 à 300), 2 bombes max, rayon du dôme 3,0, mèche 2,5 s, possession 5 s, recharge 10 s, réapparition après 2 s et invulnérabilité 2 s, un palier d'eau toutes les 20 s, blocs sur 45 % des cases libres, taille par défaut 19×15.
- Textes de l'interface en français.
- Commits : un commit par tâche, message en anglais, terminé par la ligne `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. Une correction d'un commit non poussé se fait avec `git commit --fixup=<sha>`.

## Review Focus

1. **Pointeur hors de la map ou au-dessus du vide** (sur l'eau, ou au-dessus d'un étage plus haut) : le perso continue vers le point projeté sur le plan de son niveau, sans erreur. Si le rayon est parallèle au plan, il s'arrête. Testé en Tâche 10 (`test_ray_plane_parallel_returns_null`, `test_ray_plane_hits_level_height`).
2. **Plus aucune case sèche pour réapparaître**, quand l'eau a tout couvert : le joueur est éliminé, sans boucle infinie ni crash. Testé en Tâche 5 (`test_no_dry_cell_eliminates_player`).
3. **Les derniers vivants meurent au même tick** (même explosion, ou même palier d'eau) : ils sont ex aequo et chacun marque un point. Testé en Tâches 5 et 8.
4. **Bot coincé sans aucune case sûre** : `decide()` renvoie une intention valide, sans erreur ni pose de bombe suicidaire. Testé en Tâche 9 (`test_trapped_bot_returns_intent`).
5. **10 joueurs sur la plus petite map** : 10 départs distincts, dégagés et tous reliés au sommet. Testé en Tâche 2 (`test_generate_all_sizes_ten_players`).

---

## Structure des fichiers

```
project.godot                      réglages projet, input map, autoload Session
export_presets.cfg                 preset "Web" (Tâche 12)
src/session.gd                     autoload : SimConfig choisi à l'écran de réglages
src/sim/sim_config.gd              SimConfig : constantes de règles + réglages de partie
src/sim/arena.gd                   Arena : grille, hauteurs, tuiles, requêtes de terrain
src/sim/map_gen.gd                 MapGen : plan temple proportionnel + blocs + départs
src/sim/player_intent.gd           PlayerIntent
src/sim/player_state.gd            PlayerState
src/sim/bomb_state.gd              BombState
src/sim/flying_object.gd           FlyingObject (objet lancé en vol)
src/sim/explosion.gd               Explosion : cases touchées par le dôme + état actif
src/sim/movement.gd                Movement : pilotage vers la cible, glissement, aide aux coins
src/sim/world.gd                   World : simulation d'une manche
src/sim/match_state.gd             MatchState : joueurs, victoires, enchaînement des manches
src/bots/danger_map.gd             DangerMap
src/bots/bot_brain.gd              BotBrain
src/game/game.tscn + game.gd       scène de jeu : boucle à pas fixe, câblage
src/game/arena_view.gd             maillages du terrain, blocs, eau
src/game/actors_view.gd            joueurs, fantômes, bombes, objets en vol, dômes
src/game/camera_rig.gd             caméra fixe inclinée + projection souris
src/game/input_controller.gd       souris/clavier → PlayerIntent
src/game/hud.gd                    bandeau, chrono, alerte eau, tableau des scores
src/ui/settings_screen.tscn + .gd  écran de réglages (scène principale)
tests/test_case.gd                 base d'assertions
tests/run_tests.gd                 runner headless
tests/fixtures.gd                  arènes construites à la main
tests/test_*.gd                    un fichier par tâche
```

---

### Tâche 1 : Projet Godot, runner de tests, SimConfig et PlayerIntent

**Files :**
- Create : `project.godot`, `src/sim/sim_config.gd`, `src/sim/player_intent.gd`, `tests/test_case.gd`, `tests/run_tests.gd`, `tests/test_sim_config.gd`

**Interfaces :**
- Produces :
  - `class_name SimConfig extends RefCounted`, avec les constantes `TICK_RATE := 30`, `DT := 1.0 / 30.0`, `MAP_SIZES := {"petite": Vector2i(15,13), "normale": Vector2i(19,15), "grande": Vector2i(25,19), "immense": Vector2i(31,23)}`, `MAP_SIZE_LABELS := {"petite":"Petite","normale":"Normale","grande":"Grande","immense":"Immense"}`, `PLAYER_SPEED := 4.0`, `GHOST_SPEED := 4.5`, `PLAYER_HALF := 0.35`, `CORNER_ASSIST := 0.35`, `STOP_DISTANCE := 0.1`, `MAX_BOMBS := 2`, `BOMB_RADIUS := 3.0`, `FUSE := 2.5`, `EXPLOSION_DURATION := 0.5`, `RESPAWN_DELAY := 2.0`, `INVULNERABLE_TIME := 2.0`, `WATER_STEP_INTERVAL := 20.0`, `WATER_WARNING := 3.0`, `WATER_STEPS := [-1, 1, 3, 4]`, `WATER_START_H2 := -3`, `POSSESS_DURATION := 5.0`, `POSSESS_COOLDOWN := 10.0`, `POSSESS_REACH := 0.6`, `THROW_DISTANCE := 3`, `THROW_FLIGHT := 0.5`, `STUN_TIME := 1.5`, `CARRY_ESCAPE := 3.0`, `BLOCK_DENSITY := 0.45`, `SPAWN_CLEARANCE := 2`, `SCOREBOARD_DURATION := 4.0`, `PLAYER_COLORS: Array[Color]` (10 couleurs bien distinctes). Les variables réglables sont `bot_count := 3` (1 à 9), `map_size := "normale"`, `round_time := 120.0` (30 à 300) et `lives := 3` (1 à 9). La méthode `func grid_size() -> Vector2i` renvoie `MAP_SIZES[map_size]`, et `func player_count() -> int` renvoie `bot_count + 1`.
  - `class_name PlayerIntent extends RefCounted` : `var moving := false`, `var target := Vector2.ZERO` (en coordonnées de case), `var place_bomb := false`, `var action := false`.
  - Le runner : `$GODOT --headless --path . -s res://tests/run_tests.gd`, ou `... -- --only=test_xxx` pour lancer un seul fichier. Code de sortie 1 si au moins un test échoue.

- [ ] **Step 1 : créer `project.godot`**

Nom `Bomberman`, `config/features=PackedStringArray("4.7", "GL Compatibility")`, `rendering/renderer/rendering_method="gl_compatibility"` (desktop et mobile), fenêtre 1280×720, `display/window/stretch/mode="canvas_items"`, `aspect="expand"`. Input map : `move` (bouton gauche de la souris), `action` (bouton droit), `place_bomb` (touche Espace). La scène principale sera ajoutée en Tâche 11.

- [ ] **Step 2 : écrire `tests/test_case.gd` et `tests/run_tests.gd`**

`TestCase extends RefCounted` fournit `assert_eq(a, b, msg := "")`, `assert_true(c, msg := "")`, `assert_false(c, msg := "")`, `assert_almost(a: float, b: float, eps := 0.01, msg := "")` et `var failures: Array[String]`. Chaque assertion qui échoue ajoute `"<msg> : attendu <b>, obtenu <a>"`.

```gdscript
# tests/run_tests.gd
extends SceneTree

func _init() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	var total := 0
	var failed := 0
	for file in DirAccess.get_files_at("res://tests"):
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd":
			continue
		if only != "" and file.get_basename() != only:
			continue
		var script: GDScript = load("res://tests/" + file)
		for m in script.get_script_method_list():
			if not m.name.begins_with("test_"):
				continue
			var t: TestCase = script.new()
			t.call(m.name)
			total += 1
			if t.failures.is_empty():
				print("  ok   ", file, "::", m.name)
			else:
				failed += 1
				print("  FAIL ", file, "::", m.name)
				for f in t.failures:
					print("       ", f)
	print("%d tests, %d échecs" % [total, failed])
	quit(1 if failed > 0 else 0)
```

- [ ] **Step 3 : écrire le test qui échoue, `tests/test_sim_config.gd`**

```gdscript
extends TestCase

func test_defaults_match_spec() -> void:
	var c := SimConfig.new()
	assert_eq(c.lives, 3)
	assert_eq(c.round_time, 120.0)
	assert_eq(c.grid_size(), Vector2i(19, 15))
	assert_eq(c.player_count(), c.bot_count + 1)
	assert_eq(SimConfig.PLAYER_COLORS.size(), 10)

func test_all_map_sizes_are_odd() -> void:
	for k in SimConfig.MAP_SIZES:
		var s: Vector2i = SimConfig.MAP_SIZES[k]
		assert_true(s.x % 2 == 1 and s.y % 2 == 1, k)
```

- [ ] **Step 4 : importer, lancer, constater l'échec**

Run : `$GODOT --headless --path . --import && $GODOT --headless --path . -s res://tests/run_tests.gd`
Expected : erreur de parse sur `SimConfig` introuvable, ou FAIL.

- [ ] **Step 5 : implémenter `SimConfig` et `PlayerIntent`**

- [ ] **Step 6 : relancer**

Run : `$GODOT --headless --path . --import && $GODOT --headless --path . -s res://tests/run_tests.gd`
Expected : `2 tests, 0 échecs`, code de sortie 0. Il faut relancer `--import` chaque fois qu'un nouveau `class_name` apparaît.

- [ ] **Step 7 : commit**

```bash
git add project.godot src tests
git commit -m "Set up Godot project, headless test runner and sim config"
```

---

### Tâche 2 : Arena et génération du temple

**Files :**
- Create : `src/sim/arena.gd`, `src/sim/map_gen.gd`, `tests/fixtures.gd`, `tests/test_map_gen.gd`, `tests/test_arena.gd`

**Interfaces :**
- Consumes : `SimConfig` (Tâche 1).
- Produces :
  - `class_name Arena extends RefCounted` : `enum Tile { FLOOR, PILLAR, BLOCK, STAIRS }`, `enum Axis { NONE, X, Y }`, `var width: int`, `var height: int`, `var h2: PackedInt32Array`, `var tiles: PackedInt32Array`, `var stair_axis: PackedInt32Array`, `var spawns: Array[Vector2i]`, `var goal: Vector2i`.
  - `static func create(w: int, h: int) -> Arena` crée une arène de sol plat, `h2 = 0` partout.
  - `func in_bounds(c: Vector2i) -> bool`, `func h2_at(c) -> int`, `func tile_at(c) -> int`, `func set_cell(c: Vector2i, tile: int, h2v: int, axis := Axis.NONE)`, `func set_tile(c, tile)`, `static func level_of(h2v: int) -> int`, `func is_solid(c) -> bool` (PILLAR ou BLOCK ; une case hors de la grille est solide), `func can_step(a: Vector2i, b: Vector2i) -> bool`, `func walkable_neighbors(c: Vector2i) -> Array[Vector2i]`, `static func cell_of(p: Vector2) -> Vector2i`, `static func center_of(c: Vector2i) -> Vector2`.
  - `can_step(a, b)` décrit seulement le terrain, pour `b` voisin de `a` (distance de Chebyshev 1). Il est faux si `b` est hors grille ou solide, ou si `abs(h2_a - h2_b) > 1`. Si `a` ou `b` est un escalier, le pas doit être orthogonal et suivre l'axe de cet escalier. Un pas diagonal est faux dès qu'un escalier est en jeu.
  - `class_name MapGen` : `static func generate(size: Vector2i, player_count: int, rng: RandomNumberGenerator) -> Arena`.
  - `tests/fixtures.gd` (`class_name Fixtures`) : `static func flat(w: int, h: int) -> Arena`.

**Plan du temple** (algorithme fixé, reproduit les proportions de la maquette A ; `W, H` impairs, `cx = W / 2`) :

```
a1 = roundi(W*0.22); L1 = x ∈ [cx-a1, cx+a1], y ∈ [roundi(H*0.16), roundi(H*0.6)]   h2 = 2
a2 = max(1, roundi(W*0.09)); L2 = x ∈ [cx-a2, cx+a2], y ∈ [L1.y0+1, L1.y0+max(2, roundi(H*0.2))]   h2 = 4
ap = roundi(W*0.13); fosse = x ∈ [cx-ap, cx+ap], y ∈ [L1.y1+3, H-2]   h2 = -2
piliers : toute case de sol (h2 = 0) avec x impair ET y impair
escaliers sol→L1 (h2 = 1) : gauche x = L1.x0-1 et droite x = L1.x1+1, axe X, sur les lignes y = ym, ym+1 avec ym = (L1.y0+L1.y1)/2 ;
                     devant y = L1.y1+1, axe Y, sur les colonnes x ∈ [cx-1, cx+1]
escalier L1→sommet (h2 = 3) : x = cx, y = L2.y1+1, axe Y
escaliers fosse↔sol (h2 = -1) : x = fosse.x0-1 et x = fosse.x1+1, axe X, sur la ligne y = (fosse.y0+fosse.y1)/2
un escalier remplace un pilier ; la case juste à l'extérieur de chaque escalier (côté bas, et côté haut s'il est sur le sol) perd aussi son pilier
goal = (cx, (L2.y0+L2.y1)/2)
départs : on parcourt le pourtour du sol dans le sens horaire depuis (0,0), puis on prend player_count indices régulièrement espacés : i * perim.size() / player_count
blocs : chaque case FLOOR non pilier, hors sommet, hors escalier, hors goal, à distance de Manhattan > SPAWN_CLEARANCE de tout départ, devient BLOCK si rng.randf() < BLOCK_DENSITY
```

- [ ] **Step 1 : écrire les tests qui échouent**

`tests/test_arena.gd` :

```gdscript
extends TestCase

func test_step_rules() -> void:
	var a := Fixtures.flat(5, 5)
	a.set_cell(Vector2i(2, 2), Arena.Tile.STAIRS, 1, Arena.Axis.X)
	a.set_cell(Vector2i(3, 2), Arena.Tile.FLOOR, 2)
	assert_true(a.can_step(Vector2i(1, 2), Vector2i(2, 2)), "monter sur l'escalier dans l'axe")
	assert_true(a.can_step(Vector2i(2, 2), Vector2i(3, 2)), "escalier vers l'étage")
	assert_false(a.can_step(Vector2i(2, 1), Vector2i(2, 2)), "entrer sur l'escalier par le côté")
	assert_false(a.can_step(Vector2i(3, 1), Vector2i(3, 2)), "sol vers l'étage sans escalier")
	assert_false(a.can_step(Vector2i(0, 0), Vector2i(-1, 0)), "hors grille")
	a.set_tile(Vector2i(1, 1), Arena.Tile.PILLAR)
	assert_false(a.can_step(Vector2i(0, 1), Vector2i(1, 1)), "pilier")

func test_level_of() -> void:
	assert_eq(Arena.level_of(-1), -1)
	assert_eq(Arena.level_of(1), 0)
	assert_eq(Arena.level_of(4), 2)
```

`tests/test_map_gen.gd` : un helper local `_reachable(a: Arena, from: Vector2i) -> Dictionary` (parcours en largeur sur `walkable_neighbors`, **en traitant les BLOCK comme franchissables**, puisqu'ils sont destructibles).

```gdscript
func test_default_layout_has_all_levels() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 1
	var a := MapGen.generate(Vector2i(19, 15), 4, rng)
	var seen := {}
	for v in a.h2: seen[v] = true
	for v in [-2, -1, 0, 1, 2, 3, 4]: assert_true(seen.has(v), "h2 %d présent" % v)
	assert_eq(a.h2_at(a.goal), 4)

func test_generate_all_sizes_ten_players() -> void:
	for k in SimConfig.MAP_SIZES:
		var rng := RandomNumberGenerator.new(); rng.seed = 7
		var a := MapGen.generate(SimConfig.MAP_SIZES[k], 10, rng)
		assert_eq(a.spawns.size(), 10, k)
		var uniq := {}
		for s in a.spawns:
			uniq[s] = true
			assert_eq(a.h2_at(s), 0, k + " départ au sol")
			var r := _reachable(a, s)
			assert_true(r.has(a.goal), k + " sommet atteignable depuis %s" % s)
			for other in a.spawns: assert_true(r.has(other), k + " départs reliés")
		assert_eq(uniq.size(), 10, k + " départs distincts")

func test_spawn_clearance_and_no_blocks_on_summit_or_stairs() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 3
	var a := MapGen.generate(Vector2i(19, 15), 10, rng)
	for y in a.height: for x in a.width:
		var c := Vector2i(x, y)
		if a.tile_at(c) != Arena.Tile.BLOCK: continue
		assert_true(a.h2_at(c) != 4, "pas de bloc au sommet")
		for s in a.spawns:
			assert_true(absi(s.x - x) + absi(s.y - y) > SimConfig.SPAWN_CLEARANCE, "bloc trop près d'un départ")

func test_block_layout_changes_with_seed() -> void:
	var r1 := RandomNumberGenerator.new(); r1.seed = 1
	var r2 := RandomNumberGenerator.new(); r2.seed = 2
	assert_true(MapGen.generate(Vector2i(19, 15), 4, r1).tiles != MapGen.generate(Vector2i(19, 15), 4, r2).tiles)
```

- [ ] **Step 2 : lancer et constater l'échec**

Run : `$GODOT --headless --path . --import && $GODOT --headless --path . -s res://tests/run_tests.gd`
Expected : FAIL (classes absentes).

- [ ] **Step 3 : implémenter `Arena` et `MapGen.generate`** en suivant l'algorithme ci-dessus. Si une taille fait échouer l'atteignabilité, corriger la règle de dégagement des escaliers, pas les tests.

- [ ] **Step 4 : relancer.** Expected : tous les tests passent.

- [ ] **Step 5 : commit**, message `Add arena grid and proportional temple map generator`.

---

### Tâche 3 : World et déplacement

**Files :**
- Create : `src/sim/player_state.gd`, `src/sim/bomb_state.gd`, `src/sim/movement.gd`, `src/sim/world.gd`, `tests/test_movement.gd`

**Interfaces :**
- Consumes : `Arena`, `SimConfig`, `PlayerIntent`.
- Produces :
  - `class_name PlayerState extends RefCounted` : `enum Life { ALIVE, WAITING_RESPAWN, GHOST }`, `enum Held { NONE, BOMB, PLAYER, BLOCK }`. Champs : `id: int`, `pos: Vector2`, `facing := Vector2i(0, 1)`, `lives: int`, `life := Life.ALIVE`, `respawn_timer := 0.0`, `invulnerable_timer := 0.0`, `stun_timer := 0.0`, `held := Held.NONE`, `held_id := -1`, `carried_by := -1`, `carried_timer := 0.0`, `possessed_by := -1`, `possess_target := -1`, `possess_timer := 0.0`, `possess_cooldown := 0.0`, `died_tick := -1`. Méthodes : `func cell() -> Vector2i`, `func is_alive() -> bool` (vrai pour `life != GHOST`), `func can_act() -> bool` (ALIVE, non porté, non étourdi, non possédé).
  - `class_name BombState extends RefCounted` : `enum State { PLACED, HELD, FLYING }`, `id`, `owner_id`, `cell: Vector2i`, `fuse := SimConfig.FUSE`, `state := State.PLACED`, `passable_for: Array[int]`.
  - `class_name Movement` : `static func move(world: World, p: PlayerState, target: Vector2, speed: float, dt: float) -> void` pour un joueur vivant (collision avec terrain et bombes, glissement, aide aux coins, mise à jour de `facing`), et `static func move_free(world: World, p: PlayerState, target: Vector2, speed: float, dt: float) -> void` pour un fantôme (aucune collision, position bornée à la grille).
  - `class_name World extends RefCounted` : `func _init(arena: Arena, player_ids: Array[int], cfg: SimConfig, rng: RandomNumberGenerator)`. Les joueurs démarrent au centre de `arena.spawns[i]` avec `lives = cfg.lives`. Champs : `arena`, `cfg`, `rng`, `players: Dictionary` (id → PlayerState), `bombs: Dictionary` (id → BombState), `explosions: Array`, `flying: Array`, `events: Array[Dictionary]` (vidé au début de chaque `step`), `tick := 0`, `time_left: float` (= `cfg.round_time`), `water_h2 := SimConfig.WATER_START_H2`, `water_warning := false`, `finished := false`, `winners: Array[int]`. Méthodes : `func step(intents: Dictionary) -> void` (id → PlayerIntent, un id absent vaut une intention vide, dt = `SimConfig.DT`), `func bomb_at(c: Vector2i) -> BombState` (ou null), `func is_passable_for(p: PlayerState, from: Vector2i, to: Vector2i) -> bool` (`arena.can_step` et aucune bombe sur `to`, sauf si `p.id` est dans `passable_for`).

**Algorithme de `Movement.move`** (non déterminé par les tests, donc fixé ici) :

```
si distance(pos, target) <= STOP_DISTANCE : ne pas bouger
d = (target - pos).normalized() ; step = d * speed * dt (tronqué à la distance restante)
facing = axe dominant de d (Vector2i, 4 directions)
déplacement en X puis en Y, séparément : on avance l'axe, puis on teste la boîte du joueur
  (demi-côté PLAYER_HALF). Toute case recouverte, différente de la case courante, doit vérifier
  is_passable_for(p, case_courante, case). Sinon, l'axe est recalé contre le bord de la case bloquante.
aide aux coins : si l'axe dominant est bloqué et que l'écart perpendiculaire au centre de la
  case courante vaut ≤ CORNER_ASSIST, et que la case suivante sur l'axe dominant est franchissable
  depuis la case courante, on déplace l'axe perpendiculaire vers ce centre (au plus speed*dt).
recentrage : quand on avance selon un axe dominant sans blocage et que l'écart perpendiculaire
  vaut ≤ CORNER_ASSIST, on rapproche aussi la coordonnée perpendiculaire du centre de la voie
  (au plus 0.5*speed*dt), sauf si la cible elle-même est décalée sur cet axe de plus de 0.5.
après le mouvement : retirer p.id du passable_for de toute bombe que la boîte ne recouvre plus.
```

- [ ] **Step 1 : écrire les tests qui échouent, `tests/test_movement.gd`**

Helper local : `_world(a: Arena, positions: Array[Vector2]) -> World` crée un `World` avec les ids 0..n-1, puis place `players[i].pos = positions[i]`. Helper `_go(w, id, target, seconds)` appelle `step` pendant `roundi(seconds * 30)` ticks avec une intention `moving = true`.

```gdscript
func test_moves_straight_and_stops_at_target() -> void:
	var w := _world(Fixtures.flat(7, 5), [Vector2(0.5, 2.5)])
	_go(w, 0, Vector2(4.5, 2.5), 1.5)
	assert_almost(w.players[0].pos.x, 4.5, 0.05)
	assert_almost(w.players[0].pos.y, 2.5, 0.05)
	assert_eq(w.players[0].facing, Vector2i(1, 0))

func test_no_jitter_when_target_is_reached() -> void:
	var w := _world(Fixtures.flat(5, 5), [Vector2(2.5, 2.5)])
	_go(w, 0, Vector2(2.53, 2.52), 0.5)
	assert_eq(w.players[0].pos, Vector2(2.5, 2.5))

func test_slides_along_wall() -> void:
	var a := Fixtures.flat(6, 6)
	for y in 6: a.set_tile(Vector2i(3, y), Arena.Tile.PILLAR)
	var w := _world(a, [Vector2(1.5, 1.5)])
	_go(w, 0, Vector2(5.5, 4.5), 1.0)
	assert_true(w.players[0].pos.x <= 3.0 - SimConfig.PLAYER_HALF + 0.01, "ne traverse pas")
	assert_true(w.players[0].pos.y > 3.0, "a glissé vers le bas")

func test_corner_assist_enters_corridor() -> void:
	var a := Fixtures.flat(6, 5)
	a.set_tile(Vector2i(2, 1), Arena.Tile.PILLAR); a.set_tile(Vector2i(2, 3), Arena.Tile.PILLAR)
	var w := _world(a, [Vector2(1.5, 2.25)])
	_go(w, 0, Vector2(5.5, 2.25), 1.0)
	assert_true(w.players[0].pos.x > 3.0, "est passé dans le couloir")

func test_blocked_by_level_without_stairs() -> void:
	var a := Fixtures.flat(5, 5)
	for y in 5: a.set_cell(Vector2i(3, y), Arena.Tile.FLOOR, 2)
	var w := _world(a, [Vector2(1.5, 2.5)])
	_go(w, 0, Vector2(4.5, 2.5), 1.0)
	assert_true(w.players[0].pos.x <= 3.0 - SimConfig.PLAYER_HALF + 0.01)

func test_climbs_stairs() -> void:
	var a := Fixtures.flat(5, 5)
	for y in 5: a.set_cell(Vector2i(3, y), Arena.Tile.FLOOR, 2)
	a.set_cell(Vector2i(2, 2), Arena.Tile.STAIRS, 1, Arena.Axis.X)
	var w := _world(a, [Vector2(0.5, 2.5)])
	_go(w, 0, Vector2(3.5, 2.5), 1.5)
	assert_eq(w.players[0].cell(), Vector2i(3, 2))

func test_bomb_blocks_others_but_owner_can_leave() -> void:
	var w := _world(Fixtures.flat(7, 3), [Vector2(1.5, 1.5), Vector2(5.5, 1.5)])
	var i := PlayerIntent.new(); i.place_bomb = true
	w.step({0: i})
	w.bombs.values()[0].fuse = 100.0         # pas d'explosion pendant ce test
	_go(w, 0, Vector2(0.5, 1.5), 0.5)        # le poseur quitte sa bombe
	assert_eq(w.players[0].cell(), Vector2i(0, 1))
	_go(w, 0, Vector2(3.5, 1.5), 1.0)        # puis ne peut plus y revenir
	assert_true(w.players[0].pos.x <= 1.0 - SimConfig.PLAYER_HALF + 0.01)
	_go(w, 1, Vector2(0.5, 1.5), 1.5)        # l'autre joueur est bloqué
	assert_true(w.players[1].pos.x >= 2.0 + SimConfig.PLAYER_HALF - 0.01)

func test_stunned_player_does_not_move() -> void:
	var w := _world(Fixtures.flat(5, 5), [Vector2(1.5, 1.5)])
	w.players[0].stun_timer = 1.0
	_go(w, 0, Vector2(4.5, 1.5), 0.5)
	assert_eq(w.players[0].pos, Vector2(1.5, 1.5))
```

`test_bomb_blocks_others_but_owner_can_leave` a besoin de la pose de bombe minimale : dans `World.step`, `place_bomb` crée une `BombState` sur la case du joueur, si `can_act()`, si `held == NONE`, si la case n'a pas déjà de bombe et si le joueur a moins de `MAX_BOMBS` bombes actives. Le `passable_for` de cette bombe contient les ids de tous les joueurs dont la boîte la recouvre. La mèche et l'explosion arrivent en Tâche 4.

- [ ] **Step 2 : lancer et constater l'échec.** Run : `$GODOT --headless --path . --import && $GODOT --headless --path . -s res://tests/run_tests.gd -- --only=test_movement`

- [ ] **Step 3 : implémenter `PlayerState`, `BombState`, `Movement`, et `World` (constructeur, `step` réduit aux timers d'étourdissement, au déplacement et à la pose de bombe)**

- [ ] **Step 4 : relancer.** Expected : tous les tests passent.

- [ ] **Step 5 : commit**, message `Add round world with mouse-steered movement, wall sliding and corner assist`.

---

### Tâche 4 : Bombes et explosions en demi-sphère

**Files :**
- Create : `src/sim/explosion.gd`, `tests/test_explosion.gd`
- Modify : `src/sim/world.gd`

**Interfaces :**
- Consumes : `World`, `BombState`, `Arena`.
- Produces :
  - `class_name Explosion extends RefCounted` : `var origin: Vector2i`, `var cells: Array[Vector2i]`, `var timer := SimConfig.EXPLOSION_DURATION`, `var owner_id: int`. La fonction `static func hit_cells(arena: Arena, origin: Vector2i, radius: float) -> Array[Vector2i]` renvoie les cases `c` telles que `distance(center(c), center(origin)) <= radius`, `h2(c) >= 2 * level_of(h2(origin))`, `c` n'est pas un PILLAR, et aucune case **strictement entre** `origin` et `c` sur la ligne (tracé « supercover » de centre à centre) n'est PILLAR ou BLOCK.
  - `World` : la mèche des bombes `PLACED` et `HELD` décroît. À 0, la bombe explose sur sa case, ou sur la case de son porteur si elle est `HELD`. **Réaction en chaîne dans le même tick** : toute bombe sur une case touchée explose aussi. Une case BLOCK touchée devient FLOOR, avec l'événement `{"type":"block_destroyed","cell":c}`. Chaque explosion émet `{"type":"explosion","cell":origin,"radius":BOMB_RADIUS,"cells":cells}`. Pendant toute la durée de vie d'une `Explosion`, tout joueur ALIVE dont la case appartient à `cells` et dont `invulnerable_timer <= 0` subit `func kill(id: int, cause: String) -> void` (cause `"explosion"`).
  - `World.kill` (ici, la version minimale) : `lives -= 1`, `died_tick = tick`, événement `{"type":"death","id":id,"cause":cause}`. Si `lives > 0`, le joueur passe à `WAITING_RESPAWN` avec `respawn_timer = RESPAWN_DELAY`, sinon il devient `GHOST`. La réapparition elle-même est en Tâche 5.

- [ ] **Step 1 : écrire les tests qui échouent, `tests/test_explosion.gd`**

```gdscript
func test_dome_is_round_including_diagonals() -> void:
	var cells := Explosion.hit_cells(Fixtures.flat(9, 9), Vector2i(4, 4), 3.0)
	assert_eq(cells.size(), 29)
	assert_true(Vector2i(6, 6) in cells, "diagonale à 2,83")
	assert_false(Vector2i(7, 6) in cells, "hors rayon à 3,6")

func test_pillar_and_block_shield() -> void:
	var a := Fixtures.flat(9, 9)
	a.set_tile(Vector2i(5, 4), Arena.Tile.PILLAR)
	a.set_tile(Vector2i(4, 5), Arena.Tile.BLOCK)
	var cells := Explosion.hit_cells(a, Vector2i(4, 4), 3.0)
	assert_false(Vector2i(5, 4) in cells); assert_false(Vector2i(6, 4) in cells)
	assert_true(Vector2i(4, 5) in cells, "le bloc est touché"); assert_false(Vector2i(4, 6) in cells, "mais protège derrière lui")

func test_dome_rises_but_never_goes_down() -> void:
	var a := Fixtures.flat(9, 9)
	for y in 9: for x in range(6, 9): a.set_cell(Vector2i(x, y), Arena.Tile.FLOOR, 2)
	a.set_cell(Vector2i(5, 4), Arena.Tile.STAIRS, 1, Arena.Axis.X)
	assert_true(Vector2i(6, 4) in Explosion.hit_cells(a, Vector2i(4, 4), 3.0), "monte à l'étage")
	var down := Explosion.hit_cells(a, Vector2i(6, 4), 3.0)
	assert_false(Vector2i(4, 4) in down, "ne descend pas au sol")
	assert_false(Vector2i(5, 4) in down, "ni sur l'escalier plus bas")
	assert_true(Vector2i(4, 4) in Explosion.hit_cells(a, Vector2i(5, 4), 3.0), "bombe sur l'escalier : niveau 0")
```

Tests de `World`, avec le helper `_world` de la Tâche 3 copié ici :
- `test_bomb_explodes_after_fuse_and_destroys_block` : bloc en (3,1) sur une arène plate 7×3, bombe posée en (1,1), le joueur s'éloigne hors de portée en (6,1) (sur une 9×3) ; après `roundi(2.5*30)` ticks, `tile_at((3,1)) == FLOOR` et un événement `explosion` a été émis.
- `test_max_two_bombs` : trois intentions `place_bomb` sur trois cases différentes donnent `bombs.size() == 2`.
- `test_chain_reaction_same_tick` : la bombe A (mèche 0,1) et la bombe B (mèche 2,0) sont à 2 cases l'une de l'autre ; après 4 ticks, les deux ont disparu et deux événements `explosion` ont été émis le même tick.
- `test_explosion_costs_one_life` : un joueur sur une case touchée passe de 3 à 2 vies et à `WAITING_RESPAWN`. Un second joueur avec `invulnerable_timer = 1.0` garde ses 3 vies.
- `test_last_life_becomes_ghost` : `lives = 1`, touché → `life == GHOST`.

- [ ] **Step 2 : lancer et constater l'échec**, avec `--only=test_explosion`.
- [ ] **Step 3 : implémenter `Explosion` et compléter `World`.**
- [ ] **Step 4 : relancer toute la suite.** Expected : tout passe.
- [ ] **Step 5 : commit**, message `Add hemisphere bomb explosions with line of sight and chain reactions`.

---

### Tâche 5 : Montée des eaux, réapparition et fin de manche

**Files :**
- Create : `tests/test_water_round.gd`
- Modify : `src/sim/world.gd`

**Interfaces :**
- Consumes : `World.kill`, `Explosion`.
- Produces :
  - `World.time_left` décroît. À 0, `water_h2` passe à `WATER_STEPS[0]`, puis au palier suivant toutes les `WATER_STEP_INTERVAL` s. `water_warning` vaut vrai pendant les `WATER_WARNING` s qui précèdent chaque montée, y compris la première. Chaque montée émet `{"type":"water_rise","h2":water_h2}`.
  - `func is_submerged(c: Vector2i) -> bool` : `arena.h2_at(c) <= water_h2`, ou `c` hors grille.
  - Noyade : un joueur ALIVE sur une case submergée subit `kill(id, "drown")`, invulnérable ou non.
  - Réapparition : quand `respawn_timer` atteint 0, `func find_respawn_cell() -> Variant` choisit, au hasard via `rng`, parmi les cases non solides, sans bombe ni explosion active, non submergées, et de `h2` minimal parmi les cases sèches. Le joueur y repasse à ALIVE avec `invulnerable_timer = INVULNERABLE_TIME`. **Si aucune case sèche n'existe**, la fonction renvoie `null` et le joueur est éliminé : `lives = 0`, il devient `GHOST`, et `died_tick` garde la valeur du tick de sa mort.
  - Même règle quand l'eau couvre tout : la noyade d'un joueur sans case sèche disponible l'élimine directement.
  - Fin de manche, vérifiée à la fin de chaque `step` : soit `vivants = joueurs dont life != GHOST`. Si `vivants.size() == 1`, alors `finished = true` et `winners = vivants`. Si `vivants.size() == 0`, alors `finished = true` et `winners` = les joueurs dont `died_tick == tick` et `lives == 0` (ex aequo). Une fois `finished`, `step` ne fait plus rien.

- [ ] **Step 1 : écrire les tests qui échouent**, sur des arènes construites à la main (sol plat, plus une zone `h2 = 4`), avec `cfg.round_time = 1.0` :
  - `test_water_rises_by_steps_after_timer` : `water_h2` vaut `-3` à t = 0,9 s, `-1` à t = 1,0 s + 1 tick, `1` à t = 21 s, `3` à t = 41 s et `4` à t = 61 s.
  - `test_warning_before_each_rise` : `water_warning` est vrai à t = 18,5 s (1,5 s avant le palier de 21 s) et faux à t = 15 s.
  - `test_submerged_player_drowns_and_respawns_on_lowest_dry_cell` : un joueur sur une case `h2 = 0`, d'autres cases sèches à `h2 = 2` et `h2 = 4`, eau à `1`. Il perd 1 vie, puis réapparaît 2 s plus tard sur une case `h2 = 2` avec `invulnerable_timer > 0`.
  - `test_no_dry_cell_eliminates_player` : une arène entièrement à `h2 = 0` et l'eau forcée à `1`. Le joueur (3 vies) devient `GHOST` avec `lives == 0`, sans boucle infinie : la suite de tests se termine.
  - `test_single_survivor_wins` : 3 joueurs, deux tués par `kill` jusqu'à `lives == 0` → `finished` et `winners == [id restant]`.
  - `test_last_players_drowning_together_are_ex_aequo` : 2 joueurs à 1 vie chacun sur la même hauteur, l'eau monte → `winners` contient les deux ids.

- [ ] **Step 2 : lancer et constater l'échec**, avec `--only=test_water_round`.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : relancer toute la suite.**
- [ ] **Step 5 : commit**, message `Add rising water, respawns and round end with ties`.

---

### Tâche 6 : Soulever et lancer

**Files :**
- Create : `src/sim/flying_object.gd`, `tests/test_carry.gd`
- Modify : `src/sim/world.gd`

**Interfaces :**
- Consumes : `World`, `PlayerState.held/held_id/carried_by`, `BombState.State`.
- Produces :
  - `class_name FlyingObject extends RefCounted` : `var kind: int` (`PlayerState.Held`), `var ref_id: int` (id de la bombe ou du joueur, `-1` pour un bloc), `var from: Vector2`, `var landing: Variant` (`Vector2i`, ou `null` si l'objet tombe à l'eau), `var elapsed := 0.0`, `func progress() -> float` (`elapsed / THROW_FLIGHT`, borné à 1).
  - `intent.action` quand `held == NONE` et `can_act()` déclenche **la prise**. On cherche dans cet ordre : une bombe sur sa propre case, puis sur la case `cell() + facing` une bombe, puis un joueur ALIVE non porté, puis un BLOCK. Une bombe passe à `HELD`. Un bloc rend sa case FLOOR. Un joueur passe à `carried_by = id` avec `carried_timer = CARRY_ESCAPE`, et sa position suit celle du porteur.
  - `intent.action` quand `held != NONE` déclenche **le lancer** dans la direction `facing`. La case d'atterrissage est `cell() + facing * THROW_DISTANCE`. Tant qu'elle n'est pas libre, on avance d'une case dans la même direction. Une case libre est une case dans la grille, non solide, non PILLAR, sans bombe, et sans joueur ALIVE pour un bloc ou un joueur lancé ; une bombe peut atterrir sur un joueur. Si on sort de la grille, `landing = null`. Le vol dure `THROW_FLIGHT`, et l'objet peut changer de niveau en atterrissant.
  - À l'atterrissage : une bombe repasse à `PLACED` sur `landing` (sa mèche n'a jamais cessé de décroître), et chaque joueur ALIVE sur cette case reçoit `stun_timer = STUN_TIME`. Un bloc pose `BLOCK` sur `landing`. Un joueur lancé est placé au centre de `landing` avec `stun_timer = STUN_TIME`. Avec `landing == null`, il y a un événement `{"type":"splash","pos":...}` : la bombe disparaît sans exploser, le bloc disparaît, et le joueur lancé subit `kill(id, "drown")`.
  - Joueur porté : `carried_timer` décroît. À 0, il est libéré au centre de la case de son porteur. Si le porteur meurt, ce qu'il tient tombe sur sa case : une bombe repasse à `PLACED`, un joueur est libéré, un bloc est détruit.
  - `place_bomb` est ignoré tant que `held != NONE`.

- [ ] **Step 1 : écrire les tests qui échouent, `tests/test_carry.gd`** (arène plate 9×5 sauf mention contraire, joueur 0 en (1,2) tourné vers `(1,0)`) :
  - `test_pick_up_and_throw_block` : bloc en (2,2), action → `tile_at((2,2)) == FLOOR` et `held == BLOCK`. Action → après `THROW_FLIGHT` + 1 tick, `tile_at((4,2)) == BLOCK`.
  - `test_throw_skips_blocked_landing` : pilier en (4,2), on lance un bloc depuis (1,2) → il atterrit en (5,2).
  - `test_throw_off_map_splashes` : joueur en (7,2), on lance un bloc vers l'est → aucun BLOCK nouveau et un événement `splash`.
  - `test_carried_bomb_keeps_fuse_and_explodes_at_carrier` : bombe à mèche 0,5 ramassée ; 0,6 s plus tard, une explosion a lieu avec `origin == cell()` du porteur.
  - `test_cannot_place_bomb_while_holding` : avec un bloc en main, `place_bomb` ne crée aucune bombe.
  - `test_carry_player_then_escape` : joueur 1 en (2,2), action du joueur 0 → `carried_by == 0`, et une intention de déplacement du joueur 1 ne change pas sa position relative. Après `CARRY_ESCAPE` s, `carried_by == -1`.
  - `test_thrown_player_is_stunned_and_thrown_into_water_loses_life` : lancé vers (4,2) → `stun_timer > 0` à l'atterrissage. Second cas, lancé hors de la map → `lives` diminue de 1.
  - `test_thrown_bomb_stuns_player_on_landing` : joueur 1 en (4,2), on lance une bombe → `players[1].stun_timer > 0`.
  - `test_throw_lands_on_upper_level` : colonnes x ≥ 4 à `h2 = 2`, on lance une bombe depuis (1,2) → la bombe est en (4,2) et son explosion ne touche pas (1,2) (le dôme ne descend pas).

- [ ] **Step 2 : lancer et constater l'échec**, avec `--only=test_carry`.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : relancer toute la suite.**
- [ ] **Step 5 : commit**, message `Add picking up and throwing bombs, players and blocks`.

---

### Tâche 7 : Fantômes et possession

**Files :**
- Create : `tests/test_ghosts.gd`
- Modify : `src/sim/world.gd`

**Interfaces :**
- Consumes : `Movement.move_free`, `PlayerState.possessed_by/possess_target/possess_timer/possess_cooldown`.
- Produces (règles dans `World.step`) :
  - Un `GHOST` se déplace avec `Movement.move_free` à `GHOST_SPEED`. Il ignore `place_bomb` et `action`. L'eau et les explosions ne l'affectent pas.
  - Si un fantôme sans possession en cours, avec `possess_cooldown <= 0`, arrive à une distance `<= POSSESS_REACH` d'un joueur ALIVE non porté, non possédé et non invulnérable, alors `victim.possessed_by = ghost.id`, `ghost.possess_target = victim.id` et `ghost.possess_timer = POSSESS_DURATION`.
  - Pendant la possession, l'intention de la victime est **entièrement ignorée**. Elle se déplace avec `Movement.move` vers le `target` de l'intention du fantôme, si celle-ci a `moving`. Le fantôme reste collé à la victime.
  - Fin de possession : à la fin du timer, ou si la victime meurt ou est portée. On a alors `possessed_by = -1`, `possess_target = -1` et `possess_cooldown = POSSESS_COOLDOWN`.

- [ ] **Step 1 : écrire les tests qui échouent, `tests/test_ghosts.gd`**
  - `test_ghost_passes_through_pillars_and_levels` : fantôme en (0,2), pilier en (2,2) et étage `h2 = 2` en x = 3 ; cible (4,2) → atteinte en 1,5 s.
  - `test_ghost_cannot_place_bomb` : `place_bomb` donne `bombs.is_empty()`.
  - `test_ghost_immune_to_water_and_explosions` : eau au-dessus de tout, plus une explosion sur sa case → `life == GHOST`, aucun événement `death`.
  - `test_possession_moves_victim_with_ghost_target` : la victime en (2,2) veut aller vers l'ouest, le fantôme la touche et vise l'est (6,2). Après 1 s, `victim.pos.x > 3`.
  - `test_possession_ends_after_duration_then_cooldown` : après 5 s, `possessed_by == -1`. Le fantôme reste au contact : pas de nouvelle possession avant 10 s, puis nouvelle possession après 10 s.
  - `test_possessed_victim_can_be_walked_into_water` : la case visée est submergée → la victime perd une vie.

- [ ] **Step 2 : lancer et constater l'échec**, avec `--only=test_ghosts`.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : relancer toute la suite.**
- [ ] **Step 5 : commit**, message `Add ghosts that possess living players`.

---

### Tâche 8 : MatchState, enchaînement des manches et victoires

**Files :**
- Create : `src/sim/match_state.gd`, `tests/test_match.gd`

**Interfaces :**
- Consumes : `World`, `MapGen`, `SimConfig`.
- Produces :
  - `class_name MatchState extends RefCounted` : `class MatchPlayer` (`id: int`, `name: String`, `is_bot: bool`, `color: Color`, `wins := 0`), `enum Phase { PLAYING, ROUND_OVER }`, `var cfg: SimConfig`, `var players: Array[MatchPlayer]`, `var world: World`, `var phase`, `var phase_timer := 0.0`, `var round_number := 0`, `var last_winners: Array[int]`, `var rng: RandomNumberGenerator`.
  - `func _init(cfg: SimConfig, rng: RandomNumberGenerator)` crée l'humain (id 0, nom `"Toi"`) et les bots (ids 1..bot_count, noms `"Bot 1"`…), avec `PLAYER_COLORS[id]`, puis appelle `start_round()`.
  - `func start_round() -> void` génère une nouvelle `Arena` via `MapGen.generate(cfg.grid_size(), players.size(), rng)`, crée un nouveau `World` (les vies repartent à `cfg.lives`), passe en `PLAYING` et incrémente `round_number`. La liste `players` est relue à chaque manche, pour qu'un joueur ajouté entre deux manches y entre tout seul plus tard.
  - `func step(intents: Dictionary) -> void` : en `PLAYING`, appelle `world.step`. Quand `world.finished`, chaque id de `world.winners` reçoit `wins += 1`, `last_winners` est mis à jour et la phase passe à `ROUND_OVER` avec `phase_timer = SCOREBOARD_DURATION`. En `ROUND_OVER`, le timer décroît, puis `start_round()`.
  - `func player(id: int) -> MatchPlayer`.

- [ ] **Step 1 : écrire les tests qui échouent, `tests/test_match.gd`**
  - `test_creates_human_and_bots` : `bot_count = 4` → 5 joueurs, `players[0].is_bot == false`, ids 0..4, `world.players.size() == 5`.
  - `test_winner_scores_then_new_round_starts` : on force `world.kill` sur tous sauf l'id 2 (jusqu'à `lives == 0`), puis un `step` → `player(2).wins == 1` et `phase == ROUND_OVER`. Après `SCOREBOARD_DURATION` s de steps → `phase == PLAYING`, `round_number == 2` et tous les joueurs ont `lives == cfg.lives`.
  - `test_ex_aequo_both_score` : `bot_count = 1`, on met toutes les valeurs de `world.arena.h2` à `-2` et `world.time_left = 0` ; au premier palier les deux se noient sans case sèche → les deux ont `wins == 1`.
  - `test_new_round_reshuffles_blocks` : les `arena.tiles` de la manche 1 et de la manche 2 diffèrent.

- [ ] **Step 2 : lancer et constater l'échec**, avec `--only=test_match`.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : relancer toute la suite.**
- [ ] **Step 5 : commit**, message `Add endless match loop with wins and ties`.

---

### Tâche 9 : Carte des dangers et bots

**Files :**
- Create : `src/bots/danger_map.gd`, `src/bots/bot_brain.gd`, `tests/test_bots.gd`

**Interfaces :**
- Consumes : `World` (bombes, explosions, `is_submerged`, `water_warning`, `time_left`), `Explosion.hit_cells`, `Arena.walkable_neighbors`, `World.is_passable_for`.
- Produces :
  - `class_name DangerMap` : `static func build(world: World, extra_bomb: Variant = null) -> Dictionary`. Elle associe chaque case (Vector2i) au nombre de secondes avant qu'elle soit touchée : `0.0` pour une explosion active, sinon la mèche de la bombe. Pour les réactions en chaîne, une bombe touchée par une autre dont la mèche est plus courte prend cette mèche, et on itère jusqu'à stabilité. Une bombe `HELD` compte sur la case de son porteur. `extra_bomb` (Vector2i) ajoute une bombe hypothétique avec la mèche `FUSE`.
  - `class_name BotBrain extends RefCounted` : `func _init(rng: RandomNumberGenerator)` et `func decide(world: World, id: int) -> PlayerIntent`.
  - Priorités de `decide` (dans l'ordre, la première qui s'applique gagne) :
    1. Le bot est `GHOST` : `moving` vers la position du joueur ALIVE non possédé le plus proche.
    2. Le bot ne peut pas agir (`can_act()` faux) : intention vide.
    3. **Fuite** : sa case est dans la carte des dangers. On cherche en largeur, sur les cases franchissables, la case **sûre** la plus proche, c'est-à-dire hors dangers, non submergée, et pas au niveau du prochain palier si `water_warning`. Une case est utilisable sur le chemin si `danger[case] > distance_en_cases / PLAYER_SPEED + 0.2`. Le bot vise le centre de la case suivante du chemin. Sans aucune case sûre, il vise la case voisine la moins dangereuse.
    4. **Monter** : si `water_warning` est vrai ou si `world.time_left <= 0`, il vise par la même recherche en largeur la case atteignable de plus grand `h2`. Les blocs ne sont pas franchissables dans cette recherche : si la montée est bouchée par un bloc, la règle 5 s'applique d'abord.
    5. **Poser une bombe** : `place_bomb = true` si (une case 4-voisine est BLOCK, ou si un adversaire ALIVE est dans `Explosion.hit_cells` de sa case), et si `DangerMap.build(world, ma_case)` laisse une case sûre atteignable selon la règle 3.
    6. **Chercher** : il se dirige vers l'adversaire ALIVE le plus proche par la recherche en largeur, en traitant les blocs comme des destinations possibles. S'il n'y en a pas, il va vers le bloc le plus proche. Avec une probabilité de 10 % par décision (via `rng`), il choisit une case voisine au hasard pour ne pas être prévisible.
  - Les bots ne déclenchent jamais `action`.

- [ ] **Step 1 : écrire les tests qui échouent, `tests/test_bots.gd`**
  - `test_danger_map_chain_takes_shortest_fuse` : bombe A (mèche 0,5) et bombe B (mèche 2,0) à portée l'une de l'autre → les cases propres à B valent 0,5.
  - `test_bot_flees_bomb` : bot sur une arène plate 9×9, bombe adverse sur sa case voisine avec mèche 1,5. On enchaîne `decide` + `step` pendant 2 s → le bot a toujours 3 vies.
  - `test_bot_bombs_block_when_escape_exists` : bot en (1,1) sur une arène plate, bloc en (2,1) → `place_bomb == true`.
  - `test_bot_does_not_bomb_in_dead_end` : bot en (1,1), piliers en (0,1), (1,0), (1,2) et bloc en (2,1) → `place_bomb == false`.
  - `test_bot_climbs_when_water_warns` : arène avec une zone `h2 = 2` reliée par un escalier, `water_warning` forcé à vrai → après 4 s de `decide` + `step`, la case du bot a `h2 >= 2`.
  - `test_ghost_bot_heads_to_nearest_living` : bot fantôme en (0,0) et vivants en (2,0) et (8,8) → `intent.target` est proche de (2,5 ; 0,5).
  - `test_trapped_bot_returns_intent` : bot encerclé de piliers et bombe sur sa case → `decide` renvoie un `PlayerIntent` non nul avec `place_bomb == false`.

- [ ] **Step 2 : lancer et constater l'échec**, avec `--only=test_bots`.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : relancer toute la suite.**
- [ ] **Step 5 : commit**, message `Add danger map and bomb-dodging bots`.

---

### Tâche 10 : Scène de jeu 3D jouable

**Files :**
- Create : `src/game/game.tscn`, `src/game/game.gd`, `src/game/arena_view.gd`, `src/game/actors_view.gd`, `src/game/camera_rig.gd`, `src/game/input_controller.gd`, `src/session.gd`, `tests/test_camera.gd`
- Modify : `project.godot` (autoload `Session`)

**Interfaces :**
- Consumes : `MatchState`, `BotBrain`, `World` (lecture seule), `PlayerIntent`.
- Produces :
  - Autoload `Session` (`src/session.gd`, `extends Node`) : `var config: SimConfig` (un `SimConfig.new()` par défaut).
  - `Game extends Node3D` (racine de `game.tscn`) : dans `_ready`, crée `MatchState.new(Session.config, rng)` (rng initialisé avec `randomize()`) et un `BotBrain` par bot. Dans `_process(delta)`, accumule le temps et exécute 0 à 4 pas de `SimConfig.DT`. À chaque pas, les intentions sont l'humain (id 0) via `InputController.consume_intent(...)` et les bots via `decide`, puis `match.step(intents)`. Ensuite, `arena_view.sync(world)`, `actors_view.sync(world, match)` et `hud.sync(match)` (le `hud` arrive en Tâche 11 ; d'ici là, l'appel est protégé par `if hud`). Au changement de `world` (nouvelle manche), `arena_view.build(world.arena)` et `camera_rig.frame(world.arena)`.
  - `ArenaView extends Node3D` : `func build(arena: Arena)` crée une colonne `BoxMesh` par case, haute selon `h2`, avec la couleur par niveau de la maquette (fosse `#6b5d50`, sol `#c29a52`, étage `#dcbd72`, sommet `#f1e3b8`, goal `#e58bb0`). Les escaliers sont des boîtes en marches, et les piliers des boîtes `#5a4020` d'une hauteur de 1. Les blocs sont un dictionnaire case → `MeshInstance3D` (`#9a6a35`). L'eau est un grand plan bleu translucide qui dépasse la map. `func sync(world: World)` réconcilie les blocs avec `arena.tiles` (bloc détruit, bloc lancé) et anime la hauteur de l'eau vers `world.water_h2 * 0.5 + 0.25` par un `Tween` sur 2 s.
  - `ActorsView extends Node3D` : `func sync(world: World, match: MatchState)`. Un joueur est une capsule de sa couleur avec un petit cube pour le « nez » côté `facing` ; elle clignote si `invulnerable_timer > 0`, et ses yeux sont fermés (nez gris) s'il est étourdi. Un fantôme est la même capsule, blanche à 40 % d'opacité, qui flotte 1,5 au-dessus de la case. Une bombe est une sphère noire, qui grossit légèrement quand sa mèche passe sous 0,5 s. Un objet porté est au-dessus de la tête du porteur. Un objet en vol suit un arc parabolique de `from` vers `landing` selon `progress()`. Une explosion est une `SphereMesh` avec `is_hemisphere = true`, orange translucide, de rayon `BOMB_RADIUS`, mise à l'échelle de 0,2 à 1 sur `EXPLOSION_DURATION` puis effacée.
  - `CameraRig extends Node3D` : `func frame(arena: Arena)` place la `Camera3D` avec une inclinaison d'environ 55°, au-dessus et en avant du bord bas de la map, pour cadrer toute la map comme la capture de référence. `func mouse_to_tile(screen_pos: Vector2, plane_h2: int) -> Variant` utilise `static func ray_plane_to_tile(origin: Vector3, dir: Vector3, plane_y: float) -> Variant`, qui renvoie `Vector2(x, z)` du point d'intersection, ou `null` si `abs(dir.y) < 1e-4` ou si le point est derrière la caméra.
  - `InputController extends Node` : il mémorise les appuis sur `place_bomb` et `action` dans `_unhandled_input`, pour qu'aucun appui ne soit perdu entre deux ticks. `func consume_intent(p: PlayerState, rig: CameraRig) -> PlayerIntent` : `moving = Input.is_action_pressed("move")`, et la `target` est la projection de la souris sur le plan `y = h2_at(p.cell()) * 0.5` (pour un fantôme, `+ 1.5`). Si la projection vaut `null`, `moving = false`. Les appuis mémorisés sont ensuite remis à zéro.

- [ ] **Step 1 : écrire les tests qui échouent, `tests/test_camera.gd`**

```gdscript
func test_ray_plane_hits_level_height() -> void:
	var t = CameraRig.ray_plane_to_tile(Vector3(5, 10, 20), Vector3(0, -1, -1).normalized(), 1.0)
	assert_almost(t.x, 5.0); assert_almost(t.y, 11.0)

func test_ray_plane_parallel_returns_null() -> void:
	assert_eq(CameraRig.ray_plane_to_tile(Vector3(0, 5, 0), Vector3(1, 0, 0), 0.0), null)

func test_ray_plane_behind_camera_returns_null() -> void:
	assert_eq(CameraRig.ray_plane_to_tile(Vector3(0, 5, 0), Vector3(0, 1, 0), 0.0), null)
```

- [ ] **Step 2 : lancer et constater l'échec**, avec `--only=test_camera`.
- [ ] **Step 3 : implémenter les scripts et `game.tscn`**, qui contient `ArenaView`, `ActorsView`, `CameraRig` (avec `Camera3D`), `InputController`, une `DirectionalLight3D` et un `WorldEnvironment` avec un ciel bleu clair.
- [ ] **Step 4 : relancer toute la suite.** Expected : tout passe.
- [ ] **Step 5 : vérification visuelle par capture d'images**

Run : `$GODOT --path . --write-movie /private/tmp/claude-501/-Users-pauldoazan-orca-workspaces-Godot-Bomberman/b4ecbdaa-6474-4cfa-8f33-6c59632c088c/scratchpad/frames/f.png --fixed-fps 30 --quit-after 240 res://src/game/game.tscn`
Expected : aucune erreur `SCRIPT ERROR` dans la sortie. Lire `f00000030.png` et `f00000220.png` : on doit voir le temple entier (fosse, étages, sommet rose, escaliers), les blocs, les 4 joueurs colorés et, sur la seconde image, des bombes ou des dômes posés par les bots.

- [ ] **Step 6 : commit**, message `Add playable 3D game scene with fixed camera and mouse input`.

---

### Tâche 11 : Écran de réglages, bandeau et tableau des scores

**Files :**
- Create : `src/ui/settings_screen.tscn`, `src/ui/settings_screen.gd`, `src/game/hud.gd`
- Modify : `src/game/game.tscn` (ajout d'un `CanvasLayer` Hud), `src/game/game.gd`, `project.godot` (`run/main_scene="res://src/ui/settings_screen.tscn"`)

**Interfaces :**
- Consumes : `Session.config`, `MatchState`, `SimConfig.MAP_SIZE_LABELS`.
- Produces :
  - `SettingsScreen extends Control`, avec le titre « Bomberman » et quatre champs : « Bots » (`SpinBox` 1 à 9, défaut 3), « Taille de la map » (`OptionButton` sur `MAP_SIZE_LABELS`, défaut « Normale »), « Chrono (s) » (`SpinBox` 30 à 300 par pas de 10, défaut 120), « Vies » (`SpinBox` 1 à 9, défaut 3). Le bouton « Jouer » écrit un nouveau `SimConfig` dans `Session.config`, puis `get_tree().change_scene_to_file("res://src/game/game.tscn")`.
  - `Hud extends CanvasLayer` : `func sync(match: MatchState)`. Le bandeau du haut, inspiré de la capture, affiche le chrono `m:ss` (remplacé par « L'EAU MONTE ! » quand `time_left <= 0`) et une pastille par joueur avec sa couleur, ses vies `♥ n` (ou « 👻 » s'il est fantôme) et ses victoires `🏆 n`. Le message central « Attention, l'eau monte ! » s'affiche quand `water_warning` est vrai. En `ROUND_OVER`, un panneau « Fin de manche » liste les joueurs triés par victoires, avec « Vainqueur : <nom> » ou « Ex aequo : <noms> », et l'indication « Manche suivante dans n s ». Le bouton « Quitter » est toujours visible en haut à droite et ramène à l'écran de réglages.

- [ ] **Step 1 : implémenter l'écran de réglages, le Hud, et le câblage dans `game.gd`.**
- [ ] **Step 2 : relancer toute la suite de tests.** Expected : tout passe, sans régression.
- [ ] **Step 3 : vérification par capture d'images**

Run : `$GODOT --path . --write-movie /private/tmp/claude-501/-Users-pauldoazan-orca-workspaces-Godot-Bomberman/b4ecbdaa-6474-4cfa-8f33-6c59632c088c/scratchpad/frames2/f.png --fixed-fps 30 --quit-after 30` puis lire la dernière image : l'écran de réglages s'affiche avec ses 4 champs et le bouton « Jouer ».
Ensuite, mettre temporairement `round_time = 30` et `bot_count = 9` dans `Session.config` par défaut, lancer `res://src/game/game.tscn` avec `--quit-after 2400` (80 s) et lire environ 4 images réparties sur la durée. Les vérifier : bandeau avec 10 joueurs, chrono qui descend, alerte, eau qui monte, fantômes, puis panneau de fin de manche. **Annuler la modification temporaire avant le commit.**

- [ ] **Step 4 : commit**, message `Add settings screen, player bar and end-of-round scoreboard`.

---

### Tâche 12 : Export web et test dans le navigateur

**Files :**
- Create : `export_presets.cfg`
- Modify : `.gitignore` (ajouter `build/` et `.godot/`)

**Interfaces :**
- Consumes : le projet complet.
- Produces : `build/web/index.html` jouable, servi en local.

- [ ] **Step 1 : installer les modèles d'export web 4.7.2**

```bash
D="$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable"
mkdir -p "$D" && cd /private/tmp/claude-501/-Users-pauldoazan-orca-workspaces-Godot-Bomberman/b4ecbdaa-6474-4cfa-8f33-6c59632c088c/scratchpad
curl -L -o tpl.tpz https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
unzip -o -j tpl.tpz 'templates/web_nothreads_*' 'templates/version.txt' -d "$D"
ls "$D"
```
Expected : `web_nothreads_debug.zip`, `web_nothreads_release.zip` et `version.txt` (qui contient `4.7.2.stable`).

- [ ] **Step 2 : créer `export_presets.cfg`** avec le preset `name="Web"`, `platform="Web"`, `export_path="build/web/index.html"`, `variant/thread_support=false`, `html/canvas_resize_policy=2`, `html/focus_canvas_on_start=true`.

- [ ] **Step 3 : exporter**

Run : `mkdir -p build/web && $GODOT --headless --path . --export-release "Web" build/web/index.html`
Expected : code de sortie 0, avec `index.html`, `index.wasm` et `index.pck` présents dans `build/web/`.

- [ ] **Step 4 : servir et faire tester par l'utilisateur**

Run (en arrière-plan) : `python3 -m http.server 8060 -d build/web`. Demander à l'utilisateur d'ouvrir `http://localhost:8060` et de vérifier : l'écran de réglages fonctionne ; le clic gauche maintenu déplace le perso ; Espace pose une bombe ; **le clic droit soulève sans ouvrir le menu contextuel du navigateur** ; la partie reste fluide avec 9 bots en taille « Immense ».

- [ ] **Step 5 : commit**, message `Add web export preset`.

---

## Auto-revue (faite)

- **Couverture de la spec :**
  - contrôles : T3, T6, T10 ;
  - map A proportionnelle, réglable, blocs, départs : T2, T11 ;
  - dôme qui monte sans descendre, avec protection : T4 ;
  - vies, réapparition : T4, T5 ;
  - eau jusqu'à tout engloutir, ex aequo : T5, T8 ;
  - manches sans fin : T8 ;
  - fantômes : T7 ;
  - bots : T9 ;
  - écrans : T11 ;
  - web : T12 ;
  - séparation simulation / affichage : contrainte globale et T10.
- **Cohérence des noms :** `PlayerState.Held`, `FlyingObject.kind`, `World.kill(id, cause)`, `World.is_submerged`, `DangerMap.build(world, extra_bomb)` et `CameraRig.ray_plane_to_tile` sont utilisés avec les mêmes signatures d'une tâche à l'autre.
