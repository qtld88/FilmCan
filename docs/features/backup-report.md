<!-- lang:en -->
# PDF Backup Report

FilmCan can write a readable PDF for each destination after a backup, next to the transfer log.

---

## What is in it

- Header: project, episode/day/unit (when set), destination volume and path, start/end time and duration, status ("Verified ✓", "Copied, not verified" or "Failed"), warning (if any), FilmCan version.
- Summary: one line per roll with kind (Camera/Sound), file count and total size.
- One section per roll: a row per file with a thumbnail, name, relative path, size, duration (video/audio) and checksum.

The report lists everything in the roll folder on the drive, including files skipped on a resumed run. Hidden files and the `ascmhl/` folder are left out. XML sidecars and other non-media files are listed with their file icon.

---

## Enable it

Options › Logs › **PDF report with thumbnails**. It needs **Create log file** to be on; the toggle is greyed out otherwise. It is on for a new movie; movies you already had keep their setting.

---

## Where it goes

`<log file name>_report.pdf`, in the same folder as the log. With the Netflix Ingest preset the log goes in the shoot-day `Reports/` folder, so the PDF does too.

From History, right-click a card and choose **Open report** when the PDF exists. With several destinations, the menu has one **Open report** entry per destination.

---

## Good to know

- Generated in the background after history and notifications; it never delays or fails the backup.
- Only runs that copied something produce a report.
- Checksums (xxh128) come from the roll's latest ASC MHL manifest. With the simple hidden hash list style, checksums are left blank.
- Video thumbnails come from macOS QuickLook. ARRI, RED and BRAW clips show a file icon unless a QuickLook plugin is installed. Audio files show a waveform icon.
- Large cards (hundreds of clips) can take a few minutes.

<!-- lang:fr -->
# Rapport de sauvegarde PDF

FilmCan peut écrire un PDF lisible pour chaque destination après une sauvegarde, à côté du journal de transfert.

---

## Ce qu'il contient

- En-tête : projet, épisode/jour/unité (si renseignés), volume et chemin de destination, heures de début et de fin et durée, statut (« Verified ✓ », « Copied, not verified » ou « Failed »), avertissement (le cas échéant), version de FilmCan.
- Résumé : une ligne par roll avec le type (Camera/Sound), le nombre de fichiers et la taille totale.
- Une section par roll : une ligne par fichier avec une vignette, le nom, le chemin relatif, la taille, la durée (vidéo/audio) et la somme de contrôle.

Le rapport liste tout ce qui se trouve dans le dossier du roll sur le disque, y compris les fichiers sautés lors d'une reprise. Les fichiers cachés et le dossier `ascmhl/` sont exclus. Les fichiers annexes XML et les autres fichiers non média sont listés avec leur icône de fichier.

---

## L'activer

Options › Logs › **PDF report with thumbnails**. **Create log file** doit être activé ; sinon l'interrupteur est grisé. Il est activé sur un nouveau film ; les films déjà créés gardent leur réglage.

---

## Où il va

`<nom du fichier journal>_report.pdf`, dans le même dossier que le journal. Avec le preset Netflix Ingest, le journal va dans le dossier `Reports/` du jour de tournage, donc le PDF aussi.

Depuis History, faites un clic droit sur une carte et choisissez **Open report** quand le PDF existe. Avec plusieurs destinations, le menu contient une entrée **Open report** par destination.

---

## Bon à savoir

- Généré en arrière-plan après l'historique et les notifications ; il ne retarde jamais la sauvegarde et ne la fait jamais échouer.
- Seules les exécutions qui ont copié quelque chose produisent un rapport.
- Les sommes de contrôle (xxh128) viennent du dernier manifeste ASC MHL du roll. Avec le style de liste de hachage simple cachée, les sommes de contrôle restent vides.
- Les vignettes vidéo viennent de QuickLook de macOS. Les clips ARRI, RED et BRAW affichent une icône de fichier, sauf si un plug-in QuickLook est installé. Les fichiers audio affichent une icône de forme d'onde.
- Les grosses cartes (des centaines de clips) peuvent prendre quelques minutes.

<!-- lang:de -->
# PDF-Sicherungsbericht

FilmCan kann nach einer Sicherung für jedes Ziel ein lesbares PDF schreiben, neben dem Übertragungsprotokoll.

---

## Was enthalten ist

