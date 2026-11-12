# Checklist d'essai — branche `qt1/essai`

Cochez au fur et à mesure (`[x]`). Quand un point ne va pas, notez son code (ex. « D4 ») et ce que vous voyez : c'est tout ce qu'il me faut pour corriger le bon lot.

Avant tout : sauvegarde des réglages faite (`~/Desktop/FilmCan-sauvegarde` + `FilmCan-prefs.plist`).

---

## 1. D'abord : rien de cassé sur vos films existants (le plus important)

- [ ] **S1** Au lancement, vos films qui partagent un preset gardent le même nom de preset et le même aperçu de dossiers. Aucune mention « (modified) ».
- [ ] **S2** Copier une carte déjà sauvegardée avec un film existant : mêmes dossiers, mêmes fichiers qu'avant (la reprise retrouve tout).
- [ ] **T9** Un film existant avec sa propre structure, sans y toucher : même aperçu, mêmes dossiers écrits qu'avant.
- [ ] **F5** Un film existant : les réglages « détection des cartes » et « rapport PDF » sont restés comme vous les aviez.
- [ ] **R8 (rapports)** Même copie qu'avant : mêmes dossiers et fichiers sur le disque de destination.
- [ ] **L12** Le journal et l'historique d'une copie ont la même formulation qu'avant.
- [ ] **S3** Changer la structure du film A ne change pas le film B.

## 2. Premier lancement et démo (sans carte ni disque) — PR #12, #2

- [ ] **D1** Fermer tous les onglets : sous « Create First Movie », un bouton « Try with made-up cards » et deux lignes d'explication.
- [ ] **D2** Cliquer : un film « Demo » avec 2 sources (A001, S001 marquée Sound) et 2 destinations, bande jaune « Stop the demo » en haut.
- [ ] **D3** Lancer la copie : vraie copie de quelques secondes, barre jaune puis verte jusqu'à 100 %.
- [ ] **D4** Pendant la copie : « Stop the demo » est grisé.
- [ ] **D5** Historique et Catalogue : la copie de démo et ses deux rolls y sont.
- [ ] **D6** « Stop the demo » : onglet, historique, rolls et dossier `~/Library/Application Support/FilmCan/Demo` disparaissent ; les autres films sont intacts.
- [ ] **D8** Démo lancée, quitter et relancer : le film Demo est toujours là, Stop nettoie toujours tout.
- [ ] **D9** Supprimer le film Demo à la main : le bouton revient et relance une démo propre.
- [ ] **D10** Copie d'un autre film en cours, lancer la copie démo : Stop reste grisé tant que la démo copie.
- [ ] **F1** `tccutil reset All com.filmcan.app`, relancer, ajouter une carte : le dialogue macOS explique pourquoi FilmCan veut accéder au volume.
- [ ] **F2** Même chose avec un dossier dans Documents, Bureau, Téléchargements : chaque dialogue a sa phrase.
- [ ] **F3** Carte branchée, « + » nouveau film : la carte apparaît seule dans Copy From, marquée Camera (ou Sound).
- [ ] **F4** Nouveau film : « Detect camera and sound cards automatically » et « PDF report with thumbnails » sont activés.
- [ ] **F6** Copier une vraie carte avec et sans rapport PDF, chronométrer : noter le temps ajouté par les vignettes.
- [ ] **F7** Quick Copy (clic droit Finder › Services › FilmCan Copy) : pas de rapport PDF.

## 3. Écran principal — PR #6

