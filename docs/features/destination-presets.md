<!-- lang:en -->
# Starting a movie from another

A movie is the only kind of settings. There are no presets: to reuse settings, start a new movie from an old one, from the built-in Netflix Ingest model, or from a settings file. A new movie always gets its own copy; changing one movie never changes another.

---

## The "+" button

Click **+** in the tab bar (or **File › New Backup**, ⌘N). A small window asks what to start from:

- **Blank movie**: the usual first-run settings.
- **Netflix Ingest**: a blank movie with the Netflix Ingest folder settings (`Reports` log folder included).
- **Like ‹movie›**, newest first: copies that movie's settings only. Never its shoot: roll numbering, day, episode, history, catalog, sealed cards, card names, drives. Unit and camera format are kept.
- **From a settings file…**: opens a `.filmcan-movie` file and creates a new movie from it.

Closing the window creates nothing.

## Settings files

**Export Settings…** (right-click a movie tab, or the top of the movie settings) saves `‹Movie name›.filmcan-movie`. Importing it always creates a new movie (a name already taken becomes "‹name› 2"), never overwrites one. A file from a newer FilmCan version that this one cannot read is refused with a message. Old preset files are no longer opened: *Presets no longer exist. Create a movie and export its settings instead.*

## Netflix Ingest on an existing movie

In **Options › Destinations**, **Use Netflix Ingest folders** replaces the movie's folder and naming settings after a confirmation. The switch next to it turns folder organization off (the settings are kept aside) and back on.

---

## Folder and file templates

Organize files with folder structures, renaming, and duplicate handling.

---

## Example

```
Folder: {date}/{source}/
Rename: {source}_{counter}{ext}
Duplicates: Add counter
```

Result:
```
20260315/A001/
  A001_001.R3D
  A001_002.R3D
```

---

## Variables

**Source / Destination**  
`{source}`, original source name (file or folder)  
`{sourceParent}`, parent folder name of the source  
`{sourceDriveName}`, drive containing the source  
`{destinationDriveName}`, drive containing the destination  
`{destination}`, destination folder name

**Dates / Time**  
`{date}`, `YYYYMMDD`  
`{time}`, `HHmmss`  
`{datetime}`, `YYYYMMDD-HHmmss`  
`{filecreationdate}`, file creation date (`YYYYMMDD`)  
`{filemodifieddate}`, file modified date (`YYYYMMDD`)

**File Info**  
`{filename}`, source filename without extension  
`{ext}`, file extension (includes the dot)

**Counter**  
`{counter}`, incrementing counter (`001`, `002`, `003`…)

---

## Duplicate Handling

| Option | Behavior |
|--------|----------|
| **Skip** | Keep existing file |
| **Overwrite** | Replace existing file |
| **Add counter** | Add suffix like `_001` |
| **Verify using hash list** | Compare to existing hash list before writing |
| **Ask** | Prompt every time |

**Note:** Hash lists are created only when **Hash verification** is enabled (FilmCan Engine) or when rsync verification is enabled.

---

## Custom Day Boundary

Shooting past midnight? Use [Smart Date](./smart-date.md) to set a custom day start.

---

## Related

- [Smart Date](./smart-date.md)
- [Options](./options.md)

<!-- lang:fr -->
# Démarrer un film à partir d'un autre

Un film est le seul type de réglages. Il n'y a plus de présets : pour réutiliser des réglages, créez un film à partir d'un ancien, du modèle Netflix Ingest intégré, ou d'un fichier de réglages. Un nouveau film reçoit toujours sa propre copie ; modifier un film ne change jamais un autre.

---

## Le bouton « + »

Cliquez sur **+** (ou **Fichier › New Backup**, ⌘N). Une petite fenêtre demande à partir de quoi :

- **Blank movie** : les réglages habituels du premier lancement.
- **Netflix Ingest** : un film vierge avec les réglages de dossiers Netflix Ingest (dossier de journal `Reports` compris).
- **Like ‹film›**, le plus récent d'abord : copie les réglages seulement, jamais le tournage (numérotation des rolls, jour, épisode, historique, catalogue, cartes scellées, noms de cartes, disques). Unité et format caméra sont gardés.
- **From a settings file…** : ouvre un fichier `.filmcan-movie`.

Fermer la fenêtre ne crée rien.

## Fichiers de réglages

**Export Settings…** (clic droit sur l'onglet d'un film, ou en haut des réglages du film) enregistre `‹Nom du film›.filmcan-movie`. L'import crée toujours un nouveau film (« ‹nom› 2 » si le nom est pris), sans jamais écraser. Les anciens fichiers de présets ne s'ouvrent plus : *Presets no longer exist. Create a movie and export its settings instead.*

## Netflix Ingest sur un film existant

Dans **Options › Destinations**, **Use Netflix Ingest folders** remplace les réglages de dossiers et de noms du film après confirmation. L'interrupteur voisin désactive l'organisation des dossiers (les réglages sont gardés de côté) et la réactive.

---

## Modèles de dossiers et de fichiers

