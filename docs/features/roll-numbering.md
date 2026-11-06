<!-- lang:en -->
# Roll Numbering and Shoot Day

Options › Source › **Cards & rolls**. Everything here is **off by default**; existing backups
behave exactly as before.

---

## Automatic roll names

With **Number rolls automatically** on, each folder source gets a roll name instead of the
card (volume) name: camera cards `A001, A002, A003…`, sound cards `S001, S002…`. The source row shows the name it will get ("→ A003"), and a line under the settings shows the next camera and sound roll.

- Prefix (1-2 letters), digit count (2 to 4) and start number are set separately for camera and sound (the digit count is shared).
- ARRI and RED cards keep their own reel name (switch off with **ARRI and RED keep their reel
  name**).
- **The same card always gets the same roll name.** The assignment is saved before the copy
  starts, so a stopped backup resumes into the same roll folder.
- A reformatted card has a new volume UUID and is treated as a new roll.
- Two cards can never share a roll folder: a name collision still gets a `-2` suffix.
- Flat files (not folders) are not numbered.
- **Reset numbering…** forgets the assignments, after a confirmation. Backups already made keep their folder names.

Roll folders use the assigned name verbatim. The destination rename template no longer applies
to numbered roll folders.

Numbers are stored per backup in `roll-numbering.json` (Application Support/FilmCan), not in the backup
configuration. Retrying a failed destination from History reuses the roll names of the original run.

Known limit (v1): the destination preview and the log path still show the card name.

---

## Shoot-day counter

**Advance the shoot day automatically**: on the first backup of each new calendar day, `{day}`
goes up by one while keeping its width (`Day01` → `Day02`, `D9` → `D10`). The Day field is the
starting value. A Day without trailing digits is left unchanged. The current value is shown
under the toggle ("Today: Day02").

<!-- lang:fr -->
# Numérotation des rolls et jour de tournage

Options › Source › **Cards & rolls**. Tout ce qui se trouve ici est **désactivé par défaut** ; les sauvegardes existantes
se comportent exactement comme avant.

---

## Noms de roll automatiques

Avec **Number rolls automatically** activé, chaque source de type dossier reçoit un nom de roll à la place du
nom de la carte (du volume) : `A001, A002, A003…` pour les cartes caméra, `S001, S002…` pour les cartes son. La ligne de la source affiche le nom qu'elle recevra (« → A003 »), et une ligne sous les réglages indique les prochains rolls caméra et son.

- Le préfixe (1 à 2 lettres), le nombre de chiffres (2 à 4) et le numéro de départ se règlent séparément pour la caméra et le son (le nombre de chiffres est commun).
- Les cartes ARRI et RED gardent leur propre nom de bobine (désactivez avec **ARRI and RED keep their reel
  name**).
- **La même carte reçoit toujours le même nom de roll.** L'attribution est enregistrée avant le début de la copie,
  donc une sauvegarde arrêtée reprend dans le même dossier de roll.
- Une carte reformatée a un nouvel UUID de volume et est traitée comme un nouveau roll.
- Deux cartes ne peuvent jamais partager un dossier de roll : en cas de collision de nom, un suffixe `-2` est ajouté.
- Les fichiers seuls (pas des dossiers) ne sont pas numérotés.
- **Reset numbering…** oublie les attributions, après confirmation. Les sauvegardes déjà faites gardent leurs noms de dossier.

Les dossiers de roll utilisent le nom attribué tel quel. Le modèle de renommage de destination ne s'applique plus
aux dossiers de roll numérotés.

Les numéros sont stockés par sauvegarde dans `roll-numbering.json` (Application Support/FilmCan), et non dans la configuration
de la sauvegarde. Relancer une destination en échec depuis History réutilise les noms de roll de l'exécution d'origine.

Limite connue (v1) : l'aperçu de destination et le chemin du journal affichent encore le nom de la carte.

---

## Compteur de jour de tournage

**Advance the shoot day automatically** : lors de la première sauvegarde de chaque nouveau jour calendaire, `{day}`
augmente de un en gardant sa largeur (`Day01` → `Day02`, `D9` → `D10`). Le champ Day est la
valeur de départ. Un Day sans chiffres à la fin reste inchangé. La valeur actuelle s'affiche
sous l'interrupteur (« Today: Day02 »).

<!-- lang:de -->
# Roll-Nummerierung und Drehtag

Options › Source › **Cards & rolls**. Alles hier ist **standardmäßig aus**; bestehende Sicherungen
verhalten sich exakt wie zuvor.

---

## Automatische Roll-Namen

