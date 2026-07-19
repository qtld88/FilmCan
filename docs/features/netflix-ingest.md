<!-- lang:en -->
# Netflix Footage Ingest

FilmCan can produce delivery-ready output for **Netflix Footage Ingest**, the
required folder structure plus a conformant **ASC MHL** manifest per roll.

---

## Quick start

1. In **Options**, open the **Preset** menu and choose **Netflix Ingest (built-in)**.
2. The **Shoot metadata** fields appear (in the Destinations tab). Fill in:
   - **Episode / Block**, e.g. `EP103`, `Block01`, `B01`, `BK1`
   - **Day**, e.g. `Day05`, `D05`
   - **Unit**, e.g. `MU` (main), `2U` (second), `SP`, `PU`, `DU` (drone)…
   - **Camera format**, e.g. `ARRI`, `RED` (optional; the segment is omitted if blank)
3. Add your camera-card sources and destinations, then **Run Now**.

---

## What you get

For a camera card `A001` and a sound card `SR001`, shot 2026-06-15, EP103, Day 5,
Main unit, ARRI:

```
20260615_EP103_Day05_MU/
├── Reports/                         ← auto-created (the transfer log lands here)
├── Camera_Media/
│   └── ARRI/
│       └── A001/
│           ├── …copied clips…
│           └── ascmhl/
│               ├── 0001_A001_2026-06-15_…Z.mhl   ← ASC MHL v2.0 manifest (this generation)
│               └── ascmhl_chain.xml              ← generation chain (chain of custody)
└── Sound_Media/
    └── SR001/
        ├── …copied wavs…
        └── ascmhl/                  ← sound roll gets its own ASC MHL + chain
            ├── 0001_SR001_2026-06-15_…Z.mhl
            └── ascmhl_chain.xml
```

