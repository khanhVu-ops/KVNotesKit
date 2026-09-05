# Changelog

## Unreleased

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
