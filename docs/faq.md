<!-- lang:en -->
# FAQ

---

## Basics

**What is FilmCan?**  
Professional backup for camera cards. Copies to multiple drives with optional hash verification.

**Is it free?**  
Yes. GPL-3.0 licensed.

**Supported macOS?**  
13.0 (Ventura) and later.

---

## Compatibility

**Does it work with my camera?**  
It should work with any camera that mounts as storage (RED, ARRI, Sony, Canon, Panasonic, Blackmagic, GoPro, etc.).

**Network drives?**  
Not officially supported. Local drives are recommended.

---

## Verification

**How do I verify backups?**  
Choose a Verification mode in Options, `Fast` (default) checks the hash computed during the copy; `Paranoid` re-reads every file from disk. FilmCan uses xxHash128.

**Can I stop and resume?**  
Yes. Stop is clean (no partial files), and running again skips files already backed up to every destination and still present, only the rest is copied. See [Stop & Resume](./features/stop.md).

**Hash lists?**  
Yes. Created automatically unless Verification is Off. See [Hash Lists](./features/hash-lists.md).

---

## Organization

**Organize by date?**  
Yes. Use [Destination Presets](./features/destination-presets.md).

**Shoot past midnight?**  
Use [Smart Date](./features/smart-date.md) to set a custom day boundary.

---

## Technical

**Which copy engine?**  
The FilmCan Engine handles every backup. (rsync was retired from the UI in 1.2.0.) See [Copy Engines](./features/copy-engines.md).

**Config location?**  
`~/Library/Application Support/FilmCan/configs.json`  
`~/Library/Application Support/FilmCan/presets.json`  
`~/Library/Application Support/FilmCan/history.json`

**Will I lose data if I reinstall or upgrade?**  
No, not in normal reinstall/upgrade flows. FilmCan keeps movies, presets, and history in `~/Library/Application Support/FilmCan/`, outside the app bundle.  
If you use cleanup tools that remove Application Support, data can be deleted.

**Does it upload anything?**  
No file uploads. Transfers stay local; optional notifications (ntfy/webhook) only send status metadata.

---

## Troubleshooting

**Can't access files**  
Enable Full Disk Access:  
**System Settings** > **Privacy & Security** > **Full Disk Access**

**Slow or failed backup**  
See [Troubleshooting](./troubleshooting.md).

