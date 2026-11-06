<!-- lang:en -->
# Options

Options are grouped into tabs in the **Backup Editor**. Click the open tab again to collapse the options, or a tab to expand them.

The preset menu shows **(modified)** after the preset name when this movie's settings differ from the preset; hover it to list the differences.

> The copy-engine picker was removed in 1.2.0, the FilmCan Engine handles every
> backup. See [Copy Engines](./copy-engines.md).

---

## Basic options

See [Copy Engines](./copy-engines.md) for engine behavior.

- **Verification**: `Off`, `Fast`, or `Paranoid`. Default for new projects is
  `Fast`. See [Copy Engines](./copy-engines.md#verification-modes).
- **Force re-copy**: re-copies every file even if it's already backed up
  (disables resume skip). Off by default.
- **Duplicate policy**: `Skip`, `Overwrite`, `Add counter`, `Ask each time`. See [Destination Presets](./destination-presets.md).
- **Counter style**: shown only when **Duplicate policy** is `Add counter`.
- **Copy mode**: how multiple destinations are written:
  - `Automatic` *(default)*: parallel for SSDs / distinct drives, sequential for a network destination or two destinations on the same physical volume.
  - `All destinations at once`: read the source once, write everywhere together.
  - `One destination at a time`: copy each destination fully before the next (re-reads the source per destination).
- **Copy order**: `Default order`, `Smallest first`, `Largest first`, `Creation date`.

---

## Source

See [Source Selection](./source-selection.md) for patterns and auto-detect details.

- **Auto-detect sources**, toggle.
- **Drive and folder names to detect**, shown when **Auto-detect sources** is on.
- **Copy folder contents only**, copies the contents of a source folder without the top-level folder.
- **Copy-only patterns (optional)**.
- **Include patterns (optional)**.
- **Exclude patterns (optional)**.

---

## Destinations

See [Destination Presets](./destination-presets.md) for templates and tokens.

- **Auto-detect destinations**, toggle.
- **Drive and folder names to detect**, shown when **Auto-detect destinations** is on.
- **Folder template**, toggle + template field.
- **Rename only patterns (optional)**, shown when **Folder template** is on.
- **File name template**, toggle + template field.
- **Custom date for tokens**, toggle + date picker. See [Smart Date](./smart-date.md).

---

## Logs

- **Create log file**, toggle.
- **Location**, `Same as destination` or `Custom folder` (when **Create log file** is on).
- **Custom log folder**, shown when **Location** is `Custom folder`.
- **Log file path and name**, shown when **Create log file** is on.

---

## Verification & integrity

- **Verification** mode (Off / Fast / Paranoid) is in **Basic options** above.
- **xxHash128** is the checksum algorithm; hash lists are written per source
  root. See [Hash Lists](./hash-lists.md).
- Resume skip and **Force re-copy** are covered in [Copy Engines](./copy-engines.md#resume--re-running-skips-whats-already-there).

> The rsync-only **Transfer refinements** tab was removed in 1.2.0 along with the
> rsync engine.

<!-- lang:fr -->
# Options

Les options sont regroupées dans les onglets de l'**Backup Editor**. Cliquez à nouveau sur l'onglet ouvert pour replier les options, ou sur un onglet pour les déplier.

Le menu des présets affiche **(modified)** après le nom du préset quand les réglages de ce film s'en écartent ; survolez-le pour lister les différences.

> Le sélecteur de moteur de copie a été supprimé dans la version 1.2.0, le moteur FilmCan gère chaque
> backup. Voir [Copy Engines](./copy-engines.md).

---

## Options de base

Voir [Copy Engines](./copy-engines.md) pour le comportement du moteur.

- **Verification** : `Off`, `Fast` ou `Paranoid`. La valeur par défaut pour les nouveaux projets est
  `Fast`. Voir [Copy Engines](./copy-engines.md#verification-modes).
- **Force re-copy** : copie à nouveau chaque fichier même s'il a déjà été sauvegardé
  (désactive la reprise du saut). Désactivé par défaut.
- **Duplicate policy** : `Skip`, `Overwrite`, `Add counter`, `Ask each time`. Voir [Destination Presets](./destination-presets.md).
- **Counter style** : affiché uniquement lorsque **Duplicate policy** est `Add counter`.
- **Copy mode** : comment plusieurs destinations sont écrites :
  - `Automatic` *(par défaut)* : parallèle pour les disques SSD/disques distincts, séquentiel pour une destination réseau ou deux destinations sur le même volume physique.
  - `All destinations at once` : lire la source une fois, écrire partout ensemble.
  - `One destination at a time` : copier chaque destination complètement avant la suivante (relit la source par destination).
- **Copy order** : `Default order`, `Smallest first`, `Largest first`, `Creation date`.

---

## Source

Voir [Source Selection](./source-selection.md) pour les modèles et les détails de la détection automatique.

- **Auto-detect sources**, bascule.
- **Drive and folder names to detect**, affiché lorsque **Auto-detect sources** est activé.
- **Copy folder contents only**, copie le contenu d'un dossier source sans le dossier de niveau supérieur.
- **Copy-only patterns (optional)**.
- **Include patterns (optional)**.
- **Exclude patterns (optional)**.

---

## Destinations

Voir [Destination Presets](./destination-presets.md) pour les modèles et les jetons.

- **Auto-detect destinations**, bascule.
- **Drive and folder names to detect**, affiché lorsque **Auto-detect destinations** est activé.
- **Folder template**, bascule + champ de modèle.
- **Rename only patterns (optional)**, affiché lorsque **Folder template** est activé.
- **File name template**, bascule + champ de modèle.
- **Custom date for tokens**, bascule + sélecteur de date. Voir [Smart Date](./smart-date.md).

---

## Journaux

- **Create log file**, bascule.
- **Location**, `Same as destination` ou `Custom folder` (lorsque **Create log file** est activé).
- **Custom log folder**, affiché lorsque **Location** est `Custom folder`.
- **Log file path and name**, affiché lorsque **Create log file** est activé.

---

## Vérification et intégrité

- Le mode **Verification** (Off/Fast/Paranoid) se trouve dans **Basic options** ci-dessus.
- **xxHash128** est l'algorithme de somme de contrôle; les listes de hachage sont écrites par racine de source.
  Voir [Hash Lists](./hash-lists.md).
- La reprise du saut et **Force re-copy** sont couvertes dans [Copy Engines](./copy-engines.md#resume--re-running-skips-whats-already-there).

> L'onglet **Transfer refinements** uniquement pour rsync a été supprimé dans la version 1.2.0 avec le
> moteur rsync.

<!-- lang:de -->
# Optionen

Optionen sind in Registerkarten im **Backup Editor** gruppiert. Ein Klick auf die geöffnete Registerkarte klappt die Optionen ein, ein Klick auf eine Registerkarte klappt sie aus.

Das Preset-Menü zeigt **(modified)** hinter dem Preset-Namen, wenn die Einstellungen dieses Films vom Preset abweichen; fahren Sie darüber, um die Unterschiede aufzulisten.

> Die Auswahl des Kopier-Engines wurde in Version 1.2.0 entfernt. Das FilmCan Engine verwaltet jeden
> Backup. Siehe [Copy Engines](./copy-engines.md).

---

## Grundlegende Optionen

Siehe [Copy Engines](./copy-engines.md) für das Engine-Verhalten.

- **Verification** : `Off`, `Fast` oder `Paranoid`. Standard für neue Projekte ist
  `Fast`. Siehe [Copy Engines](./copy-engines.md#verification-modes).
- **Force re-copy** : kopiert jede Datei erneut, auch wenn sie bereits gesichert ist
  (deaktiviert die Fortsetzen-Übersprung). Standardmäßig deaktiviert.
- **Duplicate policy** : `Skip`, `Overwrite`, `Add counter`, `Ask each time`. Siehe [Destination Presets](./destination-presets.md).
- **Counter style** : wird nur angezeigt, wenn **Duplicate policy** auf `Add counter` eingestellt ist.
- **Copy mode** : wie mehrere Ziele geschrieben werden :
  - `Automatic` *(Standard)* : parallel für SSDs/unterschiedliche Laufwerke, sequenziell für ein Netzwerkziel oder zwei Ziele auf dem gleichen physischen Volume.
  - `All destinations at once` : Quelle einmal lesen, überall gleichzeitig schreiben.
  - `One destination at a time` : jedes Ziel vollständig kopieren, bevor das nächste kopiert wird (liest die Quelle pro Ziel erneut).
- **Copy order** : `Default order`, `Smallest first`, `Largest first`, `Creation date`.

---

## Quelle

Siehe [Source Selection](./source-selection.md) für Muster und Details zur Automatischen Erkennung.

- **Auto-detect sources**, Umschalter.
- **Drive and folder names to detect**, wird angezeigt, wenn **Auto-detect sources** aktiviert ist.
- **Copy folder contents only**, kopiert den Inhalt eines Quellordners ohne den übergeordneten Ordner.
- **Copy-only patterns (optional)**.
- **Include patterns (optional)**.
- **Exclude patterns (optional)**.

---

## Ziele

Siehe [Destination Presets](./destination-presets.md) für Vorlagen und Token.

- **Auto-detect destinations**, Umschalter.
- **Drive and folder names to detect**, wird angezeigt, wenn **Auto-detect destinations** aktiviert ist.
- **Folder template**, Umschalter + Vorlagenfeld.
- **Rename only patterns (optional)**, wird angezeigt, wenn **Folder template** aktiviert ist.
- **File name template**, Umschalter + Vorlagenfeld.
- **Custom date for tokens**, Umschalter + Datumsauswahl. Siehe [Smart Date](./smart-date.md).

---

## Protokolle

- **Create log file**, Umschalter.
- **Location**, `Same as destination` oder `Custom folder` (wenn **Create log file** aktiviert ist).
- **Custom log folder**, wird angezeigt, wenn **Location** auf `Custom folder` eingestellt ist.
- **Log file path and name**, wird angezeigt, wenn **Create log file** aktiviert ist.

---

## Verifizierung und Integrität

- Der **Verification**-Modus (Off/Fast/Paranoid) befindet sich in den **Basic options** oben.
- **xxHash128** ist der Prüfsummen-Algorithmus; Hash-Listen werden pro Quellwurzel geschrieben.
  Siehe [Hash Lists](./hash-lists.md).
- Fortsetzen-Übersprung und **Force re-copy** werden in [Copy Engines](./copy-engines.md#resume--re-running-skips-whats-already-there) behandelt.

> Die **Transfer refinements**-Registerkarte nur für rsync wurde in Version 1.2.0 zusammen mit dem
> rsync Engine entfernt.

<!-- lang:es -->
# Opciones

Las opciones se agrupan en pestañas en el **Backup Editor**. Haga clic de nuevo en la pestaña abierta para contraer las opciones, o en una pestaña para desplegarlas.

El menú de presets muestra **(modified)** tras el nombre del preset cuando los ajustes de esta película difieren de él; pase el cursor para ver las diferencias.

> El selector de motor de copia se eliminó en la versión 1.2.0, el Motor FilmCan maneja cada
> backup. Ver [Copy Engines](./copy-engines.md).

---

## Opciones básicas

Ver [Copy Engines](./copy-engines.md) para el comportamiento del motor.

- **Verification** : `Off`, `Fast` o `Paranoid`. El valor predeterminado para nuevos proyectos es
  `Fast`. Ver [Copy Engines](./copy-engines.md#verification-modes).
- **Force re-copy** : recopian cada archivo incluso si ya ha sido respaldado
  (deshabilita la reanudación de salto). Deshabilitado de forma predeterminada.
- **Duplicate policy** : `Skip`, `Overwrite`, `Add counter`, `Ask each time`. Ver [Destination Presets](./destination-presets.md).
- **Counter style** : se muestra solo cuando **Duplicate policy** es `Add counter`.
- **Copy mode** : cómo se escriben varios destinos :
  - `Automatic` *(predeterminado)* : paralelo para unidades SSD/distintas, secuencial para un destino de red o dos destinos en el mismo volumen físico.
  - `All destinations at once` : lea la fuente una vez, escriba en todas partes juntas.
  - `One destination at a time` : copie cada destino completamente antes del siguiente (relee la fuente por destino).
- **Copy order** : `Default order`, `Smallest first`, `Largest first`, `Creation date`.

---

## Origen

Ver [Source Selection](./source-selection.md) para patrones y detalles de detección automática.

- **Auto-detect sources**, alternar.
- **Drive and folder names to detect**, se muestra cuando **Auto-detect sources** está activado.
- **Copy folder contents only**, copia el contenido de una carpeta de origen sin la carpeta de nivel superior.
- **Copy-only patterns (optional)**.
- **Include patterns (optional)**.
- **Exclude patterns (optional)**.

---

## Destinos

Ver [Destination Presets](./destination-presets.md) para plantillas y tokens.

- **Auto-detect destinations**, alternar.
- **Drive and folder names to detect**, se muestra cuando **Auto-detect destinations** está activado.
- **Folder template**, alternar + campo de plantilla.
- **Rename only patterns (optional)**, se muestra cuando **Folder template** está activado.
- **File name template**, alternar + campo de plantilla.
- **Custom date for tokens**, alternar + selector de fecha. Ver [Smart Date](./smart-date.md).

---

## Registros

- **Create log file**, alternar.
- **Location**, `Same as destination` o `Custom folder` (cuando **Create log file** está activado).
- **Custom log folder**, se muestra cuando **Location** es `Custom folder`.
- **Log file path and name**, se muestra cuando **Create log file** está activado.

---

## Verificación e integridad

- El modo **Verification** (Off/Fast/Paranoid) está en **Basic options** arriba.
- **xxHash128** es el algoritmo de suma de verificación; las listas de hash se escriben por raíz de origen.
  Ver [Hash Lists](./hash-lists.md).
- La reanudación de salto y **Force re-copy** se tratan en [Copy Engines](./copy-engines.md#resume--re-running-skips-whats-already-there).

> La pestaña **Transfer refinements** solo para rsync se eliminó en la versión 1.2.0 junto con el
> Motor rsync.
