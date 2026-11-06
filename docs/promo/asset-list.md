# FilmCan — assets promo (site + réseaux)

Statut : **[S]** = capture d'écran de l'app (faite dans `assets/promo/`), **[M]** = montage à partir des captures, **[V]** = vidéo/GIF, **[T]** = texte/design seul.

## 1. Site web (`website-src/index.template.html`)

| # | Asset | Format | Où | Source |
|---|-------|--------|----|--------|
| W1 | Capture héros : copie en cours vers 2 disques (ARRI + DJI), onglets films | 3024×1894 (2×) | hero, remplace `screenshot-main.png` | [S] |
| W2 | Capture « terminé et vérifié » + historique en cartes | 3024×1894 | section « Verified for you » | [S] |
| W3 | Zoom sur une carte destination (barre jaune copie + verte vérif, débit, ETA) | ~1400×900 recadré | tuile fonctionnalité « Multi-destination » | [S] |
| W4 | Panneau Options (Basic / Destinations / Refinements) | ~1600×700 | tuile « Vérification, doublons, presets » | [S] |
| W5 | Réglages (accent Kodak/Fuji/Sony/RED/ARRI, notifications ntfy, historique) | ~1200×900 | tuile « Personnalisable » | [S] |
| W6 | Fenêtre Quick Copy (clic droit Finder → Services), deux colonnes | ~900×700 | section dédiée Quick Copy | [S] |
| W7 | Quick Copy en cours de copie | ~900×700 | idem | [S] |
| W8 | Catalogue (volet à droite de la fenêtre principale) / rapport PDF / numérotation A001-S001 | selon UI | tuiles nouveautés 1.4+ | à faire |
| W9 | `og-image.png` | 1200×630 | partage lien (Slack, X, LinkedIn) | [M] |
| W10 | Favicon / apple-touch-icon | déjà présents | — | — |
| W11 | Boucle courte de copie (10 s, sans son) | MP4 + WebM, 1600×1000 | hero ou « How it works » | [V] |
| W12 | 4 étapes « How it works » (sources → destinations → Run → vérifié) | 4 crops | section `#how` | [M] |
| W13 | Variantes FR / DE / ES si l'UI est traduite | idem W1 | pages `/fr`, `/de`, `/es` | à voir |

## 2. Réseaux sociaux

| # | Asset | Format | Plateforme | Source |
|---|-------|--------|------------|--------|
| S1 | Carte « Une passe, tous les disques » (capture W1 dans un cadre) | 1080×1350 (4:5) | Instagram, LinkedIn | [M] |
| S2 | Carte carrée vérification xxHash128 + ASC MHL | 1080×1080 | Instagram, Mastodon | [M] |
| S3 | Story / Reel : Quick Copy depuis le Finder (3 écrans) | 1080×1920 | Instagram, TikTok | [M]/[V] |
| S4 | Image d'annonce de version (numéro + 3 nouveautés) | 1600×900 | X, LinkedIn, Bluesky | [M] |
| S5 | Capture seule, fond sombre propre, coins arrondis | 2400×1500 | Reddit, forums DIT, Product Hunt | [S] |
| S6 | Galerie Product Hunt (5 images) | 1270×760 | Product Hunt | [M] |
| S7 | Social preview GitHub | 1280×640 | dépôt GitHub | [M] |
| S8 | Démo 30 s : carte → 2 disques → ✓ vérifié | 1920×1080 + 1080×1920 | YouTube, X, Reels | [V] |
| S9 | GIF : barre jaune → verte, coche finale | 800 px large | README, forums | [V] |
| S10 | Avant/après « Finder vs FilmCan » (pas de vérif vs hash-check) | 1080×1350 | LinkedIn | [M] |

## 3. Kit presse / README

- Icône 1024 px fond transparent, logo + nom (clair et sombre).
- 3 captures plein écran (W1, W2, W5) sans coins ombrés.
- Texte court (1 ligne, 1 paragraphe), liste de fonctions, lien de téléchargement, version, licence GPL-3.0.
- README : bandeau GitHub (S7) + GIF (S9).

## 4. Règles pour toutes les captures

