<!-- lang:en -->
# Source Selection

Choose what to copy.

---

## Manual Sources

Drag drives, folders, or files into **Copy From**

Or click **Browse Files...**

---

## Auto-Detect

Automatically add specific drives when connected:

1. Enable **Auto-detect camera sources** (or **Auto-detect sound sources** for sound)
2. Add drive/folder names (supports `*` wildcards)

Auto-detected sources are never removed automatically. Sound auto-detect also tags the
matched drives as Sound.

---

## Camera / Sound (Netflix routing)

Each source card has a small **clickable icon at the top-right** marking it Camera or
Sound:

- **🎥 video-camera** → Camera (lands in `Camera_Media/` under the Netflix preset)
- **🔊 speaker** → Sound (lands in `Sound_Media/`)

**Click the icon to switch** between the two, it's a toggle. Sources default to Camera.
The **Save To** preview updates to show where each source will land. This only changes
the destination folder; it has no effect unless you use a preset with separate camera
and sound folders (e.g. **Netflix Ingest**).

---

## Include / Exclude Patterns

**Include** (copy only these):
```
*.R3D
*.MOV
*.BRAW
```

**Exclude** (skip these):
```
*.tmp
*/Cache/
```

**Copy-only** (copy only these, keep folder structure):
```
*.R3D
*.BRAW
```

**Default excludes**: `.DS_Store`, `.Trashes`, `.Spotlight-V100`, `.fseventsd`, `.DocumentRevisions-V100`, `.TemporaryItems`

Include runs first, then exclude.

---

## Troubleshooting

**Source not appearing**  
Check if mounted + grant Full Disk Access

**Wrong files copied**  
Review include/exclude patterns

---

## Related

- [Quick Start](../quickstart.md)
- [Options](./options.md)

<!-- lang:fr -->
# Sélection de la source

Choisissez ce que vous souhaitez copier.

---

## Sources manuelles

Glissez les lecteurs, dossiers ou fichiers dans **Copy From**

Ou cliquez sur **Browse Files...**

---

## Détection automatique

Ajoutez automatiquement des lecteurs spécifiques lorsqu'ils sont connectés:

1. Activez **Auto-detect camera sources** (ou **Auto-detect sound sources** pour le son)
2. Ajoutez des noms de lecteur/dossier (supporte les wildcards `*`)

Les sources détectées automatiquement ne sont jamais supprimées automatiquement. La détection automatique de son étiquet également
les lecteurs correspondants comme Son.

---

## Caméra / Son (routage Netflix)

Chaque carte source a une petite **icône cliquable en haut à droite** la marquant comme Caméra ou
Son:

- **🎥 video-camera** → Caméra (atterrit dans `Camera_Media/` sous le préset Netflix)
- **🔊 speaker** → Son (atterrit dans `Sound_Media/`)

**Cliquez sur l'icône pour basculer** entre les deux, c'est un bouton bascule. Les sources par défaut sont Caméra.
L'aperçu **Save To** se met à jour pour montrer où chaque source atterrira. Cela ne change que
le dossier de destination; cela n'a aucun effet à moins que vous n'utilisiez un préset avec des dossiers
caméra et son séparés (par exemple **Netflix Ingest**).

---

## Modèles d'inclusion / exclusion

**Inclure** (copier seulement ceux-ci):
```
*.R3D
*.MOV
*.BRAW
```

**Exclure** (ignorer ceux-ci):
```
*.tmp
*/Cache/
```

**Copie uniquement** (copier seulement ceux-ci, conserver la structure des dossiers):
```
*.R3D
*.BRAW
```

**Exclusions par défaut**: `.DS_Store`, `.Trashes`, `.Spotlight-V100`, `.fseventsd`, `.DocumentRevisions-V100`, `.TemporaryItems`

L'inclusion s'exécute en premier, puis l'exclusion.

---

## Dépannage

**Source n'apparaît pas**  
Vérifiez si elle est montée + accordez l'accès complet au disque

**Mauvais fichiers copiés**  
Passez en revue les modèles d'inclusion/exclusion

---

## Connexes

- [Démarrage rapide](../quickstart.md)
- [Options](./options.md)

<!-- lang:de -->
# Quellenauswahl

Wählen Sie aus, was kopiert werden soll.

---

## Manuelle Quellen

Ziehen Sie Laufwerke, Ordner oder Dateien in **Copy From**

Oder klicken Sie auf **Browse Files...**

---

## Automatische Erkennung

Fügen Sie automatisch bestimmte Laufwerke hinzu, wenn sie verbunden sind:

