# Filos — App Store Safe Port

Temporary public development branch for an App-Store-safe iPhone/iPad file manager matching the Filos workflow and UI.

## Scope

- Native SwiftUI file browser
- Documents, app container, temporary storage, and user-selected folders
- Security-scoped folder bookmarks for Files/iCloud/external-drive access
- File/folder creation, rename, duplicate, move, delete, import, share
- ZIP compression and extraction
- Quick Look
- Text editor
- Property-list editor
- Favorites
- File metadata / POSIX permission viewer
- Search and sorting
- Logs and settings
- Privacy manifest for required-reason APIs
- No private entitlements
- No sandbox-extension token consumption
- No private system symbols
- No root filesystem browsing
- No other-app container browsing
- No forced process termination

Bundle identifier: `com.nightvibes33.filos`

The implementation on this branch is clean-room because the referenced upstream repository currently does not publish a software license.

CI builds on every push to this branch and publishes an unsigned IPA artifact for validation.