- [ ] **M1** Film avec `{day}` (ex. Netflix) : `‹ Day02 ›` à côté du titre. Film sans `{day}` : pas de sélecteur.
- [ ] **M2** Cliquer `›` puis `‹` : le jour change partout (sélecteur, ligne de résumé, aperçu Save To) en un clic.
- [ ] **M3** Compteur de jour automatique activé, cliquer `›` : le jour d'aujourd'hui change.
- [ ] **M4** Jour en texte (« Pickups ») : le sélecteur l'affiche, flèches grisées.
- [ ] **M5** 1 carte, 2 disques : une ligne de résumé au-dessus des colonnes ; moins de 25 textes visibles hors historique.
- [ ] **M6** 3 cartes, 2 disques : tout tient sans défiler en 1280 × 800 ; les liens entre colonnes n'ont pas bougé.
- [ ] **M7** Sous « Run Now » : le sous-titre change selon le cas (pas de carte, pas de disque, dossiers à créer, déjà copié).
- [ ] **M8** Une carte entière : pas de ligne de chemin (infobulle sur le nom). Un sous-dossier : chemin affiché.
- [ ] **M9** Un seul élément : pas de numéro. Deux : 1, 2, cases alignées.
- [ ] **M10** Après une copie : Save To montre une ligne repliée « Folders already on every drive ».
- [ ] **M11** `defaults delete com.filmcan.app historyListView`, relancer : historique en liste compacte ; passer en cartes, relancer : reste en cartes.
- [ ] **M12** Pendant une copie : sélecteur de jour grisé, « Backup in progress ».

## 4. Réglages du film et fenêtre Réglages — PR #7, #8

- [ ] **L1** Sous Copy From / Save To : une seule ligne « Movie settings » avec un résumé, plus de carte Options.
- [ ] **L2** Cliquer : un volet à droite (Basic / Source / Destinations / Logs + menu Preset) ; les colonnes restent lisibles.
- [ ] **L3** Changer la structure dans le volet : l'aperçu Save To suit tout de suite.
- [ ] **L4** Parcourir les 4 groupes en 1280 × 800 et en plein écran : tous les réglages sont là, rien de coupé.
- [ ] **L5** Volet ouvert, ouvrir Historique puis Catalogue : le volet se ferme ; recliquer la ligne le rouvre.
- [ ] **L6** Volet ouvert, changer d'onglet, relancer : le volet reste ouvert sur le bon film.
- [ ] **L8** Fenêtre au minimum : le volet prend toute la place, bouton fermer en haut à droite.
- [ ] **L9** Visite guidée : l'ancienne étape « Options Tabs » montre la ligne « Movie settings ».
- [ ] **L10** Réglages (Cmd+,) : barre latérale avec 8 pages ; la dernière page ouverte est retenue.
- [ ] **L11** Libellés simples : « Full check (re-reads every file) », « If a file already exists », « Checksum list format », « Folder layout »…
- [ ] **S4** Menu Preset : Off, Netflix Ingest, presets partagés une seule fois, « Save as new preset », « Delete preset ».
- [ ] **S5** Preset choisi dans A puis modifié, même preset dans B : B reçoit le preset tel qu'enregistré.
- [ ] **S6** « Save as new preset » dans A : visible dans tous les films ; A garde ses réglages.
- [ ] **S7** « Off » puis « This movie's settings (…) » : les dossiers du film reviennent intacts. Poubelle : le film passe à Off.
- [ ] **S8** « Delete preset » : les films partis de ce preset gardent leurs dossiers.
- [ ] **S9** Petite flèche à côté de « + » › « Like ‹film› » : nouveau film avec mêmes options, sans cartes ni disques ni jour.
- [ ] **S10** Film « Citizen K » avec `CITIZENK/{day}`, créer un film « comme » lui nommé « Citizen L » : son gabarit commence par `{movie}`, l'aperçu montre `Citizen L/…`.
- [ ] **S11** Taper `{movie}` dans un gabarit : l'aperçu montre le nom du film.
- [ ] **S12** Supprimer un film, quitter : plus aucune trace de lui dans `presets.json`.
- [ ] **S13** Quick Copy : le menu Preset montre les presets partagés + les réglages du film choisi seulement.
- [ ] **S14** Export des presets : seulement les presets partagés.
- [ ] **S15** Exporter un film, le supprimer, le réimporter : même preset, même aperçu.

## 5. Éditeur de structure de dossiers — PR #9