- Données factices uniquement : projets `Citizen K`, `Les 2048 Coups`, `Life Is A Crazy Miracle`, `MyShortMovie` ; cartes `A003R1KD` (ARRI), `DJI_RONIN` (DJI) ; disques `CK_backup_01/02`. Aucun chemin ni nom réel.
- Fenêtre sans ombre portée (`screencapture -o`), mode sombre, accent par défaut.
- Toujours 2× (Retina) ; réduire à la sortie, jamais agrandir.
- Pas de dock, pas de barre de menus, pas de notification visible.

## 5. Méthode de capture (reprise 2026-11-06)

Tout passe par **`scripts/promo_screenshots.sh`** (build Debug + mode demo, faux home, faux volumes, capture, images dérivées). Ne rien faire à la main :

```
scripts/promo_screenshots.sh setup      # build Debug si besoin, crée/monte les volumes factices, remet le faux home à zéro
scripts/promo_screenshots.sh all        # 21 images + screenshot-main.png x2 + og-image.png (~5 min)
scripts/promo_screenshots.sh shot 03 21 # une ou plusieurs images (numéro du fichier)
scripts/promo_screenshots.sh cleanup    # quitte l'app, démonte et supprime les images disque, supprime les prefs promo
```

Variables : `PROMO_WORK` (dossier de travail, défaut `$TMPDIR/filmcan-promo` : faux home, `.sparseimage`), `PROMO_APP` (build Debug à utiliser, défaut `FilmCan/build/promo/...`). Le Mac doit rester libre pendant `all` (clics et frappes réels dans la fenêtre FilmCan, Accessibilité requise pour le terminal).

