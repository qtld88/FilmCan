<!-- lang:en -->
# Roadmap

Where FilmCan is heading. Not a promise of dates, a direction. Order is rough priority, not a schedule.

---

## Shipped

- **1.4.1**, same-name card disambiguation (two cards named the same no longer merge), smarter resume vs. new-card detection, faster startup cleanup on full drives.
- **1.4.0**, stable and honest ETA (no more roller-coaster estimates), instant tab switching and options panels.
- **1.3.0**, Netflix Camera/Sound routing (per-source toggle, sound auto-detect, editable folder templates), ASC MHL vs simple hidden hash list, per-destination resume + full-job progress, live per-destination failure surfacing.
- **1.2.x**, Single Swift copy engine (FanOut), rsync engine removed, ASC MHL chain of custody.

---

## Next

### Automatic media classification
Detect **video vs sound clips** by container/extension and route them automatically, so the Camera/Sound tag no longer has to be set by hand on every source.

### Corrupted-file detection
Go beyond checksum-mismatch: flag clips that are **structurally broken** (truncated, unreadable headers) during or after copy, and surface them per destination.

### PDF backup report (Foolcat-style)
Generate a **delivery-ready PDF** per backup, per-roll thumbnails, clip metadata, checksums, and copy summary, written into the shoot-day `Reports/` folder alongside the transfer log.

---

## Want to influence this?

