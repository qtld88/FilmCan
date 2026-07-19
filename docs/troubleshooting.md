<!-- lang:en -->
# Troubleshooting

Quick fixes for common issues.

For detailed error codes, see [Transfer Errors Reference](./reference/transfer-errors.md).

---

## App Won’t Launch

- Right-click > Open (bypass Gatekeeper)
- Check **System Settings** > **Privacy & Security**
- Re-download the DMG
- Restart your Mac

---

## Permissions

**Can’t access files**  
**System Settings** > **Privacy & Security** > **Full Disk Access** > Add FilmCan

**No notifications**  
**System Settings** > **Notifications** > FilmCan > Enable

**Webhook not working**  
- Check the webhook URL and internet connection
- Verify your endpoint accepts JSON POST requests

---

## Transfer Issues

**Won’t start**  
- Source is mounted and readable
- Destination is writable with free space
- Check safety warnings in the UI

**Error details**  
- During a run, FilmCan shows the failure reason under each destination’s progress bar.  
- After a run, the same reason is stored in Transfer History.

**Stuck or slow**  
- Large files take time (check drive activity)
- Try sequential mode instead of parallel
- Close other disk-intensive apps
- Check cables and drive health

**Incomplete**  
- Check destination has space
- Review the log file at the configured log folder (if logs are enabled)
- Resume or re-run

---

## Sources & Destinations

**Source not detected**  
- Reconnect card reader
- Try another USB port
- Check if mounted: `/Volumes/`

**Destination full**  
- Free up space or use another drive
- Check permissions

**Wrong organization**  
- Verify organization preset settings
- Check Smart Date (Custom date for tokens)

---

## Verification

**Verification failed**
- If using FilmCan Engine with paranoid verify, the failed drive(s) show a **Retry** button under their progress row
- Choose **From sibling** to rebuild the failed drive from a verified neighbor’s MHL (the source card no longer needs to be mounted)
- Choose **From source** if the original card is still mounted and you want a fresh re-copy of just that drive
- For rsync: re-copy the file, run **Disk Utility** > **First Aid**, try another drive
- If re-checking from history passes, this was likely a drive write-cache timing issue, the drive didn’t fully flush before verify ran. If it happens repeatedly on the same drive, check drive health.

**Hash list not found**
- Confirm the destination is mounted and check `<destination>/.filmcan/hashlists/`
- FilmCan Engine writes one MHL per source root (e.g. `CARD_A001.mhl`) aggregating every file
- Re-run the backup to generate a new hash list
- Hash lists are created automatically whenever hash verification is enabled

**"DO NOT UNPLUG" banner stays on**
- Some external/USB drives are flagged as needing a full cache flush before FilmCan trusts the write
- The banner clears once the drive’s verify phase finishes
- If it persists after the run completes, the drive’s cache may not have flushed cleanly, see the os_log warnings in Console.app, filtered to subsystem `com.filmcan.app`

---

## Still Stuck?

