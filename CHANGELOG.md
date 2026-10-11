# Changelog

## [Unreleased]

## [0.2.0] - 2026-10-12

### A calmer way to connect

- Today is now the landing screen, with up to three grounded opportunities, gentle actions, upcoming plans and a quiet empty state when there is nothing useful to suggest.
- People puts names and shared context first, with search and filters that give Grow and Maintain relationships equal standing. Layouts adapt to long names, larger text and light or dark appearance.
- Suggestions use recorded interests, projects and memories without presenting unverified ideas as shared facts. Limited context no longer produces artificial personalised prompts.
- Sending an invitation is acknowledged separately from having a conversation or making a plan. An unanswered invitation suppresses further proactive suggestions until it is resolved; silence is never treated as failure.
- Optional contact logging is lighter, with correction and Undo. Plans can be recorded, completed or cancelled without turning relationships into tasks.

### Birthdays and your people

- Add birthdays with an optional birth year, birthday-day reminders and a gentle gift thought two weeks ahead. Friends and family receive gift thoughts by default; Give Space and Pause silence birthday reminders too.
- Optionally import all or selected Apple Contacts and link them to existing people. Names, contact details and birthdays can follow Contacts changes while preserving your Keep Close edits; nothing is written back to Contacts.
- Review possible duplicates through a searchable chooser. Merge duplicate people while preserving notes, histories, plans, contact details and links, with a private backup and Undo.
- Existing data and version-1/version-2 agent imports remain compatible. The CLI supports birthdays, merging, invitation resolution and plans.

- App and CLI downloads now use distinct filenames, preventing archive replacement on case-insensitive Mac filesystems. Both packages are checked again before signing the update feed.

### Paired devices

- Optional same-network pairing lets Mac and iPhone exchange relationship data, with conflict review and recovery. Device authentication, permissions and notification settings remain local to each device.

## [0.1.0] - 2026-10-11

### Grounded suggestions instead of day counting

- Recorded context per person: shared interests, memories worth keeping, concrete ways of connecting, and recurring patterns such as a weekly game night. Suggestions are built from these, so a prompt can say "Another board game evening?" rather than "You haven't contacted Ryan in 30 days".
- Every piece of context carries where it came from (you, them, a memory, an agent) and how well it is known (known, a recollection, or an unverified suggestion). Nothing inferred is presented as a fact.
- Today offers grounded opportunities and says plainly when nothing needs doing, with a quiet list of people whose recorded context is available. Give more space and Pause produce no proactive ideas at all, while a reply to an incoming message is still offered.
- Explicit feedback only: useful, I did this, not for me, later. Ignoring a suggestion records nothing. "Not for me" sets an idea aside permanently and later imports cannot revive it. Postponing is no longer counted anywhere, and repeated postponement no longer asks you to make the step smaller.
- Version-2 agent imports carry `context` (memories, interests, ideas, rituals) with `source` and `confidence`. Context is de-duplicated on the words of the text, your own wording always wins, and a dismissed idea stays dismissed. Version 1 imports still work.
- The import prompt now states the grounding rules: no invented shared history, contact details or availability, at most three ideas per person, and no suggestion justified only by elapsed time.
- Import preview lists every new person, merge and idea, and lets individual ideas be left out before applying.
- CLI gains `context`, `idea`, `memory`, `interest`, `ritual`, `useful` and `pass`, so an agent can add, edit, dismiss or remove recorded context without logging contact.

### Foundations

- Native iPhone, iPad and Mac app with multiple relationship labels, shared contexts, an intention (grow, maintain, give more space or unsure) and notes.
- Explained suggestions based on contact history, incoming messages and recorded context, with no scores, streaks or overdue states.
- Contact logging that distinguishes reaching out, hearing from someone, catching up, replying and everyday contact.
- Agent-friendly CLI with atomic writes, import previews and private backups.
- ChatGPT and Claude imports become two-way updates, sharing current records and changes since each provider's previous applied batch.
- Optional device authentication and private notification previews that keep names out of locked notifications.
- Signed Sparkle updates on Mac, with tagged GitHub release automation for notarized universal app and CLI downloads.