Open an issue or start a discussion on [GitHub](https://github.com/qtld88/FilmCan). Real-world camera-card workflows shape what gets built first.

<!-- lang:fr -->
# Feuille de route

Vers où se dirige FilmCan. Pas une promesse de dates, une direction. L'ordre est une priorité approximative, pas un calendrier.

---

## Livré

- **1.4.1**, désambiguation des cartes de même nom (deux cartes du même nom ne fusionnent plus), détection plus intelligente de la reprise par rapport aux nouvelles cartes, nettoyage de démarrage plus rapide sur les disques pleins.
- **1.4.0**, ETA stable et honnête (pas plus d'estimations en montagnes russes), commutation instantanée des onglets et panneaux d'options.
- **1.3.0**, routage Netflix Camera/Sound (bascule par source, auto-détection du son, modèles de dossier modifiables), ASC MHL par rapport à la liste de hash masquée simple, reprise par destination et progression du travail complet, surfaçage des pannes en direct par destination.
- **1.2.x**, moteur de copie Swift unique (FanOut), moteur rsync supprimé, chaîne de contrôle ASC MHL.

---

## Prochain

### Classification automatique des médias
Détectez les **clips vidéo par rapport aux clips son** par conteneur/extension et les acheminer automatiquement, de sorte que l'étiquette Camera/Sound n'ait plus besoin d'être définie manuellement sur chaque source.

### Détection de fichiers corrompus
Allez au-delà de l'erreur de somme de contrôle : marquez les clips **structurellement cassés** (tronqués, en-têtes illisibles) pendant ou après la copie, et surfacez-les par destination.

### Rapport de backup PDF (style Foolcat)
Générez un **PDF prêt pour la livraison** par backup, miniatures par roll, métadonnées de clip, sommes de contrôle et résumé de copie, écrit dans le dossier `Reports/` du jour de tournage à côté du journal de transfert.

---

## Voulez-vous influencer cela?

Ouvrez un problème ou commencez une discussion sur [GitHub](https://github.com/qtld88/FilmCan). Les flux de travail réels des cartes de caméra façonnent ce qui est construit en premier.

<!-- lang:de -->
# Roadmap

Wo FilmCan hingeht. Kein Versprechen von Daten, eine Richtung. Die Reihenfolge ist eine ungefähre Priorität, kein Zeitplan.

---

## Versand

- **1.4.1**, Disambiguierung von Karten mit gleichem Namen (zwei Karten mit gleichem Namen werden nicht mehr zusammengeführt), intelligentere Wiederaufnahme- und neue Kartenerkennung, schnellere Bereinigung beim Start auf vollen Laufwerken.
- **1.4.0**, stabile und ehrliche ETA (keine bergauf-bergab-Schätzungen mehr), sofortiger Registerkartenwechsel und Optionsbedienfelder.
- **1.3.0**, Netflix Camera/Sound-Routing (pro-Quellen-Schalter, Sound-Autoerkennung, bearbeitbare Ordnervorlagen), ASC MHL versus einfache versteckte Hash-Liste, pro-Ziel-Wiederaufnahme und vollständiger Job-Fortschritt, Live-Pro-Ziel-Fehlerauftritt.
- **1.2.x**, Single Swift copy engine (FanOut), rsync engine entfernt, ASC MHL chain of custody.

---

## Nächstes

### Automatische Medieneinstufung
Erkennen Sie **Video- versus Tonclips** nach Container/Erweiterung und leiten Sie sie automatisch weiter, damit das Camera/Sound-Tag nicht mehr manuell auf jeder Quelle festgelegt werden muss.

### Beschädigte Dateierkennung
Gehen Sie über eine Checksummen-Nichtübereinstimmung hinaus: kennzeichnen Sie Clips, die **strukturell beschädigt** sind (gekürzt, nicht lesbare Header) während oder nach der Kopie, und zeigen Sie sie pro Ziel an.

### PDF-backup-Bericht (Foolcat-Stil)
Generieren Sie pro backup ein **versandbereites PDF**, pro-roll-Miniaturansichten, Clip-Metadaten, Kontrollsummen und Kopie-Zusammenfassung, geschrieben in den `Reports/`-Ordner des Schießtages neben dem Übertragungsprotokoll.

---

## Möchten Sie dies beeinflussen?

Öffnen Sie ein Problem oder starten Sie eine Diskussion auf [GitHub](https://github.com/qtld88/FilmCan). Echte Kamerakartenarbeitsabläufe prägen, was zuerst erstellt wird.

<!-- lang:es -->
# Hoja de ruta

Hacia dónde se dirige FilmCan. No es una promesa de fechas, es una dirección. El orden es una prioridad aproximada, no un cronograma.

---

## Enviado

- **1.4.1**, desambiguación de tarjetas con el mismo nombre (dos tarjetas con el mismo nombre ya no se fusionan), detección de reanudación versus tarjeta nueva más inteligente, limpieza de inicio más rápida en unidades llenas.
- **1.4.0**, ETA estable y honesto (sin más estimaciones de montaña rusa), cambio de pestañas instantáneo y paneles de opciones.
- **1.3.0**, enrutamiento de Netflix Camera/Sound (alternancia por origen, autodetección de sonido, plantillas de carpeta editables), ASC MHL versus lista de hash oculta simple, reanudación por destino y progreso del trabajo completo, surfaceo de falla en directo por destino.
- **1.2.x**, motor de copias Swift único (FanOut), motor rsync eliminado, cadena de custodia ASC MHL.

---

## Próximo

### Clasificación automática de medios
Detecte **clips de video versus clips de sonido** por contenedor/extensión y enrútelos automáticamente, de modo que la etiqueta Camera/Sound ya no tenga que establecerse manualmente en cada origen.

### Detección de archivos dañados
Vaya más allá de la falta de coincidencia de suma de verificación: marque clips que estén **estructuralmente rotos** (truncados, encabezados ilegibles) durante o después de la copia, y muéstrelos por destino.

### Informe de backup en PDF (estilo Foolcat)
Genere un **PDF listo para la entrega** por backup, miniaturas por roll, metadatos de clip, sumas de verificación y resumen de copia, escrito en la carpeta `Reports/` del día de grabación junto al registro de transferencia.

---

## ¿Quiere influir en esto?

Abra un problema o inicie una discusión en [GitHub](https://github.com/qtld88/FilmCan). Los flujos de trabajo reales de tarjetas de cámara dan forma a lo que se construye primero.
