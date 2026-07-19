<!-- lang:en -->
# Copy Engine

FilmCan copies with one purpose-built engine: the **FilmCan Engine**, a fan-out
copier designed for cinema rushes: read the source once, write to every
destination at once, verify with cinema-grade hash lists, and recover a failed
drive with one click.

---

## How it works

1. **Read source once.** A single read pass pulls each file straight off the
   card, bypassing the Mac's memory cache, so a huge offload doesn't fill up
   your RAM with cached data.
2. **Broadcast to every destination at once.** One bounded channel feeds a
   writer task per drive. The slowest drive sets the pace; faster drives idle
   briefly. Destination writes bypass the memory cache too, so a
   multi-hundred-GB copy stays memory-bounded.
3. **Honest writes.** On exFAT, external, and USB drives, FilmCan forces the
   drive's own cache to flush to the physical media before marking a file
   done, so "copy finished" means the bytes are actually on the drive, not
   just queued in a buffer. Internal drives use the Mac's normal, faster save
   method, since they don't have this problem.
4. **Atomic finalize.** Each file is written to a hidden temp file first, then
   swapped into its final name only once it's complete, so you never see a
   half-written file at the destination.
5. **Verify** (see modes below), overlapping the copy of the next file.
6. **MHL per source root.** One sealed ASC-format `.mhl` per source root,
   aggregating every file in that tree, at `<dest>/.filmcan/hashlists/<root>.mhl`.

### Verify pipeline

Verification runs on its own lane **while the next file is still copying**, so a
paranoid re-read no longer roughly doubles the wall time. It mostly hides behind
the copy. Only the last file's verify tail runs alone (shown as "Verifying…").

---

## Verification modes

Pick in **Backup Editor → Options → Verification**.

| Mode | Catches | Cost |
|---|---|---|
| **Off** | nothing | fastest, no hashing or checking |
| **Fast** *(default for new projects)* | RAM bit-flips, PCI/USB corruption, partial writes, via the hash computed during the copy | none beyond the copy; no re-read |
| **Paranoid** | all of Fast **+** drive-firmware silent corruption, OS-cache lies, bit rot at rest, re-reads every destination (and the source) from disk and re-hashes | extra disk I/O, mostly overlapped with copying |

---

## Resume: re-running skips what's already there

Re-running a backup (including after **Stop**) does **not** recopy files that are
already done. A file is skipped when it is recorded in **every** destination's
hash list **and** still present on disk there. Only the remaining files are
copied; the progress row reads *"Resuming: N already backed up, copying the
rest."*

- If the whole backup is already present, no history card is added. An **Already
  backed up** popup appears instead, with a **Verify data** button (the same
  hash-list check as History's *Check data*).
- A file deleted from a destination is re-copied (presence is checked, not just
  the hash list).
- **Force re-copy** (Options) disables resume skip and re-copies everything.
- Caveat: with a `{date}` folder template, resuming on a *different day* re-copies
  into that day's folder (earlier files aren't matched).

---

## Directory sources

Drop a mounted card (e.g. `/Volumes/A001_C002`) or any folder. FilmCan walks the
tree, mirrors the layout under each destination, and aggregates one MHL per
source root. Hidden macOS junk (`.Spotlight-V100`, `.fseventsd`, `.DS_Store`,
`.Trashes`) is skipped automatically.

---

## Failed drives, one-click repair

When a drive fails mid-copy or fails verify, a **Retry** button appears on its
row, opening the repair sheet:

- **From source**, re-runs the engine for that single drive, pulling from the
  original source(s) if still mounted.
- **From sibling**, reads files from a verified neighbor drive's MHL, copies
  them to the failed drive, and hash-verifies each. The source card no longer
  needs to be mounted. Cinema-set workflow: keep going, fix the drive at lunch.

**From sibling** enables only when at least one other destination from the same
job succeeded.

---

## Performance & memory

- **Memory-bounded.** Source reads and destination writes bypass the Mac's
  memory cache, and the paranoid re-read releases memory as it goes chunk by
  chunk. In-flight memory is just a small per-destination buffer, capped
  between 32 MB and 96 MB depending on how much RAM the Mac has.
