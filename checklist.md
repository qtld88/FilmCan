# Checklist de test manuel — sessions d'audit (main @ c2faaad)

Une section par session. Chaque session ajoute ou met à jour **sa propre section** sans toucher aux autres.
Build à tester (sans toucher à `/Applications`, quitter les autres FilmCan avant) :

```
xcodebuild build -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -configuration Debug \
  -destination platform=macOS -derivedDataPath FilmCan/build/qc
open FilmCan/build/qc/Build/Products/Debug/FilmCan.app
```

Matériel conseillé : une carte (ou clé USB) source avec quelques clips de plus de 100 Mo, deux disques de destination.

---

## Session « fichiers incomplets / vérification impossible »

Objectif : un fichier n'arrive jamais sous son nom final s'il est incomplet, et une vérification impossible est un échec, jamais un succès.
Branche : `claude/loving-keller-oz6r0h`, fusionnée dans `main`. Tests automatiques : `FanOutCopierReadFailureTests` (6 tests). Workflow macOS vert (run 61).

- [ ] **Source arrachée en pleine copie** (Paranoid, 2 destinations). Débrancher la carte pendant la copie d'un gros clip.
  - [ ] Les deux cartes de destination passent en rouge, avec un message « Source read failed for … ».
  - [ ] Dans le Finder, aucune destination ne contient le clip en cours sous son nom final (pas de fichier tronqué).
  - [ ] Aucun fichier `.filmcan-*` ne reste (`ls -la` dans le dossier du rouleau).
  - [ ] L'app ne plante pas ; l'historique montre un résultat **par destination** (pas un échec global sans détail).
  - [ ] Le dossier `ascmhl/` contient un manifest pour les clips déjà vérifiés.
- [ ] **Reprise après l'arrachage.** Rebrancher la carte et relancer le même film.
  - [ ] Seuls les clips manquants sont copiés ; la copie se termine en vert sur les deux disques.
  - [ ] Le rouleau est scellé (`ascmhl_chain.xml` à jour) ; le hash de chaque clip correspond (`ascmhl verify` si installé).
- [ ] **Copie normale, non-régression** (Fast puis Paranoid). Une carte complète vers 2 disques.
  - [ ] Tout passe en vert, 100 % sur les deux barres ; aucun « Incomplete file » dans les erreurs.
- [ ] **Source = un fichier seul** (Quick Copy, un seul clip choisi dans le Finder).
  - [ ] Copie et vérification en vert (contrôle du nouveau test de taille sur un source non dossier).
- [ ] **Doublon conservé par Skip** (non-régression, difficile à provoquer à la main) : placer à la main un fichier du même nom au chemin cible, politique « Skip », copier.
  - [ ] Le fichier préexistant est intact après la copie.

Risque connu à surveiller : si un source est choisi via un **lien symbolique** (fichier seul), le contrôle de taille peut refuser la copie (« Incomplete file: … bytes written, … expected »). Le noter si ça arrive.

---

<!-- Autres sessions : ajouter votre section ci-dessous. -->
