# Bomberman : multijoueur en ligne (serveur, salon, équipes), conception

Date : 2026-11-07
Moteur : Godot 4.7.2, GDScript. Part de la branche `pauldoazan/Bomberman` (commit `515a1e4`), sur la branche `pauldoazan/server-websocket`.
Suite de `docs/superpowers/specs/2026-10-26-bomberman-poc-solo-design.md` (section « Préparer le multijoueur »).

## Intention

Jouer à plusieurs, chacun dans son navigateur (ordinateur ou téléphone), sur le jeu déjà en ligne sur GitHub Pages. Le cas d'usage : un groupe d'amis, jusqu'à **12 joueurs**, environ **30 minutes par semaine**. Un joueur crée la partie, partage un code ou un lien, chacun entre son pseudo et choisit une équipe, puis on enchaîne les manches.

L'hébergement doit tenir dans le **plan gratuit (Hobby) de Render**. Le jeu solo contre bots reste disponible tel quel.

## Objectifs

- Un **serveur Godot headless** qui fait autorité, hébergé sur Render. Il fait tourner la simulation existante (`src/sim`) et parle aux navigateurs en **WebSocket**.
- Un **écran d'accueil** : pseudo, « Solo », « Créer une partie », « Rejoindre » avec un code.
- Un **code de partie de 6 caractères**, et un **lien direct** qui contient ce code.
- Un **salon (lobby)** avec des **équipes** : jusqu'à 4 équipes, créées et nommées par les joueurs.
- Des **manches en équipes**, enchaînées sans fin, avec un score par équipe.
- **Rejoindre entre deux manches**, et revenir après une déconnexion.

## Hors périmètre

- Bots en ligne (décision utilisateur : pas de bots en partie en ligne).
- Comptes, mots de passe, historique, classements persistants. Le serveur ne stocke rien sur disque.
- Anti-triche au-delà de la validation de base des messages reçus.
- Parties publiques, liste de parties, matchmaking : on n'entre que par code ou par lien.
- Chat texte ou vocal.
- Sons et musique.

## Anti-objectifs (ce qui ferait échouer le projet même s'il « marche »)

- Un jeu qui saccade ou qui répond en retard au point d'être moins agréable que le solo.
- Devoir réécrire ou dupliquer les règles du jeu côté serveur : le serveur réutilise `src/sim`, il n'y a qu'une seule version des règles.
- Un parcours d'entrée laborieux sur téléphone (saisie compliquée, lien qui ne marche pas, partie impossible à retrouver).
- Un hébergement qui coûte de l'argent pour cet usage.

## Le parcours (décisions utilisateur)

1. **L'host crée la partie** : il saisit son pseudo, appuie sur « Créer une partie », et arrive dans le salon avec un code de 6 caractères.
2. **Il partage le code ou le lien.** Le lien a la forme `https://pauldoazan.github.io/bomberman/#K7P2QX`. Le code est placé après un `#` parce que GitHub Pages ne sait pas servir `/bomberman/K7P2QX` (validé par l'utilisateur).
3. **Les autres ouvrent le lien** : le code est déjà rempli, ils n'ont qu'à saisir leur pseudo. Sans le lien, ils tapent le code sur l'écran d'accueil.
4. **Dans le salon**, chacun choisit son équipe ou en crée une.
5. **L'host lance la partie.** Les manches s'enchaînent.
6. **L'host peut ramener tout le monde au salon** à tout moment (choix Claude validé par l'utilisateur), en gardant les équipes, pour changer les réglages.

### Code de partie

- 6 caractères tirés d'un alphabet sans caractères ambigus (choix Claude) : `23456789ABCDEFGHJKLMNPQRSTUVWXYZ`, sans 0, O, 1 ni I. Il doit pouvoir se dicter à voix haute.
- La saisie ignore la casse et les espaces.
- Le client lit le code dans `window.location.hash` via `JavaScriptBridge`. Dans l'éditeur ou sur ordinateur hors navigateur, il n'y a pas de lien : on tape le code.
- Une partie disparaît quand plus personne n'y est connecté, après un court délai de grâce pour laisser revenir un joueur qui recharge sa page (choix Claude).