- **Multi-source concurrency** is capped to the number of distinct source
  physical drives, three clips from one card copy sequentially (no
  head-thrashing); card-A and card-B copy in parallel.
- **Chunk size** is chosen from the slowest destination's bus, 4 MB on slow
  buses, up to 16 MB on Thunderbolt / internal.
- **Live speed & ETA** use a moving average of recent combined (copy + verify)
  throughput, so the estimate is stable and honest from the first few seconds.

---

## Related

- [Multi-Destination Backups](./multi-destination.md)
- [Hash Lists](./hash-lists.md)
- [Options](./options.md)
- [Stop](./stop.md)

<!-- lang:fr -->
# Moteur de copie

FilmCan copie avec un moteur spécialisé : le **FilmCan Engine**, un copieur en fan-out
conçu pour les rushes de cinéma : lire la source une fois, écrire à chaque
destination à la fois, vérifier avec des listes de hachage de qualité cinéma, et récupérer un disque défaillant
en un clic.

---

## Comment ça marche

1. **Lire la source une fois.** Une seule lecture tire chaque fichier directement de la
   carte, en contournant le cache mémoire du Mac, donc un grand déchargement ne remplit pas
   votre RAM avec des données en cache.
2. **Diffuser à chaque destination à la fois.** Un canal limité alimente un
   tâche d'écriture par disque. Le disque le plus lent définit le rythme; les disques plus rapides sont
   brièvement oisifs. Les écritures destination contournent également le cache mémoire, donc un
   copie multi-centaines de Go reste délimitée en mémoire.
3. **Écritures honnêtes.** Sur exFAT, les disques externes et USB, FilmCan force le
   cache propre du disque pour être vidé sur le support physique avant de marquer un fichier
   terminé, donc « copie terminée » signifie que les octets sont réellement sur le disque, pas
   juste en queue d'attente dans un tampon. Les disques internes utilisent la méthode d'enregistrement normale et plus rapide du Mac,
   car ils n'ont pas ce problème.
4. **Finalisation atomique.** Chaque fichier est d'abord écrit dans un fichier temporaire caché, puis
   échangé en son nom final seulement une fois qu'il est complètement écrit, vous ne voyez donc jamais un
   fichier à moitié écrit à la destination.
5. **Vérification** (voir les modes ci-dessous), se chevauchant avec la copie du fichier suivant.
6. **MHL par racine source.** Un `.mhl` au format ASC scellé par racine source,
   agrégant chaque fichier dans cet arborescence, à `<dest>/.filmcan/hashlists/<root>.mhl`.

### Pipeline de vérification

La vérification s'exécute sur sa propre voie **tandis que le fichier suivant est toujours en cours de copie**, donc un
re-lecture paranoïaque ne double plus à peu près le temps réel. Elle se cache principalement derrière
la copie. Seule la queue de vérification du dernier fichier s'exécute seule (affichée comme « Vérification en cours… »).

---

## Modes de vérification

Choisissez dans **Backup Editor → Options → Verification**.

| Mode | Détecte | Coût |
|---|---|---|
| **Off** | rien | plus rapide, aucun hachage ou vérification |
| **Fast** *(par défaut pour les nouveaux projets)* | Bit-flips RAM, corruption PCI/USB, écritures partielles, via le hachage calculé pendant la copie | aucun au-delà de la copie; pas de relecture |
| **Paranoid** | tout de Fast **+** corruption silencieuse du microprogramme de disque, mensonges du cache OS, décomposition au repos, relit chaque destination (et la source) à partir du disque et rehache | I/O disque supplémentaire, principalement chevauchée avec la copie |

---

## Reprise : réexécution ignore ce qui existe déjà

Réexécuter une sauvegarde (y compris après **Stop**) ne recopie **pas** les fichiers qui sont
déjà terminés. Un fichier est ignoré lorsqu'il est enregistré dans la liste de hachage **de chaque** destination
**et** est toujours présent sur le disque. Seuls les fichiers restants sont
copiés; la ligne de progression indique *« Reprise : N déjà sauvegardés, copie du
reste. »*

