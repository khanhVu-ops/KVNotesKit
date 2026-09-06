# Changelog

## Unreleased

- Add smart auto-pairing, bracket skipping, pair deletion, selected text delimiter wrapping, and keyboard toolbar indent/outdent buttons (NK-236).
- Auto-continue Markdown lists (`-`/`*`/`+`), checklists (`- [ ]`/`- [x]`), numbered lists (`1.`/`2)`), and blockquotes (`>`/`>>`) on Return, preserving nested indentation, outdenting empty indented items, and cleanly exiting root empty items with full undo support (NK-235).
- Add quick note templates (`.blank`, `.seedPhrase`, `.bankCard`, `.credentials`, `.checklist`) offered
  from the create option sheet, with unmodified skeleton detection to prevent persisting empty notes (NK-400).

- Add `hidesPreview`: a per-note toggle that stops the list drawing a note's opening line without
  putting a biometric gate in front of it. Unlike the lock it keeps the snippet stored and
  searchable by the vault's owner.
- `NoteDigest.visiblePreview` is now the one property rows and cards read to decide whether they
  may draw a preview.
- `NoteFixtures.wallet` no longer carries a snippet: a locked note cannot have one.
- Replace every `Menu` on the notes list with an option sheet: sort and filter, a note's actions,
  the batch dock's More, and the folder manager's per-folder actions. The keyboard no longer rises
  when one is opened.
- A note's actions now list the folders inline rather than behind a submenu, and a list row opens
  them on a long press where the grid card has a visible button.

- Add a two-column grid layout to the notes list, toggled from the header and remembered in
  `NoteListPreferences`. Cards carry a visible menu button in place of the row's swipe actions.
- `NoteListPreferences` decodes missing keys as defaults, so a blob written by 0.1.0 keeps the
  sort order and filter it does carry.
- Remove the unused `NotesListState.Layout`.
- Fold the list title up beside the back button instead of dropping it, and unfold it whenever the
  list is back at the top.
- Move the pinned/timeline split into one flat `ForEach` so pinning slides a row instead of
  cross-fading it, and hold the header still while the row travels.
- Queue note writes behind each other rather than refusing the second one, which used to leave a
  row pinned on screen and unpinned in the vault.
- Redesign the folder rows around the folder's own colour, drop the sheet's grabber, open the
  keyboard on rename, and let the removal confirmation animate in.

## 0.1.0 - 2026-09-05

- Scaffold the compiler-enforced Core, UI, Testing, and façade boundaries.
- Define the host contracts and provide an actor-backed in-memory store for tests and previews.
- Own Markdown parsing, insertion, and note-summary derivation in Foundation-only Core.
- Add host-independent list and editor screens driven only by Core ports and `NoteTheme`.
- Ship all KVNotesUI interface strings in the package for the app's 19 locales.
- Add a PIN fallback hand-off so hosts retain ownership of credential entry.
- Move Markdown and ViewModel behavior coverage into package-owned test targets.
