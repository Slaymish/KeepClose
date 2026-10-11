# Connection, with less administration

Today is a direct landing screen on each platform. It has at most three useful opportunities, no
suggestion counters and no categories, raw notes or contact history. Secondary reasoning and provenance
are disclosed on demand. A quiet day stays empty; agreed future plans can still appear under Coming up.

People is alphabetical with search and optional intention/category filters. A single flexible text
column keeps identity first, context second and an optional opportunity third. Grow does not rank people
above Maintain. Native controls, semantic fonts, reduced-motion transitions and adaptive action layouts
serve both platforms. The palette uses a restrained warm accent with system surfaces and borders.

Adding someone requires only a name. An optional activity gives the engine something concrete to offer;
notes remain durable context. Categories, contact details and rhythms sit behind preferences.

## Behaviour and persistence

- Outgoing messages remain `outreach`. One recorded invitation suppresses proactive ideas; no timeout
  turns silence into a new invitation. A later recorded response or an explicit Allow new ideas clears
  that gate. Legacy undirected events do not prove an open invitation.
- Actual conversation/shared time remains `conversation`. Contact events can link to an idea. Only
  actual shared time or an explicit I did this moves that activity's cadence.
- `ConnectionPlan` is separate from contact history. Plans retain stable UUIDs and an optional idea link.
  Marking one as happened creates a shared-time event. Undo/removal restores the active plan; cancellation
  creates no contact. Past plans never escalate.
- Deferral uses `snoozedUntil`; dismissal keeps the stored idea dismissed. Editing does not restore a
  dismissed idea. Explicit Bring back clears that dismissal feedback; imports cannot do so.
- Correcting/removing a new reply re-evaluates automatically resolved incoming items using
  `responseEntryId`. Manual and legacy resolutions remain authoritative. Editing only a note preserves
  resolution. Editors reject stale event/plan/person snapshots.
- Optional reminders schedule one relevant upcoming notification, not a repeating stale snapshot.
  Requested enablement and actual scheduling are distinct. Opening/running the app refreshes the next
  notification. Existing OS preview-policy and app-lock protections remain.

New `plans`, `ideaId` and `responseEntryId` fields decode with empty/nil defaults. No eager migration
rewrites relationship storage. Strict version-1/version-2 agent imports are unchanged and cannot fabricate
history or plans. App and CLI share these behaviours through the core model and locked repository.
Use matching current app/CLI versions: an older writer cannot preserve fields it does not understand.

## Scenarios

A game invitation is recorded as sent and acknowledged immediately, with Undo; no reply is required to
make that action successful. A person with only a Nearby category gets no fabricated activity. A Maintain
friendship can receive the same shared-game opportunity as a Grow friendship. No useful context produces
a quiet Today. Long names and overlapping categories stay in one readable People column with search.

The model deliberately uses explicit recorded ideas rather than inferring shared activities from arbitrary
free-form notes. The agent prompt asks for specific supported invitations, keeps durable interests and
memories separate, forbids pressure/intimacy prompts and treats silence without speculation. Suggested
rationale remains labelled and disclosed rather than asserted as known history. A local conservative
phrase guard filters common pressure prompts, including rituals, while preserving imported text for
review; it is not a general semantic safety classifier.

## Visual preview

Debug-only flags keep all preview data in a temporary repository, separate from personal data:

- `--demo --ux-preview`: fictional opportunities, a game invitation and a long name.
- Add `--demo-large`: over 120 fictional people in a separate preview repository.
- Add `--demo-empty`: empty repository in another separate preview location.
- `--demo-light` / `--demo-dark`: app-only appearance override.
- `--demo-large-type`: accessibility text size for layout review.

Preview storage is seeded once and persists deliberately, so running a test does not reset an existing
preview. These flags exist only in Debug builds. Do not use production data for screenshots or tests.

## Validation performed

- 101 model/storage tests and five sync tests passed. Coverage includes invitation suppression, plans,
  correction/undo, legacy decoding, import preservation, restoration, deferral, intention parity,
  pressure filtering, birthdays, native Contacts matching/following and backed-up person merging.
- The isolated CLI suite passed its lifecycle, v1/v2 imports, invalid-command atomicity and 30
  concurrent process writes; it now also checks plans, linked events, undo and restoration.
- Unsigned macOS and iOS Simulator builds compiled successfully.
- Native macOS review used only fictional temporary data: dark/light Today and People, a long name,
  a 125-person collection with search to its last record, sent-message acknowledgement and Undo,
  adding/setting aside a plan, the minimal add-person sheet and quiet Today after explicit deferral.
- The accessibility text-size preview flag was exercised on macOS; full iOS Dynamic Type, VoiceOver
  and device interaction checks remain necessary. This host has no available iOS simulator runtime.
- Unsigned builds do not verify OS notification permission or actual reminder delivery. Those need
  a signed app on a device. The import review/local phrase guard still depends on honest source text.