- Si la sauvegarde complète est déjà présente, aucune carte d'historique n'est ajoutée. Un popup
  **Déjà sauvegardé** apparaît à la place, avec un bouton **Verify data** (le même
  vérification de liste de hachage que *Check data* de l'historique).
- Un fichier supprimé d'une destination est recopié (la présence est vérifiée, pas seulement
  la liste de hachage).
- **Force re-copy** (Options) désactive la reprise du saut et recopie tout.
- Attention : avec un modèle de dossier `{date}`, la reprise sur un *jour différent* recopie
  dans le dossier de ce jour (les fichiers antérieurs ne sont pas mis en correspondance).

---

## Sources de répertoire

Déposez une carte montée (par ex. `/Volumes/A001_C002`) ou n'importe quel dossier. FilmCan parcourt l'arborescence,
reflète la disposition sous chaque destination et agrège un MHL par
racine source. Les fichiers cachés macOS (`.Spotlight-V100`, `.fseventsd`, `.DS_Store`,
`.Trashes`) sont ignorés automatiquement.

---

## Disques défaillants, réparation en un clic

Quand un disque tombe en panne à mi-copie ou échoue la vérification, un bouton **Retry** apparaît sur sa
ligne, ouvrant la feuille de réparation :

- **From source**, réexécute le moteur pour ce seul disque, en tirant de la
  source(s) d'origine si toujours montée(s).
- **From sibling**, lit les fichiers du MHL d'un disque voisin vérifié, les copie
  vers le disque défaillant et vérifie chaque fichier. La carte source n'a plus
  besoin d'être montée. Flux de travail d'ensemble de cinéma : continuer, réparer le disque à midi.

**From sibling** s'active uniquement lorsqu'au moins un autre destination du même
travail a réussi.

---

## Performance et mémoire

- **Délimitée en mémoire.** Les lectures source et les écritures destination contournent le
  cache mémoire du Mac, et la relecture paranoïaque libère la mémoire au fur et à mesure,
  morceau par morceau. La mémoire en vol est juste un petit tampon par destination, plafonné
  entre 32 Mo et 96 Mo selon la quantité de RAM du Mac.
- **La concurrence multi-source** est plafonnée au nombre de disques sources physiques distincts,
  trois clips d'une carte copient séquentiellement (sans secousse de tête); la carte A et la carte B copient en parallèle.
- **La taille du bloc** est choisie à partir du bus de la destination la plus lente, 4 Mo sur les
  buses lentes, jusqu'à 16 Mo sur Thunderbolt/interne.
- **La vitesse et l'ETA en direct** utilisent une moyenne mobile du débit combiné récent (copie + vérification),
  l'estimation est donc stable et honnête dès les premières secondes.

---

## Liens

- [Multi-Destination Backups](./multi-destination.md)
- [Hash Lists](./hash-lists.md)
- [Options](./options.md)
- [Stop](./stop.md)

<!-- lang:de -->
# Kopier-Engine

FilmCan kopiert mit einem speziell entwickelten Engine : der **FilmCan Engine**, einem Fan-out-
Kopier entworfen für Kino-Rushes : Quelle einmal lesen, auf jedes
Ziel gleichzeitig schreiben, mit Kino-Grade Hash-Listen verifizieren und einen fehlerhaften Datenträger
mit einem Klick wiederherstellen.

---

## Wie es funktioniert

1. **Quelle einmal lesen.** Ein einzelner Lesedurchgang zieht jede Datei direkt von der
   Karte, wobei der Memory-Cache des Mac umgangen wird, damit eine große Offload nicht
   Ihren RAM mit zwischengespeicherten Daten füllt.
2. **An jedes Ziel gleichzeitig senden.** Ein begrenzter Kanal speist einen
   Schreiber-Task pro Laufwerk. Das langsamste Laufwerk setzt das Tempo; schnellere Laufwerke sind
   kurz untätig. Zielschreiben umgehen auch den Memory-Cache, daher ein
   Kopieren von über hundert GB bleibt speicherbegrenzt.
3. **Ehrliche Schreiben.** Auf exFAT-, externen und USB-Laufwerken erzwingt FilmCan
   den Eign-Cache des Laufwerks, um vor dem Markieren einer Datei
   auf das physische Medium zu leeren abgeschlossen, also « Copy beendet » bedeutet die Bytes sind tatsächlich auf dem Laufwerk, nicht
   nur in einem Puffer in der Warteschlange. Interne Laufwerke verwenden die normale, schnellere Speichermethode des Mac,
   da sie dieses Problem nicht haben.
