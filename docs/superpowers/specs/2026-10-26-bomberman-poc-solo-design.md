# Bomberman 64-like : POC n°1 (solo contre bots), conception

Date : 2026-10-26
Moteur : Godot 4.7.2 (installé dans `/Applications/Godot.app`), GDScript.

## Intention

Recréer l'esprit du mode Bataille de Bomberman 64 (N64), joué dans le navigateur, pour à terme **jusqu'à 10 joueurs en ligne**. La map de référence est le temple à étages de la capture fournie par l'utilisateur (`docs/reference/bomberman64-temple.png`, qui sert aussi de référence pour l'angle de caméra et le bandeau du haut) (fosse pavée devant, 1er étage, sommet avec une dalle rose, escaliers, blocs destructibles, eau autour).

Ce premier POC doit prouver que **le cœur du jeu est amusant et fonctionne dans un navigateur** : se déplacer à la souris, poser des bombes, soulever et lancer, survivre à la montée des eaux, hanter en fantôme, enchaîner les manches contre des bots.

Le multijoueur en ligne viendra dans une étape suivante, et le POC doit être construit pour la préparer (voir « Préparer le multijoueur »).

## Objectifs (POC n°1)

- Jouer **en solo contre 1 à 9 bots**, dans le navigateur sur ordinateur (export web Godot). Le jeu doit aussi tourner depuis l'éditeur.
- La map « temple » avec **étages et fosse** (option A validée), générée selon une taille réglable.
- Les contrôles souris + clavier décrits plus bas.
- Bombes, explosions, blocs destructibles.
- Soulever et lancer : bombes (les siennes et celles des autres), joueurs, blocs.
- Montée des eaux à la fin du chrono, noyade.
- Fantômes qui possèdent les vivants.
- Manches enchaînées sans fin, avec score de victoires.

## Hors périmètre (POC n°1)

- Multijoueur en ligne : serveur, WebSocket, code de partie, salon, arrivées entre les manches. **On le prépare sans le construire.**
- Sons et musique.
- Bonus et power-ups.
- Graphismes soignés : formes simples (cubes, capsules ou persos stylisés, couleurs unies).
- Mobile et tactile.
- Bots qui soulèvent ou lancent des objets.

## Anti-objectifs (ce qui ferait échouer le POC même s'il « marche »)

- Rester coincé sur les coins des blocs en se déplaçant à la souris : c'est frustrant et ça tue le jeu.
- Un code où règles, affichage et contrôles sont mêlés, au point que le passage en ligne demande de tout réécrire.
- Un jeu qui ne tourne pas, ou tourne mal, dans un navigateur.

## Contrôles (décision utilisateur)

- **Clic gauche maintenu** : le perso avance **en ligne droite vers le pointeur** tant que le bouton est enfoncé. Il n'y a **pas de calcul de chemin** : c'est au joueur de contourner les obstacles avec la souris. Même principe qu'Agar.io, mais sur une grille.
  - Aide aux mouvements (validée) : le perso **glisse le long des murs** quand il les frôle et se **recentre doucement dans un couloir** quand il est presque aligné, comme l'aide aux coins des Bomberman au clavier.
  - Le perso regarde dans la direction de son dernier déplacement.
- **Espace** : pose une bombe sur la case du perso.
- **Clic droit** : soulève l'objet qui se trouve devant le perso ou sous lui. Un deuxième clic droit le lance **dans la direction où regarde le perso**, et non vers la souris.
  - Objets qu'on peut soulever : ses bombes, celles des autres, les **autres joueurs**, les **blocs destructibles**.

## La map (décision utilisateur : option A, « fidèle, en plus grand »)

- Le temple de la capture : **fosse** pavée (niveau -1) devant, **sol** (niveau 0), **1er étage** (niveau 1), **sommet** (niveau 2) avec une **dalle rose** décorative au centre. Des **escaliers** relient les niveaux. De l'eau entoure la map.
- **Taille par défaut : 2 fois la surface de l'originale**, soit environ **19×15 cases**. La taille est **réglable dans les paramètres de la partie**.
- Comme la taille varie, la map est **générée à partir d'un plan** dont les éléments (fosse, étages, escaliers) gardent leurs proportions, et non dessinée case par case.
- Une maquette de référence de la disposition existe : `.superpowers/brainstorm/*/content/map-taille.html`, option A, dessinée en 23×19. On en garde la disposition relative, pas la taille.