Organisez les fichiers avec des structures de dossiers, renommage et gestion des doublons.

---

## Exemple

```
Folder: {date}/{source}/
Rename: {source}_{counter}{ext}
Duplicates: Add counter
```

Résultat:
```
20260315/A001/
  A001_001.R3D
  A001_002.R3D
```

---

## Variables

**Source / Destination**  
`{source}`, nom d'origine original (fichier ou dossier)  
`{sourceParent}`, nom du dossier parent de la source  
`{sourceDriveName}`, disque contenant la source  
`{destinationDriveName}`, disque contenant la destination  
`{destination}`, nom du dossier de destination

**Dates / Heure**  
`{date}`, `YYYYMMDD`  
`{time}`, `HHmmss`  
`{datetime}`, `YYYYMMDD-HHmmss`  
`{filecreationdate}`, date de création du fichier (`YYYYMMDD`)  
`{filemodifieddate}`, date de modification du fichier (`YYYYMMDD`)

**Infos fichier**  
`{filename}`, nom du fichier source sans extension  
`{ext}`, extension du fichier (inclut le point)

**Compteur**  
`{counter}`, compteur croissant (`001`, `002`, `003`…)

---

## Gestion des doublons

| Option | Comportement |
|--------|----------|
| **Skip** | Garder le fichier existant |
| **Overwrite** | Remplacer le fichier existant |
| **Add counter** | Ajouter un suffixe comme `_001` |
| **Verify using hash list** | Comparer à la liste de hash existante avant d'écrire |
| **Ask** | Demander à chaque fois |

**Note:** Les listes de hash sont créées seulement quand **Hash verification** est activée (FilmCan Engine) ou quand la vérification rsync est activée.

---

## Limite de jour personnalisée

Vous tournez après minuit? Utilisez [Smart Date](./smart-date.md) pour définir une limite de jour personnalisée.

---

## Connexes

- [Smart Date](./smart-date.md)
- [Options](./options.md)

<!-- lang:de -->
# Einen Film aus einem anderen starten

Ein Film ist die einzige Art von Einstellungen. Presets gibt es nicht mehr: Um Einstellungen wiederzuverwenden, starten Sie einen neuen Film aus einem alten, aus dem eingebauten Netflix-Ingest-Modell oder aus einer Einstellungsdatei. Ein neuer Film erhält immer seine eigene Kopie; die Änderung eines Films ändert nie einen anderen.

---

## Die Schaltfläche "+"

Klicken Sie auf **+** (oder **Ablage › New Backup**, ⌘N). Ein kleines Fenster fragt, womit der Film beginnen soll:

- **Blank movie**: die üblichen Einstellungen des ersten Starts.
- **Netflix Ingest**: ein leerer Film mit den Netflix-Ingest-Ordnereinstellungen (inklusive Log-Ordner `Reports`).
- **Like ‹Film›**, neueste zuerst: kopiert nur die Einstellungen, nie den Dreh (Roll-Nummerierung, Tag, Episode, Verlauf, Katalog, versiegelte Karten, Kartennamen, Laufwerke). Unit und Kameraformat bleiben.
- **From a settings file…**: öffnet eine `.filmcan-movie`-Datei.

Schließen des Fensters legt nichts an.

## Einstellungsdateien

