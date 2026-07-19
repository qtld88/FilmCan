<!-- lang:en -->
# Hash Lists

Hash files for later verification. Hash lists are generated for successful transfers when verification is enabled and FilmCan can write the list file.

---

## Limitations

- Hash lists are stored locally on the destination drive.
- If the destination is unavailable, the hash list cannot be re‑verified.

---

## Style: ASC MHL vs Simple

**Options › Basic › Hash list style** picks the manifest format:

| Style | What it writes | For |
|-------|----------------|-----|
| **ASC MHL** (default) | Visible `ascmhl/` folder: a per-generation manifest + `ascmhl_chain.xml` (C4 chain of custody) | Delivery-grade, Netflix-conformant |
| **Simple (hidden)** | One hidden `.filmcan/hashlists/<roll>.mhl` per roll, no chain | Users who just want verification, clean destination |

Resume-skip and verification behave the same either way. The **Netflix Ingest** preset
always forces ASC MHL (the picker is locked).

---

## Format (ASC MHL)

FilmCan writes a spec-faithful **ASC MHL v2.0** manifest per roll (xxHash128 /
xxh3-128 file hashes), plus an `ascmhl_chain.xml` index recording each generation by
its **C4** hash, a chain of custody accepted by the reference ASC MHL tooling.

```xml
<hashlist version="2.0" xmlns="urn:ASC:MHL:v2.0">
  <hashes>
    <hash>
      <path size="…">A001C001.mov</path>
      <xxh128 action="original" hashdate="…">…</xxh128>
    </hash>
  </hashes>
</hashlist>
```

---

## When Generated

The xxHash128 of each file is computed during the copy and written to the manifest
as the file finalizes, unless **Verification** is set to `Off`. Each backup run adds
a new **sealed generation** to the roll's chain.

---

## Location

**ASC MHL**, at each roll's `ascmhl/` folder (the roll = the source-root folder at
the destination):

```
<destination>/<roll-folder>/ascmhl/0001_<roll>_<date>Z.mhl
<destination>/<roll-folder>/ascmhl/ascmhl_chain.xml
```

**Simple**, one hidden file per roll:

```
<destination>/.filmcan/hashlists/<roll>.mhl
```

(Backups made before 1.3 used the `.filmcan/hashlists/` location for all styles;
resume still reads those once.)

---

## Verify Later

1. Open **Transfer History** (click the **clock** icon)
2. Right-click a transfer
3. Choose **Check data**

FilmCan compares files against the saved hashes.

If a transfer is cancelled or fails, or the hash list cannot be written, the list may not be saved.

---

## Related

- [Copy Engines](./copy-engines.md)
- [Transfer History](./transfer-history.md)
- [Options](./options.md)

<!-- lang:fr -->
# Listes de hash

Fichiers de hash pour vérification ultérieure. Les listes de hash sont générées pour les transferts réussis quand la vérification est activée et que FilmCan peut écrire le fichier de liste.

---

## Limitations

- Les listes de hash sont stockées localement sur le disque de destination.
- Si la destination n'est pas disponible, la liste de hash ne peut pas être re-vérifiée.

---

## Style: ASC MHL vs Simple

**Options › Basic › Hash list style** choisit le format du manifeste:

| Style | Ce qu'il écrit | Pour |
|-------|----------------|-----|
| **ASC MHL** (par défaut) | Dossier visible `ascmhl/`: un manifeste par génération + `ascmhl_chain.xml` (chaîne de garde C4) | Qualité de livraison, conforme Netflix |
| **Simple (caché)** | Un fichier caché `.filmcan/hashlists/<roll>.mhl` par roll, pas de chaîne | Les utilisateurs qui veulent juste la vérification, destination propre |

Le saut de reprise et la vérification se comportent de la même façon de toute façon. Le préset **Netflix Ingest**
force toujours ASC MHL (le sélecteur est verrouillé).

---

## Format (ASC MHL)

FilmCan écrit un manifeste **ASC MHL v2.0** conforme aux spécifications par roll (xxHash128 /
haches de fichiers xxh3-128), plus un index `ascmhl_chain.xml` enregistrant chaque génération par
son hache **C4**, une chaîne de garde acceptée par les outils ASC MHL de référence.