Choix de conception (Claude) :
- **Piliers indestructibles** fixes, en quadrillage sur le sol (niveau 0), comme dans Bomberman classique.
- **Blocs destructibles** tirés au hasard à chaque manche (environ 22 % des cases libres), en laissant toujours libres les cases à 2 pas ou moins d'un point de départ et les escaliers. Il n'y en a pas sur le sommet.
- **Points de départ** répartis sur le pourtour du sol, autant que de joueurs (2 à 10).
- On ne **monte** d'un niveau **que par les escaliers**, qu'on peut emprunter dans toutes les directions. Depuis le bord d'un niveau, on peut **sauter vers un niveau plus bas**. Un objet lancé peut atterrir sur un autre niveau.
- **Caméra fixe en 3D**, inclinée comme sur la capture, qui cadre toute la map. Elle doit rester lisible jusqu'à la taille maximale autorisée.

## Règles d'une manche

Choix de conception (Claude, non contesté par l'utilisateur) :
- **3 vies par joueur et par manche par défaut, réglable** (décision utilisateur). Les vies repartent au maximum à chaque manche.
- Choix Claude : un joueur qui perd une vie (explosion ou noyade) réapparaît après 2 s sur une case libre et sûre (hors danger, hors de l'eau, de préférence sur le niveau sec le plus bas encore disponible). Il est invulnérable 2 s, en clignotant. À la perte de la dernière vie, il devient fantôme.
- Sans bonus, chaque joueur a des valeurs fixes : **2 bombes posées à la fois au maximum**, **portée d'explosion de 3 cases**, mèche d'environ 2,5 s.
- **L'explosion est une demi-sphère qui grossit** (décision utilisateur) : un dôme posé sur le sol du niveau où la bombe explose, qui touche **toutes les cases dans son rayon, dans toutes les directions, diagonales comprises**. Elle **monte** (elle touche les étages plus hauts dans son rayon) mais **ne descend jamais** sous le niveau de la bombe : les niveaux plus bas sont épargnés.
- Choix Claude : la grille est **une grille 2D avec une hauteur par case**. Une case est touchée si elle est à distance ≤ rayon (3 cases par défaut, à ajuster en jouant) et à un niveau ≥ celui de la bombe.
- Choix Claude (non tranché par l'utilisateur) : les **piliers et les blocs protègent** ce qui est derrière eux (ligne de vue depuis la bombe). Un bloc touché est détruit, mais il protège quand même ce qu'il cache pendant cette explosion. Le dôme est dessiné entier à l'écran, mais seules les cases en vue sont touchées.
- L'explosion tue les joueurs touchés (ils perdent une vie) et fait exploser les autres bombes touchées.

### Le chrono et la montée des eaux (décision utilisateur)

- Un **chrono** tourne pendant la manche (2 minutes par défaut, réglable).
- **À la fin du chrono, l'eau monte petit à petit.** Les joueurs peuvent **se noyer**, et il faut **monter pour survivre**.
- **L'eau monte jusqu'à tout engloutir, sommet compris** (décision utilisateur). La manche se termine donc toujours.
- Choix de conception (Claude) : l'eau monte **par paliers** (fosse → sol → 1er étage → sommet), avec un délai entre chaque palier (par exemple 20 s) et un signe visible juste avant chaque montée. Un joueur dont la case est sous l'eau se noie.

### Fin de manche et enchaînement (décision utilisateur)

- **La manche se termine quand il ne reste qu'un survivant.** Il marque un point de victoire.
- **Il n'y a pas de fin de partie** : on enchaîne les manches tant que les joueurs veulent continuer.
- Choix de conception (Claude) : après chaque manche, le tableau des scores s'affiche quelques secondes, puis la manche suivante démarre sur une nouvelle disposition des blocs. Un bouton permet de quitter vers l'écran de réglages.
- **Ex aequo** (décision utilisateur) : si les derniers survivants meurent au même instant (noyés ensemble ou par la même explosion), ils sont ex aequo. Choix Claude : chacun d'eux marque un point.

## Fantômes (décision utilisateur, d'après Bomberman 64)

Dans Bomberman 64, un joueur éliminé revient en fantôme. Il peut **prendre le contrôle d'un Bomberman vivant pendant un court moment**, mais il ne peut pas poser de bombes.

Transposition (choix Claude) :
- Un joueur qui a perdu **toutes ses vies** devient un **fantôme** pour le reste de la manche. Il flotte et traverse murs et étages, et se déplace au clic gauche maintenu.
- En touchant un vivant, il le **possède pendant environ 5 s** : sa souris dirige le déplacement du vivant, qui perd le contrôle. Le fantôme ne peut ni poser de bombe ni lancer d'objet.
- Après une possession, le fantôme a un **temps de recharge d'environ 10 s**.
- Un fantôme ne ressuscite pas. Il redevient joueur normal à la manche suivante.
- Les bots deviennent aussi des fantômes.

## Bots (validés par l'utilisateur)

Niveau correct, sans viser un champion :
- ils **fuient les explosions à venir** : ils connaissent les cases qu'une bombe va toucher (dôme, ligne de vue, niveaux) et s'en écartent ;
- ils **posent des bombes** près des blocs pour ouvrir le chemin, et près des adversaires **seulement s'ils ont une sortie de secours** ;
- ils **montent vers le sommet** quand l'eau monte ;
- en fantôme, ils **vont posséder le vivant le plus proche** ;
- ils ne soulèvent pas et ne lancent pas d'objets.

## Écrans

- **Réglages** (avant de jouer) : nombre de bots (1 à 9), taille de la map, durée du chrono, nombre de vies (3 par défaut), puis bouton « Jouer ». Ces réglages serviront plus tard dans le salon en ligne.
- **Jeu** : la map, le chrono et un bandeau des joueurs avec leurs vies restantes et leurs victoires, comme le haut de la capture.
- **Fin de manche** : tableau des scores, puis enchaînement.

## Préparer le multijoueur (contrainte d'architecture)

Cible validée pour l'étape suivante : chacun joue sur la **même URL** dans son navigateur. Un joueur crée une partie et partage un **code**. Les autres rejoignent un **salon** qui affiche la liste des joueurs, puis quelqu'un lance la partie. **Entre deux manches, un nouveau joueur peut rejoindre** avec le code, sans relancer la partie. Jusqu'à 10 joueurs.

Choix de conception (Claude) pour cette cible :
- Godot exporté en web ne peut pas utiliser ENet, il faudra des **WebSockets**. Un **serveur** fera autorité sur la partie (règles, positions, explosions), pour que la partie ne dépende pas de l'onglet d'un joueur. Seul le créateur de la partie peut la lancer.
- **Conséquence pour le POC** : les **règles du jeu** (grille, bombes, explosions, eau, fantômes, scores) sont **séparées de l'affichage et des entrées**. Chaque joueur, humain ou bot, envoie des **intentions** (« avancer vers tel point », « poser une bombe », « soulever/lancer »). La simulation les applique à un rythme fixe. Le passage en ligne consistera à faire tourner cette simulation sur le serveur et à transmettre intentions et état, sans réécrire les règles.

## Laissé au builder

- Les dimensions exactes du plan en fonction de la taille (min et max autorisés, arrondis) et les valeurs précises (vitesses, durées, hauteurs des lancers).
- La physique et l'arc des lancers, la façon de lâcher un objet sans le lancer, et ce que fait un objet qui retombe (une bombe lancée qui retombe peut continuer sa mèche, un bloc redevient un obstacle sur sa case d'arrivée).
- Ce qui arrive à un joueur porté (combien de temps, comment il se libère) et à un joueur lancé (étourdi un court instant).
- La lecture de la caméra et du sol à la souris (projection du pointeur sur la map en 3D).
- L'organisation des fichiers et des scènes Godot, et l'outillage de tests.