- [ ] **T1** Nouveau film › Destinations : « Start from » avec 4 choix, puis un petit arbre « Drive ».
- [ ] **T2** « Several days » : arbre Film › Jour › Camera / Sound ; texte `{movie}/{day}/Camera`.
- [ ] **T3** Renommer « Camera » en RUSHES : arbre, texte et aperçu suivent.
- [ ] **T4** Ajouter un dossier Date, monter/descendre, supprimer : tout suit ; boutons grisés quand impossible.
- [ ] **T5** « Put sound with the cards » puis « Give sound its own folder » : un dossier porte les deux marques, puis un dossier Sound apparaît.
- [ ] **T6** Changer de « Start from » : confirmation demandée.
- [ ] **T7** Taper `ARRI/{sourceDriveName}/CARD_{source}` : l'arbre laisse place à une phrase, l'aperçu suit le texte.
- [ ] **T8** Film Netflix Ingest : l'arbre et les champs Camera/Sound se suivent dans les deux sens.
- [ ] **T10** Aperçu (Save To et Quick Copy) : marque « new » sur les dossiers à créer ; disparaît après la copie.
- [ ] **T11** Volet le plus étroit : les 4 choix passent à la ligne, rien de caché.
- [ ] **T12** « Folder layout » désactivé : phrase à la place de l'arbre ; réactivé : même structure.
- [ ] **T13** Preset › Off : phrase « réglages mis de côté » ; « This movie's settings » les rend intacts.
- [ ] **T14** Renommer un dossier `Café` : il devient `Caf` partout.

## 6. Rapports — PR #5, #11

- [ ] **R1** Réglages › History : section « Reports », activée, chemin `~/Documents/FilmCan Reports`.
- [ ] **R2** Copie avec rapport, jour Day02, 2 disques : `FilmCan Reports/‹film›/Day02/‹disque›/` contient le PDF et la liste de sommes, pour chaque disque.
- [ ] **R3** Disques éjectés : le PDF s'ouvre depuis ce dossier, avec vignettes.
- [ ] **R4** Film sans jour : le dossier du jour porte la date du jour.
- [ ] **R5** Rapport désactivé : rien de nouveau dans `FilmCan Reports`.
- [ ] **R6** « Choose… » un autre dossier, puis « Reset » : ça suit.
- [ ] **R7** « Keep a copy of every report on this Mac » désactivé : pas de copie, le rapport sur le disque est toujours écrit.
- [ ] **G1** Copie sans rapport, Catalogue, clic droit sur le roll : « Create report from ‹disque› » + variante « re-reading every file (slow) ».
- [ ] **G2** Créer : « Creating the report for… », puis le Finder s'ouvre sur `‹roll›_report_recreated.pdf`.
- [ ] **G3** Le PDF : vignettes, sommes, « Report created after the backup, on … » ; jamais « Verified ».
- [ ] **G4** Supprimer un clip et ajouter un fichier texte sur le disque, recréer : clip manquant listé, fichier texte « Not in the checksum list », statut rouge.
- [ ] **G5** Variante « re-reading » sur un roll intact : statut vert « Re-checked: N of N ».
- [ ] **G6** Disque éjecté : une seule entrée grisée.
- [ ] **G7** Disque renommé dans le Finder : trouvé quand même.
- [ ] **G8** Rien n'a été ajouté sur le disque.
- [ ] **G9** Film avec la liste de sommes cachée simple : rapport sans sommes, le statut le dit.

## 7. Page Reconnaissance — PR #10

- [ ] **R1 (Recognition)** Réglages › Recognition : 4 groupes, rien de coupé.
- [ ] **R2 (Recognition)** « Cards it knows » : une ligne par famille avec une raison.
- [ ] **R3 (Recognition)** Clic droit sur une carte › « Not a camera card » : le disque apparaît sur la page, « Not a card », date du jour.
- [ ] **R4 (Recognition)** Forget : la ligne disparaît, la carte est de nouveau proposée.
- [ ] **R5 (Recognition)** Disque corrigé éjecté : il garde son nom, « not connected ».
- [ ] **R6 (Recognition)** Numérotation active, une copie : le film est listé avec ses cartes et la date.
- [ ] **R7 (Recognition)** Oublier un nom de roll, rebrancher la carte : elle reçoit un nouveau nom, plus haut que tous ; les autres gardent le leur.
- [ ] **R8 (Recognition)** Correction d'avant cette version : « Drive not connected (…) » jusqu'au branchement.

## 8. Notifications téléphone — PR #3 (téléphone nécessaire)

