# Birthdays, Contacts and duplicates

Add a birthday in **Edit person**. Month and day are enough; birth year is optional. Invalid dates
cannot be saved. February 29 is observed on February 28 in non-leap years. Birthdays within the next
14 calendar days appear on Today, independently of invitations and conversation history.

Enable **Birthday and gift reminders on this device** in Preferences, then allow OS notifications.
The default time is 09:00 local time. Birthday-day and gift reminders are independently editable for
each person. Gift reminders default to two weeks before birthdays for recorded Friend/Family
categories; other people can be opted in individually. Give Space and Pause silence both kinds.
No birthday action logs a message or claims that contact happened.

The app queues the nearest 60 birthday/gift notifications within a two-year horizon, leaving room
for the opportunity reminder. These are one-shot calendar notifications that can arrive while the
app is closed. Opening/running the app replenishes the queue and applies birthday, boundary, time,
time-zone, name and preview-policy changes. Large collections need occasional app openings to
replenish dates beyond the queue. Permission, notification enablement and time belong to the device.
No names appear in notification titles, identifiers, categories or hidden preview placeholders.
Named bodies require both the user's name preference and the OS When Unlocked policy. As with
existing reminders, an already scheduled OS snapshot cannot respond to edits while the app is closed.

## Contacts

Use **Import from Contacts…** in the toolbar or **Choose people from Contacts…** in Preferences.
Select all available contacts, or select a few. Importing is a reviewed local operation: nothing is
written back to Apple's Contacts, no contact notes/photos/history are requested, and no messages are
sent. New people start with Unsure and no assumed relationship categories.

Already linked contacts match by their device-scoped identifier. Unique normalized phone/email
matches are proposed automatically; names and ambiguous addresses require an explicit choice in a
searchable matching sheet. Repeat imports update a linked person rather than adding them again.
The selected import rejects a stale preview and makes a private backup when changing existing data.
On iOS 18+, limited access only exposes the contacts the user allowed; more can be allowed in system
settings. Denying or revoking permission never deletes Keep Close people.

**Keep linked people updated from Contacts** follows names, the preferred contact detail and birthdays
on app opening, activation/unlock and contact-store changes. A three-way comparison with the previous
import detects user edits. Once an override is detected, it remains protected across subsequent
Contacts changes, including a manually cleared birthday. Existing populated fields are protected
when linking for the first time; calling, messaging, email and in-person preferences stay in place. Following can be turned off or a link removed under a person's
Details. Unlinking retains the person's saved information. Missing/deleted/inaccessible Contacts
records do not delete Keep Close records. Links from another device are retained but never used as
local Contacts identifiers. Background sync while Keep Close is terminated is not supported.

## Merge

Open the person whose identity/preferences should remain, then choose **Details → Merge with another
person…**. Search for the duplicate and review the combined result. Conflicting birthdays require a
choice. Both histories, plans, memories, interests, ideas, feedback, notes and contact links survive;
alternate contact details are retained. The keeper's name, preferred method and rhythm remain.
Give Space, Pause, the longest deferral and set-aside ideas cannot be relaxed by merging. Real recorded
responses across the two histories resolve earlier incoming events without inventing a new event.
Conflicting versions of the same saved item require review rather than silently losing either version.

The merge is one locked transaction with a private before-merge backup. Undo on the receipt restores
the original two records and refuses to overwrite a later edit. Old merged UUIDs are retained as
aliases so subsequent existing-ID AI imports find the surviving person. Version-1/version-2 AI
schemas remain unchanged; birthdays currently come from the editor, Contacts or CLI.

CLI examples (use fictional records and --data-dir for testing):

```sh
scripts/keepclose update PERSON_UUID --birthday 02-29 --gift-reminder automatic
scripts/keepclose update PERSON_UUID --birthday 1992-03-04 --birthday-reminder on
scripts/keepclose update PERSON_UUID --birthday none
scripts/keepclose merge SOURCE_UUID --into DEST_UUID
scripts/keepclose merge SOURCE_UUID --into DEST_UUID --birthday source --yes
```

New optional fields decode without an eager storage rewrite. Existing app data, contact history,
intentions and AI imports remain compatible. Use matching current app and CLI builds; older writers
cannot preserve fields they do not understand.

## Validation

The core suite covers leap days, year rollover, DST, gift defaults, separate controls, boundaries,
notification privacy, identity ambiguity, following changes, permanent overrides, missing contacts,
repeat imports, device-scoped links, stale previews, merge history/response resolution, backup/Undo,
UUID aliases and legacy/new Codable round trips. The CLI suite exercises valid/invalid/cleared
birthdays, merge preview/application and backup, alongside its existing imports and concurrent writes.

macOS and iOS Simulator compilation pass. Native Mac review uses fictional temporary Contacts
snapshots and confirms selection, existing-person matching, imported birthdays on Today, duplicate
merge and Undo, and invalid-date Save prevention. Real OS permission/notification delivery, iOS
limited-access interaction and full mobile Dynamic Type/VoiceOver need a signed device build; this
host has no available iOS simulator runtime. Real personal Contacts are never accessed in previews. Notification permission/scheduling and device
sync are disabled in fictional previews.

Final validation: 101 XCTest model/storage tests plus five sync tests passed against the published
shared library, as did the isolated CLI suite with 30 concurrent writers and both platform builds.
Built app metadata contains the Contacts permission description on both platforms. The final native
walkthrough passed after unlocking the Mac: searchable matching in the large fictional collection,
linking and repeat import without duplicates, birthday-only Today presentation, birthday navigation
and localized editing, and duplicate selection, merge review, merge and Undo. Earlier invalid-date
Save prevention also passed. All walkthrough data remained in the isolated fictional preview.