- [FAQ](./faq.md)
- [Transfer Errors Reference](./reference/transfer-errors.md)
- [Report a bug](https://github.com/qtld88/FilmCan/issues)

<!-- lang:fr -->
# Dépannage

Correctifs rapides pour les problèmes courants.

Pour les codes d’erreur détaillés, voir [Référence des erreurs de transfert](./reference/transfer-errors.md).

---

## L’application ne démarre pas

- Clic droit > Ouvrir (contourner Gatekeeper)
- Vérifiez **System Settings** > **Privacy & Security**
- Retéléchargez le DMG
- Redémarrez votre Mac

---

## Permissions

**Impossible d’accéder aux fichiers**  
**System Settings** > **Privacy & Security** > **Full Disk Access** > Ajouter FilmCan

**Pas de notifications**  
**System Settings** > **Notifications** > FilmCan > Activer

**Le webhook ne fonctionne pas**  
- Vérifiez l’URL du webhook et la connexion internet
- Vérifiez que votre endpoint accepte les demandes JSON POST

---

## Problèmes de transfert

**Ne démarre pas**  
- La source est montée et lisible
- La destination est accessible en écriture avec de l’espace libre
- Vérifiez les avertissements de sécurité dans l’interface

**Détails des erreurs**  
- Pendant une exécution, FilmCan affiche la raison de l’échec sous la barre de progression de chaque destination.  
- Après une exécution, la même raison est stockée dans l’historique des transferts.

**Bloqué ou lent**  
- Les fichiers volumineux prennent du temps (vérifiez l’activité du disque)
- Essayez le mode séquentiel au lieu du mode parallèle
- Fermez les autres applications gourmandes en disque
- Vérifiez les câbles et la santé du disque

**Incomplète**  
- Vérifiez que la destination a de l’espace
- Consultez le fichier journal dans le dossier journal configuré (si les journaux sont activés)
- Reprenez ou réexécutez

---

## Sources et destinations

**Source non détectée**  
- Reconnectez le lecteur de carte
- Essayez un autre port USB
- Vérifiez si elle est montée: `/Volumes/`

**Destination pleine**  
- Libérez de l’espace ou utilisez un autre disque
- Vérifiez les permissions

**Organisation erronée**  
- Vérifiez les paramètres du préset d’organisation
- Vérifiez Smart Date (Date personnalisée pour les tokens)

---

## Vérification

**Vérification échouée**
- Si vous utilisez FilmCan Engine avec vérification paranoïaque, le ou les disques défaillants affichent un bouton **Retry** sous leur ligne de progression
- Choisissez **From sibling** pour reconstruire le disque défaillant à partir du MHL d’un voisin vérifié (la carte source n’a plus besoin d’être montée)
- Choisissez **From source** si la carte d’origine est toujours montée et que vous souhaitez une re-copie fraîche de ce disque uniquement
- Pour rsync: re-copiez le fichier, exécutez **Disk Utility** > **First Aid**, essayez un autre disque
- Si la re-vérification depuis l’historique réussit, c’était probablement un problème de timing du cache d’écriture du disque, le disque ne s’était pas complètement vidé avant que la vérification ne s’exécute. Si cela se reproduit régulièrement sur le même disque, vérifiez la santé du disque.

**Liste de hachage non trouvée**
- Confirmez que la destination est montée et vérifiez `<destination>/.filmcan/hashlists/`
- FilmCan Engine écrit un MHL par racine de source (par exemple `CARD_A001.mhl`) en agrégeant chaque fichier
- Re-exécutez le backup pour générer une nouvelle liste de hachage
- Les listes de hachage sont créées automatiquement chaque fois que la vérification de hachage est activée

**La bannière "DO NOT UNPLUG" reste affichée**
- Certains disques externes/USB sont signalés comme ayant besoin d’un vidage complet du cache avant que FilmCan ne fasse confiance à l’écriture
- La bannière s’efface une fois la phase de vérification du disque terminée
- Si elle persiste après la fin de l’exécution, le cache du disque n’a peut-être pas été vidé correctement. Consultez les avertissements os_log dans Console.app, filtrés par le sous-système `com.filmcan.app`

---

## Toujours bloqué?

- [FAQ](./faq.md)
- [Référence des erreurs de transfert](./reference/transfer-errors.md)
- [Signaler un bug](https://github.com/qtld88/FilmCan/issues)

<!-- lang:de -->
# Fehlerbehebung

Schnelle Behebungen für häufige Probleme.

Detaillierte Fehlercodes finden Sie unter [Übertragungsfehler-Referenz](./reference/transfer-errors.md).

---

## App startet nicht

- Rechtsklick > Öffnen (Gatekeeper umgehen)
- Überprüfen Sie **System Settings** > **Privacy & Security**
- DMG erneut herunterladen
- Mac neu starten

---

## Berechtigungen

**Auf Dateien kann nicht zugegriffen werden**  
**System Settings** > **Privacy & Security** > **Full Disk Access** > FilmCan hinzufügen

**Keine Benachrichtigungen**  
**System Settings** > **Notifications** > FilmCan > Aktivieren

**Webhook funktioniert nicht**  
- Überprüfen Sie die Webhook-URL und die Internetverbindung
- Stellen Sie sicher, dass Ihr Endpunkt JSON POST-Anfragen akzeptiert

---

## Übertragungsprobleme

**Startet nicht**  
- Quelle ist angehängt und lesbar
- Ziel ist schreibbar mit freiem Speicher
- Überprüfen Sie Sicherheitswarnungen in der Benutzeroberfläche

**Fehlerdetails**  
- Während einer Ausführung zeigt FilmCan den Ausfallgrund unter der Fortschrittsleiste jedes Ziels an.  
- Nach einer Ausführung wird der gleiche Grund im Übertragungsverlauf gespeichert.

**Stecken geblieben oder langsam**  
- Große Dateien brauchen Zeit (Laufwerkaktivität prüfen)
- Versuchen Sie den sequenziellen Modus statt des parallelen Modus
- Schließen Sie andere speicherintensive Anwendungen
- Überprüfen Sie Kabel und Laufwerkgesundheit

**Unvollständig**  
- Überprüfen Sie, ob das Ziel Platz hat
- Überprüfen Sie die Protokolldatei im konfigurierten Protokollordner (falls Protokolle aktiviert sind)
- Fortsetzen oder erneut ausführen

---

## Quellen und Ziele

**Quelle nicht erkannt**  
- Kartenlesen erneut anschließen
- Versuchen Sie einen anderen USB-Anschluss
- Überprüfen Sie, ob angehängt: `/Volumes/`

**Ziel voll**  
- Speicherplatz freigeben oder ein anderes Laufwerk verwenden
- Überprüfen Sie Berechtigungen

**Falsche Organisation**  
- Überprüfen Sie die Voreinstellungen der Organisation
- Überprüfen Sie Smart Date (Benutzerdatum für Tokens)

---

## Verifizierung

**Verifizierung fehlgeschlagen**
- Wenn Sie die FilmCan Engine mit paranoider Verifizierung verwenden, zeigen die fehlgeschlagenen Laufwerke eine **Retry**-Schaltfläche unter ihrer Fortschrittsreihe an
- Wählen Sie **From sibling**, um das fehlgeschlagene Laufwerk aus dem MHL eines verifizierten Nachbarn neu zu erstellen (die Quellkarte muss nicht mehr angehängt sein)
- Wählen Sie **From source**, wenn die ursprüngliche Karte noch angehängt ist und Sie eine frische Neukopie nur für dieses Laufwerk möchten
- Für rsync: Datei erneut kopieren, **Disk Utility** > **First Aid** ausführen, ein anderes Laufwerk versuchen
- Wenn die Neuüberprüfung aus dem Verlauf erfolgreich ist, war dies wahrscheinlich ein Timing-Problem beim Schreib-Cache des Laufwerks, das Laufwerk wurde nicht vollständig geleert, bevor die Verifizierung ausgeführt wurde. Wenn dies wiederholt auf dem gleichen Laufwerk passiert, überprüfen Sie die Laufwerkgesundheit.

**Hash-Liste nicht gefunden**
- Bestätigen Sie, dass das Ziel angehängt ist und überprüfen Sie `<destination>/.filmcan/hashlists/`
- FilmCan Engine schreibt ein MHL pro Quelle Root (z.B. `CARD_A001.mhl`), das alle Dateien zusammenfasst
- Führen Sie das backup erneut aus, um eine neue Hash-Liste zu generieren
- Hash-Listen werden automatisch erstellt, wenn eine Hash-Verifizierung aktiviert ist

**Banner "DO NOT UNPLUG" bleibt aktiv**
- Einige externe/USB-Laufwerke sind gekennzeichnet, da sie einen vollständigen Cache-Flush benötigen, bevor FilmCan den Schreibvorgang vertraut
- Das Banner wird gelöscht, wenn die Verifizierungsphase des Laufwerks beendet ist
- Wenn es nach Abschluss der Ausführung bestehen bleibt, wurde der Cache des Laufwerks möglicherweise nicht ordnungsgemäß geleert. Sehen Sie sich die os_log-Warnungen in Console.app an, gefiltert nach dem Subsystem `com.filmcan.app`

---

## Immer noch festgefahren?

- [FAQ](./faq.md)
- [Übertragungsfehler-Referenz](./reference/transfer-errors.md)
- [Fehler melden](https://github.com/qtld88/FilmCan/issues)

<!-- lang:es -->
# Solución de problemas

Correcciones rápidas para problemas comunes.

Para códigos de error detallados, consulte [Referencia de errores de transferencia](./reference/transfer-errors.md).

---

## La aplicación no se inicia

- Clic derecho > Abrir (omitir Gatekeeper)
- Compruebe **System Settings** > **Privacy & Security**
- Descargue nuevamente el DMG
- Reinicie su Mac

---

## Permisos

**No se puede acceder a los archivos**  
**System Settings** > **Privacy & Security** > **Full Disk Access** > Agregar FilmCan

**Sin notificaciones**  
**System Settings** > **Notifications** > FilmCan > Habilitar

**El webhook no funciona**  
- Compruebe la URL del webhook y la conexión a Internet
- Verifique que su endpoint acepte solicitudes POST JSON

---

## Problemas de transferencia

**No comienza**  
- El origen está montado y es legible
- El destino es escribible con espacio libre
- Compruebe las advertencias de seguridad en la interfaz

**Detalles del error**  
- Durante una ejecución, FilmCan muestra el motivo del fallo debajo de la barra de progreso de cada destino.  
- Después de una ejecución, el mismo motivo se almacena en el historial de transferencias.

**Atascado o lento**  
- Los archivos grandes toman tiempo (compruebe la actividad del disco)
- Intente el modo secuencial en lugar del modo paralelo
- Cierre otras aplicaciones que usen muchos recursos de disco
- Compruebe los cables y la salud del disco

**Incompleta**  
- Compruebe que el destino tiene espacio
- Revise el archivo de registro en la carpeta de registro configurada (si los registros están habilitados)
- Reanude o vuelva a ejecutar

---

## Orígenes y destinos

**Origen no detectado**  
- Reconecte el lector de tarjetas
- Intente otro puerto USB
- Compruebe si está montado: `/Volumes/`

**Destino lleno**  
- Libere espacio o use otra unidad
- Compruebe los permisos

**Organización incorrecta**  
- Verifique la configuración del preset de organización
- Compruebe Smart Date (Fecha personalizada para tokens)

---

## Verificación

**Verificación fallida**
- Si utiliza FilmCan Engine con verificación paranoica, las unidades fallidas muestran un botón **Retry** debajo de su fila de progreso
- Elija **From sibling** para reconstruir la unidad fallida a partir del MHL de un vecino verificado (la tarjeta de origen ya no necesita estar montada)
- Elija **From source** si la tarjeta original aún está montada y desea una re-copia fresca solo para esa unidad
- Para rsync: re-copie el archivo, ejecute **Disk Utility** > **First Aid**, intente otra unidad
- Si la reverificación desde el historial pasa, probablemente fue un problema de sincronización del cache de escritura de la unidad, la unidad no se vaciaba completamente antes de que se ejecutara la verificación. Si ocurre repetidamente en la misma unidad, compruebe la salud de la unidad.

**Lista de hash no encontrada**
- Confirme que el destino está montado y compruebe `<destination>/.filmcan/hashlists/`
- FilmCan Engine escribe un MHL por raíz de origen (por ejemplo, `CARD_A001.mhl`) agregando cada archivo
- Re-ejecute el backup para generar una nueva lista de hash
- Las listas de hash se crean automáticamente siempre que la verificación de hash está habilitada

**La pancarta "DO NOT UNPLUG" permanece activa**
- Algunas unidades externas/USB están marcadas como necesitando un vaciado completo del cache antes de que FilmCan confíe en la escritura
- La pancarta se borra una vez que se completa la fase de verificación de la unidad
- Si persiste después de que se complete la ejecución, es posible que el cache de la unidad no se haya vaciado correctamente. Consulte las advertencias os_log en Console.app, filtradas al subsistema `com.filmcan.app`

---

¿Aún atascado?

- [FAQ](./faq.md)
- [Referencia de errores de transferencia](./reference/transfer-errors.md)
- [Reportar un problema](https://github.com/qtld88/FilmCan/issues)