- **Root folder**: `YYYYMMDD_EP###_Day##_Unit`.
- **One ASC MHL per roll**, at the roll's `ascmhl/` folder. The reel name is the
  folder directly above `ascmhl/` (Netflix's rule).
- Each backup run adds a **new sealed generation** to the chain.

---

## Hashes & conformance

- FilmCan hashes with **xxHash128** (xxh3-128), one of Netflix's accepted formats.
- The manifest is **ASC MHL v2.0**; the chain file uses **C4** hashes, matching the
  ASC MHL specification. FilmCan's output is accepted by the reference `ascmhl` tool.

---

## Camera & Sound in one ingest

Netflix protects production sound (OPA) exactly like camera (OCF), same copies,
hashes, and ASC MHL, it just lands under `Sound_Media/` instead of `Camera_Media/`.

- **Click the icon at the top-right of each source card to switch it between Camera and
  Sound.** A **🎥 video-camera** icon means the source is treated as Camera
  (→ `Camera_Media/`); a **🔊 speaker** icon means Sound (→ `Sound_Media/`). It's a
  toggle, each click flips it. Sources default to Camera.
- The **Save To** card's path preview updates as you toggle, so you can confirm a
  sound card resolves to `…/Sound_Media/<SoundRoll>/` (with its own `ascmhl/`, verify
  and resume), a sibling of the camera media in the same shoot-day root.
- **Options › Sources › Auto-detect sound sources**: drive/folder name patterns (e.g.
  `SOUND`, `MIXPRE*`, `ZOOM*`) auto-add matching drives and tag them Sound.
- **Options › Destinations › Folder templates**: both the **Camera folder** and **Sound
  folder** sub-paths are editable (defaults `…/Camera_Media/{cameraFormat}` and
  `…/Sound_Media`).

Camera and sound can be backed up in the **same run**, the source is read once and
fanned out.

---

## Naming validation

When the Netflix Ingest preset is active, FilmCan pre-flights your roll (source
folder) names against Netflix's prohibited-character set and uniqueness rule. If a
name is invalid or duplicated, a sheet offers:

- **Auto-fix & run**, renames the source folders (prohibited chars → `_`, duplicates
  get a numeric suffix) and runs.
- **Run anyway**, proceeds unchanged.
- **Cancel**.

Prohibited characters: `` @ # $ % ^ & * ( ) ` ; : < > ? , [ ] { } / \ ' " | ~ ``

---

## Delivery readiness

Netflix recommends **≥ 3 copies** on **≥ 2 media types**, with **≥ 1 off-site**. The
metadata section shows a reminder of how many destinations you've configured. Add
more destinations (fan-out is one pass) to make extra copies.

---

## Notes

- Logs: selecting the preset pre-fills the log location to `Reports/` (changeable in
  **Options › Logs**).
- exFAT destinations trigger the existing "DO NOT UNPLUG" banner; Netflix prefers APFS.

## Related

- [Copy Engines](./copy-engines.md) · [Hash Lists](./hash-lists.md) · [Destination Presets](./destination-presets.md)
- `docs/reference/netflix-asc-mhl-requirements.md`, the full requirements memento.

<!-- lang:fr -->
# Netflix Footage Ingest

FilmCan peut produire une sortie prête pour la livraison pour **Netflix Footage Ingest**, la
structure de dossier requise plus un manifeste **ASC MHL** conforme par roll.

---

## Démarrage rapide

1. Dans **Options**, ouvrez le menu **Preset** et choisissez **Netflix Ingest (built-in)**.
2. Les champs **Shoot metadata** apparaissent (dans l'onglet Destinations). Remplissez :
   - **Episode / Block**, par ex. `EP103`, `Block01`, `B01`, `BK1`
   - **Day**, par ex. `Day05`, `D05`
   - **Unit**, par ex. `MU` (main), `2U` (second), `SP`, `PU`, `DU` (drone)…
   - **Camera format**, par ex. `ARRI`, `RED` (optionnel; le segment est omis s'il est vide)
3. Ajoutez vos sources et destinations de carte, puis cliquez sur **Run Now**.

---

## Ce que vous obtenez

Pour une carte caméra `A001` et une carte son `SR001`, tournée le 15-06-2026, EP103, Jour 5,
Unité principale, ARRI :

```
20260615_EP103_Day05_MU/
├── Reports/                         ← créé automatiquement (le journal de transfert se retrouve ici)
├── Camera_Media/
│   └── ARRI/
│       └── A001/
│           ├── …clips copiés…
│           └── ascmhl/
│               ├── 0001_A001_2026-06-15_…Z.mhl   ← Manifeste ASC MHL v2.0 (cette génération)
│               └── ascmhl_chain.xml              ← chaîne de génération (chaîne de garde)
└── Sound_Media/
    └── SR001/
        ├── …wavs copiés…
        └── ascmhl/                  ← le roll son obtient son propre ASC MHL + chaîne
            ├── 0001_SR001_2026-06-15_…Z.mhl
            └── ascmhl_chain.xml
```

- **Dossier racine** : `YYYYMMDD_EP###_Day##_Unit`.
- **Un ASC MHL par roll**, dans le dossier `ascmhl/` du roll. Le nom de la bobine est le
  dossier directement au-dessus de `ascmhl/` (règle de Netflix).
- Chaque exécution de backup ajoute une **nouvelle génération scellée** à la chaîne.

---

## Hachages et conformité

- FilmCan hache avec **xxHash128** (xxh3-128), l'un des formats acceptés par Netflix.
- Le manifeste est **ASC MHL v2.0**; le fichier chaîne utilise des hachages **C4**, correspondant à la
  spécification ASC MHL. La sortie de FilmCan est acceptée par l'outil `ascmhl` de référence.

---

## Caméra et son dans un même ingestion

Netflix protège le son de production (OPA) exactement comme la caméra (OCF), mêmes copies,
hachages et ASC MHL, il se retrouve juste sous `Sound_Media/` au lieu de `Camera_Media/`.

- **Cliquez sur l'icône en haut à droite de chaque carte source pour la basculer entre Caméra et
  Son.** Une icône **🎥 vidéo-caméra** signifie que la source est traitée comme Caméra
  (→ `Camera_Media/`); une icône **🔊 haut-parleur** signifie Son (→ `Sound_Media/`). C'est un
  basculeur, chaque clic le change. Les sources sont par défaut en Caméra.
- L'aperçu du chemin de la carte **Save To** se met à jour lorsque vous basculez, vous pouvez donc confirmer qu'une
  carte son se résout en `…/Sound_Media/<SoundRoll>/` (avec son propre `ascmhl/`, vérification
  et reprise), un frère des médias caméra dans la même racine jour de tournage.
- **Options › Sources › Auto-detect sound sources** : les modèles de noms de disque/dossier (par ex.
  `SOUND`, `MIXPRE*`, `ZOOM*`) ajoutent automatiquement les disques correspondants et les marquent comme Son.
- **Options › Destinations › Folder templates** : les chemins de sous-dossiers **Camera folder** et **Sound
  folder** sont tous deux modifiables (par défaut `…/Camera_Media/{cameraFormat}` et
  `…/Sound_Media`).

Les caméras et les sons peuvent être sauvegardés dans la **même exécution**, la source est lue une fois et
distribuée.

---

## Validation de nommage

Lorsque le préréglage Netflix Ingest est actif, FilmCan précontrôle les noms de votre roll (dossier source)
par rapport à l'ensemble de caractères interdits de Netflix et à la règle d'unicité. Si un
nom n'est pas valide ou est dupliqué, une feuille offre :

- **Auto-fix & run**, renomme les dossiers source (caractères interdits → `_`, les doublons
  obtiennent un suffixe numérique) et s'exécute.
- **Run anyway**, poursuit sans modifications.
- **Cancel**.

Caractères interdits : `` @ # $ % ^ & * ( ) ` ; : < > ? , [ ] { } / \ ' " | ~ ``

---

## Préparation à la livraison

Netflix recommande **≥ 3 copies** sur **≥ 2 types de médias**, avec **≥ 1 hors site**. La
section des métadonnées affiche un rappel du nombre de destinations que vous avez configurées. Ajoutez
plus de destinations (le fan-out est une seule transmission) pour faire des copies supplémentaires.

---

## Notes

- Journaux : la sélection du préréglage pré-remplit l'emplacement du journal à `Reports/` (modifiable dans
  **Options › Logs**).
- Les destinations exFAT déclenchent la bannière « DO NOT UNPLUG » existante; Netflix préfère APFS.

## Liens

- [Copy Engines](./copy-engines.md) · [Hash Lists](./hash-lists.md) · [Destination Presets](./destination-presets.md)
- `docs/reference/netflix-asc-mhl-requirements.md`, le mémento complet des exigences.

<!-- lang:de -->
# Netflix Footage Ingest

FilmCan kann lieferfertige Ausgaben für **Netflix Footage Ingest** erzeugen, die
erforderliche Ordnerstruktur plus ein konformes **ASC MHL**-Manifest pro Roll.

---

## Schnelleinstieg

1. Öffnen Sie in **Options** das Menü **Preset** und wählen Sie **Netflix Ingest (built-in)**.
2. Die Felder **Shoot metadata** erscheinen (auf der Registerkarte Destinations). Füllen Sie aus:
   - **Episode / Block**, z. B. `EP103`, `Block01`, `B01`, `BK1`
   - **Day**, z. B. `Day05`, `D05`
   - **Unit**, z. B. `MU` (main), `2U` (second), `SP`, `PU`, `DU` (drone)…
   - **Camera format**, z. B. `ARRI`, `RED` (optional; das Segment wird weggelassen, wenn es leer ist)
3. Fügen Sie Ihre Kartequellen und Ziele hinzu und klicken Sie dann auf **Run Now**.

---

## Was Sie erhalten

Für eine Kamera-Karte `A001` und eine Sound-Karte `SR001`, gedreht am 15.06.2026, EP103, Tag 5,
Haupteinheit, ARRI:

```
20260615_EP103_Day05_MU/
├── Reports/                         ← automatisch erstellt (das Übertragungsprotokoll wird hier abgelegt)
├── Camera_Media/
│   └── ARRI/
│       └── A001/
│           ├── …kopierte Clips…
│           └── ascmhl/
│               ├── 0001_A001_2026-06-15_…Z.mhl   ← ASC MHL v2.0-Manifest (diese Generation)
│               └── ascmhl_chain.xml              ← Generationskette (Verfolgungskette)
└── Sound_Media/
    └── SR001/
        ├── …kopierte Wavs…
        └── ascmhl/                  ← Sound-Roll erhält sein eigenes ASC MHL + Kette
            ├── 0001_SR001_2026-06-15_…Z.mhl
            └── ascmhl_chain.xml
```

- **Stammordner** : `YYYYMMDD_EP###_Day##_Unit`.
- **Ein ASC MHL pro Roll**, im Ordner `ascmhl/` des Roll. Der Aufmerksamkeitsname ist der
  Ordner direkt über `ascmhl/` (Netflix-Regel).
- Jeder Backup-Lauf fügt eine **neue versiegelte Generation** zur Kette hinzu.

---

## Hashes und Konformität

- FilmCan hashed mit **xxHash128** (xxh3-128), eines der von Netflix akzeptierten Formate.
- Das Manifest ist **ASC MHL v2.0**; die Kettendate verwendet **C4**-Hashes und stimmt mit dem
  ASC MHL-Standard überein. FilmCans Ausgabe wird vom Referenz-Tool `ascmhl` akzeptiert.

---

## Kamera und Sound in einem Ingest

Netflix schützt Production Sound (OPA) genau wie Kamera (OCF), gleiche Kopien,
Hashes und ASC MHL, es landet nur unter `Sound_Media/` statt `Camera_Media/`.

- **Klicken Sie auf das Symbol oben rechts auf jeder Quellkarte, um zwischen Kamera und Sound zu wechseln.** Ein **🎥 Videokamera**-Symbol bedeutet, dass die Quelle als Kamera behandelt wird
  (→ `Camera_Media/`); ein **🔊 Lautsprecher**-Symbol bedeutet Sound (→ `Sound_Media/`). Es ist ein
  Umschalter, jeder Klick schaltet um. Quellen sind standardmäßig auf Kamera eingestellt.
- Die Pfadvorschau der **Save To**-Karte wird aktualisiert, wenn Sie umschalten, damit Sie bestätigen können, dass eine
  Sound-Karte in `…/Sound_Media/<SoundRoll>/` aufgelöst wird (mit seinem eigenen `ascmhl/`, Verifizierung
  und Fortsetzen), ein Nebeneinander der Kameramedia in der gleichen Drehtags-Wurzel.
- **Options › Sources › Auto-detect sound sources** : Muster für Laufwerk-/Ordnernamen (z. B.
  `SOUND`, `MIXPRE*`, `ZOOM*`) fügen automatisch entsprechende Laufwerke hinzu und kennzeichnen sie als Sound.
- **Options › Destinations › Folder templates** : Beide **Camera folder** und **Sound
  folder** Unterpfade sind bearbeitbar (Standard `…/Camera_Media/{cameraFormat}` und
  `…/Sound_Media`).

Kamera und Sound können im **gleichen Durchlauf** gesichert werden, die Quelle wird einmal gelesen und
ausgestrahlt.

---

## Benennungsvalidierung

Wenn die Netflix Ingest-Voreinstellung aktiv ist, prüft FilmCan Ihre Roll-Namen (Quellordner)
gegen Netflixs verbotene Zeichensätze und Eindeutigkeitsregel vor. Wenn ein
Name ungültig oder dupliziert ist, bietet ein Blatt:

- **Auto-fix & run**, benennt die Quellordner um (verbotene Zeichen → `_`, Duplikate
  erhalten ein numerisches Suffix) und wird ausgeführt.
- **Run anyway**, wird unverändert fortgesetzt.
- **Cancel**.

Verbotene Zeichen: `` @ # $ % ^ & * ( ) ` ; : < > ? , [ ] { } / \ ' " | ~ ``

---

## Lieferbereitschaft

Netflix empfiehlt **≥ 3 Kopien** auf **≥ 2 Medientypen**, mit **≥ 1 extern**. Der
Metadatenabschnitt zeigt eine Erinnerung an, wie viele Ziele Sie konfiguriert haben. Fügen Sie
mehr Ziele hinzu (Fan-out ist ein Durchgang) für zusätzliche Kopien.

---

## Hinweise

- Protokolle: Das Auswählen der Voreinstellung füllt den Protokollspeicherort vorab auf `Reports/` aus (modifizierbar in
  **Options › Logs**).
- exFAT-Ziele lösen das vorhandene Banner « DO NOT UNPLUG » aus; Netflix bevorzugt APFS.

## Links

- [Copy Engines](./copy-engines.md) · [Hash Lists](./hash-lists.md) · [Destination Presets](./destination-presets.md)
- `docs/reference/netflix-asc-mhl-requirements.md`, das vollständige Anforderungsmemento.

<!-- lang:es -->
# Netflix Footage Ingest

FilmCan puede producir salida lista para entrega para **Netflix Footage Ingest**, la
estructura de carpeta requerida más un manifiesto **ASC MHL** conforme por roll.

---

## Inicio rápido

1. En **Options**, abra el menú **Preset** y elija **Netflix Ingest (built-in)**.
2. Aparecen los campos **Shoot metadata** (en la pestaña Destinations). Rellene:
   - **Episode / Block**, por ejemplo, `EP103`, `Block01`, `B01`, `BK1`
   - **Day**, por ejemplo, `Day05`, `D05`
   - **Unit**, por ejemplo, `MU` (main), `2U` (second), `SP`, `PU`, `DU` (drone)…
   - **Camera format**, por ejemplo, `ARRI`, `RED` (opcional; el segmento se omite si está en blanco)
3. Agregue sus orígenes y destinos de tarjeta, luego haga clic en **Run Now**.

---

## Lo que obtiene

Para una tarjeta de cámara `A001` y una tarjeta de sonido `SR001`, rodada el 15/06/2026, EP103, Día 5,
Unidad principal, ARRI:

```
20260615_EP103_Day05_MU/
├── Reports/                         ← creado automáticamente (el registro de transferencia se guardará aquí)
├── Camera_Media/
│   └── ARRI/
│       └── A001/
│           ├── …clips copiados…
│           └── ascmhl/
│               ├── 0001_A001_2026-06-15_…Z.mhl   ← Manifiesto ASC MHL v2.0 (esta generación)
│               └── ascmhl_chain.xml              ← cadena de generación (cadena de custodia)
└── Sound_Media/
    └── SR001/
        ├── …wavs copiados…
        └── ascmhl/                  ← el roll de sonido obtiene su propio ASC MHL + cadena
            ├── 0001_SR001_2026-06-15_…Z.mhl
            └── ascmhl_chain.xml
```

- **Carpeta raíz** : `YYYYMMDD_EP###_Day##_Unit`.
- **Un ASC MHL por roll**, en la carpeta `ascmhl/` del roll. El nombre del carrete es la
  carpeta directamente encima de `ascmhl/` (regla de Netflix).
- Cada ejecución de backup añade una **nueva generación sellada** a la cadena.

---

## Hashes y conformidad

- FilmCan aplica hash con **xxHash128** (xxh3-128), uno de los formatos aceptados por Netflix.
- El manifiesto es **ASC MHL v2.0**; el archivo de cadena utiliza hashes **C4**, que coinciden con la
  especificación ASC MHL. La salida de FilmCan es aceptada por la herramienta de referencia `ascmhl`.

---

## Cámara y sonido en una ingesta

Netflix protege el sonido de producción (OPA) exactamente como la cámara (OCF), las mismas copias,
hashes y ASC MHL, solo se guardan bajo `Sound_Media/` en lugar de `Camera_Media/`.

- **Haga clic en el icono en la parte superior derecha de cada tarjeta de origen para cambiar entre Cámara y
  Sonido.** Un icono **🎥 cámara de vídeo** significa que el origen se trata como Cámara
  (→ `Camera_Media/`); un icono **🔊 altavoz** significa Sonido (→ `Sound_Media/`). Es un
  alternador, cada clic lo activa. Los orígenes están configurados de forma predeterminada en Cámara.
- La vista previa de ruta de la tarjeta **Save To** se actualiza al alternar, para que pueda confirmar que una
  tarjeta de sonido se resuelve en `…/Sound_Media/<SoundRoll>/` (con su propio `ascmhl/`, verificación
  y reanudación), un hermano de los medios de cámara en la misma raíz de día de rodaje.
- **Options › Sources › Auto-detect sound sources** : patrones de nombres de unidad/carpeta (por ejemplo,
  `SOUND`, `MIXPRE*`, `ZOOM*`) añaden automáticamente unidades coincidentes y las etiquetan como Sonido.
- **Options › Destinations › Folder templates** : tanto la **Camera folder** como **Sound
  folder** rutas secundarias son editables (por defecto `…/Camera_Media/{cameraFormat}` y
  `…/Sound_Media`).

La cámara y el sonido se pueden respaldar en la **misma ejecución**, el origen se lee una vez y
se distribuye.

---

## Validación de nombres

Cuando el preset de Netflix Ingest está activo, FilmCan precontrola los nombres de su roll (carpeta de origen)
contra el conjunto de caracteres prohibidos de Netflix y la regla de unicidad. Si un
nombre no es válido o duplicado, una hoja ofrece:

- **Auto-fix & run**, renombra las carpetas de origen (caracteres prohibidos → `_`, los duplicados
  obtienen un sufijo numérico) y se ejecuta.
- **Run anyway**, continúa sin cambios.
- **Cancel**.

Caracteres prohibidos: `` @ # $ % ^ & * ( ) ` ; : < > ? , [ ] { } / \ ' " | ~ ``

---

## Preparación para la entrega

Netflix recomienda **≥ 3 copias** en **≥ 2 tipos de medios**, con **≥ 1 fuera del sitio**. La
sección de metadatos muestra un recordatorio de cuántos destinos ha configurado. Añada
más destinos (el fan-out es un solo paso) para realizar copias adicionales.

---

## Notas

- Registros: seleccionar el preset completa previamente la ubicación del registro en `Reports/` (modificable en
  **Options › Logs**).
- Los destinos exFAT activan la bandera existente « DO NOT UNPLUG »; Netflix prefiere APFS.

## Relacionado

- [Copy Engines](./copy-engines.md) · [Hash Lists](./hash-lists.md) · [Destination Presets](./destination-presets.md)
- `docs/reference/netflix-asc-mhl-requirements.md`, el memento completo de requisitos.
