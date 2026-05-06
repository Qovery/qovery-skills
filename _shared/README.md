# Shared content (authoring source)

This directory holds reference content that is copied into multiple skills.
The model never reads files from `_shared/` directly — each skill gets its own
copy under `<skill>/reference/` so that progressive disclosure works correctly
when skills are installed independently.

## How to update

1. Edit a file under `_shared/` (e.g. `_shared/console-url-detection.md`).
2. Run `scripts/sync-shared.sh` from the repo root.
3. Commit both the source change and the synced copies.

The sync map is encoded in `scripts/sync-shared.sh`.
