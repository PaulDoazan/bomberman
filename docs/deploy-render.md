# Mise en ligne : cafenavette.com sur Render

Tout tourne sur Render, décrit par `render.yaml` et déployé depuis GitHub :

- **`cafenavette-site`** (site statique, gratuit, toujours éveillé) : la page du jeu sur https://cafenavette.com. Render la construit lui-même avec `deploy/build-web.sh` (Godot et ses modèles d'export web, environ 2 min 30).
- **`cafenavette`** (service web Docker, offre gratuite, région Francfort) : le serveur de parties. Le jeu s'y connecte en WebSocket sur `wss://cafenavette-7qgq.onrender.com` (`PROD_URL` dans `src/net/net.gd`) ; les joueurs ne voient jamais cette adresse. Dans l'image, nginx écoute sur le `PORT` de Render, transmet les WebSocket au serveur Godot (port interne 9090) et renvoie les navigateurs vers https://cafenavette.com ; `/healthz` répond `ok`.

**CI/CD.** À chaque push, GitHub Actions lance les tests (`.github/workflows/ci.yml`, « Tests »). Render ne déploie les deux services que si ces tests passent (`autoDeployTrigger: checksPass`). Cette branche n'est plus publiée sur GitHub Pages.

**Liens d'invitation.** Le salon partage `https://cafenavette.com/CODE` : le site sert la page du jeu sur n'importe quel chemin, et le jeu lit le code dans l'adresse (les liens `#CODE` marchent toujours).

> **Mêmes versions.** Le site et le serveur doivent venir du même commit, sinon le jeu affiche « Nouvelle version du jeu : recharge la page ». Le site se construit plus lentement que le serveur ; recharger la page une fois les deux déploiements terminés.

## 1. Synchroniser le Blueprint

Dans Render → Blueprints :

- **Si le service `cafenavette` a été créé par un Blueprint**, ouvrir ce Blueprint et cliquer sur Sync (ou attendre la synchronisation automatique après le push). Render propose de créer `cafenavette-site` et met à jour `cafenavette` (vérification de santé sur `/healthz`, déploiement après les tests) : Apply.
- **Sinon** (service créé avec New → Web Service), New → Blueprint, dépôt `PaulDoazan/bomberman`, branche `pauldoazan/server-websocket`. Si Render veut créer un second service `cafenavette` au lieu de reprendre l'existant, supprimer l'ancien avant d'appliquer, puis donner la nouvelle adresse `onrender.com` du serveur à Claude (elle va dans `PROD_URL`).

## 2. Relier cafenavette.com (Cloudflare)

1. Render → `cafenavette-site` → Settings → Custom Domains : `cafenavette.com` est déjà listé (venu de `render.yaml`), avec `www.cafenavette.com` qui redirige vers lui. Render y indique la cible, du genre `cafenavette-site.onrender.com`.
2. Cloudflare → cafenavette.com → DNS → Records :
   - `CNAME` nom `@` → `cafenavette-site.onrender.com` (Cloudflare l'aplatit pour le domaine racine) ;
   - `CNAME` nom `www` → `cafenavette-site.onrender.com` ;
   - pour les deux, **Proxy status : DNS only** (nuage gris), sinon Render ne peut pas délivrer le certificat ;
   - supprimer tout enregistrement `A` ou `AAAA` existant sur `@` et `www` (Render n'utilise pas l'IPv6).
3. Revenir dans Render et cliquer sur Verify pour chaque domaine. Le certificat HTTPS arrive en quelques minutes.

Le domaine racine et `www` font les 2 domaines inclus dans l'offre Hobby.

## 3. Vérifier

- https://cafenavette.com ouvre le jeu ; https://cafenavette.com/ABC234 l'ouvre avec le code `ABC234` déjà rempli.
- https://cafenavette-7qgq.onrender.com/healthz répond `ok` (après le réveil du serveur).

## 4. Avant de jouer

Sur l'offre gratuite, le serveur s'endort après environ 15 minutes sans connexion et se réveille à la première, ce qui prend environ une minute. La page, elle, s'ouvre tout de suite : l'accueil affiche « Réveil du serveur… » puis les boutons en ligne deviennent actifs. Ouvrir https://cafenavette.com environ une minute avant de jouer, puis partager le lien du salon.

## 5. Journaux et charge

Dans Render → `cafenavette` → Logs : les parties créées, les joueurs qui arrivent et partent, et la ligne `Serveur à l'écoute sur 9090` au démarrage. Onglet Metrics : CPU et mémoire. Si le CPU reste au-dessus de 80 % pendant une partie, passer à l'offre Starter.

## 6. Test de charge (optionnel, avant la première partie)

Le serveur accepte au plus 4 parties à la fois (l'offre gratuite n'a que 0,1 CPU). Pour vérifier qu'une partie à 12 tient, réveiller le serveur, puis lancer depuis le dépôt, en gardant l'onglet Metrics de Render ouvert :

```bash
godot --headless --path . -s res://tests/e2e_online.gd -- --url=wss://cafenavette-7qgq.onrender.com --clients=12
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

Pour tester l'image Docker : `docker build --platform linux/amd64 -t cafenavette-server .` puis `docker run -p 9080:9080 -e PORT=9080 cafenavette-server` (nginx sur 9080, Godot sur 9090 à l'intérieur). Le script `tests/e2e_online.gd` accepte `-- --url=ws://localhost:9080` pour viser un serveur déjà lancé. Pour tester la construction du site comme Render : `bash deploy/build-web.sh` (sous Linux).