4. **Atomare Fertigstellung.** Jede Datei wird zunächst in eine verborgene temporäre Datei geschrieben, dann
   nur einmal es ist vollständig in seinen endgültigen Namen ausgetauscht, Sie sehen also nie ein
   halb geschriebene Datei am Ziel.
5. **Verifizieren** (siehe Modi unten), während die nächste Datei kopiert wird.
6. **MHL pro Quellwurzel.** Ein versiegeltes ASC-Format `.mhl` pro Quellwurzel,
   aggregiert jede Datei in diesem Baum, bei `<dest>/.filmcan/hashlists/<root>.mhl`.

### Verifizierungs-Pipeline

Die Verifizierung läuft auf ihrer eigenen Spur **während die nächste Datei noch kopiert wird**, daher a
Paranoid-Neulesevorgänge verdoppeln nicht mehr die Wandzeit. Sie versteckt sich größtenteils hinter
die Kopie. Nur der Verifizierungsschwanz der letzten Datei wird alleine ausgeführt (angezeigt als « Verifizieren… »).

---

## Verifizierungsmodi

Wählen Sie in **Backup Editor → Options → Verification**.

| Modus | Erfasst | Kosten |
|---|---|---|
| **Off** | nichts | am schnellsten, kein Hashing oder Überprüfung |
| **Fast** *(Standard für neue Projekte)* | RAM-Bitflips, PCI/USB-Beschädigungen, Teilschreiben, über den während der Kopie berechneten Hash | nichts über die Kopie hinaus; keine Neulesevorgänge |
| **Paranoid** | alles von Fast **+** stille Laufwerk-Firmware-Beschädigungen, OS-Cache-Lügen, Bitfäulnis im Ruhezustand, liest jedes Ziel (und die Quelle) von der Festplatte neu und hasht erneut | zusätzliche Festplatte I/O, größtenteils mit dem Kopieren überlappt |

---

## Fortsetzen : Neuausführung überspringt, was bereits vorhanden ist

Eine Sicherung erneut auszuführen (einschließlich nach **Stop**) kopiert **keine** Dateien, die
bereits abgeschlossen sind. Eine Datei wird übersprungen, wenn sie in der Hash-Liste **aller** Ziele
aufgezeichnet ist **und** immer noch auf der Festplatte dort vorhanden ist. Nur die verbleibenden Dateien werden
kopiert; die Fortschrittszeile zeigt *« Fortsetzen: N bereits gesichert, Kopieren der
Rest. »*

- Wenn die gesamte Sicherung bereits vorhanden ist, wird keine Verlaufskarte hinzugefügt. Ein **Bereits
  gesichert** Popup erscheint stattdessen mit einem **Verify data**-Button (die gleiche
  Hash-Listen-Überprüfung wie *Check data* des Verlaufs).
- Eine Datei, die von einem Ziel gelöscht wird, wird neu kopiert (Präsenz wird überprüft, nicht nur
  die Hash-Liste).
- **Force re-copy** (Optionen) deaktiviert die Fortsetzen-Übersprung und kopiert alles erneut.
- Vorbehalt: Bei einer Ordnervorlage `{date}` führt die Fortsetzung an einem *anderen Tag* zu einer Neukopie
  in das Verzeichnis dieses Tages (frühere Dateien werden nicht abgeglichen).

---

## Verzeichnisquellen

Legen Sie eine bereitgestellte Karte ab (z. B. `/Volumes/A001_C002`) oder einen beliebigen Ordner. FilmCan durchsucht den Baum,
spiegelt das Layout unter jedem Ziel und aggregiert ein MHL pro
Quellwurzel. Versteckte macOS-Dateien (`.Spotlight-V100`, `.fseventsd`, `.DS_Store`,
`.Trashes`) werden automatisch übersprungen.

---

## Fehlerhafte Laufwerke, Reparatur mit einem Klick