Ist **Number rolls automatically** eingeschaltet, erhält jede Ordnerquelle einen Roll-Namen statt des
Karten- (Volume-)Namens: Kamerakarten `A001, A002, A003…`, Soundkarten `S001, S002…`. Die Quellzeile zeigt den Namen, den sie erhalten wird („→ A003“), und eine Zeile unter den Einstellungen nennt den nächsten Kamera- und Sound-Roll.

- Präfix (1-2 Buchstaben), Stellenzahl (2 bis 4) und Startnummer werden für Kamera und Sound getrennt eingestellt (die Stellenzahl gilt für beide).
- ARRI- und RED-Karten behalten ihren eigenen Reel-Namen (abschalten mit **ARRI and RED keep their reel
  name**).
- **Dieselbe Karte erhält immer denselben Roll-Namen.** Die Zuordnung wird vor Beginn des Kopierens gespeichert,
  daher wird eine gestoppte Sicherung im selben Roll-Ordner fortgesetzt.
- Eine neu formatierte Karte hat eine neue Volume-UUID und wird als neuer Roll behandelt.
- Zwei Karten können nie einen Roll-Ordner teilen: Bei einer Namenskollision wird das Suffix `-2` angehängt.
- Einzelne Dateien (keine Ordner) werden nicht nummeriert.
- **Reset numbering…** vergisst die Zuordnungen, nach einer Bestätigung. Bereits erstellte Sicherungen behalten ihre Ordnernamen.

Roll-Ordner verwenden den zugewiesenen Namen unverändert. Die Umbenennungsvorlage des Ziels gilt
nicht mehr für nummerierte Roll-Ordner.

Die Nummern werden pro Sicherung in `roll-numbering.json` (Application Support/FilmCan) gespeichert, nicht in der Konfiguration
der Sicherung. Wird ein fehlgeschlagenes Ziel aus History erneut versucht, werden die Roll-Namen des ursprünglichen Durchlaufs wiederverwendet.

Bekannte Einschränkung (v1): Die Zielvorschau und der Protokollpfad zeigen weiterhin den Kartennamen.

---

## Drehtag-Zähler

**Advance the shoot day automatically**: Bei der ersten Sicherung jedes neuen Kalendertags
wird `{day}` um eins erhöht, wobei die Breite erhalten bleibt (`Day01` → `Day02`, `D9` → `D10`). Das Feld Day ist der
Startwert. Ein Day ohne abschließende Ziffern bleibt unverändert. Der aktuelle Wert steht
unter dem Schalter („Today: Day02“).

<!-- lang:es -->
# Numeración de rolls y día de rodaje

Options › Source › **Cards & rolls**. Todo lo de aquí está **desactivado por defecto**; los respaldos existentes
se comportan exactamente como antes.

---

## Nombres de roll automáticos

Con **Number rolls automatically** activado, cada origen de tipo carpeta recibe un nombre de roll en lugar del
nombre de la tarjeta (del volumen): `A001, A002, A003…` para las tarjetas de cámara, `S001, S002…` para las de sonido. La fila del origen muestra el nombre que recibirá («→ A003»), y una línea bajo los ajustes indica los próximos rolls de cámara y sonido.

- El prefijo (1-2 letras), el número de dígitos (2 a 4) y el número inicial se ajustan por separado para cámara y sonido (el número de dígitos es común).
- Las tarjetas ARRI y RED conservan su propio nombre de bobina (se desactiva con **ARRI and RED keep their reel
  name**).
- **La misma tarjeta recibe siempre el mismo nombre de roll.** La asignación se guarda antes de empezar la copia,
  así que un respaldo detenido se reanuda en la misma carpeta de roll.
- Una tarjeta reformateada tiene un nuevo UUID de volumen y se trata como un roll nuevo.
- Dos tarjetas nunca pueden compartir carpeta de roll: si hay una colisión de nombre, se añade el sufijo `-2`.
- Los archivos sueltos (no carpetas) no se numeran.
- **Reset numbering…** olvida las asignaciones, tras una confirmación. Los respaldos ya hechos conservan los nombres de sus carpetas.

Las carpetas de roll usan el nombre asignado tal cual. La plantilla de renombrado del destino ya no se aplica
a las carpetas de roll numeradas.

Los números se guardan por respaldo en `roll-numbering.json` (Application Support/FilmCan), no en la configuración
del respaldo. Reintentar un destino fallido desde History reutiliza los nombres de roll de la ejecución original.

Límite conocido (v1): la vista previa del destino y la ruta del registro siguen mostrando el nombre de la tarjeta.

---

## Contador del día de rodaje

**Advance the shoot day automatically**: en el primer respaldo de cada nuevo día natural, `{day}`
sube una unidad conservando su anchura (`Day01` → `Day02`, `D9` → `D10`). El campo Day es el
valor inicial. Un Day sin dígitos finales queda sin cambios. El valor actual se muestra
bajo el interruptor («Today: Day02»).