**Report a bug**  
See [Report a bug](https://github.com/qtld88/FilmCan/issues) for bug reporting.

---

## See Also

- [Quick Start](./quickstart.md)
- [Troubleshooting](./troubleshooting.md)
- [Support](/#support)

<!-- lang:fr -->
# FAQ

---

## Bases

**Qu'est-ce que FilmCan?**  
Backup professionnel pour cartes de caméra. Copie vers plusieurs disques avec vérification de hachage facultative.

**Est-ce gratuit?**  
Oui. Sous licence GPL-3.0.

**macOS pris en charge?**  
13.0 (Ventura) et versions ultérieures.

---

## Compatibilité

**Fonctionne-t-il avec ma caméra?**  
Il devrait fonctionner avec toute caméra qui se monte comme stockage (RED, ARRI, Sony, Canon, Panasonic, Blackmagic, GoPro, etc.).

**Disques réseau?**  
Non officiellement pris en charge. Les disques locaux sont recommandés.

---

## Vérification

**Comment vérifier les backups?**  
Choisissez un mode de vérification dans Options, `Fast` (par défaut) vérifie le hachage calculé lors de la copie; `Paranoid` relit chaque fichier du disque. FilmCan utilise xxHash128.

**Puis-je arrêter et reprendre?**  
Oui. L'arrêt est propre (pas de fichiers partiels), et l'exécution ultérieure ignore les fichiers déjà sauvegardés sur toutes les destinations et toujours présents, seul le reste est copié. Voir [Arrêt et reprise](./features/stop.md).

**Listes de hachage?**  
Oui. Créées automatiquement sauf si la vérification est désactivée. Voir [Listes de hachage](./features/hash-lists.md).

---

## Organisation

**Organiser par date?**  
Oui. Utilisez [Présets de destination](./features/destination-presets.md).

**Tournage après minuit?**  
Utilisez [Smart Date](./features/smart-date.md) pour définir une limite de jour personnalisée.

---

## Technique

**Quel moteur de copie?**  
Le moteur FilmCan gère tous les backups. (rsync a été retiré de l'interface utilisateur dans la version 1.2.0.) Voir [Moteurs de copie](./features/copy-engines.md).

**Emplacement de la configuration?**  
`~/Library/Application Support/FilmCan/configs.json`  
`~/Library/Application Support/FilmCan/presets.json`  
`~/Library/Application Support/FilmCan/history.json`

**Vais-je perdre les données si je réinstalle ou mets à jour?**  
Non, pas lors de flux de réinstallation/mise à jour normaux. FilmCan conserve les films, les présets et l'historique dans `~/Library/Application Support/FilmCan/`, en dehors du bundle d'application.  
Si vous utilisez des outils de nettoyage qui suppriment Application Support, les données peuvent être supprimées.

**Télécharge-t-elle quelque chose?**  
Pas de téléchargements de fichiers. Les transferts restent locaux; les notifications facultatives (ntfy/webhook) n'envoient que des métadonnées d'état.

---

## Dépannage

**Impossible d'accéder aux fichiers**  
Activer l'accès au disque complet:  
**System Settings** > **Privacy & Security** > **Full Disk Access**

**Backup lent ou échoué**  
Voir [Dépannage](./troubleshooting.md).

**Signaler un bug**  
Voir [Signaler un bug](https://github.com/qtld88/FilmCan/issues) pour le signalement des bugs.

---

## Voir aussi

- [Démarrage rapide](./quickstart.md)
- [Dépannage](./troubleshooting.md)
- [Support](/#support)

<!-- lang:de -->
# Häufig gestellte Fragen

---

## Grundlagen

**Was ist FilmCan?**  
Professionelle Sicherung für Speicherkarten. Kopiert auf mehrere Laufwerke mit optionaler Hash-Verifizierung.

**Ist es kostenlos?**  
Ja. Unter GPL-3.0 lizenziert.

**Unterstütztes macOS?**  
13.0 (Ventura) und später.

---

## Kompatibilität

**Funktioniert es mit meiner Kamera?**  
Es sollte mit jeder Kamera funktionieren, die als Speicher angehängt wird (RED, ARRI, Sony, Canon, Panasonic, Blackmagic, GoPro, etc.).

**Netzlaufwerke?**  
Nicht offiziell unterstützt. Lokale Laufwerke werden empfohlen.

---

## Verifizierung

**Wie überprüfe ich Backups?**  
Wählen Sie einen Verifizierungsmodus in Options, `Fast` (Standard) überprüft den während der Kopie berechneten Hash; `Paranoid` liest jede Datei erneut von der Festplatte. FilmCan verwendet xxHash128.

**Kann ich anhalten und fortsetzen?**  
Ja. Der Stopp ist sauber (keine Teildateien), und das erneute Ausführen überspringt Dateien, die bereits auf alle Ziele gesichert wurden und immer noch vorhanden sind, nur der Rest wird kopiert. Siehe [Stop & Resume](./features/stop.md).

**Hash-Listen?**  
Ja. Automatisch erstellt, wenn die Verifizierung nicht ausgeschaltet ist. Siehe [Hash-Listen](./features/hash-lists.md).

---

## Organisation

**Nach Datum organisieren?**  
Ja. Verwenden Sie [Zielvoreinstellungen](./features/destination-presets.md).

**Nach Mitternacht drehen?**  
Verwenden Sie [Smart Date](./features/smart-date.md), um eine benutzerdefinierte Tagesgrenze festzulegen.

---

## Technisch

**Welcher Kopiermechanismus?**  
Die FilmCan Engine verwaltet jede Sicherung. (rsync wurde in Version 1.2.0 aus der Benutzeroberfläche entfernt.) Siehe [Kopiermechanismen](./features/copy-engines.md).

**Konfigurationsort?**  
`~/Library/Application Support/FilmCan/configs.json`  
`~/Library/Application Support/FilmCan/presets.json`  
`~/Library/Application Support/FilmCan/history.json`

**Verliere ich Daten, wenn ich neu installiere oder aktualisiere?**  
Nein, nicht bei normalen Neuinstallations-/Aktualisierungsflüssen. FilmCan speichert Filme, Voreinstellungen und Verlauf in `~/Library/Application Support/FilmCan/`, außerhalb des App-Bundles.  
Wenn Sie Bereinigungstools verwenden, die Application Support entfernen, können Daten gelöscht werden.

**Lädt sie etwas hoch?**  
Keine Datei-Uploads. Transfers bleiben lokal; optionale Benachrichtigungen (ntfy/webhook) senden nur Statusmetadaten.

---

## Fehlerbehebung

**Auf Dateien kann nicht zugegriffen werden**  
Aktivieren Sie Full Disk Access:  
**System Settings** > **Privacy & Security** > **Full Disk Access**

**Langsame oder fehlgeschlagene Sicherung**  
Siehe [Fehlerbehebung](./troubleshooting.md).

**Fehler melden**  
Siehe [Fehler melden](https://github.com/qtld88/FilmCan/issues) für die Fehlerberichterstattung.

---

## Siehe auch

- [Schnellstart](./quickstart.md)
- [Fehlerbehebung](./troubleshooting.md)
- [Unterstützung](/#support)

<!-- lang:es -->
# Preguntas frecuentes

---

## Conceptos básicos

¿Qué es FilmCan?
Copia de seguridad profesional para tarjetas de cámara. Copia a múltiples unidades con verificación de hash opcional.

¿Es gratis?
Sí. Licencia GPL-3.0.

¿macOS compatible?
13.0 (Ventura) y posterior.

---

## Compatibilidad

¿Funciona con mi cámara?
Debería funcionar con cualquier cámara que se monte como almacenamiento (RED, ARRI, Sony, Canon, Panasonic, Blackmagic, GoPro, etc.).

¿Unidades de red?
No oficialmente compatible. Se recomiendan las unidades locales.

---

## Verificación

¿Cómo verifico las copias de seguridad?
Elija un modo de verificación en Opciones, `Fast` (predeterminado) verifica el hash calculado durante la copia; `Paranoid` relee cada archivo del disco. FilmCan utiliza xxHash128.

¿Puedo detener y reanudar?
Sí. La parada es limpia (sin archivos parciales), y volver a ejecutar omite los archivos ya copias a todos los destinos y aún presentes, solo se copia el resto. Ver [Detener y reanudar](./features/stop.md).

¿Listas de hash?
Sí. Se crean automáticamente a menos que la verificación esté desactivada. Ver [Listas de hash](./features/hash-lists.md).

---

## Organización

¿Organizar por fecha?
Sí. Utilice [Presets de destino](./features/destination-presets.md).

¿Grabar después de la medianoche?
Utilice [Smart Date](./features/smart-date.md) para establecer un límite de día personalizado.

---

## Técnico

¿Cuál es el motor de copia?
El motor FilmCan maneja cada backup. (rsync se retiró de la interfaz de usuario en 1.2.0.) Ver [Motores de copia](./features/copy-engines.md).

¿Ubicación de la configuración?
`~/Library/Application Support/FilmCan/configs.json`
`~/Library/Application Support/FilmCan/presets.json`
`~/Library/Application Support/FilmCan/history.json`

¿Perderé datos si reinstalo o actualizo?
No, no en flujos normales de reinstalación/actualización. FilmCan mantiene películas, presets e historial en `~/Library/Application Support/FilmCan/`, fuera del paquete de la aplicación.
Si utiliza herramientas de limpieza que eliminen Application Support, los datos pueden ser eliminados.

¿Carga algo?
Sin cargas de archivos. Las transferencias se mantienen locales; las notificaciones opcionales (ntfy/webhook) solo envían metadatos de estado.

---

## Solución de problemas

¿No se puede acceder a los archivos?
Habilitar acceso total al disco:
**System Settings** > **Privacy & Security** > **Full Disk Access**

¿Copia de seguridad lenta o fallida?
Ver [Solución de problemas](./troubleshooting.md).

¿Reportar un error?
Ver [Reportar un error](https://github.com/qtld88/FilmCan/issues) para informar de errores.

---

## Ver también

- [Inicio rápido](./quickstart.md)
- [Solución de problemas](./troubleshooting.md)
- [Soporte](/#support)