### Écran d'accueil (choix Claude)

L'écran d'accueil devient le nouveau point d'entrée du jeu (`run/main_scene`). Il contient :
- un champ **pseudo** ;
- **« Solo »**, qui mène à l'écran de réglages actuel ;
- **« Créer une partie »** ;
- un champ **code** avec **« Rejoindre »**.

Le dernier pseudo saisi est retenu dans le navigateur.

Pseudo : de 1 à 12 caractères, sans espaces en début ni en fin. Il doit être unique dans la partie, sinon le serveur refuse et le client le dit (choix Claude).

### Salon : version A (décision utilisateur, maquette validée)

Pensé d'abord pour un écran de téléphone en portrait. De haut en bas :
- le titre « Partie de <pseudo de l'host> » ;
- le **code en gros** ;
- les boutons **« Copier le lien »** et **« Partager »**. « Partager » ouvre le menu de partage natif quand le navigateur le permet (`navigator.share`), sinon il copie le lien ;
- les **équipes empilées en liste**. Chaque équipe affiche son nom, sa couleur, le nombre de joueurs et ses joueurs, chacun dans sa teinte, avec une ★ pour l'host. Un bouton « Rejoindre » apparaît sur les équipes dont on ne fait pas partie ;
- **« + Créer une équipe »**, tant qu'il y a moins de 4 équipes ;
- la ligne « Sans équipe : … » ;
- les **réglages de la partie**, modifiables par l'host et visibles par les autres (choix Claude, non contredit par l'utilisateur) : taille de carte, durée de manche, vies et objets, les mêmes que l'écran de réglages solo. Pas de nombre de bots ;
- **« Lancer »**, réservé à l'host, avec le compteur « n/12 ».

### Équipes (décisions utilisateur)

- **Jusqu'à 4 équipes.** N'importe quel joueur peut en **créer** une, en lui donnant un nom, et il la rejoint aussitôt. N'importe quel joueur peut **rejoindre** une équipe existante ou en changer.
- La **couleur d'équipe** est attribuée automatiquement, la première libre parmi rouge, bleu, vert et jaune (choix Claude).
- Nom d'équipe : de 1 à 16 caractères (choix Claude). Deux équipes peuvent porter le même nom, leurs couleurs les distinguent.
- On peut être « sans équipe » dans le salon (choix Claude).
- Une équipe que tout le monde a quittée disparaît, et sa couleur redevient libre (choix Claude).
- **Conditions pour lancer** (choix Claude) : au moins 2 équipes avec au moins un joueur chacune, et aucun joueur sans équipe.
- Il n'y a **pas de limite de joueurs par équipe**, hormis le maximum de 12 au total. Les équipes peuvent être déséquilibrées.

### Maximum de joueurs

**12 joueurs** par partie (décision utilisateur). Le 13ᵉ reçoit « Partie pleine ». La simulation répartit déjà les points d'apparition selon le nombre de joueurs (`MapGen`). Il faut vérifier que 12 joueurs tiennent sur chaque taille de carte. Si la petite carte est trop serrée, le builder peut la refuser ou l'agrandir au-delà d'un certain nombre de joueurs.

## Règles en équipe (décisions utilisateur)

- **Les dégâts touchent tout le monde** : coéquipiers, adversaires et soi-même. Rien ne change dans les explosions.
- **Fin de manche** : la manche se termine quand tous les joueurs encore en jeu (pas fantômes) appartiennent à la même équipe. Cette équipe gagne la manche. Si tout le monde meurt en même temps, la manche est nulle, ou revient à l'équipe des derniers morts selon la règle actuelle des joueurs morts au même tick (choix Claude : on reprend la règle actuelle, appliquée aux équipes). C'était une supposition de Claude, non contredite par l'utilisateur.
- **Positions de départ** (décision utilisateur) : **chaque équipe part regroupée**, dans sa propre zone de la carte. Les zones des équipes sont réparties le plus loin possible les unes des autres. Les coéquipiers apparaissent proches, mais sur des cases distinctes et sûres, avec la même place libre autour de chaque point de départ qu'aujourd'hui. Le placement exact selon le nombre d'équipes et de joueurs est laissé au builder. Il doit rester équitable quand les équipes sont de tailles différentes.
- La montée des eaux, les fantômes, les objets et les malus restent les mêmes qu'en solo. Un fantôme peut posséder un coéquipier comme un adversaire (choix Claude : rien ne change).
- **Score** : le tableau des scores compte les **victoires par équipe**.
- **En solo**, il n'y a pas d'équipes : chaque joueur forme sa propre équipe, et le comportement actuel ne change pas.

