---
name: release
description: Release Keep Close when asked to publish or tag a new version, updating its changelog and version metadata and monitoring the tagged GitHub Actions release.
---

Work from the repository root. Read [docs/RELEASING.md](../../../docs/RELEASING.md) for signing requirements and workflow details.

Check the working tree and existing tags/releases first. Preserve unrelated changes. A request to release authorizes committing the release's changes, pushing and creating its new tag; merely editing or reviewing this skill does not authorize a release.

Summarize the actual user-facing changes under `CHANGELOG.md` → `[Unreleased]`. Never include personal relationships, preferences, logs, credentials or local machine paths. Choose a semantic version fitting the change (ask if the user's intended version cannot be inferred). Run `python3 scripts/release.py prepare VERSION`; it moves the notes into a dated entry, increments the numeric build and regenerates Xcode.

Run `swift test`, `python3 scripts/test-cli.py`, and unsigned macOS/iOS simulator builds as described in AGENTS.md. Review the release diff. Before tagging, confirm all required GitHub secret *names* exist with `gh secret list --repo slaymish/KeepClose`. The Ed25519 public key must continue matching the private signing key. Never regenerate or rotate it as a routine release step. Missing Apple credentials block binary publication: finish the reviewable metadata/checks and report the specific missing setup; don't publish an unsigned substitute.

Run `python3 scripts/release.py verify VERSION`. Commit only the intended changes, push the commit, then create and push an annotated `vVERSION` tag. The tag must point at the verified commit. Never force or reuse a published tag.

Monitor the Release workflow with `gh run view` or `gh run watch`, inspect failures, and verify the GitHub release contains the app ZIP, CLI ZIP, signed appcast and checksums. Report the release URL and any failure clearly. If a tag fails after pushing, repair forward; don't repeatedly retag or create replacement public releases without resolving the failure. Source tags are not evidence that signing, notarization or publication succeeded.