```xml
<hashlist version="2.0" xmlns="urn:ASC:MHL:v2.0">
  <hashes>
    <hash>
      <path size="…">A001C001.mov</path>
      <xxh128 action="original" hashdate="…">…</xxh128>
    </hash>
  </hashes>
</hashlist>
```

---

## Quand générée

Le xxHash128 de chaque fichier est calculé pendant la copie et écrit au manifeste
à mesure que le fichier se finalise, sauf si **Verification** est défini sur `Off`. Chaque run de backup ajoute
une nouvelle **génération scellée** à la chaîne du roll.

---

## Localisation

**ASC MHL**, au dossier `ascmhl/` de chaque roll (le roll = le dossier racine source à
la destination):

```
<destination>/<roll-folder>/ascmhl/0001_<roll>_<date>Z.mhl
<destination>/<roll-folder>/ascmhl/ascmhl_chain.xml
```

**Simple**, un fichier caché par roll:

```
<destination>/.filmcan/hashlists/<roll>.mhl
```

(Les backups faits avant 1.3 utilisaient l'emplacement `.filmcan/hashlists/` pour tous les styles;
la reprise lit toujours ceux-ci une fois.)

---

## Vérifier ultérieurement

1. Ouvrez **Transfer History** (cliquez sur l'icône **clock**)
2. Faites un clic droit sur un transfert
3. Choisissez **Check data**

FilmCan compare les fichiers contre les haches sauvegardées.

Si un transfert est annulé ou échoue, ou si la liste de hash ne peut pas être écrite, la liste peut ne pas être sauvegardée.

---

## Connexes

- [Copy Engines](./copy-engines.md)
- [Transfer History](./transfer-history.md)
- [Options](./options.md)

<!-- lang:de -->
# Hash-Listen

Hash-Dateien zur späteren Verifizierung. Hash-Listen werden für erfolgreiche Übertragungen generiert, wenn die Verifizierung aktiviert ist und FilmCan die Listendatei schreiben kann.

---

## Einschränkungen

- Hash-Listen werden lokal auf dem Zieldatenträger gespeichert.
- Wenn das Ziel nicht verfügbar ist, kann die Hash-Liste nicht erneut überprüft werden.

---

## Style: ASC MHL vs Simple

**Options › Basic › Hash list style** wählt das Manifestformat:

| Style | Was es schreibt | Für |
|-------|----------------|-----|
| **ASC MHL** (Standard) | Sichtbarer `ascmhl/`-Ordner: ein Manifest pro Generation + `ascmhl_chain.xml` (C4-Handhabungskette) | Lieferqualität, Netflix-konform |
| **Simple (verborgen)** | Eine verborgene Datei `.filmcan/hashlists/<roll>.mhl` pro roll, keine Kette | Benutzer, die nur Verifizierung wünschen, sauberes Ziel |

Resume-Skip und Verifizierung verhalten sich sowieso gleich. Die **Netflix Ingest**-Voreinstellung
erzwingt immer ASC MHL (die Auswahl ist gesperrt).

---

## Format (ASC MHL)

FilmCan schreibt ein spezifikationskonformes **ASC MHL v2.0**-Manifest pro roll (xxHash128 /
xxh3-128 Datei-Hashes) plus einen `ascmhl_chain.xml`-Index, der jede Generation nach
seinem **C4**-Hash aufzeichnet, eine Handhabungskette, die von den Reference ASC MHL-Tools akzeptiert wird.

```xml
<hashlist version="2.0" xmlns="urn:ASC:MHL:v2.0">
  <hashes>
    <hash>
      <path size="…">A001C001.mov</path>
      <xxh128 action="original" hashdate="…">…</xxh128>
    </hash>
  </hashes>
</hashlist>
```

---

## Wann generiert

Der xxHash128 jeder Datei wird während des Kopierens berechnet und ins Manifest geschrieben,
wenn die Datei finalisiert wird, es sei denn, **Verification** ist auf `Off` gesetzt. Jeder Backup-Run fügt
eine neue **versiegelte Generation** zur Kette des roll hinzu.

---

## Standort

**ASC MHL**, im `ascmhl/`-Ordner jedes roll (der roll = der Quellwurzelordner am
Ziel):

```
<destination>/<roll-folder>/ascmhl/0001_<roll>_<date>Z.mhl
<destination>/<roll-folder>/ascmhl/ascmhl_chain.xml
```

**Simple**, eine verborgene Datei pro roll:

```
<destination>/.filmcan/hashlists/<roll>.mhl
```

(Backups, die vor 1.3 erstellt wurden, verwendeten den Speicherort `.filmcan/hashlists/` für alle Styles;
Resume liest diese immer noch einmal.)

---

## Später verifizieren

1. Öffnen Sie **Transfer History** (klicken Sie auf das **clock**-Symbol)
2. Klicken Sie mit der rechten Maustaste auf eine Übertragung
3. Wählen Sie **Check data**

FilmCan vergleicht Dateien gegen die gespeicherten Hashes.

Wenn eine Übertragung abgebrochen oder fehlgeschlagen ist oder die Hash-Liste nicht geschrieben werden kann, wird die Liste möglicherweise nicht gespeichert.

---

## Verwandte

- [Copy Engines](./copy-engines.md)
- [Transfer History](./transfer-history.md)
- [Options](./options.md)

<!-- lang:es -->
# Listas de hash

Archivos hash para verificación posterior. Las listas de hash se generan para transferencias exitosas cuando la verificación está habilitada y FilmCan puede escribir el archivo de lista.

---

## Limitaciones

- Las listas de hash se almacenan localmente en la unidad de destino.
- Si el destino no está disponible, no se puede reverificar la lista de hash.

---

## Estilo: ASC MHL vs Simple

**Options › Basic › Hash list style** elige el formato del manifiesto:

| Estilo | Lo que escribe | Para |
|--------|----------------|-----|
| **ASC MHL** (predeterminado) | Carpeta visible `ascmhl/`: un manifiesto por generación + `ascmhl_chain.xml` (cadena de custodia C4) | Calidad de entrega, conforme con Netflix |
| **Simple (oculto)** | Un archivo oculto `.filmcan/hashlists/<roll>.mhl` por roll, sin cadena | Usuarios que solo desean verificación, destino limpio |

El skip de reanudación y la verificación se comportan igual de todas formas. El ajuste predefinido **Netflix Ingest**
siempre fuerza ASC MHL (el selector está bloqueado).

---

## Formato (ASC MHL)

FilmCan escribe un manifiesto **ASC MHL v2.0** conforme a las especificaciones por roll (xxHash128 /
hashes de archivo xxh3-128), más un índice `ascmhl_chain.xml` que registra cada generación por
su hash **C4**, una cadena de custodia aceptada por las herramientas de referencia de ASC MHL.

```xml
<hashlist version="2.0" xmlns="urn:ASC:MHL:v2.0">
  <hashes>
    <hash>
      <path size="…">A001C001.mov</path>
      <xxh128 action="original" hashdate="…">…</xxh128>
    </hash>
  </hashes>
</hashlist>
```

---

## Cuándo se genera

El xxHash128 de cada archivo se calcula durante la copia y se escribe en el manifiesto
a medida que el archivo se finaliza, a menos que **Verification** esté establecido en `Off`. Cada ejecución de backup agrega
una nueva **generación sellada** a la cadena del roll.

---

## Ubicación

**ASC MHL**, en la carpeta `ascmhl/` de cada roll (el roll = la carpeta raíz de origen en
el destino):

```
<destination>/<roll-folder>/ascmhl/0001_<roll>_<date>Z.mhl
<destination>/<roll-folder>/ascmhl/ascmhl_chain.xml
```

**Simple**, un archivo oculto por roll:

```
<destination>/.filmcan/hashlists/<roll>.mhl
```

(Los backups creados antes de 1.3 usaban la ubicación `.filmcan/hashlists/` para todos los estilos;
la reanudación aún lee esos una vez.)

---

## Verificar más tarde

1. Abra **Transfer History** (haga clic en el icono **clock**)
2. Haga clic con el botón derecho en una transferencia
3. Elija **Check data**

FilmCan compara archivos contra los hashes guardados.

Si una transferencia se cancela o falla, o si la lista de hash no se puede escribir, es posible que la lista no se guarde.

---

## Relacionado

- [Copy Engines](./copy-engines.md)
- [Transfer History](./transfer-history.md)
- [Options](./options.md)