- [ ] **P1** Préférences ntfy effacées (commandes dans `docs/smoke-qa-checklist.md`), Réglages › Push : un interrupteur, éteint ; « Advanced » replié.
- [ ] **P2** L'allumer : un QR code et un nom de canal `filmcan-…`.
- [ ] **P3** Scanner avec un téléphone sans ntfy : la page FilmCan s'ouvre dans la langue du téléphone, propose le bon store. *(La page n'est en ligne qu'une fois `website/phone/` publié sur `main` : sinon, sauter P3 et P11.)*
- [ ] **P4** Installer ntfy, s'abonner, « Send a test » : reçu en moins de 2 minutes. Noter si « Open in ntfy » marche sur iPhone / Android.
- [ ] **P5** Une petite copie : message de fin reçu.
- [ ] **P6** « New code… » : nouveau code ; l'ancien abonnement ne reçoit plus rien.
- [ ] **P7** Quitter, relancer : même code, les notifications arrivent toujours.
- [ ] **P8** Mac avec une URL ntfy déjà configurée : « Advanced » ouvert, URL et jeton intacts, pas de QR.
- [ ] **P9** « Use my own ntfy server » off puis on : QR puis retour à votre URL.
- [ ] **P10** `defaults write com.filmcan.app ntfyEnabled -bool true` sans URL : bouton « Create my QR code », rien d'envoyé avant le clic.
- [ ] **P11** `https://www.filmcan.eu/phone/` sans `#` : la page demande de rescanner, pas d'erreur.
- [ ] **D7** Notifications configurées, copie de la démo : rien sur le téléphone.

## 9. Matériel réel (cartes, disques, hub, USB 2)

Cartes — PR #4 :
- [ ] **C1** Carte `DCIM` avec vidéo (appareil photo, drone, téléphone) : ajoutée, badge « Camera card ».
- [ ] **C2** Carte `DCIM` avec photos seulement : non ajoutée.
- [ ] **C3** Carte Insta360 : badge « Insta360 card ».
- [ ] **C4** Carte AVCHD : badge « AVCHD card » ; Panasonic `PANA_GRP` et Sony `M4ROOT` gardent leur badge.
- [ ] **C5** Carte Panasonic P2 : badge « Panasonic card ».
- [ ] **C6** ARRI, RED, Sony, Canon, Blackmagic, GoPro, DJI, enregistreur son : même badge qu'avant.
- [ ] **C7** Disque de sauvegarde avec un `DCIM` vidéo à la racine : proposé comme carte ; « Not a camera card » le retire pour de bon.

Vitesse — PR #13 :
- [ ] **V1** SSD USB 3 + disque dur à plateaux USB 3 en destinations, mode Automatic : bande « ‘‹disque dur›’ sets the pace… » avec « Copy to ‘‹SSD›’ first ».
- [ ] **V2** Cliquer le bouton : le SSD passe en haut, mode « One destination at a time », bande disparue.
- [ ] **V3** Remettre le disque dur en haut : bande « ‘‹SSD›’ waits behind… ».
- [ ] **V4** « Dismiss », débrancher/rebrancher : la bande ne revient pas.
- [ ] **V5** Lecteur ou disque en USB 2 : bande « connected over USB 2 ».
- [ ] **V6** Deux disques sur le même hub : bande « share one USB hub » ; branchés directement : rien.
- [ ] **V7** SSD rempli à plus de 90 % par la copie : bande « over 90 % full ».
- [ ] **V8** Deux SSD USB 3 seulement : aucune bande de lenteur.
- [ ] **V9** Pendant une copie : aucune bande.
- [ ] **V10** Copie ≥ 1 Go, une destination à la fois, SSD + disque dur : phrase « ‘‹disque dur›’ was the slowest drive: … » sous les colonnes.
- [ ] **V11** Quick Copy ≥ 1 Go : aucune phrase de vitesse.

Veille :
- [ ] **Capot fermé** Lancer une copie de plusieurs minutes, fermer le capot 2 minutes, rouvrir. Noter : reprend seule ? échoue ? barre figée ? ce que dit l'historique ; puis relancer pour voir si la reprise marche. Sur secteur puis sur batterie.
