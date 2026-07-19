<!-- lang:en -->
# Multi-Destination Backups

Back up to multiple destinations for redundancy. The FilmCan Engine reads the
source **once** and writes to every destination together; the **Copy mode**
option chooses how those writes are scheduled.

---

## Copy mode

Set in **Backup Editor → Options → Copy mode**.

### Automatic *(default)*

FilmCan picks per run: **parallel** when destinations are distinct SSDs, and
**sequential** when a destination is a network volume or two destinations live on
the same physical volume (parallel writes to one drive thrash it). It does **not**
gate on the OS "solid state" flag, which is unreliable for external USB /
Thunderbolt SSDs.

### All destinations at once (parallel)

Source is read once and broadcast to every destination in parallel. Throughput
is set by the slowest drive, the others overlap their writes. One read pass per
source regardless of destination count.

### One destination at a time (sequential)

Copy each destination fully before the next. Gentler on a shared bus or hard
drives, but re-reads the source once per destination.

Each destination still gets one sealed ASC-format MHL per source root, and a
failed drive can be repaired without restarting the others.

---

## Setup

1. Add multiple destinations in **Save To** (drag drives or click **Add another destination**)
2. Pick the **Copy mode** in Options (default **Automatic** is usually right)
3. Drag destinations to reorder

---

## Behavior

