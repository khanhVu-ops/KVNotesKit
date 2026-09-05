# KVNotesKit

Reusable private-notes text and UI components for iOS 18 and later.

The package deliberately owns Markdown behavior and screens, but never vault persistence,
encryption keys, trash policy, favourites, or decoy scopes. Hosts provide those capabilities
through the ports in `KVNotesCore`.

## Targets

- `KVNotesCore`: Foundation-only note models, Markdown behavior, and host ports.
- `KVNotesUI`: SwiftUI screens and the hardened platform text editor.
- `KVNotesTesting`: fixtures and in-memory test doubles.
- `KVNotesKit`: the convenience façade imported by an app.