Wenn ein Laufwerk während der Kopie ausfällt oder die Verifizierung fehlschlägt, wird ein **Retry**-Button auf seiner
Zeile angezeigt, das Reparaturblatt wird geöffnet:

- **From source**, führt das Engine für dieses einzelne Laufwerk erneut aus und zieht von der
  ursprünglichen Quelle(n), falls noch bereitgestellt.
- **From sibling**, liest Dateien aus dem MHL eines verifizierten Nachbar-Laufwerks, kopiert sie
  auf das fehlerhafte Laufwerk und verifiziert jede. Die Quellkarte muss nicht mehr
  bereitgestellt werden. Kino-Set-Workflow: Weitermachen, Laufwerk zur Mittagszeit reparieren.

**From sibling** wird nur aktiviert, wenn mindestens ein anderes Ziel aus demselben
Auftrag erfolgreich war.

---

## Leistung und Speicher

- **Speicherbegrenzt.** Quelllesevorgänge und Zielschreiben umgehen den
  Memory-Cache des Mac, und die Paranoid-Neulesevorgänge geben Speicher frei, während er
  Stück für Stück abläuft. In-Flight-Speicher ist nur ein kleiner pro-Ziel-Puffer, begrenzt
  zwischen 32 MB und 96 MB, je nachdem wie viel RAM der Mac hat.
- **Multi-Source-Parallelität** ist auf die Anzahl unterschiedlicher Quell-
  physischer Laufwerke begrenzt, drei Clips von einer Karte kopieren sequenziell (kein
  Kopfwackeln); Karte A und Karte B kopieren parallel.
- **Blockgröße** wird aus dem langsamsten Zielbus gewählt, 4 MB auf langsamen
  Bussen, bis zu 16 MB auf Thunderbolt/intern.
- **Live-Geschwindigkeit und ETA** verwenden einen gleitenden Durchschnitt des kombiniertes Durchsatzes (Kopieren + Verifizierung), daher
  die Schätzung ist vom ersten Moment an stabil und ehrlich.

---

## Links

- [Multi-Destination Backups](./multi-destination.md)
- [Hash Lists](./hash-lists.md)
- [Options](./options.md)
- [Stop](./stop.md)

<!-- lang:es -->
# Motor de copia

FilmCan copia con un motor especialmente diseñado: el **FilmCan Engine**, un copiador en fan-out
diseñado para rushes de cine: leer el origen una vez, escribir en cada
destino a la vez, verificar con listas de hash de calidad de cine, y recuperar un disco defectuoso
con un clic.

---

## Cómo funciona

1. **Leer el origen una vez.** Un único paso de lectura extrae cada archivo directamente de la
   tarjeta, evitando el caché de memoria del Mac, por lo que una descarga grande no llena
   su RAM con datos almacenados en caché.
2. **Transmitir a cada destino a la vez.** Un canal acotado alimenta un
   tarea de escritor por unidad. La unidad más lenta marca el ritmo; las unidades más rápidas están
   brevemente inactivas. Las escrituras de destino también evitan el caché de memoria, por lo que un
   copia de cientos de GB se mantiene limitada en memoria.
3. **Escrituras honestas.** En unidades exFAT, externas y USB, FilmCan obliga a
   caché propia de la unidad para vaciarse en el medio físico antes de marcar un archivo
   como completado, así « copiar finalizado » significa que los bytes están realmente en la unidad, no
   solo en cola en un búfer. Las unidades internas usan el método de guardado normal y más rápido del Mac,
   ya que no tienen este problema.
4. **Finalización atómica.** Cada archivo se escribe primero en un archivo temporal oculto, luego
   se cambia a su nombre final solo cuando está completamente escrito, nunca verá un
   archivo a medio escribir en el destino.
5. **Verificación** (ver modos a continuación), superpuesto con la copia del siguiente archivo.
6. **MHL por origen raíz.** Un `.mhl` de formato ASC sellado por origen raíz,
   agregando cada archivo en ese árbol, en `<dest>/.filmcan/hashlists/<root>.mhl`.

### Canalización de verificación

