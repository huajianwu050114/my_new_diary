# Diary v2 architecture

## Product boundary

Diary v2 is local-first and must work without an account or a network
connection. Firebase authentication, Firestore, Firebase Storage, and cloud
sync are outside the v2 scope.

The existing application remains the reference implementation for product
behaviour and visual design. Features are migrated into the v2 structure
instead of being rewritten all at once.

## Dependency rule

Dependencies point inwards:

```text
presentation -> application -> domain <- data
```

- `domain` contains immutable business models and repository contracts.
- `application` contains use cases and coordinates domain operations.
- `data` implements repositories with local storage and maps persisted data.
- `presentation` contains Flutter pages, widgets, and state.

The domain layer must not import Flutter, SQLite, Firebase, or `dart:io`.

## Local data

SQLite will be the canonical store for v2. Images are stored as managed files;
the database stores stable image identifiers and relative paths rather than
temporary picker paths.

Deletion is soft by default (`deletedAt`), allowing entries to be restored
from the recycle bin. Permanent deletion removes the database row and its
managed image files in one application operation.

## Compatibility

Migration must recognise both formats used by earlier versions:

1. The current `diary.db` SQLite database.
2. The older `diaries/<year>/<month>/*.json` files and their image paths.

Migration is idempotent: running it more than once must not duplicate entries.
Before a source is modified or removed, v2 must verify that every entry and
image was imported successfully. The first migration implementation will only
read legacy data.

## Delivery order

1. Domain model and repository contract.
2. Tested SQLite implementation and legacy migration.
3. Entry list, create, view, edit, trash, and search.
4. Calendar and favourites.
5. Location, analysis, export, notifications, and optional AI features.
6. Cloud sync only after the local v2 release is stable.
