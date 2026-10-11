# Keep Close

Remember your people, and find one small next step to stay in touch. A native SwiftUI app for Mac, iPhone and iPad, with a CLI your agents can use.

![Keep Close on Mac, showing suggested next steps with fictional demo relationships](docs/screenshot.png)

- Keep overlapping relationship labels, shared contexts and notes without reducing someone to a score.
- Choose whether to grow, maintain, give space, or think more about each relationship.
- Get a few explained suggestions: reply, say hello, make time together, or take the initiative.
- Import people from ChatGPT or Claude, then send your corrections back and bring in new context.
- Optional Face ID/Touch ID/device authentication and private reminder previews.

**Status:** early version. Data stays local to each device; **iPhone and Mac do not sync yet**. The screenshot uses fictional data.

## Install on Mac

Requires macOS 14 or later. Release downloads support Apple Silicon and Intel.

1. Open [GitHub Releases](https://github.com/slaymish/KeepClose/releases/latest).
2. Download `KeepClose-macOS.zip`, unzip it, and move **Keep Close.app** to **Applications**.
3. Open Keep Close. Add a person, or choose **Import from ChatGPT** and copy the prompt into your chat. Review the returned JSON before applying it.
4. Set a reminder time in **Preferences**. For private named previews, set macOS Notifications → Keep Close → Show previews → **When Unlocked**.

Published Mac releases are Developer ID signed and notarized. Sparkle checks for signed updates, offers automatic updates through its standard settings, and provides **Keep Close → Check for Updates…**. If there is no release yet, build from source below; binary publication requires the maintainer's Apple distribution credentials.

### Install the agent CLI

Download `keepclose-macOS.zip` from the same release, unzip it, then run:

```sh
mkdir -p "$HOME/.local/bin"
install -m 755 /path/to/downloaded/keepclose "$HOME/.local/bin/keepclose"
"$HOME/.local/bin/keepclose" help
```

Add `$HOME/.local/bin` to your shell's `PATH`, or give your agent the full executable path. The CLI reads the same Mac data as the app. It supports listing, creating/editing people, logging contact, suggestions, reminders and imports. No MCP server or account connection is required. CLI releases are signed/notarized; updating the Mac app does not replace a separately installed CLI.

## Build from source / install on iPhone

Install Xcode with Swift 6 support. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you want to regenerate the project (`brew install xcodegen`). Then:

```sh
git clone https://github.com/slaymish/KeepClose.git
cd KeepClose
open SocialManager.xcodeproj
```

Choose the **SocialManager** scheme and **My Mac**, an iPhone simulator, or your connected iPhone. Choose your Apple development team in **Signing & Capabilities**, then Run. iPhone/iPad updates currently come through Xcode; no App Store/TestFlight release pipeline is configured.

For the Mac, `scripts/run-mac.sh` builds, signs all nested components with an existing valid Apple Development identity, builds the CLI and launches the app. Set `KEEPCLOSE_SIGNING_IDENTITY` to choose an identity. The script does not create Apple certificates. Unsigned builds check compilation but don't reliably validate notifications.

For agents working from source, use `scripts/keepclose help`; it builds the CLI incrementally. `project.yml` owns the Xcode configuration. Sparkle 2.10.0 is pinned and linked only on macOS; the core/CLI Swift package has no external dependencies. Debug builds do not run the updater.

## Relationships and suggestions

Setup uses selectable categories rather than a single relationship column:

- Multiple relationship labels: Friend, Family, Colleague, Partner, Acquaintance, or your own.
- Multiple shared contexts: Work, Flatmate, Online, Hobby, Nearby, Another city, or your own.
- An intention: Grow, Maintain, Give more space, or Unsure.
- Notes to preserve the nuance, preferred contact method, and an optional custom rhythm.

People is grouped by intention and can be filtered by a relationship or shared context. Today offers up to three explained next actions; the CLI returns every ready suggestion. Reply suggestions come first.

Contact logs distinguish **I reached out**, **They reached out**, **We caught up**, **I replied**, and **Everyday contact**. Catch-ups optionally record who initiated. Incoming messages create a reply suggestion; a reply or catch-up closes earlier incoming messages. An incoming item can also be marked "No reply needed" without pretending a conversation happened. Backdated incoming logs are matched against already-recorded later replies/catch-ups.

Rules are deliberately inspectable:

- An outstanding incoming message suggests replying, even if your intention is to give more space.
- A sent message, reply, or meaningful catch-up starts a new rhythm. Everyday contact in passing does not.
- Three recent recorded contacts initiated by them can suggest taking the initiative once your rhythm is ready. An incoming message followed by its catch-up counts as one initiation.
- Two outreach attempts without a later logged response or conversation suggest giving them room. This is an inference from your logs, not evidence that they ignored you.
- Grow suggests making time together; Maintain suggests a small hello; Unsure suggests choosing a direction. Give more space suppresses proactive outreach suggestions. Pause suppresses all suggestions.
- Postponement delays suggestions. Repeated postponement offers a smaller step and a rhythm change.

Editable starting rhythms are 14 days, 7 for a Partner label, or 30 for an Acquaintance label. Work/Flatmate/Nearby contexts allow at least 21 days between intentional check-ins. Grow halves this starting rhythm (minimum 3 days). Give more space retains a 45-day or longer rhythm but does not create proactive reminders. These are product defaults, not measures of relationship health. Custom rhythms take precedence and are never automatically adjusted.

The app opens your configured contact app; you send the message yourself. Opening it never logs contact. Suggestions use manually logged history; no message or contact-account access is involved.

An optional daily local notification at an adjustable time (6 pm by default) invites you to check in, even if nobody is due. Names are optional and only scheduled when the OS uses When Unlocked previews; see privacy details below. There is no numerical relationship score or streak.

## Limits and next decisions

On Mac, app and CLI share `~/Library/Application Support/KeepClose`. The local Mac build is not sandboxed, allowing agents to access the same data; iOS retains its app sandbox. Files are saved atomically with a shared lock. The app refreshes external changes every two seconds and rejects stale editor saves. Each device keeps a separate local copy. **There is no cross-device sync yet.** Do not enter the same information on both devices expecting it to merge.

This prototype reduces the effort of choosing and starting. It cannot guarantee follow-through. It deliberately avoids overdue scores, streaks and increasing alerts. Trying it with a few real relationships should show whether repeated postponement needs a more explicit barrier check (too busy, unsure what to say, difficult relationship) or a scheduled five-minute connection session.

Possible next work: iCloud sync, contact import with permission, widgets, a scheduled connection session, data export and undo for contact logs. The current version supports manual data entry, agent JSON imports/updates and manual contact logging. Contact history and person deletion have no undo yet; deletion asks for confirmation.

## Agent CLI

Use `scripts/keepclose help` for the full command reference. All command results are JSON; errors go to stderr with a nonzero exit status. No MCP setup is required.

```
scripts/keepclose list
scripts/keepclose due
scripts/keepclose add --name 'Alex' --days 14 --method message
scripts/keepclose update PERSON_UUID --types 'Friend,Colleague' --contexts 'Work,Online' --intention grow
scripts/keepclose update PERSON_UUID --notes 'Ask about their new job'
scripts/keepclose suggestions
scripts/keepclose suggest PERSON_UUID
scripts/keepclose log PERSON_UUID --kind incoming --note 'They sent a hello'
scripts/keepclose log PERSON_UUID --kind reply --note 'Replied'
scripts/keepclose snooze PERSON_UUID --days 3
scripts/keepclose pause PERSON_UUID
scripts/keepclose resume PERSON_UUID
scripts/keepclose reminders on --time 18:00 --launch
scripts/keepclose reminders
```

Also supports `show`, `resolve ID --entry ENTRY_UUID`, `open`, `delete ID --yes`, `reminders off` and `path`. `open` never sends or logs contact. CLI writes reload the latest data under a lock and change only the requested fields. Use `--data-dir PATH` for an isolated dataset. Mac CLI access does not give agents access to iPhone data.

Reminders run through the app, which owns the OS notification permission. The CLI stores the requested schedule; `reminders` reports both the request and the last actual status reported by the app. The app must run at least once to apply changes. Once the OS has scheduled a reminder, the app need not stay open for delivery. Scheduling status does not guarantee a banner is displayed: system settings and Focus can affect presentation.

## Development checks

Run `swift test` for the scheduling, suggestion rules, legacy migration, transaction, data preservation and reminder settings tests. Run `python3 scripts/test-cli.py` for CLI lifecycle checks and 30 concurrent process writes against a temporary dataset. Application builds are checked with:

```
xcodebuild -project SocialManager.xcodeproj -scheme SocialManager -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SocialManager.xcodeproj -scheme SocialManager -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

On upgrade, original labels become relationship categories, original notes remain notes, and existing rhythms remain custom. Legacy history is preserved and excluded from inferences about unanswered messages because the first version did not track incoming replies. A private backup of existing relationship data was saved before this upgrade.

## Import from ChatGPT or Claude

The toolbar's **Import from ChatGPT** menu offers ChatGPT and Claude. Choose a provider to open the import screen and copy a prompt. Paste it into a chat with that agent. The app does not connect to either account or launch chats automatically.

The prompt asks for real people identified from memories and conversation context the agent can actually access, with multiple relationship labels, shared contexts and useful notes. Unknown intentions are left unset; new records start as Unsure. No contact history or dates are fabricated.

- Local agents with terminal access get the CLI path in the prompt. They can preview and apply a batch directly. The running Mac app refreshes after import.
- Chats without local terminal access return a `keepclose-import.json` file or JSON code block. Choose the file or paste the JSON in the app, inspect the preview, select the people to include, and import.
- On iPhone, the prompt uses the file/paste route. Imported data is still local to that device; cross-device sync is not implemented.

CLI commands:

```
scripts/keepclose import-prompt --source chatgpt
scripts/keepclose import-prompt --source claude
scripts/keepclose import /private/path/keepclose-import.json --dry-run
scripts/keepclose import /private/path/keepclose-import.json --apply
```

Import defaults to preview, with JSON output. `--apply` validates the whole batch, locks/reloads the latest data, saves a private backup of existing storage and writes atomically. The app rejects an outdated preview and lets you refresh it. Validation errors never partially import a batch.

Minimal file format:

```json
{
  "version": 1,
  "source": "chatgpt",
  "people": [
    {
      "name": "Example person",
      "types": ["Friend", "Colleague"],
      "contexts": ["Work"],
      "notes": "Useful relationship context."
    }
  ]
}
```

Optional person fields: `id` (an existing UUID), `intention`, `method`, `address`, `rhythmDays`. Intention uses grow/maintain/space/unsure; method uses message/call/email/in-person. No other fields are accepted. JSON code fences are supported for pasted replies. Limits: 2 MB, 1,000 people per batch, 20,000 characters of notes per person.

Duplicates match by existing UUID when supplied, otherwise by normalized name (case, whitespace and accents). Multiple matching people require an explicit UUID; multiple import records targeting one person are rejected. Matching does not guess nicknames or identities. Merges add categories and new notes, fill empty contact details, and retain existing intentions, rhythms, contact history, pause/snooze settings and populated contact details. Repeated identical imports become no-ops. Import origin is recorded on each person; existing notes receive a provider label when new imported notes are appended.

## App lock and notification privacy

Preferences now includes **Require authentication to open Keep Close**. Enabling or disabling it requires successful Apple device-owner authentication. Unlock uses Face ID or Touch ID where supported, with the device passcode or Mac login password as the system fallback. No separate app password is collected or stored. The lock preference is saved atomically in the device's local app settings; unreadable settings fail closed. Lock is off until you enable it and is configured separately on each device.

When enabled, the app starts locked, hides its UI when inactive, and re-locks on leaving/backgrounding, device data protection, Mac sleep or session changes. Authentication completed after a lock/background event is discarded. **Lock now** is also available. Locking closes unsaved editors and import previews. The app lock protects the UI; it does not encrypt or revoke local agent access to the shared JSON files or backups. The CLI remains available to your agents.

For reminders, the title is always generic. The category's hidden preview says **“Someone is ready for a little connection.”** Names appear only in the notification body, and the app only includes them when the OS reports **Show Previews → When Unlocked**. Set that option explicitly for Keep Close in system Notifications settings. If previews are Always, Never, unknown, or the in-app names toggle is off, reminders are scheduled with generic wording instead. The app cannot change the OS preview preference itself; the preferences screen includes a shortcut and reports the detected setting.

The OS controls rendering of already-scheduled notifications. Keep **When Unlocked** selected while named notifications are pending. If you change that OS setting while the app is closed, it cannot rewrite pending notifications until it runs again. Turning names off in the app reschedules the reminder generically and clears the previous delivered reminder. Privacy settings are rechecked when the app becomes active and periodically while running. Reminder names are a snapshot of up to three suggested people for the next scheduled check-in, refreshed when the app sees relationship changes.

CLI notification preference:

```
scripts/keepclose reminders on --names when-unlocked
scripts/keepclose reminders on --names never
```

See Apple's [device authentication policy](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthentication), [notification preview setting](https://developer.apple.com/documentation/usernotifications/unnotificationsettings/showpreviewssetting) and [hidden preview placeholder](https://developer.apple.com/documentation/usernotifications/unnotificationcategory/hiddenpreviewsbodyplaceholder).


## Updating from ChatGPT or Claude

After an import, that provider's menu item becomes **Update from ChatGPT/Claude**. The copied prompt includes current people (stable UUIDs, names, categories, preferences, notes and contact history), changes since that provider's last applied batch, previous values for edited records, and deleted records. Only share this prompt with a chat you want to have that information.

The agent is asked to reconcile its accessible memory with your app corrections, then return new people or useful context. A name correction stays attached to the same UUID; imports never overwrite your current name or preferences. If the agent cannot save memory, it must report that and give you corrections to save manually. Copying a prompt does not connect to an account, run an agent or change memory by itself.

Preview and apply the returned JSON as before. An empty `people` array is valid after a memory-only update. Each successfully applied batch establishes a checkpoint for that provider; copying the prompt does not. Checkpoints include app and CLI changes, not just manual edits. Older imports have no historical checkpoint, so the first update shares the current records without claiming to reconstruct past edits. Checkpoints and backups stay outside the repository.

From a local agent:

```sh
scripts/keepclose import-prompt --source chatgpt
scripts/keepclose import /private/path/keepclose-import.json --dry-run
scripts/keepclose import /private/path/keepclose-import.json --apply
```

## Releases

Tags such as `v0.1.0` run tests and publish signed/notarized universal Mac app and CLI downloads plus a signed Sparkle feed. Apple distribution secrets must be configured first. Read [the release guide](docs/RELEASING.md) or ask an agent to use the project's [release skill](.agents/skills/release/SKILL.md). User-facing changes live in [CHANGELOG.md](CHANGELOG.md).
