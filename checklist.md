# Checklist de test manuel : sessions d'audit

Une section par session. Chaque session ajoute et coche la sienne. Cocher = testé à la main sur un vrai Mac avec de vrais disques.
Les tests automatiques (workflow `macOS tests`) ne remplacent pas cette liste.

Build à tester sans toucher à `/Applications` (quitter les autres FilmCan avant) :

```
xcodebuild build -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -configuration Debug \
  -destination platform=macOS -derivedDataPath FilmCan/build/qc
open FilmCan/build/qc/Build/Products/Debug/FilmCan.app
```

Statut des sessions : 1 = finalisation des fichiers (fusionnée) · 2 = preuve de vérification et seal (fusionnée) · 3 = écrasement et collisions (fusionnée) · 4 = hash lists conformes et robustes (fusionnée) · 5 = résultats annoncés autour du moteur (fusionnée).

---

## Session 1 : finalisation des fichiers

Objectif : un fichier n'arrive jamais sous son nom final s'il est incomplet, et une vérification impossible est un échec, jamais un succès.
Tests automatiques : `FanOutCopierReadFailureTests` (7 tests).

Prérequis : une carte (ou clé USB) avec quelques clips de plus de 100 Mo, deux disques de destination, vérification **Paranoid**.

### Source arrachée en pleine copie (constats 1 et 4)
- [ ] Débrancher la carte pendant la copie d'un gros clip : les deux cartes de destination passent en rouge (« Source read failed for … »). Pas de plantage.
- [ ] Dans le Finder, aucune destination ne contient ce clip sous son nom final (pas de fichier tronqué).
- [ ] Aucun fichier `.filmcan-*` ne reste dans le dossier du roll (`ls -la`).
- [ ] L'historique montre un résultat **par destination**, pas un échec global sans détail.
- [ ] `ascmhl/` contient un manifest (partiel ou non) avec les clips déjà vérifiés.
- [ ] Rebrancher et relancer : seuls les clips manquants sont copiés, tout finit en vert, le roll est scellé dans `ascmhl_chain.xml`.

### Vérification impossible (constat 2)
- [ ] Difficile à provoquer à la main (couvert par tests). Si une erreur de relecture apparaît (disque qui décroche pendant « Verifying… ») : la destination doit finir en **échec de vérification**, jamais en vert.

### Fichier préexistant conservé par Skip (constat 3)
- [ ] Couvert par tests (corruption source simulée). À la main : vérifier qu'un fichier identique déjà présent avec Skip reste en place après la copie (recoupe la session 2).

### Régression à surveiller
- [ ] Copie normale Fast puis Paranoid, 2 destinations : tout en vert, 100 % sur les deux barres, aucune erreur « Incomplete file ».
- [ ] Quick Copy d'un seul clip (source = fichier, pas dossier) : copie et vérification en vert.
- [ ] Risque connu : un source choisi via un **lien symbolique** (fichier seul) peut être refusé par le nouveau contrôle de taille (« Incomplete file: … bytes written, … expected »). Le noter si ça arrive.

---

## Session 2 : « vérifié » et seal exigent une preuve par hash

Prérequis : une carte (ou un dossier) avec 3 à 5 clips, deux disques de destination, film réel (pas la démo).

