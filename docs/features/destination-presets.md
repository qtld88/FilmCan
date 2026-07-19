<!-- lang:en -->
# Destination Presets

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
# Présets de destination

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
# Zielvoreinstellungen

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
# Ajustes predefinidos de destino

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
