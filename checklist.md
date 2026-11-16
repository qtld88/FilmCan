# Checklist de test manuel : sessions d'audit

Une section par session. Chaque session ajoute et coche la sienne. Cocher = testé à la main sur un vrai Mac avec de vrais disques.
Les tests automatiques (workflow `macOS tests`) ne remplacent pas cette liste.

Statut des sessions : 1 = finalisation des fichiers (à compléter par son auteur) · 2 = preuve de vérification et seal (fusionnée) · 3 = écrasement et collisions (à compléter).

---

## Session 1 : finalisation des fichiers
_À remplir par la session 1._

- [ ] …

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
