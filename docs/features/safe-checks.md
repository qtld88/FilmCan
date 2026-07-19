<!-- lang:en -->
# Safe Checks

FilmCan validates setup before each backup to prevent avoidable failures.

---

## What’s Checked

- Source exists and is readable
- Destination exists (or can be created) and is writable
- Destination is not read-only
- Free space (pre‑flight warning)
- Delete confirmation when **Delete files not in source** is enabled
- Log and hash list locations are validated; FilmCan warns if they can’t be created

---

## What You’ll See

Warnings for:
- Low disk space (you can still continue)
- Log file could not be created (FilmCan continues without a log)
- Hash list could not be created (FilmCan continues without a hash list)

Duplicate handling happens during transfer based on your **Duplicate policy**.

---

## Settings

Source and destination validation always runs.  
Duplicate behavior is set in **Options** under **Duplicate policy**.

---

## Related

- [Options](./options.md)
- [Multi-Destination](./multi-destination.md)

<!-- lang:fr -->
# Vérifications de sécurité

FilmCan valide la configuration avant chaque backup pour éviter les défaillances évitables.

---

## Ce qui est vérifié

- La source existe et est lisible
- La destination existe (ou peut être créée) et est inscriptible
- La destination n’est pas en lecture seule
- Espace libre (avertissement de pré-vol)
- Confirmation de suppression quand **Delete files not in source** est activé
- Les emplacements des fichiers journaux et des listes de hash sont validés ; FilmCan avertit s’ils ne peuvent pas être créés

---

## Ce que vous verrez

Avertissements pour:
- Espace disque faible (vous pouvez toujours continuer)
- Le fichier journal n’a pas pu être créé (FilmCan continue sans journal)
- La liste de hash n’a pas pu être créée (FilmCan continue sans liste de hash)

La gestion des doublons se fait pendant le transfert en fonction de votre **Duplicate policy**.

---

## Paramètres

La validation de la source et de la destination s’exécute toujours.  
Le comportement des doublons est défini dans **Options** sous **Duplicate policy**.

---

## Connexes

- [Options](./options.md)
- [Multi-Destination](./multi-destination.md)

<!-- lang:de -->
# Sicherheitsprüfungen

FilmCan validiert die Einrichtung vor jedem Backup, um vermeidbare Ausfälle zu verhindern.

---

## Was wird überprüft

- Quelle existiert und ist lesbar
- Ziel existiert (oder kann erstellt werden) und ist beschreibbar
- Ziel ist nicht schreibgeschützt
- Freier Speicherplatz (Vor-Flug-Warnung)
- Bestätigung löschen, wenn **Delete files not in source** aktiviert ist
- Protokoll- und Hash-Listenorte werden validiert; FilmCan warnt, wenn sie nicht erstellt werden können

---

## Was Sie sehen werden

Warnungen für:
- Niedriger Festplattenspeicher (Sie können trotzdem fortfahren)
- Protokolldatei konnte nicht erstellt werden (FilmCan läuft ohne Protokoll weiter)
- Hash-Liste konnte nicht erstellt werden (FilmCan läuft ohne Hash-Liste weiter)

Duplikatbehandlung erfolgt während der Übertragung basierend auf Ihrer **Duplicate policy**.

---

## Einstellungen

Die Validierung von Quelle und Ziel wird immer ausgeführt.  
Das Duplikatverhalten wird in **Options** unter **Duplicate policy** eingestellt.

---

## Verwandte

- [Options](./options.md)
- [Multi-Destination](./multi-destination.md)

<!-- lang:es -->
# Comprobaciones de seguridad

FilmCan valida la configuración antes de cada backup para evitar fallos evitables.

---

## Lo que se verifica

- El origen existe y es legible
- El destino existe (o se puede crear) y es escribible
- El destino no es de solo lectura
- Espacio libre (advertencia previa al vuelo)
- Confirmación de eliminación cuando está habilitado **Delete files not in source**
- Se validan las ubicaciones de archivos de registro y listas de hash; FilmCan advierte si no se pueden crear

---

## Lo que verá

Advertencias para:
- Espacio en disco bajo (aún puede continuar)
- El archivo de registro no se pudo crear (FilmCan continúa sin registro)
- No se pudo crear la lista de hash (FilmCan continúa sin lista de hash)

El manejo de duplicados ocurre durante la transferencia según su **Duplicate policy**.

---

## Configuración

La validación de origen y destino siempre se ejecuta.  
El comportamiento de duplicados se establece en **Options** bajo **Duplicate policy**.

---

## Relacionado

- [Options](./options.md)
- [Multi-Destination](./multi-destination.md)
