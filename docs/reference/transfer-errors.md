<!-- lang:en -->
# Transfer Errors Reference

This page lists the current user‑facing messages FilmCan emits, based on the app code.

Where messages appear:
- **Validation alerts** before a transfer starts.
- **Destination cards** during/after transfer (`TransferResult.errorMessage`).
- **Warning line** on destination cards (`TransferResult.warningMessage`).
- **History > Check data** alert sheet.

---

## Preflight Validation (Before Transfer)

These are shown as alerts in the Backup Editor:

- `Please add at least one source file or folder`
- `Please add at least one destination folder`
- `Source does not exist: <path>`
- `Permission denied: Cannot read source <name>`
- `Destination is read-only (<format>): <path>`
- `Cannot create destination folder: <path>\n<error>`
- `Permission denied: Cannot write to <name>`

---

## Preflight Space Warning

When destinations do not have enough space, you’ll see one of:

- `Not enough space on <name>.\n\nNeeded: <bytes>\nAvailable: <bytes>\n\nThe backup may fail or be incomplete.`
- `Not enough space on <count> destinations: <names>.\n\nThe backup may fail or be incomplete on these drives.`

---

## Copy and Verify Errors

These are surfaced as destination card errors:

- `Stopped by user`
- `Cancelled by user`
- `Copy failed.`
- `Verification failed for <N> files`
- `Cannot read source file: <path>`
- `Cannot write to destination: <path>`
- `Copy failed: Failed to read source: <error>`
- `Copy failed: Failed to write destination: <error>`
- `Copy failed: Failed to read file for verification: <error>`
- `Copy failed: xxHash128 unavailable. Ensure libxxhash is bundled.`

Warnings:

- `Hash list could not be written: <error>`
- `Could not remove partial file at <path>: <error>`

---

## History > Check Data Messages

- `Failed to read hash list.`
- `Hash list missing for this backup`
- `Hash list not found on disk`
- `Verified <N> file(s). All files match.`
- `Verified <N> file(s). <missing> missing, <mismatched> mismatched.`

<!-- lang:fr -->
# Référence des erreurs de transfert

Cette page répertorie les messages actuels générés par FilmCan auxquels l’utilisateur est confronté, basés sur le code de l’application.

Où les messages apparaissent:
- **Alertes de validation** avant le démarrage d’un transfert.
- **Cartes de destination** pendant/après le transfert (`TransferResult.errorMessage`).
- **Ligne d’avertissement** sur les cartes de destination (`TransferResult.warningMessage`).
- Feuille d’alerte **Historique > Vérifier les données**.

---

## Validation préalable (avant le transfert)

Celles-ci sont affichées sous forme d’alertes dans l’éditeur de backup:

- `Please add at least one source file or folder`
- `Please add at least one destination folder`
- `Source does not exist: <path>`
- `Permission denied: Cannot read source <name>`
- `Destination is read-only (<format>): <path>`
- `Cannot create destination folder: <path>\n<error>`
- `Permission denied: Cannot write to <name>`

---

## Avertissement d’espace préalable

Quand les destinations n’ont pas assez d’espace, vous verrez l’un des messages suivants:

- `Not enough space on <name>.\n\nNeeded: <bytes>\nAvailable: <bytes>\n\nThe backup may fail or be incomplete.`
- `Not enough space on <count> destinations: <names>.\n\nThe backup may fail or be incomplete on these drives.`

---

## Erreurs de copie et de vérification

Celles-ci sont affichées sous forme d’erreurs de carte de destination:

- `Stopped by user`
- `Cancelled by user`
- `Copy failed.`
- `Verification failed for <N> files`
- `Cannot read source file: <path>`
- `Cannot write to destination: <path>`
- `Copy failed: Failed to read source: <error>`
- `Copy failed: Failed to write destination: <error>`
- `Copy failed: Failed to read file for verification: <error>`
- `Copy failed: xxHash128 unavailable. Ensure libxxhash is bundled.`

Avertissements:

- `Hash list could not be written: <error>`
- `Could not remove partial file at <path>: <error>`

---

## Historique > Messages de vérification des données

- `Failed to read hash list.`
- `Hash list missing for this backup`
- `Hash list not found on disk`
- `Verified <N> file(s). All files match.`
- `Verified <N> file(s). <missing> missing, <mismatched> mismatched.`

<!-- lang:de -->
# Übertragungsfehler-Referenz