**Export Settings…** (Rechtsklick auf den Film-Tab oder oben in den Filmeinstellungen) speichert `‹Filmname›.filmcan-movie`. Der Import legt immer einen neuen Film an („‹Name› 2", wenn der Name vergeben ist) und überschreibt nie. Alte Preset-Dateien werden nicht mehr geöffnet: *Presets no longer exist. Create a movie and export its settings instead.*

## Netflix Ingest für einen vorhandenen Film

In **Options › Destinations** ersetzt **Use Netflix Ingest folders** nach einer Bestätigung die Ordner- und Namenseinstellungen des Films. Der Schalter daneben schaltet die Ordnerorganisation aus (die Einstellungen bleiben erhalten) und wieder ein.

---

## Ordner- und Dateivorlagen

Organisieren Sie Dateien mit Ordnerstrukturen, Umbenennung und Duplikatbehandlung.

---

## Beispiel

```
Folder: {date}/{source}/
Rename: {source}_{counter}{ext}
Duplicates: Add counter
```

Ergebnis:
```
20260315/A001/
  A001_001.R3D
  A001_002.R3D
```

---

## Variablen

**Quelle / Ziel**  
`{source}`, Original-Quellname (Datei oder Ordner)  
`{sourceParent}`, Name des übergeordneten Ordners der Quelle  
`{sourceDriveName}`, Laufwerk mit der Quelle  
`{destinationDriveName}`, Laufwerk mit dem Ziel  
`{destination}`, Name des Zielordners

**Daten / Zeit**  
`{date}`, `YYYYMMDD`  
`{time}`, `HHmmss`  
`{datetime}`, `YYYYMMDD-HHmmss`  
`{filecreationdate}`, Dateierstel lungsdatum (`YYYYMMDD`)  
`{filemodifieddate}`, Dateiänderungsdatum (`YYYYMMDD`)

**Dateiinfo**  
`{filename}`, Quelldateiname ohne Erweiterung  
`{ext}`, Dateierweiterung (enthält den Punkt)

**Zähler**  
`{counter}`, aufsteigender Zähler (`001`, `002`, `003`…)

---

## Duplikatbehandlung

| Option | Verhalten |
|--------|----------|
| **Skip** | Vorhandene Datei beibehalten |
| **Overwrite** | Vorhandene Datei ersetzen |
| **Add counter** | Suffix wie `_001` hinzufügen |
| **Verify using hash list** | Mit vorhandener Hash-Liste vergleichen, bevor Sie schreiben |
| **Ask** | Jedes Mal auffordern |

**Hinweis:** Hash-Listen werden nur erstellt, wenn **Hash verification** aktiviert ist (FilmCan Engine) oder wenn die rsync-Verifizierung aktiviert ist.

---

## Benutzerdefinierte Tagesgrenze

Drehen Sie nach Mitternacht? Verwenden Sie [Smart Date](./smart-date.md), um eine benutzerdefinierte Tagesgrenze zu setzen.

---

## Verwandte

- [Smart Date](./smart-date.md)
- [Options](./options.md)

<!-- lang:es -->
# Empezar una película desde otra

Una película es el único tipo de ajustes. Ya no hay presets: para reutilizar ajustes, cree una película nueva a partir de una antigua, del modelo Netflix Ingest incluido o de un archivo de ajustes. Una película nueva recibe siempre su propia copia; cambiar una película nunca cambia otra.

---

## El botón "+"

Haga clic en **+** (o **Archivo › New Backup**, ⌘N). Una ventana pequeña pregunta con qué empezar:

- **Blank movie**: los ajustes habituales del primer inicio.
- **Netflix Ingest**: una película en blanco con los ajustes de carpetas de Netflix Ingest (carpeta de registro `Reports` incluida).
- **Like ‹película›**, la más reciente primero: copia solo los ajustes, nunca el rodaje (numeración de rolls, día, episodio, historial, catálogo, tarjetas selladas, nombres de tarjeta, unidades). Se mantienen la unidad y el formato de cámara.
- **From a settings file…**: abre un archivo `.filmcan-movie`.

Cerrar la ventana no crea nada.

## Archivos de ajustes

**Export Settings…** (clic derecho en la pestaña de una película, o arriba en sus ajustes) guarda `‹Nombre›.filmcan-movie`. Importarlo siempre crea una película nueva («‹nombre› 2» si el nombre está tomado) y nunca sobrescribe. Los archivos de presets antiguos ya no se abren: *Presets no longer exist. Create a movie and export its settings instead.*

## Netflix Ingest en una película existente

En **Options › Destinations**, **Use Netflix Ingest folders** reemplaza los ajustes de carpetas y nombres de la película tras una confirmación. El interruptor contiguo desactiva la organización de carpetas (los ajustes se guardan aparte) y la reactiva.

---

## Plantillas de carpetas y archivos

Organice archivos con estructuras de carpetas, cambio de nombre y manejo de duplicados.

---

## Ejemplo

```
Folder: {date}/{source}/
Rename: {source}_{counter}{ext}
Duplicates: Add counter
```

Resultado:
```
20260315/A001/
  A001_001.R3D
  A001_002.R3D
```

---

## Variables

**Origen / Destino**  
`{source}`, nombre de origen original (archivo o carpeta)  
`{sourceParent}`, nombre de carpeta padre del origen  
`{sourceDriveName}`, unidad que contiene el origen  
`{destinationDriveName}`, unidad que contiene el destino  
`{destination}`, nombre de carpeta de destino

**Fechas / Hora**  
`{date}`, `YYYYMMDD`  
`{time}`, `HHmmss`  
`{datetime}`, `YYYYMMDD-HHmmss`  
`{filecreationdate}`, fecha de creación del archivo (`YYYYMMDD`)  
`{filemodifieddate}`, fecha de modificación del archivo (`YYYYMMDD`)

**Información de archivo**  
`{filename}`, nombre de archivo de origen sin extensión  
`{ext}`, extensión de archivo (incluye el punto)

**Contador**  
`{counter}`, contador ascendente (`001`, `002`, `003`…)

---

## Manejo de duplicados

| Opción | Comportamiento |
|--------|----------|
| **Skip** | Mantener archivo existente |
| **Overwrite** | Reemplazar archivo existente |
| **Add counter** | Agregar sufijo como `_001` |
| **Verify using hash list** | Comparar con lista de hash existente antes de escribir |
| **Ask** | Preguntar cada vez |

**Nota:** Las listas de hash se crean solo cuando **Hash verification** está habilitada (FilmCan Engine) o cuando la verificación de rsync está habilitada.

---

## Límite de día personalizado

¿Está fotografiando después de la medianoche? Utilice [Smart Date](./smart-date.md) para establecer un límite de día personalizado.

---

## Relacionado

- [Smart Date](./smart-date.md)
- [Options](./options.md)