- Each destination card shows its own progress bar, percent, bytes copied / total, speed, ETA, and verify phase
- A drive that needs extra care to write safely (typically exFAT, USB HDDs, some externals) shows an orange **DO NOT UNPLUG** badge while active
- Verification of one file overlaps the copy of the next (see [Copy Engines](./copy-engines.md#verify-pipeline))
- If one destination fails, the others continue
- When the run finishes with at least one failed destination, the **Retry repair panel** appears under the progress

---

## Repair after a failure

If a drive fails mid-job, you don't have to start over. After the run, the failed row has a **Retry** button. Pressing it opens the repair sheet:

- **From source**, if the original source(s) are still mounted, FilmCan re-runs the fan-out engine for that single drive.
- **From sibling**, FilmCan reads the verified neighbor drive's MHL, copies each listed file to the failed drive, and hash-verifies as it goes. The source card no longer needs to be mounted. This is the cinema set workflow: keep going, fix the drive at lunch.

The **From sibling** option only enables when at least one other destination from the same job succeeded.

---

## Drive speed warning

If FilmCan detects that destinations have very different expected throughputs (e.g. one Thunderbolt SSD and one USB-2 HDD), it shows a heads-up, the slow drive will pace the whole job in fan-out mode. The warning is informational; the copy proceeds.

---

## Related

- [Copy Engines](./copy-engines.md)
- [Hash Lists](./hash-lists.md)
- [Stop](./stop.md)
- [Push Notifications](./push-notifications.md)

<!-- lang:fr -->
# Backups vers plusieurs destinations

Sauvegardez vers plusieurs destinations pour la redondance. Le FilmCan Engine lit la
source **une seule fois** et écrit vers toutes les destinations ensemble ; l'option
**Copy mode** choisit comment ces écritures sont programmées.

---

## Copy mode

Défini dans **Backup Editor → Options → Copy mode**.

### Automatique *(par défaut)*

FilmCan choisit par run : **parallèle** quand les destinations sont des SSD distincts, et
**séquentiel** quand une destination est un volume réseau ou que deux destinations se trouvent sur
le même volume physique (les écritures parallèles sur un seul lecteur le surchargentt). Il ne
prend **pas** en compte le flag "solid state" du système, qui est peu fiable pour les
SSD externes USB ou Thunderbolt.

### Toutes les destinations à la fois (parallèle)

La source est lue une fois et diffusée vers toutes les destinations en parallèle. Le débit
est limité par le lecteur le plus lent, les autres chevauchent leurs écritures. Un seul passage de lecture par
source quel que soit le nombre de destinations.

### Une destination à la fois (séquentiel)

Copier chaque destination complètement avant la suivante. Plus doux pour un bus partagé ou les
disques durs, mais relit la source une fois par destination.

Chaque destination reçoit toujours un MHL au format ASC scellé par racine source, et un
lecteur défaillant peut être réparé sans redémarrer les autres.

---

## Configuration

1. Ajoutez plusieurs destinations dans **Save To** (glissez les lecteurs ou cliquez sur **Add another destination**)
2. Choisissez le **Copy mode** dans Options (le **Automatique** par défaut est généralement correct)
3. Glissez les destinations pour les réorganiser

---

## Comportement

- Chaque carte de destination affiche sa propre barre de progression, son pourcentage, les octets copiés / total, la vitesse, l'ETA et la phase de vérification
- Un lecteur qui nécessite une attention particulière pour l'écriture sécurisée (généralement exFAT, USB HDD, certains externes) affiche un badge orange **DO NOT UNPLUG** pendant qu'il est actif
- La vérification d'un fichier chevauche la copie du suivant (voir [Copy Engines](./copy-engines.md#verify-pipeline))
- Si une destination échoue, les autres continuent
- Quand la run s'achève avec au moins une destination défaillante, le **panneau de réparation de réessai** apparaît sous la progression

---

## Réparation après un échec

Si un lecteur échoue au milieu du travail, vous n'avez pas besoin de recommencer. Après la run, la ligne défaillante a un bouton **Retry**. En appuyant dessus, la feuille de réparation s'ouvre :

- **From source**, si la ou les source(s) d'origine sont toujours montées, FilmCan relance le moteur fan-out pour ce seul lecteur.
- **From sibling**, FilmCan lit le MHL du lecteur voisin vérifié, copie chaque fichier listé vers le lecteur défaillant et vérifie par hash à mesure que cela avance. La carte source n'a plus besoin d'être montée. C'est le flux de travail du plateau de cinéma : continuez, réparez le lecteur à midi.

L'option **From sibling** ne s'active que quand au moins une autre destination de la même tâche a réussi.

---

## Avertissement de vitesse du lecteur

Si FilmCan détecte que les destinations ont des débits attendus très différents (par exemple, un SSD Thunderbolt et un HDD USB-2), il affiche un avertissement, le lecteur lent déterminera le rythme de toute la tâche en mode fan-out. L'avertissement est informatif ; la copie continue.

---

## Connexes

- [Copy Engines](./copy-engines.md)
- [Hash Lists](./hash-lists.md)
- [Stop](./stop.md)
- [Push Notifications](./push-notifications.md)

<!-- lang:de -->
# Backups auf mehreren Zielen

Sichern Sie auf mehrere Ziele für Redundanz. Das FilmCan Engine liest die
Quelle **einmal** und schreibt auf alle Ziele zusammen; die Option **Copy mode**
bestimmt, wie diese Schreibvorgänge geplant werden.

---

## Copy mode

Eingestellt in **Backup Editor → Options → Copy mode**.

### Automatisch *(Standard)*

FilmCan wählt pro Run: **parallel**, wenn die Ziele unterschiedliche SSDs sind, und
**sequenziell**, wenn ein Ziel ein Netzwerk-Volume ist oder zwei Ziele auf demselben
physischen Volume liegen (parallele Schreibvorgänge auf einem Laufwerk überlasten es). Es
wird **nicht** vom "solid state"-Flag des Betriebssystems abhängig gemacht, was für externe
USB-/Thunderbolt-SSDs unzuverlässig ist.

### Alle Ziele gleichzeitig (parallel)

Die Quelle wird einmal gelesen und parallel an alle Ziele übertragen. Der Durchsatz wird
durch das langsamste Laufwerk bestimmt, die anderen überlappen ihre Schreibvorgänge. Ein
Lesepass pro Quelle, unabhängig von der Anzahl der Ziele.

### Ein Ziel nach dem anderen (sequenziell)

Kopieren Sie jedes Ziel vollständig, bevor Sie zum nächsten übergehen. Sanfter für einen
gemeinsamen Bus oder Festplatten, liest aber die Quelle einmal pro Ziel erneut.

Jedes Ziel erhält weiterhin ein versiegeltes ASC-Format-MHL pro Quellwurzel, und ein
ausgefallenes Laufwerk kann repariert werden, ohne die anderen neu zu starten.

---

## Einrichtung

1. Fügen Sie mehrere Ziele in **Save To** hinzu (Laufwerke ziehen oder auf **Add another destination** klicken)
2. Wählen Sie den **Copy mode** in Options (Standard **Automatisch** ist normalerweise richtig)
3. Ziehen Sie Ziele, um sie neu zu ordnen

---

## Verhalten

- Jede Zielkarte zeigt ihre eigene Fortschrittsleiste, Prozentsatz, kopierte Bytes / Gesamt, Geschwindigkeit, ETA und Verifizierungsphase
- Ein Laufwerk, das besondere Sorgfalt beim sicheren Schreiben erfordert (normalerweise exFAT, USB-Festplatten, einige externe), zeigt ein oranges **DO NOT UNPLUG**-Badge während es aktiv ist
- Die Verifizierung einer Datei überlappt die Kopie der nächsten (siehe [Copy Engines](./copy-engines.md#verify-pipeline))
- Wenn ein Ziel fehlschlägt, fahren die anderen fort
- Wenn der Run mit mindestens einem fehlgeschlagenen Ziel endet, erscheint das **Retry-Reparaturfeld** unter dem Fortschritt

---

## Reparatur nach einem Fehler

Wenn ein Laufwerk mitten im Job ausfällt, müssen Sie nicht von vorne beginnen. Nach dem Run hat die fehlerhafte Zeile eine **Retry**-Schaltfläche. Drücken Sie sie, um das Reparaturblatt zu öffnen:

- **From source**, wenn die Original-Quelle(n) noch eingebunden ist/sind, startet FilmCan das Fan-Out-Engine für dieses einzelne Laufwerk erneut.
- **From sibling**, FilmCan liest die MHL des verifizierten Nachbarlaufwerks, kopiert jede aufgelistete Datei auf das fehlerhafte Laufwerk und verifiziert per Hash. Die Quellkarte muss nicht mehr eingebunden sein. Dies ist der Workflow für Filmsets: weitermachen, Laufwerk bei Mittag reparieren.

Die **From sibling**-Option wird nur aktiviert, wenn mindestens ein anderes Ziel aus demselben Job erfolgreich war.

---

## Warnung zu Laufwerksgeschwindigkeit

Wenn FilmCan feststellt, dass Ziele sehr unterschiedliche erwartete Durchsätze haben (z. B. eine Thunderbolt-SSD und eine USB-2-Festplatte), zeigt es eine Warnung an, das langsame Laufwerk bestimmt den Rhythmus des gesamten Jobs im Fan-Out-Modus. Die Warnung ist informativ, die Kopie wird fortgesetzt.

---

## Verwandte

- [Copy Engines](./copy-engines.md)
- [Hash Lists](./hash-lists.md)
- [Stop](./stop.md)
- [Push Notifications](./push-notifications.md)

<!-- lang:es -->
# Backups en múltiples destinos

Haga backup a múltiples destinos para redundancia. El FilmCan Engine lee la
fuente **una vez** y escribe en todos los destinos juntos; la opción **Copy mode**
elige cómo se programan esas escrituras.

---

## Copy mode

Establecido en **Backup Editor → Options → Copy mode**.

### Automático *(predeterminado)*

FilmCan elige por ejecución: **paralelo** cuando los destinos son SSD distintos, y
**secuencial** cuando un destino es un volumen de red o dos destinos residen en
el mismo volumen físico (las escrituras paralelas en una unidad la saturan). **No**
se basa en la bandera "solid state" del SO, que no es confiable para SSD
externos USB/Thunderbolt.

### Todos los destinos a la vez (paralelo)

La fuente se lee una vez y se transmite a todos los destinos en paralelo. El rendimiento
está limitado por la unidad más lenta, las otras superponen sus escrituras. Un pase de lectura por
fuente independientemente del número de destinos.

### Un destino a la vez (secuencial)

Copie cada destino completamente antes del siguiente. Más suave en un bus compartido o
discos duros, pero relee la fuente una vez por destino.

Cada destino recibe un MHL en formato ASC sellado por raíz de fuente, y un
disco que falla se puede reparar sin reiniciar los demás.

---

## Configuración

1. Agregue múltiples destinos en **Save To** (arrastre unidades o haga clic en **Add another destination**)
2. Elija el **Copy mode** en Options (el **Automático** predeterminado suele ser correcto)
3. Arrastre los destinos para reordenarlos

---

## Comportamiento

- Cada tarjeta de destino muestra su propia barra de progreso, porcentaje, bytes copiados / total, velocidad, ETA y fase de verificación
- Una unidad que requiere cuidado especial para escribir de forma segura (generalmente exFAT, USB HDD, algunos externos) muestra una insignia naranja **DO NOT UNPLUG** mientras está activa
- La verificación de un archivo se superpone a la copia del siguiente (ver [Copy Engines](./copy-engines.md#verify-pipeline))
- Si un destino falla, los otros continúan
- Cuando la ejecución termina con al menos un destino fallido, aparece el **panel de reparación de reintento** bajo el progreso

---

## Reparación después de un fallo

Si una unidad falla a mitad del trabajo, no tiene que empezar de nuevo. Después de la ejecución, la fila fallida tiene un botón **Retry**. Al presionarlo, se abre la hoja de reparación:

- **From source**, si la(s) fuente(s) original(es) todavía está(n) montada(s), FilmCan reexecuta el motor fan-out para esa unidad individual.
- **From sibling**, FilmCan lee el MHL de la unidad vecina verificada, copia cada archivo listado a la unidad fallida y verifica por hash a medida que avanza. La tarjeta de fuente ya no necesita estar montada. Este es el flujo de trabajo del set de cine: continúe, repare la unidad al mediodía.

La opción **From sibling** solo se activa cuando al menos otro destino del mismo trabajo tuvo éxito.

---

## Advertencia de velocidad de unidad

Si FilmCan detecta que los destinos tienen rendimientos esperados muy diferentes (por ejemplo, una SSD Thunderbolt y una HDD USB-2), muestra una advertencia, la unidad lenta marcará el ritmo de todo el trabajo en modo fan-out. La advertencia es informativa, la copia continúa.

---

## Relacionado

- [Copy Engines](./copy-engines.md)
- [Hash Lists](./hash-lists.md)
- [Stop](./stop.md)
- [Push Notifications](./push-notifications.md)
