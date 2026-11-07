# Multijoueur en ligne : plan d'implémentation

> **Pour les agents qui exécutent ce plan :** SOUS-SKILL REQUIS : utiliser superpowers:subagent-driven-development (recommandé) ou superpowers:executing-plans pour exécuter ce plan tâche par tâche. Les étapes sont des cases à cocher (`- [ ]`) pour suivre l'avancement.

**Objectif :** jouer jusqu'à 12 en équipes, chacun dans son navigateur. Un serveur Godot headless sur Render fait autorité, et on rejoint une partie par un code ou un lien `#CODE`.

**Architecture :** un seul projet Godot joue les deux rôles. `src/boot.gd` choisit entre serveur et client au démarrage. Le serveur (`src/server/`) fait tourner `MatchState` à 30 Hz pour chaque partie (`Room`) et envoie en WebSocket un instantané compressé 15 fois par seconde. Le client (`src/net/`, `src/ui/`) envoie ses `PlayerIntent`. Il reconstruit à partir des instantanés un `MatchState` miroir, mis à jour sur place, que les vues existantes affichent sans changer leur façon de lire l'état.

**Technologies :** Godot 4.7.2, GDScript, `TCPServer` + `WebSocketPeer`, `var_to_bytes` + compression DEFLATE, Docker sur Render (plan gratuit, Frankfurt), GitHub Pages pour le client.

**Spécification :** `docs/superpowers/specs/2026-11-07-multijoueur-en-ligne-design.md` (à lire avant toute tâche).

## Contraintes globales

