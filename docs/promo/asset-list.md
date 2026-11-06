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
| W6 | Fenêtre Quick Copy (clic droit Finder → Services) | ~900×700 | section dédiée Quick Copy | [S] |
| W7 | Quick Copy en cours de copie | ~900×700 | idem | [S] |
| W8 | Catalogue / rapport PDF / numérotation A001-S001 | selon UI | tuiles nouveautés 1.4+ | à faire |
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
