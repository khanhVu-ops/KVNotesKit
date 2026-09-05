# Changelog

## Unreleased

## 0.1.0 - 2026-09-05

- Scaffold the compiler-enforced Core, UI, Testing, and façade boundaries.
- Define the host contracts and provide an actor-backed in-memory store for tests and previews.
- Own Markdown parsing, insertion, and note-summary derivation in Foundation-only Core.
- Add host-independent list and editor screens driven only by Core ports and `NoteTheme`.
- Ship all KVNotesUI interface strings in the package for the app's 19 locales.
- Add a PIN fallback hand-off so hosts retain ownership of credential entry.
- Move Markdown and ViewModel behavior coverage into package-owned test targets.