1. Aktivieren Sie **Auto-detect camera sources** (oder **Auto-detect sound sources** für Sound)
2. Fügen Sie Laufwerks-/Ordnernamen hinzu (unterstützt `*`-Platzhalter)

Automatisch erkannte Quellen werden niemals automatisch entfernt. Die Sound-Auto-Erkennung kennzeichnet auch
die übereinstimmenden Laufwerke als Sound.

---

## Kamera / Sound (Netflix-Routing)

Jede Quellkarte hat ein kleines **anklickbares Symbol oben rechts**, das sie als Kamera oder
Sound markiert:

- **🎥 video-camera** → Kamera (landet in `Camera_Media/` unter der Netflix-Voreinstellung)
- **🔊 speaker** → Sound (landet in `Sound_Media/`)

**Klicken Sie auf das Symbol, um zu wechseln** zwischen den beiden, es ist ein Umschalter. Quellen sind standardmäßig Kamera.
Die **Save To**-Vorschau aktualisiert sich, um zu zeigen, wo jede Quelle landen wird. Dies ändert nur
den Zielordner; es hat keine Auswirkung, es sei denn, Sie verwenden eine Voreinstellung mit separaten Kamera-
und Sound-Ordnern (z. B. **Netflix Ingest**).

---

## Ein- und Ausschlussmuster

**Einschließen** (nur diese kopieren):
```
*.R3D
*.MOV
*.BRAW
```

**Ausschließen** (diese überspringen):
```
*.tmp
*/Cache/
```

**Nur kopieren** (nur diese kopieren, Ordnerstruktur beibehalten):
```
*.R3D
*.BRAW
```

**Standardausschlüsse**: `.DS_Store`, `.Trashes`, `.Spotlight-V100`, `.fseventsd`, `.DocumentRevisions-V100`, `.TemporaryItems`

Einschließen wird zuerst ausgeführt, dann Ausschließen.

---

## Fehlerbehebung

**Quelle wird nicht angezeigt**  
Überprüfen Sie, ob eingebunden + Vollzugriff auf Festplatte gewähren

**Falsche Dateien kopiert**  
Überprüfen Sie die Ein- und Ausschlussmuster

---

## Verwandte

- [Schnellstart](../quickstart.md)
- [Options](./options.md)

<!-- lang:es -->
# Selección de origen

Elija qué copiar.

---

## Orígenes manuales

Arrastre unidades, carpetas o archivos a **Copy From**

O haga clic en **Browse Files...**

---

## Detección automática

Agregue automáticamente unidades específicas cuando se conecten:

1. Habilite **Auto-detect camera sources** (o **Auto-detect sound sources** para sonido)
2. Agregue nombres de unidad/carpeta (admite caracteres comodín `*`)

Las orígenes detectadas automáticamente nunca se eliminan automáticamente. La detección automática de sonido también etiqueta
las unidades coincidentes como Sonido.

---

## Cámara / Sonido (enrutamiento Netflix)

Cada tarjeta de origen tiene un pequeño **icono hacer clic en la esquina superior derecha** que la marca como Cámara o
Sonido:

- **🎥 video-camera** → Cámara (se coloca en `Camera_Media/` bajo el ajuste predeterminado de Netflix)
- **🔊 speaker** → Sonido (se coloca en `Sound_Media/`)

**Haga clic en el icono para cambiar** entre los dos, es un interruptor. Los orígenes tienen como predeterminado Cámara.
La vista previa **Save To** se actualiza para mostrar dónde aterrizará cada origen. Esto solo cambia
la carpeta de destino; no tiene efecto a menos que use un ajuste predefinido con cámaras separadas
y carpetas de sonido (por ejemplo, **Netflix Ingest**).

---

## Patrones de inclusión / exclusión

**Incluir** (copiar solo estos):
```
*.R3D
*.MOV
*.BRAW
```

**Excluir** (omitir estos):
```
*.tmp
*/Cache/
```

**Solo copiar** (copiar solo estos, mantener estructura de carpetas):
```
*.R3D
*.BRAW
```

**Exclusiones predeterminadas**: `.DS_Store`, `.Trashes`, `.Spotlight-V100`, `.fseventsd`, `.DocumentRevisions-V100`, `.TemporaryItems`

Incluir se ejecuta primero, luego Excluir.

---

## Solución de problemas

**El origen no aparece**  
Verifique si está montado + Otorgue acceso completo al disco

**Archivos incorrectos copiados**  
Revise los patrones de inclusión/exclusión

---

## Relacionado

- [Inicio rápido](../quickstart.md)
- [Options](./options.md)
