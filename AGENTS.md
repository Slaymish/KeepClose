# Keep Close / SocialManager

Native SwiftUI app for macOS and iOS, plus a Swift CLI for local agent access.

## Agent access

Use `scripts/keepclose help` for command usage.
The wrapper builds the CLI incrementally, writes diagnostics to stderr and returns JSON on stdout.
Use the CLI rather than editing the JSON storage files directly: it locks and reloads before each write.

Typical commands:

```
scripts/keepclose list
scripts/keepclose due
scripts/keepclose show PERSON_UUID
scripts/keepclose update PERSON_UUID --context 'Ask about their move'
scripts/keepclose log PERSON_UUID --note 'Sent a hello'
scripts/keepclose context PERSON_UUID
scripts/keepclose idea PERSON_UUID --add --activity 'a board game evening' --reason 'You both enjoy them'
scripts/keepclose reminders
```

Person IDs are full UUIDs from `list`. Output dates use ISO 8601. Update changes only supplied fields.
Only log contact that actually happened; opening a contact app does not count.
`due` returns all people with a ready suggestion; Today caps these at three. `suggestions` returns
ready people with action and reason; `suggest ID` explains any person's current recommendation.
`context ID` returns one person's recorded context plus the ways of connecting that are ready now.
Use `--types 'Friend,Colleague'`, `--contexts 'Work,Online'`, and `--intention grow|maintain|space|unsure`.
`--notes` (or legacy `--context`) stores personal nuance; `--contexts` is the shared-context category list.
`--days` sets a custom rhythm. `--rhythm auto` restores editable category/intention defaults.
Log contact with `--kind outreach|incoming|conversation|reply|ambient`; conversation accepts
`--initiator me|them|mutual|unknown`. Incoming prompts a reply; reply/catch-up closes earlier incoming.
`resolve ID --entry ENTRY_UUID` means no reply is needed; it does not log contact.
Ambient contact does not reset the meaningful-contact rhythm. Space suppresses proactive suggestions,
while pause suppresses all. Historical logs without directional data do not prove unanswered messages.

Recorded context: `idea ID --add/--edit/--dismiss/--restore/--remove`, `memory ID --add/--edit/--forget`,
`interest ID --add/--edit/--remove`, `ritual ID --add/--remove`. Use `--source me|them|memory|agent|unsure`
and `--confidence known|unsure|suggested` to record where something came from and how well it is known;
`--kind` for ideas is sharedActivity/async/call/ritual/visit/gesture/conversation and `--timing` is
anytime/weekday/evening/weekend/freeTime. `--cadence DAYS` sets how often an idea may return; `none`
clears it. `useful ID` records that a suggestion helped; `pass ID [--idea IDEA_UUID]` sets it aside.

Dismissed ideas stay dismissed: imports never revive them, even reworded. Feedback is explicit only —
never infer anything from a suggestion the user ignored, and never present an agent's idea as a fact.
Imported context defaults to `suggested` confidence unless the import states otherwise.
Reminder commands save the requested schedule. The running app applies it and reports actual status.
`--launch` starts the app; OS notification permission is still required. `reminders` distinguishes
requested settings from app-reported scheduling status. Optional same-network iPhone/Mac sync is available; see docs/NATIVE_LIBRARY.md. OS notification permission remains per device.

## Data and concurrency

Mac data lives in `~/Library/Application Support/KeepClose`, shared by app and CLI.
The local Mac build is not sandboxed so agent tools can access that same directory. iOS uses
its sandbox. Existing prototype data remains in its original location.
Atomic writes and a shared file lock protect concurrent mutations. The app polls every two seconds.
App edits reject stale person records instead of overwriting concurrent CLI updates.
Keep real relationship data out of the repository, tests, fixtures and command logs.
Use `--data-dir /temporary/path` for isolated CLI testing.

## Development

- `swift test`: core model and storage tests.
- `python3 scripts/test-cli.py`: isolated CLI lifecycle and concurrent write checks.
- `swift build --product keepclose`: CLI.
- `xcodegen generate`: regenerate the checked-in Xcode project from `project.yml`.
- `scripts/run-mac.sh`: build, sign using an existing valid Apple Development identity and launch.
  Set `KEEPCLOSE_SIGNING_IDENTITY` to select a specific identity. The script never creates keys.
- Unsigned Xcode builds verify compilation but do not validate notification permission or scheduling.

Preserve the sandbox and hardened-runtime design appropriate to each platform. Do not replace the
user's data on load failure. Preserve unrelated working changes. Sparkle is the macOS-only application dependency; keep it out of the core/CLI package.

## Batch memory import

- `import-prompt --source chatgpt|claude` returns a provider-specific prompt as JSON.
- `import FILE` / `import FILE --dry-run` previews without changing relationship data.
- `import FILE --apply` validates, backs up, merges and saves the whole batch atomically.
- The file format and merge rules are documented in README.md. Version 1 (source chatgpt or claude and a
  people array; fields name, optional id/types/contexts/intention/notes/method/address/rhythmDays) is still
  accepted. Version 2 adds an optional per-person `context` object with `source`, `confidence`, `memories`,
  `interests`, `ideas` and `rituals`. Unknown keys anywhere, contact-history fields and versions above 2 are
  rejected before anything is written. Never mark agent-generated context as `known`.
- Prefer existing UUIDs from `list` when the identity is known. Never guess matches or contact
  history from a passing mention. Unknown intentions should be omitted (new records use Unsure).
- Keep import files containing personal data outside this repository. The native import screen
  previews and selects records; a local agent can use the CLI directly when instructed to import.
- Repeated batches are idempotent for identical categories, notes and context; context matches on kind plus
  the words of the text, ignoring punctuation. Existing preferences, contact history, the user's own wording
  and set-aside ideas are preserved. Backups are private files under
  Application Support/KeepClose/backups; an unchanged batch writes none.

## App lock / privacy

App lock is a per-device UI gate configured in the native preferences. Changes require Apple
LocalAuthentication; don't bypass that gate by modifying app-lock.json. Existing authorized CLI
access to relationship data remains available (the app lock does not encrypt JSON or backups).
`reminders on --names when-unlocked|never` configures named/generic notification bodies.
Never put names in titles, categories, thread IDs, hidden preview placeholders or notification actions.
Named bodies require the OS When Unlocked preview policy; otherwise use generic text. See README
for the OS-managed pending-notification limitation and snapshot behavior.

## Releases

Use the project [release skill](.agents/skills/release/SKILL.md) when asked to tag/publish.
`project.yml` owns version and Sparkle configuration. Never commit signing secrets or real app data.
The macOS-only Sparkle package is pinned; keep its release-tool version aligned with the workflow.
Build both platforms after changing dependencies. See docs/RELEASING.md for credential requirements.

Shared native helpers come from HamishNativeLibrary; see docs/NATIVE_LIBRARY.md. Keep the existing version-1/2
import contract, reference-date storage encoding, `.lock` path and domain merge/checkpoint transaction.
Update shared helpers in the library rather than restoring local copies. Release archive/appcast wrappers
use scripts from the resolved library version. No library upgrade alone updates an installed app.

## Two-way agent updates

`import-prompt` includes all current records and per-provider changes since the last applied batch.
Copying a prompt does not advance its checkpoint. Applying even an empty batch advances it.
Checkpoint files are private, beside relationships.json, never in the repository. For older imports
without a checkpoint, current records are authoritative but historical edits cannot be reconstructed.
Memory updates happen through the receiving agent's available tools; don't claim unavailable access.
Always use existing UUIDs for returned updates, so corrected names remain the same person.
