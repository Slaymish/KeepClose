# Changelog

## [Unreleased]

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
