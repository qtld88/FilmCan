# The film owns its settings

**Date:** 2026-11-11 · **Lot:** 5 (part 1 of 2) · **Branch:** `qt1/film-settings`, stacked on `qt1/first-launch-defaults`

## Goal

Today a film that uses a preset is live-linked to it: the folder editor writes straight into the shared preset, and every save pushes the film's options back into it. Two films on the same preset silently change each other. Make the film the owner of its settings. A preset becomes what its name says: a starting point, and something you can save to.

This part delivers the model, the migration, "new movie like a previous one" and the `{movie}` folder token. Part 2 (separate lot, stacked on this one) moves the Options card into a "Movie settings" panel, regroups the Settings window and rewrites the first-level labels.

## Expected behaviour

### 1. Each film has its own copy

A preset record gains an optional owner, `ownerFilmId`. A preset with an owner is that film's private copy; a preset without one is a shared preset, as before.

- The film keeps pointing at a preset by id (`selectedOrganizationPresetId`), now always its own copy. Every existing reader (run, resume context, editor bindings, Quick Copy's "pick a movie") keeps working unchanged, because nothing about the lookup changes.
- Choosing a preset in a film ("Netflix Ingest (built-in)", a saved preset) copies its values into the film's own copy. The shared preset is never touched afterwards.
- "Save as new preset" (was "Create new preset") saves the film's current settings as a new shared preset, sound folders included. The film keeps its own copy.
- "Off" and the trash button remove the film's own copy only. A shared preset is deleted from the Preset menu ("Delete preset"). The pencil renames the film's own copy.
- Every path that selects a preset goes through the same copy step, including the plain id setter; nothing ever falls back to "the first preset in the list".
- Lookups by name (built-in Netflix preset, "new movie from history") search shared presets only.
- Lists that offer presets to start from (the Preset menu, Quick Copy's picker, preset export) show shared presets only. Quick Copy also shows the picked film's own copy, since that is what that film runs with.
- The "(modified)" mark next to the preset name no longer appears for a film's own copy: there is nothing to diverge from.
- Deleting a film deletes its own copy.

### 2. Migration, once, at load

For every film whose preset id points at a preset it does not own: clone the preset (new id, `ownerFilmId` = the film), point the film at the clone. Same values, same name, so the same folders and files as before; the built-in Netflix behaviours are keyed on the preset's name, which the clone keeps. Two films on one preset each get a clone. A film with no preset, or with a dangling id, is left alone. The shared preset stays in the list. Running the migration twice changes nothing.

The migration also aligns the film's saved working copy of the folder settings with the preset, so the film's first save cannot write an older state into its new copy. Past history entries keep the id of the shared preset they ran with.

No pruning happens at load (a failed `configs.json` load must not delete anything); orphaned copies are only removed when their film is deleted.

### 3. New movie like a previous one

The "+" in the tab bar becomes a split control: a click still creates a blank movie; its menu offers "Like <film>" for each existing film (most recently used first), then "From preset <name>" for each shared preset. The File menu gets the same entries.

"Like <film>" copies: the film's own preset copy, engine and verification options, duplicate handling, log and report options, hash-list style, copy mode, roll-numbering settings, auto-detect switches and patterns, episode, unit and camera format, Netflix folder templates. It never copies: sources, destinations, excluded paths, per-path tags, the shoot day, the day counter and roll counters (they are stored per film id), card names, history, usage dates. It is a copy, not a link.

### 4. `{movie}` folder token

Folder and rename templates accept `{movie}`: the film's name, with `/`, `\` and `:` replaced by `-`. Templates that do not contain the token resolve exactly as before. (Notification templates already have their own `{movie}`; the two are separate substitutions with the same meaning.) In Quick Copy the token is the picked movie's name, else the project name.

When a film is created "like" another, a leading folder in its templates that spells the source film's name (ignoring case, spaces and punctuation: `CITIZENK` for "Citizen K") is replaced by `{movie}`, so the new film gets its own top folder. A leading folder that does not match the name is left as typed; the new film then writes under the same top folder until the user edits it. This is stated in the PR as a known limit.

## What does not change

- What a run writes for any existing film: same resolver, same preset values.
- The engine, verification, manifests.
- `configs.json` field set (no field added or removed). `presets.json` gains one optional key per record; a file without it decodes as before.
- Quick Copy's own behaviour.

## Edge cases

- Going back to an older app version: own copies appear as ordinary presets with duplicate names. Harmless; nothing is lost.
- Preset export writes shared presets only; an imported preset is always shared. An imported movie pointing at a shared preset gets its copy right after the import.
- Quick Copy looks presets up in the full list but offers only shared presets plus the picked movie's own settings.
- A film's own copy renamed away from "Netflix Ingest" loses the Netflix-specific behaviours, exactly as renaming the shared preset did before.

## Success criteria

- Tests: legacy `presets.json` decodes with no owner; migration clones per film, is idempotent, preserves the resolved run preset byte for byte; editing one film's copy leaves the other film and the shared preset equal to their previous values; "like" copies the listed settings and none of the excluded ones; `{movie}` resolves, and templates without it are unchanged; the leading-folder rule.
- Full suite green on the macOS runner.
