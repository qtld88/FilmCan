# Checklist de test manuel : sessions d'audit

Une section par session. Chaque session ajoute et coche la sienne. Cocher = testé à la main sur un vrai Mac avec de vrais disques.
Les tests automatiques (workflow `macOS tests`) ne remplacent pas cette liste.

Build à tester sans toucher à `/Applications` (quitter les autres FilmCan avant) :

```
xcodebuild build -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -configuration Debug \
  -destination platform=macOS -derivedDataPath FilmCan/build/qc
open FilmCan/build/qc/Build/Products/Debug/FilmCan.app
```

Statut des sessions : 1 = finalisation des fichiers (fusionnée) · 2 = preuve de vérification et seal (fusionnée) · 3 = écrasement et collisions (à compléter).

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
_À remplir par la session 3._

- [ ] …
