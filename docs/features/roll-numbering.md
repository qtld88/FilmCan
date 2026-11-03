<!-- lang:en -->
# Roll Numbering and Shoot Day

Options › Sources › **Cards & rolls**. Everything here is **off by default**; existing backups
behave exactly as before.

---

## Automatic roll names

With **Number rolls automatically** on, each folder source gets a roll name instead of the
card (volume) name: camera cards `A001, A002, A003…`, sound cards `S001, S002…`.

- Prefix (1-2 letters), digit count and start number are set separately for camera and sound.
- ARRI and RED cards keep their own reel name (switch off with **ARRI and RED keep their reel
  name**).
- **The same card always gets the same roll name.** The assignment is saved before the copy
  starts, so a stopped backup resumes into the same roll folder.
- A reformatted card has a new volume UUID and is treated as a new roll.
- Two cards can never share a roll folder: a name collision still gets a `-2` suffix.
- Flat files (not folders) are not numbered.
- **Reset numbering…** forgets the assignments. Backups already made keep their folder names.

Roll folders use the assigned name verbatim. The destination rename template no longer applies
to numbered roll folders.

Numbers are stored in `roll-numbering.json` (Application Support/FilmCan), not in the backup
configuration. "Retry from source" in history reuses the roll names of the original run.

Known limit (v1): the destination preview and the log path still show the card name.

---

## Shoot-day counter

**Advance the shoot day automatically**: on the first backup of each new calendar day, `{day}`
goes up by one while keeping its width (`Day01` → `Day02`, `D9` → `D10`). The Day field is the
starting value. A Day without trailing digits is left unchanged. The current value is shown
under the toggle ("Today: Day02").
