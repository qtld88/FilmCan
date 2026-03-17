# Architecture Overview

FilmCan is a **local macOS app**. It does **not** use a backend or database.

---

## Core Layers

**Views (SwiftUI)**  
UI components only. Views are responsible for layout and user interaction.

**ViewModels**  
UI state, validation, and orchestration of transfer runs.  
Examples: `TransferViewModel`, `BackupEditorViewModel`.

**Services**  
Business logic and I/O:
- `RsyncService` (rsync engine)
- `CustomCopierService` (FilmCan engine)
- `NotificationService`, `WebhookService`
- `ConfigurationStorage` (local persistence)

**Utilities & Models**  
Formatting, hashing, file enumeration, and shared data structures.

---

## Persistence (Local Only)

FilmCan stores configuration, presets, and history in the user’s **Application Support** folder.  
There is no cloud storage and no remote API.

---

## Data Flow (High Level)

1. User configures sources/destinations in the UI.  
2. ViewModel validates paths and settings.  
3. Transfer runs via `RsyncService` or `CustomCopierService`.  
4. Results and history are stored locally and shown in the UI.