- **Sécurité** : l'app ne tourne que sur une **copie** (`$PROMO_WORK/promo-app/FilmCan.app`, bundle id `com.filmcan.app.promo`, sans `NSServices`, signature ad hoc) avec `CFFIXED_USER_HOME=$PROMO_WORK/fakehome`. Les vraies préférences `com.filmcan.app` (URL ntfy, dernier film, cadres de fenêtre) ne sont jamais lues ni écrites. Le script refuse de tourner si le faux home est le vrai home, est dedans (`~/Library`) ou le contient, et s'arrête si un volume réel porte déjà le nom d'un faux volume.
- **Faux home** : `scripts/promo_fixtures/{configs,presets,history,catalog}.json`, copiés à chaque `setup`. Le preset `Alexa35` a les mêmes réglages que la config `Citizen K` (vérif `fast`, parallèle), sinon le menu affiche « (modified) ». Dossiers : caméra `CITIZENK/RUSHES/Camera_Media/{source}`, son `CITIZENK/RUSHES/Sound_Media/{source}` (deux branches dans « Folders on every drive »).
- **Volumes** : 5 `.sparseimage` APFS (`A003R1KD` 11g, `DJI_RONIN` 7g, `ZOOM_F6` 2g, `CK_backup_01/02` 32g). Les clips sont des fichiers **creux** (`truncate -s`) : 11 .mov ARRI de 890 Mo (9,79 Go), 13 .MP4 DJI de 377 Mo (4,9 Go), 10 WAV de 30 Mo (0,3 Go) = 14,99 Go, quasi aucun espace disque réel. `ZOOM_F6` (et pas `ZOOM_F8`, nom pris par une carte factice du dev) est la 3e source de `Citizen K`, réglée sur Sound. Rien n'est copié : le mode demo fige l'état.
- **Capture** : `screencapture -o -x -l <windowID>` (ID via `CGWindowListCopyWindowInfo` sur le PID), fenêtre principale remise à 1392×873 pt, Réglages 560×748, Quick Copy 900×652, Catalogue 760×592. `open -a` avant chaque capture pour avoir les feux tricolores actifs.
- **Hero** : `assets/screenshot-main.png` et `website/assets/screenshot-main.png` = copie de `03-backup-copying-60.png`. `website/assets/og-image.png` = montage PIL 1200×630 (fond #1b1b1b, titre Avenir Next, capture 03 réduite à 940 px avec ombre, icône en haut à droite), généré par `scripts/promo_screenshots.sh derive`.
- Ne jamais capturer l'onglet About (IBAN du dev).

## 6. Demo mode (fast screenshots)

Build Debug uniquement (`#if DEBUG`, code dans `FilmCan/Sources/Debug/DemoMode.swift`) : absent du Release. Il fige une fausse copie fan-out : rien n'est copié, aucun manifest/MHL, aucune notification, aucune entrée d'historique écrite. Sources, destinations, cartes, barres de capacité et arbre de dossiers restent ceux de la config sélectionnée.

| Variable | Valeur | Défaut |
|----------|--------|--------|
| `FILMCAN_DEMO_STATE` | `copying`, `verifying`, `done` (`setup` : Quick Copy seulement) | absente = mode inactif |
| `FILMCAN_DEMO_PROGRESS` | 0 à 1, avancement de la phase en cours (copie ou vérif) | `0.60` |
| `FILMCAN_DEMO_SPEED_MBPS` | débit en Mo/s (décimal), sert aussi à l'ETA | `500` |
| `FILMCAN_DEMO_TOTAL_GB` | taille du job en Go (décimal) ; mettre la somme réelle des sources (14.99 fenêtre principale, 14.69 Quick Copy) | `14.75` |
| `FILMCAN_DEMO_QUICKCOPY` | sources séparées par des virgules : ouvre une fenêtre Quick Copy | absente |
| `FILMCAN_DEMO_QUICKCOPY_DEST` | destinations séparées par des virgules | vide |

Cohérence : octets copiés = total × progression, ETA = octets restants / débit (14,75 Go à 60 % et 500 Mo/s : 8,85 / 14,75 Go, 12 s). En `copying`, la vérif suit à 85 % de la copie. En `verifying`, la copie est à 100 % et la barre verte porte la progression (titre Quick Copy « Verifying… »). En `done`, les cartes sont `Complete` et les résultats verts (en mémoire seulement). Le panneau Historique affiche le `history.json` du faux home : rien n'y est ajouté.

Lancement : `scripts/promo_screenshots.sh shot <n>` positionne les variables ci-dessous (vitesse 500 Mo/s partout) et utilise la copie « promo » de l'app (bundle id `com.filmcan.app.promo`, voir section 5). À la main, avec le même faux home :

```
open -n --env CFFIXED_USER_HOME=<faux home> --env FILMCAN_DEMO_STATE=copying \
  --env FILMCAN_DEMO_PROGRESS=0.60 --env FILMCAN_DEMO_SPEED_MBPS=500 --env FILMCAN_DEMO_TOTAL_GB=14.99 \
  <PROMO_WORK>/promo-app/FilmCan.app
```

Piège : lancer le `.app` Debug d'origine (bundle id `com.filmcan.app`) lit et écrit les VRAIES préférences (`CFFIXED_USER_HOME` ne les redirige pas) : URL ntfy réelle visible dans Réglages > Push, dernier film, cadres de fenêtre. Toujours passer par la copie promo. En demo, Cmd+Q quitte sans dialogue. Limite : le nombre de fichiers affiché en demo est fixe (15, « 15 files copied » dans Quick Copy), indépendant des vrais fichiers.

| Capture | Variables |
|---------|-----------|
| 02-backup-copying-36 | `STATE=copying PROGRESS=0.36` |
| 03-backup-copying-60 (hero) | `STATE=copying PROGRESS=0.60` |
| 04-backup-verifying-77 | `STATE=verifying PROGRESS=0.77` |
| 05-backup-done | `STATE=done` |
| 20-quickcopy-setup | `QUICKCOPY=/Volumes/A003R1KD,/Volumes/DJI_RONIN QUICKCOPY_DEST=/Volumes/CK_backup_01,/Volumes/CK_backup_02` (sans STATE) |
| 21 / 22 quickcopy-copying | idem + `STATE=copying PROGRESS=0.21` / `0.48` |
| 23-quickcopy-verifying-88 | idem + `STATE=verifying PROGRESS=0.88` |
| 24-quickcopy-done | idem + `STATE=done` |
| 01, 06 à 17 | pas de demo (mode normal) ; le script clique les onglets Options (06 à 08), ouvre Réglages (10 à 15) et le Catalogue (Window > Catalog / Open Catalog in Window, recherche `A003C00`) |