- Kopfbereich: Projekt, Episode/Tag/Einheit (falls gesetzt), Zielvolume und -pfad, Start- und Endzeit sowie Dauer, Status („Verified ✓“, „Copied, not verified“ oder „Failed“), Warnung (falls vorhanden), FilmCan-Version.
- Zusammenfassung: eine Zeile pro Roll mit Art (Camera/Sound), Dateianzahl und Gesamtgröße.
- Ein Abschnitt pro Roll: eine Zeile pro Datei mit Vorschaubild, Name, relativem Pfad, Größe, Dauer (Video/Audio) und Prüfsumme.

Der Bericht listet alles im Roll-Ordner auf dem Laufwerk auf, auch Dateien, die bei einem fortgesetzten Durchlauf übersprungen wurden. Versteckte Dateien und der Ordner `ascmhl/` bleiben außen vor. XML-Sidecars und andere Nicht-Mediendateien werden mit ihrem Dateisymbol aufgeführt.

---

## Aktivieren

Options › Logs › **PDF report with thumbnails**. **Create log file** muss eingeschaltet sein; sonst ist der Schalter ausgegraut. Bei einem neuen Film ist er an; bereits vorhandene Filme behalten ihre Einstellung.

---

## Wohin es geht

`<Name der Protokolldatei>_report.pdf`, im selben Ordner wie das Protokoll. Mit dem Preset Netflix Ingest landet das Protokoll im Ordner `Reports/` des Drehtags, also auch das PDF.

Klicken Sie in History mit der rechten Maustaste auf eine Karte und wählen Sie **Open report**, sobald das PDF existiert. Bei mehreren Zielen enthält das Menü pro Ziel einen Eintrag **Open report**.

---

## Gut zu wissen

- Wird nach Verlauf und Benachrichtigungen im Hintergrund erzeugt; es verzögert die Sicherung nie und lässt sie nie fehlschlagen.
- Nur Durchläufe, die etwas kopiert haben, erzeugen einen Bericht.
- Die Prüfsummen (xxh128) stammen aus dem neuesten ASC-MHL-Manifest des Rolls. Beim einfachen versteckten Hash-Listen-Stil bleiben die Prüfsummen leer.
- Videovorschauen stammen von macOS QuickLook. ARRI-, RED- und BRAW-Clips zeigen ein Dateisymbol, sofern kein QuickLook-Plug-in installiert ist. Audiodateien zeigen ein Wellenform-Symbol.
- Große Karten (Hunderte Clips) können einige Minuten dauern.

<!-- lang:es -->
# Informe de respaldo en PDF

FilmCan puede escribir un PDF legible para cada destino tras un respaldo, junto al registro de transferencia.

---

## Qué contiene

- Cabecera: proyecto, episodio/día/unidad (si están definidos), volumen y ruta de destino, hora de inicio y fin y duración, estado («Verified ✓», «Copied, not verified» o «Failed»), advertencia (si la hay), versión de FilmCan.
- Resumen: una línea por roll con el tipo (Camera/Sound), el número de archivos y el tamaño total.
- Una sección por roll: una fila por archivo con miniatura, nombre, ruta relativa, tamaño, duración (vídeo/audio) y suma de comprobación.

El informe lista todo lo que hay en la carpeta del roll en la unidad, incluidos los archivos omitidos en una ejecución reanudada. Los archivos ocultos y la carpeta `ascmhl/` se excluyen. Los archivos auxiliares XML y otros archivos que no son medios se listan con su icono de archivo.

---

## Activarlo

Options › Logs › **PDF report with thumbnails**. Requiere que **Create log file** esté activado; si no, el interruptor aparece atenuado. Está activado en una película nueva; las películas que ya tenía conservan su ajuste.

---

## Dónde se guarda

`<nombre del archivo de registro>_report.pdf`, en la misma carpeta que el registro. Con el preset Netflix Ingest el registro va a la carpeta `Reports/` del día de rodaje, así que el PDF también.

Desde History, haga clic derecho en una tarjeta y elija **Open report** cuando el PDF exista. Con varios destinos, el menú tiene una entrada **Open report** por destino.

---

## Conviene saber

- Se genera en segundo plano después del historial y las notificaciones; nunca retrasa ni hace fallar el respaldo.
- Solo las ejecuciones que copiaron algo generan un informe.
- Las sumas de comprobación (xxh128) proceden del último manifiesto ASC MHL del roll. Con el estilo de lista de hash simple oculta, las sumas de comprobación quedan en blanco.
- Las miniaturas de vídeo vienen de QuickLook de macOS. Los clips ARRI, RED y BRAW muestran un icono de archivo salvo que haya un plug-in de QuickLook instalado. Los archivos de audio muestran un icono de forma de onda.
- Las tarjetas grandes (cientos de clips) pueden tardar unos minutos.
