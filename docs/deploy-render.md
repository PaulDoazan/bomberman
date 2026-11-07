# Mise en ligne : serveur sur Render, jeu sur GitHub Pages

Le jeu (client web) est servi par GitHub Pages. Le serveur de parties tourne sur Render (offre gratuite, Docker, région Francfort), construit à partir du `Dockerfile` et décrit par `render.yaml`.

> **Attention : une seule version sur Pages.** Le site GitHub Pages montre la branche poussée en dernier. Pousser `pauldoazan/server-websocket` remplace les builds de `main`, `pauldoazan/Bomberman` et `pauldoazan/positions-and-moves`, et un push ultérieur d'une de ces branches remplace celui-ci. Seul le build de cette branche parle au serveur Render : pour jouer en ligne, le site doit montrer cette branche.
>
> **Mêmes versions.** Le client (Pages) et le serveur (Render) doivent venir du même commit, sinon le jeu affiche « Nouvelle version du jeu : recharge la page ». Recharger la page une fois les deux déploiements terminés.

## 1. Autoriser la branche sur GitHub (avant de pousser)

Dépôt `PaulDoazan/bomberman` → Settings → Environments → `github-pages` → Deployment branches and tags : ajouter `pauldoazan/server-websocket` (comme pour `pauldoazan/positions-and-moves`). Sans cela, le premier déploiement Pages échoue.

## 2. Pousser la branche

```bash
git push -u origin pauldoazan/server-websocket
```

Le push déclenche :
- la construction du jeu sur GitHub Pages pour cette branche (`.github/workflows/pages.yml`) ;
- côté Render, un redéploiement automatique du service une fois qu'il existe (`autoDeploy: true`).

## 3. Créer le service sur Render

1. Créer un compte sur https://render.com (connexion avec GitHub, et autoriser l'accès au dépôt `PaulDoazan/bomberman`).
2. New → Blueprint, choisir le dépôt `PaulDoazan/bomberman`, branche `pauldoazan/server-websocket`.
3. Render lit `render.yaml` : vérifier le service `bomberman-pauldoazan`, la branche `pauldoazan/server-websocket`, la région Frankfurt, et choisir l'instance Free si Render le demande, puis Apply. La première construction prend quelques minutes.

## 4. Vérifier l'adresse

Le service doit répondre sur `https://bomberman-pauldoazan.onrender.com`. Si Render a donné une autre adresse (nom déjà pris, suffixe ajouté), remplacer `PROD_URL` dans `src/net/net.gd` par `wss://<adresse>` (même hôte, `wss://` au lieu de `https://`), ou donner l'adresse à Claude. Ce changement doit être committé et poussé pour que Pages reconstruise le jeu.

## 5. Avant de jouer

Sur l'offre gratuite, le serveur s'endort après environ 15 minutes sans connexion. Il se réveille à la première connexion, ce qui prend environ une minute. Ouvrir la page du jeu (https://pauldoazan.github.io/bomberman/) environ une minute avant de jouer : l'accueil affiche « Réveil du serveur… » puis les boutons en ligne deviennent actifs. Partager ensuite le lien avec `#CODE`.

## 6. Journaux et charge

Dans le tableau de bord Render, onglet Logs : on y voit les parties créées, les joueurs qui arrivent et partent. Pour confirmer que le serveur est vivant, chercher la ligne `Serveur à l'écoute sur …` dans les Logs, juste après le démarrage. Onglet Metrics : CPU et mémoire. Si le CPU reste au-dessus de 80 % pendant une partie, passer à l'offre Starter.

## 7. Test de charge (optionnel, avant la première partie)

Le serveur accepte au plus 4 parties à la fois (l'offre gratuite n'a que 0,1 CPU). Pour vérifier qu'une partie à 12 tient, réveiller le serveur (ouvrir la page du jeu), puis lancer depuis le dépôt, en gardant l'onglet Metrics de Render ouvert :

```bash
godot --headless --path . -s res://tests/e2e_online.gd -- --url=wss://bomberman-pauldoazan.onrender.com --clients=12
```

Le script joue une partie à 12 clients (2 joueurs et 10 bots qui bougent au hasard) pendant 15 secondes, puis affiche le plus grand écart entre deux instantanés reçus (normalement autour de 70 ms) et `PASS`. Si le CPU reste au-dessus de 80 % pendant le test, ou si l'écart dépasse 300 ms, envisager l'offre Starter.

## Tester en local

```bash
# 1. Le serveur (port 9080 par défaut, ou PORT=...)
godot --headless --path . -- --server

# 2. L'export web, dans un autre terminal
mkdir -p build/web
godot --headless --path . --export-release "Web" build/web/index.html
cd build/web && python3 -m http.server 8000

# 3. Ouvrir dans le navigateur
http://localhost:8000/?server=ws://localhost:9080
```

Pour tester l'image Docker : `docker build --platform linux/amd64 -t bomberman-server .` puis `docker run -p 9080:9080 -e PORT=9080 bomberman-server`. Le script `tests/e2e_online.gd` accepte `-- --url=ws://localhost:9080` pour viser un serveur déjà lancé.