La verificación se ejecuta en su propio carril **mientras el siguiente archivo aún se está copiando**, por lo que un
releer paranoico ya no duplica aproximadamente el tiempo de pared. Se oculta principalmente detrás
la copia. Solo la cola de verificación del último archivo se ejecuta sola (se muestra como « Verificando… »).

---

## Modos de verificación

Elija en **Backup Editor → Options → Verification**.

| Modo | Detecta | Costo |
|---|---|---|
| **Off** | nada | más rápido, sin hash o verificación |
| **Fast** *(predeterminado para nuevos proyectos)* | Cambios de bits de RAM, corrupción PCI/USB, escrituras parciales, a través del hash calculado durante la copia | nada más allá de la copia; sin relectura |
| **Paranoid** | todo de Fast **+** corrupción silenciosa del firmware de la unidad, mentiras del caché del SO, pudrición de bits en reposo, relee cada destino (y el origen) desde el disco y rehace hash | I/O de disco adicional, principalmente superpuesto con copia |

---

## Reanudación: la re-ejecución omite lo que ya está ahí

Volver a ejecutar una copia de seguridad (incluida después de **Stop**) **no** recopian archivos que son
ya se hizo. Un archivo se omite cuando se registra en la lista de hash **de cada** destino
**y** aún está presente en el disco allí. Solo se copian los archivos restantes;
la fila de progreso dice *« Reanudación: N ya respaldados, copiando el
resto. »*

- Si la copia de seguridad completa ya está presente, no se añade ninguna tarjeta de historial. Un **Ya
  respaldado** popup aparece en su lugar, con un botón **Verify data** (la misma
  verificación de lista de hash que *Check data* del historial).
- Un archivo eliminado de un destino se recopian (se comprueba la presencia, no solo
  la lista de hash).
- **Force re-copy** (Opciones) deshabilita la omisión de reanudación y recopian todo.
- Advertencia: con una plantilla de carpeta `{date}`, reanudar en un *día diferente* recopian
  en la carpeta de ese día (los archivos anteriores no coinciden).

---

## Orígenes de directorio

Suelte una tarjeta montada (por ejemplo, `/Volumes/A001_C002`) o cualquier carpeta. FilmCan recorre el árbol,
refleja el diseño bajo cada destino y agrega un MHL por
origen raíz. Los archivos ocultos de macOS (`.Spotlight-V100`, `.fseventsd`, `.DS_Store`,
`.Trashes`) se omiten automáticamente.

---

## Discos defectuosos, reparación con un clic

Cuando un disco falla a mitad de la copia o falla en la verificación, un botón **Retry** aparece en su
fila, abriendo la hoja de reparación:

- **From source**, re-ejecuta el motor para ese único disco, extrayendo de la
  fuente(s) original(es) si aún está montada(s).
- **From sibling**, lee archivos del MHL de un disco vecino verificado, los copia
  al disco fallido y verifica hash a cada uno. Ya no es necesario montar la tarjeta de origen.
  Flujo de trabajo de conjunto de cine: continuar, reparar el disco al mediodía.

**From sibling** se habilita solo cuando al menos otro destino del mismo
trabajo tuvo éxito.

---

## Rendimiento y memoria

- **Limitado en memoria.** Las lecturas de origen y las escrituras de destino evitan el
  caché de memoria del Mac, y la relectura paranoica libera memoria a medida que avanza,
  fragmento por fragmento. La memoria en vuelo es solo un pequeño búfer por destino, limitado
  entre 32 MB y 96 MB según la cantidad de RAM que tenga la Mac.
- **La concurrencia multi-origen** se limita al número de origen físico distinto
  unidades, tres clips de una tarjeta se copian secuencialmente (sin
  trashing de cabeza); la tarjeta A y la tarjeta B se copian en paralelo.
- **El tamaño del fragmento** se elige desde el bus de destino más lento, 4 MB en
  buses lentos, hasta 16 MB en Thunderbolt/interno.
- **La velocidad en vivo y ETA** utilizan un promedio móvil del rendimiento combinado reciente (copia + verificación),
  por lo que la estimación es estable y honesta desde los primeros segundos.

---

## Relacionado

- [Multi-Destination Backups](./multi-destination.md)
- [Hash Lists](./hash-lists.md)
- [Options](./options.md)
- [Stop](./stop.md)
