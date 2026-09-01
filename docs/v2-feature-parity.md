# Diary v2 feature parity

This checklist tracks local features visible in the original application.
Items are only checked after they are connected to v2 storage and covered by
an appropriate test.

## Core diary

- [x] Local SQLite database
- [x] Create a text entry
- [x] Entry date, mood, and tags
- [x] Chronological entry list
- [x] Bounded recent list with expandable monthly archive
- [x] Entry detail
- [x] Original-style paged detail image viewer and creation-time signature
- [x] Edit an entry
- [x] Move an entry to the recycle bin
- [x] Restore or permanently delete an entry
- [x] Full-text search
- [x] Tag filtering
- [x] Attach, view, replace, and remove multiple images

## Data compatibility

- [x] Idempotent import from the previous SQLite `diary.db`
- [x] Idempotent import from older JSON diary files
- [x] Copy reachable legacy images into v2 managed storage
- [x] In-app migration report and retry controls

## Browse and organise

- [x] Calendar and entries by day
- [x] Favourite diary entries
- [x] Public festivals with offline cache
- [x] Custom festivals, anniversaries, and countdowns
- [x] Location selection
- [x] Location memories

## Reflection and portability

- [x] Statistics and activity heat map
- [x] Word cloud and custom stop words
- [x] PDF export
- [x] Complete local backup export and import
- [x] AI conversation and saved diary analysis
- [x] Multiple persistent Chat sessions per diary with resumable history
- [x] Single-entry AI summary cards
- [x] Opt-in automatic friend-style AI reply after saving an entry
- [x] Weekly and monthly AI recap cards
- [x] Secure local Gemini API Key configuration and explicit transfer consent
- [x] Switchable Gemini and DeepSeek providers with separate secure API Keys

## App experience

- [x] Original-style home date header and gradient timeline cards
- [x] Home month grouping, on-this-day memories, and photo highlights
- [x] Home festival cards, profile drawer, and expandable quick actions
- [x] System, light, and dark themes
- [x] Local profile without requiring an account
- [x] Local reminders and notifications
- [x] Biometric/system-credential app lock
- [x] Settings
- [ ] Android and iOS release validation
- [x] Windows x64 release build validation

## Deferred beyond local v2

- [ ] Optional account
- [ ] Cloud backup and multi-device sync
- [ ] Conflict handling and offline sync queue