## Apparence des joueurs (décisions utilisateur)

- Tous les membres d'une équipe ont la **couleur de l'équipe**, chacun avec une **teinte légèrement différente** pour qu'on les distingue (plus claire, plus foncée, plus ou moins saturée). Le builder choisit la façon de dériver les teintes. Elles doivent rester clairement de la couleur de l'équipe et se distinguer entre elles, jusqu'à 12 joueurs dans une seule équipe.
- Les **3 premières lettres du pseudo**, en majuscules, sont **écrites sur le corps du personnage, devant et derrière**. Elles doivent être lisibles avec la caméra du jeu, y compris sur téléphone.
- Le HUD (les pastilles de joueurs en haut à gauche) affiche les teintes de couleur et les pseudos.

## Arrivées, départs et host (décisions utilisateur)

- **Rejoindre entre deux manches** : un joueur qui ouvre le lien d'une partie en cours saisit son pseudo, choisit une équipe existante ou en crée une (s'il y en a moins de 4), puis regarde la manche en cours. Il apparaît à la manche suivante.
- **Déconnexion en pleine manche** (décision utilisateur) : le joueur a un **délai de grâce de 10 secondes**.
  - Pendant ce délai, son personnage reste en jeu, immobile et sans action. Il peut quand même être touché, porté, etc.
  - S'il revient pendant ce délai, avec son jeton, il reprend le contrôle de son personnage là où il est.
  - Au-delà de 10 secondes, son personnage est éliminé pour la manche (il passe en fantôme sans vie restante), et le joueur jouera à la manche suivante s'il revient.
- **Retour** : un joueur qui revient par le même lien retrouve son pseudo et son équipe, et joue à la manche suivante. Choix Claude : le client garde dans le navigateur un jeton propre à la partie, que le serveur reconnaît. Un joueur déconnecté depuis plus d'un certain temps (au choix du builder, de l'ordre de quelques minutes) est oublié.
- **L'host part** : le rôle d'host passe automatiquement au joueur arrivé le plus tôt parmi ceux qui restent.
- **Une seule équipe restante** (choix Claude) : une manche ne démarre que si au moins 2 équipes ont un joueur connecté. Sinon, le tableau des scores reste affiché avec « En attente d'une autre équipe… ». La manche suivante démarre dès qu'un joueur rejoint ou revient dans une autre équipe. L'host peut aussi revenir au salon. Une manche déjà commencée se termine normalement.

### Vie des équipes et des scores (choix Claude)

- Une équipe est identifiée par un identifiant propre, pas par sa couleur. Son score lui est attaché.
- Un joueur déconnecté mais encore retenu par le serveur garde sa place dans son équipe. Une équipe ne disparaît que lorsqu'elle n'a plus aucun membre, ni connecté ni retenu. Le joueur qui revient retrouve donc son équipe.
- Les joueurs retenus comptent dans le maximum de 12.
- Une équipe recréée repart à 0, même si elle reprend la même couleur.
- En cours de partie, on ne change pas d'équipe. Seuls les nouveaux arrivants choisissent ou créent la leur entre deux manches. Les changements d'équipe se font dans le salon.
- Les scores repartent à 0 à chaque « Lancer » depuis le salon.

## Architecture technique (recommandation de Claude, acceptée par l'utilisateur)

### Un seul projet Godot, deux rôles

Le même projet produit :
- **le client web**, l'export actuel, publié sur GitHub Pages ;
- **le serveur**, un export Linux lancé en `--headless`, publié sur Render.