- Godot **4.7.2**, GDScript typé, dans le style du code existant : commentaires en anglais, textes visibles en français.
- Les tests passent par `./godot --headless --path . -s res://tests/run_tests.gd`, ou par `godot` installé dans `/Applications/Godot.app/Contents/MacOS/Godot`, et `-- --only=test_xxx` pour un seul fichier. Ce sont des fichiers `tests/test_*.gd` qui étendent `TestCase`.
- Le mode **solo** ne change pas : les 300 et quelques tests existants restent verts après chaque tâche.
- **12 joueurs** au maximum par partie et **4 équipes** au maximum. Pseudo de **1 à 12** caractères, nom d'équipe de **1 à 16**, après `strip_edges()`.
- Alphabet des codes : `23456789ABCDEFGHJKLMNPQRSTUVWXYZ`, longueur **6**.
- Délai de grâce en pleine manche : **10 s**.
- Le serveur décode les messages avec `bytes_to_var` uniquement, **jamais** `bytes_to_var_with_objects`.
- Aucun message à l'écran pour un bonus ramassé ou une action (décision utilisateur) : `world.events` n'est pas transmis.
- Le serveur écoute sur `PORT` (variable d'environnement), et sur **9080** par défaut.
- Simulation à **30 Hz** (`SimConfig.TICK_RATE`), instantanés envoyés tous les **2** ticks.
- Commits en anglais, au présent, et un commit par tâche. Une correction d'un commit non poussé se fait avec `git commit --fixup=<sha>`. Rien n'est poussé sans l'accord de l'utilisateur.

## Points de vigilance de la relecture

1. **Téléphone mis en veille quelques secondes**, puis rouvert : le joueur reprend son personnage. Au-delà de 10 s, il est fantôme et rejoue à la manche suivante. Tests dans la tâche 7.
2. **Deux pseudos identiques à la casse ou aux espaces près** (`"Paul"` et `" paul "`) : le second est refusé avec `name_taken`. Un pseudo de 13 caractères est refusé avec `bad_name`. Tests dans la tâche 6.
3. **Lien saisi ou collé de travers** (`#k7p2qx`, `k7p2 qx`, `#K7P2QX/`) : il est normalisé. Un code inconnu donne aussitôt « Code inconnu », sans attente sans fin. Tests dans les tâches 6 et 11.
4. **L'host se déconnecte dans le salon** : le rôle passe au joueur connecté de plus petit id. S'il revient, il ne redevient pas host. Tests dans la tâche 6.
5. **Client et serveur de versions différentes** (Pages et Render déployés séparément) : le serveur refuse avec `version`, et le client affiche « Nouvelle version du jeu : recharge la page ». Tests dans les tâches 4 et 8.

---

## Organisation des fichiers

| Fichier | Rôle |
|---|---|
| `src/sim/match_state.gd` (modifié) | Équipes, liste de joueurs fournie de l'extérieur, victoires par équipe, manche suivante retenue |
| `src/sim/world.gd` (modifié) | `teams`, fin de manche par équipe, `forfeit()` |
| `src/sim/map_gen.gd` (modifié) | Points d'apparition groupés par équipe |
| `src/sim/explosion.gd`, `src/sim/flying_object.gd`, `src/sim/carry.gd` (modifiés) | Champ `uid` stable |
| `src/sim/team_colors.gd` (nouveau) | Couleurs d'équipe et teintes |
| `src/net/protocol.gd` (nouveau) | Types de messages, codes d'erreur, (dé)codage, intentions |
| `src/net/sim_codec.gd` (nouveau) | `MatchState` ↔ `Dictionary`, application sur place dans un miroir |
| `src/net/net_client.gd` (nouveau) | Socket client : connexion avec réessais, envoi, réception |
| `src/net/net.gd` (nouveau, autoload `Net`) | État en ligne du client : partie, id, jeton, salon, ping, navigation entre écrans |
| `src/net/online_store.gd` (nouveau) | Pseudo et jetons dans `user://online.cfg` |
| `src/server/room_codes.gd` (nouveau) | Génération et normalisation des codes |
| `src/server/room.gd` (nouveau) | Une partie : salon, équipes, host, déroulement, grâce, oubli |
| `src/server/intent_buffer.gd` (nouveau) | Fusion des intentions reçues entre deux ticks |
| `src/server/server_core.gd` (nouveau) | WebSocket serveur, routage des messages, cadence |
| `src/server/server.gd` + `.tscn` (nouveaux) | Nœud qui fait tourner `ServerCore` |
| `src/boot.gd` + `.tscn` (nouveaux) | Nouvelle scène principale : serveur ou accueil |
| `src/ui/settings_form.gd` (nouveau) | Formulaire de réglages extrait de `settings_screen.gd` |
| `src/ui/home_screen.gd` + `.tscn` (nouveaux) | Écran d'accueil |
| `src/ui/lobby_screen.gd` + `.tscn` (nouveaux) | Salon, version A |
| `src/game/snapshot_queue.gd` (nouveau) | Tampon d'instantanés pour lisser l'affichage |
| `src/game/game.gd`, `hud.gd`, `actors_view.gd` (modifiés) | Mode en ligne, joueur local, lettres, scores par équipe |
| `Dockerfile`, `.dockerignore`, `render.yaml`, `docs/deploy-render.md` (nouveaux) | Hébergement |
| `tests/bench_server.gd` (nouveau) | Mesure manuelle du coût par tick, ne fait pas partie de la suite |

---

### Tâche 1 : équipes dans la simulation

**Fichiers :**
- Modifier : `src/sim/match_state.gd`, `src/sim/world.gd`
- Test : `tests/test_teams.gd`

**Interfaces :**
- Produit :
  - `MatchState.MatchPlayer` gagne `var team := -1` et `var tag := ""` (3 lettres affichées, vide en solo).
  - `static func MatchState.tag_of(name: String) -> String` renvoie `name.strip_edges().left(3).to_upper()`.
  - `MatchState._init(p_cfg: SimConfig, p_rng: RandomNumberGenerator, roster: Variant = null, auto_start := true)`. Avec `null`, c'est le solo actuel (bots). Avec un `Array[MatchPlayer]`, ce sont ces joueurs-là. Avec `auto_start == false`, pas de `start_round()` (`world` reste `null`), pour le miroir client.
  - `MatchState.team_wins: Dictionary`, qui associe l'id d'équipe au nombre de victoires.
  - `MatchState.hold_next_round := false`.
  - `func MatchState.sync_roster(roster: Array[MatchPlayer]) -> void` remplace `players` en gardant `wins` pour les id déjà présents.
  - `World._init(p_arena, player_ids, p_cfg, p_rng, p_teams: Dictionary = {})`, avec `var teams: Dictionary` qui associe l'id joueur à l'id d'équipe.
  - `func World.team_of(id: int) -> int` renvoie `teams.get(id, id)`.
  - `func World.forfeit(id: int) -> void`.

- [ ] **Étape 1 : écrire les tests qui échouent** dans `tests/test_teams.gd`. Une aide `_roster(teams: Array[int]) -> Array[MatchState.MatchPlayer]` crée des joueurs d'id 0..n-1 avec ces équipes.
  - `test_solo_unchanged` : `MatchState.new(cfg, rng)` avec 4 bots, `world.team_of(i) == i`, `team_wins.is_empty()`.
  - `test_round_ends_when_one_team_left` : équipes `[0, 0, 1]`. On tue l'id 2 jusqu'à 0 vie, puis `step({})` : phase `ROUND_OVER`, `last_winners` vaut `[0, 1]` (survivants de l'équipe 0), `team_wins[0] == 1`, `player(0).wins == 1`, `player(1).wins == 1`.
  - `test_teammates_alive_round_continues` : équipes `[0, 0, 1, 1]`. On tue 0 et 2 : la phase reste `PLAYING`.
  - `test_hold_next_round` : on finit une manche, `hold_next_round = true`, puis `step({})` pendant `SCOREBOARD_DURATION + 1 s` de ticks. `round_number` ne change pas et `phase_timer <= 0`. Avec `hold_next_round = false`, un `step` relance la manche (`round_number` + 1).
  - `test_sync_roster_adds_player_next_round` : on ajoute un joueur d'id 3 (équipe 1) pendant `ROUND_OVER`. Il est dans `world.players` après le passage à la manche suivante, et le joueur 0 garde ses `wins`.
  - `test_forfeit_makes_ghost` : `world.forfeit(1)` donne `life == GHOST`, `lives == 0` et `death_cause == "déconnexion"`. Un second appel ne fait rien (pas d'erreur).
  - `test_tag_of` : `MatchState.tag_of(" paul ") == "PAU"` et `MatchState.tag_of("Al") == "AL"`.

- [ ] **Étape 2 : lancer `-- --only=test_teams`.** Résultat attendu : ÉCHEC (méthodes ou propriétés inconnues).

- [ ] **Étape 3 : implémenter.**
  - `start_round()` trie `players` par `(team, id)` et passe à `World` le dictionnaire `teams`, construit à partir de `mp.team` quand il est `>= 0`.
  - `_check_round_end()` : soit `alive_teams` l'ensemble des `team_of()` des non-fantômes, et `all_teams` le même ensemble pour tous les joueurs. La manche est finie avec `winners = alive` si `alive_teams.size() == 1 and all_teams.size() > 1`. Le cas « tout le monde mort » reste celui d'aujourd'hui.
  - Dans `MatchState.step`, chaque équipe distincte parmi `winners` reçoit +1 dans `team_wins`. En `ROUND_OVER`, on ne relance pas tant que `hold_next_round` est vrai (le minuteur reste à 0).
  - `forfeit` met `lives` à 0 et passe le joueur en `GHOST` en enregistrant la mort (`died_tick`, `death_cause`, événement `death`), comme `_eliminate`.

- [ ] **Étape 4 : lancer toute la suite.** Résultat attendu : `0 échecs`.

- [ ] **Étape 5 : commit** `Add teams to the match rules`.

### Tâche 2 : départs groupés par équipe

**Fichiers :**
- Modifier : `src/sim/map_gen.gd`, `src/sim/sim_config.gd`, `src/sim/match_state.gd` (passer `team_sizes`)
- Test : `tests/test_team_spawns.gd`

**Interfaces :**
- Consomme : l'ordre de `players` trié par équipe (tâche 1).
- Produit : `static func MapGen.generate(size: Vector2i, player_count: int, rng: RandomNumberGenerator, team_sizes: Array[int] = []) -> Arena`, plus `const SimConfig.TEAM_SPAWN_STEP := 3`.

- [ ] **Étape 1 : écrire les tests.** Pour chaque taille de `SimConfig.MAP_SIZES` et chaque répartition `[[6, 6], [11, 1], [3, 3, 3, 3], [4, 4, 4], [1, 1]]` :
  - `spawns.size()` vaut la somme des tailles ;
  - toutes les cases sont distinctes et au sol (`h2_at == 0`) ;
  - pour chaque équipe, la plus grande distance entre deux coéquipiers (Manhattan) est plus petite que la plus petite distance entre un de ses joueurs et un joueur d'une autre équipe.

  Ajouter `test_no_teams_same_as_before` : sans `team_sizes`, on obtient les mêmes `spawns` qu'avant pour le même seed (valeurs de référence calculées avant la modification).

- [ ] **Étape 2 : lancer le test.** Résultat attendu : ÉCHEC.

- [ ] **Étape 3 : implémenter.**
  - Sur le périmètre `perim` existant, la position de départ de l'équipe `t` est `t * perim.size() / team_sizes.size()`.
  - Ses `n` membres occupent les indices `ancre + (k - (n - 1) / 2.0) * TEAM_SPAWN_STEP`, arrondis et pris modulo `perim.size()`.
  - Si deux cases se chevauchent (grosse équipe sur petite carte), on réduit l'écart à 2 pour cette répartition.
  - `MatchState.start_round()` passe les tailles d'équipe dans l'ordre du tri, et seulement si au moins un joueur a `team >= 0`.

- [ ] **Étape 4 : lancer toute la suite.** Résultat attendu : `0 échecs`.

- [ ] **Étape 5 : commit** `Spawn each team together`.

### Tâche 3 : couleurs d'équipe

**Fichiers :**
- Créer : `src/sim/team_colors.gd`
- Test : `tests/test_team_colors.gd`

**Interfaces :**
- Produit :
  - `class_name TeamColors` ;
  - `const BASES: Array[Color] = [Color("e6194b"), Color("4363d8"), Color("3cb44b"), Color("ffe119")]` (rouge, bleu, vert, jaune) ;
  - `const LABELS := ["Rouge", "Bleu", "Vert", "Jaune"]` ;
  - `static func tint(color_index: int, member_index: int, member_count: int) -> Color` ;
  - `static func free_index(used: Array[int]) -> int` renvoie le premier indice libre, ou -1.

- [ ] **Étape 1 : écrire les tests.**
  - `tint(i, 0, n) == BASES[i]`.
  - Pour chaque base et `n = 12`, deux teintes sont toujours séparées d'au moins 0,06 en distance RVB.
  - L'écart de teinte (`h`, circulaire) avec la base reste ≤ 0,04.
  - Chaque teinte reste plus proche de sa base que de toute autre base.
  - `free_index([0, 2]) == 1` et `free_index([0, 1, 2, 3]) == -1`.

- [ ] **Étape 2 : lancer le test.** Résultat attendu : ÉCHEC.

- [ ] **Étape 3 : implémenter `tint`.** On fait varier la luminosité (`v`) et la saturation (`s`) en alternant plus clair et plus foncé autour de la base, sans toucher à `h`. Il faut faire attention au jaune, qui est déjà clair : il se décline surtout en plus foncé.

- [ ] **Étape 4 : lancer le test.** Résultat attendu : RÉUSSITE.

- [ ] **Étape 5 : commit** `Add team colours and tints`.

### Tâche 4 : sérialisation de l'état (SimCodec)

**Fichiers :**
- Modifier : `src/sim/explosion.gd`, `src/sim/flying_object.gd`, `src/sim/world.gd`, `src/sim/carry.gd` (attribuer `uid`)
- Créer : `src/net/sim_codec.gd`
- Test : `tests/test_sim_codec.gd`

**Interfaces :**
- Consomme : `MatchState`, `World` et `MatchPlayer` des tâches 1 à 3.
- Produit :
  - `Explosion.uid: int` et `FlyingObject.uid: int`, uniques dans un `World` grâce à `World.next_uid() -> int`.
  - `class_name SimCodec` avec :
    - `static func encode_match(m: MatchState) -> Dictionary` ;
    - `static func apply_match(data: Dictionary, mirror: MatchState, cfg: SimConfig) -> MatchState` ;
    - `static func encode_config(cfg: SimConfig) -> Dictionary` ;
    - `static func decode_config(d: Dictionary) -> SimConfig`, qui valide et borne les valeurs ;
    - `static func schema_hash() -> int`.

**Format choisi :**
- Chaque objet (`PlayerState`, `BombState`, `Explosion`, `FlyingObject`, et les champs simples de `World`) est encodé comme un `Array` de valeurs, dans l'ordre de `keys_of(script)`.
- `keys_of(script)` donne les variables de script triées par nom, sans celles qui commencent par `_`.
- Exclues de `World` : `arena`, `cfg`, `rng`, `players`, `bombs`, `explosions`, `flying`, `events`, `hidden`.
- L'arène est envoyée entière à chaque fois (`w, h, h2, tiles, stair_axis, goal`).
- `schema_hash()` est le `hash()` de toutes les listes de clés concaténées : il change dès qu'un champ de la simulation change.

**Application sur place :**
- Si `mirror` vaut `null`, ou si `data.round` diffère de `mirror.round_number`, on construit un nouveau `MatchState` avec `auto_start = false`, ainsi qu'une nouvelle `Arena` et un nouveau `World`.
- Sinon, on met à jour le même `World`, la même `Arena` (on remplace seulement `tiles`) et les mêmes objets : joueurs et bombes par id, explosions et objets en vol par `uid`. Les objets absents sont retirés.
- Les tableaux typés sont restaurés avec `.assign()`.

C'est indispensable : `ActorsView` indexe ses nœuds par instance d'`Explosion` et de `FlyingObject`, et `Game._refresh_world` reconstruit l'arène quand l'objet `World` change.

- [ ] **Étape 1 : écrire les tests.**
  - `test_roundtrip_same_state` : une partie de 12 joueurs (équipes `[3, 3, 3, 3]`, carte « immense ») avance de 90 ticks avec des intentions aléatoires (bombes comprises). Ensuite, `apply_match(encode_match(m), null, cfg)` donne un miroir dont `encode_match(miroir) == encode_match(m)`.
  - `test_apply_keeps_identity` : même manche, on applique deux fois. Le second appel renvoie le même `MatchState` et le même `World`. Une explosion présente dans les deux instantanés est la même instance.
  - `test_new_round_new_world` : `round` change, donc un nouveau `World`.
  - `test_hidden_not_sent` : `encode_match(m)` ne contient aucune clé `hidden`.
  - `test_config_roundtrip_and_clamp` : `decode_config(encode_config(cfg))` restitue les mêmes réglages. Avec `{"lives": 99, "map_size": "xxl"}`, on obtient `lives == 9` et `map_size == "normale"`.

- [ ] **Étape 2 : lancer le test.** Résultat attendu : ÉCHEC.

- [ ] **Étape 3 : implémenter.** L'ordre de lecture et d'écriture des champs suit `keys_of()`.

- [ ] **Étape 4 : lancer toute la suite.** Résultat attendu : `0 échecs`.

- [ ] **Étape 5 : commit** `Serialise the match state for the network`.

### Tâche 5 : protocole et fusion des intentions

**Fichiers :**
- Créer : `src/net/protocol.gd`, `src/server/intent_buffer.gd`
- Test : `tests/test_protocol.gd`

**Interfaces :**
- Produit :
  - `class_name Protocol`.
  - Messages :

    ```gdscript
    enum Msg {
        CREATE = 1, JOIN = 2, CREATE_TEAM = 3, JOIN_TEAM = 4, LEAVE_TEAM = 5,
        SETTINGS = 6, START = 7, TO_LOBBY = 8, INTENT = 9, PING = 10, LEAVE = 11,
        WELCOME = 20, LOBBY = 21, ERROR = 22, SNAPSHOT = 23, PONG = 24,
    }
    ```

  - Codes d'erreur (`String`) : `ERR_UNKNOWN_CODE = "unknown_code"`, `ERR_FULL = "full"`, `ERR_NAME_TAKEN = "name_taken"`, `ERR_BAD_NAME = "bad_name"`, `ERR_TEAMS_FULL = "teams_full"`, `ERR_HOST_ONLY = "host_only"`, `ERR_CANNOT_START = "cannot_start"`, `ERR_NOT_NOW = "not_now"`, `ERR_VERSION = "version"`, `ERR_SERVER_FULL = "server_full"`.
  - Libellés `const ERROR_LABELS` :
    - `unknown_code` : « Code inconnu »
    - `full` : « Partie pleine (12 joueurs) »
    - `name_taken` : « Ce pseudo est déjà pris »
    - `bad_name` : « Nom invalide »
    - `teams_full` : « Il y a déjà 4 équipes »
    - `host_only` : « Seul l'host peut faire ça »
    - `cannot_start` : « Il faut au moins 2 équipes et tout le monde dans une équipe »
    - `not_now` : « Pas pendant la partie »
    - `version` : « Nouvelle version du jeu : recharge la page »
    - `server_full` : « Serveur plein, réessaie plus tard »
  - `static func encode(type: int, body: Variant) -> PackedByteArray` : 1 octet de type, suivi de `var_to_bytes(body)` compressé en DEFLATE.
  - `static func decode(bytes: PackedByteArray) -> Array` renvoie `[type, body]`, ou `[]` si le message est invalide : décompression en échec, type inconnu ou objet présent.
  - `static func intent_to_array(i: PlayerIntent) -> Array` donne `[moving, target.x, target.y, place_bomb, action, action_held, detonate, struggle]`.
  - `static func intent_from_array(a: Variant) -> PlayerIntent` renvoie `null` si la forme ou les types sont faux, et borne `struggle` entre 0 et 10.
  - `class_name IntentBuffer` avec :
    - `func push(id: int, intent: PlayerIntent) -> void` ;
    - `func take() -> Dictionary`, qui associe l'id à un `PlayerIntent`.

- [ ] **Étape 1 : écrire les tests.**
  - Aller-retour `encode`/`decode` pour un `Dictionary` et pour un `Array`.
  - `decode(PackedByteArray([1, 2, 3])) == []`.
  - Le décodage d'un `var_to_bytes_with_objects` contenant un objet renvoie `[]`.
  - Aller-retour des intentions.
  - `intent_from_array([true, "x"]) == null`.
  - `IntentBuffer` :
    - deux pushes dans le même tick, le premier avec `place_bomb` et le second sans : `take()` a `place_bomb` vrai, et la cible est celle du second ;
    - `struggle` 1 + 2 donne 3 ;
    - après `take()` sans nouveau push, le `take()` suivant garde `moving`, `target` et `action_held`, mais `place_bomb`, `action`, `detonate` et `struggle` sont remis à zéro.
  - `test_snapshot_size_budget` (dans `tests/test_sim_codec.gd`) : `Protocol.encode(Protocol.Msg.SNAPSHOT, SimCodec.encode_match(m)).size() < 2500` pour la partie de 12 joueurs du test `test_roundtrip_same_state` de la tâche 4.

- [ ] **Étape 2 : lancer le test.** Résultat attendu : ÉCHEC.

- [ ] **Étape 3 : implémenter.** Pour la décompression : `decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)`. Pour le décodage : `bytes_to_var`, puis rejet si le résultat contient un `Object`.

- [ ] **Étape 4 : lancer toute la suite.** Résultat attendu : `0 échecs`. Si `test_snapshot_size_budget` échoue, envoyer `h2` et `stair_axis` une seule fois par manche (champ `arena_static`, présent seulement dans le premier instantané d'une manche pour chaque client) et ajuster `SimCodec` en conséquence.

- [ ] **Étape 5 : commit** `Add the network protocol`.

### Tâche 6 : codes et salon (Room, partie 1)

**Fichiers :**
- Créer : `src/server/room_codes.gd`, `src/server/room.gd`
- Test : `tests/test_room_lobby.gd`

**Interfaces :**
- Consomme : `Protocol.ERR_*`, `TeamColors`, `SimCodec.encode_config`, `MatchState`.
- Produit :
  - `class_name RoomCodes` avec `const ALPHABET := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"`, plus :
    - `static func generate(rng: RandomNumberGenerator, taken: Dictionary) -> String` ;
    - `static func normalize(s: String) -> String`, qui enlève `#`, `/`, les espaces, passe en majuscules, et renvoie `""` si le résultat n'a pas 6 caractères de l'alphabet.
  - `class_name Room` avec les constantes : `MAX_PLAYERS := 12`, `MAX_TEAMS := 4`, `NAME_MAX := 12`, `TEAM_NAME_MAX := 16`, `GRACE_IN_ROUND := 10.0`, `FORGET_AFTER := 180.0`, `EMPTY_ROOM_TTL := 60.0`.
  - `enum Phase { LOBBY, PLAYING }`.
  - Classes internes :
    - `RoomPlayer` : `id`, `name`, `token`, `team := -1`, `connected := true`, `disconnected_at := 0.0`, `forfeited := false` ;
    - `Team` : `id`, `name`, `color_index`.
  - `var code: String`, `phase`, `host_id: int`, `players: Dictionary` (id → `RoomPlayer`), `teams: Dictionary` (id → `Team`), `config: SimConfig`, `match_state: MatchState`.
  - Méthodes :

    ```gdscript
    func _init(p_code: String, p_rng: RandomNumberGenerator)
    func join(name: String, token: String, now: float) -> Dictionary  # {"id", "token"} ou {"error"}
    func disconnect_player(id: int, now: float) -> void
    func create_team(id: int, name: String) -> String  # "" si accepté, sinon un ERR_*
    func join_team(id: int, team_id: int) -> String
    func leave_team(id: int) -> String
    func set_config(id: int, cfg: SimConfig) -> String
    func start(id: int) -> String
    func back_to_lobby(id: int) -> String
    func can_start() -> bool
    func lobby_state() -> Dictionary
    ```

  - Format de `lobby_state()` : `{"code", "host", "phase": "lobby"|"playing", "can_start", "config": encode_config, "teams": [{"id", "name", "color_index"}], "players": [{"id", "name", "team", "connected", "color": Color}]}`.

- [ ] **Étape 1 : écrire les tests.**
  - `normalize("#k7p2qx") == "K7P2QX"`, `normalize("k7p2 qx/") == "K7P2QX"`, `normalize("K7P2Q0") == ""` et `normalize("ABC") == ""`.
  - `generate` produit 6 caractères de l'alphabet et évite les codes de `taken`.
  - Premier `join` : le joueur devient host. Le 13ᵉ `join` donne `full`, y compris quand certains des 12 sont déconnectés mais encore retenus.
  - `join(" paul ")` après `join("Paul")` donne `name_taken`. `join("")` et un nom de 13 caractères donnent `bad_name`.
  - `join` avec le jeton d'un joueur déconnecté rend le même id, même équipe, `connected` vrai, et ignore le pseudo fourni.
  - `create_team` donne des couleurs 0, 1, 2, 3, puis `teams_full`. Le créateur est dans l'équipe. Quitter la dernière équipe la supprime, et `free_index` redonne sa couleur.
  - `start` : un non-host obtient `host_only`. Avec une seule équipe ou un joueur sans équipe, on obtient `cannot_start`. Sinon on obtient `""`, `phase == PLAYING` et un `match_state` avec ces joueurs, `team` remplis, couleurs prises dans `TeamColors.tint` et `tag` rempli.
  - Pendant `PLAYING`, `leave_team` et `join_team` d'un joueur déjà dans la partie donnent `not_now`. Pour un nouvel arrivant (absent de `match_state.players`), ils sont acceptés.
  - L'host se déconnecte en salon : `host_id` passe au plus petit id connecté. Quand il revient avec son jeton, `host_id` ne change pas.
  - `set_config` est réservé à l'host. Les scores (`team_wins`) repartent à 0 à chaque `start`.

- [ ] **Étape 2 : lancer le test.** Résultat attendu : ÉCHEC.

- [ ] **Étape 3 : implémenter.**
  - Le jeton fait 16 caractères hexadécimaux tirés du `rng`.
  - Les id joueurs sont incrémentaux et jamais réutilisés : l'ordre d'arrivée est l'ordre des id.
  - L'unicité du pseudo se vérifie sur `strip_edges().to_lower()`, parmi tous les joueurs retenus.

- [ ] **Étape 4 : lancer toute la suite.** Résultat attendu : `0 échecs`.

- [ ] **Étape 5 : commit** `Add game codes and the lobby rules`.

### Tâche 7 : déroulement de la partie (Room, partie 2)

**Fichiers :**
- Modifier : `src/server/room.gd`
- Test : `tests/test_room_match.gd`

**Interfaces :**
- Produit :
  - `func Room.tick(now: float, intents: Dictionary) -> void` avance d'un pas de simulation si la partie est en `PLAYING`.
  - `func Room.is_dead(now: float) -> bool` est vrai si aucun joueur n'est connecté depuis `EMPTY_ROOM_TTL`.
  - `func Room.in_match(id: int) -> bool`.

**Ce que fait `tick`, dans l'ordre :**
1. Si la partie n'est pas en `PLAYING`, ne rien faire de plus que l'oubli des joueurs (point 3).
2. Un joueur déconnecté, présent dans `world.players`, non fantôme, déconnecté depuis au moins `GRACE_IN_ROUND` et sans `forfeited` : appeler `world.forfeit(id)` et passer `forfeited` à vrai.
3. Un joueur déconnecté depuis au moins `FORGET_AFTER` est retiré de `players` et de son équipe. L'équipe disparaît si elle est vide.
4. En `ROUND_OVER` : appeler `match_state.sync_roster(...)` avec les joueurs retenus qui ont une équipe, couleurs recalculées, et remettre `forfeited` à faux.
5. `hold_next_round = (nombre d'équipes ayant au moins un joueur connecté) < 2`.
6. `match_state.step(intents)`.

- [ ] **Étape 1 : écrire les tests.** Ils utilisent une partie lancée avec 2 équipes de 2 joueurs, `now` avancé de `SimConfig.DT` à chaque `tick`.
  - Déconnexion à t, reconnexion par jeton à t + 5 s : le joueur n'est pas fantôme et ses intentions le font bouger (`pos` change avec `moving` vers une case libre).
  - Déconnexion sans retour : à t + 9,9 s il n'est pas fantôme, à t + 10,1 s il est `GHOST`.
  - Un arrivant pendant la manche qui rejoint l'équipe 1 : il n'est pas dans `world.players` pendant la manche, il y est après la manche suivante.
  - Les deux joueurs d'une équipe se déconnectent pendant `ROUND_OVER` : `round_number` reste figé. L'un revient, et la manche suivante démarre.
  - Un joueur déconnecté depuis 181 s est oublié. Son équipe, si elle est vide, disparaît du `lobby_state()`.
  - `back_to_lobby` par l'host : `phase == LOBBY`, équipes conservées. `start` ensuite donne `team_wins` vide.
  - `is_dead` : faux à 59 s sans joueur connecté, vrai à 61 s.

- [ ] **Étape 2 : lancer le test.** Résultat attendu : ÉCHEC.

- [ ] **Étape 3 : implémenter `tick`, `is_dead` et `in_match`** comme décrit ci-dessus.

- [ ] **Étape 4 : lancer toute la suite.** Résultat attendu : `0 échecs`.

- [ ] **Étape 5 : commit** `Run matches in a room`.

### Tâche 8 : serveur WebSocket

**Fichiers :**
- Créer : `src/server/server_core.gd`, `src/server/server.gd`, `src/server/server.tscn`, `src/boot.gd`, `src/boot.tscn`, `tests/bench_server.gd`
- Modifier : `project.godot` (`run/main_scene="res://src/boot.tscn"`)
- Test : `tests/test_net_loopback.gd`

**Interfaces :**
- Consomme : `Room`, `RoomCodes`, `Protocol`, `IntentBuffer`, `SimCodec`.
- Produit :
  - `class_name ServerCore` (RefCounted) :
    - `const MAX_ROOMS := 20`, `const SNAPSHOT_EVERY := 2` ;
    - `func listen(port: int) -> Error` ;
    - `func poll(now: float) -> void` ;
    - `func stop() -> void` ;
    - `var rooms: Dictionary`, qui associe un code à une `Room`.
  - `static func Boot.is_server() -> bool` est vrai si `OS.has_feature("dedicated_server")` ou si `OS.get_cmdline_user_args().has("--server")`.

**Routage :**
- Un pair a l'état `{ws, room_code, player_id}`.
- `CREATE {name, schema}` et `JOIN {code, name, token, schema}` :
  - un `schema` différent de `SimCodec.schema_hash()` donne `ERROR version` ;
  - un code inconnu donne `ERROR unknown_code` ;
  - au-delà de `MAX_ROOMS`, `ERROR server_full` ;
  - sinon `WELCOME {code, id, token}`, puis `LOBBY` envoyé à tous les membres.
- Si un jeton déjà relié à un pair ouvert revient, l'ancien pair est fermé.
- Toute action de salon acceptée fait renvoyer `LOBBY` à tous. Une action refusée fait envoyer `ERROR` au seul demandeur.
- `INTENT` va dans l'`IntentBuffer` de la partie, et seulement si `room.in_match(id)`.
- `PING {t}` reçoit `PONG {t}`.
- `LEAVE` et la fermeture du socket appellent `disconnect_player`, puis `LOBBY` est envoyé à tous.

**Cadence :**
- On accumule `now`, et chaque `SimConfig.DT` on fait un `room.tick` par partie, avec 4 rattrapages au plus.
- Tous les `SNAPSHOT_EVERY` ticks, pour chaque partie en `PLAYING` : un seul `Protocol.encode(SNAPSHOT, SimCodec.encode_match(m))`, envoyé à tous les pairs de la partie, spectateurs compris.
- Quand une partie bascule entre `LOBBY` et `PLAYING`, `LOBBY` est envoyé à tous.
- Les parties pour lesquelles `is_dead(now)` est vrai sont supprimées.

**Côté nœuds :**
- `server.gd` : `Engine.max_fps = 60` (sinon la boucle headless occupe tout le CPU), port lu dans `PORT` ou 9080, `poll(Time.get_ticks_msec() / 1000.0)` dans `_process`. Il journalise la création et la suppression des parties, et les arrivées et départs.
- `boot.gd` : `change_scene_to_file.call_deferred(...)` vers `server.tscn`, ou vers `home_screen.tscn`. Tant que la tâche 11 n'existe pas, utiliser `settings_screen.tscn` à la place.

- [ ] **Étape 1 : écrire `tests/test_net_loopback.gd`.** On démarre `ServerCore` sur le port 19080, avec deux `WebSocketPeer` clients bruts. Une aide `_pump(seconds)` appelle `core.poll()` et `ws.poll()` en boucle avec `OS.delay_msec(5)`.
  - Le client A envoie `CREATE {"name": "Paul", "schema": SimCodec.schema_hash()}` et reçoit `WELCOME` avec un code de 6 caractères, puis `LOBBY`.
  - Le client B envoie `JOIN` avec ce code : A et B reçoivent un `LOBBY` à 2 joueurs.
  - `JOIN` avec `schema: 1` donne `ERROR version`. `JOIN` avec un code inconnu donne `ERROR unknown_code`.
  - A et B créent chacun une équipe, A envoie `START` : les deux reçoivent un `LOBBY` en phase `"playing"`, puis au moins un `SNAPSHOT` en moins d'une seconde.
  - B ferme son socket : A reçoit un `LOBBY` où B a `connected == false`.

- [ ] **Étape 2 : lancer le test.** Résultat attendu : ÉCHEC.

- [ ] **Étape 3 : implémenter `ServerCore`, `server.gd`/`.tscn` et `boot.gd`/`.tscn`.**

- [ ] **Étape 4 : lancer toute la suite**, puis `godot --headless --path . -- --server`. Résultat attendu : la suite à `0 échecs`, et le journal `Serveur à l'écoute sur 9080`. Arrêter avec Ctrl+C.

- [ ] **Étape 5 : écrire et lancer le banc d'essai** `tests/bench_server.gd` (`extends SceneTree`, hors suite). Il mesure 600 ticks d'une partie de 12 joueurs sur la carte immense, avec des intentions aléatoires et un encodage tous les 2 ticks, puis affiche `ms/tick` (moyenne et maximum) et la taille moyenne d'un instantané. Lancer avec `godot --headless --path . -s res://tests/bench_server.gd`. Noter le résultat dans le message de commit.

- [ ] **Étape 6 : commit** `Add the WebSocket game server`.

### Tâche 9 : client réseau

**Fichiers :**
- Créer : `src/net/net_client.gd`, `src/net/net.gd`, `src/net/online_store.gd`
- Modifier : `project.godot` (autoload `Net="*res://src/net/net.gd"`), `src/session.gd`
- Test : `tests/test_net_loopback.gd` (ajouts), `tests/test_online_store.gd`

**Interfaces :**
- Consomme : `Protocol`, `SimCodec`, `ServerCore` (pour les tests).
- Produit :
  - `class_name NetClient` (RefCounted) :
    - `enum Status { OFFLINE, CONNECTING, WAKING, ONLINE, LOST }`, `const WAKE_TIMEOUT := 90.0`, `const RETRY_EVERY := 3.0`, `const WAKING_AFTER := 3.0` ;
    - `signal message(type: int, body: Variant)` et `signal status_changed(status: int)` ;
    - `func open(url: String, now: float)`, `func poll(now: float)`, `func send(type: int, body: Variant)`, `func close()`.

    Les réessais continuent jusqu'à `WAKE_TIMEOUT`, puis le statut passe à `LOST`. Une coupure une fois `ONLINE` passe aussi à `LOST`.
  - Autoload `Net` (Node) :
    - `const PROD_URL := "wss://bomberman-server.onrender.com"`, à mettre à jour avec l'adresse réelle au moment du déploiement ;
    - `static func server_url() -> String` : en web, le paramètre `?server=` de la page s'il est présent, sinon `PROD_URL`. Hors web : `"ws://localhost:9080"` ;
    - `var code := ""`, `var my_id := -1`, `var lobby: Dictionary = {}`, `var mirror: MatchState = null`, `var ping_ms := -1`, `var config: SimConfig` ;
    - `signal lobby_changed`, `signal error_received(code: String)`, `signal snapshot_received(data: Dictionary)`, `signal status_changed(status: int)` ;
    - `func create_game(name: String)`, `func join_game(code: String, name: String)`, `func leave()`, `func send_action(type: int, body: Variant = {})`, `func send_intent(i: PlayerIntent)` ;
    - `func invite_link() -> String` : en web, `location.origin + location.pathname + "#" + code`, sinon `"https://pauldoazan.github.io/bomberman/#" + code` ;
    - `func share_link() -> void` : `navigator.share` s'il existe, sinon copie (`DisplayServer.clipboard_set`) ;
    - `func is_online() -> bool`.
  - Au `WELCOME`, `Net` enregistre le jeton (`OnlineStore`) et, en web, remplace l'adresse par `#CODE` avec `history.replaceState`.
  - À chaque `LOBBY` : `config = SimCodec.decode_config(...)`, `Session.config = config`, puis navigation (phase `"lobby"` vers `lobby_screen.tscn`, phase `"playing"` vers `game.tscn` si ce n'est pas déjà la scène courante).
  - `LOST` ramène vers `home_screen.tscn` avec le message « Connexion perdue ».
  - Un `PING` part toutes les 2 s, et `ping_ms` est mis à jour au `PONG`.
  - `class_name OnlineStore` :
    - `static func load_nickname() -> String` et `static func save_nickname(n: String)` ;
    - `static func token_for(code: String) -> String` et `static func save_token(code: String, token: String)` ;
    - un fichier `user://online.cfg`, avec un chemin remplaçable par une variable statique `path` pour les tests.
  - `Session` gagne `var local_id := 0`. `Net` le règle à `my_id` en ligne et le remet à 0 en solo.

- [ ] **Étape 1 : écrire les tests.**
  - Dans le test réseau : un `NetClient` ouvert sur un port où rien n'écoute passe à `WAKING` après plus de 3 s (avec un `now` simulé), puis à `LOST` après plus de 90 s. Un `NetClient` ouvert sur `ServerCore` passe à `ONLINE`, puis reçoit `WELCOME` après `send(CREATE, ...)`.
  - `test_online_store.gd` : aller-retour du pseudo et du jeton sur un fichier temporaire.

- [ ] **Étape 2 : lancer les tests.** Résultat attendu : ÉCHEC.

- [ ] **Étape 3 : implémenter.** La navigation passe par `get_tree().change_scene_to_file.call_deferred`. Le code `JavaScriptBridge` est protégé par `OS.has_feature("web")`.

- [ ] **Étape 4 : lancer toute la suite.** Résultat attendu : `0 échecs`.

- [ ] **Étape 5 : commit** `Add the network client`.

### Tâche 10 : formulaire de réglages réutilisable

**Fichiers :**
- Créer : `src/ui/settings_form.gd`
- Modifier : `src/ui/settings_screen.gd`
- Test : `tests/test_settings_form.gd` (et `tests/test_settings.gd` existant, qui doit rester vert)

**Interfaces :**
- Produit : `class_name SettingsForm extends GridContainer` avec :
  - `func _init(cfg: SimConfig, show_bots: bool)` ;
  - `func build_config() -> SimConfig` (garde `bot_count` de la config d'origine si `show_bots` est faux) ;
  - `func load_config(cfg: SimConfig) -> void` (sans émettre `changed`) ;
  - `var editable := true`, qui désactive les contrôles quand il est faux ;
  - `signal changed` ;
  - `var columns_for_width` à laisser dans `settings_screen._fit`, qui règle `form.columns`.

  Le contenu (Partie, Bonus et malus, steppers, tailles, interrupteurs) est déplacé tel quel depuis `settings_screen.gd`.

- [ ] **Étape 1 : écrire les tests.**
  - `SettingsForm.new(cfg, false)` ne contient pas la ligne « Bots ».
  - `load_config` suivi de `build_config` restitue les mêmes réglages.
  - Avec `editable = false`, tous les `BaseButton` sont `disabled`.
  - Modifier un stepper émet `changed`.

- [ ] **Étape 2 : lancer les tests.** Résultat attendu : ÉCHEC.

- [ ] **Étape 3 : extraire le formulaire.** `settings_screen.gd` garde le titre, le formulaire et « Jouer ». Ajouter un bouton « Retour » vers l'accueil, actif une fois la tâche 11 faite.

- [ ] **Étape 4 : lancer toute la suite.** Résultat attendu : `0 échecs`. Ouvrir l'écran solo dans l'éditeur : il est identique à avant.

- [ ] **Étape 5 : commit** `Extract the settings form`.

### Tâche 11 : écran d'accueil

**Fichiers :**
- Créer : `src/ui/home_screen.gd`, `src/ui/home_screen.tscn`
- Modifier : `src/boot.gd` (aller à l'accueil)
- Test : `tests/test_home.gd`

**Interfaces :**
- Consomme : `Net`, `OnlineStore`, `RoomCodes.normalize`, `Protocol.ERROR_LABELS`.
- Produit :
  - `class_name HomeScreen extends Control` ;
  - `static func code_from_hash(h: String) -> String` (passe par `RoomCodes.normalize`) ;
  - `static func status_text(status: int) -> String` :
    - `CONNECTING` : « Connexion… » ;
    - `WAKING` : « Réveil du serveur… (jusqu'à une minute) » ;
    - `LOST` : « Serveur injoignable, réessaie dans un instant ».
  - `var message := ""` (statique dans `Net`), affiché en arrivant sur l'accueil, par exemple « Connexion perdue ».

**Disposition, sur téléphone en portrait d'abord :**
- titre « Bomberman » ;
- champ pseudo, pré-rempli avec `OnlineStore.load_nickname()`, 12 caractères au plus ;
- « Créer une partie » ;
- « ou » ;
- champ code (6 caractères, en majuscules) + « Rejoindre » ;
- « Solo », qui mène à `settings_screen.tscn` ;
- une ligne d'état.

**Comportement :**
- Les boutons en ligne sont désactivés tant que le pseudo est vide. « Rejoindre » l'est aussi tant que le code n'est pas valide.
- Arrivée avec un `#CODE` valide : le code est pré-rempli et « Rejoindre » devient le bouton principal. Le pseudo garde le focus.
- Les erreurs (`Net.error_received`) sont affichées avec `Protocol.ERROR_LABELS`.

- [ ] **Étape 1 : écrire les tests.**
  - `code_from_hash("#k7p2qx") == "K7P2QX"` et `code_from_hash("") == ""`.
  - `status_text(NetClient.Status.WAKING)` contient « Réveil ».
  - La scène instanciée avec un pseudo vide a « Créer une partie » désactivé.

- [ ] **Étape 2 : lancer les tests.** Résultat attendu : ÉCHEC.

- [ ] **Étape 3 : implémenter.** Reprendre le thème et le zoom des écrans existants (`SettingsLayout.zoom_for`).

- [ ] **Étape 4 : lancer toute la suite.** Résultat attendu : `0 échecs`.

- [ ] **Étape 5 : commit** `Add the home screen`.

### Tâche 12 : salon (version A)

**Fichiers :**
- Créer : `src/ui/lobby_screen.gd`, `src/ui/lobby_screen.tscn`
- Test : `tests/test_lobby_screen.gd`

**Interfaces :**
- Consomme : `Net` (`lobby`, `my_id`, `send_action`, `invite_link`, `share_link`, `leave`), `SettingsForm`, `TeamColors`, `Protocol.Msg`.
- Produit : `class_name LobbyScreen extends Control` avec `func show_state(state: Dictionary, my_id: int) -> void`, appelée sur `Net.lobby_changed`.

**Disposition (maquette A) :**
- « Partie de <host> » ;
- code en gros ;
- « Copier le lien » et « Partager » ;
- une carte par équipe, en liste, bordée de sa couleur, avec le nom, le nombre de joueurs et des pastilles de pseudo dans leur teinte (★ pour l'host, grisées si déconnectées), plus « Rejoindre » si ce n'est pas mon équipe ;
- « + Créer une équipe », masqué à 4 équipes. Il ouvre une ligne avec un champ nom (16 caractères au plus) et « Créer et rejoindre » ;
- « Sans équipe : … » ;
- le `SettingsForm` (`show_bots = false`, `editable` pour l'host seulement), dont chaque `changed` envoie `SETTINGS` ;
- « Lancer · n/12 », visible pour l'host seulement et actif si `can_start` ;
- « Quitter ».

Les erreurs s'affichent dans une ligne d'état.

- [ ] **Étape 1 : écrire les tests** avec un état fictif (3 équipes, 6 joueurs dont un sans équipe, host = 0).
  - `show_state(state, 0)` affiche 3 cartes d'équipe, « Lancer » visible et désactivé (car un joueur est sans équipe), et le formulaire `editable`.
  - `show_state(state, 4)` : « Lancer » est masqué et le formulaire n'est pas `editable`.
  - Avec 4 équipes, « + Créer une équipe » est masqué.
  - Le nombre de boutons « Rejoindre » vaut le nombre d'équipes moins celle du joueur.

- [ ] **Étape 2 : lancer les tests.** Résultat attendu : ÉCHEC.

- [ ] **Étape 3 : implémenter.** `show_state` reconstruit la liste des équipes. Le formulaire est mis à jour avec `load_config`, mais pas pendant que l'host est en train de le modifier : il ne se recharge que si la config reçue diffère de `build_config()`.

- [ ] **Étape 4 : lancer toute la suite.** Résultat attendu : `0 échecs`.

- [ ] **Étape 5 : commit** `Add the lobby screen`.

### Tâche 13 : apparence en ligne (lettres, teintes, HUD)

**Fichiers :**
- Modifier : `src/game/actors_view.gd`, `src/game/hud.gd`
- Test : `tests/test_hud_online.gd`, `tests/test_player_letters.gd`

**Interfaces :**
- Consomme : `MatchPlayer.tag`, `.team`, `.color`, `MatchState.team_wins`, `hold_next_round`, `Session.local_id`, `Net.ping_ms`, `Net.lobby` (noms d'équipes).
- Produit :
  - `PlayerNode` gagne `front_label: Label3D` et `back_label: Label3D`, créés si `mp.tag != ""`, avec le texte `mp.tag`.

    Réglages des étiquettes :
    - collées au torse, devant et derrière ;
    - `billboard` désactivé, pour qu'elles tournent avec le corps ;
    - lettres blanches à contour noir ;
    - `fixed_size` désactivé ;
    - taille réglée pour être lisible avec la caméra du jeu sur la carte « normale », vérifiée à l'œil.
  - `static func Hud.team_scoreboard_text(m: MatchState, team_names: Dictionary) -> String` produit :
    - les lignes `"<nom d'équipe> : 🏆 n"`, triées par victoires ;
    - `"Vainqueur : <équipe>"` ;
    - puis, si `hold_next_round`, « En attente d'une autre équipe… », sinon « Manche suivante dans n s ».
  - `Hud` lit le joueur local par `Session.local_id` au lieu de `0`. En ligne, il ajoute :
    - un libellé « ping 42 ms » en haut à droite ;
    - un bouton « Retour au salon » pour l'host (envoie `TO_LOBBY`) ;
    - « Tu joues à la prochaine manche » pour qui n'est pas dans `world.players`.

    Les pastilles affichent le pseudo et utilisent `mp.color`, qui est déjà la teinte.

- [ ] **Étape 1 : écrire les tests.**
  - `team_scoreboard_text` sur un `MatchState` à 2 équipes avec `team_wins {0: 2, 1: 1}` : « Les Pétards : 🏆 2 » arrive avant « Team Mèche : 🏆 1 ». Avec `hold_next_round`, le texte contient « En attente d'une autre équipe ».
  - `ActorsView` synchronisé avec un joueur `tag = "PAU"` a deux `Label3D` de texte « PAU ». Un joueur solo (`tag` vide) n'en a aucun.

- [ ] **Étape 2 : lancer les tests.** Résultat attendu : ÉCHEC.

- [ ] **Étape 3 : implémenter.** En solo, `_scoreboard_text` reste celui d'aujourd'hui.

- [ ] **Étape 4 : lancer toute la suite.** Résultat attendu : `0 échecs`.

- [ ] **Étape 5 : commit** `Show nicknames, tints and team scores`.

### Tâche 14 : partie en ligne côté client

**Fichiers :**
- Créer : `src/game/snapshot_queue.gd`
- Modifier : `src/game/game.gd`
- Test : `tests/test_snapshot_queue.gd`

**Interfaces :**
- Consomme : `Net.snapshot_received`, `Net.send_intent`, `SimCodec.apply_match`, `Session.local_id`, `InputController.consume_intent`.
- Produit : `class_name SnapshotQueue` avec :
  - `const INTERVAL := SimConfig.DT * 2`, `const MAX_BACKLOG := 3` ;
  - `func push(data: Dictionary) -> void` ;
  - `func advance(delta: float) -> Variant`, qui renvoie l'instantané à appliquer maintenant ou `null` ;
  - `func alpha() -> float`, la fraction de 0 à 1 de `INTERVAL` écoulée depuis le dernier instantané appliqué.

  Le tampon démarre après 1 instantané d'avance. Au-delà de `MAX_BACKLOG` en attente, il saute au plus récent moins 1. S'il est vide, il ne renvoie rien et `alpha` reste à 1.

**`Game` en ligne (`Net.is_online()` au `_ready`) :**
- pas de `MatchState` local ni de bots ;
- chaque instantané tiré de la file passe par `match_state = SimCodec.apply_match(data, match_state, Net.config)`, puis `_refresh_world()` et `_sync_views()` ;
- `actors_view.render(queue.alpha())` à chaque image ;
- à chaque `SimConfig.DT` local, si le joueur local est dans `world.players`, `Net.send_intent(input_controller.consume_intent(world.players[Session.local_id], camera_rig))` ;
- le bouton « Quitter » du HUD appelle `Net.leave()`.

Le solo ne change pas.

- [ ] **Étape 1 : écrire les tests.**
  - Le premier `advance` sans rien en attente renvoie `null`.
  - Après 2 `push`, un `advance(INTERVAL)` renvoie le premier.
  - Avec 6 en attente, `advance` saute jusqu'au 5ᵉ.
  - `alpha()` vaut 0,5 à mi-intervalle.

- [ ] **Étape 2 : lancer les tests.** Résultat attendu : ÉCHEC.

- [ ] **Étape 3 : implémenter `SnapshotQueue` et la branche en ligne de `Game`.**

- [ ] **Étape 4 : lancer toute la suite.** Résultat attendu : `0 échecs`.

- [ ] **Étape 5 : essai local de bout en bout.**
  1. Lancer le serveur : `godot --headless --path . -- --server`.
  2. Exporter le web : `godot --headless --path . --export-release "Web" build/web/index.html`.
  3. Servir le jeu : `python3 -m http.server 8090 -d build/web`.
  4. Ouvrir deux onglets sur `http://localhost:8090/?server=ws://localhost:9080`.
  5. Créer la partie dans l'un, rejoindre par le lien `#CODE` dans l'autre, créer 2 équipes, lancer.

  Vérifier que :
  - les deux personnages bougent de façon fluide ;
  - les lettres sont visibles et les couleurs d'équipe correctes ;
  - recharger un onglet en pleine manche fait reprendre le personnage ;
  - « Retour au salon » ramène les deux onglets au salon.

- [ ] **Étape 6 : commit** `Play online matches in the client`.

### Tâche 15 : hébergement Render et mise en ligne

**Fichiers :**
- Créer : `Dockerfile`, `.dockerignore`, `render.yaml`, `docs/deploy-render.md`
- Modifier : `.github/workflows/pages.yml` (ajouter la branche `pauldoazan/server-websocket`), `src/net/net.gd` (`PROD_URL` réelle)

**Interfaces :**
- Consomme : `godot --headless --path . -- --server` (tâche 8).

**Dockerfile :**
- `debian:bookworm-slim` + `ca-certificates curl unzip` ;
- téléchargement de `Godot_v4.7.2-stable_linux.x86_64.zip`, la même URL que dans `pages.yml` ;
- `COPY . /app` ;
- `RUN ./godot --headless --path /app --import` ;
- `CMD ["/app/godot", "--headless", "--path", "/app", "--", "--server"]`.

On utilise le binaire de l'éditeur, sans modèles d'export : c'est plus simple, et environ 150 Mo de RAM tiennent dans les 512 Mo.

**`.dockerignore` :** `build/`, `.godot/`, `docs/`, `.superpowers/`, `.git/`.

**`render.yaml` :** un service `web`, `name: bomberman-server`, `runtime: docker`, `plan: free`, `region: frankfurt`, `branch: pauldoazan/server-websocket`, `autoDeploy: true`.

**`docs/deploy-render.md` :** les étapes pour l'utilisateur, en français :
1. créer un compte Render ;
2. New → Blueprint, puis choisir le dépôt `PaulDoazan/bomberman` ;
3. récupérer l'adresse `https://bomberman-server-xxxx.onrender.com` ;
4. réveiller le serveur avant une partie ;
5. lire les journaux.

- [ ] **Étape 1 : construire et lancer l'image en local, si Docker est disponible :** `docker build -t bomberman-server . && docker run -p 9080:9080 -e PORT=9080 bomberman-server`. Résultat attendu : `Serveur à l'écoute sur 9080`, et l'essai local de la tâche 14 fonctionne contre ce conteneur. Si Docker n'est pas installé, le signaler à l'utilisateur et passer à la suite.

- [ ] **Étape 2 : commit** `Add the Render deployment` (`Dockerfile`, `.dockerignore`, `render.yaml`, doc).

- [ ] **Étape 3 : demander à l'utilisateur.**
  - Il doit pousser la branche, ce qui publie aussi le jeu sur Pages une fois `pages.yml` modifié.
  - Il doit autoriser la branche dans l'environnement `github-pages`, avec la même politique de branches que pour `positions-and-moves`.
  - Il doit créer le service Render en suivant `docs/deploy-render.md` et donner l'adresse obtenue.

  **Ne rien pousser avant son accord.**

- [ ] **Étape 4 : après son accord.**
  - Mettre l'adresse réelle dans `PROD_URL`.
  - Ajouter la branche à `pages.yml` et à la politique de l'environnement (`gh api`).
  - Lancer toute la suite, puis faire un commit `Point the client at the Render server`.
  - Pousser.
  - Vérifier sur `https://pauldoazan.github.io/bomberman/` avec un ordinateur et un téléphone : création, lien `#CODE`, réveil du serveur, partie à 2.

- [ ] **Étape 5 : mesurer sur Render.** Lancer une partie avec plusieurs onglets et relever le CPU dans le tableau de bord Render. Si le CPU dépasse durablement 80 %, prévenir l'utilisateur (option Starter). Ne pas baisser la fréquence sans son accord.
