# Captures promo FilmCan (données factices)

Fenêtre seule, mode sombre, coins transparents, Retina 2×. Reprises le 2026-11-06 avec le **mode demo** (build Debug, état figé, 500 Mo/s, rien n'est copié) via `scripts/promo_screenshots.sh`, sur la branche `qt1/ui-audit-batch1` (UI des lots 1 à 3 : cartes Save To avec légende « used · to copy · left », arbre de dossiers, échelle typo, Catalogue en volet, Quick Copy en deux colonnes). Projets `Citizen K` / `Les 2048 Coups` / `Life Is A Crazy Miracle` / `MyShortMovie`. Sources `A003R1KD` (ARRI, 11 clips, 9,79 Go), `DJI_RONIN` (DJI, 13 clips, 4,9 Go) et carte son `ZOOM_F6` (10 WAV, 0,3 Go, réglée sur Sound) = 14,99 Go (Quick Copy : les deux premières, 14,69 Go). Destinations `CK_backup_01/02`, preset `Alexa35`. Aucun chemin ni nom réel.

| Fichier | Contenu | Usage conseillé |
|---------|---------|-----------------|
| 01-backup-ready | Avant lancement, 3 cartes (dont la carte son) + 2 disques, arbre de dossiers Camera_Media / Sound_Media | étape « Add sources / destinations » |
| 02-backup-copying-36 | Copie 36 %, barre jaune, 500 Mo/s | hero secondaire |
| **03-backup-copying-60** | Copie 60 % : jaune + vert, 500 Mo/s, 12 s | **hero du site** (copié dans `screenshot-main.png`, base de `og-image.png`) |
| 04-backup-verifying-77 | Copie à 100 %, vérif à 77 % (la pastille affiche 99 %) | tuile « vérifié » |
| **05-backup-done** | 100 % ✓, cartes d'historique | **« Verified for you »**, annonce de version |
| 06/07/08-options-* | Onglets Source / Destinations / Logs (page défilée en bas) | tuiles « options » |
| 10 à 15-settings-* | Apparence, Notifications, Push, Historique, Disques, Raccourcis | tuile « personnalisable » |
| **16-catalog-search** | Fenêtre Catalogue : clips ARRI trouvés par nom, 2 copies ✓ | tuile Catalogue |
| **17-catalog-pane** | Fenêtre principale avec le Catalogue dans le volet droit, recherche `A003C00`, pastilles de disques cliquables | tuile Catalogue / nouveautés 1.4+ |
| **20-quickcopy-setup** | Quick Copy : deux colonnes, puces de preset, un seul arbre de dossiers, bouton Run noir sur jaune | section Quick Copy |
| 21 à 23-quickcopy-* | Copie 21 % / 48 % / vérif 88 % | Quick Copy en action |
| **24-quickcopy-done** | « Copied and verified » ×2 | fin de séquence Quick Copy |

Taille des fenêtres : principale 1392×873 pt (2784×1746 px), Réglages 560×748 pt (1120×1496 px), Catalogue 760×592 pt, Quick Copy 900×652 pt (taille par défaut du nouveau layout ; l'ancien faisait 1080×800 / 1080×490).

Non fait : « À propos » (contient l'IBAN du dev), onglet Netflix Ingest, rapport PDF, numérotation A001/S001. Limites du mode demo : le nombre de fichiers est fixe (« 15 files copied » dans Quick Copy 24, quel que soit le contenu) et la pastille de pourcentage d'une carte en vérification affiche 99 % tant que la copie n'est pas à 100 % exact. Le roll `DJI_RONIN` s'affiche encore « Files not indexed · Zero KB » dans le Catalogue si le catalogue ne liste pas ses fichiers (le jeu de données de `scripts/promo_fixtures/catalog.json` les liste).

Reproduire : `scripts/promo_screenshots.sh setup` puis `all` (ou `shot 03 21`), `cleanup` à la fin. Méthode et variables du mode demo : `docs/promo/asset-list.md`, sections 5 et 6.
