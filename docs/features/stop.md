<!-- lang:en -->
# Stop & Resume

Stop a backup and continue later without re-copying what's already done.

---

## Stop

- Click **Stop Backup** (or **Stop Backups**) during a transfer.
- The stop is clean: the file being written is aborted **before** it's finalized,
  so no half-written file is left at the destination. A *"Stopping the backup(s)
  properly…"* indicator shows while the engine finishes aborting.

---

## Resume

- Select the backup and click **Run Now** again.
- Files already recorded in **every** destination's hash list **and** still
  present on disk are skipped. Only the remaining files are copied. The progress
  row reads *"Resuming, N already backed up, copying the rest."*
- A file that was deleted from a destination is re-copied (presence is checked,
  not just the hash list).
- **Force re-copy** (Options) ignores all of this and re-copies everything.

If the whole backup is already present when you press Run, no new history card is
created, an **Already backed up** popup appears instead, with a **Verify data**
button (the same hash-list check as History's *Check data*).

> Caveat: with a `{date}` folder template, resuming on a *different day* re-copies
> into that day's folder (earlier files aren't matched). Use Force re-copy to be
> explicit.

---

## Related

- [Copy Engines](./copy-engines.md)
- [Transfer History](./transfer-history.md)

<!-- lang:fr -->
# Arrêt et reprise

Arrêtez un backup et continuez plus tard sans recopier ce qui est déjà fait.

---

## Arrêt

- Cliquez sur **Stop Backup** (ou **Stop Backups**) pendant un transfert.
- L'arrêt est propre : le fichier en cours d'écriture est interrompu **avant** d'être finalisé,
  de sorte qu'aucun fichier partiellement écrit n'est laissé à la destination. Un indicateur
  *"Stopping the backup(s) properly…"* s'affiche pendant que le moteur termine l'interruption.

---

## Reprise

- Sélectionnez le backup et cliquez à nouveau sur **Run Now**.
- Les fichiers déjà enregistrés dans la liste de hash **de toutes** les destinations **et** toujours
  présents sur le disque sont ignorés. Seuls les fichiers restants sont copiés. La ligne de progression
  lit *"Resuming, N already backed up, copying the rest."*
- Un fichier qui a été supprimé d'une destination est re-copié (la présence est vérifiée,
  pas seulement la liste de hash).
- **Force re-copy** (Options) ignore tout cela et recopie tout.

Si le backup complet est déjà présent quand vous appuyez sur Run, aucune nouvelle carte d'historique n'est
créée, une popup **Already backed up** s'affiche à la place, avec un bouton **Verify data**
(la même vérification de liste de hash que *Check data* de l'historique).

> Caveat : avec un modèle de dossier `{date}`, la reprise sur un *jour différent* recopie
> dans le dossier de ce jour (les fichiers antérieurs ne correspondent pas). Utilisez Force re-copy pour être
> explicite.

---

## Connexes

- [Copy Engines](./copy-engines.md)
- [Transfer History](./transfer-history.md)

<!-- lang:de -->
# Stop & Resume

Stoppen Sie ein backup und setzen Sie es später fort, ohne das Bereits fertige neu zu kopieren.

---

## Stop

- Klicken Sie während einer Übertragung auf **Stop Backup** (oder **Stop Backups**).
- Der Stop ist sauber: die Datei, die geschrieben wird, wird **vor** der Finalisierung abgebrochen,
  so dass keine halb geschriebene Datei am Ziel verbleibt. Ein *"Stopping the backup(s)
  properly…"*-Indikator wird angezeigt, während das Motor die Abbruchbeendigung beendet.

---

## Resume

- Wählen Sie das backup aus und klicken Sie erneut auf **Run Now**.
- Dateien, die bereits in der Hash-Liste **aller** Ziele **und** noch vorhanden sind
  auf der Festplatte werden übersprungen. Nur die verbleibenden Dateien werden kopiert. Die Fortschrittszeile
  liest *"Resuming, N already backed up, copying the rest."*
- Eine Datei, die aus einem Ziel gelöscht wurde, wird neu kopiert (das Vorhandensein wird überprüft,
  nicht nur die Hash-Liste).
- **Force re-copy** (Options) ignoriert alles dies und kopiert erneut.

Wenn das ganze backup bereits vorhanden ist, wenn Sie auf Run drücken, wird keine neue Historienkarte
erstellt, stattdessen erscheint ein **Already backed up**-Popup mit einer **Verify data**-Schaltfläche
(dieselbe Hash-Listen-Überprüfung wie History's *Check data*).

> Caveat: Mit einer `{date}`-Ordnervorlage führt die Wiederaufnahme an einem *anderen Tag* zu einem Neukopieren
> in den Ordner dieses Tages (frühere Dateien werden nicht abgeglichen). Verwenden Sie Force re-copy, um explizit zu sein.

---

## Verwandte

- [Copy Engines](./copy-engines.md)
- [Transfer History](./transfer-history.md)

<!-- lang:es -->
# Detener y reanudar

Detenga un backup y continúe más tarde sin volver a copiar lo que ya está hecho.

---

## Detener

- Haga clic en **Stop Backup** (o **Stop Backups**) durante una transferencia.
- La parada es limpia: el archivo que se está escribiendo se aborta **antes** de finalizarse,
  por lo que no hay ningún archivo parcialmente escrito en el destino. Un indicador
  *"Stopping the backup(s) properly…"* se muestra mientras el motor termina el aborto.

---

## Reanudar

- Seleccione el backup y haga clic en **Run Now** nuevamente.
- Los archivos ya registrados en la lista de hash **de todos** los destinos **y** aún
  presentes en el disco se omiten. Solo se copian los archivos restantes. La fila de progreso
  lee *"Resuming, N already backed up, copying the rest."*
- Un archivo que fue eliminado de un destino se vuelve a copiar (se verifica la presencia,
  no solo la lista de hash).
- **Force re-copy** (Options) ignora todo esto y vuelve a copiar todo.

Si el backup completo ya está presente cuando presiona Ejecutar, no se crea ninguna tarjeta de historial nueva,
aparece un popup **Already backed up**, con un botón **Verify data**
(la misma verificación de lista de hash que *Check data* de History).

> Caveat: con una plantilla de carpeta `{date}`, reanudar en un *día diferente* vuelve a copiar
> en la carpeta de ese día (los archivos anteriores no coinciden). Utilice Force re-copy para ser
> explícito.

---

## Relacionado

- [Copy Engines](./copy-engines.md)
- [Transfer History](./transfer-history.md)