### Off puis Fast (constat 1)
- [ ] Run 1 en Vérification **Off**. Les clips arrivent, la carte n'affiche **pas** de badge scellé.
- [ ] Run 2 en **Fast**, rien modifié. Le run relit les fichiers (plus long qu'un simple « déjà sauvegardé »), puis la carte est scellée.
- [ ] Run 1 en Off. Modifier un clip sur la destination sans changer sa taille (éditeur hexa : un octet). Run 2 en Fast : le clip est recopié, pas sauté. Le contenu redevient identique à la carte.
- [ ] Run 1 en Off, run 2 en Off : jamais de seal.
- [ ] Run 1 en Fast, run 2 en Fast : « déjà sauvegardé », carte scellée, pas de relecture lente.
- [ ] Dans `<dossier roll>/.filmcan/` : `unverified.json` existe après un run Off, disparaît après le run Fast qui a tout vérifié.

### Politique Skip (constat 2)
- [ ] Quick Copy (Skip par défaut) vers un dossier qui contient déjà un fichier **de même nom, contenu différent**, hors manifest : la destination passe en **échec** (« A different file with the same name is already there »). Le fichier existant est intact. Pas de seal.
- [ ] Même chose avec un fichier **identique** déjà présent : succès, le fichier est inscrit au manifest (`ascmhl/`), seal écrit.
- [ ] Un conflit sur un fichier n'empêche pas la copie des autres fichiers.
- [ ] Fermer le prompt de doublon sans répondre : même comportement que Skip (échec si différent).
- [ ] Texte de l'erreur lisible dans la carte de destination et dans l'historique.

### Reprise (constat 3)
- [ ] Après un run Fast, tronquer un clip de destination à 0 octet. Relancer : il est recopié.
- [ ] Idem avec le style de liste « simple » (Options › hash list).
- [ ] Reprise normale après un Stop : seuls les fichiers manquants sont copiés.

### Seal (constats 4, 5, 6)
- [ ] Carte avec un dossier illisible (`chmod 000`), choisir « continuer sans » : la copie réussit, la carte n'est **pas** scellée.
- [ ] Ajouter un clip à la carte pendant la copie : fin du run, la carte est « modifiée depuis le seal » (badge cassé), pas scellée à tort.
- [ ] Modifier la date d'un clip (`touch`) sans changer sa taille : le badge passe à « modifié ».
- [ ] Une ancienne carte scellée avec une version précédente apparaît « non scellée » (seal v1 ignoré). Attendu.
- [ ] Eject d'une carte scellée : pas d'avertissement. Carte non scellée : avertissement.
- [ ] « Essayer avec des cartes factices » (démo) : aucun `.filmcan/seal.json` dans les dossiers démo. Ajouter une vraie carte au film démo : toujours aucun seal.
- [ ] Source = fichier isolé (pas un dossier) : pas d'erreur, pas de seal.

### Catalogue (constat 7)
- [ ] Après un run Off : la copie est dans le catalogue mais **non vérifiée**.
- [ ] Après un run Fast complet : copie **vérifiée**.
- [ ] Source son détectée automatiquement (motif Settings › sound auto-detect) : le roll apparaît en **Sound** dans le catalogue, pas en Camera.

### Régression à surveiller
- [ ] Copie normale 2 destinations en Paranoid : barres, vitesse, ETA inchangées.
- [ ] Historique et notifications : ✓/✗ par destination corrects.
- [ ] Rapport PDF généré comme avant.
- [ ] Note : le rapport PDF utilise encore les kinds explicites du film (son auto-détecté en Camera dans le PDF). Connu, non corrigé.

---

## Session 3 : écrasement de fichiers manifestés et collisions de chemins

Prérequis : une carte (ou un dossier) avec 3 clips de plus de 1 Mo, deux disques de destination, politique doublons « Ask » (défaut).

### Carte réutilisée (constat 1)
- [ ] Run 1 complet. Vider la carte dans le Finder **sans formater**, filmer (ou copier) d'autres clips nommés C0001… de **taille différente**. Run 2 : le prompt doublons apparaît, liste les clips concernés. Choisir **Skip** : les anciens clips sont intacts sur les deux disques, la destination passe en échec « conflit », pas de seal.
- [ ] Même scénario, choisir **Overwrite** : les nouveaux clips remplacent les anciens. Le manifest (`ascmhl/`) liste les nouveaux hash.
- [ ] Même scénario, choisir **Add counter** : `C0001_001.MP4` à côté de l'ancien, les deux listés au manifest.
- [ ] Même scénario avec le style de liste « simple » (Options › hash list) : même prompt.
- [ ] Fermer le prompt sans répondre : rien n'est écrasé.
- [ ] Non-régression : tronquer un clip de destination à 0 octet (carte inchangée). Relancer : recopié **sans** prompt.
- [ ] Politique réglée sur **Overwrite** dans les options du film : le run 2 écrase sans prompt (choix explicite de l'utilisateur). Attendu.

### Deux sources, un même chemin (constat 2)
- [ ] « Copy folder contents » activé, deux cartes contenant chacune `DCIM/100MEDIA/C0001.MP4` : le run s'arrête **avant toute copie** avec « Two or more files would be copied to the same place: … ». Rien sur les disques.
- [ ] Deux fichiers isolés de même nom, venant de deux dossiers, dans Quick Copy (s'il est autorisé) ou via la fenêtre principale : bloqué (voir constat 4).
- [ ] Deux cartes en « contents » sans nom commun : copie normale.

### Prompt doublons (constat 3)
- [ ] Trois fichiers déjà présents hors manifest : le prompt indique « 3 files are already at the destination — file 1 of 3 » et liste les trois chemins (le fichier courant en gras).
- [ ] « Apply to … » **désactivé** : Skip sur le 1er, Overwrite sur le 2e, Skip sur le 3e. Seul le 2e est remplacé.
- [ ] « Apply to … » **activé** au 1er fichier : plus de question, le choix vaut pour les trois.
- [ ] « Add counter » avec un style personnalisé (ex. `-v2`) : le style saisi est utilisé.
- [ ] Même vérifications dans une fenêtre Quick Copy.

### Fichiers isolés multiples (constat 4)
- [ ] Fenêtre principale : ajouter deux fichiers isolés comme sources, Run : message « Several loose files can't be copied together yet… », rien n'est lancé.
- [ ] Un fichier isolé + un dossier : le run part.

### Nom de roll saisi (constat 5)
- [ ] Carte « Untitled » : taper `..` comme nom de roll. Le nom est refusé (champ vidé), rien n'est écrit dans le dossier parent de la destination.
- [ ] Taper `../Jour 1` : le nom affiché devient `_Jour 1` (pas de point de tête : pas de dossier caché), un seul dossier sous la destination.
- [ ] Noms accentués (`Bobine é`) : les caractères hors ASCII deviennent `_`, comme dans les modèles de dossiers. Attendu.
- [ ] Préfixes de numérotation (Options › Number rolls) : seules des lettres sont acceptées, `.` et `/` ignorés.

---

## Session 4 : hash lists correctes, conformes ASC MHL, robustes à un manifest abîmé ou étranger

Objectif : une reprise retrouve toujours ce qui est déjà sauvegardé, le dossier `ascmhl/` est accepté par l'outil de référence, et un manifest abîmé ou venu d'un autre outil n'efface ni ne falsifie rien.
Tests automatiques : `HashListIntegrityTests` (13 tests), `ASCMHLConformanceTests` (2 tests, validés par le CLI `ascmhl` sur la CI), `OverwriteSafetyTests` (cas liste simple).

Prérequis : une carte (ou un dossier) avec 3 à 5 clips, deux disques de destination, film réel. Outil de référence : `pipx install ascmhl`.

### Liste « simple » (constat 1)
- [ ] Options › hash list = **simple**. Run 1 complet, puis run 2 sans rien changer : « déjà sauvegardé », aucun clip recopié.
- [ ] Ouvrir `<destination>/.filmcan/hashlists/<roll>.mhl` : chaque ligne porte `name="…"` et `mtime="…"`.
- [ ] Carte réutilisée (voir session 3) en liste simple : le prompt présente le clip comme **modifié depuis la sauvegarde**, pas comme un fichier inconnu.

### Conformité ASC MHL (constat 2)
- [ ] Après un run : dans le manifest, `lastmodificationdate="2026-…T…+00:00"` (date lisible, plus un nombre).
- [ ] `ascmhl diff <dossier du roll>` : code de sortie 0, aucun « new file ».
- [ ] Ajouter un clip à la carte, run 2 : la génération 0002 garde, pour les anciens clips, la `hashdate` de la 0001. Seul le nouveau clip porte la date du jour.
- [ ] Stop en pleine copie, puis relancer jusqu'au bout : `ascmhl/` ne contient que des générations **contiguës** (0001, 0002…), toutes listées dans `ascmhl_chain.xml`. Le manifest partiel du run arrêté a disparu. `ascmhl diff` : code 0.
- [ ] Ancien roll sauvegardé avant cette version (dates en nombre) : la reprise marche, rien n'est recopié.

### Manifest d'un autre outil (constat 3)
- [ ] Roll sauvegardé par un autre outil en **md5** ou **xxh64** (Silverstack, ShotPut…), puis run FilmCan sur la même carte : les clips ne sont **pas** sautés sur la seule foi du md5. Ils sont recopiés ou comparés selon la politique doublons.
- [ ] Dans la nouvelle génération, un fichier que FilmCan n'a pas recopié garde sa balise d'origine (`<md5>`), jamais une valeur md5 sous `<xxh128>`.

### Chaîne ou manifest illisible (constat 4)
- [ ] Remplacer le contenu de `ascmhl_chain.xml` par du texte quelconque, puis run : la copie réussit, la destination affiche l'avertissement « manifest non scellé ». L'ancienne chaîne est conservée telle quelle sous `ascmhl_chain.xml.unreadable-<date>Z`. Aucune nouvelle chaîne qui ne contiendrait que la dernière génération.
- [ ] Texte de l'avertissement lisible dans la carte de destination et dans l'historique.
- [ ] Tronquer le dernier manifest de `ascmhl/` (garder la moitié du fichier), puis run : la reprise s'appuie sur la génération précédente, seuls les clips absents de celle-ci sont recopiés. Le manifest tronqué n'est ni supprimé ni écrasé.

### Régression à surveiller
- [ ] Netflix Ingest, caméra + son : chaque roll a son `ascmhl/` valide (`ascmhl diff` code 0 sur chacun).
- [ ] Réparation depuis une destination sœur (Retry › copier depuis l'autre disque) : la génération écrite porte `action="original"` et la date du jour pour les fichiers réparés.
- [ ] Rapport PDF et recréation de rapport : les checksums affichés sont inchangés.
- [ ] Connu, non corrigé : une entrée `action="failed"` d'un autre outil compte encore pour la reprise ; le rapport, l'archive de rapport et `HashListVerifier` lisent toujours le dernier manifest sans repli.

---

## Session 5 : les fonctions autour du moteur n'annoncent plus un résultat faux

Objectif : réparation, « Verify data », rapport PDF, auto-fix Netflix, annulation et statuts disent ce qui s'est vraiment passé.
Tests automatiques : `HonestOutcomeTests` (15 tests).

Prérequis : deux cartes (ou dossiers) de 3 clips chacune, deux disques de destination, film réel.

### Réparation depuis une autre destination (constat 1)
- [ ] Run à **deux cartes**, une destination en échec (débrancher pendant la copie). Retry › copier depuis l'autre disque : les deux rolls reviennent sur le disque réparé, chacun avec son `ascmhl/`.
- [ ] Supprimer un clip du second roll sur le disque sain avant la réparation : la réparation échoue, la destination reste rouge.
- [ ] Un clip réparé est relu depuis le disque : la réparation est plus longue qu'avant (deux lectures). Attendu.

### Réparation depuis la source (constat 2)
- [ ] Film Netflix (épisode, jour, unité remplis), une destination en échec. Retry › depuis la source : les clips arrivent dans le **même** dossier `<date>_<épisode>_<jour>_<unité>/Camera_Media/…` que sur le disque sain, pas dans un dossier aux champs vides.
- [ ] Connu : si minuit passe entre la sauvegarde et la réparation, `{date}` change de jour (non corrigé).

### Verify data (constat 3)
- [ ] Numérotation automatique activée (A001…). Run complet, puis relancer : popup « déjà sauvegardé ». **Verify data** : le nombre de fichiers vérifiés est celui de la carte, pas 0.
- [ ] Même chose avec une carte « Untitled » (nom générique `Untitled_NN`).

### Rapport PDF (constat 4)
- [ ] Désactiver le log, activer le rapport : un PDF est écrit à l'endroit où le log serait allé (destination, ou `Reports/` en Netflix).
- [ ] En-tête : « Verified ✓ — N verified this run · M from an earlier backup » quand tout est prouvé. Chaque clip porte « xxh128: … · Verified this run » ou « From an earlier backup ».
- [ ] Run en Vérification **Off** : en-tête « Not everything is verified », clips « Copied, not verified », **aucun** checksum affiché.
- [ ] Modifier la taille d'un clip sur la destination puis générer un rapport (relancer avec un nouveau clip) : ce clip n'a pas de checksum, note « Size changed since the backup ».
- [ ] Rapport d'une centaine de clips : la fenêtre reste fluide pendant la génération.

### Auto-fix Netflix (constat 5)
- [ ] Film Netflix, carte nommée `A#01` : la fenêtre de validation propose Auto-fix. Après Auto-fix : la carte s'appelle **toujours** `A#01` dans le Finder, le roll s'appelle `A_01` sur les destinations.
- [ ] Deux cartes qui donnent le même nom corrigé : la seconde devient `…_001` sur les destinations.
- [ ] Avec la numérotation automatique : le nom numéroté gagne, l'auto-fix ne change rien.

### Annulation en mode séquentiel (constat 6)
- [ ] Mode de copie **Sequential**, trois destinations. Pendant la copie de la première, Stop sur la troisième (en attente) : elle n'est jamais copiée, sa carte passe en « Cancelled by user ». La deuxième est copiée normalement.
- [ ] Stop sur la destination **en cours** : seule elle s'arrête, la suivante démarre.

### Option « Copy order » (constat 7)
- [ ] Options › Basic : la ligne « Copy order » a disparu. Un film qui l'avait réglée s'ouvre sans erreur.

### Statuts (constat 8)
- [ ] Paranoid, gros clip : Stop pendant « Verifying… ». La carte et l'historique disent « Cancelled by user », jamais « Verification mismatch ».
- [ ] Une carte rouge pendant la copie ne redevient jamais bleue/active avant la fin du run.

### Régression à surveiller
- [ ] Copie normale 2 destinations, Fast puis Paranoid : barres, statuts, historique inchangés.
- [ ] Quick Copy : copie, vérification et rapport (si le film l'a activé) comme avant.
- [ ] Connu, non corrigé : un clip déjà renommé en place mais pas encore vérifié au moment du Stop reste sur le disque hors manifest ; le run suivant le présente comme un fichier inconnu (prompt doublons).