Le serveur réutilise `src/sim` sans le modifier, hormis l'ajout des équipes. Il ne fait aucun rendu et n'utilise pas la physique de Godot : il appelle `MatchState.step()` lui-même à `SimConfig.TICK_RATE` (30 Hz).

La façon de choisir le rôle au démarrage (argument de ligne de commande, tag de fonctionnalité `dedicated_server` ou scène principale du preset d'export) est laissée au builder.

### Le serveur fait autorité

- Le client envoie seulement ses **intentions** (`PlayerIntent`) à chaque tick où il en a, ainsi que les actions du salon.
- Le serveur applique les intentions, fait avancer la simulation et renvoie l'**état** aux clients.
- Le client **ne simule pas la partie**. Il reconstruit à partir des messages reçus de quoi alimenter les vues existantes (`ArenaView`, `ActorsView`, `Hud`), en modifiant le moins possible ces vues (choix Claude).
- Les **événements ponctuels** de la simulation (`world.events`) ne sont **pas transmis** (décision utilisateur : l'interface n'affiche pas de message pour le dernier bonus pris ni pour aucune autre action). Les animations ponctuelles (coup de pied, lancer, mort) se déduisent déjà de l'état des joueurs (`kick_tick`, `throw_tick`, `died_tick`), qui survit aux ticks non envoyés.
- Le hasard (`RandomNumberGenerator`) n'existe que sur le serveur.
- Choix Claude : on écarte la synchronisation où chaque client fait tourner la simulation (lockstep). Elle exige une simulation parfaitement déterministe entre le serveur et des navigateurs différents, et un téléphone lent ferait ralentir tout le monde.

### Réseau

- Transport en **WebSocket** (`WebSocketPeer`, ou `WebSocketMultiplayerPeer` si le builder le préfère). C'est la seule option pour un navigateur, et Render ne propose pas d'UDP.
- Messages **binaires** compacts plutôt que du JSON. Le builder choisit le format exact : envoi de l'état complet ou des seules différences, fréquence d'envoi (chaque tick ou un tick sur deux).
- Contraintes : rester très en dessous de la bande passante gratuite de Render, et ne jamais envoyer à 12 joueurs plus de quelques dizaines de Ko/s chacun.
- **Interpolation côté client** : la vue affiche un léger retard sur le dernier état reçu, pour lisser les mouvements de tout le monde. `ActorsView.render(alpha)` sait déjà interpoler entre deux ticks.
- **Pas de prédiction locale dans la première version** (choix Claude) : on mesure d'abord la sensation de jeu en partie réelle. Si le déplacement de son propre personnage paraît en retard, on ajoutera une prédiction du mouvement local dans une étape suivante.
- Le client affiche un indicateur discret de latence (ping) dans le HUD, pour diagnostiquer les playtests (choix Claude).

### Plusieurs parties sur un serveur

Le serveur gère **plusieurs parties à la fois**, identifiées par leur code (choix Claude : ça ne coûte presque rien et ça évite qu'une deuxième bande d'amis bloque la première). Le jeu reste dimensionné pour l'usage prévu, une partie de 12 à la fois. Le builder fixe une limite de parties simultanées raisonnable pour le plan gratuit.

### Hébergement sur Render

- **Web Service**, plan **gratuit**, région **Frankfurt** (la plus proche des joueurs, en France).
- Déploiement par un `Dockerfile` à la racine (ou dans un dossier dédié) qui télécharge Godot 4.7.2 et lance le serveur. Ajouter aussi un `render.yaml` (blueprint).
- Le serveur écoute sur le port donné par la variable d'environnement `PORT`.
- **Mise en veille** : le service gratuit s'endort après 15 minutes sans trafic et met environ une minute à se réveiller. Le client doit le gérer. Quand on crée ou rejoint une partie, il affiche « Réveil du serveur… » et réessaie de se connecter pendant au moins 90 secondes avant d'abandonner avec un message clair.
- Render peut redémarrer le service à tout moment. Toutes les parties en cours sont alors perdues, et c'est accepté : le client affiche « Connexion perdue » et ramène à l'accueil.
- L'adresse du serveur (`wss://…onrender.com`) est une constante du client. Pour les tests en local, on peut la remplacer par `ws://localhost:<port>`, par exemple avec un paramètre dans l'URL ou en lançant le jeu depuis l'éditeur.
- **La création du compte et du service Render revient à l'utilisateur**, avec son compte. Le builder fournit les fichiers et les étapes à suivre.
- Les tests du serveur tournent dans le workflow GitHub existant. Si le CPU s'avère trop juste pour 12 joueurs à 30 Hz, l'option est de passer en instance Starter (environ 7 $/mois) ; on ne descend pas sous 30 Hz sans en parler à l'utilisateur.

### Messages à prévoir (indicatif)

Côté salon : créer une partie, rejoindre (code, pseudo, jeton éventuel), créer une équipe (nom), rejoindre une équipe, quitter son équipe, changer les réglages (host), lancer (host), retour au salon (host). Le serveur renvoie l'état complet du salon à chaque changement, et une erreur lisible quand une action est refusée : code inconnu, partie pleine, pseudo pris, 4 équipes déjà créées, action réservée à l'host.

Côté jeu : intentions du client, état et événements du serveur, début et fin de manche, scores.

## Ce que le jeu existant doit changer

- `MatchState.MatchPlayer` : ajouter le pseudo, l'équipe et l'état de connexion. Il faut pouvoir ajouter des joueurs entre deux manches (`start_round()` relit déjà la liste) et en retirer.
- `World._check_round_end()` : passer à une fin de manche par équipe.
- `MapGen` : générer des points d'apparition groupés par équipe.
- Un joueur en délai de grâce : son personnage reste dans le `World` sans intention, puis est éliminé au bout de 10 secondes.
- `MatchState` : compter les victoires par équipe.
- Couleurs : passer d'une couleur par joueur (`SimConfig.PLAYER_COLORS`) à une couleur d'équipe déclinée en teintes. Le solo garde ses couleurs actuelles.
- `ActorsView` : afficher les 3 lettres du pseudo sur le corps, devant et derrière.
- `Hud` : pseudos, teintes, score par équipe, indicateur de ping.
- `Game` : en ligne, les intentions partent au serveur et l'état vient du serveur. En solo, le fonctionnement actuel ne change pas.
- Nouvelles scènes : accueil, salon. L'écran de réglages solo reste accessible depuis « Solo ».

## Réussite

- Un soir de playtest : 10 à 12 personnes, sur ordinateur et sur téléphone, rejoignent une partie par le lien en moins d'une minute chacune (hors réveil du serveur), forment des équipes et jouent une demi-heure sans déconnexion ni saccade gênante.
- Un joueur qui recharge sa page revient dans sa partie avec son pseudo et son équipe.
- Le plan gratuit de Render suffit, sans facture.

## Tests (choix Claude)

- Tests automatiques headless, dans le même harnais (`tests/run_tests.gd`) :
  - règles du salon : codes, équipes, conditions de lancement, transfert d'host, arrivées et départs ;
  - fin de manche par équipe ;
  - encodage et décodage des messages, dans les deux sens ;
  - une partie complète simulée sans réseau, avec des clients factices.
- Un test d'intégration local : le serveur headless et au moins deux clients (navigateur, ou client headless de test) sur `localhost`.
- Avant le playtest, une mesure de la charge CPU du serveur sur Render avec 12 clients simulés.

## Laissé au builder

- Le format exact des messages, le choix entre état complet et différences, et la fréquence d'envoi.
- L'organisation des fichiers, des scènes et des autoloads, et la manière de choisir le rôle client ou serveur au démarrage.
- Le délai de grâce avant la suppression d'une partie vide, la durée de conservation d'un joueur déconnecté, et la limite de parties simultanées.
- Le calcul des teintes par équipe et le rendu des lettres sur le corps (`Label3D`, texture, décalque…).
- La présentation des réglages dans le salon pour les joueurs autres que l'host (lecture seule).
- Le comportement de la petite carte au-delà d'un certain nombre de joueurs.
- La façon de rejoindre une partie depuis l'éditeur ou en local.