Diese Seite listet die aktuellen benutzerorientierten Meldungen auf, die FilmCan basierend auf dem App-Code ausgibt.

Wo die Meldungen angezeigt werden:
- **Validierungswarnungen** vor dem Start einer Übertragung.
- **Zielkarten** während/nach der Übertragung (`TransferResult.errorMessage`).
- **Warnzeile** auf Zielkarten (`TransferResult.warningMessage`).
- Warnblatt **Verlauf > Daten prüfen**.

---

## Vorflight-Validierung (vor der Übertragung)

Diese werden als Warnungen im Backup-Editor angezeigt:

- `Please add at least one source file or folder`
- `Please add at least one destination folder`
- `Source does not exist: <path>`
- `Permission denied: Cannot read source <name>`
- `Destination is read-only (<format>): <path>`
- `Cannot create destination folder: <path>\n<error>`
- `Permission denied: Cannot write to <name>`

---

## Vorflight-Speicherwarnung

Wenn Ziele nicht genug Speicherplatz haben, sehen Sie einen der folgenden Meldungen:

- `Not enough space on <name>.\n\nNeeded: <bytes>\nAvailable: <bytes>\n\nThe backup may fail or be incomplete.`
- `Not enough space on <count> destinations: <names>.\n\nThe backup may fail or be incomplete on these drives.`

---

## Kopier- und Verifizierungsfehler

Diese werden als Zielkartenfehler angezeigt:

- `Stopped by user`
- `Cancelled by user`
- `Copy failed.`
- `Verification failed for <N> files`
- `Cannot read source file: <path>`
- `Cannot write to destination: <path>`
- `Copy failed: Failed to read source: <error>`
- `Copy failed: Failed to write destination: <error>`
- `Copy failed: Failed to read file for verification: <error>`
- `Copy failed: xxHash128 unavailable. Ensure libxxhash is bundled.`

Warnungen:

- `Hash list could not be written: <error>`
- `Could not remove partial file at <path>: <error>`

---

## Verlauf > Daten prüfen Meldungen

- `Failed to read hash list.`
- `Hash list missing for this backup`
- `Hash list not found on disk`
- `Verified <N> file(s). All files match.`
- `Verified <N> file(s). <missing> missing, <mismatched> mismatched.`

<!-- lang:es -->
# Referencia de errores de transferencia

Esta página enumera los mensajes actuales orientados al usuario que emite FilmCan, basados en el código de la aplicación.

Dónde aparecen los mensajes:
- **Alertas de validación** antes de que comience una transferencia.
- **Tarjetas de destino** durante/después de la transferencia (`TransferResult.errorMessage`).
- **Línea de advertencia** en tarjetas de destino (`TransferResult.warningMessage`).
- Hoja de alerta **Historial > Verificar datos**.

---

## Validación previa (antes de la transferencia)

Se muestran como alertas en el editor de backup:

- `Please add at least one source file or folder`
- `Please add at least one destination folder`
- `Source does not exist: <path>`
- `Permission denied: Cannot read source <name>`
- `Destination is read-only (<format>): <path>`
- `Cannot create destination folder: <path>\n<error>`
- `Permission denied: Cannot write to <name>`

---

## Advertencia de espacio previo

Cuando los destinos no tienen suficiente espacio, verá uno de:

- `Not enough space on <name>.\n\nNeeded: <bytes>\nAvailable: <bytes>\n\nThe backup may fail or be incomplete.`
- `Not enough space on <count> destinations: <names>.\n\nThe backup may fail or be incomplete on these drives.`

---

## Errores de copia y verificación

Se muestran como errores de tarjeta de destino:

- `Stopped by user`
- `Cancelled by user`
- `Copy failed.`
- `Verification failed for <N> files`
- `Cannot read source file: <path>`
- `Cannot write to destination: <path>`
- `Copy failed: Failed to read source: <error>`
- `Copy failed: Failed to write destination: <error>`
- `Copy failed: Failed to read file for verification: <error>`
- `Copy failed: xxHash128 unavailable. Ensure libxxhash is bundled.`

Advertencias:

- `Hash list could not be written: <error>`
- `Could not remove partial file at <path>: <error>`

---

## Historial > Mensajes de verificación de datos

- `Failed to read hash list.`
- `Hash list missing for this backup`
- `Hash list not found on disk`
- `Verified <N> file(s). All files match.`
- `Verified <N> file(s). <missing> missing, <mismatched> mismatched.`
